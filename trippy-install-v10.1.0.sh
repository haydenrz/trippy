#!/usr/bin/env bash
set -euo pipefail

# Trippy v10.1.0: Immich-style web UI route-tour generator for Proxmox LXC
# Adds stop-based clustering, stop radius, stop review/editing, and lasso grouping.
#
# Run on Proxmox host:
#   bash trippy-install-v10.1.0.sh
#
# Optional:
#   CTID=106 STORAGE=local-lvm BRIDGE=vmbr0 bash trippy-install-v10.1.0.sh

CTID="${CTID:-}"
HOSTNAME="${HOSTNAME:-Trippy}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
BRIDGE="${BRIDGE:-vmbr0}"
DISK_SIZE="${DISK_SIZE:-32}"
MEMORY="${MEMORY:-4096}"
CORES="${CORES:-2}"
PASSWORD="${PASSWORD:-trippy-change-me}"
APP_DIR="/opt/trippy"
PORT="8088"

next_ctid() {
  local id=100
  while pct status "$id" >/dev/null 2>&1; do
    id=$((id+1))
  done
  echo "$id"
}

if [[ -z "${CTID:-}" ]]; then
  CTID="$(next_ctid)"
fi


# ─────────────────────────────────────────────────────────────────────────────
# Trippy installer styling
# ─────────────────────────────────────────────────────────────────────────────
BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[38;5;45m"
BLUE="\033[38;5;39m"
GREEN="\033[38;5;82m"
PINK="\033[38;5;213m"
YELLOW="\033[38;5;226m"
RED="\033[38;5;196m"
RESET="\033[0m"

clear
cat <<'LOGO'
   ______     _                       
  /_  __/____(_)___  ____  __  __    
   / / / ___/ / __ \/ __ \/ / / /    
  / / / /  / / /_/ / /_/ / /_/ /     
 /_/ /_/  /_/ .___/ .___/\__, /      
            /_/   /_/    /____/      

LOGO

printf "${CYAN}${BOLD}Trippy v10.1.0 Clean Installer${RESET}\n"
printf "${DIM}Interactive journey player • present mode • Immich memories • spatial storytelling${RESET}\n\n"

spin() {
  local pid="$1"
  local msg="$2"
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r${CYAN}%s${RESET} %s" "${frames[$i]}" "$msg"
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.12
  done
  wait "$pid"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf "\r${GREEN}✓${RESET} %s\n" "$msg"
  else
    printf "\r${RED}✗${RESET} %s\n" "$msg"
    exit "$rc"
  fi
}

step() {
  printf "\n${BLUE}${BOLD}▶ %s${RESET}\n" "$1"
}

run_bg() {
  local msg="$1"
  shift
  ("$@") &
  spin "$!" "$msg"
}


printf "${YELLOW}${BOLD}Clean install mode:${RESET} CTID ${BOLD}$CTID${RESET} will be deleted/recreated if it already exists.\n"
if ! command -v pct >/dev/null 2>&1; then
  echo "ERROR: Run this on the Proxmox host. pct not found."
  exit 1
fi

step "Choosing container"
if pct status "$CTID" >/dev/null 2>&1; then
  printf "${YELLOW}!${RESET} CTID ${BOLD}$CTID${RESET} exists. Rebuilding selected target.\n"
  pct stop "$CTID" >/dev/null 2>&1 || true
  pct destroy "$CTID" --purge 1 --force 1 >/dev/null 2>&1 || pct destroy "$CTID" --force 1 >/dev/null 2>&1 || true
  sleep 2
fi

step "Finding Debian 12 template"
mkdir -p "/var/lib/vz/template/cache"
TEMPLATE="$(ls /var/lib/vz/template/cache/debian-12-standard_*.tar.zst 2>/dev/null | sort -V | tail -n1 || true)"
if [[ -z "$TEMPLATE" ]]; then
  run_bg "Refreshing Proxmox template index" pveam update
  TEMPLATE_NAME="$(pveam available --section system | awk '/debian-12-standard/ {print $2}' | sort -V | tail -n1)"
  if [[ -z "${TEMPLATE_NAME:-}" ]]; then
    printf "${RED}ERROR:${RESET} Could not find a Debian 12 standard template.\n"
    exit 1
  fi
  run_bg "Downloading $TEMPLATE_NAME" pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME"
  TEMPLATE="/var/lib/vz/template/cache/$TEMPLATE_NAME"
fi

step "Creating fresh LXC $CTID ($HOSTNAME)"
pct create "$CTID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --storage "$STORAGE" \
  --rootfs "${STORAGE}:${DISK_SIZE}" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
  --unprivileged 1 \
  --features nesting=1 \
  --password "$PASSWORD" \
  --start 1 >/dev/null

printf "${GREEN}✓${RESET} Fresh container created\n"

pct set "$CTID" --description "🧭 Trippy v10.1.0
Interactive Immich journey player
Present Mode • Stop grouping • Preview Suite
Required Immich API permissions:
asset.read, asset.view, asset.download, map.read, timeline.read" >/dev/null 2>&1 || true

step "Installing system dependencies"
run_bg "Installing Debian packages and Node.js" pct exec "$CTID" -- bash -lc '
set -e
apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl git ca-certificates gnupg python3 python3-venv python3-pip \
  ffmpeg exiftool nginx unzip jq build-essential >/dev/null
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs >/dev/null
'

step "Writing Trippy app files"
pct exec "$CTID" -- bash -lc "mkdir -p $APP_DIR/{backend,frontend,uploads,exports,work,projects,cache}"

cat >/tmp/trippy_requirements.txt <<'PYREQ'
fastapi==0.115.6
uvicorn[standard]==0.34.0
python-multipart==0.0.20
requests==2.32.3
pydantic==2.10.4
pillow==11.0.0
PYREQ
pct push "$CTID" /tmp/trippy_requirements.txt "$APP_DIR/backend/requirements.txt"

cat >/tmp/trippy_backend.py <<'PYAPP'
import json
import math
import shutil
import subprocess
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional, List

import requests
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

APP_DIR = Path("/opt/trippy")
UPLOADS = APP_DIR / "uploads"
EXPORTS = APP_DIR / "exports"
WORK = APP_DIR / "work"
PROJECTS = APP_DIR / "projects"
FRONTEND = APP_DIR / "frontend"

for p in [UPLOADS, EXPORTS, WORK, PROJECTS]:
    p.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Trippy", version="1.1.0")
app.mount("/exports", StaticFiles(directory=str(EXPORTS)), name="exports")
app.mount("/uploads", StaticFiles(directory=str(UPLOADS)), name="uploads")

@app.get("/api/health")
def health():
    return {
        "ok": True,
        "app": "trippy",
        "version": "1.1.0",
        "projects_dir": str(PROJECTS),
        "exports_dir": str(EXPORTS)
    }

def run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{p.stderr[-2500:]}")
    return p.stdout

def haversine_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2*r*math.atan2(math.sqrt(a), math.sqrt(1-a))

def save_project(project: dict):
    pid = project["id"]
    (PROJECTS / f"{pid}.json").write_text(json.dumps(project, indent=2))

def load_project(pid: str):
    f = PROJECTS / f"{pid}.json"
    if not f.exists():
        raise HTTPException(404, "Project not found")
    return json.loads(f.read_text())

def weighted_center(assets: List[dict]):
    if not assets:
        return None
    # Equal weights for now; future can weight favorites/videos.
    lat = sum(a["lat"] for a in assets) / len(assets)
    lon = sum(a["lon"] for a in assets) / len(assets)
    return lat, lon

def auto_cluster_stops(assets: List[dict], radius_m: float):
    """Simple density-first clustering:
    - Find the unassigned asset with the most neighbors inside radius.
    - That asset's neighbor group becomes a stop.
    - Stop center becomes the average location of the grouped assets.
    This favors locations with many photos close together.
    """
    remaining = {a["asset_id"] for a in assets}
    by_id = {a["asset_id"]: a for a in assets}
    stops = []

    while remaining:
        best_id = None
        best_neighbors = []
        for aid in list(remaining):
            a = by_id[aid]
            neighbors = []
            for bid in remaining:
                b = by_id[bid]
                if haversine_m(a["lat"], a["lon"], b["lat"], b["lon"]) <= radius_m:
                    neighbors.append(bid)
            if len(neighbors) > len(best_neighbors):
                best_id = aid
                best_neighbors = neighbors

        group_assets = [by_id[x] for x in best_neighbors]
        c = weighted_center(group_assets)
        stop = {
            "stop_id": str(uuid.uuid4())[:8],
            "name": f"Stop {len(stops)+1}",
            "lat": c[0],
            "lon": c[1],
            "radius_m": radius_m,
            "asset_ids": best_neighbors,
            "mode": "auto",
            "locked": False
        }
        stops.append(stop)
        remaining -= set(best_neighbors)

    # Order stops by earliest asset time.
    def stop_time(s):
        vals = [by_id[x].get("time") or "" for x in s["asset_ids"] if x in by_id]
        return min(vals) if vals else ""
    stops.sort(key=stop_time)
    for i, s in enumerate(stops, start=1):
        s["name"] = f"Stop {i}"
    return stops

def ensure_stops(project: dict):
    settings = project.setdefault("settings", {})
    radius_m = float(settings.get("stop_radius_m", 200))
    assets = [a for a in project.get("assets", []) if a.get("selected", True)]
    if not project.get("stops"):
        project["stops"] = auto_cluster_stops(assets, radius_m)
    return project

def extract_points_from_files(folder: Path) -> List[dict]:
    files = [str(p) for p in folder.rglob("*") if p.is_file()]
    if not files:
        return []
    out = run(["exiftool", "-json", "-n", "-GPSLatitude", "-GPSLongitude", "-DateTimeOriginal", "-CreateDate", "-MediaCreateDate"] + files)
    data = json.loads(out)
    points = []
    for item in data:
        lat = item.get("GPSLatitude")
        lon = item.get("GPSLongitude")
        if lat is None or lon is None:
            continue
        src = Path(item.get("SourceFile", ""))
        dt = item.get("DateTimeOriginal") or item.get("MediaCreateDate") or item.get("CreateDate") or ""
        points.append({
            "asset_id": str(uuid.uuid4())[:12],
            "lat": float(lat),
            "lon": float(lon),
            "time": dt,
            "name": src.name,
            "thumb": "",
            "selected": True,
            "source": "upload"
        })
    points.sort(key=lambda x: x.get("time") or "")
    return points

def fetch_immich_assets(base_url: str, api_key: str, start_date: str, end_date: str, limit: int = 1000) -> List[dict]:
    url = base_url.rstrip("/") + "/api/search/metadata"
    payload = {
        "takenAfter": start_date,
        "takenBefore": end_date,
        "size": limit,
        "withExif": True
    }
    r = requests.post(url, headers={"x-api-key": api_key, "Content-Type": "application/json"}, json=payload, timeout=90)
    if r.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"Immich API error {r.status_code}: {r.text[:500]}")
    j = r.json()
    items = j.get("assets", {}).get("items") or j.get("items") or []
    assets = []
    for a in items:
        exif = a.get("exifInfo") or {}
        lat = exif.get("latitude")
        lon = exif.get("longitude")
        if lat is None or lon is None:
            continue
        aid = a.get("id")
        assets.append({
            "asset_id": aid,
            "lat": float(lat),
            "lon": float(lon),
            "time": a.get("localDateTime") or a.get("fileCreatedAt") or "",
            "name": a.get("originalFileName", "Immich asset"),
            "thumb": f"/api/immich-thumb?base={base_url.rstrip('/')}&key={api_key}&id={aid}",
            "selected": True,
            "source": "immich"
        })
    assets.sort(key=lambda x: x.get("time") or "")
    return assets

def route_bounds(points):
    lats = [p["lat"] for p in points]
    lons = [p["lon"] for p in points]
    return [min(lons), min(lats), max(lons), max(lats)]

def write_tour_html(job: Path, stops: List[dict], assets: List[dict], settings: dict):
    by_id = {a["asset_id"]: a for a in assets}
    stop_route = [[s["lon"], s["lat"]] for s in stops]
    if len(stop_route) < 2:
        raise HTTPException(400, "Need at least two stops for a route tour. Lower the stop radius or select more assets.")
    b = route_bounds([{"lat": s["lat"], "lon": s["lon"]} for s in stops])
    duration_min = float(settings.get("duration_min", 12))
    mode = settings.get("mode", "earth")
    pace = settings.get("pace", "smooth")
    title = settings.get("title", "Trippy")
    show_slides = bool(settings.get("show_stop_slides", True))

    # Lightweight stop slide data; no private API downloads. Uploaded/Immich thumbs shown if available in browser render.
    stop_payload = []
    for s in stops:
        stop_assets = [by_id[x] for x in s.get("asset_ids", []) if x in by_id]
        stop_payload.append({
            "name": s.get("name", "Stop"),
            "lat": s["lat"],
            "lon": s["lon"],
            "count": len(stop_assets),
            "thumbs": [a.get("thumb") for a in stop_assets[:6] if a.get("thumb")]
        })

    html = f"""<!doctype html>
<html>
<head>
<meta charset="utf-8" />
<title>{title}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link href="https://unpkg.com/maplibre-gl@5.9.0/dist/maplibre-gl.css" rel="stylesheet" />
<script src="https://unpkg.com/maplibre-gl@5.9.0/dist/maplibre-gl.js">
// Trippy v10.1.0 UI behavior upgrades
(function(){{
  function ready(fn){{ if(document.readyState!=='loading') fn(); else document.addEventListener('DOMContentLoaded',fn); }}
  window.TRIPPY_VERSION='v10.1.0';
  ready(() => {{
    if(!document.querySelector('.versionBadge')){{
      const v=document.createElement('div'); v.className='versionBadge'; v.textContent='v10.1.0'; document.body.appendChild(v);
    }}
    const side=document.querySelector('aside,.sidebar,.left')||document.body.firstElementChild;
    if(side && !document.querySelector('.trippyBrand')){{
      const brand=document.createElement('div');
      brand.className='trippyBrand';
      brand.innerHTML='<div class="trippyLogo"><span class="petal p1"></span><span class="petal p2"></span><span class="petal p3"></span><span class="petal p4"></span><span class="petal p5"></span></div><div class="trippyWord">trippy</div>';
      side.prepend(brand);
    }}
    document.querySelectorAll('button').forEach(b=>{{const t=(b.textContent||'').toLowerCase();if(t.includes('present')||t.includes('preview')){{b.classList.add('presentHero');b.textContent='▶  Present Journey';}}}});
  }});

  const patchStops=()=>{{
    document.querySelectorAll('.stop').forEach((el,idx)=>{{
      if(el.dataset.v101)return;
      el.dataset.v101='1';
      el.classList.add('collapsed');
      const b=el.querySelector('b');
      const small=el.querySelector('.small');
      const summary=document.createElement('div');
      summary.className='stopSummary';
      summary.innerHTML='<div>'+(b?b.outerHTML:'<b>Stop '+(idx+1)+'</b>')+(small?small.outerHTML:'')+'</div><span class="stopChevron">›</span>';
      if(b)b.remove(); if(small)small.remove();
      el.prepend(summary);
      summary.addEventListener('click',(ev)=>{{ev.stopPropagation();document.querySelectorAll('.stop').forEach(x=>{{if(x!==el)x.classList.add('collapsed')}});el.classList.toggle('collapsed');}});
    }});
  }};
  const oldRenderStops=window.renderStops;
  if(typeof oldRenderStops==='function'){{window.renderStops=function(){{oldRenderStops();patchStops();}};}}
  ready(()=>setTimeout(patchStops,1000));

  const oldFocusAsset=window.focusAsset;
  if(typeof oldFocusAsset==='function'){{
    window.focusAsset=function(i){{
      oldFocusAsset(i);
      try{{
        const a=project.assets[i]; if(!a||!map)return;
        if(map.flyTo)map.flyTo({{center:[a.lon,a.lat],zoom:19,pitch:45,bearing:0,duration:850}});
        const popupHtml='<div class="photoPopup">'+(a.thumb?'<img src="'+a.thumb+'">':'')+'<b>'+(a.name||'Photo')+'</b><br><span>'+(a.time||'')+'</span></div>';
        if(window.maplibregl&&maplibregl.Popup)new maplibregl.Popup({{offset:18,closeButton:true}}).setLngLat([a.lon,a.lat]).setHTML(popupHtml).addTo(map);
        else if(window.L&&L.popup)L.popup().setLatLng([a.lat,a.lon]).setContent(popupHtml).openOn(map);
      }}catch(e){{console.warn('popup failed',e);}}
    }};
  }}

  if(!window.openPresentMode){{
    window.openPresentMode=function(){{ if(typeof openPreviewSuite==='function')return openPreviewSuite(); }};
  }}
}})();

</script>
<script src="https://unpkg.com/@turf/turf@7.2.0/turf.min.js"></script>
<style>
html, body, #map {{ margin:0; width:100%; height:100%; background:#05070c; overflow:hidden; }}
.badge {{ position:absolute; z-index:3; left:28px; bottom:24px; color:white; font:700 34px system-ui; text-shadow:0 2px 14px #000; }}
.meta {{ position:absolute; z-index:3; right:28px; bottom:28px; color:white; font:500 20px system-ui; text-shadow:0 2px 12px #000; }}
.stopcard {{ position:absolute; z-index:4; left:50%; top:50%; transform:translate(-50%,-50%); min-width:520px; max-width:760px;
  background:rgba(7,13,22,.88); color:white; border:1px solid rgba(125,211,252,.45); border-radius:24px; padding:26px;
  box-shadow:0 0 50px rgba(0,180,255,.22); font-family:system-ui; opacity:0; transition:opacity .7s; }}
.stopcard.show {{ opacity:1; }}
.stoptitle {{ font-size:38px; font-weight:800; margin-bottom:8px; }}
.stopcount {{ font-size:18px; opacity:.82; margin-bottom:16px; }}
.thumbgrid {{ display:grid; grid-template-columns:repeat(3,1fr); gap:8px; }}
.thumbgrid img {{ width:100%; height:130px; object-fit:cover; border-radius:14px; }}

/* Trippy v10.1.0 UI refresh */
:root{{--bg:#03070d;--panel:#08111c;--panel2:#0d1826;--line:#1d3348;--cyan:#00d9ff;--cyan2:#18f0ff;--blue:#247cff;--green:#27d97f;--orange:#ff7a1a;--pink:#ff4da6;--text:#eef7ff;--muted:#8fa6b8}}
body{{background:radial-gradient(circle at 14% 8%,rgba(0,217,255,.16),transparent 28%),radial-gradient(circle at 78% 18%,rgba(36,124,255,.10),transparent 30%),linear-gradient(145deg,#03070d,#07101a 55%,#02040a)!important;color:var(--text)}}
aside,.sidebar,.left,.panel,#projects,.right,.settings,.card{{background:rgba(8,17,28,.88)!important;border-color:rgba(75,126,164,.28)!important;box-shadow:0 16px 60px rgba(0,0,0,.35);backdrop-filter:blur(14px)}}
button{{border-radius:14px!important;border:1px solid rgba(68,131,176,.45)!important;background:linear-gradient(180deg,rgba(20,44,69,.95),rgba(11,27,45,.95))!important;color:#ecfbff!important;font-weight:800}}
button:hover{{border-color:var(--cyan)!important;box-shadow:0 0 22px rgba(0,217,255,.25)}}
button.primary,button[onclick*="createImmich"],button[onclick*="openPreviewSuite"],button[onclick*="render"],.presentHero{{background:linear-gradient(135deg,#0726a8,#00a3c7)!important;border-color:rgba(0,217,255,.8)!important;box-shadow:0 0 26px rgba(0,217,255,.28)}}
input,select,textarea{{background:#07101a!important;color:var(--text)!important;border:1px solid rgba(89,139,174,.36)!important;border-radius:14px!important}}
#map,.mapwrap{{border-radius:22px!important;overflow:hidden;box-shadow:inset 0 0 0 1px rgba(0,217,255,.18),0 20px 80px rgba(0,0,0,.32)}}
.versionBadge{{position:fixed;left:18px;top:14px;z-index:50;color:var(--cyan2);font-weight:900;font-size:15px;letter-spacing:.4px;text-shadow:0 0 12px rgba(0,217,255,.6)}}
.trippyBrand{{display:flex;align-items:center;gap:12px;margin:24px 12px 22px}}
.trippyLogo{{width:62px;height:62px;position:relative;filter:drop-shadow(0 0 12px rgba(0,217,255,.25))}}
.trippyLogo .petal{{position:absolute;left:23px;top:3px;width:28px;height:44px;border-radius:24px 24px 10px 10px;transform-origin:8px 28px;mix-blend-mode:screen}}
.trippyLogo .p1{{background:#ff2727;transform:rotate(0deg) skewX(-16deg)}}
.trippyLogo .p2{{background:#ffb300;transform:rotate(72deg) skewX(17deg)}}
.trippyLogo .p3{{background:#18c957;transform:rotate(144deg) skewX(-13deg)}}
.trippyLogo .p4{{background:#2385ff;transform:rotate(216deg) skewX(15deg)}}
.trippyLogo .p5{{background:#e66ab5;transform:rotate(288deg) skewX(-18deg)}}
.trippyLogo:after{{content:"";position:absolute;inset:18px;border:2px solid rgba(0,217,255,.8);border-radius:50%;box-shadow:0 0 10px rgba(0,217,255,.7)}}
.trippyWord{{font-size:38px;font-weight:950;font-style:italic;line-height:1;color:white;letter-spacing:-1px;text-shadow:2px 0 #00d9ff,-2px 0 #ff4da6,0 4px 18px rgba(0,0,0,.9)}}
.topbar,.header,.toolbar{{background:rgba(5,12,20,.78)!important;backdrop-filter:blur(16px);border-bottom:1px solid rgba(0,217,255,.18)!important}}
.stop.collapsed .row{{display:none!important}}
.stop{{border-radius:16px!important;transition:.18s ease}}
.stop:hover,.stop.active{{border-color:var(--cyan)!important;box-shadow:0 0 22px rgba(0,217,255,.18)}}
.stopSummary{{cursor:pointer;display:flex;align-items:center;justify-content:space-between;gap:8px}}
.stopChevron{{color:var(--muted);font-weight:900}}
.tile{{border-radius:16px!important;overflow:hidden}}
.tile.focused,.tile:hover{{transform:translateY(-2px) scale(1.02);box-shadow:0 0 25px rgba(0,217,255,.32)!important}}
.leaflet-popup-content-wrapper,.maplibregl-popup-content{{background:#08111c!important;color:#eef7ff!important;border:1px solid rgba(0,217,255,.45)!important;border-radius:16px!important;box-shadow:0 0 35px rgba(0,217,255,.25)!important}}
.photoPopup img{{width:180px;height:110px;object-fit:cover;border-radius:12px;display:block;margin-bottom:8px}}

</style>
</head>
<body>
<div id="map"></div>
<div class="badge">{title}</div>
<div class="meta">{len(stops)} stops • {duration_min:g} min</div>
<div id="stopcard" class="stopcard"></div>
<script>
const route = {json.dumps(stop_route)};
const stops = {json.dumps(stop_payload)};
const durationMs = {int(duration_min * 60 * 1000)};
const mode = {json.dumps(mode)};
const pace = {json.dumps(pace)};
const showSlides = {str(show_slides).lower()};
const line = turf.lineString(route);
const total = turf.length(line, {{units:'kilometers'}});
const map = new maplibregl.Map({{
  container: 'map',
  style: {{
    version: 8,
    sources: {{
      osm: {{
        type: 'raster',
        tiles: ['https://tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png'],
        tileSize: 256,
        attribution: '© OpenStreetMap contributors'
      }}
    }},
    layers: [{{ id:'osm', type:'raster', source:'osm' }}]
  }},
  center: route[0],
  zoom: 3,
  pitch: mode === 'earth' ? 60 : 35,
  bearing: 0
}});
function easing(t) {{
  if (pace === "fast") return Math.pow(t, .85);
  if (pace === "slow") return t*t*(3-2*t);
  return t < 0.5 ? 2*t*t : 1 - Math.pow(-2*t+2,2)/2;
}}
function showStop(idx) {{
  if (!showSlides) return;
  const s = stops[idx];
  if (!s) return;
  const card = document.getElementById('stopcard');
  card.innerHTML = `<div class="stoptitle">${{s.name}}</div><div class="stopcount">${{s.count}} photos nearby</div>` +
    (s.thumbs.length ? `<div class="thumbgrid">${{s.thumbs.map(t=>`<img src="${{t}}">`).join('')}}</div>` : '');
  card.classList.add('show');
  setTimeout(()=>card.classList.remove('show'), 2600);
}}
map.on('load', () => {{
  map.addSource('route', {{ type:'geojson', data: {{ type:'Feature', geometry: {{ type:'LineString', coordinates: route }} }} }});
  map.addLayer({{ id:'route-line', type:'line', source:'route', paint: {{ 'line-width': 6, 'line-color': '#00d4ff', 'line-opacity': .9 }} }});
  map.addSource('dot', {{ type:'geojson', data: {{type:'Feature', geometry: {{type:'Point', coordinates: route[0]}} }} }});
  map.addLayer({{ id:'dot', type:'circle', source:'dot', paint: {{ 'circle-radius': 10, 'circle-color': '#fff', 'circle-stroke-width': 3, 'circle-stroke-color': '#00d4ff' }} }});
  map.addSource('stops', {{ type:'geojson', data: {{type:'FeatureCollection', features:route.map((c,i)=>({{type:'Feature',properties:{{i}},geometry:{{type:'Point',coordinates:c}}}}))}} }});
  map.addLayer({{ id:'stops-dot', type:'circle', source:'stops', paint: {{ 'circle-radius': 6, 'circle-color': '#00d4ff', 'circle-stroke-width': 2, 'circle-stroke-color': '#fff' }} }});
  map.fitBounds([[{b[0]}, {b[1]}], [{b[2]}, {b[3]}]], {{padding: {{top:90,bottom:90,left:140,right:140}}, duration: 2400}});
  let start;
  let lastStop = -1;
  function frame(ts) {{
    if (!start) start = ts;
    const t = Math.min((ts - start) / durationMs, 1);
    const e = easing(t);
    const along = turf.along(line, total * e, {{units:'kilometers'}});
    const coord = along.geometry.coordinates;
    const ahead = turf.along(line, Math.min(total, total * e + Math.max(total/150, .1)), {{units:'kilometers'}}).geometry.coordinates;
    const bearing = turf.bearing(turf.point(coord), turf.point(ahead));
    map.getSource('dot').setData({{type:'Feature', geometry: {{type:'Point', coordinates: coord}}}});
    map.easeTo({{
      center: coord,
      zoom: mode === 'overview' ? 8 : 11,
      pitch: mode === 'earth' ? 65 : 45,
      bearing: isFinite(bearing) ? bearing : 0,
      duration: 0
    }});
    const nearest = route.map((c,i)=>[i, Math.hypot(c[0]-coord[0], c[1]-coord[1])]).sort((a,b)=>a[1]-b[1])[0][0];
    if (nearest !== lastStop && (t === 0 || route.length < 4 || nearest > lastStop)) {{
      lastStop = nearest;
      showStop(nearest);
    }}
    if (t < 1) requestAnimationFrame(frame);
    else window.TRIPPY_DONE = true;
  }}
  setTimeout(() => requestAnimationFrame(frame), 2500);
}});
</script>
</body>
</html>"""
    (job / "tour.html").write_text(html)

def render_video(job: Path, duration_min: float, audio_path: Optional[Path]):
    frames_dir = job / "frames"
    frames_dir.mkdir(exist_ok=True)
    video_raw = job / "tour_raw.mp4"
    video_final = job / "tour.mp4"
    fps = 24
    frames = max(300, int(duration_min * 60 * fps))
    node_script = job / "capture.js"
    node_script.write_text(f"""
const {{ chromium }} = require('playwright');
(async () => {{
  const browser = await chromium.launch({{headless: true, args:['--no-sandbox', '--disable-dev-shm-usage']}});
  const page = await browser.newPage({{ viewport: {{ width: 1920, height: 1080 }}, deviceScaleFactor: 1 }});
  await page.goto('file://{job}/tour.html', {{waitUntil:'networkidle'}});
  await page.waitForTimeout(3500);
  for (let i=0; i<{frames}; i++) {{
    await page.screenshot({{path:`{frames_dir}/frame_${{String(i).padStart(6,'0')}}.png`}});
    await page.waitForTimeout({int(1000/fps)});
  }}
  await browser.close();
}})();
""")
    run(["node", str(node_script)], cwd=str(job))
    run(["ffmpeg", "-y", "-framerate", str(fps), "-i", str(frames_dir / "frame_%06d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p", str(video_raw)])
    if audio_path and audio_path.exists():
        run(["ffmpeg", "-y", "-i", str(video_raw), "-i", str(audio_path), "-map", "0:v:0", "-map", "1:a:0", "-shortest", "-c:v", "copy", "-c:a", "aac", str(video_final)])
    else:
        shutil.move(str(video_raw), str(video_final))
    return video_final

@app.get("/", response_class=HTMLResponse)
def index():
    return (FRONTEND / "index.html").read_text()

@app.get("/api/projects")
def projects():
    out = []
    for f in sorted(PROJECTS.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True):
        p = json.loads(f.read_text())
        out.append({"id": p["id"], "name": p.get("name", "Untitled"), "created": p.get("created"), "count": len(p.get("assets", [])), "stops": len(p.get("stops", []))})
    return out

@app.post("/api/project/upload")
async def project_upload(files: List[UploadFile] = File(...), name: str = Form("Upload Tour")):
    pid = str(uuid.uuid4())[:8]
    folder = UPLOADS / pid
    folder.mkdir(parents=True, exist_ok=True)
    for f in files:
        dest = folder / Path(f.filename).name
        dest.write_bytes(await f.read())
    assets = extract_points_from_files(folder)
    project = {
        "id": pid,
        "name": name,
        "created": datetime.utcnow().isoformat(),
        "source": "upload",
        "assets": assets,
        "settings": {"title": name, "duration_min": 12, "mode": "earth", "pace": "smooth", "stop_radius_m": 200, "show_stop_slides": True},
        "stops": auto_cluster_stops(assets, 200) if assets else []
    }
    save_project(project)
    return project

class ImmichProjectRequest(BaseModel):
    name: str = "Immich Journey"
    base_url: str
    api_key: str
    start_date: str
    end_date: str

class ImmichConnectionRequest(BaseModel):
    base_url: str
    api_key: str

def test_immich_connection(base_url: str, api_key: str):
    base = base_url.rstrip("/")
    headers = {"x-api-key": api_key, "Content-Type": "application/json"}
    result = {"ok": False, "base_url": base, "required_permissions": ["asset.read", "asset.download", "asset.view"], "search_ok": False, "thumb_ok": False, "message": ""}
    r = requests.post(base + "/api/search/metadata", headers=headers, json={"size": 1, "withExif": True}, timeout=30)
    if r.status_code == 401:
        result["message"] = "Unauthorized. The API key is invalid or revoked."
        return result
    if r.status_code == 403:
        result["message"] = "Forbidden. API key is missing required permissions: asset.read, asset.download, asset.view."
        return result
    if r.status_code >= 400:
        result["message"] = f"Immich search failed: HTTP {r.status_code}: {r.text[:250]}"
        return result
    result["search_ok"] = True
    j = r.json()
    items = j.get("assets", {}).get("items") or j.get("items") or []
    if not items:
        result["ok"] = True
        result["thumb_ok"] = None
        result["message"] = "Connected. Search works; no asset was returned for thumbnail testing."
        return result
    aid = items[0].get("id")
    tr = requests.get(base + f"/api/assets/{aid}/thumbnail?size=preview", headers={"x-api-key": api_key}, timeout=30)
    if tr.status_code == 403:
        result["message"] = "Search works, but thumbnail fetch is forbidden. Add asset.download and asset.view."
        return result
    if tr.status_code == 401:
        result["message"] = "Search works, but thumbnail fetch is unauthorized. Recreate the API key."
        return result
    if tr.status_code >= 400:
        result["message"] = f"Search works, but thumbnail fetch failed: HTTP {tr.status_code}"
        return result
    result["thumb_ok"] = True
    result["ok"] = True
    result["message"] = "Immich connection verified. Required asset permissions appear valid."
    return result

@app.post("/api/immich/test")
def immich_test(req: ImmichConnectionRequest):
    return test_immich_connection(req.base_url, req.api_key)

@app.post("/api/project/immich")
def project_immich(req: ImmichProjectRequest):
    pid = str(uuid.uuid4())[:8]
    assets = fetch_immich_assets(req.base_url, req.api_key, req.start_date, req.end_date)
    for a in assets:
        if a.get("source") == "immich" and a.get("asset_id"):
            a["thumb"] = f"/api/project/{pid}/thumb/{a['asset_id']}"
    project = {
        "id": pid,
        "name": req.name,
        "created": datetime.utcnow().isoformat(),
        "source": "immich",
        "immich": req.dict(),
        "assets": assets,
        "settings": {"title": req.name, "duration_min": 12, "mode": "earth", "pace": "smooth", "stop_radius_m": 200, "show_stop_slides": True},
        "stops": auto_cluster_stops(assets, 200) if assets else []
    }
    save_project(project)
    return project

@app.get("/api/project/{pid}")
def get_project(pid: str):
    project = ensure_stops(load_project(pid))
    save_project(project)
    return project

@app.delete("/api/project/{pid}")
def delete_project(pid: str):
    project_file = PROJECTS / f"{pid}.json"
    upload_dir = UPLOADS / pid
    export_file = EXPORTS / f"trippy-{pid}.mp4"
    removed = {"project": False, "uploads": False, "export": False}
    if project_file.exists():
        project_file.unlink()
        removed["project"] = True
    if upload_dir.exists():
        shutil.rmtree(upload_dir, ignore_errors=True)
        removed["uploads"] = True
    if export_file.exists():
        export_file.unlink()
        removed["export"] = True
    return {"ok": True, "deleted": removed, "id": pid}

@app.put("/api/project/{pid}")
def update_project(pid: str, project: dict):
    old = load_project(pid)
    project["id"] = pid
    project.setdefault("created", old.get("created"))
    save_project(project)
    return project

class ReclusterRequest(BaseModel):
    radius_m: float

@app.post("/api/project/{pid}/recluster")
def recluster(pid: str, req: ReclusterRequest):
    project = load_project(pid)
    project.setdefault("settings", {})["stop_radius_m"] = req.radius_m
    assets = [a for a in project.get("assets", []) if a.get("selected", True)]
    project["stops"] = auto_cluster_stops(assets, req.radius_m)
    save_project(project)
    return project

@app.get("/api/immich-thumb")
def immich_thumb(base: str, key: str, id: str):
    url = base.rstrip("/") + f"/api/assets/{id}/thumbnail?size=preview"
    r = requests.get(url, headers={"x-api-key": key}, timeout=30)
    if r.status_code >= 400:
        raise HTTPException(r.status_code, "Thumbnail unavailable")
    tmp = WORK / f"thumb-{id}.jpg"
    tmp.write_bytes(r.content)
    return FileResponse(tmp, media_type="image/jpeg")

@app.get("/api/project/{pid}/thumb/{asset_id}")
def project_thumb(pid: str, asset_id: str):
    project = load_project(pid)
    immich = project.get("immich") or {}
    base = immich.get("base_url")
    key = immich.get("api_key")
    if not base or not key:
        raise HTTPException(404, "No Immich credentials saved for this project")
    url = base.rstrip("/") + f"/api/assets/{asset_id}/thumbnail?size=preview"
    r = requests.get(url, headers={"x-api-key": key}, timeout=30)
    if r.status_code >= 400:
        raise HTTPException(r.status_code, "Thumbnail unavailable")
    tmp = WORK / f"thumb-{pid}-{asset_id}.jpg"
    tmp.write_bytes(r.content)
    return FileResponse(tmp, media_type="image/jpeg")

@app.post("/api/project/{pid}/render")
async def render_project(pid: str, audio: Optional[UploadFile] = File(None)):
    project = ensure_stops(load_project(pid))
    assets = [a for a in project.get("assets", []) if a.get("selected", True)]
    selected_ids = {a["asset_id"] for a in assets}
    stops = [s for s in project.get("stops", []) if any(x in selected_ids for x in s.get("asset_ids", []))]
    stops.sort(key=lambda s: min([next((a.get("time") or "" for a in assets if a["asset_id"] == x), "") for x in s.get("asset_ids", [])] or [""]))
    if project.get("settings", {}).get("reverse_route"):
        stops = list(reversed(stops))
    if len(stops) < 2:
        raise HTTPException(400, "Need at least two stops before rendering. Lower the stop radius, select more assets, or split the current stop.")
    job = WORK / f"render-{pid}-{str(uuid.uuid4())[:6]}"
    job.mkdir(parents=True)
    audio_path = None
    if audio and audio.filename:
        audio_path = job / ("audio_" + Path(audio.filename).name)
        audio_path.write_bytes(await audio.read())
    settings = project.get("settings", {})
    write_tour_html(job, stops, assets, settings)
    video = render_video(job, float(settings.get("duration_min", 12)), audio_path)
    out = EXPORTS / f"trippy-{pid}.mp4"
    shutil.copy(video, out)
    project["last_export"] = f"/exports/{out.name}"
    save_project(project)
    return {"download": project["last_export"], "points": len(assets), "stops": len(stops)}
PYAPP
pct push "$CTID" /tmp/trippy_backend.py "$APP_DIR/backend/main.py"

cat >/tmp/trippy_index.html <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Trippy — Present Your Journey</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <link href="https://unpkg.com/maplibre-gl@5.9.0/dist/maplibre-gl.css" rel="stylesheet" />
  <script src="https://unpkg.com/maplibre-gl@5.9.0/dist/maplibre-gl.js"></script>
  <style>
    :root{--bg:#0b0f14;--panel:#111820;--panel2:#151d27;--line:#263242;--text:#eef6ff;--muted:#9fb0c3;--accent:#00c8ff;--bad:#ff6b6b;--good:#72f1b8}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,system-ui,-apple-system,Segoe UI,sans-serif}
    .app{display:grid;grid-template-columns:285px 1fr 390px;height:100vh}
    aside,.right{background:var(--panel);border-color:var(--line);overflow:auto}
    aside{border-right:1px solid var(--line);padding:18px}
    .right{border-left:1px solid var(--line);padding:18px}
    main{display:grid;grid-template-rows:64px 1fr 270px;min-width:0}
    header{display:flex;align-items:center;gap:12px;padding:0 18px;border-bottom:1px solid var(--line);background:#0e141c}
    h1{font-size:26px;margin:0 0 18px}
    h2{font-size:15px;margin:22px 0 10px;color:#dceeff}
    button,input,select{width:100%;padding:11px;border:1px solid #314052;border-radius:12px;background:#0b1119;color:var(--text);margin:6px 0}
    button{cursor:pointer;background:#15283a;font-weight:700}
    button.primary{background:#006a8c;border-color:#0394c4}
    button.danger{background:#46202a;border-color:#73404d}
    button:hover{filter:brightness(1.12)}
    .small{font-size:12px;color:var(--muted)}
    .projects div{padding:10px;border:1px solid var(--line);border-radius:12px;margin:8px 0;background:var(--panel2);cursor:pointer}
    .toolbar{display:flex;gap:10px;align-items:center}
    .toolbar button{min-width:88px}
    .mapwrap{position:relative;min-height:0}
    #map{position:absolute;inset:0}
    .mapHint{position:absolute;left:14px;top:14px;z-index:4;background:rgba(0,0,0,.62);padding:10px 12px;border-radius:12px;border:1px solid #35526b;display:none}
    .renderOverlay{display:none;position:absolute;inset:0;z-index:10;align-items:center;justify-content:center;background:radial-gradient(circle at center,rgba(0,200,255,.18),rgba(0,0,0,.72));backdrop-filter:blur(2px)}
    .renderBox{width:min(620px,90%);background:rgba(10,18,28,.92);border:1px solid #3aa7cf;border-radius:24px;padding:24px;box-shadow:0 0 70px rgba(0,200,255,.28)}
    .renderTitle{font-size:28px;font-weight:900;margin-bottom:8px}
    .renderSub{color:var(--muted);margin-bottom:18px}
    .bar{height:14px;background:#08111b;border:1px solid #29455a;border-radius:999px;overflow:hidden}
    .barFill{height:100%;width:12%;background:linear-gradient(90deg,#00c8ff,#72f1b8,#00c8ff);border-radius:999px;animation:loadbar 2.1s infinite ease-in-out}
    @keyframes loadbar{0%{width:8%;margin-left:0}50%{width:72%;margin-left:18%}100%{width:8%;margin-left:92%}}
    .tile.focused{border-color:var(--good);box-shadow:0 0 0 3px rgba(114,241,184,.25)}
    .filterPill{position:absolute;right:14px;top:14px;z-index:4;background:rgba(0,0,0,.66);border:1px solid #31506a;border-radius:999px;padding:8px 12px;color:#dff7ff;display:none}
    .gallery{overflow:auto;padding:14px;display:grid;grid-template-columns:repeat(auto-fill,minmax(118px,1fr));grid-auto-rows:128px;gap:10px;background:#090d12}
    .tile{position:relative;border-radius:14px;overflow:hidden;background:#17202b;border:2px solid transparent;cursor:pointer}
    .tile.selected{border-color:var(--accent);box-shadow:0 0 0 2px #003b50}
    .tile.instop{outline:2px solid var(--good)}
    .tile img,.tile .ph{width:100%;height:100%;object-fit:cover;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#1e2937,#0e7490);font-weight:800}
    .tile .name{position:absolute;left:0;right:0;bottom:0;padding:20px 7px 6px;background:linear-gradient(transparent,rgba(0,0,0,.82));font-size:11px}
    .pill{display:inline-block;border:1px solid var(--line);border-radius:999px;padding:6px 10px;margin:4px;background:#0b1119;color:var(--muted);font-size:12px}
    .row{display:grid;grid-template-columns:1fr 1fr;gap:8px}
    .stop{border:1px solid var(--line);border-radius:14px;background:var(--panel2);padding:10px;margin:8px 0;cursor:pointer}
    .stop.active{border-color:var(--accent);box-shadow:0 0 0 1px #00445c}
    .stop b{display:block;margin-bottom:3px}
    a{color:#7dd3fc}
    .status{white-space:pre-wrap;margin-top:8px;color:#b8c7d8}
    label{display:block;font-size:12px;color:var(--muted);margin-top:6px}
  </style>
</head>
<body>
<div class="app">
  <aside>
    <h1>🧭 Trippy</h1>
    <button class="primary" onclick="newImmich()">New Immich Journey</button>
    <button onclick="document.getElementById('fileInput').click()">Upload Media</button>
    <input id="fileInput" type="file" multiple hidden onchange="uploadFiles(this.files)">
    <h2>Projects</h2>
    <div id="projects" class="projects"></div>
    <p class="small">Workflow: import, select/reselect, cluster into stops, edit/lasso stops, preview route, render, reopen, revise.</p>
  </aside>

  <main>
    <header>
      <strong id="title">No project selected</strong>
      <div class="toolbar">
        <button onclick="selectAll()">Select all</button>
        <button onclick="selectNone()">Select none</button>
        <button onclick="invertSelection()">Invert</button>
        <button onclick="toggleLasso()">Lasso stop</button>
        <button onclick="toggleStopSelect()">Select Stops</button>
        <button onclick="groupSelectedStops()">Group Stop</button>
        <button onclick="reverseRoute()">Reverse Route</button>
        <button onclick="openAccount()">Account</button>
      </div>
    </header>
    <div class="mapwrap">
      <div id="map"></div>
      <div id="mapHint" class="mapHint">Lasso mode: click points on the map, then click “Finish lasso”.</div>
      <div id="filterPill" class="filterPill"></div>
      <div id="renderOverlay" class="renderOverlay">
        <div class="renderBox">
          <div class="renderTitle">Rendering Trippy Tour</div>
          <div id="renderSub" class="renderSub">Building route, stops, frames, and MP4 export…</div>
          <div class="bar"><div class="barFill"></div></div>
          <p class="small">This can take a few minutes. Do not refresh.</p>
        </div>
      </div>
    </div>
    <div id="gallery" class="gallery"></div>
  </main>

  <div class="right">
    <h2>Tour settings</h2>
    <label>Title</label>
    <input id="tourTitle" placeholder="Title">
    <div class="row">
      <div><label>Minutes</label><input id="duration" value="12" type="number" min="1" max="60"></div>
      <div><label>Mode</label><select id="mode"><option value="earth">Earth-style</option><option value="overview">Overview</option></select></div>
    </div>
    <label>Pace</label>
    <select id="pace"><option value="smooth">Smooth pace</option><option value="slow">Slow cinematic</option><option value="fast">Fast travel</option></select>
    <label><input id="showStopSlides" type="checkbox" checked style="width:auto"> Show stop slideshow cards during route</label>
    <label><input id="reverseRouteBox" type="checkbox" style="width:auto"> Reverse route direction</label>

    <h2>Stops</h2>
    <label>Stop radius, meters</label>
    <input id="stopRadius" value="200" type="number" min="10" max="10000">
    <button onclick="recluster()">Auto-cluster stops</button>
    <button onclick="moveStopToMapCenter()">Move selected stop to map center</button>
    <button onclick="centerStopFromPhotos()">Recenter selected stop from its photos</button>
    <div class="row">
      <button onclick="finishLasso()">Finish lasso</button>
      <button class="danger" onclick="clearLasso()">Clear lasso</button>
    </div>
    <div id="stops"></div>

    <button onclick="save()">Save edits</button>
    <button class="danger" onclick="deleteCurrentProject()">Delete current project</button>

    <h2>Audio</h2>
    <input id="audio" type="file" accept="audio/*">
    <p class="small">Optional. Leave blank for silent export.</p>

    <h2>Render</h2>
    <button class="primary" onclick="render()">Render MP4</button>
    <div id="stats" class="status"></div>

    <h2>Immich import</h2>
    <input id="immichUrl" placeholder="http://192.168.68.153:2283">
    <input id="immichKey" placeholder="API key" type="password">
    <div class="row">
      <button onclick="saveImmichConnection()">Save API key</button>
      <button onclick="testImportConnection()">Test key</button>
    </div>
    <button onclick="clearImmichConnection()">Clear saved</button>
    <p class="small">Saved locally in this browser. Anyone using this browser profile can reuse it.</p>
    <label>Start date</label>
    <input id="immichStart" type="date">
    <label>End date</label>
    <input id="immichEnd" type="date">
    <div class="row">
      <button onclick="setDatePreset(7)">Last 7 days</button>
      <button onclick="setDatePreset(30)">Last 30 days</button>
    </div>
    <button onclick="setToday()">Today</button>
    <button onclick="createImmich()">Import date range</button>
  </div>
</div>

<div id="setupModal" style="display:none;position:fixed;inset:0;z-index:20;background:rgba(0,0,0,.72);align-items:center;justify-content:center;padding:22px">
  <div style="width:min(720px,96vw);background:#111820;border:1px solid #31506a;border-radius:22px;padding:24px;box-shadow:0 0 60px rgba(0,200,255,.18)">
    <h1>Connect Immich</h1>
    <p class="small">Insert your Immich API key so Trippy can read GPS metadata. In Immich, go to Account Settings → API Keys, create a key for Trippy, and include <b>asset.read</b>, <b>asset.download</b>, and <b>asset.view</b>.</p>
    <label>Immich URL</label>
    <input id="setupImmichUrl" placeholder="http://192.168.68.153:2283">
    <label>Immich API key</label>
    <input id="setupImmichKey" type="password" placeholder="Paste API key">
    <div class="row">
      <button class="primary" onclick="saveSetupConnection()">Save and continue</button>
      <button onclick="testSetupConnection()">Test connection</button>
    </div>
    <button onclick="skipSetup()">Skip for now</button>
    <p class="small">Saved locally in this browser. You can change it later under Account.</p>
  </div>
</div>

<div id="accountModal" style="display:none;position:fixed;inset:0;z-index:21;background:rgba(0,0,0,.72);align-items:center;justify-content:center;padding:22px">
  <div style="width:min(720px,96vw);background:#111820;border:1px solid #31506a;border-radius:22px;padding:24px;box-shadow:0 0 60px rgba(0,200,255,.18)">
    <h1>Account</h1>
    <h2>Immich connection</h2>
    <p class="small">Update the API key here any time. Required permissions: <b>asset.read</b>, <b>asset.download</b>, and <b>asset.view</b>.</p>
    <label>Immich URL</label>
    <input id="accountImmichUrl" placeholder="http://192.168.68.153:2283">
    <label>Immich API key</label>
    <input id="accountImmichKey" type="password" placeholder="Paste API key">
    <div class="row">
      <button class="primary" onclick="saveAccountConnection()">Save</button>
      <button onclick="testAccountConnection()">Test</button>
    </div>
    <button class="danger" onclick="clearAccountConnection()">Clear</button>
    <button onclick="closeAccount()">Close</button>
  </div>
</div>

<script>
let project=null, map=null, routeLayer=false, activeStop=null, galleryFilterStop=null, focusedAsset=null, stopSelectMode=false, selectedStops=new Set();
let lassoMode=false, lassoCoords=[];

function initMap(){
  map = new maplibregl.Map({
    container:'map',
    style:{version:8,sources:{osm:{type:'raster',tiles:['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],tileSize:256,attribution:'© OpenStreetMap'}},layers:[{id:'osm',type:'raster',source:'osm'}]},
    center:[-98,39], zoom:3, pitch:45
  });
  map.on('click', e => {
    if(!lassoMode) return;
    lassoCoords.push([e.lngLat.lng, e.lngLat.lat]);
    drawLasso();
  });
}
initMap();

async function loadProjects(){
  const r=await fetch('/api/projects'); const list=await r.json();
  projects.innerHTML=list.map(p=>`<div onclick="openProject('${p.id}')"><b>${p.name}</b><br><span class="small">${p.count} GPS assets • ${p.stops||0} stops</span><button class="danger" onclick="event.stopPropagation(); deleteProjectById('${p.id}')">Delete</button></div>`).join('');
}
async function openProject(id){
  project=await (await fetch('/api/project/'+id)).json();
  activeStop=project.stops?.[0]?.stop_id || null;
  hydrate();
}
function hydrate(){
  title.innerText=project.name;
  tourTitle.value=project.settings.title||project.name;
  duration.value=project.settings.duration_min||12;
  mode.value=project.settings.mode||'earth';
  pace.value=project.settings.pace||'smooth';
  stopRadius.value=project.settings.stop_radius_m||200;
  showStopSlides.checked=project.settings.show_stop_slides!==false;
  reverseRouteBox.checked=!!project.settings.reverse_route;
  renderGallery();
  renderStops();
  drawRoute();
  updateStats();
}
function stopAssets(stop){
  const ids=new Set(stop.asset_ids||[]);
  return project.assets.filter(a=>ids.has(a.asset_id));
}
function renderGallery(){
  const active = project.stops?.find(s=>s.stop_id===activeStop);
  const activeIds = new Set(active?.asset_ids || []);
  let assets = project.assets.map((a,i)=>({a,i}));
  if(galleryFilterStop){
    const fs=project.stops?.find(s=>s.stop_id===galleryFilterStop);
    const ids=new Set(fs?.asset_ids||[]);
    assets=assets.filter(x=>ids.has(x.a.asset_id));
    filterPill.style.display='block';
    filterPill.innerHTML=`Filtered to ${fs?.name||'stop'} <button onclick="clearGalleryFilter()" style="width:auto;margin:0 0 0 8px;padding:4px 8px">Clear</button>`;
  } else {
    filterPill.style.display='none';
  }
  gallery.innerHTML=assets.map(({a,i})=>`
    <div class="tile ${a.selected?'selected':''} ${activeIds.has(a.asset_id)?'instop':''} ${focusedAsset===a.asset_id?'focused':''}" onclick="focusAsset(${i})">
      ${a.thumb?`<img src="${a.thumb}" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'ph',innerText:'GPS'}))">`:`<div class="ph">GPS</div>`}
      <div class="name">${a.name||a.time||'Asset'}</div>
    </div>`).join('');
}
function clearGalleryFilter(){
  galleryFilterStop=null;
  focusedAsset=null;
  renderGallery();
  drawRoute();
}
function renderStops(){
  if(!project.stops) project.stops=[];
  stops.innerHTML=project.stops.map((s,i)=>`
    <div class="stop ${s.stop_id===activeStop?'active':''} ${selectedStops.has(s.stop_id)?'active':''}" onclick="stopCardClick('${s.stop_id}')">
      <b>${stopSelectMode?(selectedStops.has(s.stop_id)?'☑ ':'☐ '):''}${s.name||('Stop '+(i+1))}</b>
      <span class="small">${(s.asset_ids||[]).length} photos • ${s.mode||'auto'} • ${Number(s.radius_m||0).toFixed(0)} m</span>
      <div class="row">
        <button onclick="event.stopPropagation(); renameStop('${s.stop_id}')">Rename</button>
        <button onclick="event.stopPropagation(); deleteStop('${s.stop_id}')">Delete</button>
      </div>
    </div>`).join('');
}
function selected(){return project?project.assets.filter(a=>a.selected):[]}
function focusAsset(i){
  const a=project.assets[i];
  focusedAsset=a.asset_id;
  a.selected=true;
  const containing=(project.stops||[]).find(s=>(s.asset_ids||[]).includes(a.asset_id));
  if(containing){
    activeStop=containing.stop_id;
    galleryFilterStop=containing.stop_id;
  }
  map.flyTo({center:[a.lon,a.lat],zoom:16,pitch:55,bearing:0,duration:900});
  renderStops();
  renderGallery();
  drawRoute(false);
  updateStats();
}
function selectAll(){if(!project)return; galleryFilterStop=null; project.assets.forEach(a=>a.selected=true); hydrate();}
function selectNone(){if(!project)return; galleryFilterStop=null; project.assets.forEach(a=>a.selected=false); hydrate();}
function invertSelection(){if(!project)return; project.assets.forEach(a=>a.selected=!a.selected); hydrate();}
function cleanupMap(){
  for(const id of ['route','dots','stopdots','lasso-fill','lasso-line']){
    if(map.getLayer(id)) map.removeLayer(id);
    if(map.getSource(id)) map.removeSource(id);
  }
  routeLayer=false;
}
function drawRoute(autoFit=true){
  if(!map || !project) return;
  cleanupMap();
  const pts=selected().map(a=>[a.lon,a.lat]);
  if(pts.length){
    map.addSource('dots',{type:'geojson',data:{type:'FeatureCollection',features:pts.map(c=>({type:'Feature',geometry:{type:'Point',coordinates:c}}))}});
    map.addLayer({id:'dots',type:'circle',source:'dots',paint:{'circle-radius':4,'circle-color':'#fff','circle-stroke-width':1,'circle-stroke-color':'#00c8ff'}});
  }
  const stopsPts=(project.stops||[]).map(s=>[s.lon,s.lat]);
  if(stopsPts.length){
    map.addSource('stopdots',{type:'geojson',data:{type:'FeatureCollection',features:(project.stops||[]).map(s=>({type:'Feature',properties:{id:s.stop_id,active:s.stop_id===activeStop},geometry:{type:'Point',coordinates:[s.lon,s.lat]}}))}});
    map.addLayer({id:'stopdots',type:'circle',source:'stopdots',paint:{'circle-radius':['case',['==',['get','active'],true],10,7],'circle-color':['case',['==',['get','active'],true],'#72f1b8','#00c8ff'],'circle-stroke-width':2,'circle-stroke-color':'#fff'}});
  }
  if(stopsPts.length>=2){
    map.addSource('route',{type:'geojson',data:{type:'Feature',geometry:{type:'LineString',coordinates:stopsPts}}});
    map.addLayer({id:'route',type:'line',source:'route',paint:{'line-width':5,'line-color':'#00c8ff','line-opacity':.85}});
    routeLayer=true;
  }
  const fitPts = stopsPts.length ? stopsPts : pts;
  if(autoFit && fitPts.length){
    const lons=fitPts.map(p=>p[0]), lats=fitPts.map(p=>p[1]);
    map.fitBounds([[Math.min(...lons),Math.min(...lats)],[Math.max(...lons),Math.max(...lats)]],{padding:80,duration:600,maxZoom:14});
  }
  drawLasso();
}
function focusStop(id){
  const s=project.stops?.find(x=>x.stop_id===id);
  if(!s)return;
  activeStop=id;
  galleryFilterStop=id;
  focusedAsset=null;
  const assets=stopAssets(s);
  if(assets.length){
    const pts=assets.map(a=>[a.lon,a.lat]);
    const lons=pts.map(p=>p[0]), lats=pts.map(p=>p[1]);
    map.fitBounds([[Math.min(...lons),Math.min(...lats)],[Math.max(...lons),Math.max(...lats)]],{padding:120,duration:800,maxZoom:17});
  } else {
    map.flyTo({center:[s.lon,s.lat],zoom:15,pitch:55,duration:800});
  }
  renderStops();
  renderGallery();
  drawRoute(false);
}
function updateStats(){
  if(!project){stats.innerText='';return}
  stats.innerHTML=`<span class="pill">${project.assets.length} total</span><span class="pill">${selected().length} selected</span><span class="pill">${(project.stops||[]).length} stops</span>`+(project.last_export?`<p><a href="${project.last_export}">Last export</a></p>`:'');
}
async function save(){
  if(!project)return;
  project.name=tourTitle.value||project.name;
  project.settings={title:tourTitle.value||project.name,duration_min:Number(duration.value||12),mode:mode.value,pace:pace.value,stop_radius_m:Number(stopRadius.value||200),show_stop_slides:showStopSlides.checked,reverse_route:reverseRouteBox.checked};
  project=await (await fetch('/api/project/'+project.id,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(project)})).json();
  await loadProjects(); hydrate(); status('Saved.');
}
function status(s){stats.innerHTML += `<p>${s}</p>`}
async function testImmichConnectionFields(urlEl,keyEl){
  const base_url=urlEl.value.trim().replace(/\/$/,'');
  const api_key=keyEl.value.trim();
  if(!base_url || !api_key){status('Enter Immich URL and API key first.');return null}
  status('Testing Immich connection…');
  const r=await fetch('/api/immich/test',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({base_url,api_key})});
  const j=await r.json();
  if(j.ok){status('✅ '+j.message);}
  else{status('❌ '+j.message);}
  return j;
}
async function testImportConnection(){return testImmichConnectionFields(immichUrl,immichKey)}
async function testSetupConnection(){return testImmichConnectionFields(setupImmichUrl,setupImmichKey)}
async function testAccountConnection(){return testImmichConnectionFields(accountImmichUrl,accountImmichKey)}
function stopCardClick(id){
  if(stopSelectMode){
    if(selectedStops.has(id)) selectedStops.delete(id); else selectedStops.add(id);
    renderStops();
    return;
  }
  focusStop(id);
}
function toggleStopSelect(){
  stopSelectMode=!stopSelectMode;
  selectedStops.clear();
  status(stopSelectMode?'Stop select mode on. Click stop cards, then Group Stop.':'Stop select mode off.');
  renderStops();
}
function groupSelectedStops(){
  if(!project || selectedStops.size<2){status('Select at least two stops to group.');return}
  const chosen=project.stops.filter(s=>selectedStops.has(s.stop_id));
  const ids=[...new Set(chosen.flatMap(s=>s.asset_ids||[]))];
  const assets=project.assets.filter(a=>ids.includes(a.asset_id));
  if(!assets.length){status('Selected stops have no photos.');return}
  const lat=assets.reduce((sum,a)=>sum+a.lat,0)/assets.length;
  const lon=assets.reduce((sum,a)=>sum+a.lon,0)/assets.length;
  const firstIndex=Math.min(...chosen.map(s=>project.stops.findIndex(x=>x.stop_id===s.stop_id)));
  const grouped={stop_id:Math.random().toString(16).slice(2,10),name:`Grouped Stop ${firstIndex+1}`,lat,lon,radius_m:Number(stopRadius.value||200),asset_ids:ids,mode:'grouped',locked:true,children:chosen};
  project.stops=project.stops.filter(s=>!selectedStops.has(s.stop_id));
  project.stops.splice(firstIndex,0,grouped);
  activeStop=grouped.stop_id;
  selectedStops.clear();
  stopSelectMode=false;
  hydrate();
  status(`Grouped ${chosen.length} stops into one stop with ${ids.length} photos.`);
}
function reverseRoute(){
  if(!project || !project.stops?.length)return;
  project.stops.reverse();
  reverseRouteBox.checked=!reverseRouteBox.checked;
  project.settings.reverse_route=reverseRouteBox.checked;
  hydrate();
  status('Route order reversed.');
}
function saveImmichConnection(){
  localStorage.setItem('trippy_immich_url', immichUrl.value.trim());
  localStorage.setItem('trippy_immich_key', immichKey.value.trim());
  localStorage.setItem('trippy_setup_seen', '1');
  status('Saved Immich URL/API key in this browser.');
}
function clearImmichConnection(){
  localStorage.removeItem('trippy_immich_url');
  localStorage.removeItem('trippy_immich_key');
  immichUrl.value='';
  immichKey.value='';
  status('Cleared saved Immich connection from this browser.');
}
function loadImmichConnection(){
  immichUrl.value = localStorage.getItem('trippy_immich_url') || immichUrl.value || 'http://192.168.68.153:2283';
  immichKey.value = localStorage.getItem('trippy_immich_key') || '';
}
function maybeShowSetup(){
  const seen=localStorage.getItem('trippy_setup_seen');
  const key=localStorage.getItem('trippy_immich_key');
  if(!seen && !key){
    setupImmichUrl.value=localStorage.getItem('trippy_immich_url') || 'http://192.168.68.153:2283';
    setupImmichKey.value='';
    setupModal.style.display='flex';
  }
}
function saveSetupConnection(){
  localStorage.setItem('trippy_immich_url', setupImmichUrl.value.trim());
  localStorage.setItem('trippy_immich_key', setupImmichKey.value.trim());
  localStorage.setItem('trippy_setup_seen', '1');
  loadImmichConnection();
  setupModal.style.display='none';
  status('Immich API key saved. You can import a date range now.');
}
function skipSetup(){
  localStorage.setItem('trippy_setup_seen', '1');
  setupModal.style.display='none';
}
function openAccount(){
  accountImmichUrl.value=localStorage.getItem('trippy_immich_url') || immichUrl.value || 'http://192.168.68.153:2283';
  accountImmichKey.value=localStorage.getItem('trippy_immich_key') || immichKey.value || '';
  accountModal.style.display='flex';
}
function closeAccount(){
  accountModal.style.display='none';
}
function saveAccountConnection(){
  localStorage.setItem('trippy_immich_url', accountImmichUrl.value.trim());
  localStorage.setItem('trippy_immich_key', accountImmichKey.value.trim());
  localStorage.setItem('trippy_setup_seen', '1');
  loadImmichConnection();
  closeAccount();
  status('Account Immich connection saved.');
}
function clearAccountConnection(){
  localStorage.removeItem('trippy_immich_url');
  localStorage.removeItem('trippy_immich_key');
  immichUrl.value='';
  immichKey.value='';
  accountImmichUrl.value='';
  accountImmichKey.value='';
  status('Account Immich connection cleared.');
}
async function deleteProjectById(id){
  const isCurrent=project && project.id===id;
  const name=isCurrent?(project.name||id):id;
  if(!confirm(`Delete project "${name}"? This removes the project from Trippy, not Immich.`)) return;
  const r=await fetch(`/api/project/${id}`,{method:'DELETE'});
  const j=await r.json();
  if(!r.ok){status('Delete failed: '+(j.detail||JSON.stringify(j)));return}
  if(isCurrent){
    project=null;
    activeStop=null;
    galleryFilterStop=null;
    focusedAsset=null;
    title.innerText='No project selected';
    gallery.innerHTML='';
    stops.innerHTML='';
    stats.innerHTML='Deleted project.';
    cleanupMap();
  }
  await loadProjects();
}
async function deleteCurrentProject(){
  if(!project){status('No project selected.');return}
  return deleteProjectById(project.id);
}
async function recluster(){
  if(!project)return;
  const r=await fetch(`/api/project/${project.id}/recluster`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({radius_m:Number(stopRadius.value||200)})});
  project=await r.json();
  activeStop=project.stops?.[0]?.stop_id || null;
  await loadProjects(); hydrate(); status('Reclustered stops.');
}
function renameStop(id){
  const s=project.stops.find(x=>x.stop_id===id); if(!s)return;
  const name=prompt('Stop name',s.name||'Stop'); if(name){s.name=name; hydrate();}
}
function deleteStop(id){
  project.stops=project.stops.filter(s=>s.stop_id!==id);
  activeStop=project.stops?.[0]?.stop_id || null;
  hydrate();
}
function moveStopToMapCenter(){
  if(!project||!activeStop)return;
  const s=project.stops.find(x=>x.stop_id===activeStop); if(!s)return;
  const c=map.getCenter(); s.lon=c.lng; s.lat=c.lat; s.mode='manual-moved'; hydrate();
}
function centerStopFromPhotos(){
  if(!project||!activeStop)return;
  const s=project.stops.find(x=>x.stop_id===activeStop); if(!s)return;
  const assets=stopAssets(s); if(!assets.length)return;
  s.lat=assets.reduce((a,b)=>a+b.lat,0)/assets.length;
  s.lon=assets.reduce((a,b)=>a+b.lon,0)/assets.length;
  s.mode='manual-centered'; hydrate();
}
function toggleLasso(){
  lassoMode=!lassoMode;
  mapHint.style.display=lassoMode?'block':'none';
  if(lassoMode) status('Lasso mode on. Click around the area on the map, then Finish lasso.');
}
function clearLasso(){
  lassoCoords=[]; lassoMode=false; mapHint.style.display='none'; drawRoute();
}
function drawLasso(){
  if(!map || lassoCoords.length<2) return;
  if(map.getLayer('lasso-line')) map.removeLayer('lasso-line');
  if(map.getSource('lasso-line')) map.removeSource('lasso-line');
  map.addSource('lasso-line',{type:'geojson',data:{type:'Feature',geometry:{type:'LineString',coordinates:lassoCoords}}});
  map.addLayer({id:'lasso-line',type:'line',source:'lasso-line',paint:{'line-width':3,'line-color':'#72f1b8','line-dasharray':[2,2]}});
  if(lassoCoords.length>=3){
    const poly=[...lassoCoords,lassoCoords[0]];
    if(map.getLayer('lasso-fill')) map.removeLayer('lasso-fill');
    if(map.getSource('lasso-fill')) map.removeSource('lasso-fill');
    map.addSource('lasso-fill',{type:'geojson',data:{type:'Feature',geometry:{type:'Polygon',coordinates:[poly]}}});
    map.addLayer({id:'lasso-fill',type:'fill',source:'lasso-fill',paint:{'fill-color':'#72f1b8','fill-opacity':.14}});
  }
}
function pointInPoly(pt, poly){
  const x=pt[0], y=pt[1]; let inside=false;
  for(let i=0,j=poly.length-1;i<poly.length;j=i++){
    const xi=poly[i][0], yi=poly[i][1], xj=poly[j][0], yj=poly[j][1];
    const intersect=((yi>y)!=(yj>y)) && (x < (xj-xi)*(y-yi)/(yj-yi)+xi);
    if(intersect) inside=!inside;
  }
  return inside;
}
function finishLasso(){
  if(!project||lassoCoords.length<3){status('Need at least 3 lasso points.');return}
  const inside=project.assets.filter(a=>a.selected && pointInPoly([a.lon,a.lat],lassoCoords));
  if(!inside.length){status('No selected photos inside lasso.');return}
  const lat=inside.reduce((x,a)=>x+a.lat,0)/inside.length;
  const lon=inside.reduce((x,a)=>x+a.lon,0)/inside.length;
  const s={stop_id:Math.random().toString(16).slice(2,10),name:`Lasso Stop ${(project.stops||[]).length+1}`,lat,lon,radius_m:Number(stopRadius.value||200),asset_ids:inside.map(a=>a.asset_id),mode:'lasso',locked:true};
  project.stops=(project.stops||[]).filter(old=>!old.asset_ids?.some(id=>s.asset_ids.includes(id)));
  project.stops.push(s);
  activeStop=s.stop_id;
  clearLasso();
  hydrate();
  status(`Created lasso stop with ${inside.length} photos.`);
}
async function render(){
  if(!project)return;
  await save();
  const fd=new FormData();
  const f=audio.files[0]; if(f) fd.append('audio',f);
  renderOverlay.style.display='flex';
  const stages=[
    'Clustering stops and building the route…',
    'Opening the map renderer…',
    'Capturing animation frames…',
    'Encoding MP4 with FFmpeg…',
    'Almost done. Cleaning up export…'
  ];
  let stage=0;
  renderSub.innerText=stages[0];
  const timer=setInterval(()=>{stage=(stage+1)%stages.length; renderSub.innerText=stages[stage];},4200);
  status('Rendering. Do not refresh this tab.');
  try{
    const r=await fetch(`/api/project/${project.id}/render`,{method:'POST',body:fd});
    const text=await r.text();
    let j;
    try{j=JSON.parse(text)}catch(_){j={detail:text||'Unknown render error'}}
    clearInterval(timer);
    renderOverlay.style.display='none';
    if(!r.ok){status('Error: '+(j.detail||JSON.stringify(j))); return;}
    project.last_export=j.download;
    updateStats();
    status(`Done: ${j.stops} stops, ${j.points} photos. <a href="${j.download}">Download MP4</a>`);
  }catch(e){
    clearInterval(timer);
    renderOverlay.style.display='none';
    status('Render failed: '+e);
  }
}
function newImmich(){immichUrl.focus()}
function localDateString(d){
  const y=d.getFullYear();
  const m=String(d.getMonth()+1).padStart(2,'0');
  const day=String(d.getDate()).padStart(2,'0');
  return `${y}-${m}-${day}`;
}
function setDatePreset(days){
  const end=new Date();
  const start=new Date();
  start.setDate(end.getDate()-(days-1));
  immichStart.value=localDateString(start);
  immichEnd.value=localDateString(end);
}
function setToday(){
  const today=localDateString(new Date());
  immichStart.value=today;
  immichEnd.value=today;
}
function dateToImmichStart(d){
  return `${d}T00:00:00`;
}
function dateToImmichEnd(d){
  return `${d}T23:59:59`;
}
function initDateDefaults(){
  if(!immichStart.value || !immichEnd.value) setDatePreset(7);
}
async function createImmich(){
  initDateDefaults();
  if(!immichUrl.value || !immichKey.value){status('Enter Immich URL and API key.');return}
  if(!immichStart.value || !immichEnd.value){status('Pick start and end dates.');return}
  if(immichStart.value > immichEnd.value){status('Start date must be before end date.');return}
  const test=await testImportConnection();
  if(!test || !test.ok){status('Fix Immich connection before importing. Required permissions: asset.read, asset.download, asset.view.');return}
  saveImmichConnection();
  const body={
    name:`Immich Journey ${immichStart.value} to ${immichEnd.value}`,
    base_url:immichUrl.value.trim().replace(/\/$/,''),
    api_key:immichKey.value.trim(),
    start_date:dateToImmichStart(immichStart.value),
    end_date:dateToImmichEnd(immichEnd.value)
  };
  status('Importing Immich GPS assets.');
  const r=await fetch('/api/project/immich',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
  const j=await r.json(); if(!r.ok){status('Error: '+(j.detail||JSON.stringify(j)));return}
  await loadProjects(); project=j; activeStop=project.stops?.[0]?.stop_id||null; hydrate();
}
async function uploadFiles(files){
  const fd=new FormData();
  for(const f of files)fd.append('files',f);
  fd.append('name','Upload Tour');
  const r=await fetch('/api/project/upload',{method:'POST',body:fd});
  const j=await r.json(); if(!r.ok){alert(j.detail||JSON.stringify(j));return}
  await loadProjects(); project=j; activeStop=project.stops?.[0]?.stop_id||null; hydrate();
}
loadImmichConnection();
initDateDefaults();
loadProjects();
maybeShowSetup();
</script>
</body>
</html>
HTML
pct push "$CTID" /tmp/trippy_index.html "$APP_DIR/frontend/index.html"

step "Installing render/runtime dependencies"
run_bg "Installing Python packages, Playwright, and Chromium" pct exec "$CTID" -- bash -lc "
set -e
cd $APP_DIR/backend
python3 -m venv venv
./venv/bin/pip install --upgrade pip >/dev/null
./venv/bin/pip install -r requirements.txt >/dev/null
cd $APP_DIR
npm init -y >/dev/null
npm install playwright >/dev/null
npx playwright install --with-deps chromium >/dev/null
"

step "Creating Trippy service"
cat >/tmp/trippy.service <<SERVICE
[Unit]
Description=Trippy Immich-style route tour generator
After=network-online.target

[Service]
WorkingDirectory=$APP_DIR/backend
ExecStart=$APP_DIR/backend/venv/bin/uvicorn main:app --host 0.0.0.0 --port $PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE
pct push "$CTID" /tmp/trippy.service /etc/systemd/system/trippy.service
run_bg "Starting Trippy service" pct exec "$CTID" -- bash -lc "systemctl daemon-reload && systemctl enable --now trippy"

step "Waiting for network"
sleep 3
IP="$(pct exec "$CTID" -- bash -lc "hostname -I | awk '{print \$1}'" | tr -d '\r')"

step "Install complete"
echo
printf "${GREEN}${BOLD}Trippy is ready.${RESET}\n"
printf "  ${BOLD}CTID:${RESET}     $CTID\n"
printf "  ${BOLD}Hostname:${RESET} $HOSTNAME\n"
printf "  ${BOLD}URL:${RESET}      http://${IP}:${PORT}\n"
echo
printf "${DIM}Default root password: $PASSWORD${RESET}\n"
printf "${DIM}Change it after install: pct enter $CTID && passwd${RESET}\n"
echo
printf "${CYAN}${BOLD}v10.1.0 features${RESET}\n"
printf "  ${CYAN}•${RESET} Clean rebuild install, community-script style\n"
printf "  ${CYAN}•${RESET} Styled console logo and animated progress\n"
printf "  ${CYAN}•${RESET} Immich-style projects/gallery/map editor\n"
printf "  ${CYAN}•${RESET} Date range import from Immich\n"
printf "  ${CYAN}•${RESET} Upload-based GPS media import\n"
printf "  ${CYAN}•${RESET} Stop radius auto-clustering\n"
printf "  ${CYAN}•${RESET} Density-first stop location selection\n"
printf "  ${CYAN}•${RESET} Stop list review and lasso stop grouping\n"
printf "  ${CYAN}•${RESET} Stop grouping with Select Stops → Group Stop\n"
printf "  ${CYAN}•${RESET} Reverse route button/setting\n"
printf "  ${CYAN}•${RESET} Preview Suite before render\n"
printf "  ${CYAN}•${RESET} Efficient flat render path, no MapLibre/WebGL during export\n"
printf "  ${CYAN}•${RESET} Render overlay with animated loading bar\n"
printf "  ${CYAN}•${RESET} Optional audio upload and MP4 export\n"
printf "  ${CYAN}•${RESET} Delete old projects from the UI\n"
printf "  ${CYAN}•${RESET} Save Immich URL/API key locally in browser\n"
printf "  ${CYAN}•${RESET} First-run Immich API key setup prompt\n"
printf "  ${CYAN}•${RESET} Account panel for updating Immich connection\n"
printf "  ${CYAN}•${RESET} Immich connection validator\n"
printf "  ${CYAN}•${RESET} Setup permissions: asset.read, asset.view, asset.download, map.read, timeline.read\n"
printf "  ${CYAN}•${RESET} Safer project thumbnail proxy for new projects\n"
echo
printf "  ${CYAN}•${RESET} Auto-selects next available CTID by default\n"
printf "  ${CYAN}•${RESET} Container hostname/name: Trippy\n"
printf "  ${CYAN}•${RESET} Present Mode-first interactive journey player\n"
printf "  ${CYAN}•${RESET} Logo/brand identity in installer, LXC notes, and web banner\n"
printf "  ${CYAN}•${RESET} Future export direction: portable interactive journey package, MP4 secondary\n"
printf "${PINK}${BOLD}Go make something weird.${RESET}\n"
