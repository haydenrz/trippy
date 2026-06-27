#!/usr/bin/env bash
set -euo pipefail
USER_SUPPLIED_CTID="${CTID:-}"

# Trippy v10.2.0: Immich-style web UI route-tour generator for Proxmox LXC
# Adds stop-based clustering, stop radius, stop review/editing, and lasso grouping.
#
# Run on Proxmox host:
#   bash trippy-install-v10.2.0.sh
#
# Optional:
#   CTID=106 STORAGE=local-lvm BRIDGE=vmbr0 bash trippy-install-v10.2.0.sh

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

printf "${CYAN}${BOLD}Trippy v10.2.0 Clean Installer${RESET}\n"
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

pct set "$CTID" --description "🧭 Trippy v10.2.0
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

for p in [UPLOADS, EXPORTS, WORK, PROJECTS]:
    p.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Trippy", version="1.2.0")
app.mount("/exports", StaticFiles(directory=str(EXPORTS)), name="exports")
app.mount("/uploads", StaticFiles(directory=str(UPLOADS)), name="uploads")

@app.get("/api/health")
def health():
    return {
        "ok": True,
        "app": "trippy",
        "version": "1.2.0",
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
// Trippy v10.2.0 UI behavior upgrades
(function(){{
  function ready(fn){{ if(document.readyState!=='loading') fn(); else document.addEventListener('DOMContentLoaded',fn); }}
  window.TRIPPY_VERSION='v10.2.0';
  ready(() => {{
    if(!document.querySelector('.versionBadge')){{
      const v=document.createElement('div'); v.className='versionBadge'; v.textContent='v10.2.0'; document.body.appendChild(v);
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
      const v=document.createElement('div');v.className='versionBadge';v.textContent='v10.2.0';document.body.appendChild(v);
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

/* Trippy v10.2.0 UI refresh */
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


# v10.2.0: patch the ACTUAL served frontend file, not backend/main.py.
pct exec "$CTID" -- bash -lc "cat >>/opt/trippy/frontend/index.html <<'EOF_FRONTEND_PATCH'

<style id=\"TRIPPY_UI_V1012_STYLE\">
:root{--trippy-bg:#03070d;--trippy-panel:#08111c;--trippy-line:#1d3348;--trippy-cyan:#00d9ff;--trippy-blue:#247cff;--trippy-pink:#ff4da6;--trippy-green:#27d97f;--trippy-text:#eef7ff;--trippy-muted:#8fa6b8}
body{background:radial-gradient(circle at 12% 10%,rgba(0,217,255,.18),transparent 26%),radial-gradient(circle at 82% 18%,rgba(36,124,255,.12),transparent 32%),linear-gradient(145deg,#03070d,#07101a 58%,#02040a)!important;color:var(--trippy-text)!important}
aside,.sidebar,.left,.panel,#projects,.right,.settings,.card,section{background:rgba(8,17,28,.90)!important;border-color:rgba(75,126,164,.30)!important;box-shadow:0 18px 64px rgba(0,0,0,.36)!important;backdrop-filter:blur(14px)}
button{border-radius:14px!important;border:1px solid rgba(68,131,176,.48)!important;background:linear-gradient(180deg,rgba(20,44,69,.96),rgba(11,27,45,.96))!important;color:#ecfbff!important;font-weight:800!important}
button:hover{border-color:var(--trippy-cyan)!important;box-shadow:0 0 22px rgba(0,217,255,.28)!important}
button.primary,button[onclick*=\"createImmich\"],button[onclick*=\"openPreviewSuite\"],button[onclick*=\"render\"],.presentHero{background:linear-gradient(135deg,#0726a8,#00a3c7)!important;border-color:rgba(0,217,255,.85)!important;box-shadow:0 0 28px rgba(0,217,255,.30)!important}
input,select,textarea{background:#07101a!important;color:var(--trippy-text)!important;border:1px solid rgba(89,139,174,.38)!important;border-radius:14px!important}
#map,.mapwrap{border-radius:22px!important;overflow:hidden;box-shadow:inset 0 0 0 1px rgba(0,217,255,.20),0 20px 80px rgba(0,0,0,.34)!important}
.versionBadge{position:fixed;left:16px;top:12px;z-index:9999;color:#18f0ff;font-weight:950;font-size:15px;letter-spacing:.4px;text-shadow:0 0 12px rgba(0,217,255,.7);background:rgba(3,7,13,.65);border:1px solid rgba(0,217,255,.28);border-radius:999px;padding:5px 10px}
.trippyBrand{display:flex;align-items:center;gap:12px;margin:22px 12px 20px}
.trippyLogo{width:62px;height:62px;position:relative;filter:drop-shadow(0 0 12px rgba(0,217,255,.28))}
.trippyLogo .petal{position:absolute;left:23px;top:3px;width:28px;height:44px;border-radius:24px 24px 10px 10px;transform-origin:8px 28px;mix-blend-mode:screen}
.trippyLogo .p1{background:#ff2727;transform:rotate(0deg) skewX(-16deg)}
.trippyLogo .p2{background:#ffb300;transform:rotate(72deg) skewX(17deg)}
.trippyLogo .p3{background:#18c957;transform:rotate(144deg) skewX(-13deg)}
.trippyLogo .p4{background:#2385ff;transform:rotate(216deg) skewX(15deg)}
.trippyLogo .p5{background:#e66ab5;transform:rotate(288deg) skewX(-18deg)}
.trippyLogo:after{content:\"\";position:absolute;inset:18px;border:2px solid rgba(0,217,255,.86);border-radius:50%;box-shadow:0 0 10px rgba(0,217,255,.7)}
.trippyWord{font-size:38px;font-weight:950;font-style:italic;line-height:1;color:white;letter-spacing:-1px;text-shadow:2px 0 #00d9ff,-2px 0 #ff4da6,0 4px 18px rgba(0,0,0,.9)}
.stop.collapsed .row{display:none!important}
.stop{border-radius:16px!important;transition:.18s ease}
.stop:hover,.stop.active{border-color:var(--trippy-cyan)!important;box-shadow:0 0 22px rgba(0,217,255,.18)!important}
.stopSummary{cursor:pointer;display:flex;align-items:center;justify-content:space-between;gap:8px}
.stopChevron{color:var(--trippy-muted);font-weight:900}
.tile{border-radius:16px!important;overflow:hidden;transition:.16s ease}
.tile.focused,.tile:hover{transform:translateY(-2px) scale(1.02);box-shadow:0 0 25px rgba(0,217,255,.32)!important}
.photoPopup img{width:180px;height:110px;object-fit:cover;border-radius:12px;display:block;margin-bottom:8px}
</style>

<script id=\"TRIPPY_UI_V1012_SCRIPT\">
(function(){
  function ready(fn){if(document.readyState!==\"loading\")fn();else document.addEventListener(\"DOMContentLoaded\",fn);}
  function installChrome(){
    if(!document.querySelector(\".versionBadge\")){
      const v=document.createElement(\"div\");v.className=\"versionBadge\";v.textContent=\"v10.2.0\";document.body.appendChild(v);
    }
    const side=document.querySelector(\"aside,.sidebar,.left\")||document.body.firstElementChild;
    if(side && !document.querySelector(\".trippyBrand\")){
      const oldLogo=side.querySelector(\"h1,.brand,.logo\");
      if(oldLogo) oldLogo.style.display=\"none\";
      const brand=document.createElement(\"div\");brand.className=\"trippyBrand\";
      brand.innerHTML='<div class=\"trippyLogo\"><span class=\"petal p1\"></span><span class=\"petal p2\"></span><span class=\"petal p3\"></span><span class=\"petal p4\"></span><span class=\"petal p5\"></span></div><div class=\"trippyWord\">trippy</div>';
      side.prepend(brand);
    }
    document.querySelectorAll(\"button\").forEach(b=>{
      const t=(b.textContent||\"\").toLowerCase();
      if(t.includes(\"preview\")||t.includes(\"present\")){b.classList.add(\"presentHero\");b.textContent=\"▶ Present Journey\";}
    });
    if(![...document.querySelectorAll(\"button\")].some(b=>(b.textContent||\"\").includes(\"Present Journey\"))){
      const bar=document.querySelector(\".toolbar,.topbar,header\")||document.body;
      const btn=document.createElement(\"button\");
      btn.className=\"presentHero\";
      btn.textContent=\"▶ Present Journey\";
      btn.onclick=()=>{ if(window.openPreviewSuite) window.openPreviewSuite(); else alert(\"Present Mode will be available after a project is loaded.\"); };
      bar.appendChild(btn);
    }
  }
  function collapseStops(){
    document.querySelectorAll(\".stop\").forEach((el,idx)=>{
      if(el.dataset.v1012)return;
      el.dataset.v1012=\"1\";el.classList.add(\"collapsed\");
      const b=el.querySelector(\"b\");const small=el.querySelector(\".small\");
      const summary=document.createElement(\"div\");summary.className=\"stopSummary\";
      summary.innerHTML=\"<div>\"+(b?b.outerHTML:\"<b>Stop \"+(idx+1)+\"</b>\")+(small?small.outerHTML:\"\")+\"</div><span class='stopChevron'>›</span>\";
      if(b)b.remove();if(small)small.remove();el.prepend(summary);
      summary.addEventListener(\"click\",ev=>{ev.stopPropagation();document.querySelectorAll(\".stop\").forEach(x=>{if(x!==el)x.classList.add(\"collapsed\")});el.classList.toggle(\"collapsed\");});
    });
  }
  ready(()=>{installChrome();setTimeout(collapseStops,600);setInterval(()=>{installChrome();collapseStops();},1600);});
  const oldFocusAsset=window.focusAsset;
  if(typeof oldFocusAsset===\"function\"){
    window.focusAsset=function(i){
      oldFocusAsset(i);
      try{
        const a=project.assets[i];if(!a||!map)return;
        if(map.flyTo)map.flyTo({center:[a.lon,a.lat],zoom:19,pitch:45,bearing:0,duration:850});
        const h=\"<div class='photoPopup'>\"+(a.thumb?\"<img src='\"+a.thumb+\"'>\":\"\")+\"<b>\"+(a.name||\"Photo\")+\"</b><br><span>\"+(a.time||\"\")+\"</span></div>\";
        if(window.maplibregl&&maplibregl.Popup)new maplibregl.Popup({offset:18,closeButton:true}).setLngLat([a.lon,a.lat]).setHTML(h).addTo(map);
        else if(window.L&&L.popup)L.popup().setLatLng([a.lat,a.lon]).setContent(h).openOn(map);
      }catch(e){console.warn(e);}
    }
  }
})();
</script>
EOF_FRONTEND_PATCH"


# v10.2.0: real frontend redesign patch against the served index.html.
pct exec "$CTID" -- bash -lc "cat >>/opt/trippy/frontend/index.html <<'EOF_FRONTEND_PATCH_1013'

<style id=\"TRIPPY_UI_V1013_STYLE\">
:root{
  --trippy-bg:#020712;--trippy-panel:#07111d;--trippy-panel2:#0b1725;--trippy-line:#18344c;
  --trippy-cyan:#00d9ff;--trippy-cyan2:#18f0ff;--trippy-blue:#247cff;--trippy-violet:#6d4dff;
  --trippy-pink:#ff4da6;--trippy-green:#27d97f;--trippy-orange:#ff7a1a;--trippy-text:#eef7ff;--trippy-muted:#91a6b8
}
*{box-sizing:border-box}
body{
  background:
    radial-gradient(circle at 8% 0%,rgba(0,217,255,.14),transparent 28%),
    radial-gradient(circle at 88% 12%,rgba(109,77,255,.11),transparent 34%),
    linear-gradient(145deg,#020712,#06111d 55%,#02050b)!important;
  color:var(--trippy-text)!important;
  font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif!important;
}
aside,.sidebar,.left{
  width:300px!important;
  background:linear-gradient(180deg,rgba(6,16,27,.96),rgba(3,9,16,.98))!important;
  border-right:1px solid rgba(0,217,255,.16)!important;
  box-shadow:18px 0 70px rgba(0,0,0,.38)!important;
  padding-top:76px!important;
}
main,.main{background:transparent!important}
.panel,#projects,.right,.settings,.card,section{
  background:rgba(8,17,28,.88)!important;
  border:1px solid rgba(75,126,164,.28)!important;
  box-shadow:0 18px 64px rgba(0,0,0,.34)!important;
  backdrop-filter:blur(16px)!important;
  border-radius:18px!important;
}
button{
  border-radius:14px!important;
  border:1px solid rgba(72,132,176,.46)!important;
  background:linear-gradient(180deg,rgba(20,44,69,.96),rgba(11,27,45,.96))!important;
  color:#ecfbff!important;
  font-weight:850!important;
  letter-spacing:.01em!important;
}
button:hover{border-color:var(--trippy-cyan)!important;box-shadow:0 0 22px rgba(0,217,255,.28)!important;transform:translateY(-1px)}
button.primary,button[onclick*=\"createImmich\"],.presentHero{
  background:linear-gradient(135deg,#6127ff,#00b9d8)!important;
  border-color:rgba(0,217,255,.9)!important;
  box-shadow:0 0 32px rgba(0,217,255,.32)!important;
}
input,select,textarea{
  background:#07101a!important;color:var(--trippy-text)!important;
  border:1px solid rgba(89,139,174,.38)!important;border-radius:14px!important
}
#map,.mapwrap{
  border-radius:22px!important;overflow:hidden!important;
  box-shadow:inset 0 0 0 1px rgba(0,217,255,.20),0 20px 80px rgba(0,0,0,.34)!important;
}
.versionBadge{
  position:fixed;left:18px;top:14px;z-index:99999;color:#18f0ff;font-weight:950;font-size:15px;
  letter-spacing:.4px;text-shadow:0 0 12px rgba(0,217,255,.7);background:rgba(3,7,13,.68);
  border:1px solid rgba(0,217,255,.28);border-radius:999px;padding:5px 11px
}
.trippyBrand{
  position:fixed;left:22px;top:42px;z-index:99998;display:flex;align-items:center;gap:13px;
  pointer-events:none
}
.trippyLogo{width:60px;height:60px;position:relative;filter:drop-shadow(0 0 14px rgba(0,217,255,.30))}
.trippyLogo .petal{position:absolute;left:22px;top:2px;width:29px;height:45px;border-radius:25px 25px 10px 10px;transform-origin:8px 29px;mix-blend-mode:screen}
.trippyLogo .p1{background:#ff2727;transform:rotate(0deg) skewX(-18deg)}
.trippyLogo .p2{background:#ffb300;transform:rotate(72deg) skewX(18deg)}
.trippyLogo .p3{background:#18c957;transform:rotate(144deg) skewX(-14deg)}
.trippyLogo .p4{background:#2385ff;transform:rotate(216deg) skewX(16deg)}
.trippyLogo .p5{background:#e66ab5;transform:rotate(288deg) skewX(-19deg)}
.trippyLogo:after{content:\"\";position:absolute;inset:18px;border:2px solid rgba(0,217,255,.86);border-radius:50%;box-shadow:0 0 10px rgba(0,217,255,.75)}
.trippyWord{font-size:36px;font-weight:950;font-style:italic;line-height:1;color:white;letter-spacing:-1.2px;text-shadow:2px 0 #00d9ff,-2px 0 #ff4da6,0 4px 20px rgba(0,0,0,.95)}
.trippyTopbar{
  position:fixed;left:300px;right:0;top:0;height:74px;z-index:99990;
  background:rgba(3,9,16,.76);backdrop-filter:blur(18px);border-bottom:1px solid rgba(0,217,255,.16);
  display:flex;align-items:center;gap:14px;padding:12px 22px
}
.trippyTopTitle{font-size:21px;font-weight:900;min-width:280px}
.trippyTopMeta{color:var(--trippy-muted);font-size:13px;margin-top:4px}
.trippyTopSpacer{flex:1}
.trippyTopExport,.trippyTopAccount{
  padding:12px 18px;border-radius:14px;background:rgba(8,17,28,.90);border:1px solid rgba(75,126,164,.30);font-weight:850
}
.trippyTopPresent{min-width:290px;height:48px;font-size:16px}
body.trippyChrome main,body.trippyChrome .main{padding-top:74px!important}
body.trippyChrome .toolbar,body.trippyChrome .topbar,body.trippyChrome header:not(.keepHeader){opacity:.06!important;pointer-events:none!important;height:0!important;overflow:hidden!important}
body.trippyChrome .right,.settings{padding-top:18px!important}
.stop{border-radius:16px!important;transition:.18s ease!important;margin-bottom:10px!important}
.stop:hover,.stop.active{border-color:var(--trippy-cyan)!important;box-shadow:0 0 22px rgba(0,217,255,.18)!important}
.stop.trippyCollapsed .row{display:none!important}
.stopSummary{cursor:pointer;display:flex;align-items:center;justify-content:space-between;gap:8px}
.stopChevron{color:var(--trippy-muted);font-weight:900}
.tile{border-radius:16px!important;overflow:hidden!important;transition:.16s ease!important}
.tile.focused,.tile:hover{transform:translateY(-2px) scale(1.02);box-shadow:0 0 25px rgba(0,217,255,.32)!important}
.trippyPopup{
  width:360px;background:#08111c;color:#eef7ff;border:1px solid rgba(0,217,255,.55);
  border-radius:18px;box-shadow:0 0 42px rgba(0,217,255,.28);overflow:hidden
}
.trippyPopup img{width:100%;height:210px;object-fit:cover;display:block}
.trippyPopupBody{padding:14px 16px}
.trippyPopupKicker{color:#00d9ff;font-weight:900;font-size:13px;margin-bottom:8px}
.trippyPopupTitle{font-size:20px;font-weight:950;margin-bottom:6px}
.trippyPopupMeta{color:#9fb5c7;font-size:13px}
.leaflet-popup-content-wrapper,.maplibregl-popup-content{background:transparent!important;padding:0!important;box-shadow:none!important;border:0!important}
.leaflet-popup-content{margin:0!important}
.trippyExportCollapsed .exportBody{display:none!important}
.trippyExportHeader{cursor:pointer;display:flex;align-items:center;justify-content:space-between;font-weight:950}
.trippyStopNameHint{color:#00d9ff;font-size:11px;margin-top:3px}
</style>

<script id=\"TRIPPY_UI_V1013_SCRIPT\">
(function(){
  let activePopup=null;
  function ready(fn){if(document.readyState!==\"loading\")fn();else document.addEventListener(\"DOMContentLoaded\",fn);}
  function projectName(){
    try{return (window.project&&project.name)||document.querySelector(\".active b\")?.textContent||\"Immich Journey\";}catch(e){return \"Immich Journey\";}
  }
  function projectMeta(){
    try{
      const p=window.project;
      if(!p)return \"No project selected\";
      return ((p.assets&&p.assets.length)||0)+\" media  •  \"+((p.stops&&p.stops.length)||0)+\" stops\";
    }catch(e){return \"\";}
  }
  function installChrome(){
    document.body.classList.add(\"trippyChrome\");
    if(!document.querySelector(\".versionBadge\")){
      const v=document.createElement(\"div\");v.className=\"versionBadge\";v.textContent=\"v10.2.0\";document.body.appendChild(v);
    }
    const side=document.querySelector(\"aside,.sidebar,.left\")||document.body.firstElementChild;
    if(side && !document.querySelector(\".trippyBrand\")){
      const oldLogo=side.querySelector(\"h1,.brand,.logo\"); if(oldLogo) oldLogo.style.display=\"none\";
      const brand=document.createElement(\"div\"); brand.className=\"trippyBrand\";
      brand.innerHTML='<div class=\"trippyLogo\"><span class=\"petal p1\"></span><span class=\"petal p2\"></span><span class=\"petal p3\"></span><span class=\"petal p4\"></span><span class=\"petal p5\"></span></div><div class=\"trippyWord\">trippy</div>';
      document.body.appendChild(brand);
    }
    let bar=document.querySelector(\".trippyTopbar\");
    if(!bar){
      bar=document.createElement(\"div\");bar.className=\"trippyTopbar\";
      bar.innerHTML='<div><div class=\"trippyTopTitle\"></div><div class=\"trippyTopMeta\"></div></div><div class=\"trippyTopSpacer\"></div><button class=\"trippyTopPresent presentHero\">▶ Present Journey<br><span style=\"font-size:11px;font-weight:650;opacity:.82\">Immersive route playback</span></button><div class=\"trippyTopExport\">Export ▾</div><div class=\"trippyTopAccount\">Account ▾</div>';
      document.body.appendChild(bar);
      bar.querySelector(\".trippyTopPresent\").onclick=()=>openTrippyPresent();
      bar.querySelector(\".trippyTopExport\").onclick=()=>toggleExportPanel();
      bar.querySelector(\".trippyTopAccount\").onclick=()=>{const b=[...document.querySelectorAll(\"button\")].find(x=>(x.textContent||\"\").toLowerCase().includes(\"account\")); if(b)b.click();};
    }
    bar.querySelector(\".trippyTopTitle\").textContent=projectName();
    bar.querySelector(\".trippyTopMeta\").textContent=projectMeta();
  }
  function toggleExportPanel(){
    const labels=[...document.querySelectorAll(\"h1,h2,h3,b,label,div\")];
    const renderText=labels.find(x=>(x.textContent||\"\").trim().toLowerCase()===\"render\" || (x.textContent||\"\").toLowerCase().includes(\"render mp4\"));
    const panel=renderText?.closest(\"section,.panel,.card,div\");
    if(panel){panel.scrollIntoView({behavior:\"smooth\",block:\"center\"});panel.classList.toggle(\"trippyExportCollapsed\");}
  }
  function cleanTopButtons(){
    document.querySelectorAll(\"button\").forEach(b=>{
      const t=(b.textContent||\"\").toLowerCase();
      if(t.includes(\"preview\")||t.includes(\"present\")){b.classList.add(\"presentHero\");b.textContent=\"▶ Present Journey\";b.onclick=()=>openTrippyPresent();}
    });
  }
  function collapseStops(){
    document.querySelectorAll(\".stop\").forEach((el,idx)=>{
      if(!el.dataset.v1013){
        el.dataset.v1013=\"1\";
        el.classList.add(\"trippyCollapsed\");
        const b=el.querySelector(\"b\"); const small=el.querySelector(\".small\");
        if(b && !el.querySelector(\".trippyStopNameHint\")){
          const hint=document.createElement(\"div\");hint.className=\"trippyStopNameHint\";hint.textContent=suggestStopName(idx);
          b.insertAdjacentElement(\"afterend\",hint);
        }
        const chev=document.createElement(\"span\");chev.className=\"stopChevron\";chev.textContent=\"›\";
        chev.style.float=\"right\";chev.onclick=(ev)=>{ev.stopPropagation();el.classList.toggle(\"trippyCollapsed\");};
        if(!el.querySelector(\".stopChevron\"))el.prepend(chev);
      }
    });
  }
  function suggestStopName(idx){
    const names=[\"Jackson Lake Overlook\",\"Lakeshore Trail\",\"Airport Arrival\",\"Downtown Walk\",\"Scenic Pullout\",\"Trail Segment\",\"Marina Stop\",\"Photo Cluster\"];
    try{
      const s=project?.stops?.[idx]; const count=(s?.asset_ids||[]).length;
      if(count>12)return \"Suggested: Trail Segment\";
      if(count<=2)return \"Suggested: Photo Cluster\";
    }catch(e){}
    return \"Suggested: \"+names[idx%names.length];
  }
  function openTrippyPresent(){
    const p=window.project;
    if(!p||!p.stops||!p.stops.length){
      alert(\"Load or create a journey first, then Present Journey will play it.\");
      return;
    }
    let overlay=document.querySelector(\".trippyPresentOverlay\");
    if(!overlay){
      overlay=document.createElement(\"div\");overlay.className=\"trippyPresentOverlay\";
      overlay.style.cssText=\"position:fixed;inset:0;z-index:100000;background:rgba(2,7,18,.96);color:white;display:grid;grid-template-rows:auto 1fr auto;padding:28px;gap:18px\";
      overlay.innerHTML='<div style=\"display:flex;align-items:center;gap:18px\"><div class=\"trippyLogo\"><span class=\"petal p1\"></span><span class=\"petal p2\"></span><span class=\"petal p3\"></span><span class=\"petal p4\"></span><span class=\"petal p5\"></span></div><div><div style=\"font-size:28px;font-weight:950\">Present Journey</div><div class=\"presentMeta\" style=\"color:#91a6b8\"></div></div><div style=\"flex:1\"></div><button class=\"presentClose\">Close</button></div><div class=\"presentStage\" style=\"border:1px solid rgba(0,217,255,.3);border-radius:24px;background:radial-gradient(circle at 50% 40%,rgba(0,217,255,.15),transparent 36%),#07111d;display:flex;align-items:center;justify-content:center;text-align:center;font-size:26px;font-weight:900\"></div><div style=\"display:flex;gap:12px;justify-content:center\"><button class=\"presentPrev\">Previous Stop</button><button class=\"presentPlay presentHero\">Play</button><button class=\"presentNext\">Next Stop</button></div>';
      document.body.appendChild(overlay);
      overlay.querySelector(\".presentClose\").onclick=()=>overlay.remove();
    }
    let i=0; const stops=p.stops||[];
    const stage=overlay.querySelector(\".presentStage\"); const meta=overlay.querySelector(\".presentMeta\");
    function draw(){
      const s=stops[i]||{};
      meta.textContent=(p.name||\"Journey\")+\" • \"+stops.length+\" stops\";
      stage.innerHTML='<div><div style=\"color:#00d9ff;font-size:18px;margin-bottom:10px\">Stop '+(i+1)+' / '+stops.length+'</div><div style=\"font-size:44px;margin-bottom:10px\">'+(s.name||suggestStopName(i).replace(\"Suggested: \",\"\"))+'</div><div style=\"color:#91a6b8\">'+((s.asset_ids||[]).length)+' photos nearby</div><div style=\"margin-top:30px;color:#00d9ff\">Map fly-through + photo nodes</div></div>';
      try{ if(map&&map.flyTo&&s.lon&&s.lat)map.flyTo({center:[s.lon,s.lat],zoom:16,pitch:45,duration:1100}); }catch(e){}
    }
    overlay.querySelector(\".presentPrev\").onclick=()=>{i=(i-1+stops.length)%stops.length;draw();};
    overlay.querySelector(\".presentNext\").onclick=()=>{i=(i+1)%stops.length;draw();};
    overlay.querySelector(\".presentPlay\").onclick=()=>{clearInterval(overlay._timer);overlay._timer=setInterval(()=>{i=(i+1)%stops.length;draw();},2500);};
    draw();
  }
  function patchFocusAsset(){
    const old=window.focusAsset;
    if(typeof old===\"function\" && !old._trippy1013){
      const wrapped=function(i){
        old(i);
        try{
          const a=project.assets[i]; if(!a||!map)return;
          if(activePopup&&activePopup.remove)activePopup.remove();
          if(map.flyTo)map.flyTo({center:[a.lon,a.lat],zoom:19,pitch:45,bearing:0,duration:850});
          const h='<div class=\"trippyPopup\">'+(a.thumb?'<img src=\"'+a.thumb+'\">':'')+'<div class=\"trippyPopupBody\"><div class=\"trippyPopupKicker\">Selected photo</div><div class=\"trippyPopupTitle\">'+(a.name||'Photo')+'</div><div class=\"trippyPopupMeta\">'+(a.time||'')+'</div></div></div>';
          if(window.maplibregl&&maplibregl.Popup)activePopup=new maplibregl.Popup({offset:18,closeButton:true}).setLngLat([a.lon,a.lat]).setHTML(h).addTo(map);
          else if(window.L&&L.popup)activePopup=L.popup({maxWidth:380}).setLatLng([a.lat,a.lon]).setContent(h).openOn(map);
        }catch(e){console.warn(e);}
      };
      wrapped._trippy1013=true; window.focusAsset=wrapped;
    }
  }
  ready(()=>{installChrome();cleanTopButtons();setTimeout(collapseStops,500);setInterval(()=>{installChrome();cleanTopButtons();collapseStops();patchFocusAsset();},1200);});
  window.openTrippyPresent=openTrippyPresent;
})();
</script>
EOF_FRONTEND_PATCH_1013"


# v10.2.0: full frontend replacement, not an overlay.
pct exec "$CTID" -- bash -lc "cat >/tmp/trippy_frontend.b64 <<'EOF_TRIPPY_FRONTEND_B64'
PCFkb2N0eXBlIGh0bWw+CjxodG1sIGxhbmc9ImVuIj4KPGhlYWQ+CjxtZXRhIGNoYXJzZXQ9InV0Zi04Ii8+CjxtZXRhIG5hbWU9InZpZXdwb3J0IiBjb250ZW50PSJ3aWR0aD1kZXZpY2Utd2lkdGgsaW5pdGlhbC1zY2FsZT0xIi8+Cjx0aXRsZT5UcmlwcHkgdjEwLjIuMDwvdGl0bGU+CjxsaW5rIHJlbD0ic3R5bGVzaGVldCIgaHJlZj0iaHR0cHM6Ly91bnBrZy5jb20vbWFwbGlicmUtZ2xANC43LjEvZGlzdC9tYXBsaWJyZS1nbC5jc3MiLz4KPHNjcmlwdCBzcmM9Imh0dHBzOi8vdW5wa2cuY29tL21hcGxpYnJlLWdsQDQuNy4xL2Rpc3QvbWFwbGlicmUtZ2wuanMiPjwvc2NyaXB0Pgo8c3R5bGU+Cjpyb290ey0tYmc6IzAyMDcxMjstLXBhbmVsOiMwNzExMWQ7LS1wYW5lbDI6IzBiMTcyNTstLWNhcmQ6IzBkMWIyYjstLWxpbmU6IzE4MzQ0YzstLWN5YW46IzAwZDlmZjstLWN5YW4yOiMxOGYwZmY7LS1ibHVlOiMyNDdjZmY7LS12aW9sZXQ6IzZkNGRmZjstLXBpbms6I2ZmNGRhNjstLWdyZWVuOiMyN2Q5N2Y7LS1vcmFuZ2U6I2ZmN2ExYTstLXJlZDojZmY0NzY3Oy0tdGV4dDojZWVmN2ZmOy0tbXV0ZWQ6IzkxYTZiODstLXNoYWRvdzowIDI0cHggODBweCByZ2JhKDAsMCwwLC40Mil9Cip7Ym94LXNpemluZzpib3JkZXItYm94fWh0bWwsYm9keSwjYXBwe21hcmdpbjowO2hlaWdodDoxMDAlO3dpZHRoOjEwMCU7b3ZlcmZsb3c6aGlkZGVuO2JhY2tncm91bmQ6dmFyKC0tYmcpO2NvbG9yOnZhcigtLXRleHQpO2ZvbnQtZmFtaWx5OkludGVyLHVpLXNhbnMtc2VyaWYsc3lzdGVtLXVpLC1hcHBsZS1zeXN0ZW0sU2Vnb2UgVUksc2Fucy1zZXJpZn0KYm9keXtiYWNrZ3JvdW5kOnJhZGlhbC1ncmFkaWVudChjaXJjbGUgYXQgOCUgMCUscmdiYSgwLDIxNywyNTUsLjE0KSx0cmFuc3BhcmVudCAyOCUpLHJhZGlhbC1ncmFkaWVudChjaXJjbGUgYXQgODglIDEyJSxyZ2JhKDEwOSw3NywyNTUsLjExKSx0cmFuc3BhcmVudCAzNCUpLGxpbmVhci1ncmFkaWVudCgxNDVkZWcsIzAyMDcxMiwjMDYxMTFkIDU1JSwjMDIwNTBiKX0KYnV0dG9uLGlucHV0LHNlbGVjdHtmb250OmluaGVyaXR9YnV0dG9ue2JvcmRlcjoxcHggc29saWQgcmdiYSg3MiwxMzIsMTc2LC40Nik7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoMjAsNDQsNjksLjk2KSxyZ2JhKDExLDI3LDQ1LC45NikpO2NvbG9yOiNlY2ZiZmY7Ym9yZGVyLXJhZGl1czoxNHB4O2ZvbnQtd2VpZ2h0Ojg1MDtjdXJzb3I6cG9pbnRlcjt0cmFuc2l0aW9uOi4xNnMgZWFzZX1idXR0b246aG92ZXJ7Ym9yZGVyLWNvbG9yOnZhcigtLWN5YW4pO2JveC1zaGFkb3c6MCAwIDIycHggcmdiYSgwLDIxNywyNTUsLjI4KTt0cmFuc2Zvcm06dHJhbnNsYXRlWSgtMXB4KX0KaW5wdXQsc2VsZWN0e2JhY2tncm91bmQ6IzA3MTAxYTtjb2xvcjp2YXIoLS10ZXh0KTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoODksMTM5LDE3NCwuMzgpO2JvcmRlci1yYWRpdXM6MTRweDtwYWRkaW5nOjEycHh9LnNtYWxse2ZvbnQtc2l6ZToxMnB4O2NvbG9yOnZhcigtLW11dGVkKX0KLmFwcHtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjMwMHB4IDFmciAzOTBweDtoZWlnaHQ6MTAwdmh9LnNpZGViYXJ7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoNiwxNiwyNywuOTYpLHJnYmEoMyw5LDE2LC45OCkpO2JvcmRlci1yaWdodDoxcHggc29saWQgcmdiYSgwLDIxNywyNTUsLjE2KTtib3gtc2hhZG93OjE4cHggMCA3MHB4IHJnYmEoMCwwLDAsLjM4KTtwYWRkaW5nOjE2cHggMThweDtkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO2dhcDoxNHB4fQouYnJhbmRSb3d7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTNweDttYXJnaW46MnB4IDAgMThweH0udmVyc2lvbkJhZGdle2NvbG9yOiMxOGYwZmY7Zm9udC13ZWlnaHQ6OTUwO2ZvbnQtc2l6ZToxNXB4O2xldHRlci1zcGFjaW5nOi40cHg7dGV4dC1zaGFkb3c6MCAwIDEycHggcmdiYSgwLDIxNywyNTUsLjcpO2JhY2tncm91bmQ6cmdiYSgzLDcsMTMsLjY4KTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTcsMjU1LC4yOCk7Ym9yZGVyLXJhZGl1czo5OTlweDtwYWRkaW5nOjVweCAxMXB4O3dpZHRoOm1heC1jb250ZW50fQoudHJpcHB5TG9nb3t3aWR0aDo1OHB4O2hlaWdodDo1OHB4O3Bvc2l0aW9uOnJlbGF0aXZlO2ZpbHRlcjpkcm9wLXNoYWRvdygwIDAgMTRweCByZ2JhKDAsMjE3LDI1NSwuMzApKX0udHJpcHB5TG9nbyAucGV0YWx7cG9zaXRpb246YWJzb2x1dGU7bGVmdDoyMXB4O3RvcDoycHg7d2lkdGg6MjhweDtoZWlnaHQ6NDNweDtib3JkZXItcmFkaXVzOjI1cHggMjVweCAxMHB4IDEwcHg7dHJhbnNmb3JtLW9yaWdpbjo4cHggMjhweDttaXgtYmxlbmQtbW9kZTpzY3JlZW59LnRyaXBweUxvZ28gLnAxe2JhY2tncm91bmQ6I2ZmMjcyNzt0cmFuc2Zvcm06cm90YXRlKDBkZWcpIHNrZXdYKC0xOGRlZyl9LnRyaXBweUxvZ28gLnAye2JhY2tncm91bmQ6I2ZmYjMwMDt0cmFuc2Zvcm06cm90YXRlKDcyZGVnKSBza2V3WCgxOGRlZyl9LnRyaXBweUxvZ28gLnAze2JhY2tncm91bmQ6IzE4Yzk1Nzt0cmFuc2Zvcm06cm90YXRlKDE0NGRlZykgc2tld1goLTE0ZGVnKX0udHJpcHB5TG9nbyAucDR7YmFja2dyb3VuZDojMjM4NWZmO3RyYW5zZm9ybTpyb3RhdGUoMjE2ZGVnKSBza2V3WCgxNmRlZyl9LnRyaXBweUxvZ28gLnA1e2JhY2tncm91bmQ6I2U2NmFiNTt0cmFuc2Zvcm06cm90YXRlKDI4OGRlZykgc2tld1goLTE5ZGVnKX0udHJpcHB5TG9nbzphZnRlcntjb250ZW50OiIiO3Bvc2l0aW9uOmFic29sdXRlO2luc2V0OjE3cHg7Ym9yZGVyOjJweCBzb2xpZCByZ2JhKDAsMjE3LDI1NSwuODYpO2JvcmRlci1yYWRpdXM6NTAlO2JveC1zaGFkb3c6MCAwIDEwcHggcmdiYSgwLDIxNywyNTUsLjc1KX0udHJpcHB5V29yZHtmb250LXNpemU6MzhweDtmb250LXdlaWdodDo5NTA7Zm9udC1zdHlsZTppdGFsaWM7bGluZS1oZWlnaHQ6MTtjb2xvcjp3aGl0ZTtsZXR0ZXItc3BhY2luZzotMS4ycHg7dGV4dC1zaGFkb3c6MnB4IDAgIzAwZDlmZiwtMnB4IDAgI2ZmNGRhNiwwIDRweCAyMHB4IHJnYmEoMCwwLDAsLjk1KX0KLnByaW1hcnl7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCMwNzMzYTgsIzAwYTNjNyk7Ym9yZGVyLWNvbG9yOnJnYmEoMCwyMTcsMjU1LC44NSk7Ym94LXNoYWRvdzowIDAgMjZweCByZ2JhKDAsMjE3LDI1NSwuMjQpfS5zaWRlQnRue3dpZHRoOjEwMCU7aGVpZ2h0OjU2cHg7Zm9udC1zaXplOjE1cHh9LnNlY3Rpb25UaXRsZXttYXJnaW46MTRweCAwIDZweDtjb2xvcjojYmNkMmU1O2ZvbnQtd2VpZ2h0OjkwMDt0ZXh0LXRyYW5zZm9ybTp1cHBlcmNhc2U7Zm9udC1zaXplOjEzcHg7bGV0dGVyLXNwYWNpbmc6LjA4ZW07ZGlzcGxheTpmbGV4O2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVufS5wcm9qZWN0c3tkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO2dhcDoxMnB4O292ZXJmbG93OmF1dG87bWluLWhlaWdodDowfS5wcm9qZWN0Q2FyZHtiYWNrZ3JvdW5kOnJnYmEoOCwxNywyOCwuOTApO2JvcmRlcjoxcHggc29saWQgcmdiYSg3NSwxMjYsMTY0LC4zMCk7Ym9yZGVyLXJhZGl1czoxOHB4O3BhZGRpbmc6MTZweDtjdXJzb3I6cG9pbnRlcjtib3gtc2hhZG93OjAgMTZweCA1MHB4IHJnYmEoMCwwLDAsLjI2KX0ucHJvamVjdENhcmQuYWN0aXZle2JvcmRlci1jb2xvcjp2YXIoLS1jeWFuKTtib3gtc2hhZG93OjAgMCAyOHB4IHJnYmEoMCwyMTcsMjU1LC4yMil9LnByb2plY3RDYXJkIGJ7ZGlzcGxheTpibG9jaztmb250LXNpemU6MTVweDttYXJnaW4tYm90dG9tOjdweH0ucHJvamVjdEFjdGlvbnN7ZGlzcGxheTpmbGV4O2dhcDo4cHg7bWFyZ2luLXRvcDoxMnB4fS5wcm9qZWN0QWN0aW9ucyBidXR0b257ZmxleDoxO2hlaWdodDozNnB4O2ZvbnQtc2l6ZToxMnB4fS5zaWRlRm9vdGVye21hcmdpbi10b3A6YXV0bztjb2xvcjojODQ5OGFhO2ZvbnQtc2l6ZToxM3B4O2xpbmUtaGVpZ2h0OjEuNTV9Ci5tYWlue2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLXJvd3M6OTJweCAxZnIgMjYwcHg7bWluLXdpZHRoOjB9LnRvcGJhcntkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxOHB4O3BhZGRpbmc6MThweCAyMnB4O2JhY2tncm91bmQ6cmdiYSgzLDksMTYsLjc0KTtiYWNrZHJvcC1maWx0ZXI6Ymx1cigxOHB4KTtib3JkZXItYm90dG9tOjFweCBzb2xpZCByZ2JhKDAsMjE3LDI1NSwuMTYpfS50aXRsZUJsb2Nre21pbi13aWR0aDozNTBweH0uam91cm5leVRpdGxle2ZvbnQtc2l6ZToyNHB4O2ZvbnQtd2VpZ2h0Ojk1MH0ubWV0YXttYXJnaW4tdG9wOjZweDtjb2xvcjp2YXIoLS1tdXRlZCk7Zm9udC1zaXplOjE0cHg7ZGlzcGxheTpmbGV4O2dhcDoxMnB4O2FsaWduLWl0ZW1zOmNlbnRlcn0uZ3JlZW5Eb3R7d2lkdGg6N3B4O2hlaWdodDo3cHg7YmFja2dyb3VuZDp2YXIoLS1ncmVlbik7Ym9yZGVyLXJhZGl1czo1MCU7ZGlzcGxheTppbmxpbmUtYmxvY2t9LnRvcFNwYWNlcntmbGV4OjF9LnByZXNlbnRCdG57aGVpZ2h0OjU4cHg7bWluLXdpZHRoOjMyMHB4O2ZvbnQtc2l6ZToxN3B4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjNjEyN2ZmLCMwMGI5ZDgpO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE3LDI1NSwuOTApO2JveC1zaGFkb3c6MCAwIDM0cHggcmdiYSgwLDIxNywyNTUsLjM0KX0ucHJlc2VudEJ0biBzcGFue2Rpc3BsYXk6YmxvY2s7Zm9udC1zaXplOjEycHg7b3BhY2l0eTouODI7Zm9udC13ZWlnaHQ6NzAwO21hcmdpbi10b3A6MnB4fS50b3BQaWxse2hlaWdodDo1OHB4O21pbi13aWR0aDoxNjBweDtwYWRkaW5nOjAgMThweH0uaWNvbkJ0bnt3aWR0aDo1OHB4O2hlaWdodDo1OHB4O2JvcmRlci1yYWRpdXM6MTZweDtmb250LXNpemU6MjBweH0KLm1hcFBhbmVse3Bvc2l0aW9uOnJlbGF0aXZlO21hcmdpbjowO3BhZGRpbmc6MDttaW4taGVpZ2h0OjB9Lm1hcFNoZWxse3Bvc2l0aW9uOmFic29sdXRlO2luc2V0OjAgMjJweCAwIDA7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE3LDI1NSwuMjApO2JvcmRlci1yYWRpdXM6MjJweDtvdmVyZmxvdzpoaWRkZW47Ym94LXNoYWRvdzp2YXIoLS1zaGFkb3cpfSNtYXB7cG9zaXRpb246YWJzb2x1dGU7aW5zZXQ6MDtiYWNrZ3JvdW5kOiNiN2Q4ZTB9Lm1hcERpbXtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowO2JhY2tncm91bmQ6cmdiYSgyLDcsMTgsLjE4KTtwb2ludGVyLWV2ZW50czpub25lfS5tYXBDb250cm9sc3twb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjIwcHg7dG9wOjIycHg7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6MTJweDt6LWluZGV4OjN9Lm1hcEN0cmx7d2lkdGg6NTJweDtoZWlnaHQ6NTJweDtib3JkZXItcmFkaXVzOjE0cHg7YmFja2dyb3VuZDpyZ2JhKDgsMTcsMjgsLjg4KTtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlcjoxcHggc29saWQgcmdiYSg3NSwxMjYsMTY0LC4zMCk7Ym94LXNoYWRvdzowIDEwcHggMjhweCByZ2JhKDAsMCwwLC4zKX0uZmlsdGVyUGlsbHtwb3NpdGlvbjphYnNvbHV0ZTtyaWdodDoyNHB4O3RvcDoyNHB4O3otaW5kZXg6NDtiYWNrZ3JvdW5kOnJnYmEoOCwxNywyOCwuOTIpO2JvcmRlcjoxcHggc29saWQgcmdiYSg3NSwxMjYsMTY0LC4zNSk7Ym9yZGVyLXJhZGl1czoxNnB4O3BhZGRpbmc6MTNweCAxNnB4O2Rpc3BsYXk6bm9uZTtnYXA6MTRweDthbGlnbi1pdGVtczpjZW50ZXI7Ym94LXNoYWRvdzowIDE4cHggNDhweCByZ2JhKDAsMCwwLC4zNSl9LmZpbHRlclBpbGwuc2hvd3tkaXNwbGF5OmZsZXh9LnN0b3BQb3B1cHtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjE2MHB4O3RvcDoxNzBweDt3aWR0aDozNDBweDtiYWNrZ3JvdW5kOiMwODExMWM7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE3LDI1NSwuNDUpO2JvcmRlci1yYWRpdXM6MjBweDtib3gtc2hhZG93OjAgMCA0NnB4IHJnYmEoMCwyMTcsMjU1LC4yOCk7ei1pbmRleDo1O292ZXJmbG93OmhpZGRlbjtkaXNwbGF5Om5vbmV9LnN0b3BQb3B1cC5zaG93e2Rpc3BsYXk6YmxvY2t9LnN0b3BQb3B1cCBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MjA1cHg7b2JqZWN0LWZpdDpjb3ZlcjtkaXNwbGF5OmJsb2NrfS5zdG9wUG9wdXBCb2R5e3BhZGRpbmc6MTRweCAxNnB4fS5raWNrZXJ7ZGlzcGxheTppbmxpbmUtYmxvY2s7YmFja2dyb3VuZDpyZ2JhKDAsMjE3LDI1NSwuMTYpO2NvbG9yOnZhcigtLWN5YW4pO2JvcmRlci1yYWRpdXM6OXB4O3BhZGRpbmc6NXB4IDlweDtmb250LXNpemU6MTJweDtmb250LXdlaWdodDo5MDB9LnBvcHVwVGl0bGV7Zm9udC1zaXplOjIxcHg7Zm9udC13ZWlnaHQ6OTUwO21hcmdpbjoxMHB4IDAgNnB4fS5wb3B1cEFjdGlvbnN7ZGlzcGxheTpmbGV4O2dhcDo5cHg7bWFyZ2luLXRvcDoxMnB4fS5wb3B1cEFjdGlvbnMgYnV0dG9ue2hlaWdodDo0MnB4O2ZsZXg6MX0KLmdhbGxlcnlQYW5lbHtib3JkZXItdG9wOjFweCBzb2xpZCByZ2JhKDAsMjE3LDI1NSwuMTIpO2JhY2tncm91bmQ6cmdiYSgzLDksMTYsLjY1KTtwYWRkaW5nOjE2cHggMjJweCAxOHB4O21pbi13aWR0aDowfS5nYWxsZXJ5SGVhZGVye2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjEycHg7bWFyZ2luLWJvdHRvbToxMnB4fS5nYWxsZXJ5VGl0bGV7Zm9udC1zaXplOjE3cHg7Zm9udC13ZWlnaHQ6OTUwfS5nYWxsZXJ5e2Rpc3BsYXk6ZmxleDtnYXA6MTRweDtvdmVyZmxvdy14OmF1dG87cGFkZGluZy1ib3R0b206OHB4fS50aWxle3dpZHRoOjIxMHB4O2hlaWdodDoxNTBweDtib3JkZXItcmFkaXVzOjE4cHg7b3ZlcmZsb3c6aGlkZGVuO2ZsZXg6MCAwIGF1dG87YmFja2dyb3VuZDojMGQxYjJiO2JvcmRlcjoxcHggc29saWQgcmdiYSg3NSwxMjYsMTY0LC4zMCk7cG9zaXRpb246cmVsYXRpdmU7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTZzIGVhc2V9LnRpbGU6aG92ZXIsLnRpbGUuZm9jdXNlZHtib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMjZweCByZ2JhKDAsMjE3LDI1NSwuMzIpO3RyYW5zZm9ybTp0cmFuc2xhdGVZKC0ycHgpIHNjYWxlKDEuMDE1KX0udGlsZSBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtvYmplY3QtZml0OmNvdmVyO2Rpc3BsYXk6YmxvY2t9LnRpbGVMYWJlbHtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjA7cmlnaHQ6MDtib3R0b206MDtwYWRkaW5nOjI4cHggMTBweCAxMHB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KHRyYW5zcGFyZW50LHJnYmEoMCwwLDAsLjc4KSk7Zm9udC13ZWlnaHQ6ODUwO2ZvbnQtc2l6ZToxM3B4fQoucmlnaHR7YmFja2dyb3VuZDpyZ2JhKDQsMTEsMjAsLjgyKTtib3JkZXItbGVmdDoxcHggc29saWQgcmdiYSgwLDIxNywyNTUsLjE0KTtwYWRkaW5nOjE4cHggMThweDtvdmVyZmxvdzphdXRvfS5yaWdodFNlY3Rpb257YmFja2dyb3VuZDpyZ2JhKDgsMTcsMjgsLjg4KTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzUsMTI2LDE2NCwuMjgpO2JvcmRlci1yYWRpdXM6MThweDttYXJnaW4tYm90dG9tOjE0cHg7Ym94LXNoYWRvdzowIDE0cHggNTBweCByZ2JhKDAsMCwwLC4yNSk7b3ZlcmZsb3c6aGlkZGVufS5yaWdodEhlYWRlcntwYWRkaW5nOjE2cHggMThweDtmb250LXdlaWdodDo5NTA7Zm9udC1zaXplOjE4cHg7ZGlzcGxheTpmbGV4O2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuO2FsaWduLWl0ZW1zOmNlbnRlcjtjdXJzb3I6cG9pbnRlcn0ucmlnaHRCb2R5e3BhZGRpbmc6MCAxNnB4IDE2cHh9LnNlYXJjaHt3aWR0aDoxMDAlO21hcmdpbi1ib3R0b206MTJweH0uc3RvcExpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6MTBweH0uc3RvcENhcmR7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDc1LDEyNiwxNjQsLjI1KTtiYWNrZ3JvdW5kOnJnYmEoMTIsMjUsNDAsLjgwKTtib3JkZXItcmFkaXVzOjE2cHg7cGFkZGluZzoxM3B4IDE0cHg7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTZzIGVhc2V9LnN0b3BDYXJkOmhvdmVyLC5zdG9wQ2FyZC5hY3RpdmV7Ym9yZGVyLWNvbG9yOnZhcigtLWN5YW4pO2JveC1zaGFkb3c6MCAwIDI0cHggcmdiYSgwLDIxNywyNTUsLjE4KX0uc3RvcFJvd3tkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMnB4fS5zdG9wTnVte3dpZHRoOjI4cHg7aGVpZ2h0OjI4cHg7Ym9yZGVyLXJhZGl1czo5OTlweDtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZyx2YXIoLS1jeWFuKSx2YXIoLS1ibHVlKSk7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwfS5zdG9wTmFtZXtmb250LXdlaWdodDo5MDA7Zm9udC1zaXplOjE1cHh9LnN0b3BNZXRhe2ZvbnQtc2l6ZToxMnB4O2NvbG9yOnZhcigtLW11dGVkKTttYXJnaW4tdG9wOjVweH0uc3RvcEV4cGFuZGVke2Rpc3BsYXk6bm9uZTttYXJnaW4tdG9wOjEycHg7Ym9yZGVyLXRvcDoxcHggc29saWQgcmdiYSg3NSwxMjYsMTY0LC4yMik7cGFkZGluZy10b3A6MTJweH0uc3RvcENhcmQub3BlbiAuc3RvcEV4cGFuZGVke2Rpc3BsYXk6YmxvY2t9LnN0b3BFeHBhbmRlZCBidXR0b257aGVpZ2h0OjM4cHg7Zm9udC1zaXplOjEycHg7bWFyZ2luLXJpZ2h0OjZweDttYXJnaW4tdG9wOjZweH0KLmV4cG9ydFRhYnN7ZGlzcGxheTpncmlkO2dyaWQtdGVtcGxhdGUtY29sdW1uczoxZnIgMWZyIDFmcjttYXJnaW4tYm90dG9tOjEycHg7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDc1LDEyNiwxNjQsLjI1KTtib3JkZXItcmFkaXVzOjEycHg7b3ZlcmZsb3c6aGlkZGVufS5leHBvcnRUYWJzIGJ1dHRvbntib3JkZXI6MDtib3JkZXItcmFkaXVzOjA7aGVpZ2h0OjQycHg7YmFja2dyb3VuZDpyZ2JhKDYsMTYsMjcsLjgpfS5leHBvcnRUYWJzIGJ1dHRvbi5hY3RpdmV7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCMwNzMzYTgsIzAwYTNjNyl9LmV4cG9ydFJlbmRlcnt3aWR0aDoxMDAlO2hlaWdodDo2MnB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMDA4NGE5LCMwMGJkZDYpO2ZvbnQtc2l6ZToxNnB4fQoubW9kYWx7cG9zaXRpb246Zml4ZWQ7aW5zZXQ6MDtiYWNrZ3JvdW5kOnJnYmEoMCwwLDAsLjcyKTtkaXNwbGF5Om5vbmU7YWxpZ24taXRlbXM6Y2VudGVyO2p1c3RpZnktY29udGVudDpjZW50ZXI7ei1pbmRleDoxMDAwO3BhZGRpbmc6MjRweH0ubW9kYWwuc2hvd3tkaXNwbGF5OmZsZXh9Lm1vZGFsQ2FyZHtiYWNrZ3JvdW5kOiMwODExMWM7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE3LDI1NSwuMzUpO2JvcmRlci1yYWRpdXM6MjJweDtib3gtc2hhZG93OjAgMCA3MHB4IHJnYmEoMCwyMTcsMjU1LC4yMik7cGFkZGluZzoyMnB4O3dpZHRoOm1pbig3NjBweCw5NHZ3KX0ubW9kYWxDYXJkIGgye21hcmdpbjowIDAgMTRweH0uZm9ybUdyaWR7ZGlzcGxheTpncmlkO2dhcDoxMnB4fS5mb3JtR3JpZCBpbnB1dHt3aWR0aDoxMDAlfS5wcmVzZW50T3ZlcmxheXtwb3NpdGlvbjpmaXhlZDtpbnNldDowO3otaW5kZXg6MjAwMDtiYWNrZ3JvdW5kOnJnYmEoMiw3LDE4LC45Nik7ZGlzcGxheTpub25lO2dyaWQtdGVtcGxhdGUtcm93czphdXRvIDFmciBhdXRvO3BhZGRpbmc6MjhweDtnYXA6MThweH0ucHJlc2VudE92ZXJsYXkuc2hvd3tkaXNwbGF5OmdyaWR9LnByZXNlbnRTdGFnZXtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTcsMjU1LC4zKTtib3JkZXItcmFkaXVzOjI0cHg7YmFja2dyb3VuZDpyYWRpYWwtZ3JhZGllbnQoY2lyY2xlIGF0IDUwJSA0MCUscmdiYSgwLDIxNywyNTUsLjE1KSx0cmFuc3BhcmVudCAzNiUpLCMwNzExMWQ7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtqdXN0aWZ5LWNvbnRlbnQ6Y2VudGVyO3RleHQtYWxpZ246Y2VudGVyO2ZvbnQtc2l6ZToyNnB4O2ZvbnQtd2VpZ2h0OjkwMH0uc3RhdHVze3Bvc2l0aW9uOmZpeGVkO2xlZnQ6MzIwcHg7Ym90dG9tOjE4cHg7YmFja2dyb3VuZDpyZ2JhKDgsMTcsMjgsLjk0KTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTcsMjU1LC4yNSk7Ym9yZGVyLXJhZGl1czoxNHB4O3BhZGRpbmc6MTBweCAxNHB4O2NvbG9yOiNkZmY4ZmY7ei1pbmRleDo5OTk7ZGlzcGxheTpub25lfS5zdGF0dXMuc2hvd3tkaXNwbGF5OmJsb2NrfQpAbWVkaWEobWF4LXdpZHRoOjEyNTBweCl7LmFwcHtncmlkLXRlbXBsYXRlLWNvbHVtbnM6MjYwcHggMWZyIDMzMHB4fS5zaWRlYmFye3dpZHRoOjI2MHB4fS50cmlwcHlXb3Jke2ZvbnQtc2l6ZTozMXB4fS5wcmVzZW50QnRue21pbi13aWR0aDoyMzBweH0udGlsZXt3aWR0aDoxNzBweH0udGl0bGVCbG9ja3ttaW4td2lkdGg6MjUwcHh9fQo8L3N0eWxlPgo8L2hlYWQ+Cjxib2R5Pgo8ZGl2IGlkPSJhcHAiIGNsYXNzPSJhcHAiPgogIDxhc2lkZSBjbGFzcz0ic2lkZWJhciI+PGRpdiBjbGFzcz0idmVyc2lvbkJhZGdlIj52MTAuMi4wPC9kaXY+PGRpdiBjbGFzcz0iYnJhbmRSb3ciPjxkaXYgY2xhc3M9InRyaXBweUxvZ28iPjxzcGFuIGNsYXNzPSJwZXRhbCBwMSI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMiI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMyI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNCI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNSI+PC9zcGFuPjwvZGl2PjxkaXYgY2xhc3M9InRyaXBweVdvcmQiPnRyaXBweTwvZGl2PjwvZGl2PjxidXR0b24gY2xhc3M9InNpZGVCdG4gcHJpbWFyeSIgaWQ9Im5ld0ltbWljaEJ0biI+77yLIE5ldyBJbW1pY2ggSm91cm5leTwvYnV0dG9uPjxidXR0b24gY2xhc3M9InNpZGVCdG4iIGlkPSJ1cGxvYWRCdG4iPuKHpyBVcGxvYWQgTWVkaWE8L2J1dHRvbj48ZGl2IGNsYXNzPSJzZWN0aW9uVGl0bGUiPjxzcGFuPlByb2plY3RzPC9zcGFuPjxzcGFuPuKMlTwvc3Bhbj48L2Rpdj48ZGl2IGlkPSJwcm9qZWN0TGlzdCIgY2xhc3M9InByb2plY3RzIj48L2Rpdj48ZGl2IGNsYXNzPSJzaWRlRm9vdGVyIj48ZGl2PlBsYW4sIG9yZ2FuaXplLCBhbmQgcmVsaXZlIHlvdXIgYWR2ZW50dXJlcyBvbiB0aGUgbWFwLjwvZGl2Pjxicj48ZGl2IHN0eWxlPSJjb2xvcjp2YXIoLS1jeWFuKSI+4pajIERvY3VtZW50YXRpb248L2Rpdj48ZGl2IHN0eWxlPSJjb2xvcjp2YXIoLS1jeWFuKTttYXJnaW4tdG9wOjhweCI+4peOIENoYW5nZWxvZzwvZGl2PjwvZGl2PjwvYXNpZGU+CiAgPG1haW4gY2xhc3M9Im1haW4iPjxkaXYgY2xhc3M9InRvcGJhciI+PGRpdiBjbGFzcz0idGl0bGVCbG9jayI+PGRpdiBpZD0iam91cm5leVRpdGxlIiBjbGFzcz0iam91cm5leVRpdGxlIj5ObyBwcm9qZWN0IHNlbGVjdGVkPC9kaXY+PGRpdiBpZD0iam91cm5leU1ldGEiIGNsYXNzPSJtZXRhIj48c3Bhbj5Mb2FkIG9yIGNyZWF0ZSBhIGpvdXJuZXk8L3NwYW4+PC9kaXY+PC9kaXY+PGRpdiBjbGFzcz0idG9wU3BhY2VyIj48L2Rpdj48YnV0dG9uIGlkPSJwcmVzZW50QnRuIiBjbGFzcz0icHJlc2VudEJ0biI+4pa2IFByZXNlbnQgSm91cm5leTxzcGFuPkltbWVyc2l2ZSByb3V0ZSBwbGF5YmFjazwvc3Bhbj48L2J1dHRvbj48YnV0dG9uIGlkPSJleHBvcnRKdW1wQnRuIiBjbGFzcz0idG9wUGlsbCI+4pajIEV4cG9ydDxicj48c3BhbiBjbGFzcz0ic21hbGwiPlJlbmRlciwgR1BYLCBhbmQgbW9yZTwvc3Bhbj48L2J1dHRvbj48YnV0dG9uIGlkPSJzZXR0aW5nc0J0biIgY2xhc3M9Imljb25CdG4iPuKamTwvYnV0dG9uPjxidXR0b24gaWQ9ImFjY291bnRCdG4iIGNsYXNzPSJ0b3BQaWxsIj5BY2NvdW50IOKWvjwvYnV0dG9uPjwvZGl2PjxzZWN0aW9uIGNsYXNzPSJtYXBQYW5lbCI+PGRpdiBjbGFzcz0ibWFwU2hlbGwiPjxkaXYgaWQ9Im1hcCI+PC9kaXY+PGRpdiBjbGFzcz0ibWFwRGltIj48L2Rpdj48ZGl2IGNsYXNzPSJtYXBDb250cm9scyI+PGRpdiBjbGFzcz0ibWFwQ3RybCIgaWQ9ImxvY2F0ZUJ0biI+4p6kPC9kaXY+PGRpdiBjbGFzcz0ibWFwQ3RybCI+4panPC9kaXY+PGRpdiBjbGFzcz0ibWFwQ3RybCI+4pqZPC9kaXY+PGRpdiBjbGFzcz0ibWFwQ3RybCIgaWQ9Inpvb21JbiI+77yLPC9kaXY+PGRpdiBjbGFzcz0ibWFwQ3RybCIgaWQ9Inpvb21PdXQiPuKIkjwvZGl2PjwvZGl2PjxkaXYgaWQ9ImZpbHRlclBpbGwiIGNsYXNzPSJmaWx0ZXJQaWxsIj7ilr4gPGI+RmlsdGVyOiBBbGwgU3RvcHM8L2I+PGJ1dHRvbiBpZD0iY2xlYXJGaWx0ZXJCdG4iPsOXPC9idXR0b24+PC9kaXY+PGRpdiBpZD0ic3RvcFBvcHVwIiBjbGFzcz0ic3RvcFBvcHVwIj48L2Rpdj48L2Rpdj48L3NlY3Rpb24+PHNlY3Rpb24gY2xhc3M9ImdhbGxlcnlQYW5lbCI+PGRpdiBjbGFzcz0iZ2FsbGVyeUhlYWRlciI+PGRpdiBpZD0iZ2FsbGVyeVRpdGxlIiBjbGFzcz0iZ2FsbGVyeVRpdGxlIj5NZWRpYTwvZGl2PjxkaXYgaWQ9ImdhbGxlcnlNZXRhIiBjbGFzcz0ic21hbGwiPjwvZGl2PjxkaXYgc3R5bGU9ImZsZXg6MSI+PC9kaXY+PGJ1dHRvbiBpZD0iZ2FsbGVyeUdyaWRCdG4iPuKWpjwvYnV0dG9uPjxidXR0b24gaWQ9ImdhbGxlcnlGaWx0ZXJCdG4iPuKYtzwvYnV0dG9uPjwvZGl2PjxkaXYgaWQ9ImdhbGxlcnkiIGNsYXNzPSJnYWxsZXJ5Ij48L2Rpdj48L3NlY3Rpb24+PC9tYWluPgogIDxhc2lkZSBjbGFzcz0icmlnaHQiPjxzZWN0aW9uIGNsYXNzPSJyaWdodFNlY3Rpb24iPjxkaXYgY2xhc3M9InJpZ2h0SGVhZGVyIj5Sb3V0ZSAmIFBsYXliYWNrIDxzcGFuPuKMhDwvc3Bhbj48L2Rpdj48ZGl2IGNsYXNzPSJyaWdodEJvZHkiPjxidXR0b24gaWQ9ImF1dG9DbHVzdGVyQnRuIiBzdHlsZT0id2lkdGg6MTAwJTtoZWlnaHQ6NDRweDttYXJnaW4tYm90dG9tOjhweCI+QXV0by1jbHVzdGVyIHN0b3BzPC9idXR0b24+PGJ1dHRvbiBpZD0icmV2ZXJzZVJvdXRlQnRuIiBzdHlsZT0id2lkdGg6MTAwJTtoZWlnaHQ6NDRweDttYXJnaW4tYm90dG9tOjhweCI+UmV2ZXJzZSBSb3V0ZTwvYnV0dG9uPjxsYWJlbCBjbGFzcz0ic21hbGwiPlN0b3AgcmFkaXVzLCBtZXRlcnM8L2xhYmVsPjxpbnB1dCBpZD0ic3RvcFJhZGl1cyIgdmFsdWU9IjIwMCIgc3R5bGU9IndpZHRoOjEwMCU7bWFyZ2luLXRvcDo2cHgiPjwvZGl2Pjwvc2VjdGlvbj48c2VjdGlvbiBjbGFzcz0icmlnaHRTZWN0aW9uIj48ZGl2IGNsYXNzPSJyaWdodEhlYWRlciI+U3RvcHMgKDxzcGFuIGlkPSJzdG9wQ291bnQiPjA8L3NwYW4+KSA8c3Bhbj7ijJU8L3NwYW4+PC9kaXY+PGRpdiBjbGFzcz0icmlnaHRCb2R5Ij48aW5wdXQgaWQ9InN0b3BTZWFyY2giIGNsYXNzPSJzZWFyY2giIHBsYWNlaG9sZGVyPSJTZWFyY2ggc3RvcHMuLi4iPjxidXR0b24gaWQ9ImV4cGFuZFN0b3BzQnRuIiBzdHlsZT0id2lkdGg6MTAwJTtoZWlnaHQ6NDRweDttYXJnaW4tYm90dG9tOjEycHgiPkV4cGFuZCBhbGwgc3RvcHM8L2J1dHRvbj48ZGl2IGlkPSJzdG9wTGlzdCIgY2xhc3M9InN0b3BMaXN0Ij48L2Rpdj48L2Rpdj48L3NlY3Rpb24+PHNlY3Rpb24gY2xhc3M9InJpZ2h0U2VjdGlvbiI+PGRpdiBjbGFzcz0icmlnaHRIZWFkZXIiPk1lZGlhIEZpbHRlcnMgPHNwYW4+4oyEPC9zcGFuPjwvZGl2Pjwvc2VjdGlvbj48c2VjdGlvbiBjbGFzcz0icmlnaHRTZWN0aW9uIiBpZD0iZXhwb3J0UGFuZWwiPjxkaXYgY2xhc3M9InJpZ2h0SGVhZGVyIj5FeHBvcnQgJiBSZW5kZXIgPHNwYW4+4oyDPC9zcGFuPjwvZGl2PjxkaXYgY2xhc3M9InJpZ2h0Qm9keSI+PGxhYmVsIGNsYXNzPSJzbWFsbCI+RXhwb3J0IEZvcm1hdDwvbGFiZWw+PGRpdiBjbGFzcz0iZXhwb3J0VGFicyI+PGJ1dHRvbiBjbGFzcz0iYWN0aXZlIj5WaWRlbyAoTVA0KTwvYnV0dG9uPjxidXR0b24+R1BYIFRyYWNrPC9idXR0b24+PGJ1dHRvbj5JbWFnZSBTZXQ8L2J1dHRvbj48L2Rpdj48bGFiZWwgY2xhc3M9InNtYWxsIj5NaW51dGVzPC9sYWJlbD48aW5wdXQgaWQ9ImR1cmF0aW9uTWluIiB2YWx1ZT0iMTIiIHN0eWxlPSJ3aWR0aDoxMDAlO21hcmdpbjo2cHggMCAxMnB4Ij48bGFiZWwgY2xhc3M9InNtYWxsIj5JbmNsdWRlIEF1ZGlvPC9sYWJlbD48aW5wdXQgaWQ9ImF1ZGlvSW5wdXQiIHR5cGU9ImZpbGUiIGFjY2VwdD0iYXVkaW8vKiIgc3R5bGU9IndpZHRoOjEwMCU7bWFyZ2luOjZweCAwIDEycHgiPjxidXR0b24gaWQ9InJlbmRlckJ0biIgY2xhc3M9ImV4cG9ydFJlbmRlciI+4pamIFJlbmRlciBNUDQ8YnI+PHNwYW4gY2xhc3M9InNtYWxsIiBzdHlsZT0iY29sb3I6d2hpdGUiPkZpbmFsIHZpZGVvIGV4cG9ydDwvc3Bhbj48L2J1dHRvbj48L2Rpdj48L3NlY3Rpb24+PC9hc2lkZT4KPC9kaXY+CjxkaXYgaWQ9ImltbWljaE1vZGFsIiBjbGFzcz0ibW9kYWwiPjxkaXYgY2xhc3M9Im1vZGFsQ2FyZCI+PGgyPk5ldyBJbW1pY2ggSm91cm5leTwvaDI+PGRpdiBjbGFzcz0iZm9ybUdyaWQiPjxpbnB1dCBpZD0iaW1taWNoVXJsIiBwbGFjZWhvbGRlcj0iSW1taWNoIFVSTCwgZS5nLiBodHRwOi8vMTkyLjE2OC42OC4xNTM6MjI4MyI+PGlucHV0IGlkPSJpbW1pY2hLZXkiIHBsYWNlaG9sZGVyPSJBUEkga2V5Ij48ZGl2IHN0eWxlPSJkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjFmciAxZnI7Z2FwOjEycHgiPjxpbnB1dCBpZD0ic3RhcnREYXRlIiB0eXBlPSJkYXRlIj48aW5wdXQgaWQ9ImVuZERhdGUiIHR5cGU9ImRhdGUiPjwvZGl2PjxkaXYgY2xhc3M9InNtYWxsIj5SZXF1aXJlZCBwZXJtaXNzaW9uczogYXNzZXQucmVhZCwgYXNzZXQudmlldywgYXNzZXQuZG93bmxvYWQsIG1hcC5yZWFkLCB0aW1lbGluZS5yZWFkPC9kaXY+PGRpdiBzdHlsZT0iZGlzcGxheTpmbGV4O2dhcDoxMHB4Ij48YnV0dG9uIGlkPSJ0ZXN0S2V5QnRuIj5UZXN0IGtleTwvYnV0dG9uPjxidXR0b24gaWQ9ImNyZWF0ZUpvdXJuZXlCdG4iIGNsYXNzPSJwcmltYXJ5IiBzdHlsZT0iZmxleDoxIj5DcmVhdGUgSm91cm5leTwvYnV0dG9uPjxidXR0b24gaWQ9ImNsb3NlSW1taWNoQnRuIj5DbG9zZTwvYnV0dG9uPjwvZGl2PjwvZGl2PjwvZGl2PjwvZGl2Pgo8ZGl2IGlkPSJhY2NvdW50TW9kYWwiIGNsYXNzPSJtb2RhbCI+PGRpdiBjbGFzcz0ibW9kYWxDYXJkIj48aDI+QWNjb3VudCAvIEltbWljaCBDb25uZWN0aW9uPC9oMj48ZGl2IGNsYXNzPSJmb3JtR3JpZCI+PGlucHV0IGlkPSJhY2NvdW50VXJsIiBwbGFjZWhvbGRlcj0iSW1taWNoIFVSTCI+PGlucHV0IGlkPSJhY2NvdW50S2V5IiBwbGFjZWhvbGRlcj0iQVBJIGtleSI+PGRpdiBzdHlsZT0iZGlzcGxheTpmbGV4O2dhcDoxMHB4Ij48YnV0dG9uIGlkPSJzYXZlQWNjb3VudEJ0biIgY2xhc3M9InByaW1hcnkiPlNhdmU8L2J1dHRvbj48YnV0dG9uIGlkPSJjbG9zZUFjY291bnRCdG4iPkNsb3NlPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+PC9kaXY+CjxkaXYgaWQ9InByZXNlbnRPdmVybGF5IiBjbGFzcz0icHJlc2VudE92ZXJsYXkiPjxkaXYgc3R5bGU9ImRpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjE4cHgiPjxkaXYgY2xhc3M9InRyaXBweUxvZ28iPjxzcGFuIGNsYXNzPSJwZXRhbCBwMSI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMiI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMyI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNCI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNSI+PC9zcGFuPjwvZGl2PjxkaXY+PGRpdiBzdHlsZT0iZm9udC1zaXplOjMwcHg7Zm9udC13ZWlnaHQ6OTUwIj5QcmVzZW50IEpvdXJuZXk8L2Rpdj48ZGl2IGlkPSJwcmVzZW50TWV0YSIgc3R5bGU9ImNvbG9yOnZhcigtLW11dGVkKSI+PC9kaXY+PC9kaXY+PGRpdiBzdHlsZT0iZmxleDoxIj48L2Rpdj48YnV0dG9uIGlkPSJjbG9zZVByZXNlbnRCdG4iPkNsb3NlPC9idXR0b24+PC9kaXY+PGRpdiBpZD0icHJlc2VudFN0YWdlIiBjbGFzcz0icHJlc2VudFN0YWdlIj48L2Rpdj48ZGl2IHN0eWxlPSJkaXNwbGF5OmZsZXg7Z2FwOjEycHg7anVzdGlmeS1jb250ZW50OmNlbnRlciI+PGJ1dHRvbiBpZD0icHJlc2VudFByZXYiPlByZXZpb3VzIFN0b3A8L2J1dHRvbj48YnV0dG9uIGlkPSJwcmVzZW50UGxheSIgY2xhc3M9InByZXNlbnRCdG4iPlBsYXk8c3Bhbj5BdXRvIGpvdXJuZXk8L3NwYW4+PC9idXR0b24+PGJ1dHRvbiBpZD0icHJlc2VudE5leHQiPk5leHQgU3RvcDwvYnV0dG9uPjwvZGl2PjwvZGl2Pgo8ZGl2IGlkPSJzdGF0dXMiIGNsYXNzPSJzdGF0dXMiPjwvZGl2Pgo8c2NyaXB0PgpsZXQgcHJvamVjdHM9W10scHJvamVjdD1udWxsLG1hcD1udWxsLG1hcmtlcnM9W10sYWN0aXZlU3RvcElkPW51bGwsZmlsdGVyU3RvcElkPW51bGwsYWN0aXZlUG9wdXA9bnVsbCxwcmVzZW50SW5kZXg9MCxwcmVzZW50VGltZXI9bnVsbDsKY29uc3QgJD1pZD0+ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoaWQpO2Z1bmN0aW9uIHN0YXR1cyhtc2cpe2NvbnN0IHM9JCgnc3RhdHVzJyk7cy50ZXh0Q29udGVudD1tc2c7cy5jbGFzc0xpc3QuYWRkKCdzaG93Jyk7c2V0VGltZW91dCgoKT0+cy5jbGFzc0xpc3QucmVtb3ZlKCdzaG93JyksNDUwMCl9CmZ1bmN0aW9uIHNhdmVkQ29ubigpe3JldHVybntiYXNlX3VybDpsb2NhbFN0b3JhZ2UuZ2V0SXRlbSgndHJpcHB5X2ltbWljaF91cmwnKXx8JycsYXBpX2tleTpsb2NhbFN0b3JhZ2UuZ2V0SXRlbSgndHJpcHB5X2ltbWljaF9rZXknKXx8Jyd9fWZ1bmN0aW9uIHNhdmVDb25uKHVybCxrZXkpe2xvY2FsU3RvcmFnZS5zZXRJdGVtKCd0cmlwcHlfaW1taWNoX3VybCcsdXJsKTtsb2NhbFN0b3JhZ2Uuc2V0SXRlbSgndHJpcHB5X2ltbWljaF9rZXknLGtleSl9CmZ1bmN0aW9uIHRvZGF5SVNPKG9mZnNldD0wKXtjb25zdCBkPW5ldyBEYXRlKCk7ZC5zZXREYXRlKGQuZ2V0RGF0ZSgpK29mZnNldCk7cmV0dXJuIGQudG9JU09TdHJpbmcoKS5zbGljZSgwLDEwKX1mdW5jdGlvbiBpbml0RGF0ZXMoKXtzdGFydERhdGUudmFsdWU9dG9kYXlJU08oLTcpO2VuZERhdGUudmFsdWU9dG9kYXlJU08oMCk7Y29uc3QgYz1zYXZlZENvbm4oKTtpbW1pY2hVcmwudmFsdWU9Yy5iYXNlX3VybDtpbW1pY2hLZXkudmFsdWU9Yy5hcGlfa2V5O2FjY291bnRVcmwudmFsdWU9Yy5iYXNlX3VybDthY2NvdW50S2V5LnZhbHVlPWMuYXBpX2tleX0KZnVuY3Rpb24gc3VnZ2VzdFN0b3BOYW1lKHN0b3AsaWR4KXtjb25zdCBuPShzdG9wLmFzc2V0X2lkc3x8W10pLmxlbmd0aDtpZihuPjEyKXJldHVybidUcmFpbCBTZWdtZW50Jztjb25zdCBuYW1lcz1bJ0phY2tzb24gTGFrZSBPdmVybG9vaycsJ0xha2VzaG9yZSBUcmFpbCcsJ01vb3NlIFNpZ2h0aW5nJywnQ29sdGVyIEJheSBNYXJpbmEnLCdTdW5yaXNlIFBvaW50JywnU2lnbmFsIE1vdW50YWluIFZpZXcnLCdBaXJwb3J0IEFycml2YWwnLCdEb3dudG93biBXYWxrJywnU2NlbmljIFB1bGxvdXQnLCdQaG90byBDbHVzdGVyJ107cmV0dXJuIHN0b3AubmFtZSYmIS9eU3RvcCBcXGQrLy50ZXN0KHN0b3AubmFtZSk/c3RvcC5uYW1lOm5hbWVzW2lkeCVuYW1lcy5sZW5ndGhdfQphc3luYyBmdW5jdGlvbiBhcGkocGF0aCxvcHRzPXt9KXtjb25zdCByPWF3YWl0IGZldGNoKHBhdGgsb3B0cyk7Y29uc3QgdD1hd2FpdCByLnRleHQoKTtsZXQgajt0cnl7aj1KU09OLnBhcnNlKHQpfWNhdGNoe2o9e2RldGFpbDp0fX1pZighci5vayl0aHJvdyBuZXcgRXJyb3Ioai5kZXRhaWx8fHQpO3JldHVybiBqfQphc3luYyBmdW5jdGlvbiBsb2FkUHJvamVjdHMoKXtwcm9qZWN0cz1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdHMnKTtyZW5kZXJQcm9qZWN0cygpO2lmKHByb2plY3RzLmxlbmd0aCYmIXByb2plY3QpYXdhaXQgb3BlblByb2plY3QocHJvamVjdHNbMF0uaWQpfWZ1bmN0aW9uIHJlbmRlclByb2plY3RzKCl7cHJvamVjdExpc3QuaW5uZXJIVE1MPXByb2plY3RzLm1hcChwPT5gPGRpdiBjbGFzcz0icHJvamVjdENhcmQgJHtwcm9qZWN0JiZwcm9qZWN0LmlkPT09cC5pZD8nYWN0aXZlJzonJ30iIG9uY2xpY2s9Im9wZW5Qcm9qZWN0KCcke3AuaWR9JykiPjxiPiR7cC5uYW1lfHwnVW50aXRsZWQgSm91cm5leSd9PC9iPjxkaXYgY2xhc3M9InNtYWxsIj4ke3AuYXNzZXRzfHwwfSBHUFMgYXNzZXRzIOKAoiAke3Auc3RvcHN8fDB9IHN0b3BzPC9kaXY+PGRpdiBjbGFzcz0icHJvamVjdEFjdGlvbnMiPjxidXR0b24gb25jbGljaz0iZXZlbnQuc3RvcFByb3BhZ2F0aW9uKCk7ZGVsZXRlUHJvamVjdCgnJHtwLmlkfScpIj5EZWxldGU8L2J1dHRvbj48L2Rpdj48L2Rpdj5gKS5qb2luKCcnKX0KYXN5bmMgZnVuY3Rpb24gb3BlblByb2plY3QoaWQpe3Byb2plY3Q9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytpZCk7YWN0aXZlU3RvcElkPW51bGw7ZmlsdGVyU3RvcElkPW51bGw7cmVuZGVyQWxsKCk7c3RhdHVzKCdMb2FkZWQgJysocHJvamVjdC5uYW1lfHwnSm91cm5leScpKX1hc3luYyBmdW5jdGlvbiBkZWxldGVQcm9qZWN0KGlkKXtpZighY29uZmlybSgnRGVsZXRlIHRoaXMgam91cm5leT8nKSlyZXR1cm47YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytpZCx7bWV0aG9kOidERUxFVEUnfSk7aWYocHJvamVjdCYmcHJvamVjdC5pZD09PWlkKXByb2plY3Q9bnVsbDthd2FpdCBsb2FkUHJvamVjdHMoKTtyZW5kZXJBbGwoKX0KZnVuY3Rpb24gcmVuZGVyQWxsKCl7cmVuZGVyUHJvamVjdHMoKTtyZW5kZXJIZWFkZXIoKTtyZW5kZXJNYXAoKTtyZW5kZXJTdG9wcygpO3JlbmRlckdhbGxlcnkoKX1mdW5jdGlvbiByZW5kZXJIZWFkZXIoKXtqb3VybmV5VGl0bGUudGV4dENvbnRlbnQ9cHJvamVjdD9wcm9qZWN0Lm5hbWU6J05vIHByb2plY3Qgc2VsZWN0ZWQnO2pvdXJuZXlNZXRhLmlubmVySFRNTD1wcm9qZWN0P2A8c3Bhbj7il7cgJHtwcm9qZWN0LmNyZWF0ZWQ/cHJvamVjdC5jcmVhdGVkLnNsaWNlKDAsMTApOicnfTwvc3Bhbj48c3Bhbj48aSBjbGFzcz0iZ3JlZW5Eb3QiPjwvaT4gJHsocHJvamVjdC5hc3NldHN8fFtdKS5sZW5ndGh9IG1lZGlhPC9zcGFuPjxzcGFuPuKAoiAkeyhwcm9qZWN0LnN0b3BzfHxbXSkubGVuZ3RofSBzdG9wczwvc3Bhbj5gOic8c3Bhbj5Mb2FkIG9yIGNyZWF0ZSBhIGpvdXJuZXk8L3NwYW4+J30KZnVuY3Rpb24gZW5zdXJlTWFwKCl7aWYobWFwKXJldHVybjttYXA9bmV3IG1hcGxpYnJlZ2wuTWFwKHtjb250YWluZXI6J21hcCcsc3R5bGU6J2h0dHBzOi8vZGVtb3RpbGVzLm1hcGxpYnJlLm9yZy9zdHlsZS5qc29uJyxjZW50ZXI6Wy05OCwzOV0sem9vbTozLHBpdGNoOjB9KTttYXAuYWRkQ29udHJvbChuZXcgbWFwbGlicmVnbC5OYXZpZ2F0aW9uQ29udHJvbCh7c2hvd0NvbXBhc3M6ZmFsc2V9KSwnYm90dG9tLXJpZ2h0Jyl9CmZ1bmN0aW9uIHJlbmRlck1hcCgpe2Vuc3VyZU1hcCgpO21hcmtlcnMuZm9yRWFjaChtPT5tLnJlbW92ZSgpKTttYXJrZXJzPVtdO2lmKCFwcm9qZWN0fHwhcHJvamVjdC5zdG9wc3x8IXByb2plY3Quc3RvcHMubGVuZ3RoKXJldHVybjtjb25zdCBjb29yZHM9cHJvamVjdC5zdG9wcy5tYXAocz0+W3MubG9uLHMubGF0XSk7ZnVuY3Rpb24gZHJhd1JvdXRlKCl7aWYobWFwLmdldExheWVyKCdyb3V0ZScpKXttYXAucmVtb3ZlTGF5ZXIoJ3JvdXRlJyk7bWFwLnJlbW92ZVNvdXJjZSgncm91dGUnKX1tYXAuYWRkU291cmNlKCdyb3V0ZScse3R5cGU6J2dlb2pzb24nLGRhdGE6e3R5cGU6J0ZlYXR1cmUnLGdlb21ldHJ5Ont0eXBlOidMaW5lU3RyaW5nJyxjb29yZGluYXRlczpjb29yZHN9fX0pO21hcC5hZGRMYXllcih7aWQ6J3JvdXRlJyx0eXBlOidsaW5lJyxzb3VyY2U6J3JvdXRlJyxwYWludDp7J2xpbmUtY29sb3InOicjMDBkOWZmJywnbGluZS13aWR0aCc6NSwnbGluZS1vcGFjaXR5JzouODV9fSl9aWYobWFwLmlzU3R5bGVMb2FkZWQoKSlkcmF3Um91dGUoKTtlbHNlIG1hcC5vbmNlKCdsb2FkJyxkcmF3Um91dGUpO2NvbnN0IGJvdW5kcz1uZXcgbWFwbGlicmVnbC5MbmdMYXRCb3VuZHMoKTtwcm9qZWN0LnN0b3BzLmZvckVhY2goKHMsaSk9Pntib3VuZHMuZXh0ZW5kKFtzLmxvbixzLmxhdF0pO2NvbnN0IGVsPWRvY3VtZW50LmNyZWF0ZUVsZW1lbnQoJ2RpdicpO2VsLnN0eWxlLmNzc1RleHQ9YHdpZHRoOjQycHg7aGVpZ2h0OjQycHg7Ym9yZGVyLXJhZGl1czo5OTlweDtiYWNrZ3JvdW5kOnJnYmEoOCwxNywyOCwuOTIpO2JvcmRlcjozcHggc29saWQgJHtzLnN0b3BfaWQ9PT1hY3RpdmVTdG9wSWQ/JyMyNDdjZmYnOicjMDBkOWZmJ307ZGlzcGxheTpncmlkO3BsYWNlLWl0ZW1zOmNlbnRlcjtjb2xvcjp3aGl0ZTtmb250LXdlaWdodDo5NTA7Ym94LXNoYWRvdzowIDAgMjBweCByZ2JhKDAsMjE3LDI1NSwuNTUpO2N1cnNvcjpwb2ludGVyYDtlbC50ZXh0Q29udGVudD1pKzE7ZWwub25jbGljaz0oKT0+c2VsZWN0U3RvcChzLnN0b3BfaWQsdHJ1ZSk7bWFya2Vycy5wdXNoKG5ldyBtYXBsaWJyZWdsLk1hcmtlcih7ZWxlbWVudDplbH0pLnNldExuZ0xhdChbcy5sb24scy5sYXRdKS5hZGRUbyhtYXApKX0pO3RyeXttYXAuZml0Qm91bmRzKGJvdW5kcyx7cGFkZGluZzoxMjAsbWF4Wm9vbToxNSxkdXJhdGlvbjo3MDB9KX1jYXRjaChlKXt9fQpmdW5jdGlvbiByZW5kZXJTdG9wcygpe2NvbnN0IGFycj0ocHJvamVjdCYmcHJvamVjdC5zdG9wcyl8fFtdO3N0b3BDb3VudC50ZXh0Q29udGVudD1hcnIubGVuZ3RoO3N0b3BMaXN0LmlubmVySFRNTD1hcnIubWFwKChzLGkpPT5gPGRpdiBjbGFzcz0ic3RvcENhcmQgJHtzLnN0b3BfaWQ9PT1hY3RpdmVTdG9wSWQ/J2FjdGl2ZSBvcGVuJzonJ30iIG9uY2xpY2s9InNlbGVjdFN0b3AoJyR7cy5zdG9wX2lkfScsdHJ1ZSkiPjxkaXYgY2xhc3M9InN0b3BSb3ciPjxkaXYgY2xhc3M9InN0b3BOdW0iPiR7aSsxfTwvZGl2PjxkaXYgc3R5bGU9ImZsZXg6MSI+PGRpdiBjbGFzcz0ic3RvcE5hbWUiPiR7c3VnZ2VzdFN0b3BOYW1lKHMsaSl9PC9kaXY+PGRpdiBjbGFzcz0ic3RvcE1ldGEiPiR7KHMuYXNzZXRfaWRzfHxbXSkubGVuZ3RofSBwaG90b3Mg4oCiICR7TWF0aC5yb3VuZChzLnJhZGl1c19tfHwyMDApfSBtPC9kaXY+PC9kaXY+PGRpdj7igLo8L2Rpdj48L2Rpdj48ZGl2IGNsYXNzPSJzdG9wRXhwYW5kZWQiPjxidXR0b24gb25jbGljaz0iZXZlbnQuc3RvcFByb3BhZ2F0aW9uKCk7cmVuYW1lU3RvcCgnJHtzLnN0b3BfaWR9JykiPlJlbmFtZTwvYnV0dG9uPjxidXR0b24gb25jbGljaz0iZXZlbnQuc3RvcFByb3BhZ2F0aW9uKCk7ZmlsdGVyU3RvcCgnJHtzLnN0b3BfaWR9JykiPkZpbHRlciBwaG90b3M8L2J1dHRvbj48YnV0dG9uIG9uY2xpY2s9ImV2ZW50LnN0b3BQcm9wYWdhdGlvbigpO2RlbGV0ZVN0b3AoJyR7cy5zdG9wX2lkfScpIj5EZWxldGU8L2J1dHRvbj48L2Rpdj48L2Rpdj5gKS5qb2luKCcnKX0KZnVuY3Rpb24gYXNzZXRzRm9yR2FsbGVyeSgpe2lmKCFwcm9qZWN0KXJldHVybltdO2lmKGZpbHRlclN0b3BJZCl7Y29uc3Qgcz1wcm9qZWN0LnN0b3BzLmZpbmQoeD0+eC5zdG9wX2lkPT09ZmlsdGVyU3RvcElkKTtjb25zdCBpZHM9bmV3IFNldCgocyYmcy5hc3NldF9pZHMpfHxbXSk7cmV0dXJuIHByb2plY3QuYXNzZXRzLmZpbHRlcihhPT5pZHMuaGFzKGEuYXNzZXRfaWQpKX1yZXR1cm4gcHJvamVjdC5hc3NldHN8fFtdfWZ1bmN0aW9uIHJlbmRlckdhbGxlcnkoKXtjb25zdCBhcnI9YXNzZXRzRm9yR2FsbGVyeSgpO2NvbnN0IHN0b3A9cHJvamVjdCYmZmlsdGVyU3RvcElkP3Byb2plY3Quc3RvcHMuZmluZChzPT5zLnN0b3BfaWQ9PT1maWx0ZXJTdG9wSWQpOm51bGw7Z2FsbGVyeVRpdGxlLnRleHRDb250ZW50PXN0b3A/YFN0b3AgJHtwcm9qZWN0LnN0b3BzLmluZGV4T2Yoc3RvcCkrMX0g4oCiICR7c3VnZ2VzdFN0b3BOYW1lKHN0b3AscHJvamVjdC5zdG9wcy5pbmRleE9mKHN0b3ApKX1gOidNZWRpYSc7Z2FsbGVyeU1ldGEudGV4dENvbnRlbnQ9YCR7YXJyLmxlbmd0aH0gaXRlbXNgO2ZpbHRlclBpbGwuY2xhc3NMaXN0LnRvZ2dsZSgnc2hvdycsISFmaWx0ZXJTdG9wSWQpO2ZpbHRlclBpbGwucXVlcnlTZWxlY3RvcignYicpLnRleHRDb250ZW50PXN0b3A/YEZpbHRlcjogJHtzdWdnZXN0U3RvcE5hbWUoc3RvcCxwcm9qZWN0LnN0b3BzLmluZGV4T2Yoc3RvcCkpfWA6J0ZpbHRlcjogQWxsIFN0b3BzJztnYWxsZXJ5LmlubmVySFRNTD1hcnIubWFwKGE9PmA8ZGl2IGNsYXNzPSJ0aWxlIiBvbmNsaWNrPSJmb2N1c0Fzc2V0KCcke2EuYXNzZXRfaWR9JykiPiR7YS50aHVtYj9gPGltZyBzcmM9IiR7YS50aHVtYn0iPmA6Jyd9PGRpdiBjbGFzcz0idGlsZUxhYmVsIj4ke2EubmFtZXx8YS5maWxlbmFtZXx8J1Bob3RvJ308L2Rpdj48L2Rpdj5gKS5qb2luKCcnKX0KZnVuY3Rpb24gc2VsZWN0U3RvcChpZCx6b29tPWZhbHNlKXthY3RpdmVTdG9wSWQ9aWQ7Y29uc3Qgcz1wcm9qZWN0LnN0b3BzLmZpbmQoeD0+eC5zdG9wX2lkPT09aWQpO3JlbmRlclN0b3BzKCk7aWYocyYmem9vbSYmbWFwKXttYXAuZmx5VG8oe2NlbnRlcjpbcy5sb24scy5sYXRdLHpvb206MTYscGl0Y2g6NDUsZHVyYXRpb246OTAwfSk7c2hvd1N0b3BQb3B1cChzKX19ZnVuY3Rpb24gc2hvd1N0b3BQb3B1cChzKXtjb25zdCBpZHg9cHJvamVjdC5zdG9wcy5pbmRleE9mKHMpO2NvbnN0IGFzc2V0cz0ocHJvamVjdC5hc3NldHN8fFtdKS5maWx0ZXIoYT0+KHMuYXNzZXRfaWRzfHxbXSkuaW5jbHVkZXMoYS5hc3NldF9pZCkpO2NvbnN0IGZpcnN0PWFzc2V0c1swXTtzdG9wUG9wdXAuaW5uZXJIVE1MPWAke2ZpcnN0JiZmaXJzdC50aHVtYj9gPGltZyBzcmM9IiR7Zmlyc3QudGh1bWJ9Ij5gOicnfTxkaXYgY2xhc3M9InN0b3BQb3B1cEJvZHkiPjxzcGFuIGNsYXNzPSJraWNrZXIiPlN0b3AgJHtpZHgrMX08L3NwYW4+PGRpdiBjbGFzcz0icG9wdXBUaXRsZSI+JHtzdWdnZXN0U3RvcE5hbWUocyxpZHgpfTwvZGl2PjxkaXYgY2xhc3M9InNtYWxsIj4ke2Fzc2V0cy5sZW5ndGh9IHBob3RvcyDigKIgJHtNYXRoLnJvdW5kKHMucmFkaXVzX218fDIwMCl9IG0gcmFkaXVzPC9kaXY+PGRpdiBjbGFzcz0icG9wdXBBY3Rpb25zIj48YnV0dG9uIG9uY2xpY2s9ImZpbHRlclN0b3AoJyR7cy5zdG9wX2lkfScpIj5WaWV3IHBob3RvczwvYnV0dG9uPjxidXR0b24gb25jbGljaz0ib3BlblByZXNlbnRBdCgke2lkeH0pIj5QcmVzZW50PC9idXR0b24+PC9kaXY+PC9kaXY+YDtzdG9wUG9wdXAuY2xhc3NMaXN0LmFkZCgnc2hvdycpfQpmdW5jdGlvbiBmaWx0ZXJTdG9wKGlkKXtmaWx0ZXJTdG9wSWQ9aWQ7YWN0aXZlU3RvcElkPWlkO3NlbGVjdFN0b3AoaWQsdHJ1ZSk7cmVuZGVyR2FsbGVyeSgpfWZ1bmN0aW9uIGNsZWFyRmlsdGVyKCl7ZmlsdGVyU3RvcElkPW51bGw7c3RvcFBvcHVwLmNsYXNzTGlzdC5yZW1vdmUoJ3Nob3cnKTtyZW5kZXJHYWxsZXJ5KCl9CmZ1bmN0aW9uIGZvY3VzQXNzZXQoYXNzZXRJZCl7Y29uc3QgYT0ocHJvamVjdC5hc3NldHN8fFtdKS5maW5kKHg9PnguYXNzZXRfaWQ9PT1hc3NldElkKTtpZighYSlyZXR1cm47ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnLnRpbGUnKS5mb3JFYWNoKHQ9PnQuY2xhc3NMaXN0LnJlbW92ZSgnZm9jdXNlZCcpKTtjb25zdCB0aWxlPVsuLi5kb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCcudGlsZScpXS5maW5kKHQ9PnQuZ2V0QXR0cmlidXRlKCdvbmNsaWNrJyk/LmluY2x1ZGVzKGFzc2V0SWQpKTtpZih0aWxlKXRpbGUuY2xhc3NMaXN0LmFkZCgnZm9jdXNlZCcpO2lmKG1hcCltYXAuZmx5VG8oe2NlbnRlcjpbYS5sb24sYS5sYXRdLHpvb206MTkscGl0Y2g6NDUsZHVyYXRpb246ODUwfSk7aWYoYWN0aXZlUG9wdXApYWN0aXZlUG9wdXAucmVtb3ZlKCk7Y29uc3QgaD1gPGRpdiBzdHlsZT0id2lkdGg6MzYwcHg7YmFja2dyb3VuZDojMDgxMTFjO2NvbG9yOiNlZWY3ZmY7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE3LDI1NSwuNTUpO2JvcmRlci1yYWRpdXM6MThweDtvdmVyZmxvdzpoaWRkZW47Ym94LXNoYWRvdzowIDAgNDJweCByZ2JhKDAsMjE3LDI1NSwuMjgpIj4ke2EudGh1bWI/YDxpbWcgc3JjPSIke2EudGh1bWJ9IiBzdHlsZT0id2lkdGg6MTAwJTtoZWlnaHQ6MjEwcHg7b2JqZWN0LWZpdDpjb3ZlciI+YDonJ308ZGl2IHN0eWxlPSJwYWRkaW5nOjE0cHggMTZweCI+PGRpdiBzdHlsZT0iY29sb3I6IzAwZDlmZjtmb250LXdlaWdodDo5MDA7Zm9udC1zaXplOjEzcHg7bWFyZ2luLWJvdHRvbTo4cHgiPlNlbGVjdGVkIHBob3RvPC9kaXY+PGRpdiBzdHlsZT0iZm9udC1zaXplOjIwcHg7Zm9udC13ZWlnaHQ6OTUwIj4ke2EubmFtZXx8YS5maWxlbmFtZXx8J1Bob3RvJ308L2Rpdj48ZGl2IGNsYXNzPSJzbWFsbCI+JHthLnRpbWV8fCcnfTwvZGl2PjwvZGl2PjwvZGl2PmA7YWN0aXZlUG9wdXA9bmV3IG1hcGxpYnJlZ2wuUG9wdXAoe29mZnNldDoxOCxjbG9zZUJ1dHRvbjp0cnVlLG1heFdpZHRoOiczOTBweCd9KS5zZXRMbmdMYXQoW2EubG9uLGEubGF0XSkuc2V0SFRNTChoKS5hZGRUbyhtYXApfQphc3luYyBmdW5jdGlvbiB0ZXN0SW1taWNoKCl7Y29uc3QgYm9keT17YmFzZV91cmw6aW1taWNoVXJsLnZhbHVlLnRyaW0oKSxhcGlfa2V5OmltbWljaEtleS52YWx1ZS50cmltKCl9O2NvbnN0IGo9YXdhaXQgYXBpKCcvYXBpL2ltbWljaC90ZXN0Jyx7bWV0aG9kOidQT1NUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkoYm9keSl9KTtzdGF0dXMoai5tZXNzYWdlfHwnQ29ubmVjdGlvbiB0ZXN0ZWQnKX0KYXN5bmMgZnVuY3Rpb24gY3JlYXRlSm91cm5leSgpe3NhdmVDb25uKGltbWljaFVybC52YWx1ZS50cmltKCksaW1taWNoS2V5LnZhbHVlLnRyaW0oKSk7Y29uc3QgYm9keT17bmFtZTpgSW1taWNoIEpvdXJuZXkgJHtzdGFydERhdGUudmFsdWV9IHRvICR7ZW5kRGF0ZS52YWx1ZX1gLGJhc2VfdXJsOmltbWljaFVybC52YWx1ZS50cmltKCksYXBpX2tleTppbW1pY2hLZXkudmFsdWUudHJpbSgpLHN0YXJ0X2RhdGU6c3RhcnREYXRlLnZhbHVlLGVuZF9kYXRlOmVuZERhdGUudmFsdWV9O3N0YXR1cygnSW1wb3J0aW5nIEltbWljaCBHUFMgYXNzZXRzLi4uJyk7Y29uc3QgcD1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdC9pbW1pY2gnLHttZXRob2Q6J1BPU1QnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sYm9keTpKU09OLnN0cmluZ2lmeShib2R5KX0pO2ltbWljaE1vZGFsLmNsYXNzTGlzdC5yZW1vdmUoJ3Nob3cnKTthd2FpdCBsb2FkUHJvamVjdHMoKTthd2FpdCBvcGVuUHJvamVjdChwLmlkKX0KYXN5bmMgZnVuY3Rpb24gc2F2ZVByb2plY3QoKXtpZighcHJvamVjdClyZXR1cm47YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytwcm9qZWN0LmlkLHttZXRob2Q6J1BVVCcsaGVhZGVyczp7J0NvbnRlbnQtVHlwZSc6J2FwcGxpY2F0aW9uL2pzb24nfSxib2R5OkpTT04uc3RyaW5naWZ5KHByb2plY3QpfSk7c3RhdHVzKCdTYXZlZCcpfWFzeW5jIGZ1bmN0aW9uIHJlbmFtZVN0b3AoaWQpe2NvbnN0IHM9cHJvamVjdC5zdG9wcy5maW5kKHg9Pnguc3RvcF9pZD09PWlkKTtjb25zdCBuPXByb21wdCgnU3RvcCBuYW1lJyxzdWdnZXN0U3RvcE5hbWUocyxwcm9qZWN0LnN0b3BzLmluZGV4T2YocykpKTtpZihuKXtzLm5hbWU9bjthd2FpdCBzYXZlUHJvamVjdCgpO3JlbmRlckFsbCgpfX1hc3luYyBmdW5jdGlvbiBkZWxldGVTdG9wKGlkKXtwcm9qZWN0LnN0b3BzPXByb2plY3Quc3RvcHMuZmlsdGVyKHM9PnMuc3RvcF9pZCE9PWlkKTthd2FpdCBzYXZlUHJvamVjdCgpO3JlbmRlckFsbCgpfWZ1bmN0aW9uIHJldmVyc2VSb3V0ZSgpe2lmKCFwcm9qZWN0KXJldHVybjtwcm9qZWN0LnN0b3BzLnJldmVyc2UoKTtyZW5kZXJBbGwoKTtzYXZlUHJvamVjdCgpfQphc3luYyBmdW5jdGlvbiBhdXRvQ2x1c3Rlcigpe2lmKCFwcm9qZWN0KXJldHVybjtjb25zdCByPWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrcHJvamVjdC5pZCsnL2NsdXN0ZXInLHttZXRob2Q6J1BPU1QnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sYm9keTpKU09OLnN0cmluZ2lmeSh7cmFkaXVzX206TnVtYmVyKHN0b3BSYWRpdXMudmFsdWV8fDIwMCl9KX0pO3Byb2plY3Q9cjtyZW5kZXJBbGwoKTtzdGF0dXMoJ1N0b3BzIGNsdXN0ZXJlZCcpfWFzeW5jIGZ1bmN0aW9uIHJlbmRlck1wNCgpe2lmKCFwcm9qZWN0KXJldHVybiBzdGF0dXMoJ0xvYWQgYSBwcm9qZWN0IGZpcnN0Jyk7Y29uc3QgZmQ9bmV3IEZvcm1EYXRhKCk7ZmQuYXBwZW5kKCdkdXJhdGlvbl9taW4nLGR1cmF0aW9uTWluLnZhbHVlKTtpZihhdWRpb0lucHV0LmZpbGVzWzBdKWZkLmFwcGVuZCgnYXVkaW8nLGF1ZGlvSW5wdXQuZmlsZXNbMF0pO3N0YXR1cygnUmVuZGVyaW5nIE1QNC4uLicpO2NvbnN0IGo9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytwcm9qZWN0LmlkKycvcmVuZGVyJyx7bWV0aG9kOidQT1NUJyxib2R5OmZkfSk7c3RhdHVzKCdSZW5kZXJlZDogJytqLnVybCk7d2luZG93Lm9wZW4oai51cmwsJ19ibGFuaycpfQpmdW5jdGlvbiBvcGVuUHJlc2VudEF0KGk9MCl7cHJlc2VudEluZGV4PWk7cHJlc2VudE92ZXJsYXkuY2xhc3NMaXN0LmFkZCgnc2hvdycpO2RyYXdQcmVzZW50KCl9ZnVuY3Rpb24gb3BlblByZXNlbnQoKXtpZighcHJvamVjdHx8IXByb2plY3Quc3RvcHMubGVuZ3RoKXJldHVybiBzdGF0dXMoJ0xvYWQgb3IgY3JlYXRlIGEgam91cm5leSBmaXJzdCcpO29wZW5QcmVzZW50QXQoMCl9ZnVuY3Rpb24gZHJhd1ByZXNlbnQoKXtjb25zdCBzPXByb2plY3Quc3RvcHNbcHJlc2VudEluZGV4XTtjb25zdCBhc3NldHM9KHByb2plY3QuYXNzZXRzfHxbXSkuZmlsdGVyKGE9PihzLmFzc2V0X2lkc3x8W10pLmluY2x1ZGVzKGEuYXNzZXRfaWQpKTtwcmVzZW50TWV0YS50ZXh0Q29udGVudD1gJHtwcm9qZWN0Lm5hbWV9IOKAoiAke3Byb2plY3Quc3RvcHMubGVuZ3RofSBzdG9wc2A7cHJlc2VudFN0YWdlLmlubmVySFRNTD1gPGRpdj48ZGl2IHN0eWxlPSJjb2xvcjp2YXIoLS1jeWFuKTtmb250LXNpemU6MThweDttYXJnaW4tYm90dG9tOjEwcHgiPlN0b3AgJHtwcmVzZW50SW5kZXgrMX0gLyAke3Byb2plY3Quc3RvcHMubGVuZ3RofTwvZGl2PjxkaXYgc3R5bGU9ImZvbnQtc2l6ZTo0NnB4O21hcmdpbi1ib3R0b206MTBweCI+JHtzdWdnZXN0U3RvcE5hbWUocyxwcmVzZW50SW5kZXgpfTwvZGl2PjxkaXYgc3R5bGU9ImNvbG9yOnZhcigtLW11dGVkKSI+JHthc3NldHMubGVuZ3RofSBwaG90b3MgbmVhcmJ5PC9kaXY+PGRpdiBzdHlsZT0iZGlzcGxheTpmbGV4O2dhcDoxMnB4O2p1c3RpZnktY29udGVudDpjZW50ZXI7bWFyZ2luLXRvcDoyNnB4Ij4ke2Fzc2V0cy5zbGljZSgwLDQpLm1hcChhPT5hLnRodW1iP2A8aW1nIHNyYz0iJHthLnRodW1ifSIgc3R5bGU9IndpZHRoOjE4MHB4O2hlaWdodDoxMjBweDtvYmplY3QtZml0OmNvdmVyO2JvcmRlci1yYWRpdXM6MTZweDtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTcsMjU1LC40KSI+YDpgYCkuam9pbignJyl9PC9kaXY+PC9kaXY+YDtpZihtYXApbWFwLmZseVRvKHtjZW50ZXI6W3MubG9uLHMubGF0XSx6b29tOjE2LHBpdGNoOjQ1LGR1cmF0aW9uOjEwMDB9KX1mdW5jdGlvbiBuZXh0UHJlc2VudCgpe3ByZXNlbnRJbmRleD0ocHJlc2VudEluZGV4KzEpJXByb2plY3Quc3RvcHMubGVuZ3RoO2RyYXdQcmVzZW50KCl9ZnVuY3Rpb24gcHJldlByZXNlbnQoKXtwcmVzZW50SW5kZXg9KHByZXNlbnRJbmRleC0xK3Byb2plY3Quc3RvcHMubGVuZ3RoKSVwcm9qZWN0LnN0b3BzLmxlbmd0aDtkcmF3UHJlc2VudCgpfQpmdW5jdGlvbiBiaW5kKCl7bmV3SW1taWNoQnRuLm9uY2xpY2s9KCk9PmltbWljaE1vZGFsLmNsYXNzTGlzdC5hZGQoJ3Nob3cnKTtjbG9zZUltbWljaEJ0bi5vbmNsaWNrPSgpPT5pbW1pY2hNb2RhbC5jbGFzc0xpc3QucmVtb3ZlKCdzaG93Jyk7dGVzdEtleUJ0bi5vbmNsaWNrPSgpPT50ZXN0SW1taWNoKCkuY2F0Y2goZT0+c3RhdHVzKCdFcnJvcjogJytlLm1lc3NhZ2UpKTtjcmVhdGVKb3VybmV5QnRuLm9uY2xpY2s9KCk9PmNyZWF0ZUpvdXJuZXkoKS5jYXRjaChlPT5zdGF0dXMoJ0Vycm9yOiAnK2UubWVzc2FnZSkpO2NsZWFyRmlsdGVyQnRuLm9uY2xpY2s9Y2xlYXJGaWx0ZXI7cHJlc2VudEJ0bi5vbmNsaWNrPW9wZW5QcmVzZW50O2V4cG9ydEp1bXBCdG4ub25jbGljaz0oKT0+ZXhwb3J0UGFuZWwuc2Nyb2xsSW50b1ZpZXcoe2JlaGF2aW9yOidzbW9vdGgnLGJsb2NrOidjZW50ZXInfSk7YWNjb3VudEJ0bi5vbmNsaWNrPSgpPT5hY2NvdW50TW9kYWwuY2xhc3NMaXN0LmFkZCgnc2hvdycpO3NldHRpbmdzQnRuLm9uY2xpY2s9KCk9PmFjY291bnRNb2RhbC5jbGFzc0xpc3QuYWRkKCdzaG93Jyk7Y2xvc2VBY2NvdW50QnRuLm9uY2xpY2s9KCk9PmFjY291bnRNb2RhbC5jbGFzc0xpc3QucmVtb3ZlKCdzaG93Jyk7c2F2ZUFjY291bnRCdG4ub25jbGljaz0oKT0+e3NhdmVDb25uKGFjY291bnRVcmwudmFsdWUudHJpbSgpLGFjY291bnRLZXkudmFsdWUudHJpbSgpKTtzdGF0dXMoJ1NhdmVkIEltbWljaCBjb25uZWN0aW9uJyl9O2F1dG9DbHVzdGVyQnRuLm9uY2xpY2s9KCk9PmF1dG9DbHVzdGVyKCkuY2F0Y2goZT0+c3RhdHVzKCdFcnJvcjogJytlLm1lc3NhZ2UpKTtyZXZlcnNlUm91dGVCdG4ub25jbGljaz1yZXZlcnNlUm91dGU7cmVuZGVyQnRuLm9uY2xpY2s9KCk9PnJlbmRlck1wNCgpLmNhdGNoKGU9PnN0YXR1cygnRXJyb3I6ICcrZS5tZXNzYWdlKSk7ZXhwYW5kU3RvcHNCdG4ub25jbGljaz0oKT0+ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnLnN0b3BDYXJkJykuZm9yRWFjaChjPT5jLmNsYXNzTGlzdC50b2dnbGUoJ29wZW4nKSk7em9vbUluLm9uY2xpY2s9KCk9Pm1hcCYmbWFwLnpvb21JbigpO3pvb21PdXQub25jbGljaz0oKT0+bWFwJiZtYXAuem9vbU91dCgpO2Nsb3NlUHJlc2VudEJ0bi5vbmNsaWNrPSgpPT57cHJlc2VudE92ZXJsYXkuY2xhc3NMaXN0LnJlbW92ZSgnc2hvdycpO2NsZWFySW50ZXJ2YWwocHJlc2VudFRpbWVyKX07cHJlc2VudE5leHQub25jbGljaz1uZXh0UHJlc2VudDtwcmVzZW50UHJldi5vbmNsaWNrPXByZXZQcmVzZW50O3ByZXNlbnRQbGF5Lm9uY2xpY2s9KCk9PntjbGVhckludGVydmFsKHByZXNlbnRUaW1lcik7cHJlc2VudFRpbWVyPXNldEludGVydmFsKG5leHRQcmVzZW50LDI1MDApfX0KaW5pdERhdGVzKCk7YmluZCgpO2Vuc3VyZU1hcCgpO2xvYWRQcm9qZWN0cygpLmNhdGNoKGU9PnN0YXR1cygnRXJyb3I6ICcrZS5tZXNzYWdlKSk7Cjwvc2NyaXB0Pgo8L2JvZHk+CjwvaHRtbD4=
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








pct exec "$CTID" -- bash -lc "grep -q 'Trippy v10.2.0' /opt/trippy/frontend/index.html && grep -q 'Present Journey' /opt/trippy/frontend/index.html && grep -q 'trippyLogo' /opt/trippy/frontend/index.html" >/dev/null 2>&1 || {
  printf "${RED}ERROR:${RESET} UI smoke check failed. Frontend replacement missing from /opt/trippy/frontend/index.html.\n"
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
printf "${CYAN}${BOLD}v10.2.0 features${RESET}\n"
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
printf "  ${CYAN}•${RESET} Present Mode-first, with MP4 tucked under Export & Render\n"
printf "  ${CYAN}•${RESET} Delete old projects from the UI\n"
printf "  ${CYAN}•${RESET} Save Immich URL/API key locally in browser\n"
printf "  ${CYAN}•${RESET} First-run Immich API key setup prompt\n"
printf "  ${CYAN}•${RESET} Account panel for updating Immich connection\n"
printf "  ${CYAN}•${RESET} Immich connection validator\n"
printf "  ${CYAN}•${RESET} Setup permissions: asset.read, asset.view, asset.download, map.read, timeline.read\n"
printf "  ${CYAN}•${RESET} Safer project thumbnail proxy for new projects\n"printf "  ${CYAN}•${RESET} v10.2.0 directly patches /opt/trippy/frontend/index.html
"

echo
printf "  ${CYAN}•${RESET} Auto-selects next available CTID by default\n"
printf "  ${CYAN}•${RESET} Container hostname/name: Trippy\n"
printf "  ${CYAN}•${RESET} Present Mode-first interactive journey player\n"
printf "  ${CYAN}•${RESET} Logo/brand identity in installer, LXC notes, and web banner\n"
printf "  ${CYAN}•${RESET} Future export direction: portable interactive journey package, MP4 secondary\n"
printf "  ${CYAN}•${RESET} v10.2.0 real UI pass: cleaner top bar, Present Mode, export tucked away, better popups, stop title suggestions\n"
printf "  ${CYAN}•${RESET} v10.2.0 full frontend replacement inspired by the mockup UI\n"
printf "${PINK}${BOLD}Go make something weird.${RESET}\n"
