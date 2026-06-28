#!/usr/bin/env bash
set -euo pipefail
USER_SUPPLIED_CTID="${CTID:-}"

# Trippy v10.2.2: Immich-style web UI route-tour generator for Proxmox LXC
# Adds stop-based clustering, stop radius, stop review/editing, and lasso grouping.
#
#
# Install directly from GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.2.2.sh \
#     -o trippy-install-v10.2.2.sh
#   chmod +x trippy-install-v10.2.2.sh
#   ./trippy-install-v10.2.2.sh
#
# Or with wget:
#
#   wget -O trippy-install-v10.2.2.sh \
#     https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.2.2.sh
#   chmod +x trippy-install-v10.2.2.sh
#   ./trippy-install-v10.2.2.sh
#
# Run on Proxmox host:
#   bash trippy-install-v10.2.2.sh
#
# Optional:
#   CTID=106 STORAGE=local-lvm BRIDGE=vmbr0 bash trippy-install-v10.2.2.sh

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

printf "${CYAN}${BOLD}Trippy v10.2.2 Clean Installer${RESET}\n"
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


if ! command -v pct >/dev/null 2>&1; then
  echo "ERROR: Run this on the Proxmox host. pct not found."
  exit 1
fi

step "Choosing container"
if [[ -n "${USER_SUPPLIED_CTID:-}" ]] && pct status "$CTID" >/dev/null 2>&1; then
  printf "${YELLOW}!${RESET} Existing CTID ${BOLD}$CTID${RESET} explicitly selected. Rebuilding that container.\n"
  pct stop "$CTID" >/dev/null 2>&1 || true
  pct destroy "$CTID" --purge 1 --force 1 >/dev/null 2>&1 || pct destroy "$CTID" --force 1 >/dev/null 2>&1 || true
  sleep 2
elif pct status "$CTID" >/dev/null 2>&1; then
  CTID="$(next_ctid)"
fi
printf "${GREEN}✓${RESET} Selected CTID: ${BOLD}$CTID${RESET}\n"

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

step "Creating fresh LXC $CTID (Trippy)"
pct create "$CTID" "$TEMPLATE" \
  --hostname "Trippy" \
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
pct set "$CTID" --hostname Trippy >/dev/null 2>&1 || true
pct exec "$CTID" -- bash -lc 'hostnamectl set-hostname Trippy || true; echo Trippy >/etc/hostname' >/dev/null 2>&1 || true

pct set "$CTID" --description "🧭 Trippy v10.2.2
Interactive Immich journey player
Present Mode • Stop grouping • Preview Suite
Required Immich API permissions:
asset.read, asset.view, asset.download, map.read, timeline.read" >/dev/null 2>&1 || true

step "Installing system dependencies"
run_bg "Installing Debian packages and Node.js" pct exec "$CTID" -- bash -lc '
set -e
export DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=a LANG=C.UTF-8 LC_ALL=C.UTF-8
apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 apt-get install -y \
  curl git ca-certificates gnupg python3 python3-venv python3-pip \
  ffmpeg exiftool nginx unzip jq build-essential >/dev/null
curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 apt-get install -y nodejs >/dev/null
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

for p in [UPLOADS, EXPORTS, WORK, PROJECTS, FRONTEND]:
    p.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Trippy", version="1.2.2")
app.mount("/exports", StaticFiles(directory=str(EXPORTS)), name="exports")
app.mount("/uploads", StaticFiles(directory=str(UPLOADS)), name="uploads")
app.mount("/static", StaticFiles(directory=str(FRONTEND)), name="static")

@app.get("/api/health")
def health():
    return {
        "ok": True,
        "app": "trippy",
        "version": "1.2.2",
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
// Trippy v10.2.2 UI behavior upgrades
(function(){{
  function ready(fn){{ if(document.readyState!=='loading') fn(); else document.addEventListener('DOMContentLoaded',fn); }}
  window.TRIPPY_VERSION='v10.2.2';
  ready(() => {{
    if(!document.querySelector('.versionBadge')){{
      const v=document.createElement('div'); v.className='versionBadge'; v.textContent='v10.2.2'; document.body.appendChild(v);
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


// TRIPPY_UI_V1011_DIRECT
(function(){{
  function ready(fn){{if(document.readyState!=='loading')fn();else document.addEventListener('DOMContentLoaded',fn);}}
  function installChrome(){{
    if(!document.querySelector('.versionBadge')){{
      const v=document.createElement('div');v.className='versionBadge';v.textContent='v10.2.2';document.body.appendChild(v);
    }}
    const side=document.querySelector('aside,.sidebar,.left')||document.body.firstElementChild;
    if(side && !document.querySelector('.trippyBrand')){{
      const brand=document.createElement('div');brand.className='trippyBrand';
      brand.innerHTML='<div class="trippyLogo"><span class="petal p1"></span><span class="petal p2"></span><span class="petal p3"></span><span class="petal p4"></span><span class="petal p5"></span></div><div class="trippyWord">trippy</div>';
      side.prepend(brand);
    }}
    document.querySelectorAll('button').forEach(b=>{{const t=(b.textContent||'').toLowerCase();if(t.includes('preview')||t.includes('present')){{b.classList.add('presentHero');b.textContent='▶ Present Journey';}}}});
  }}
  function collapseStops(){{
    document.querySelectorAll('.stop').forEach((el,idx)=>{{
      if(el.dataset.v1011)return;
      el.dataset.v1011='1';el.classList.add('collapsed');
      const b=el.querySelector('b');const small=el.querySelector('.small');
      const summary=document.createElement('div');summary.className='stopSummary';
      summary.innerHTML='<div>'+(b?b.outerHTML:'<b>Stop '+(idx+1)+'</b>')+(small?small.outerHTML:'')+'</div><span class="stopChevron">›</span>';
      if(b)b.remove();if(small)small.remove();el.prepend(summary);
      summary.addEventListener('click',ev=>{{ev.stopPropagation();document.querySelectorAll('.stop').forEach(x=>{{if(x!==el)x.classList.add('collapsed')}});el.classList.toggle('collapsed');}});
    }});
  }}
  ready(()=>{{installChrome();setTimeout(collapseStops,600);setInterval(()=>{{installChrome();collapseStops();}},1600);}});
  const oldFocusAsset=window.focusAsset;
  if(typeof oldFocusAsset==='function'){{
    window.focusAsset=function(i){{
      oldFocusAsset(i);
      try{{
        const a=project.assets[i];if(!a||!map)return;
        if(map.flyTo)map.flyTo({{center:[a.lon,a.lat],zoom:19,pitch:45,bearing:0,duration:850}});
        const h='<div class="photoPopup">'+(a.thumb?'<img src="'+a.thumb+'">':'')+'<b>'+(a.name||'Photo')+'</b><br><span>'+(a.time||'')+'</span></div>';
        if(window.maplibregl&&maplibregl.Popup)new maplibregl.Popup({{offset:18,closeButton:true}}).setLngLat([a.lon,a.lat]).setHTML(h).addTo(map);
        else if(window.L&&L.popup)L.popup().setLatLng([a.lat,a.lon]).setContent(h).openOn(map);
      }}catch(e){{console.warn(e);}}
    }}
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

/* Trippy v10.2.2 UI refresh */
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


/* TRIPPY_UI_V1011_DIRECT */
:root{{--trippy-bg:#03070d;--trippy-panel:#08111c;--trippy-line:#1d3348;--trippy-cyan:#00d9ff;--trippy-blue:#247cff;--trippy-pink:#ff4da6;--trippy-green:#27d97f;--trippy-text:#eef7ff;--trippy-muted:#8fa6b8}}
body{{background:radial-gradient(circle at 12% 10%,rgba(0,217,255,.18),transparent 26%),radial-gradient(circle at 82% 18%,rgba(36,124,255,.12),transparent 32%),linear-gradient(145deg,#03070d,#07101a 58%,#02040a)!important;color:var(--trippy-text)!important}}
aside,.sidebar,.left,.panel,#projects,.right,.settings,.card,section{{background:rgba(8,17,28,.90)!important;border-color:rgba(75,126,164,.30)!important;box-shadow:0 18px 64px rgba(0,0,0,.36)!important;backdrop-filter:blur(14px)}}
button{{border-radius:14px!important;border:1px solid rgba(68,131,176,.48)!important;background:linear-gradient(180deg,rgba(20,44,69,.96),rgba(11,27,45,.96))!important;color:#ecfbff!important;font-weight:800!important}}
button:hover{{border-color:var(--trippy-cyan)!important;box-shadow:0 0 22px rgba(0,217,255,.28)!important}}
button.primary,button[onclick*="createImmich"],button[onclick*="openPreviewSuite"],button[onclick*="render"],.presentHero{{background:linear-gradient(135deg,#0726a8,#00a3c7)!important;border-color:rgba(0,217,255,.85)!important;box-shadow:0 0 28px rgba(0,217,255,.30)!important}}
input,select,textarea{{background:#07101a!important;color:var(--trippy-text)!important;border:1px solid rgba(89,139,174,.38)!important;border-radius:14px!important}}
#map,.mapwrap{{border-radius:22px!important;overflow:hidden;box-shadow:inset 0 0 0 1px rgba(0,217,255,.20),0 20px 80px rgba(0,0,0,.34)!important}}
.versionBadge{{position:fixed;left:16px;top:12px;z-index:9999;color:#18f0ff;font-weight:950;font-size:15px;letter-spacing:.4px;text-shadow:0 0 12px rgba(0,217,255,.7);background:rgba(3,7,13,.65);border:1px solid rgba(0,217,255,.28);border-radius:999px;padding:5px 10px}}
.trippyBrand{{display:flex;align-items:center;gap:12px;margin:22px 12px 20px}}
.trippyLogo{{width:62px;height:62px;position:relative;filter:drop-shadow(0 0 12px rgba(0,217,255,.28))}}
.trippyLogo .petal{{position:absolute;left:23px;top:3px;width:28px;height:44px;border-radius:24px 24px 10px 10px;transform-origin:8px 28px;mix-blend-mode:screen}}
.trippyLogo .p1{{background:#ff2727;transform:rotate(0deg) skewX(-16deg)}}
.trippyLogo .p2{{background:#ffb300;transform:rotate(72deg) skewX(17deg)}}
.trippyLogo .p3{{background:#18c957;transform:rotate(144deg) skewX(-13deg)}}
.trippyLogo .p4{{background:#2385ff;transform:rotate(216deg) skewX(15deg)}}
.trippyLogo .p5{{background:#e66ab5;transform:rotate(288deg) skewX(-18deg)}}
.trippyLogo:after{{content:"";position:absolute;inset:18px;border:2px solid rgba(0,217,255,.86);border-radius:50%;box-shadow:0 0 10px rgba(0,217,255,.7)}}
.trippyWord{{font-size:38px;font-weight:950;font-style:italic;line-height:1;color:white;letter-spacing:-1px;text-shadow:2px 0 #00d9ff,-2px 0 #ff4da6,0 4px 18px rgba(0,0,0,.9)}}
.stop.collapsed .row{{display:none!important}}
.stop{{border-radius:16px!important;transition:.18s ease}}
.stop:hover,.stop.active{{border-color:var(--trippy-cyan)!important;box-shadow:0 0 22px rgba(0,217,255,.18)!important}}
.stopSummary{{cursor:pointer;display:flex;align-items:center;justify-content:space-between;gap:8px}}
.stopChevron{{color:var(--trippy-muted);font-weight:900}}
.tile{{border-radius:16px!important;overflow:hidden;transition:.16s ease}}
.tile.focused,.tile:hover{{transform:translateY(-2px) scale(1.02);box-shadow:0 0 25px rgba(0,217,255,.32)!important}}
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
        immich = p.get("immich") or {}
        out.append({
            "id": p["id"],
            "name": p.get("name", "Untitled"),
            "created": p.get("created"),
            "source": p.get("source"),
            "count": len(p.get("assets", [])),
            "stops": len(p.get("stops", [])),
            "start_date": immich.get("start_date"),
            "end_date": immich.get("end_date"),
        })
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
    result = {"ok": False, "base_url": base, "required_permissions": ["asset.read", "asset.view", "asset.download", "map.read", "timeline.read"], "search_ok": False, "thumb_ok": False, "message": ""}
    r = requests.post(base + "/api/search/metadata", headers=headers, json={"size": 1, "withExif": True}, timeout=30)
    if r.status_code == 401:
        result["message"] = "Unauthorized. The API key is invalid or revoked."
        return result
    if r.status_code == 403:
        result["message"] = "Forbidden. API key is missing required permissions: asset.read, asset.view, asset.download, map.read, timeline.read."
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
  if(!test || !test.ok){status('Fix Immich connection before importing. Required permissions: asset.read, asset.view, asset.download, map.read, timeline.read.');return}
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






# v10.2.2: full frontend replacement, not an overlay.
pct exec "$CTID" -- bash -lc "cat >/tmp/trippy_frontend.b64 <<'EOF_TRIPPY_FRONTEND_B64'
PCFkb2N0eXBlIGh0bWw+CjxodG1sIGxhbmc9ImVuIj4KPGhlYWQ+CjxtZXRhIGNoYXJzZXQ9InV0Zi04Ij4KPG1ldGEgbmFtZT0idmlld3BvcnQiIGNvbnRlbnQ9IndpZHRoPWRldmljZS13aWR0aCxpbml0aWFsLXNjYWxlPTEiPgo8dGl0bGU+VHJpcHB5IHYxMC4yLjI8L3RpdGxlPgo8bGluayByZWw9InN0eWxlc2hlZXQiIGhyZWY9Ii9zdGF0aWMvdmVuZG9yL21hcGxpYnJlLWdsLmNzcyI+CjxzY3JpcHQgc3JjPSIvc3RhdGljL3ZlbmRvci9tYXBsaWJyZS1nbC5qcyI+PC9zY3JpcHQ+CjxzdHlsZT4KOnJvb3R7CiAgLS1iZzojMDMwODEzOy0tYmcyOiMwNzExMWQ7LS1wYW5lbDojMDgxNDIxOy0tcGFuZWwyOiMwZDFjMmM7LS1jYXJkOiMwYzFhMjk7CiAgLS1saW5lOiMxZDM4NTA7LS1saW5lMjojMjU0YTY4Oy0tY3lhbjojMDBkOGZmOy0tY3lhbjI6IzM2ZWRmZjstLWJsdWU6IzI2N2RmZjsKICAtLXZpb2xldDojNjg0OGZmOy0tcGluazojZmY0ZGE2Oy0tZ3JlZW46IzM5ZDk5NTstLXJlZDojZmY0ZDY2Oy0tdGV4dDojZjJmOGZmOwogIC0tbXV0ZWQ6IzhlYTNiNjstLXNvZnQ6I2I4YzhkNzstLXNoYWRvdzowIDI0cHggNzBweCByZ2JhKDAsMCwwLC40MikKfQoqe2JveC1zaXppbmc6Ym9yZGVyLWJveH0KaHRtbCxib2R5e2hlaWdodDoxMDAlO21hcmdpbjowO292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOnZhcigtLWJnKTtjb2xvcjp2YXIoLS10ZXh0KTtmb250LWZhbWlseTpJbnRlciwiU2Vnb2UgVUkiLHN5c3RlbS11aSxzYW5zLXNlcmlmfQpib2R5e2JhY2tncm91bmQ6cmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCA5JSAwJSxyZ2JhKDAsMjE2LDI1NSwuMTMpLHRyYW5zcGFyZW50IDI3JSkscmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCA4MiUgNyUscmdiYSgxMDQsNzIsMjU1LC4xMiksdHJhbnNwYXJlbnQgMzAlKSxsaW5lYXItZ3JhZGllbnQoMTQ1ZGVnLCMwMjA3MTEsIzA3MTIxZSA1OCUsIzAyMDYwZCl9CmJ1dHRvbixpbnB1dCxzZWxlY3R7Zm9udDppbmhlcml0fWJ1dHRvbntjb2xvcjp2YXIoLS10ZXh0KTtjdXJzb3I6cG9pbnRlcjtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzUsMTI2LDE2NCwuNDUpO2JvcmRlci1yYWRpdXM6MTNweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgyMCw0Myw2NiwuOTgpLHJnYmEoMTAsMjUsNDEsLjk4KSk7Zm9udC13ZWlnaHQ6ODAwO3RyYW5zaXRpb246LjE2cyBlYXNlfWJ1dHRvbjpob3Zlcntib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMjJweCByZ2JhKDAsMjE2LDI1NSwuMjIpO3RyYW5zZm9ybTp0cmFuc2xhdGVZKC0xcHgpfQppbnB1dCxzZWxlY3R7d2lkdGg6MTAwJTtjb2xvcjp2YXIoLS10ZXh0KTtiYWNrZ3JvdW5kOiMwNzExMWM7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDkwLDEzOSwxNzMsLjM4KTtib3JkZXItcmFkaXVzOjEycHg7cGFkZGluZzoxMXB4IDEycHg7b3V0bGluZTpub25lfWlucHV0OmZvY3VzLHNlbGVjdDpmb2N1c3tib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMCAzcHggcmdiYSgwLDIxNiwyNTUsLjEwKX0KLnNtYWxse2ZvbnQtc2l6ZToxMnB4O2NvbG9yOnZhcigtLW11dGVkKX0uaGlkZGVue2Rpc3BsYXk6bm9uZSFpbXBvcnRhbnR9LnN2Z0ljb257d2lkdGg6MjBweDtoZWlnaHQ6MjBweDtzdHJva2U6Y3VycmVudENvbG9yO2ZpbGw6bm9uZTtzdHJva2Utd2lkdGg6MS44O3N0cm9rZS1saW5lY2FwOnJvdW5kO3N0cm9rZS1saW5lam9pbjpyb3VuZH0KLmFwcFNoZWxse2hlaWdodDoxMDB2aDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjI4NnB4IG1pbm1heCg2NTBweCwxZnIpIDM1MHB4O292ZXJmbG93OmhpZGRlbn0KLmxlZnRSYWlse21pbi13aWR0aDowO2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDE4MGRlZyxyZ2JhKDQsMTMsMjMsLjk4KSxyZ2JhKDIsOCwxNSwuOTkpKTtib3JkZXItcmlnaHQ6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4xNCk7cGFkZGluZzoxN3B4IDE3cHggMjBweDtkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO2dhcDoxNHB4O2JveC1zaGFkb3c6MTZweCAwIDYwcHggcmdiYSgwLDAsMCwuMzQpO3otaW5kZXg6MTB9Ci5icmFuZExpbmV7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTJweDtoZWlnaHQ6NjRweH0ud29yZG1hcmt7Zm9udC1zaXplOjMxcHg7Zm9udC13ZWlnaHQ6OTUwO2ZvbnQtc3R5bGU6aXRhbGljO2xldHRlci1zcGFjaW5nOi0xLjVweDt0ZXh0LXNoYWRvdzoycHggMCB2YXIoLS1jeWFuKSwtMnB4IDAgdmFyKC0tcGluayksMCA2cHggMjVweCByZ2JhKDAsMCwwLC45KX0udmVyc2lvbnttYXJnaW4tbGVmdDphdXRvO3BhZGRpbmc6NnB4IDEwcHg7Ym9yZGVyLXJhZGl1czo5OTlweDtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4yOCk7YmFja2dyb3VuZDpyZ2JhKDAsMjE2LDI1NSwuMDgpO2NvbG9yOnZhcigtLWN5YW4yKTtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5NTA7Ym94LXNoYWRvdzowIDAgMThweCByZ2JhKDAsMjE2LDI1NSwuMTApfQoubG9nb0Zsb3dlcntwb3NpdGlvbjpyZWxhdGl2ZTt3aWR0aDo0OXB4O2hlaWdodDo0OXB4O2ZsZXg6MCAwIGF1dG87ZmlsdGVyOmRyb3Atc2hhZG93KDAgMCAxMXB4IHJnYmEoMCwyMTYsMjU1LC4zNSkpIHNhdHVyYXRlKDEuMTgpfS5sb2dvRmxvd2VyIC5wZXRhbHtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjE4cHg7dG9wOjJweDt3aWR0aDoxN3B4O2hlaWdodDoyOXB4O2JvcmRlci1yYWRpdXM6MTRweCAxNHB4IDdweCA3cHg7dHJhbnNmb3JtLW9yaWdpbjo3cHggMjNweDttaXgtYmxlbmQtbW9kZTpzY3JlZW59LmxvZ29GbG93ZXIgLnAxe2JhY2tncm91bmQ6I2ZmNTQ1NDt0cmFuc2Zvcm06cm90YXRlKDBkZWcpIHRyYW5zbGF0ZVkoLTFweCkgc2tld1goLThkZWcpfS5sb2dvRmxvd2VyIC5wMntiYWNrZ3JvdW5kOiNmZmJiMzE7dHJhbnNmb3JtOnJvdGF0ZSg2MGRlZykgdHJhbnNsYXRlWSgwKSBza2V3WCg5ZGVnKX0ubG9nb0Zsb3dlciAucDN7YmFja2dyb3VuZDojNzlkZjRjO3RyYW5zZm9ybTpyb3RhdGUoMTIwZGVnKSB0cmFuc2xhdGVZKDFweCkgc2tld1goLThkZWcpfS5sb2dvRmxvd2VyIC5wNHtiYWNrZ3JvdW5kOiMyN2Q2Yzc7dHJhbnNmb3JtOnJvdGF0ZSgxODBkZWcpIHRyYW5zbGF0ZVkoLTFweCkgc2tld1goOGRlZyl9LmxvZ29GbG93ZXIgLnA1e2JhY2tncm91bmQ6IzQxOGNmZjt0cmFuc2Zvcm06cm90YXRlKDI0MGRlZykgdHJhbnNsYXRlWSgxcHgpIHNrZXdYKC0xMGRlZyl9LmxvZ29GbG93ZXIgLnA2e2JhY2tncm91bmQ6I2RmNjhmZjt0cmFuc2Zvcm06cm90YXRlKDMwMGRlZykgdHJhbnNsYXRlWSgtMXB4KSBza2V3WCg5ZGVnKX0ubG9nb0Zsb3dlcjpiZWZvcmV7Y29udGVudDoiIjtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDo2cHg7Ym9yZGVyLXJhZGl1czo1MCU7Ym94LXNoYWRvdzozcHggMCA4cHggcmdiYSgyNTUsNzcsMTY2LC40NSksLTNweCAwIDhweCByZ2JhKDAsMjE2LDI1NSwuNSk7ZmlsdGVyOmJsdXIoMXB4KX0ubG9nb0Zsb3dlcjphZnRlcntjb250ZW50OiIiO3Bvc2l0aW9uOmFic29sdXRlO2luc2V0OjE2cHg7Ym9yZGVyOjJweCBzb2xpZCByZ2JhKDI0NSwyNTMsMjU1LC44OCk7Ym9yZGVyLXJhZGl1czo1MCU7Ym94LXNoYWRvdzowIDAgOXB4IHJnYmEoMCwyMTYsMjU1LC45KX0KLnNpZGVQcmltYXJ5LC5zaWRlU2Vjb25kYXJ5e2hlaWdodDo1NHB4O3dpZHRoOjEwMCU7Zm9udC1zaXplOjE0cHh9LnNpZGVQcmltYXJ5e2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMDk2MmJkLCMwMGE5YzgpO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuODgpO2JveC1zaGFkb3c6MCAwIDI4cHggcmdiYSgwLDIxNiwyNTUsLjIxKX0KLnNlY3Rpb25MYWJlbHttYXJnaW4tdG9wOjhweDtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuO2NvbG9yOiNjNGQ0ZTI7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwO2xldHRlci1zcGFjaW5nOi4wOGVtO3RleHQtdHJhbnNmb3JtOnVwcGVyY2FzZX0ucHJvamVjdExpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6MTBweDtvdmVyZmxvdzphdXRvO21pbi1oZWlnaHQ6MDtwYWRkaW5nLXJpZ2h0OjJweH0ucHJvamVjdENhcmR7cG9zaXRpb246cmVsYXRpdmU7cGFkZGluZzoxNXB4IDE0cHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoMTMsMjksNDUsLjk0KSxyZ2JhKDcsMTgsMzAsLjk0KSk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDYyLDExMywxNTEsLjMyKTtib3JkZXItcmFkaXVzOjE1cHg7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTZzIGVhc2V9LnByb2plY3RDYXJkOmhvdmVyLC5wcm9qZWN0Q2FyZC5hY3RpdmV7Ym9yZGVyLWNvbG9yOnZhcigtLWN5YW4pO2JveC1zaGFkb3c6MCAwIDI0cHggcmdiYSgwLDIxNiwyNTUsLjE3KX0ucHJvamVjdENhcmRUaXRsZXtwYWRkaW5nLXJpZ2h0OjI0cHg7Zm9udC13ZWlnaHQ6OTAwO2ZvbnQtc2l6ZToxNHB4O3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30ucHJvamVjdERhdGV7bWFyZ2luLXRvcDo2cHg7Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxMnB4fS5wcm9qZWN0U3RhdHN7bWFyZ2luLXRvcDo5cHg7Y29sb3I6IzllYjRjNjtmb250LXNpemU6MTJweH0ucHJvamVjdFN0YXRzIC5kb3R7Y29sb3I6dmFyKC0tY3lhbil9LnByb2plY3RNZW51e3Bvc2l0aW9uOmFic29sdXRlO3JpZ2h0OjlweDt0b3A6MTBweDt3aWR0aDoyOHB4O2hlaWdodDozMnB4O2JvcmRlcjowO2JhY2tncm91bmQ6dHJhbnNwYXJlbnQ7Zm9udC1zaXplOjIwcHg7Ym94LXNoYWRvdzpub25lfS5wcm9qZWN0RGVsZXRle3dpZHRoOjEwMCU7aGVpZ2h0OjM0cHg7bWFyZ2luLXRvcDoxMHB4O2ZvbnQtc2l6ZToxMnB4O2Rpc3BsYXk6bm9uZX0ucHJvamVjdENhcmQubWVudU9wZW4gLnByb2plY3REZWxldGV7ZGlzcGxheTpibG9ja30KLmxlZnRGb290ZXJ7bWFyZ2luLXRvcDphdXRvO2NvbG9yOiM4Mjk2YTg7Zm9udC1zaXplOjEycHg7bGluZS1oZWlnaHQ6MS42NX0uZm9vdGVyTGlua3tkaXNwbGF5OmJsb2NrO21hcmdpbi10b3A6MTBweDtjb2xvcjp2YXIoLS1jeWFuKTt0ZXh0LWRlY29yYXRpb246bm9uZX0KLndvcmtzcGFjZXttaW4td2lkdGg6MDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1yb3dzOjkxcHggbWlubWF4KDM1MHB4LDFmcikgMjI4cHg7YmFja2dyb3VuZDpyZ2JhKDIsOCwxNCwuNTApfQoudG9wQmFye2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjE2cHg7cGFkZGluZzoxNHB4IDE5cHg7Ym9yZGVyLWJvdHRvbToxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjEzKTtiYWNrZ3JvdW5kOnJnYmEoMywxMCwxOCwuODQpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDE4cHgpO3otaW5kZXg6OH0udGl0bGVBcmVhe21pbi13aWR0aDozMjBweDttYXgtd2lkdGg6NDMwcHh9LmpvdXJuZXlUaXRsZVJvd3tkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDo5cHh9LmpvdXJuZXlUaXRsZXtmb250LXNpemU6MjJweDtmb250LXdlaWdodDo5NTA7d2hpdGUtc3BhY2U6bm93cmFwO292ZXJmbG93OmhpZGRlbjt0ZXh0LW92ZXJmbG93OmVsbGlwc2lzfS5lZGl0VGl0bGV7Ym9yZGVyOjA7YmFja2dyb3VuZDp0cmFuc3BhcmVudDtjb2xvcjp2YXIoLS1tdXRlZCk7cGFkZGluZzoycHg7Ym94LXNoYWRvdzpub25lfS5qb3VybmV5TWV0YXtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMXB4O21hcmdpbi10b3A6NnB4O2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTJweH0uam91cm5leU1ldGEgLmxpdmVEb3R7d2lkdGg6N3B4O2hlaWdodDo3cHg7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDp2YXIoLS1ncmVlbik7Ym94LXNoYWRvdzowIDAgOHB4IHJnYmEoNTcsMjE3LDE0OSwuNil9LnRvcFNwYWNlcntmbGV4OjF9LnByZXNlbnRCdXR0b257aGVpZ2h0OjU0cHg7bWluLXdpZHRoOjI2NXB4O3BhZGRpbmc6MCAyNHB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjNjMzYmZmLCMwMGFmZDApO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuODUpO2JveC1zaGFkb3c6MCAwIDMycHggcmdiYSgwLDIxNiwyNTUsLjI4KTtmb250LXNpemU6MTVweH0ucHJlc2VudEJ1dHRvbiBzcGFue2Rpc3BsYXk6YmxvY2s7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6NjUwO29wYWNpdHk6Ljg0O21hcmdpbi10b3A6MnB4fS50b3BBY3Rpb257aGVpZ2h0OjU0cHg7bWluLXdpZHRoOjE0NXB4O3BhZGRpbmc6MCAxNnB4fS5nZWFyQnV0dG9ue3dpZHRoOjU0cHg7bWluLXdpZHRoOjU0cHg7aGVpZ2h0OjU0cHg7Zm9udC1zaXplOjIwcHh9Ci5tYXBab25le3Bvc2l0aW9uOnJlbGF0aXZlO21pbi1oZWlnaHQ6MDtwYWRkaW5nOjAgOHB4IDAgMH0ubWFwRnJhbWV7cG9zaXRpb246YWJzb2x1dGU7aW5zZXQ6MCA4cHggMCAwO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjE4KTtib3JkZXItcmFkaXVzOjE4cHg7b3ZlcmZsb3c6aGlkZGVuO2JveC1zaGFkb3c6dmFyKC0tc2hhZG93KTtiYWNrZ3JvdW5kOiM5Y2I2YmV9Lm1hcENhbnZhc3twb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowfS5tYXBTaGFkZXtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowO3BvaW50ZXItZXZlbnRzOm5vbmU7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoMSw3LDEzLC4wNCkscmdiYSgxLDcsMTMsLjAzKSl9Lm1hcFRvb2xze3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6MTdweDt0b3A6MThweDt6LWluZGV4OjQ7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6OXB4fS5tYXBUb29se3dpZHRoOjQ3cHg7aGVpZ2h0OjQ3cHg7ZGlzcGxheTpncmlkO3BsYWNlLWl0ZW1zOmNlbnRlcjtib3JkZXItcmFkaXVzOjEzcHg7YmFja2dyb3VuZDpyZ2JhKDcsMTksMzEsLjkyKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjksMTE5LDE1NCwuNDIpO2JveC1zaGFkb3c6MCAxMnB4IDI4cHggcmdiYSgwLDAsMCwuMjgpO2NvbG9yOiNlN2Y3ZmZ9Lm1hcFRvb2wuYWN0aXZle2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMGQ5YmMzLCMwMGQ0ZWUpO2JvcmRlci1jb2xvcjojNWFmM2ZmfS5tYXBab29tR3JvdXB7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjttYXJnaW4tdG9wOjRweH0ubWFwWm9vbUdyb3VwIC5tYXBUb29se2JvcmRlci1yYWRpdXM6MH0ubWFwWm9vbUdyb3VwIC5tYXBUb29sOmZpcnN0LWNoaWxke2JvcmRlci1yYWRpdXM6MTNweCAxM3B4IDAgMH0ubWFwWm9vbUdyb3VwIC5tYXBUb29sOmxhc3QtY2hpbGR7Ym9yZGVyLXJhZGl1czowIDAgMTNweCAxM3B4O2JvcmRlci10b3A6MH0uZmlsdGVyQ2hpcHtwb3NpdGlvbjphYnNvbHV0ZTtyaWdodDoyMHB4O3RvcDoyMHB4O3otaW5kZXg6NTtkaXNwbGF5Om5vbmU7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMHB4O3BhZGRpbmc6MTBweCAxMXB4IDEwcHggMTRweDtib3JkZXItcmFkaXVzOjE0cHg7YmFja2dyb3VuZDpyZ2JhKDUsMTYsMjcsLjk0KTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzMsMTI1LDE2MSwuNDIpO2JveC1zaGFkb3c6MCAxNXB4IDM2cHggcmdiYSgwLDAsMCwuMzIpO2ZvbnQtc2l6ZToxMnB4fS5maWx0ZXJDaGlwLnNob3d7ZGlzcGxheTpmbGV4fS5maWx0ZXJDaGlwIGJ1dHRvbnt3aWR0aDozMHB4O2hlaWdodDozMHB4O3BhZGRpbmc6MH0KLnBob3RvTWFya2Vye3Bvc2l0aW9uOnJlbGF0aXZlO3dpZHRoOjU0cHg7aGVpZ2h0OjU0cHg7Ym9yZGVyLXJhZGl1czo1MCU7cGFkZGluZzozcHg7YmFja2dyb3VuZDojZWRmYWZmO2JvcmRlcjozcHggc29saWQgdmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMCAycHggcmdiYSgyNTUsMjU1LDI1NSwuNTUpLDAgMCAyMnB4IHJnYmEoMCwyMTYsMjU1LC42NSk7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTVzIGVhc2V9LnBob3RvTWFya2VyOmhvdmVyLC5waG90b01hcmtlci5hY3RpdmV7dHJhbnNmb3JtOnNjYWxlKDEuMTEpO2JvcmRlci1jb2xvcjp3aGl0ZTtib3gtc2hhZG93OjAgMCAwIDNweCB2YXIoLS1jeWFuKSwwIDAgMjhweCByZ2JhKDAsMjE2LDI1NSwuODUpfS5waG90b01hcmtlciBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmJsb2NrO29iamVjdC1maXQ6Y292ZXI7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDojMTczMTQ5fS5waG90b01hcmtlciAuZmFsbGJhY2t7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlci1yYWRpdXM6NTAlO2JhY2tncm91bmQ6cmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCAzMCUgMzAlLCMzZjgxOWEsIzBhMjYzOSk7Zm9udC13ZWlnaHQ6OTUwfS5tYXJrZXJCYWRnZXtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjUwJTt0b3A6LTE2cHg7dHJhbnNmb3JtOnRyYW5zbGF0ZVgoLTUwJSk7bWluLXdpZHRoOjI4cHg7aGVpZ2h0OjI4cHg7cGFkZGluZzowIDZweDtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlci1yYWRpdXM6OTk5cHg7YmFja2dyb3VuZDojMDcxMzFmO2NvbG9yOiNmZmY7Ym9yZGVyOjJweCBzb2xpZCByZ2JhKDI1NSwyNTUsMjU1LC43Mik7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwO2JveC1zaGFkb3c6MCA1cHggMTVweCByZ2JhKDAsMCwwLC40NSl9Ci5tYXBsaWJyZWdsLXBvcHVwLWNvbnRlbnR7cGFkZGluZzowIWltcG9ydGFudDtiYWNrZ3JvdW5kOnRyYW5zcGFyZW50IWltcG9ydGFudDtib3JkZXItcmFkaXVzOjE4cHghaW1wb3J0YW50O2JveC1zaGFkb3c6bm9uZSFpbXBvcnRhbnR9Lm1hcGxpYnJlZ2wtcG9wdXAtdGlwe2JvcmRlci10b3AtY29sb3I6IzA3MTMxZiFpbXBvcnRhbnR9Lm1hcGxpYnJlZ2wtcG9wdXAtY2xvc2UtYnV0dG9ue3otaW5kZXg6NDtyaWdodDo4cHghaW1wb3J0YW50O3RvcDo4cHghaW1wb3J0YW50O3dpZHRoOjI4cHg7aGVpZ2h0OjI4cHg7Ym9yZGVyLXJhZGl1czo1MCUhaW1wb3J0YW50O2JhY2tncm91bmQ6cmdiYSg4LDIwLDMzLC44MikhaW1wb3J0YW50O2NvbG9yOndoaXRlIWltcG9ydGFudDtmb250LXNpemU6MThweCFpbXBvcnRhbnQ7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDI1NSwyNTUsMjU1LC4yMikhaW1wb3J0YW50fS5zdG9wUG9wdXB7d2lkdGg6MzMwcHg7Ym9yZGVyLXJhZGl1czoxOHB4O292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOiMwNzEzMWY7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuNDIpO2JveC1zaGFkb3c6MCAwIDQwcHggcmdiYSgwLDIxNiwyNTUsLjI1KSwwIDI1cHggNjVweCByZ2JhKDAsMCwwLC40OCl9LnN0b3BQb3B1cEltYWdle2hlaWdodDoxODVweDtiYWNrZ3JvdW5kOiMxMDJhNDB9LnN0b3BQb3B1cEltYWdlIGltZ3t3aWR0aDoxMDAlO2hlaWdodDoxMDAlO2Rpc3BsYXk6YmxvY2s7b2JqZWN0LWZpdDpjb3Zlcn0uc3RvcFBvcHVwQm9keXtwYWRkaW5nOjEzcHggMTVweCAxNXB4fS5wb3B1cEtpY2tlcntkaXNwbGF5OmlubGluZS1mbGV4O3BhZGRpbmc6NXB4IDhweDtib3JkZXItcmFkaXVzOjhweDtiYWNrZ3JvdW5kOnJnYmEoMCwyMTYsMjU1LC4xNSk7Y29sb3I6dmFyKC0tY3lhbik7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6OTAwfS5wb3B1cFRpdGxle21hcmdpbi10b3A6OXB4O2ZvbnQtc2l6ZToxOXB4O2ZvbnQtd2VpZ2h0Ojk1MH0ucG9wdXBNZXRhe21hcmdpbi10b3A6NnB4O2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTJweH0ucG9wdXBCdXR0b25ze2Rpc3BsYXk6ZmxleDtnYXA6OHB4O21hcmdpbi10b3A6MTJweH0ucG9wdXBCdXR0b25zIGJ1dHRvbntoZWlnaHQ6NDBweDtmbGV4OjE7Zm9udC1zaXplOjEycHh9LnBvcHVwQnV0dG9ucyAuZGFuZ2Vye2ZsZXg6MCAwIDQycHg7Y29sb3I6dmFyKC0tcmVkKX0KLm1lZGlhU3RyaXB7bWluLXdpZHRoOjA7cGFkZGluZzoxM3B4IDE3cHggMTVweDtib3JkZXItdG9wOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMTIpO2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDE4MGRlZyxyZ2JhKDQsMTIsMjAsLjcyKSxyZ2JhKDMsOSwxNiwuOTUpKX0ubWVkaWFIZWFkZXJ7aGVpZ2h0OjMxcHg7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTFweH0ubWVkaWFUaXRsZXtmb250LXNpemU6MTRweDtmb250LXdlaWdodDo5NTB9Lm1lZGlhQ291bnR7Zm9udC1zaXplOjEycHg7Y29sb3I6dmFyKC0tbXV0ZWQpfS5tZWRpYUhlYWRlclNwYWNlcntmbGV4OjF9LnRpbnlCdXR0b257d2lkdGg6MzFweDtoZWlnaHQ6MzFweDtwYWRkaW5nOjA7Ym9yZGVyLXJhZGl1czoxMHB4fS5nYWxsZXJ5e2hlaWdodDoxNjRweDtkaXNwbGF5OmZsZXg7Z2FwOjEwcHg7b3ZlcmZsb3cteDphdXRvO292ZXJmbG93LXk6aGlkZGVuO3BhZGRpbmc6OHB4IDFweCA0cHg7c2Nyb2xsYmFyLXdpZHRoOnRoaW59Lm1lZGlhVGlsZXtwb3NpdGlvbjpyZWxhdGl2ZTtmbGV4OjAgMCAyMThweDtoZWlnaHQ6MTQ1cHg7Ym9yZGVyLXJhZGl1czoxM3B4O292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOiMxMDIyMzU7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDcxLDEyMywxNjAsLjM1KTtjdXJzb3I6cG9pbnRlcjt0cmFuc2l0aW9uOi4xNnMgZWFzZX0ubWVkaWFUaWxlOmhvdmVyLC5tZWRpYVRpbGUuYWN0aXZle2JvcmRlci1jb2xvcjp2YXIoLS1jeWFuKTtib3gtc2hhZG93OjAgMCAyMXB4IHJnYmEoMCwyMTYsMjU1LC4yNCk7dHJhbnNmb3JtOnRyYW5zbGF0ZVkoLTJweCl9Lm1lZGlhVGlsZSBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtvYmplY3QtZml0OmNvdmVyO2Rpc3BsYXk6YmxvY2t9Lm1lZGlhVGlsZU5hbWV7cG9zaXRpb246YWJzb2x1dGU7bGVmdDowO3JpZ2h0OjA7Ym90dG9tOjA7cGFkZGluZzoyNXB4IDEwcHggOXB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KHRyYW5zcGFyZW50LHJnYmEoMSw2LDExLC45KSk7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6ODUwO3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30KLnJpZ2h0UmFpbHttaW4td2lkdGg6MDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSg0LDEyLDIxLC45NykscmdiYSgyLDgsMTUsLjk5KSk7Ym9yZGVyLWxlZnQ6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4xNCk7cGFkZGluZzoxNXB4IDE1cHggMTdweDtkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO292ZXJmbG93OmhpZGRlbn0ucmlnaHRUb3B7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtoZWlnaHQ6NDBweH0ucmlnaHRUaXRsZXtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5NTA7dGV4dC10cmFuc2Zvcm06dXBwZXJjYXNlO2xldHRlci1zcGFjaW5nOi4wNGVtfS5yaWdodENvdW50e2NvbG9yOnZhcigtLW11dGVkKTttYXJnaW4tbGVmdDo1cHh9LnJpZ2h0U2VhcmNoe21hcmdpbi1sZWZ0OmF1dG87d2lkdGg6MzVweDtoZWlnaHQ6MzVweDtwYWRkaW5nOjA7YmFja2dyb3VuZDp0cmFuc3BhcmVudDtib3JkZXI6MDtib3gtc2hhZG93Om5vbmV9LnN0b3BTZWFyY2hXcmFwe2Rpc3BsYXk6bm9uZTttYXJnaW4tYm90dG9tOjEwcHh9LnN0b3BTZWFyY2hXcmFwLnNob3d7ZGlzcGxheTpibG9ja30uc3RvcExpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6N3B4O292ZXJmbG93OmF1dG87bWluLWhlaWdodDowO2ZsZXg6MTtwYWRkaW5nOjFweCAycHggOHB4IDB9LnN0b3BDYXJke2JvcmRlci1yYWRpdXM6MTJweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgxMywyOCw0NCwuOTIpLHJnYmEoOCwyMCwzMywuOTIpKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjEsMTA4LDE0MywuMzApO292ZXJmbG93OmhpZGRlbjt0cmFuc2l0aW9uOi4xNXMgZWFzZX0uc3RvcENhcmQ6aG92ZXIsLnN0b3BDYXJkLmFjdGl2ZXtib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzppbnNldCA0cHggMCAwIHZhcigtLWN5YW4pLDAgMCAxOHB4IHJnYmEoMCwyMTYsMjU1LC4xMyl9LnN0b3BTdW1tYXJ5e21pbi1oZWlnaHQ6NThweDtwYWRkaW5nOjEwcHggMTFweDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjI4cHggMWZyIDIycHg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDo4cHg7Y3Vyc29yOnBvaW50ZXJ9LnN0b3BOdW1iZXJ7Zm9udC1zaXplOjEzcHg7Zm9udC13ZWlnaHQ6OTUwO3RleHQtYWxpZ246Y2VudGVyfS5zdG9wTmFtZXtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5MDA7d2hpdGUtc3BhY2U6bm93cmFwO292ZXJmbG93OmhpZGRlbjt0ZXh0LW92ZXJmbG93OmVsbGlwc2lzfS5zdG9wTWV0YXttYXJnaW4tdG9wOjRweDtjb2xvcjp2YXIoLS1tdXRlZCk7Zm9udC1zaXplOjExcHh9LnN0b3BDaGV2cm9ue2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MThweDt0cmFuc2l0aW9uOi4xNXN9LnN0b3BDYXJkLm9wZW4gLnN0b3BDaGV2cm9ue3RyYW5zZm9ybTpyb3RhdGUoOTBkZWcpfS5zdG9wQ29udHJvbHN7ZGlzcGxheTpub25lO3BhZGRpbmc6MCAxMXB4IDExcHggNDdweDtnYXA6NnB4O2ZsZXgtd3JhcDp3cmFwfS5zdG9wQ2FyZC5vcGVuIC5zdG9wQ29udHJvbHN7ZGlzcGxheTpmbGV4fS5zdG9wQ29udHJvbHMgYnV0dG9ue2hlaWdodDozMnB4O3BhZGRpbmc6MCA5cHg7Zm9udC1zaXplOjEwcHh9LmFkZFN0b3BCdXR0b257aGVpZ2h0OjQycHg7d2lkdGg6MTAwJTttYXJnaW46NHB4IDAgMTJweH0KLmV4cG9ydEJveHtmbGV4OjAgMCBhdXRvO2JvcmRlcjoxcHggc29saWQgcmdiYSg2MiwxMTEsMTQ4LC4zMCk7Ym9yZGVyLXJhZGl1czoxNHB4O2JhY2tncm91bmQ6cmdiYSg4LDE5LDMxLC45MCk7b3ZlcmZsb3c6aGlkZGVufS5leHBvcnRIZWFkZXJ7aGVpZ2h0OjQ4cHg7cGFkZGluZzowIDEzcHg7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtqdXN0aWZ5LWNvbnRlbnQ6c3BhY2UtYmV0d2Vlbjtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5NTA7Y3Vyc29yOnBvaW50ZXJ9LmV4cG9ydEJvZHl7cGFkZGluZzowIDEycHggMTJweH0uZXhwb3J0Qm94LmNvbGxhcHNlZCAuZXhwb3J0Qm9keXtkaXNwbGF5Om5vbmV9LmV4cG9ydFRhYnN7ZGlzcGxheTpncmlkO2dyaWQtdGVtcGxhdGUtY29sdW1uczoxZnIgMWZyIDFmcjtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjMsMTEzLDE1MCwuMzMpO2JvcmRlci1yYWRpdXM6MTBweDtvdmVyZmxvdzpoaWRkZW47bWFyZ2luOjdweCAwIDEycHh9LmV4cG9ydFRhYnMgYnV0dG9ue2JvcmRlcjowO2JvcmRlci1yYWRpdXM6MDtoZWlnaHQ6MzZweDtiYWNrZ3JvdW5kOiMwNzEzMWY7Zm9udC1zaXplOjEwcHh9LmV4cG9ydFRhYnMgYnV0dG9uLmFjdGl2ZXtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxMzVkZWcsIzA4NzljMywjMDBhOWM5KTtib3gtc2hhZG93Om5vbmV9LmZpZWxkTGFiZWx7ZGlzcGxheTpibG9jaztmb250LXNpemU6MTBweDtjb2xvcjp2YXIoLS1tdXRlZCk7bWFyZ2luOjEwcHggMCA1cHh9LmF1ZGlvUm93e2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OnNwYWNlLWJldHdlZW47Y29sb3I6dmFyKC0tc29mdCk7Zm9udC1zaXplOjExcHh9LnN3aXRjaHt3aWR0aDozOXB4O2hlaWdodDoyMXB4O2JvcmRlci1yYWRpdXM6OTk5cHg7YmFja2dyb3VuZDojMjAzNzRhO2JvcmRlcjoxcHggc29saWQgIzM1NTM2YTtwb3NpdGlvbjpyZWxhdGl2ZTtjdXJzb3I6cG9pbnRlcn0uc3dpdGNoOmFmdGVye2NvbnRlbnQ6IiI7cG9zaXRpb246YWJzb2x1dGU7dG9wOjJweDtsZWZ0OjJweDt3aWR0aDoxNXB4O2hlaWdodDoxNXB4O2JvcmRlci1yYWRpdXM6NTAlO2JhY2tncm91bmQ6I2RjZWFmNDt0cmFuc2l0aW9uOi4xNnN9LnN3aXRjaC5vbntiYWNrZ3JvdW5kOiMwMGE5Y2U7Ym9yZGVyLWNvbG9yOiMyMGUxZmZ9LnN3aXRjaC5vbjphZnRlcntsZWZ0OjIwcHh9LmF1ZGlvSW5wdXR7ZGlzcGxheTpub25lfS5yZW5kZXJCdXR0b257d2lkdGg6MTAwJTtoZWlnaHQ6NTVweDttYXJnaW4tdG9wOjExcHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCMwODdkYTMsIzExYmFjZSk7Ym9yZGVyLWNvbG9yOnJnYmEoMCwyMTYsMjU1LC43NSk7Zm9udC1zaXplOjE0cHh9LnJlbmRlckJ1dHRvbiBzcGFue2Rpc3BsYXk6YmxvY2s7Zm9udC1zaXplOjEwcHg7Zm9udC13ZWlnaHQ6NjUwO29wYWNpdHk6Ljg1O21hcmdpbi10b3A6MnB4fQoubW9kYWx7cG9zaXRpb246Zml4ZWQ7aW5zZXQ6MDt6LWluZGV4OjEwMDA7ZGlzcGxheTpub25lO2FsaWduLWl0ZW1zOmNlbnRlcjtqdXN0aWZ5LWNvbnRlbnQ6Y2VudGVyO3BhZGRpbmc6MjRweDtiYWNrZ3JvdW5kOnJnYmEoMCw0LDksLjc1KTtiYWNrZHJvcC1maWx0ZXI6Ymx1cig3cHgpfS5tb2RhbC5zaG93e2Rpc3BsYXk6ZmxleH0ubW9kYWxDYXJke3dpZHRoOm1pbig3MjBweCw5NHZ3KTttYXgtaGVpZ2h0Ojkwdmg7b3ZlcmZsb3c6YXV0bztwYWRkaW5nOjIxcHg7Ym9yZGVyLXJhZGl1czoxOXB4O2JhY2tncm91bmQ6IzA3MTMxZjtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4zNSk7Ym94LXNoYWRvdzowIDAgNjBweCByZ2JhKDAsMjE2LDI1NSwuMTgpLDAgMzVweCAxMDBweCByZ2JhKDAsMCwwLC41NSl9Lm1vZGFsVGl0bGV7Zm9udC1zaXplOjIxcHg7Zm9udC13ZWlnaHQ6OTUwO21hcmdpbi1ib3R0b206MTVweH0uZm9ybUdyaWR7ZGlzcGxheTpncmlkO2dhcDoxMXB4fS50d29Db2x7ZGlzcGxheTpncmlkO2dyaWQtdGVtcGxhdGUtY29sdW1uczoxZnIgMWZyO2dhcDoxMXB4fS5tb2RhbEFjdGlvbnN7ZGlzcGxheTpmbGV4O2p1c3RpZnktY29udGVudDpmbGV4LWVuZDtnYXA6OXB4O21hcmdpbi10b3A6NnB4fS5tb2RhbEFjdGlvbnMgYnV0dG9ue2hlaWdodDo0MnB4O3BhZGRpbmc6MCAxNnB4fS5wcmltYXJ5e2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMDc1ZGI0LCMwMGFlY2IpO2JvcmRlci1jb2xvcjp2YXIoLS1jeWFuKX0KLnRvYXN0e3Bvc2l0aW9uOmZpeGVkO2xlZnQ6MzA1cHg7Ym90dG9tOjE4cHg7ei1pbmRleDozMDAwO2Rpc3BsYXk6bm9uZTtwYWRkaW5nOjExcHggMTRweDtib3JkZXItcmFkaXVzOjEycHg7YmFja2dyb3VuZDpyZ2JhKDYsMTksMzEsLjk1KTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4zMik7Ym94LXNoYWRvdzowIDE1cHggNDBweCByZ2JhKDAsMCwwLC4zNSk7Zm9udC1zaXplOjEycHh9LnRvYXN0LnNob3d7ZGlzcGxheTpibG9ja30KLnByZXNlbnRPdmVybGF5e3Bvc2l0aW9uOmZpeGVkO2luc2V0OjA7ei1pbmRleDoyMjAwO2Rpc3BsYXk6bm9uZTtiYWNrZ3JvdW5kOiMwMjA3MTB9LnByZXNlbnRPdmVybGF5LnNob3d7ZGlzcGxheTpncmlkO2dyaWQtdGVtcGxhdGUtcm93czo3MnB4IG1pbm1heCgwLDFmcikgMTcwcHh9LnByZXNlbnRIZWFkZXJ7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTNweDtwYWRkaW5nOjEwcHggMThweDtib3JkZXItYm90dG9tOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMTYpO2JhY2tncm91bmQ6cmdiYSgzLDEwLDE4LC45MCl9LnByZXNlbnRIZWFkZXJUaXRsZXtmb250LXNpemU6MjBweDtmb250LXdlaWdodDo5NTB9LnByZXNlbnRIZWFkZXJNZXRhe2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTFweDttYXJnaW4tdG9wOjNweH0ucHJlc2VudEhlYWRlclNwYWNlcntmbGV4OjF9LnByZXNlbnRNYWlue3Bvc2l0aW9uOnJlbGF0aXZlO21pbi1oZWlnaHQ6MH0ucHJlc2VudE1hcHtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowfS5wcmVzZW50U3RvcFJhaWx7cG9zaXRpb246YWJzb2x1dGU7bGVmdDoxOHB4O3RvcDoxOHB4O2JvdHRvbToxOHB4O3dpZHRoOjI0MHB4O3otaW5kZXg6NDtwYWRkaW5nOjEycHg7Ym9yZGVyLXJhZGl1czoxNnB4O2JhY2tncm91bmQ6cmdiYSg0LDE0LDI0LC44NCk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMjQpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDE1cHgpO292ZXJmbG93OmF1dG99LnByZXNlbnRTdG9wSXRlbXtwYWRkaW5nOjEwcHg7Ym9yZGVyLXJhZGl1czoxMHB4O2NvbG9yOiNiNGM4ZDg7Zm9udC1zaXplOjEycHg7Y3Vyc29yOnBvaW50ZXJ9LnByZXNlbnRTdG9wSXRlbS5hY3RpdmV7YmFja2dyb3VuZDpyZ2JhKDAsMjE2LDI1NSwuMTQpO2NvbG9yOndoaXRlO2JveC1zaGFkb3c6aW5zZXQgM3B4IDAgMCB2YXIoLS1jeWFuKX0ucHJlc2VudFBob3RvQ2FyZHtwb3NpdGlvbjphYnNvbHV0ZTtyaWdodDoyMnB4O3RvcDoyMnB4O3dpZHRoOjM1MHB4O3otaW5kZXg6NTtib3JkZXItcmFkaXVzOjE4cHg7b3ZlcmZsb3c6aGlkZGVuO2JhY2tncm91bmQ6cmdiYSg1LDE1LDI1LC45NCk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzQpO2JveC1zaGFkb3c6MCAwIDQycHggcmdiYSgwLDIxNiwyNTUsLjIwKSwwIDI1cHggNjBweCByZ2JhKDAsMCwwLC41KTtkaXNwbGF5Om5vbmV9LnByZXNlbnRQaG90b0NhcmQuc2hvd3tkaXNwbGF5OmJsb2NrfS5wcmVzZW50UGhvdG9DYXJkIGltZ3t3aWR0aDoxMDAlO2hlaWdodDoyMjBweDtvYmplY3QtZml0OmNvdmVyO2Rpc3BsYXk6YmxvY2t9LnByZXNlbnRQaG90b0JvZHl7cGFkZGluZzoxM3B4fS5wcmVzZW50UGhvdG9UaXRsZXtmb250LXNpemU6MTZweDtmb250LXdlaWdodDo5NTB9LnByZXNlbnRQaG90b01ldGF7Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxMXB4O21hcmdpbi10b3A6NHB4fS5wcmVzZW50SHVke3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6NTAlO2JvdHRvbToxOHB4O3RyYW5zZm9ybTp0cmFuc2xhdGVYKC01MCUpO3otaW5kZXg6NjtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDo4cHg7cGFkZGluZzo4cHg7Ym9yZGVyLXJhZGl1czoxNnB4O2JhY2tncm91bmQ6cmdiYSg0LDE0LDI0LC44Nik7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMjIpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDEycHgpfS5wcmVzZW50SHVkIGJ1dHRvbntoZWlnaHQ6NDJweDtwYWRkaW5nOjAgMTRweDtmb250LXNpemU6MTFweH0ucHJlc2VudEh1ZCAucGxheXttaW4td2lkdGg6MTEwcHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCM2MDNjZmYsIzAwYWRjYil9LnByZXNlbnRGaWxtc3RyaXB7cGFkZGluZzoxMnB4IDE4cHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLCMwNjExMWQsIzAyMDcxMSk7Ym9yZGVyLXRvcDoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjE0KTtkaXNwbGF5OmZsZXg7Z2FwOjEwcHg7b3ZlcmZsb3cteDphdXRvfS5wcmVzZW50VGh1bWJ7ZmxleDowIDAgMTkwcHg7aGVpZ2h0OjE0MHB4O2JvcmRlci1yYWRpdXM6MTNweDtvdmVyZmxvdzpoaWRkZW47Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDY5LDEyMSwxNTgsLjM0KTtjdXJzb3I6cG9pbnRlcjtwb3NpdGlvbjpyZWxhdGl2ZX0ucHJlc2VudFRodW1iLmFjdGl2ZXtib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMjFweCByZ2JhKDAsMjE2LDI1NSwuMjgpfS5wcmVzZW50VGh1bWIgaW1ne3dpZHRoOjEwMCU7aGVpZ2h0OjEwMCU7ZGlzcGxheTpibG9jaztvYmplY3QtZml0OmNvdmVyfS5wcmVzZW50VGh1bWJMYWJlbHtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDphdXRvIDAgMDtwYWRkaW5nOjI0cHggOHB4IDdweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCh0cmFuc3BhcmVudCxyZ2JhKDAsMCwwLC44NSkpO2ZvbnQtc2l6ZToxMHB4O2ZvbnQtd2VpZ2h0OjgwMH0KQG1lZGlhKG1heC13aWR0aDoxMzAwcHgpey5hcHBTaGVsbHtncmlkLXRlbXBsYXRlLWNvbHVtbnM6MjUwcHggbWlubWF4KDU4MHB4LDFmcikgMzIwcHh9LmxlZnRSYWlse3BhZGRpbmctbGVmdDoxM3B4O3BhZGRpbmctcmlnaHQ6MTNweH0ud29yZG1hcmt7Zm9udC1zaXplOjI3cHh9LnByZXNlbnRCdXR0b257bWluLXdpZHRoOjIyMHB4fS50aXRsZUFyZWF7bWluLXdpZHRoOjI0MHB4fS50b3BBY3Rpb257bWluLXdpZHRoOjExMHB4fS5tZWRpYVRpbGV7ZmxleC1iYXNpczoxODVweH19Cjwvc3R5bGU+CjwvaGVhZD4KPGJvZHk+CjxkaXYgY2xhc3M9ImFwcFNoZWxsIj4KICA8YXNpZGUgY2xhc3M9ImxlZnRSYWlsIj4KICAgIDxkaXYgY2xhc3M9ImJyYW5kTGluZSI+CiAgICAgIDxkaXYgY2xhc3M9ImxvZ29GbG93ZXIiPjxzcGFuIGNsYXNzPSJwZXRhbCBwMSI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMiI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMyI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNCI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNSI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNiI+PC9zcGFuPjwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJ3b3JkbWFyayI+dHJpcHB5PC9kaXY+PGRpdiBjbGFzcz0idmVyc2lvbiI+djEwLjIuMjwvZGl2PgogICAgPC9kaXY+CiAgICA8YnV0dG9uIGlkPSJuZXdJbW1pY2hCdXR0b24iIGNsYXNzPSJzaWRlUHJpbWFyeSI+77yLJm5ic3A7IE5ldyBJbW1pY2ggSm91cm5leTwvYnV0dG9uPgogICAgPGJ1dHRvbiBpZD0idXBsb2FkQnV0dG9uIiBjbGFzcz0ic2lkZVNlY29uZGFyeSI+4oenJm5ic3A7IFVwbG9hZCBNZWRpYTwvYnV0dG9uPgogICAgPGRpdiBjbGFzcz0ic2VjdGlvbkxhYmVsIj48c3Bhbj5Qcm9qZWN0czwvc3Bhbj48YnV0dG9uIGlkPSJwcm9qZWN0U2VhcmNoQnV0dG9uIiBjbGFzcz0icHJvamVjdE1lbnUiPuKMlTwvYnV0dG9uPjwvZGl2PgogICAgPGlucHV0IGlkPSJwcm9qZWN0U2VhcmNoIiBjbGFzcz0iaGlkZGVuIiBwbGFjZWhvbGRlcj0iU2VhcmNoIHByb2plY3Rz4oCmIj4KICAgIDxkaXYgaWQ9InByb2plY3RMaXN0IiBjbGFzcz0icHJvamVjdExpc3QiPjwvZGl2PgogICAgPGRpdiBjbGFzcz0ibGVmdEZvb3RlciI+UGxhbiwgb3JnYW5pemUsIGFuZCByZWxpdmUgeW91ciBhZHZlbnR1cmVzIG9uIHRoZSBtYXAuCiAgICAgIDxhIGNsYXNzPSJmb290ZXJMaW5rIiBocmVmPSIjIj7ilqMmbmJzcDsgRG9jdW1lbnRhdGlvbjwvYT48YSBjbGFzcz0iZm9vdGVyTGluayIgaHJlZj0iIyI+4peOJm5ic3A7IENoYW5nZWxvZzwvYT4KICAgIDwvZGl2PgogIDwvYXNpZGU+CgogIDxtYWluIGNsYXNzPSJ3b3Jrc3BhY2UiPgogICAgPGhlYWRlciBjbGFzcz0idG9wQmFyIj4KICAgICAgPGRpdiBjbGFzcz0idGl0bGVBcmVhIj48ZGl2IGNsYXNzPSJqb3VybmV5VGl0bGVSb3ciPjxkaXYgaWQ9ImpvdXJuZXlUaXRsZSIgY2xhc3M9ImpvdXJuZXlUaXRsZSI+Tm8gam91cm5leSBzZWxlY3RlZDwvZGl2PjxidXR0b24gaWQ9InJlbmFtZVByb2plY3RCdXR0b24iIGNsYXNzPSJlZGl0VGl0bGUiPuKcjjwvYnV0dG9uPjwvZGl2PjxkaXYgaWQ9ImpvdXJuZXlNZXRhIiBjbGFzcz0iam91cm5leU1ldGEiPkxvYWQgb3IgY3JlYXRlIGEgam91cm5leTwvZGl2PjwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJ0b3BTcGFjZXIiPjwvZGl2PgogICAgICA8YnV0dG9uIGlkPSJwcmVzZW50QnV0dG9uIiBjbGFzcz0icHJlc2VudEJ1dHRvbiI+4pa2Jm5ic3A7IFByZXNlbnQgSm91cm5leTxzcGFuPkltbWVyc2l2ZSByb3V0ZSBwbGF5YmFjazwvc3Bhbj48L2J1dHRvbj4KICAgICAgPGJ1dHRvbiBpZD0iZXhwb3J0SnVtcEJ1dHRvbiIgY2xhc3M9InRvcEFjdGlvbiI+4pajJm5ic3A7IEV4cG9ydDxicj48c3BhbiBjbGFzcz0ic21hbGwiPlJlbmRlciwgR1BYLCBhbmQgbW9yZSZuYnNwO+KMhDwvc3Bhbj48L2J1dHRvbj4KICAgICAgPGJ1dHRvbiBpZD0ic2V0dGluZ3NCdXR0b24iIGNsYXNzPSJnZWFyQnV0dG9uIj7impk8L2J1dHRvbj4KICAgICAgPGJ1dHRvbiBpZD0iYWNjb3VudEJ1dHRvbiIgY2xhc3M9InRvcEFjdGlvbiI+4pmZJm5ic3A7IEFjY291bnQmbmJzcDvijIQ8L2J1dHRvbj4KICAgIDwvaGVhZGVyPgoKICAgIDxzZWN0aW9uIGNsYXNzPSJtYXBab25lIj48ZGl2IGNsYXNzPSJtYXBGcmFtZSI+PGRpdiBpZD0ibWFwIiBjbGFzcz0ibWFwQ2FudmFzIj48L2Rpdj48ZGl2IGNsYXNzPSJtYXBTaGFkZSI+PC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9Im1hcFRvb2xzIj4KICAgICAgICA8YnV0dG9uIGlkPSJsb2NhdGVCdXR0b24iIGNsYXNzPSJtYXBUb29sIj7inqQ8L2J1dHRvbj48YnV0dG9uIGlkPSJsaWdodE1hcEJ1dHRvbiIgY2xhc3M9Im1hcFRvb2wgYWN0aXZlIj7il6s8L2J1dHRvbj48YnV0dG9uIGlkPSJkYXJrTWFwQnV0dG9uIiBjbGFzcz0ibWFwVG9vbCI+4peQPC9idXR0b24+PGJ1dHRvbiBpZD0ic2F0ZWxsaXRlTWFwQnV0dG9uIiBjbGFzcz0ibWFwVG9vbCI+4panPC9idXR0b24+CiAgICAgICAgPGRpdiBjbGFzcz0ibWFwWm9vbUdyb3VwIj48YnV0dG9uIGlkPSJ6b29tSW5CdXR0b24iIGNsYXNzPSJtYXBUb29sIj7vvIs8L2J1dHRvbj48YnV0dG9uIGlkPSJ6b29tT3V0QnV0dG9uIiBjbGFzcz0ibWFwVG9vbCI+4oiSPC9idXR0b24+PC9kaXY+CiAgICAgIDwvZGl2PgogICAgICA8ZGl2IGlkPSJmaWx0ZXJDaGlwIiBjbGFzcz0iZmlsdGVyQ2hpcCI+PHNwYW4+4pa+Jm5ic3A7IDxiIGlkPSJmaWx0ZXJDaGlwVGV4dCI+RmlsdGVyOiBBbGwgU3RvcHM8L2I+PC9zcGFuPjxidXR0b24gaWQ9ImNsZWFyRmlsdGVyQnV0dG9uIj7DlzwvYnV0dG9uPjwvZGl2PgogICAgPC9kaXY+PC9zZWN0aW9uPgoKICAgIDxzZWN0aW9uIGNsYXNzPSJtZWRpYVN0cmlwIj48ZGl2IGNsYXNzPSJtZWRpYUhlYWRlciI+PGRpdiBpZD0ibWVkaWFUaXRsZSIgY2xhc3M9Im1lZGlhVGl0bGUiPk1lZGlhPC9kaXY+PGRpdiBpZD0ibWVkaWFDb3VudCIgY2xhc3M9Im1lZGlhQ291bnQiPjwvZGl2PjxkaXYgY2xhc3M9Im1lZGlhSGVhZGVyU3BhY2VyIj48L2Rpdj48YnV0dG9uIGNsYXNzPSJ0aW55QnV0dG9uIj7ilqY8L2J1dHRvbj48YnV0dG9uIGNsYXNzPSJ0aW55QnV0dG9uIj7imLc8L2J1dHRvbj48L2Rpdj48ZGl2IGlkPSJnYWxsZXJ5IiBjbGFzcz0iZ2FsbGVyeSI+PC9kaXY+PC9zZWN0aW9uPgogIDwvbWFpbj4KCiAgPGFzaWRlIGNsYXNzPSJyaWdodFJhaWwiPgogICAgPGRpdiBjbGFzcz0icmlnaHRUb3AiPjxkaXYgY2xhc3M9InJpZ2h0VGl0bGUiPlN0b3BzIDxzcGFuIGlkPSJzdG9wQ291bnQiIGNsYXNzPSJyaWdodENvdW50Ij4oMCk8L3NwYW4+PC9kaXY+PGJ1dHRvbiBpZD0ic3RvcFNlYXJjaEJ1dHRvbiIgY2xhc3M9InJpZ2h0U2VhcmNoIj7ijJU8L2J1dHRvbj48L2Rpdj4KICAgIDxkaXYgaWQ9InN0b3BTZWFyY2hXcmFwIiBjbGFzcz0ic3RvcFNlYXJjaFdyYXAiPjxpbnB1dCBpZD0ic3RvcFNlYXJjaCIgcGxhY2Vob2xkZXI9IlNlYXJjaCBzdG9wc+KApiI+PC9kaXY+CiAgICA8ZGl2IGlkPSJzdG9wTGlzdCIgY2xhc3M9InN0b3BMaXN0Ij48L2Rpdj4KICAgIDxidXR0b24gaWQ9ImFkZFN0b3BCdXR0b24iIGNsYXNzPSJhZGRTdG9wQnV0dG9uIj7vvIsmbmJzcDsgQWRkIFN0b3AgTWFudWFsbHk8L2J1dHRvbj4KICAgIDxzZWN0aW9uIGlkPSJleHBvcnRCb3giIGNsYXNzPSJleHBvcnRCb3giPjxkaXYgaWQ9ImV4cG9ydEhlYWRlciIgY2xhc3M9ImV4cG9ydEhlYWRlciI+PHNwYW4+RXhwb3J0ICZhbXA7IFJlbmRlcjwvc3Bhbj48c3Bhbj7ijIM8L3NwYW4+PC9kaXY+PGRpdiBjbGFzcz0iZXhwb3J0Qm9keSI+CiAgICAgIDxzcGFuIGNsYXNzPSJmaWVsZExhYmVsIj5FeHBvcnQgRm9ybWF0PC9zcGFuPjxkaXYgY2xhc3M9ImV4cG9ydFRhYnMiPjxidXR0b24gY2xhc3M9ImFjdGl2ZSI+VmlkZW8gKE1QNCk8L2J1dHRvbj48YnV0dG9uIGlkPSJncHhCdXR0b24iPkdQWCBUcmFjazwvYnV0dG9uPjxidXR0b24gaWQ9ImltYWdlU2V0QnV0dG9uIj5JbWFnZSBTZXQ8L2J1dHRvbj48L2Rpdj4KICAgICAgPHNwYW4gY2xhc3M9ImZpZWxkTGFiZWwiPlF1YWxpdHk8L3NwYW4+PHNlbGVjdCBpZD0icXVhbGl0eVNlbGVjdCI+PG9wdGlvbj4xMDgwcCAoSGlnaCk8L29wdGlvbj48b3B0aW9uPjcyMHA8L29wdGlvbj48L3NlbGVjdD4KICAgICAgPGRpdiBjbGFzcz0iYXVkaW9Sb3ciPjxkaXY+PGI+SW5jbHVkZSBBdWRpbzwvYj48ZGl2IGNsYXNzPSJzbWFsbCI+QWRkIG11c2ljIHRvIHlvdXIgdmlkZW88L2Rpdj48L2Rpdj48ZGl2IGlkPSJhdWRpb1N3aXRjaCIgY2xhc3M9InN3aXRjaCI+PC9kaXY+PC9kaXY+PGlucHV0IGlkPSJhdWRpb0lucHV0IiBjbGFzcz0iYXVkaW9JbnB1dCIgdHlwZT0iZmlsZSIgYWNjZXB0PSJhdWRpby8qIj4KICAgICAgPGJ1dHRvbiBpZD0icmVuZGVyQnV0dG9uIiBjbGFzcz0icmVuZGVyQnV0dG9uIj7ilqYmbmJzcDsgUmVuZGVyIE1QNDxzcGFuPkZpbmFsIHZpZGVvIGV4cG9ydDwvc3Bhbj48L2J1dHRvbj4KICAgIDwvZGl2Pjwvc2VjdGlvbj4KICA8L2FzaWRlPgo8L2Rpdj4KCjxkaXYgaWQ9ImltbWljaE1vZGFsIiBjbGFzcz0ibW9kYWwiPjxkaXYgY2xhc3M9Im1vZGFsQ2FyZCI+PGRpdiBjbGFzcz0ibW9kYWxUaXRsZSI+TmV3IEltbWljaCBKb3VybmV5PC9kaXY+PGRpdiBjbGFzcz0iZm9ybUdyaWQiPjxpbnB1dCBpZD0iaW1taWNoVXJsIiBwbGFjZWhvbGRlcj0iSW1taWNoIFVSTCDigJQgZm9yIGV4YW1wbGUgaHR0cDovLzE5Mi4xNjguNjguMTUzOjIyODMiPjxpbnB1dCBpZD0iaW1taWNoS2V5IiB0eXBlPSJwYXNzd29yZCIgcGxhY2Vob2xkZXI9IkltbWljaCBBUEkga2V5Ij48ZGl2IGNsYXNzPSJ0d29Db2wiPjxpbnB1dCBpZD0ic3RhcnREYXRlIiB0eXBlPSJkYXRlIj48aW5wdXQgaWQ9ImVuZERhdGUiIHR5cGU9ImRhdGUiPjwvZGl2PjxkaXYgY2xhc3M9InNtYWxsIj5SZXF1aXJlZCBwZXJtaXNzaW9uczogYXNzZXQucmVhZCwgYXNzZXQudmlldywgYXNzZXQuZG93bmxvYWQsIG1hcC5yZWFkLCB0aW1lbGluZS5yZWFkPC9kaXY+PGRpdiBjbGFzcz0ibW9kYWxBY3Rpb25zIj48YnV0dG9uIGlkPSJ0ZXN0SW1taWNoQnV0dG9uIj5UZXN0IENvbm5lY3Rpb248L2J1dHRvbj48YnV0dG9uIGlkPSJjcmVhdGVKb3VybmV5QnV0dG9uIiBjbGFzcz0icHJpbWFyeSI+Q3JlYXRlIEpvdXJuZXk8L2J1dHRvbj48YnV0dG9uIGRhdGEtY2xvc2U9ImltbWljaE1vZGFsIj5DYW5jZWw8L2J1dHRvbj48L2Rpdj48L2Rpdj48L2Rpdj48L2Rpdj4KPGRpdiBpZD0idXBsb2FkTW9kYWwiIGNsYXNzPSJtb2RhbCI+PGRpdiBjbGFzcz0ibW9kYWxDYXJkIj48ZGl2IGNsYXNzPSJtb2RhbFRpdGxlIj5VcGxvYWQgR1BTIE1lZGlhPC9kaXY+PGRpdiBjbGFzcz0iZm9ybUdyaWQiPjxpbnB1dCBpZD0idXBsb2FkTmFtZSIgdmFsdWU9IlVwbG9hZGVkIEpvdXJuZXkiIHBsYWNlaG9sZGVyPSJKb3VybmV5IG5hbWUiPjxpbnB1dCBpZD0idXBsb2FkRmlsZXMiIHR5cGU9ImZpbGUiIGFjY2VwdD0iaW1hZ2UvKix2aWRlby8qIiBtdWx0aXBsZT48ZGl2IGNsYXNzPSJzbWFsbCI+T25seSBtZWRpYSBjb250YWluaW5nIEdQUyBtZXRhZGF0YSBjYW4gYXBwZWFyIG9uIHRoZSBtYXAuPC9kaXY+PGRpdiBjbGFzcz0ibW9kYWxBY3Rpb25zIj48YnV0dG9uIGlkPSJjcmVhdGVVcGxvYWRCdXR0b24iIGNsYXNzPSJwcmltYXJ5Ij5JbXBvcnQgTWVkaWE8L2J1dHRvbj48YnV0dG9uIGRhdGEtY2xvc2U9InVwbG9hZE1vZGFsIj5DYW5jZWw8L2J1dHRvbj48L2Rpdj48L2Rpdj48L2Rpdj48L2Rpdj4KPGRpdiBpZD0ic2V0dGluZ3NNb2RhbCIgY2xhc3M9Im1vZGFsIj48ZGl2IGNsYXNzPSJtb2RhbENhcmQiPjxkaXYgY2xhc3M9Im1vZGFsVGl0bGUiPkpvdXJuZXkgU2V0dGluZ3M8L2Rpdj48ZGl2IGNsYXNzPSJmb3JtR3JpZCI+PGxhYmVsIGNsYXNzPSJzbWFsbCI+U3RvcCByYWRpdXMsIG1ldGVyczwvbGFiZWw+PGlucHV0IGlkPSJzdG9wUmFkaXVzIiB0eXBlPSJudW1iZXIiIG1pbj0iMTAiIHZhbHVlPSIyMDAiPjxkaXYgY2xhc3M9InR3b0NvbCI+PGJ1dHRvbiBpZD0icmVjbHVzdGVyQnV0dG9uIj5BdXRvLWNsdXN0ZXIgU3RvcHM8L2J1dHRvbj48YnV0dG9uIGlkPSJyZXZlcnNlUm91dGVCdXR0b24iPlJldmVyc2UgUm91dGU8L2J1dHRvbj48L2Rpdj48bGFiZWwgY2xhc3M9InNtYWxsIj5EZWZhdWx0IG1hcDwvbGFiZWw+PHNlbGVjdCBpZD0iZGVmYXVsdE1hcFNlbGVjdCI+PG9wdGlvbiB2YWx1ZT0ibGlnaHQiPkxpZ2h0IE9TTTwvb3B0aW9uPjxvcHRpb24gdmFsdWU9ImRhcmsiPkRhcms8L29wdGlvbj48b3B0aW9uIHZhbHVlPSJzYXRlbGxpdGUiPlNhdGVsbGl0ZTwvb3B0aW9uPjwvc2VsZWN0PjxkaXYgY2xhc3M9Im1vZGFsQWN0aW9ucyI+PGJ1dHRvbiBkYXRhLWNsb3NlPSJzZXR0aW5nc01vZGFsIj5DbG9zZTwvYnV0dG9uPjwvZGl2PjwvZGl2PjwvZGl2PjwvZGl2Pgo8ZGl2IGlkPSJhY2NvdW50TW9kYWwiIGNsYXNzPSJtb2RhbCI+PGRpdiBjbGFzcz0ibW9kYWxDYXJkIj48ZGl2IGNsYXNzPSJtb2RhbFRpdGxlIj5BY2NvdW50IC8gSW1taWNoIENvbm5lY3Rpb248L2Rpdj48ZGl2IGNsYXNzPSJmb3JtR3JpZCI+PGlucHV0IGlkPSJhY2NvdW50VXJsIiBwbGFjZWhvbGRlcj0iSW1taWNoIFVSTCI+PGlucHV0IGlkPSJhY2NvdW50S2V5IiB0eXBlPSJwYXNzd29yZCIgcGxhY2Vob2xkZXI9IkFQSSBrZXkiPjxkaXYgY2xhc3M9Im1vZGFsQWN0aW9ucyI+PGJ1dHRvbiBpZD0ic2F2ZUFjY291bnRCdXR0b24iIGNsYXNzPSJwcmltYXJ5Ij5TYXZlIENvbm5lY3Rpb248L2J1dHRvbj48YnV0dG9uIGRhdGEtY2xvc2U9ImFjY291bnRNb2RhbCI+Q2xvc2U8L2J1dHRvbj48L2Rpdj48L2Rpdj48L2Rpdj48L2Rpdj4KCjxkaXYgaWQ9InByZXNlbnRPdmVybGF5IiBjbGFzcz0icHJlc2VudE92ZXJsYXkiPjxkaXYgY2xhc3M9InByZXNlbnRIZWFkZXIiPjxkaXYgY2xhc3M9ImxvZ29GbG93ZXIiPjxzcGFuIGNsYXNzPSJwZXRhbCBwMSI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMiI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMyI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNCI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNSI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNiI+PC9zcGFuPjwvZGl2PjxkaXY+PGRpdiBpZD0icHJlc2VudEhlYWRlclRpdGxlIiBjbGFzcz0icHJlc2VudEhlYWRlclRpdGxlIj5QcmVzZW50IEpvdXJuZXk8L2Rpdj48ZGl2IGlkPSJwcmVzZW50SGVhZGVyTWV0YSIgY2xhc3M9InByZXNlbnRIZWFkZXJNZXRhIj48L2Rpdj48L2Rpdj48ZGl2IGNsYXNzPSJwcmVzZW50SGVhZGVyU3BhY2VyIj48L2Rpdj48YnV0dG9uIGlkPSJjbG9zZVByZXNlbnRCdXR0b24iIGNsYXNzPSJ0b3BBY3Rpb24iPkNsb3NlPC9idXR0b24+PC9kaXY+CiAgPGRpdiBjbGFzcz0icHJlc2VudE1haW4iPjxkaXYgaWQ9InByZXNlbnRNYXAiIGNsYXNzPSJwcmVzZW50TWFwIj48L2Rpdj48ZGl2IGlkPSJwcmVzZW50U3RvcFJhaWwiIGNsYXNzPSJwcmVzZW50U3RvcFJhaWwiPjwvZGl2PjxkaXYgaWQ9InByZXNlbnRQaG90b0NhcmQiIGNsYXNzPSJwcmVzZW50UGhvdG9DYXJkIj48L2Rpdj48ZGl2IGNsYXNzPSJwcmVzZW50SHVkIj48YnV0dG9uIGlkPSJwcmV2aW91c1N0b3BCdXR0b24iPuKGkCBTdG9wPC9idXR0b24+PGJ1dHRvbiBpZD0icHJldmlvdXNQaG90b0J1dHRvbiI+4oaQIFBob3RvPC9idXR0b24+PGJ1dHRvbiBpZD0icGxheUpvdXJuZXlCdXR0b24iIGNsYXNzPSJwbGF5Ij7ilrYgUGxheTwvYnV0dG9uPjxidXR0b24gaWQ9Im5leHRQaG90b0J1dHRvbiI+UGhvdG8g4oaSPC9idXR0b24+PGJ1dHRvbiBpZD0ibmV4dFN0b3BCdXR0b24iPlN0b3Ag4oaSPC9idXR0b24+PC9kaXY+PC9kaXY+PGRpdiBpZD0icHJlc2VudEZpbG1zdHJpcCIgY2xhc3M9InByZXNlbnRGaWxtc3RyaXAiPjwvZGl2Pgo8L2Rpdj4KPGRpdiBpZD0idG9hc3QiIGNsYXNzPSJ0b2FzdCI+PC9kaXY+Cgo8c2NyaXB0Pgpjb25zdCBNQVBfU1RZTEVTPXsKIGxpZ2h0Ont2ZXJzaW9uOjgsc291cmNlczp7YmFzZTp7dHlwZToncmFzdGVyJyx0aWxlczpbJ2h0dHBzOi8vYS5iYXNlbWFwcy5jYXJ0b2Nkbi5jb20vcmFzdGVydGlsZXMvdm95YWdlci97en0ve3h9L3t5fUAyeC5wbmcnLCdodHRwczovL2IuYmFzZW1hcHMuY2FydG9jZG4uY29tL3Jhc3RlcnRpbGVzL3ZveWFnZXIve3p9L3t4fS97eX1AMngucG5nJ10sdGlsZVNpemU6MjU2LGF0dHJpYnV0aW9uOifCqSBPcGVuU3RyZWV0TWFwIGNvbnRyaWJ1dG9ycyDCqSBDQVJUTyd9fSxsYXllcnM6W3tpZDonYmFzZScsdHlwZToncmFzdGVyJyxzb3VyY2U6J2Jhc2UnLG1pbnpvb206MCxtYXh6b29tOjIwfV19LAogZGFyazp7dmVyc2lvbjo4LHNvdXJjZXM6e2Jhc2U6e3R5cGU6J3Jhc3RlcicsdGlsZXM6WydodHRwczovL2EuYmFzZW1hcHMuY2FydG9jZG4uY29tL2RhcmtfYWxsL3t6fS97eH0ve3l9QDJ4LnBuZycsJ2h0dHBzOi8vYi5iYXNlbWFwcy5jYXJ0b2Nkbi5jb20vZGFya19hbGwve3p9L3t4fS97eX1AMngucG5nJ10sdGlsZVNpemU6MjU2LGF0dHJpYnV0aW9uOifCqSBPcGVuU3RyZWV0TWFwIGNvbnRyaWJ1dG9ycyDCqSBDQVJUTyd9fSxsYXllcnM6W3tpZDonYmFzZScsdHlwZToncmFzdGVyJyxzb3VyY2U6J2Jhc2UnLG1pbnpvb206MCxtYXh6b29tOjIwfV19LAogc2F0ZWxsaXRlOnt2ZXJzaW9uOjgsc291cmNlczp7YmFzZTp7dHlwZToncmFzdGVyJyx0aWxlczpbJ2h0dHBzOi8vc2VydmVyLmFyY2dpc29ubGluZS5jb20vQXJjR0lTL3Jlc3Qvc2VydmljZXMvV29ybGRfSW1hZ2VyeS9NYXBTZXJ2ZXIvdGlsZS97en0ve3l9L3t4fSddLHRpbGVTaXplOjI1NixhdHRyaWJ1dGlvbjonVGlsZXMgwqkgRXNyaSd9fSxsYXllcnM6W3tpZDonYmFzZScsdHlwZToncmFzdGVyJyxzb3VyY2U6J2Jhc2UnLG1pbnpvb206MCxtYXh6b29tOjIwfV19Cn07CmxldCBwcm9qZWN0cz1bXSxwcm9qZWN0PW51bGwsbWFwPW51bGwscHJlc2VudE1hcD1udWxsLG1hcFN0eWxlS2V5PWxvY2FsU3RvcmFnZS5nZXRJdGVtKCd0cmlwcHlfbWFwX3N0eWxlJyl8fCdsaWdodCc7CmxldCBtYXJrZXJzPVtdLHByZXNlbnRNYXJrZXJzPVtdLGFjdGl2ZVN0b3BJZD1udWxsLGZpbHRlclN0b3BJZD1udWxsLGFjdGl2ZUFzc2V0SWQ9bnVsbCxhY3RpdmVQb3B1cD1udWxsLHByZXNlbnRTdG9wSW5kZXg9MCxwcmVzZW50UGhvdG9JbmRleD0wLHByZXNlbnRUaW1lcj1udWxsOwpjb25zdCBlbD1pZD0+ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoaWQpOwpmdW5jdGlvbiBjbG9uZVN0eWxlKGtleSl7cmV0dXJuIEpTT04ucGFyc2UoSlNPTi5zdHJpbmdpZnkoTUFQX1NUWUxFU1trZXldfHxNQVBfU1RZTEVTLmxpZ2h0KSl9CmZ1bmN0aW9uIHRvYXN0KG1lc3NhZ2Upe2NvbnN0IHQ9ZWwoJ3RvYXN0Jyk7dC50ZXh0Q29udGVudD1tZXNzYWdlO3QuY2xhc3NMaXN0LmFkZCgnc2hvdycpO2NsZWFyVGltZW91dCh0Ll90aW1lcik7dC5fdGltZXI9c2V0VGltZW91dCgoKT0+dC5jbGFzc0xpc3QucmVtb3ZlKCdzaG93JyksNDMwMCl9CmZ1bmN0aW9uIGVzYyh2KXtyZXR1cm4gU3RyaW5nKHY/PycnKS5yZXBsYWNlKC9bJjw+JyJdL2csYz0+KHsnJic6JyZhbXA7JywnPCc6JyZsdDsnLCc+JzonJmd0OycsIiciOicmIzM5OycsJyInOicmcXVvdDsnfVtjXSkpfQpmdW5jdGlvbiBpc29EYXRlKHYpe2lmKCF2KXJldHVybicnO3JldHVybiBTdHJpbmcodikuc2xpY2UoMCwxMCl9CmZ1bmN0aW9uIHByZXR0eURhdGUodil7aWYoIXYpcmV0dXJuJyc7Y29uc3QgZD1uZXcgRGF0ZShTdHJpbmcodikuc2xpY2UoMCwxMCkrJ1QxMjowMDowMCcpO3JldHVybiBOdW1iZXIuaXNOYU4oZC5nZXRUaW1lKCkpP1N0cmluZyh2KS5zbGljZSgwLDEwKTpkLnRvTG9jYWxlRGF0ZVN0cmluZyh1bmRlZmluZWQse21vbnRoOidzaG9ydCcsZGF5OidudW1lcmljJyx5ZWFyOidudW1lcmljJ30pfQpmdW5jdGlvbiByYW5nZVRleHQob2JqKXtjb25zdCBhPW9iaj8uaW1taWNoPy5zdGFydF9kYXRlfHxvYmo/LnN0YXJ0X2RhdGU7Y29uc3QgYj1vYmo/LmltbWljaD8uZW5kX2RhdGV8fG9iaj8uZW5kX2RhdGU7aWYoYSYmYilyZXR1cm4gYCR7aXNvRGF0ZShhKX0gdG8gJHtpc29EYXRlKGIpfWA7cmV0dXJuIHByZXR0eURhdGUob2JqPy5jcmVhdGVkKX0KZnVuY3Rpb24gY29ubigpe3JldHVybntiYXNlX3VybDpsb2NhbFN0b3JhZ2UuZ2V0SXRlbSgndHJpcHB5X2ltbWljaF91cmwnKXx8JycsYXBpX2tleTpsb2NhbFN0b3JhZ2UuZ2V0SXRlbSgndHJpcHB5X2ltbWljaF9rZXknKXx8Jyd9fQpmdW5jdGlvbiBzYXZlQ29ubih1cmwsa2V5KXtsb2NhbFN0b3JhZ2Uuc2V0SXRlbSgndHJpcHB5X2ltbWljaF91cmwnLHVybCk7bG9jYWxTdG9yYWdlLnNldEl0ZW0oJ3RyaXBweV9pbW1pY2hfa2V5JyxrZXkpfQphc3luYyBmdW5jdGlvbiBhcGkocGF0aCxvcHRpb25zPXt9KXtjb25zdCByZXNwb25zZT1hd2FpdCBmZXRjaChwYXRoLG9wdGlvbnMpO2NvbnN0IHJhdz1hd2FpdCByZXNwb25zZS50ZXh0KCk7bGV0IGRhdGE7dHJ5e2RhdGE9SlNPTi5wYXJzZShyYXcpfWNhdGNoe2RhdGE9e2RldGFpbDpyYXd9fWlmKCFyZXNwb25zZS5vayl0aHJvdyBuZXcgRXJyb3IoZGF0YS5kZXRhaWx8fHJhd3x8YEhUVFAgJHtyZXNwb25zZS5zdGF0dXN9YCk7cmV0dXJuIGRhdGF9CmZ1bmN0aW9uIHN0b3BOYW1lKHN0b3AsaW5kZXgpe2NvbnN0IHJhdz0oc3RvcD8ubmFtZXx8JycpLnRyaW0oKTtyZXR1cm4gcmF3JiYhL15TdG9wXHMrXGQrJC9pLnRlc3QocmF3KT9yYXc6YFN0b3AgJHtpbmRleCsxfWB9CmZ1bmN0aW9uIHN0b3BBc3NldHMoc3RvcCl7aWYoIXByb2plY3R8fCFzdG9wKXJldHVybltdO2NvbnN0IGlkcz1uZXcgU2V0KHN0b3AuYXNzZXRfaWRzfHxbXSk7cmV0dXJuKHByb2plY3QuYXNzZXRzfHxbXSkuZmlsdGVyKGE9Pmlkcy5oYXMoYS5hc3NldF9pZCkpfQpmdW5jdGlvbiBmaXJzdFN0b3BBc3NldChzdG9wKXtyZXR1cm4gc3RvcEFzc2V0cyhzdG9wKVswXXx8bnVsbH0KZnVuY3Rpb24gcHJvamVjdFN1bW1hcnlDb3VudChwKXtyZXR1cm4gTnVtYmVyKHA/LmNvdW50Pz9wPy5hc3NldHM/Lmxlbmd0aD8/MCl9CmZ1bmN0aW9uIHNldE1vZGFsKGlkLG9uPXRydWUpe2VsKGlkKS5jbGFzc0xpc3QudG9nZ2xlKCdzaG93Jyxvbil9CmZ1bmN0aW9uIGluaXRGb3Jtcygpe2NvbnN0IGM9Y29ubigpO2VsKCdpbW1pY2hVcmwnKS52YWx1ZT1jLmJhc2VfdXJsO2VsKCdpbW1pY2hLZXknKS52YWx1ZT1jLmFwaV9rZXk7ZWwoJ2FjY291bnRVcmwnKS52YWx1ZT1jLmJhc2VfdXJsO2VsKCdhY2NvdW50S2V5JykudmFsdWU9Yy5hcGlfa2V5O2NvbnN0IGQ9bmV3IERhdGUoKSxzPW5ldyBEYXRlKCk7cy5zZXREYXRlKHMuZ2V0RGF0ZSgpLTcpO2VsKCdzdGFydERhdGUnKS52YWx1ZT1zLnRvSVNPU3RyaW5nKCkuc2xpY2UoMCwxMCk7ZWwoJ2VuZERhdGUnKS52YWx1ZT1kLnRvSVNPU3RyaW5nKCkuc2xpY2UoMCwxMCk7ZWwoJ2RlZmF1bHRNYXBTZWxlY3QnKS52YWx1ZT1tYXBTdHlsZUtleX0KYXN5bmMgZnVuY3Rpb24gbG9hZFByb2plY3RzKCl7cHJvamVjdHM9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3RzJyk7cmVuZGVyUHJvamVjdHMoKTtpZighcHJvamVjdCYmcHJvamVjdHMubGVuZ3RoKWF3YWl0IG9wZW5Qcm9qZWN0KHByb2plY3RzWzBdLmlkKTtpZighcHJvamVjdHMubGVuZ3RoKXJlbmRlckFsbCgpfQpmdW5jdGlvbiByZW5kZXJQcm9qZWN0cygpe2NvbnN0IHE9ZWwoJ3Byb2plY3RTZWFyY2gnKS52YWx1ZS50cmltKCkudG9Mb3dlckNhc2UoKTtjb25zdCBsaXN0PXByb2plY3RzLmZpbHRlcihwPT4hcXx8KHAubmFtZXx8JycpLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocSkpO2VsKCdwcm9qZWN0TGlzdCcpLmlubmVySFRNTD1saXN0Lm1hcChwPT5gPGFydGljbGUgY2xhc3M9InByb2plY3RDYXJkICR7cHJvamVjdD8uaWQ9PT1wLmlkPydhY3RpdmUnOicnfSIgZGF0YS1pZD0iJHtlc2MocC5pZCl9Ij48YnV0dG9uIGNsYXNzPSJwcm9qZWN0TWVudSIgZGF0YS1tZW51PSIke2VzYyhwLmlkKX0iPuKLrjwvYnV0dG9uPjxkaXYgY2xhc3M9InByb2plY3RDYXJkVGl0bGUiPiR7ZXNjKHAubmFtZXx8J1VudGl0bGVkIEpvdXJuZXknKX08L2Rpdj48ZGl2IGNsYXNzPSJwcm9qZWN0RGF0ZSI+JHtlc2MocmFuZ2VUZXh0KHApfHwnJyl9PC9kaXY+PGRpdiBjbGFzcz0icHJvamVjdFN0YXRzIj48c3BhbiBjbGFzcz0iZG90Ij7il488L3NwYW4+ICR7cHJvamVjdFN1bW1hcnlDb3VudChwKX0gbWVkaWEmbmJzcDsg4oCiICZuYnNwOyR7TnVtYmVyKHAuc3RvcHN8fDApfSBzdG9wczwvZGl2PjxidXR0b24gY2xhc3M9InByb2plY3REZWxldGUiIGRhdGEtZGVsZXRlPSIke2VzYyhwLmlkKX0iPkRlbGV0ZTwvYnV0dG9uPjwvYXJ0aWNsZT5gKS5qb2luKCcnKXx8JzxkaXYgY2xhc3M9InNtYWxsIj5ObyBqb3VybmV5cyB5ZXQuPC9kaXY+Jztkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCcucHJvamVjdENhcmQnKS5mb3JFYWNoKGNhcmQ9PmNhcmQuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLGU9PntpZihlLnRhcmdldC5jbG9zZXN0KCdidXR0b24nKSlyZXR1cm47b3BlblByb2plY3QoY2FyZC5kYXRhc2V0LmlkKX0pKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1tZW51XScpLmZvckVhY2goYj0+Yi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsZT0+e2Uuc3RvcFByb3BhZ2F0aW9uKCk7Yi5jbG9zZXN0KCcucHJvamVjdENhcmQnKS5jbGFzc0xpc3QudG9nZ2xlKCdtZW51T3BlbicpfSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLWRlbGV0ZV0nKS5mb3JFYWNoKGI9PmIuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLGU9PntlLnN0b3BQcm9wYWdhdGlvbigpO2RlbGV0ZVByb2plY3QoYi5kYXRhc2V0LmRlbGV0ZSl9KSl9CmFzeW5jIGZ1bmN0aW9uIG9wZW5Qcm9qZWN0KGlkKXtwcm9qZWN0PWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KGlkKSk7YWN0aXZlU3RvcElkPXByb2plY3Quc3RvcHM/LlswXT8uc3RvcF9pZHx8bnVsbDtmaWx0ZXJTdG9wSWQ9YWN0aXZlU3RvcElkO2FjdGl2ZUFzc2V0SWQ9bnVsbDtyZW5kZXJBbGwoKTt0b2FzdChgTG9hZGVkICR7cHJvamVjdC5uYW1lfHwnam91cm5leSd9YCl9CmFzeW5jIGZ1bmN0aW9uIGRlbGV0ZVByb2plY3QoaWQpe2lmKCFjb25maXJtKCdEZWxldGUgdGhpcyBqb3VybmV5IGFuZCBpdHMgc2F2ZWQgZXhwb3J0PycpKXJldHVybjthd2FpdCBhcGkoJy9hcGkvcHJvamVjdC8nK2VuY29kZVVSSUNvbXBvbmVudChpZCkse21ldGhvZDonREVMRVRFJ30pO2lmKHByb2plY3Q/LmlkPT09aWQpcHJvamVjdD1udWxsO3Byb2plY3RzPXByb2plY3RzLmZpbHRlcihwPT5wLmlkIT09aWQpO2F3YWl0IGxvYWRQcm9qZWN0cygpfQpmdW5jdGlvbiByZW5kZXJBbGwoKXtyZW5kZXJQcm9qZWN0cygpO3JlbmRlckhlYWRlcigpO3JlbmRlclN0b3BzKCk7cmVuZGVyR2FsbGVyeSgpO3JlbmRlck1hcCh0cnVlKX0KZnVuY3Rpb24gcmVuZGVySGVhZGVyKCl7aWYoIXByb2plY3Qpe2VsKCdqb3VybmV5VGl0bGUnKS50ZXh0Q29udGVudD0nTm8gam91cm5leSBzZWxlY3RlZCc7ZWwoJ2pvdXJuZXlNZXRhJykudGV4dENvbnRlbnQ9J0xvYWQgb3IgY3JlYXRlIGEgam91cm5leSc7cmV0dXJufWVsKCdqb3VybmV5VGl0bGUnKS50ZXh0Q29udGVudD1wcm9qZWN0Lm5hbWV8fCdVbnRpdGxlZCBKb3VybmV5Jztjb25zdCBtZWRpYT0ocHJvamVjdC5hc3NldHN8fFtdKS5sZW5ndGgsc3RvcHM9KHByb2plY3Quc3RvcHN8fFtdKS5sZW5ndGg7ZWwoJ2pvdXJuZXlNZXRhJykuaW5uZXJIVE1MPWA8c3Bhbj7il7cgJHtlc2MocmFuZ2VUZXh0KHByb2plY3QpfHxwcmV0dHlEYXRlKHByb2plY3QuY3JlYXRlZCkpfTwvc3Bhbj48c3BhbiBjbGFzcz0ibGl2ZURvdCI+PC9zcGFuPjxzcGFuPiR7bWVkaWF9IG1lZGlhPC9zcGFuPjxzcGFuPuKAoiAke3N0b3BzfSBzdG9wczwvc3Bhbj5gfQpmdW5jdGlvbiBlbnN1cmVNYXAoKXtpZihtYXApcmV0dXJuO21hcD1uZXcgbWFwbGlicmVnbC5NYXAoe2NvbnRhaW5lcjonbWFwJyxzdHlsZTpjbG9uZVN0eWxlKG1hcFN0eWxlS2V5KSxjZW50ZXI6Wy05OCwzOV0sem9vbTozLHBpdGNoOjAsYmVhcmluZzowLGF0dHJpYnV0aW9uQ29udHJvbDp0cnVlfSk7bWFwLmFkZENvbnRyb2wobmV3IG1hcGxpYnJlZ2wuTmF2aWdhdGlvbkNvbnRyb2woe3Nob3dDb21wYXNzOmZhbHNlfSksJ2JvdHRvbS1yaWdodCcpO21hcC5vbignbG9hZCcsKCk9PnJlbmRlck1hcCh0cnVlKSl9CmZ1bmN0aW9uIGNsZWFyTWFwTWFya2Vycygpe21hcmtlcnMuZm9yRWFjaChtPT5tLnJlbW92ZSgpKTttYXJrZXJzPVtdO2lmKGFjdGl2ZVBvcHVwKXt0cnl7YWN0aXZlUG9wdXAucmVtb3ZlKCl9Y2F0Y2h7fWFjdGl2ZVBvcHVwPW51bGx9fQpmdW5jdGlvbiBhZGRSb3V0ZUxheWVycyh0YXJnZXRNYXAsaWRQcmVmaXgsY29vcmRzKXtjb25zdCBzb3VyY2U9aWRQcmVmaXgrJy1yb3V0ZScsZ2xvdz1pZFByZWZpeCsnLXJvdXRlLWdsb3cnLGxpbmU9aWRQcmVmaXgrJy1yb3V0ZS1saW5lJztbbGluZSxnbG93XS5mb3JFYWNoKGlkPT57aWYodGFyZ2V0TWFwLmdldExheWVyKGlkKSl0YXJnZXRNYXAucmVtb3ZlTGF5ZXIoaWQpfSk7aWYodGFyZ2V0TWFwLmdldFNvdXJjZShzb3VyY2UpKXRhcmdldE1hcC5yZW1vdmVTb3VyY2Uoc291cmNlKTtpZihjb29yZHMubGVuZ3RoPDIpcmV0dXJuO3RhcmdldE1hcC5hZGRTb3VyY2Uoc291cmNlLHt0eXBlOidnZW9qc29uJyxkYXRhOnt0eXBlOidGZWF0dXJlJyxnZW9tZXRyeTp7dHlwZTonTGluZVN0cmluZycsY29vcmRpbmF0ZXM6Y29vcmRzfX19KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOmdsb3csdHlwZTonbGluZScsc291cmNlLHBhaW50OnsnbGluZS1jb2xvcic6JyMwMGQ4ZmYnLCdsaW5lLXdpZHRoJzoxMSwnbGluZS1vcGFjaXR5JzouMjAsJ2xpbmUtYmx1cic6NX19KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOmxpbmUsdHlwZTonbGluZScsc291cmNlLHBhaW50OnsnbGluZS1jb2xvcic6JyMwMGNmZWUnLCdsaW5lLXdpZHRoJzo0LCdsaW5lLW9wYWNpdHknOi45NX19KX0KZnVuY3Rpb24gbWFya2VyRWxlbWVudChzdG9wLGluZGV4LGlzUHJlc2VudD1mYWxzZSl7Y29uc3QgYXNzZXQ9Zmlyc3RTdG9wQXNzZXQoc3RvcCksbm9kZT1kb2N1bWVudC5jcmVhdGVFbGVtZW50KCdkaXYnKTtub2RlLmNsYXNzTmFtZT0ncGhvdG9NYXJrZXInKyhzdG9wLnN0b3BfaWQ9PT1hY3RpdmVTdG9wSWQmJiFpc1ByZXNlbnQ/JyBhY3RpdmUnOicnKTtub2RlLmlubmVySFRNTD1hc3NldD8udGh1bWI/YDxpbWcgc3JjPSIke2VzYyhhc3NldC50aHVtYil9IiBhbHQ9IiI+YDonPGRpdiBjbGFzcz0iZmFsbGJhY2siPuKAojwvZGl2Pic7Y29uc3QgYmFkZ2U9ZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgnc3BhbicpO2JhZGdlLmNsYXNzTmFtZT0nbWFya2VyQmFkZ2UnO2JhZGdlLnRleHRDb250ZW50PVN0cmluZyhpbmRleCsxKTtub2RlLmFwcGVuZENoaWxkKGJhZGdlKTtyZXR1cm4gbm9kZX0KZnVuY3Rpb24gcmVuZGVyTWFwKGZpdD1mYWxzZSl7ZW5zdXJlTWFwKCk7aWYoIW1hcC5pc1N0eWxlTG9hZGVkKCkpe21hcC5vbmNlKCdsb2FkJywoKT0+cmVuZGVyTWFwKGZpdCkpO3JldHVybn1jbGVhck1hcE1hcmtlcnMoKTtjb25zdCBzdG9wcz1wcm9qZWN0Py5zdG9wc3x8W107aWYoIXN0b3BzLmxlbmd0aClyZXR1cm47Y29uc3QgY29vcmRzPXN0b3BzLm1hcChzPT5bTnVtYmVyKHMubG9uKSxOdW1iZXIocy5sYXQpXSk7YWRkUm91dGVMYXllcnMobWFwLCdtYWluJyxjb29yZHMpO2NvbnN0IGJvdW5kcz1uZXcgbWFwbGlicmVnbC5MbmdMYXRCb3VuZHMoKTtzdG9wcy5mb3JFYWNoKChzLGkpPT57Ym91bmRzLmV4dGVuZChbcy5sb24scy5sYXRdKTtjb25zdCBub2RlPW1hcmtlckVsZW1lbnQocyxpKTtub2RlLm9uY2xpY2s9KCk9PnNlbGVjdFN0b3Aocy5zdG9wX2lkLHtmbHk6dHJ1ZSxwb3B1cDp0cnVlLGZpbHRlcjp0cnVlfSk7bWFya2Vycy5wdXNoKG5ldyBtYXBsaWJyZWdsLk1hcmtlcih7ZWxlbWVudDpub2RlLGFuY2hvcjonY2VudGVyJ30pLnNldExuZ0xhdChbcy5sb24scy5sYXRdKS5hZGRUbyhtYXApKX0pO2lmKGZpdCl7dHJ5e21hcC5maXRCb3VuZHMoYm91bmRzLHtwYWRkaW5nOnt0b3A6ODUsYm90dG9tOjkwLGxlZnQ6OTUscmlnaHQ6OTV9LG1heFpvb206MTQuOCxkdXJhdGlvbjo4NTB9KX1jYXRjaHt9fX0KZnVuY3Rpb24gc2V0TWFwU3R5bGUoa2V5KXtpZighTUFQX1NUWUxFU1trZXldKXJldHVybjttYXBTdHlsZUtleT1rZXk7bG9jYWxTdG9yYWdlLnNldEl0ZW0oJ3RyaXBweV9tYXBfc3R5bGUnLGtleSk7WydsaWdodCcsJ2RhcmsnLCdzYXRlbGxpdGUnXS5mb3JFYWNoKGs9PmVsKGsrJ01hcEJ1dHRvbicpLmNsYXNzTGlzdC50b2dnbGUoJ2FjdGl2ZScsaz09PWtleSkpO2VsKCdkZWZhdWx0TWFwU2VsZWN0JykudmFsdWU9a2V5O2lmKG1hcCl7bWFwLnNldFN0eWxlKGNsb25lU3R5bGUoa2V5KSk7bWFwLm9uY2UoJ3N0eWxlLmxvYWQnLCgpPT5yZW5kZXJNYXAoZmFsc2UpKX19CmZ1bmN0aW9uIGJlYXJpbmcoYSxiKXtjb25zdCB5PU1hdGguc2luKChiLmxvbi1hLmxvbikqTWF0aC5QSS8xODApKk1hdGguY29zKGIubGF0Kk1hdGguUEkvMTgwKTtjb25zdCB4PU1hdGguY29zKGEubGF0Kk1hdGguUEkvMTgwKSpNYXRoLnNpbihiLmxhdCpNYXRoLlBJLzE4MCktTWF0aC5zaW4oYS5sYXQqTWF0aC5QSS8xODApKk1hdGguY29zKGIubGF0Kk1hdGguUEkvMTgwKSpNYXRoLmNvcygoYi5sb24tYS5sb24pKk1hdGguUEkvMTgwKTtyZXR1cm4oTWF0aC5hdGFuMih5LHgpKjE4MC9NYXRoLlBJKzM2MCklMzYwfQpmdW5jdGlvbiBzZWxlY3RTdG9wKGlkLHtmbHk9dHJ1ZSxwb3B1cD10cnVlLGZpbHRlcj10cnVlfT17fSl7aWYoIXByb2plY3QpcmV0dXJuO2NvbnN0IGluZGV4PShwcm9qZWN0LnN0b3BzfHxbXSkuZmluZEluZGV4KHM9PnMuc3RvcF9pZD09PWlkKTtpZihpbmRleDwwKXJldHVybjtjb25zdCBzdG9wPXByb2plY3Quc3RvcHNbaW5kZXhdO2FjdGl2ZVN0b3BJZD1pZDtpZihmaWx0ZXIpZmlsdGVyU3RvcElkPWlkO3JlbmRlclN0b3BzKCk7cmVuZGVyR2FsbGVyeSgpO3JlbmRlck1hcChmYWxzZSk7aWYoZmx5JiZtYXApe2NvbnN0IG5leHQ9cHJvamVjdC5zdG9wc1tNYXRoLm1pbihpbmRleCsxLHByb2plY3Quc3RvcHMubGVuZ3RoLTEpXXx8c3RvcDttYXAuZmx5VG8oe2NlbnRlcjpbc3RvcC5sb24sc3RvcC5sYXRdLHpvb206MTUuNyxwaXRjaDo0MixiZWFyaW5nOmJlYXJpbmcoc3RvcCxuZXh0KSxkdXJhdGlvbjoxMDUwLGVzc2VudGlhbDp0cnVlfSl9aWYocG9wdXApc2V0VGltZW91dCgoKT0+c2hvd1N0b3BQb3B1cChzdG9wLGluZGV4KSw0NTApfQpmdW5jdGlvbiBzaG93U3RvcFBvcHVwKHN0b3AsaW5kZXgpe2lmKGFjdGl2ZVBvcHVwKXt0cnl7YWN0aXZlUG9wdXAucmVtb3ZlKCl9Y2F0Y2h7fX1jb25zdCBhc3NldHM9c3RvcEFzc2V0cyhzdG9wKSxmaXJzdD1hc3NldHNbMF07Y29uc3QgY29udGVudD1gPGRpdiBjbGFzcz0ic3RvcFBvcHVwIj48ZGl2IGNsYXNzPSJzdG9wUG9wdXBJbWFnZSI+JHtmaXJzdD8udGh1bWI/YDxpbWcgc3JjPSIke2VzYyhmaXJzdC50aHVtYil9Ij5gOicnfTwvZGl2PjxkaXYgY2xhc3M9InN0b3BQb3B1cEJvZHkiPjxzcGFuIGNsYXNzPSJwb3B1cEtpY2tlciI+U3RvcCAke2luZGV4KzF9PC9zcGFuPjxkaXYgY2xhc3M9InBvcHVwVGl0bGUiPiR7ZXNjKHN0b3BOYW1lKHN0b3AsaW5kZXgpKX08L2Rpdj48ZGl2IGNsYXNzPSJwb3B1cE1ldGEiPiR7YXNzZXRzLmxlbmd0aH0gcGhvdG9zJm5ic3A7IOKAoiAmbmJzcDske01hdGgucm91bmQoc3RvcC5yYWRpdXNfbXx8MjAwKX0gbSByYWRpdXM8L2Rpdj48ZGl2IGNsYXNzPSJwb3B1cEJ1dHRvbnMiPjxidXR0b24gZGF0YS1wb3B1cC1maWx0ZXI9IiR7ZXNjKHN0b3Auc3RvcF9pZCl9Ij5WaWV3IFBob3RvczwvYnV0dG9uPjxidXR0b24gZGF0YS1wb3B1cC1wcmVzZW50PSIke2luZGV4fSI+4pa2IFByZXNlbnQ8L2J1dHRvbj48YnV0dG9uIGNsYXNzPSJkYW5nZXIiIGRhdGEtcG9wdXAtZGVsZXRlPSIke2VzYyhzdG9wLnN0b3BfaWQpfSI+4oyrPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+YDthY3RpdmVQb3B1cD1uZXcgbWFwbGlicmVnbC5Qb3B1cCh7b2Zmc2V0OjI0LGNsb3NlQnV0dG9uOnRydWUsbWF4V2lkdGg6JzM1MHB4J30pLnNldExuZ0xhdChbc3RvcC5sb24sc3RvcC5sYXRdKS5zZXRIVE1MKGNvbnRlbnQpLmFkZFRvKG1hcCk7c2V0VGltZW91dCgoKT0+e2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoJ1tkYXRhLXBvcHVwLWZpbHRlcl0nKT8uYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT57ZmlsdGVyU3RvcElkPXN0b3Auc3RvcF9pZDtyZW5kZXJHYWxsZXJ5KCl9KTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCdbZGF0YS1wb3B1cC1wcmVzZW50XScpPy5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9Pm9wZW5QcmVzZW50KGluZGV4KSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvcignW2RhdGEtcG9wdXAtZGVsZXRlXScpPy5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PmRlbGV0ZVN0b3Aoc3RvcC5zdG9wX2lkKSl9LDApfQpmdW5jdGlvbiByZW5kZXJTdG9wcygpe2NvbnN0IHN0b3BzPXByb2plY3Q/LnN0b3BzfHxbXSxxPWVsKCdzdG9wU2VhcmNoJykudmFsdWUudHJpbSgpLnRvTG93ZXJDYXNlKCk7ZWwoJ3N0b3BDb3VudCcpLnRleHRDb250ZW50PWAoJHtzdG9wcy5sZW5ndGh9KWA7ZWwoJ3N0b3BMaXN0JykuaW5uZXJIVE1MPXN0b3BzLm1hcCgocyxpKT0+KHtzLGl9KSkuZmlsdGVyKHg9PiFxfHxzdG9wTmFtZSh4LnMseC5pKS50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKHEpKS5tYXAoKHtzLGl9KT0+e2NvbnN0IGNvdW50PShzLmFzc2V0X2lkc3x8W10pLmxlbmd0aCxhY3RpdmU9cy5zdG9wX2lkPT09YWN0aXZlU3RvcElkO3JldHVybmA8YXJ0aWNsZSBjbGFzcz0ic3RvcENhcmQgJHthY3RpdmU/J2FjdGl2ZSBvcGVuJzonJ30iIGRhdGEtc3RvcD0iJHtlc2Mocy5zdG9wX2lkKX0iPjxkaXYgY2xhc3M9InN0b3BTdW1tYXJ5Ij48ZGl2IGNsYXNzPSJzdG9wTnVtYmVyIj4ke2krMX08L2Rpdj48ZGl2PjxkaXYgY2xhc3M9InN0b3BOYW1lIj4ke2VzYyhzdG9wTmFtZShzLGkpKX08L2Rpdj48ZGl2IGNsYXNzPSJzdG9wTWV0YSI+JHtjb3VudH0gcGhvdG9zJm5ic3A7IOKAoiAmbmJzcDske01hdGgucm91bmQocy5yYWRpdXNfbXx8MjAwKX0gbTwvZGl2PjwvZGl2PjxkaXYgY2xhc3M9InN0b3BDaGV2cm9uIj7igLo8L2Rpdj48L2Rpdj48ZGl2IGNsYXNzPSJzdG9wQ29udHJvbHMiPjxidXR0b24gZGF0YS12aWV3PSIke2VzYyhzLnN0b3BfaWQpfSI+VmlldzwvYnV0dG9uPjxidXR0b24gZGF0YS1yZW5hbWU9IiR7ZXNjKHMuc3RvcF9pZCl9Ij5SZW5hbWU8L2J1dHRvbj48YnV0dG9uIGRhdGEtcmVjZW50ZXI9IiR7ZXNjKHMuc3RvcF9pZCl9Ij5SZWNlbnRlcjwvYnV0dG9uPjxidXR0b24gZGF0YS1kZWxldGUtc3RvcD0iJHtlc2Mocy5zdG9wX2lkKX0iPkRlbGV0ZTwvYnV0dG9uPjwvZGl2PjwvYXJ0aWNsZT5gfSkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gc3RvcHMgZm91bmQuPC9kaXY+Jztkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCcuc3RvcFN1bW1hcnknKS5mb3JFYWNoKHJvdz0+cm93LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+e2NvbnN0IGNhcmQ9cm93LmNsb3Nlc3QoJy5zdG9wQ2FyZCcpO2NvbnN0IGlkPWNhcmQuZGF0YXNldC5zdG9wO2lmKGFjdGl2ZVN0b3BJZD09PWlkKWNhcmQuY2xhc3NMaXN0LnRvZ2dsZSgnb3BlbicpO2Vsc2Ugc2VsZWN0U3RvcChpZCx7Zmx5OnRydWUscG9wdXA6dHJ1ZSxmaWx0ZXI6dHJ1ZX0pfSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXZpZXddJykuZm9yRWFjaChiPT5iLmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+c2VsZWN0U3RvcChiLmRhdGFzZXQudmlldyx7Zmx5OnRydWUscG9wdXA6dHJ1ZSxmaWx0ZXI6dHJ1ZX0pKSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtcmVuYW1lXScpLmZvckVhY2goYj0+Yi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PnJlbmFtZVN0b3AoYi5kYXRhc2V0LnJlbmFtZSkpKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1yZWNlbnRlcl0nKS5mb3JFYWNoKGI9PmIuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5yZWNlbnRlclN0b3AoYi5kYXRhc2V0LnJlY2VudGVyKSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLWRlbGV0ZS1zdG9wXScpLmZvckVhY2goYj0+Yi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PmRlbGV0ZVN0b3AoYi5kYXRhc2V0LmRlbGV0ZVN0b3ApKSl9CmZ1bmN0aW9uIGdhbGxlcnlBc3NldHMoKXtpZighcHJvamVjdClyZXR1cm5bXTtpZihmaWx0ZXJTdG9wSWQpe2NvbnN0IHN0b3A9cHJvamVjdC5zdG9wcy5maW5kKHM9PnMuc3RvcF9pZD09PWZpbHRlclN0b3BJZCk7cmV0dXJuIHN0b3BBc3NldHMoc3RvcCl9cmV0dXJuIHByb2plY3QuYXNzZXRzfHxbXX0KZnVuY3Rpb24gcmVuZGVyR2FsbGVyeSgpe2NvbnN0IGFzc2V0cz1nYWxsZXJ5QXNzZXRzKCksc3RvcD1wcm9qZWN0Py5zdG9wcz8uZmluZChzPT5zLnN0b3BfaWQ9PT1maWx0ZXJTdG9wSWQpLGlkeD1zdG9wP3Byb2plY3Quc3RvcHMuaW5kZXhPZihzdG9wKTotMTtlbCgnbWVkaWFUaXRsZScpLnRleHRDb250ZW50PXN0b3A/YFN0b3AgJHtpZHgrMX0gIOKAoiAgJHtzdG9wTmFtZShzdG9wLGlkeCl9YDonTWVkaWEnO2VsKCdtZWRpYUNvdW50JykudGV4dENvbnRlbnQ9YCR7YXNzZXRzLmxlbmd0aH0gaXRlbXNgO2VsKCdmaWx0ZXJDaGlwJykuY2xhc3NMaXN0LnRvZ2dsZSgnc2hvdycsISFzdG9wKTtlbCgnZmlsdGVyQ2hpcFRleHQnKS50ZXh0Q29udGVudD1zdG9wP2BGaWx0ZXI6ICR7c3RvcE5hbWUoc3RvcCxpZHgpfWA6J0ZpbHRlcjogQWxsIFN0b3BzJztlbCgnZ2FsbGVyeScpLmlubmVySFRNTD1hc3NldHMubWFwKGE9PmA8ZGl2IGNsYXNzPSJtZWRpYVRpbGUgJHthLmFzc2V0X2lkPT09YWN0aXZlQXNzZXRJZD8nYWN0aXZlJzonJ30iIGRhdGEtYXNzZXQ9IiR7ZXNjKGEuYXNzZXRfaWQpfSI+JHthLnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoYS50aHVtYil9Ij5gOicnfTxkaXYgY2xhc3M9Im1lZGlhVGlsZU5hbWUiPiR7ZXNjKGEubmFtZXx8J1Bob3RvJyl9PC9kaXY+PC9kaXY+YCkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gR1BTIG1lZGlhIGluIHRoaXMgdmlldy48L2Rpdj4nO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJy5tZWRpYVRpbGUnKS5mb3JFYWNoKHRpbGU9PnRpbGUuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5mb2N1c0Fzc2V0KHRpbGUuZGF0YXNldC5hc3NldCkpKX0KZnVuY3Rpb24gZm9jdXNBc3NldChpZCl7Y29uc3QgYXNzZXQ9KHByb2plY3Q/LmFzc2V0c3x8W10pLmZpbmQoYT0+YS5hc3NldF9pZD09PWlkKTtpZighYXNzZXQpcmV0dXJuO2FjdGl2ZUFzc2V0SWQ9aWQ7cmVuZGVyR2FsbGVyeSgpO2lmKG1hcCltYXAuZmx5VG8oe2NlbnRlcjpbYXNzZXQubG9uLGFzc2V0LmxhdF0sem9vbToxOC41LHBpdGNoOjUyLGJlYXJpbmc6MTIsZHVyYXRpb246OTAwLGVzc2VudGlhbDp0cnVlfSk7aWYoYWN0aXZlUG9wdXApe3RyeXthY3RpdmVQb3B1cC5yZW1vdmUoKX1jYXRjaHt9fWFjdGl2ZVBvcHVwPW5ldyBtYXBsaWJyZWdsLlBvcHVwKHtvZmZzZXQ6MjAsY2xvc2VCdXR0b246dHJ1ZSxtYXhXaWR0aDonMzgwcHgnfSkuc2V0TG5nTGF0KFthc3NldC5sb24sYXNzZXQubGF0XSkuc2V0SFRNTChgPGRpdiBjbGFzcz0ic3RvcFBvcHVwIj48ZGl2IGNsYXNzPSJzdG9wUG9wdXBJbWFnZSI+JHthc3NldC50aHVtYj9gPGltZyBzcmM9IiR7ZXNjKGFzc2V0LnRodW1iKX0iPmA6Jyd9PC9kaXY+PGRpdiBjbGFzcz0ic3RvcFBvcHVwQm9keSI+PHNwYW4gY2xhc3M9InBvcHVwS2lja2VyIj5TZWxlY3RlZCBwaG90bzwvc3Bhbj48ZGl2IGNsYXNzPSJwb3B1cFRpdGxlIj4ke2VzYyhhc3NldC5uYW1lfHwnUGhvdG8nKX08L2Rpdj48ZGl2IGNsYXNzPSJwb3B1cE1ldGEiPiR7ZXNjKGFzc2V0LnRpbWV8fCcnKX08L2Rpdj48L2Rpdj48L2Rpdj5gKS5hZGRUbyhtYXApfQphc3luYyBmdW5jdGlvbiBzYXZlUHJvamVjdCgpe2lmKCFwcm9qZWN0KXJldHVybjtwcm9qZWN0PWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KHByb2plY3QuaWQpLHttZXRob2Q6J1BVVCcsaGVhZGVyczp7J0NvbnRlbnQtVHlwZSc6J2FwcGxpY2F0aW9uL2pzb24nfSxib2R5OkpTT04uc3RyaW5naWZ5KHByb2plY3QpfSk7YXdhaXQgcmVmcmVzaFByb2plY3RTdW1tYXJ5KCk7cmVuZGVyQWxsKCl9CmFzeW5jIGZ1bmN0aW9uIHJlZnJlc2hQcm9qZWN0U3VtbWFyeSgpe3Byb2plY3RzPWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0cycpfQphc3luYyBmdW5jdGlvbiByZW5hbWVQcm9qZWN0KCl7aWYoIXByb2plY3QpcmV0dXJuO2NvbnN0IHZhbHVlPXByb21wdCgnSm91cm5leSBuYW1lJyxwcm9qZWN0Lm5hbWV8fCcnKTtpZighdmFsdWU/LnRyaW0oKSlyZXR1cm47cHJvamVjdC5uYW1lPXZhbHVlLnRyaW0oKTtwcm9qZWN0LnNldHRpbmdzPXByb2plY3Quc2V0dGluZ3N8fHt9O3Byb2plY3Quc2V0dGluZ3MudGl0bGU9cHJvamVjdC5uYW1lO2F3YWl0IHNhdmVQcm9qZWN0KCl9CmFzeW5jIGZ1bmN0aW9uIHJlbmFtZVN0b3AoaWQpe2NvbnN0IGk9cHJvamVjdC5zdG9wcy5maW5kSW5kZXgocz0+cy5zdG9wX2lkPT09aWQpO2lmKGk8MClyZXR1cm47Y29uc3QgdmFsdWU9cHJvbXB0KCdTdG9wIG5hbWUnLHN0b3BOYW1lKHByb2plY3Quc3RvcHNbaV0saSkpO2lmKCF2YWx1ZT8udHJpbSgpKXJldHVybjtwcm9qZWN0LnN0b3BzW2ldLm5hbWU9dmFsdWUudHJpbSgpO2F3YWl0IHNhdmVQcm9qZWN0KCl9CmFzeW5jIGZ1bmN0aW9uIHJlY2VudGVyU3RvcChpZCl7Y29uc3Qgc3RvcD1wcm9qZWN0LnN0b3BzLmZpbmQocz0+cy5zdG9wX2lkPT09aWQpLGFzc2V0cz1zdG9wQXNzZXRzKHN0b3ApO2lmKCFzdG9wfHwhYXNzZXRzLmxlbmd0aClyZXR1cm4gdG9hc3QoJ1RoaXMgc3RvcCBoYXMgbm8gcGhvdG9zIHRvIHJlY2VudGVyIGZyb20uJyk7c3RvcC5sYXQ9YXNzZXRzLnJlZHVjZSgobixhKT0+bitOdW1iZXIoYS5sYXQpLDApL2Fzc2V0cy5sZW5ndGg7c3RvcC5sb249YXNzZXRzLnJlZHVjZSgobixhKT0+bitOdW1iZXIoYS5sb24pLDApL2Fzc2V0cy5sZW5ndGg7YXdhaXQgc2F2ZVByb2plY3QoKTtzZWxlY3RTdG9wKGlkLHtmbHk6dHJ1ZSxwb3B1cDp0cnVlLGZpbHRlcjp0cnVlfSl9CmFzeW5jIGZ1bmN0aW9uIGRlbGV0ZVN0b3AoaWQpe2lmKCFjb25maXJtKCdEZWxldGUgdGhpcyBzdG9wPyBQaG90b3MgcmVtYWluIGluIHRoZSBqb3VybmV5LicpKXJldHVybjtwcm9qZWN0LnN0b3BzPXByb2plY3Quc3RvcHMuZmlsdGVyKHM9PnMuc3RvcF9pZCE9PWlkKTtpZihhY3RpdmVTdG9wSWQ9PT1pZClhY3RpdmVTdG9wSWQ9cHJvamVjdC5zdG9wc1swXT8uc3RvcF9pZHx8bnVsbDtpZihmaWx0ZXJTdG9wSWQ9PT1pZClmaWx0ZXJTdG9wSWQ9YWN0aXZlU3RvcElkO2F3YWl0IHNhdmVQcm9qZWN0KCl9CmFzeW5jIGZ1bmN0aW9uIGFkZFN0b3AoKXtpZighcHJvamVjdHx8IW1hcClyZXR1cm4gdG9hc3QoJ0xvYWQgYSBqb3VybmV5IGZpcnN0LicpO2NvbnN0IGNlbnRlcj1tYXAuZ2V0Q2VudGVyKCk7cHJvamVjdC5zdG9wcz1wcm9qZWN0LnN0b3BzfHxbXTtjb25zdCBzdG9wPXtzdG9wX2lkOmNyeXB0by5yYW5kb21VVUlEKCkuc2xpY2UoMCw4KSxuYW1lOmBTdG9wICR7cHJvamVjdC5zdG9wcy5sZW5ndGgrMX1gLGxhdDpjZW50ZXIubGF0LGxvbjpjZW50ZXIubG5nLHJhZGl1c19tOk51bWJlcihwcm9qZWN0LnNldHRpbmdzPy5zdG9wX3JhZGl1c19tfHwyMDApLGFzc2V0X2lkczpbXSxtb2RlOidtYW51YWwnLGxvY2tlZDpmYWxzZX07cHJvamVjdC5zdG9wcy5wdXNoKHN0b3ApO2F3YWl0IHNhdmVQcm9qZWN0KCk7c2VsZWN0U3RvcChzdG9wLnN0b3BfaWQse2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KX0KYXN5bmMgZnVuY3Rpb24gcmVjbHVzdGVyKCl7aWYoIXByb2plY3QpcmV0dXJuO2NvbnN0IHJhZGl1cz1OdW1iZXIoZWwoJ3N0b3BSYWRpdXMnKS52YWx1ZXx8MjAwKTtwcm9qZWN0PWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KHByb2plY3QuaWQpKycvcmVjbHVzdGVyJyx7bWV0aG9kOidQT1NUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkoe3JhZGl1c19tOnJhZGl1c30pfSk7cHJvamVjdC5zZXR0aW5ncz1wcm9qZWN0LnNldHRpbmdzfHx7fTtwcm9qZWN0LnNldHRpbmdzLnN0b3BfcmFkaXVzX209cmFkaXVzO2FjdGl2ZVN0b3BJZD1wcm9qZWN0LnN0b3BzWzBdPy5zdG9wX2lkfHxudWxsO2ZpbHRlclN0b3BJZD1hY3RpdmVTdG9wSWQ7YXdhaXQgcmVmcmVzaFByb2plY3RTdW1tYXJ5KCk7cmVuZGVyQWxsKCk7c2V0TW9kYWwoJ3NldHRpbmdzTW9kYWwnLGZhbHNlKTt0b2FzdCgnU3RvcHMgcmVjbHVzdGVyZWQnKX0KYXN5bmMgZnVuY3Rpb24gcmV2ZXJzZVJvdXRlKCl7aWYoIXByb2plY3QpcmV0dXJuO3Byb2plY3Quc3RvcHMucmV2ZXJzZSgpO3Byb2plY3Quc2V0dGluZ3M9cHJvamVjdC5zZXR0aW5nc3x8e307cHJvamVjdC5zZXR0aW5ncy5yZXZlcnNlX3JvdXRlPSFwcm9qZWN0LnNldHRpbmdzLnJldmVyc2Vfcm91dGU7YXdhaXQgc2F2ZVByb2plY3QoKTt0b2FzdCgnUm91dGUgb3JkZXIgcmV2ZXJzZWQnKX0KYXN5bmMgZnVuY3Rpb24gdGVzdEltbWljaCgpe2NvbnN0IGJvZHk9e2Jhc2VfdXJsOmVsKCdpbW1pY2hVcmwnKS52YWx1ZS50cmltKCksYXBpX2tleTplbCgnaW1taWNoS2V5JykudmFsdWUudHJpbSgpfTtjb25zdCByZXN1bHQ9YXdhaXQgYXBpKCcvYXBpL2ltbWljaC90ZXN0Jyx7bWV0aG9kOidQT1NUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkoYm9keSl9KTt0b2FzdChyZXN1bHQubWVzc2FnZXx8J0Nvbm5lY3Rpb24gdGVzdGVkJyl9CmFzeW5jIGZ1bmN0aW9uIGNyZWF0ZUltbWljaEpvdXJuZXkoKXtjb25zdCBiYXNlX3VybD1lbCgnaW1taWNoVXJsJykudmFsdWUudHJpbSgpLGFwaV9rZXk9ZWwoJ2ltbWljaEtleScpLnZhbHVlLnRyaW0oKSxzdGFydF9kYXRlPWVsKCdzdGFydERhdGUnKS52YWx1ZSxlbmRfZGF0ZT1lbCgnZW5kRGF0ZScpLnZhbHVlO2lmKCFiYXNlX3VybHx8IWFwaV9rZXl8fCFzdGFydF9kYXRlfHwhZW5kX2RhdGUpcmV0dXJuIHRvYXN0KCdDb21wbGV0ZSB0aGUgSW1taWNoIFVSTCwga2V5LCBhbmQgZGF0ZXMuJyk7c2F2ZUNvbm4oYmFzZV91cmwsYXBpX2tleSk7dG9hc3QoJ0ltcG9ydGluZyBHUFMgbWVkaWEgZnJvbSBJbW1pY2jigKYnKTtjb25zdCBjcmVhdGVkPWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0L2ltbWljaCcse21ldGhvZDonUE9TVCcsaGVhZGVyczp7J0NvbnRlbnQtVHlwZSc6J2FwcGxpY2F0aW9uL2pzb24nfSxib2R5OkpTT04uc3RyaW5naWZ5KHtuYW1lOmBJbW1pY2ggSm91cm5leSAke3N0YXJ0X2RhdGV9IHRvICR7ZW5kX2RhdGV9YCxiYXNlX3VybCxhcGlfa2V5LHN0YXJ0X2RhdGUsZW5kX2RhdGV9KX0pO3NldE1vZGFsKCdpbW1pY2hNb2RhbCcsZmFsc2UpO2F3YWl0IHJlZnJlc2hQcm9qZWN0U3VtbWFyeSgpO2F3YWl0IG9wZW5Qcm9qZWN0KGNyZWF0ZWQuaWQpfQphc3luYyBmdW5jdGlvbiBjcmVhdGVVcGxvYWRKb3VybmV5KCl7Y29uc3QgZmlsZXM9ZWwoJ3VwbG9hZEZpbGVzJykuZmlsZXM7aWYoIWZpbGVzLmxlbmd0aClyZXR1cm4gdG9hc3QoJ0Nob29zZSBtZWRpYSBmaWxlcyBmaXJzdC4nKTtjb25zdCBmb3JtPW5ldyBGb3JtRGF0YSgpO2Zvcihjb25zdCBmaWxlIG9mIGZpbGVzKWZvcm0uYXBwZW5kKCdmaWxlcycsZmlsZSk7Zm9ybS5hcHBlbmQoJ25hbWUnLGVsKCd1cGxvYWROYW1lJykudmFsdWUudHJpbSgpfHwnVXBsb2FkZWQgSm91cm5leScpO3RvYXN0KCdSZWFkaW5nIEdQUyBtZXRhZGF0YeKApicpO2NvbnN0IGNyZWF0ZWQ9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvdXBsb2FkJyx7bWV0aG9kOidQT1NUJyxib2R5OmZvcm19KTtzZXRNb2RhbCgndXBsb2FkTW9kYWwnLGZhbHNlKTthd2FpdCByZWZyZXNoUHJvamVjdFN1bW1hcnkoKTthd2FpdCBvcGVuUHJvamVjdChjcmVhdGVkLmlkKX0KYXN5bmMgZnVuY3Rpb24gcmVuZGVyTXA0KCl7aWYoIXByb2plY3QpcmV0dXJuIHRvYXN0KCdMb2FkIGEgam91cm5leSBmaXJzdC4nKTtwcm9qZWN0LnNldHRpbmdzPXByb2plY3Quc2V0dGluZ3N8fHt9O3Byb2plY3Quc2V0dGluZ3MuZHVyYXRpb25fbWluPTEyO2F3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KHByb2plY3QuaWQpLHttZXRob2Q6J1BVVCcsaGVhZGVyczp7J0NvbnRlbnQtVHlwZSc6J2FwcGxpY2F0aW9uL2pzb24nfSxib2R5OkpTT04uc3RyaW5naWZ5KHByb2plY3QpfSk7Y29uc3QgZm9ybT1uZXcgRm9ybURhdGEoKTtpZihlbCgnYXVkaW9Td2l0Y2gnKS5jbGFzc0xpc3QuY29udGFpbnMoJ29uJykmJmVsKCdhdWRpb0lucHV0JykuZmlsZXNbMF0pZm9ybS5hcHBlbmQoJ2F1ZGlvJyxlbCgnYXVkaW9JbnB1dCcpLmZpbGVzWzBdKTt0b2FzdCgnUmVuZGVyaW5nIE1QNOKApicpO2NvbnN0IHJlc3VsdD1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdC8nK2VuY29kZVVSSUNvbXBvbmVudChwcm9qZWN0LmlkKSsnL3JlbmRlcicse21ldGhvZDonUE9TVCcsYm9keTpmb3JtfSk7Y29uc3QgdXJsPXJlc3VsdC51cmx8fHJlc3VsdC5wYXRofHxyZXN1bHQuZG93bmxvYWRfdXJsO2lmKHVybCl3aW5kb3cub3Blbih1cmwsJ19ibGFuaycpO3RvYXN0KCdSZW5kZXIgY29tcGxldGUnKX0KZnVuY3Rpb24gZW5zdXJlUHJlc2VudE1hcCgpe2lmKHByZXNlbnRNYXApcmV0dXJuO3ByZXNlbnRNYXA9bmV3IG1hcGxpYnJlZ2wuTWFwKHtjb250YWluZXI6J3ByZXNlbnRNYXAnLHN0eWxlOmNsb25lU3R5bGUobWFwU3R5bGVLZXk9PT0nbGlnaHQnPydzYXRlbGxpdGUnOm1hcFN0eWxlS2V5KSxjZW50ZXI6Wy05OCwzOV0sem9vbTozLHBpdGNoOjU1LGJlYXJpbmc6MH0pO3ByZXNlbnRNYXAuYWRkQ29udHJvbChuZXcgbWFwbGlicmVnbC5OYXZpZ2F0aW9uQ29udHJvbCgpLCdib3R0b20tcmlnaHQnKX0KZnVuY3Rpb24gcHJlc2VudEFzc2V0cygpe2NvbnN0IHN0b3A9cHJvamVjdD8uc3RvcHM/LltwcmVzZW50U3RvcEluZGV4XTtyZXR1cm4gc3RvcEFzc2V0cyhzdG9wKX0KZnVuY3Rpb24gcmVuZGVyUHJlc2VudFN0b3BzKCl7Y29uc3Qgc3RvcHM9cHJvamVjdD8uc3RvcHN8fFtdO2VsKCdwcmVzZW50U3RvcFJhaWwnKS5pbm5lckhUTUw9YDxkaXYgc3R5bGU9ImZvbnQtd2VpZ2h0Ojk1MDttYXJnaW46MnB4IDRweCAxMHB4Ij5Kb3VybmV5IFN0b3BzPC9kaXY+YCtzdG9wcy5tYXAoKHMsaSk9PmA8ZGl2IGNsYXNzPSJwcmVzZW50U3RvcEl0ZW0gJHtpPT09cHJlc2VudFN0b3BJbmRleD8nYWN0aXZlJzonJ30iIGRhdGEtcHJlc2VudC1zdG9wPSIke2l9Ij48Yj4ke2krMX0uPC9iPiZuYnNwOyAke2VzYyhzdG9wTmFtZShzLGkpKX08ZGl2IGNsYXNzPSJzbWFsbCI+JHsocy5hc3NldF9pZHN8fFtdKS5sZW5ndGh9IHBob3RvczwvZGl2PjwvZGl2PmApLmpvaW4oJycpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXByZXNlbnQtc3RvcF0nKS5mb3JFYWNoKHg9PnguYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5nb1ByZXNlbnRTdG9wKE51bWJlcih4LmRhdGFzZXQucHJlc2VudFN0b3ApKSkpfQpmdW5jdGlvbiByZW5kZXJQcmVzZW50RmlsbXN0cmlwKCl7Y29uc3QgYXNzZXRzPXByZXNlbnRBc3NldHMoKTtlbCgncHJlc2VudEZpbG1zdHJpcCcpLmlubmVySFRNTD1hc3NldHMubWFwKChhLGkpPT5gPGRpdiBjbGFzcz0icHJlc2VudFRodW1iICR7aT09PXByZXNlbnRQaG90b0luZGV4PydhY3RpdmUnOicnfSIgZGF0YS1wcmVzZW50LXBob3RvPSIke2l9Ij4ke2EudGh1bWI/YDxpbWcgc3JjPSIke2VzYyhhLnRodW1iKX0iPmA6Jyd9PGRpdiBjbGFzcz0icHJlc2VudFRodW1iTGFiZWwiPiR7ZXNjKGEubmFtZXx8J1Bob3RvJyl9PC9kaXY+PC9kaXY+YCkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gcGhvdG9zIGFzc2lnbmVkIHRvIHRoaXMgc3RvcC48L2Rpdj4nO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXByZXNlbnQtcGhvdG9dJykuZm9yRWFjaCh4PT54LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+Z29QcmVzZW50UGhvdG8oTnVtYmVyKHguZGF0YXNldC5wcmVzZW50UGhvdG8pKSkpfQpmdW5jdGlvbiByZW5kZXJQcmVzZW50TWFwTGF5ZXJzKCl7aWYoIXByZXNlbnRNYXB8fCFwcmVzZW50TWFwLmlzU3R5bGVMb2FkZWQoKSlyZXR1cm47cHJlc2VudE1hcmtlcnMuZm9yRWFjaChtPT5tLnJlbW92ZSgpKTtwcmVzZW50TWFya2Vycz1bXTtjb25zdCBzdG9wcz1wcm9qZWN0Py5zdG9wc3x8W107YWRkUm91dGVMYXllcnMocHJlc2VudE1hcCwncHJlc2VudCcsc3RvcHMubWFwKHM9PltzLmxvbixzLmxhdF0pKTtzdG9wcy5mb3JFYWNoKChzLGkpPT57Y29uc3Qgbm9kZT1tYXJrZXJFbGVtZW50KHMsaSx0cnVlKTtub2RlLm9uY2xpY2s9KCk9PmdvUHJlc2VudFN0b3AoaSk7cHJlc2VudE1hcmtlcnMucHVzaChuZXcgbWFwbGlicmVnbC5NYXJrZXIoe2VsZW1lbnQ6bm9kZX0pLnNldExuZ0xhdChbcy5sb24scy5sYXRdKS5hZGRUbyhwcmVzZW50TWFwKSl9KX0KZnVuY3Rpb24gZ29QcmVzZW50U3RvcChpbmRleCl7Y29uc3Qgc3RvcHM9cHJvamVjdD8uc3RvcHN8fFtdO2lmKCFzdG9wcy5sZW5ndGgpcmV0dXJuO3ByZXNlbnRTdG9wSW5kZXg9KGluZGV4K3N0b3BzLmxlbmd0aCklc3RvcHMubGVuZ3RoO3ByZXNlbnRQaG90b0luZGV4PTA7Y29uc3Qgc3RvcD1zdG9wc1twcmVzZW50U3RvcEluZGV4XSxuZXh0PXN0b3BzWyhwcmVzZW50U3RvcEluZGV4KzEpJXN0b3BzLmxlbmd0aF18fHN0b3A7cmVuZGVyUHJlc2VudFN0b3BzKCk7cmVuZGVyUHJlc2VudEZpbG1zdHJpcCgpO2VsKCdwcmVzZW50SGVhZGVyVGl0bGUnKS50ZXh0Q29udGVudD1zdG9wTmFtZShzdG9wLHByZXNlbnRTdG9wSW5kZXgpO2VsKCdwcmVzZW50SGVhZGVyTWV0YScpLnRleHRDb250ZW50PWBTdG9wICR7cHJlc2VudFN0b3BJbmRleCsxfSBvZiAke3N0b3BzLmxlbmd0aH0g4oCiICR7KHN0b3AuYXNzZXRfaWRzfHxbXSkubGVuZ3RofSBwaG90b3NgO2VsKCdwcmVzZW50UGhvdG9DYXJkJykuY2xhc3NMaXN0LnJlbW92ZSgnc2hvdycpO3ByZXNlbnRNYXAuZmx5VG8oe2NlbnRlcjpbc3RvcC5sb24sc3RvcC5sYXRdLHpvb206MTUuMyxwaXRjaDo1OCxiZWFyaW5nOmJlYXJpbmcoc3RvcCxuZXh0KSxkdXJhdGlvbjoxNjAwLGN1cnZlOjEuNDUsZXNzZW50aWFsOnRydWV9KX0KZnVuY3Rpb24gZ29QcmVzZW50UGhvdG8oaW5kZXgpe2NvbnN0IGFzc2V0cz1wcmVzZW50QXNzZXRzKCk7aWYoIWFzc2V0cy5sZW5ndGgpcmV0dXJuO3ByZXNlbnRQaG90b0luZGV4PShpbmRleCthc3NldHMubGVuZ3RoKSVhc3NldHMubGVuZ3RoO2NvbnN0IGFzc2V0PWFzc2V0c1twcmVzZW50UGhvdG9JbmRleF07cmVuZGVyUHJlc2VudEZpbG1zdHJpcCgpO2VsKCdwcmVzZW50UGhvdG9DYXJkJykuaW5uZXJIVE1MPWAke2Fzc2V0LnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoYXNzZXQudGh1bWIpfSI+YDonJ308ZGl2IGNsYXNzPSJwcmVzZW50UGhvdG9Cb2R5Ij48ZGl2IGNsYXNzPSJwcmVzZW50UGhvdG9UaXRsZSI+JHtlc2MoYXNzZXQubmFtZXx8J1Bob3RvJyl9PC9kaXY+PGRpdiBjbGFzcz0icHJlc2VudFBob3RvTWV0YSI+JHtlc2MoYXNzZXQudGltZXx8JycpfTwvZGl2PjwvZGl2PmA7ZWwoJ3ByZXNlbnRQaG90b0NhcmQnKS5jbGFzc0xpc3QuYWRkKCdzaG93Jyk7cHJlc2VudE1hcC5mbHlUbyh7Y2VudGVyOlthc3NldC5sb24sYXNzZXQubGF0XSx6b29tOjE4LjMscGl0Y2g6NjIsYmVhcmluZzoocHJlc2VudFBob3RvSW5kZXgqMjMpJTM2MCxkdXJhdGlvbjoxMjUwLGN1cnZlOjEuMjUsZXNzZW50aWFsOnRydWV9KX0KZnVuY3Rpb24gb3BlblByZXNlbnQoaW5kZXg9MCl7aWYoIXByb2plY3Q/LnN0b3BzPy5sZW5ndGgpcmV0dXJuIHRvYXN0KCdMb2FkIGEgam91cm5leSB3aXRoIHN0b3BzIGZpcnN0LicpO2VsKCdwcmVzZW50T3ZlcmxheScpLmNsYXNzTGlzdC5hZGQoJ3Nob3cnKTtlbnN1cmVQcmVzZW50TWFwKCk7c2V0VGltZW91dCgoKT0+e3ByZXNlbnRNYXAucmVzaXplKCk7aWYocHJlc2VudE1hcC5pc1N0eWxlTG9hZGVkKCkpe3JlbmRlclByZXNlbnRNYXBMYXllcnMoKTtnb1ByZXNlbnRTdG9wKGluZGV4KX1lbHNlIHByZXNlbnRNYXAub25jZSgnbG9hZCcsKCk9PntyZW5kZXJQcmVzZW50TWFwTGF5ZXJzKCk7Z29QcmVzZW50U3RvcChpbmRleCl9KX0sNjApfQpmdW5jdGlvbiBjbG9zZVByZXNlbnQoKXtjbGVhckludGVydmFsKHByZXNlbnRUaW1lcik7cHJlc2VudFRpbWVyPW51bGw7ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykudGV4dENvbnRlbnQ9J+KWtiBQbGF5JztlbCgncHJlc2VudE92ZXJsYXknKS5jbGFzc0xpc3QucmVtb3ZlKCdzaG93Jyl9CmZ1bmN0aW9uIHRvZ2dsZVBsYXkoKXtpZihwcmVzZW50VGltZXIpe2NsZWFySW50ZXJ2YWwocHJlc2VudFRpbWVyKTtwcmVzZW50VGltZXI9bnVsbDtlbCgncGxheUpvdXJuZXlCdXR0b24nKS50ZXh0Q29udGVudD0n4pa2IFBsYXknO3JldHVybn1lbCgncGxheUpvdXJuZXlCdXR0b24nKS50ZXh0Q29udGVudD0n4oWhIFBhdXNlJztwcmVzZW50VGltZXI9c2V0SW50ZXJ2YWwoKCk9Pntjb25zdCBhc3NldHM9cHJlc2VudEFzc2V0cygpO2lmKGFzc2V0cy5sZW5ndGgmJnByZXNlbnRQaG90b0luZGV4PGFzc2V0cy5sZW5ndGgtMSlnb1ByZXNlbnRQaG90byhwcmVzZW50UGhvdG9JbmRleCsxKTtlbHNlIGdvUHJlc2VudFN0b3AocHJlc2VudFN0b3BJbmRleCsxKX0sMzQwMCl9CmZ1bmN0aW9uIGRvd25sb2FkR3B4KCl7aWYoIXByb2plY3QpcmV0dXJuO2NvbnN0IHBvaW50cz0ocHJvamVjdC5zdG9wc3x8W10pLm1hcCgocyxpKT0+YDx3cHQgbGF0PSIke3MubGF0fSIgbG9uPSIke3MubG9ufSI+PG5hbWU+JHtlc2Moc3RvcE5hbWUocyxpKSl9PC9uYW1lPjwvd3B0PmApLmpvaW4oJycpO2NvbnN0IGdweD1gPD94bWwgdmVyc2lvbj0iMS4wIj8+PGdweCB2ZXJzaW9uPSIxLjEiIGNyZWF0b3I9IlRyaXBweSI+JHtwb2ludHN9PC9ncHg+YDtjb25zdCBibG9iPW5ldyBCbG9iKFtncHhdLHt0eXBlOidhcHBsaWNhdGlvbi9ncHgreG1sJ30pLGE9ZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgnYScpO2EuaHJlZj1VUkwuY3JlYXRlT2JqZWN0VVJMKGJsb2IpO2EuZG93bmxvYWQ9KHByb2plY3QubmFtZXx8J3RyaXBweScpKycuZ3B4JzthLmNsaWNrKCk7VVJMLnJldm9rZU9iamVjdFVSTChhLmhyZWYpfQpmdW5jdGlvbiBiaW5kKCl7ZWwoJ25ld0ltbWljaEJ1dHRvbicpLm9uY2xpY2s9KCk9PnNldE1vZGFsKCdpbW1pY2hNb2RhbCcpO2VsKCd1cGxvYWRCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNb2RhbCgndXBsb2FkTW9kYWwnKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1jbG9zZV0nKS5mb3JFYWNoKGI9PmIub25jbGljaz0oKT0+c2V0TW9kYWwoYi5kYXRhc2V0LmNsb3NlLGZhbHNlKSk7ZWwoJ3Byb2plY3RTZWFyY2hCdXR0b24nKS5vbmNsaWNrPSgpPT5lbCgncHJvamVjdFNlYXJjaCcpLmNsYXNzTGlzdC50b2dnbGUoJ2hpZGRlbicpO2VsKCdwcm9qZWN0U2VhcmNoJykub25pbnB1dD1yZW5kZXJQcm9qZWN0cztlbCgncmVuYW1lUHJvamVjdEJ1dHRvbicpLm9uY2xpY2s9cmVuYW1lUHJvamVjdDtlbCgncHJlc2VudEJ1dHRvbicpLm9uY2xpY2s9KCk9Pm9wZW5QcmVzZW50KDApO2VsKCdleHBvcnRKdW1wQnV0dG9uJykub25jbGljaz0oKT0+e2VsKCdleHBvcnRCb3gnKS5jbGFzc0xpc3QucmVtb3ZlKCdjb2xsYXBzZWQnKTtlbCgnZXhwb3J0Qm94Jykuc2Nyb2xsSW50b1ZpZXcoe2JlaGF2aW9yOidzbW9vdGgnLGJsb2NrOidlbmQnfSl9O2VsKCdzZXR0aW5nc0J1dHRvbicpLm9uY2xpY2s9KCk9PntlbCgnc3RvcFJhZGl1cycpLnZhbHVlPXByb2plY3Q/LnNldHRpbmdzPy5zdG9wX3JhZGl1c19tfHwyMDA7c2V0TW9kYWwoJ3NldHRpbmdzTW9kYWwnKX07ZWwoJ2FjY291bnRCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNb2RhbCgnYWNjb3VudE1vZGFsJyk7ZWwoJ3NhdmVBY2NvdW50QnV0dG9uJykub25jbGljaz0oKT0+e3NhdmVDb25uKGVsKCdhY2NvdW50VXJsJykudmFsdWUudHJpbSgpLGVsKCdhY2NvdW50S2V5JykudmFsdWUudHJpbSgpKTt0b2FzdCgnSW1taWNoIGNvbm5lY3Rpb24gc2F2ZWQnKTtzZXRNb2RhbCgnYWNjb3VudE1vZGFsJyxmYWxzZSl9O2VsKCd0ZXN0SW1taWNoQnV0dG9uJykub25jbGljaz0oKT0+dGVzdEltbWljaCgpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdjcmVhdGVKb3VybmV5QnV0dG9uJykub25jbGljaz0oKT0+Y3JlYXRlSW1taWNoSm91cm5leSgpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdjcmVhdGVVcGxvYWRCdXR0b24nKS5vbmNsaWNrPSgpPT5jcmVhdGVVcGxvYWRKb3VybmV5KCkuY2F0Y2goZT0+dG9hc3QoZS5tZXNzYWdlKSk7ZWwoJ3N0b3BTZWFyY2hCdXR0b24nKS5vbmNsaWNrPSgpPT5lbCgnc3RvcFNlYXJjaFdyYXAnKS5jbGFzc0xpc3QudG9nZ2xlKCdzaG93Jyk7ZWwoJ3N0b3BTZWFyY2gnKS5vbmlucHV0PXJlbmRlclN0b3BzO2VsKCdhZGRTdG9wQnV0dG9uJykub25jbGljaz1hZGRTdG9wO2VsKCdleHBvcnRIZWFkZXInKS5vbmNsaWNrPSgpPT5lbCgnZXhwb3J0Qm94JykuY2xhc3NMaXN0LnRvZ2dsZSgnY29sbGFwc2VkJyk7ZWwoJ2F1ZGlvU3dpdGNoJykub25jbGljaz0oKT0+e2VsKCdhdWRpb1N3aXRjaCcpLmNsYXNzTGlzdC50b2dnbGUoJ29uJyk7aWYoZWwoJ2F1ZGlvU3dpdGNoJykuY2xhc3NMaXN0LmNvbnRhaW5zKCdvbicpKWVsKCdhdWRpb0lucHV0JykuY2xpY2soKX07ZWwoJ3JlbmRlckJ1dHRvbicpLm9uY2xpY2s9KCk9PnJlbmRlck1wNCgpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdncHhCdXR0b24nKS5vbmNsaWNrPWRvd25sb2FkR3B4O2VsKCdpbWFnZVNldEJ1dHRvbicpLm9uY2xpY2s9KCk9PnRvYXN0KCdJbWFnZSBTZXQgZXhwb3J0IGlzIGNvbWluZyBuZXh0LicpO2VsKCdjbGVhckZpbHRlckJ1dHRvbicpLm9uY2xpY2s9KCk9PntmaWx0ZXJTdG9wSWQ9bnVsbDthY3RpdmVTdG9wSWQ9bnVsbDtyZW5kZXJHYWxsZXJ5KCk7cmVuZGVyU3RvcHMoKTtyZW5kZXJNYXAoZmFsc2UpfTtlbCgnbG9jYXRlQnV0dG9uJykub25jbGljaz0oKT0+bmF2aWdhdG9yLmdlb2xvY2F0aW9uPy5nZXRDdXJyZW50UG9zaXRpb24ocD0+bWFwLmZseVRvKHtjZW50ZXI6W3AuY29vcmRzLmxvbmdpdHVkZSxwLmNvb3Jkcy5sYXRpdHVkZV0sem9vbToxNSxkdXJhdGlvbjo5MDB9KSwoKT0+dG9hc3QoJ0xvY2F0aW9uIHVuYXZhaWxhYmxlJykpO2VsKCd6b29tSW5CdXR0b24nKS5vbmNsaWNrPSgpPT5tYXA/Lnpvb21JbigpO2VsKCd6b29tT3V0QnV0dG9uJykub25jbGljaz0oKT0+bWFwPy56b29tT3V0KCk7ZWwoJ2xpZ2h0TWFwQnV0dG9uJykub25jbGljaz0oKT0+c2V0TWFwU3R5bGUoJ2xpZ2h0Jyk7ZWwoJ2RhcmtNYXBCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNYXBTdHlsZSgnZGFyaycpO2VsKCdzYXRlbGxpdGVNYXBCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNYXBTdHlsZSgnc2F0ZWxsaXRlJyk7ZWwoJ2RlZmF1bHRNYXBTZWxlY3QnKS5vbmNoYW5nZT1lPT5zZXRNYXBTdHlsZShlLnRhcmdldC52YWx1ZSk7ZWwoJ3JlY2x1c3RlckJ1dHRvbicpLm9uY2xpY2s9KCk9PnJlY2x1c3RlcigpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdyZXZlcnNlUm91dGVCdXR0b24nKS5vbmNsaWNrPSgpPT5yZXZlcnNlUm91dGUoKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgnY2xvc2VQcmVzZW50QnV0dG9uJykub25jbGljaz1jbG9zZVByZXNlbnQ7ZWwoJ3ByZXZpb3VzU3RvcEJ1dHRvbicpLm9uY2xpY2s9KCk9PmdvUHJlc2VudFN0b3AocHJlc2VudFN0b3BJbmRleC0xKTtlbCgnbmV4dFN0b3BCdXR0b24nKS5vbmNsaWNrPSgpPT5nb1ByZXNlbnRTdG9wKHByZXNlbnRTdG9wSW5kZXgrMSk7ZWwoJ3ByZXZpb3VzUGhvdG9CdXR0b24nKS5vbmNsaWNrPSgpPT5nb1ByZXNlbnRQaG90byhwcmVzZW50UGhvdG9JbmRleC0xKTtlbCgnbmV4dFBob3RvQnV0dG9uJykub25jbGljaz0oKT0+Z29QcmVzZW50UGhvdG8ocHJlc2VudFBob3RvSW5kZXgrMSk7ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykub25jbGljaz10b2dnbGVQbGF5fQppbml0Rm9ybXMoKTtiaW5kKCk7ZW5zdXJlTWFwKCk7c2V0TWFwU3R5bGUobWFwU3R5bGVLZXkpO2xvYWRQcm9qZWN0cygpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpOwo8L3NjcmlwdD4KPC9ib2R5Pgo8L2h0bWw+
EOF_TRIPPY_FRONTEND_B64
base64 -d /tmp/trippy_frontend.b64 >/opt/trippy/frontend/index.html
rm -f /tmp/trippy_frontend.b64"

step "Installing render/runtime dependencies"
run_bg "Installing Python packages, Playwright, and Chromium" pct exec "$CTID" -- bash -lc "
set -e
cd $APP_DIR/backend
python3 -m venv venv
./venv/bin/pip install --upgrade pip >/dev/null
./venv/bin/pip install -r requirements.txt >/dev/null
cd $APP_DIR
npm init -y >/dev/null
npm install playwright maplibre-gl >/dev/null
mkdir -p $APP_DIR/frontend/vendor
cp $APP_DIR/node_modules/maplibre-gl/dist/maplibre-gl.js $APP_DIR/frontend/vendor/maplibre-gl.js
cp $APP_DIR/node_modules/maplibre-gl/dist/maplibre-gl.css $APP_DIR/frontend/vendor/maplibre-gl.css
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








pct exec "$CTID" -- bash -lc "grep -q 'Trippy v10.2.2' /opt/trippy/frontend/index.html && grep -q 'presentMap' /opt/trippy/frontend/index.html && grep -q 'photoMarker' /opt/trippy/frontend/index.html && test -s /opt/trippy/frontend/vendor/maplibre-gl.js" >/dev/null 2>&1 || {
  printf "${RED}ERROR:${RESET} UI smoke check failed. Frontend or local MapLibre assets are missing.
"
  exit 1
}

step "Waiting for network"
sleep 3
IP="$(pct exec "$CTID" -- bash -lc "hostname -I | awk '{print \$1}'" | tr -d '\r')"

step "Install complete"
echo
printf "${GREEN}${BOLD}Trippy is ready.${RESET}\n"
printf "  ${BOLD}CTID:${RESET}     $CTID\n"
printf "  ${BOLD}Hostname:${RESET} Trippy\n"
printf "  ${BOLD}URL:${RESET}      http://${IP}:${PORT}\n"
echo
printf "${DIM}Default root password: $PASSWORD${RESET}\n"
printf "${DIM}Change it after install: pct enter $CTID && passwd${RESET}\n"
echo
printf "${CYAN}${BOLD}v10.2.2 features${RESET}\n"
printf "  ${CYAN}•${RESET} Full mockup-driven frontend replacement\n"
printf "  ${CYAN}•${RESET} Light OSM, dark, and satellite map modes\n"
printf "  ${CYAN}•${RESET} Thumbnail stop markers, route glow, and single clean popups\n"
printf "  ${CYAN}•${RESET} Cinematic Present Journey with stop and photo fly-through controls\n"
printf "  ${CYAN}•${RESET} Immich date-range import and upload-based GPS media import\n"
printf "  ${CYAN}•${RESET} Stop clustering, renaming, recentering, deletion, and route reversal\n"
printf "  ${CYAN}•${RESET} Project deletion, saved Immich connection, GPX, and MP4 export\n"
printf "  ${CYAN}•${RESET} Local MapLibre bundle for reliable frontend loading\n"
printf "  ${CYAN}•${RESET} Auto-selects the next available CTID and uses hostname Trippy\n"
printf "${PINK}${BOLD}Go make something weird.${RESET}\n"
