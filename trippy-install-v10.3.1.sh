#!/usr/bin/env bash
set -euo pipefail
USER_SUPPLIED_CTID="${CTID:-}"

# Trippy v10.3.1: Immich-style web UI route-tour generator for Proxmox LXC
# Adds stop-based clustering, stop radius, stop review/editing, and lasso grouping.
#
#
# Install directly from GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.3.1.sh \
#     -o trippy-install-v10.3.1.sh
#   chmod +x trippy-install-v10.3.1.sh
#   ./trippy-install-v10.3.1.sh
#
# Or with wget:
#
#   wget -O trippy-install-v10.3.1.sh \
#     https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.3.1.sh
#   chmod +x trippy-install-v10.3.1.sh
#   ./trippy-install-v10.3.1.sh
#
# Installer implementation note:
#   Large frontend files are staged on the Proxmox host and copied with pct push.
#   Do not inline the frontend inside pct exec; Linux command arguments have a size limit.
#
# Run on Proxmox host:
#   bash trippy-install-v10.3.1.sh
#
# Optional:
#   CTID=106 STORAGE=local-lvm BRIDGE=vmbr0 bash trippy-install-v10.3.1.sh

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

printf "${CYAN}${BOLD}Trippy v10.3.1 Clean Installer${RESET}\n"
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

pct set "$CTID" --description "🧭 Trippy v10.3.1
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

app = FastAPI(title="Trippy", version="1.3.1")
app.mount("/exports", StaticFiles(directory=str(EXPORTS)), name="exports")
app.mount("/uploads", StaticFiles(directory=str(UPLOADS)), name="uploads")
app.mount("/static", StaticFiles(directory=str(FRONTEND)), name="static")

@app.get("/api/health")
def health():
    return {
        "ok": True,
        "app": "trippy",
        "version": "1.3.1",
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
// Trippy v10.3.1 UI behavior upgrades
(function(){{
  function ready(fn){{ if(document.readyState!=='loading') fn(); else document.addEventListener('DOMContentLoaded',fn); }}
  window.TRIPPY_VERSION='v10.3.1';
  ready(() => {{
    if(!document.querySelector('.versionBadge')){{
      const v=document.createElement('div'); v.className='versionBadge'; v.textContent='v10.3.1'; document.body.appendChild(v);
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
      const v=document.createElement('div');v.className='versionBadge';v.textContent='v10.3.1';document.body.appendChild(v);
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

/* Trippy v10.3.1 UI refresh */
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

cat >/tmp/trippy_index.html <<'TRIPPY_FRONTEND_EOF_1031'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Trippy v10.3.1</title>
<link rel="stylesheet" href="/static/vendor/maplibre-gl.css">
<script src="/static/vendor/maplibre-gl.js"></script>
<style>
:root{
  --bg:#030813;--bg2:#07111d;--panel:#081421;--panel2:#0d1c2c;--card:#0c1a29;
  --line:#1d3850;--line2:#254a68;--cyan:#00d8ff;--cyan2:#36edff;--blue:#267dff;
  --violet:#6848ff;--pink:#ff4da6;--green:#39d995;--red:#ff4d66;--text:#f2f8ff;
  --muted:#8ea3b6;--soft:#b8c8d7;--shadow:0 24px 70px rgba(0,0,0,.42)
}
*{box-sizing:border-box}
html,body{height:100%;margin:0;overflow:hidden;background:var(--bg);color:var(--text);font-family:Inter,"Segoe UI",system-ui,sans-serif}
body{background:radial-gradient(circle at 9% 0%,rgba(0,216,255,.13),transparent 27%),radial-gradient(circle at 82% 7%,rgba(104,72,255,.12),transparent 30%),linear-gradient(145deg,#020711,#07121e 58%,#02060d)}
button,input,select{font:inherit}button{color:var(--text);cursor:pointer;border:1px solid rgba(75,126,164,.45);border-radius:13px;background:linear-gradient(180deg,rgba(20,43,66,.98),rgba(10,25,41,.98));font-weight:800;transition:.16s ease}button:hover{border-color:var(--cyan);box-shadow:0 0 22px rgba(0,216,255,.22);transform:translateY(-1px)}
input,select{width:100%;color:var(--text);background:#07111c;border:1px solid rgba(90,139,173,.38);border-radius:12px;padding:11px 12px;outline:none}input:focus,select:focus{border-color:var(--cyan);box-shadow:0 0 0 3px rgba(0,216,255,.10)}
.small{font-size:12px;color:var(--muted)}.hidden{display:none!important}.svgIcon{width:20px;height:20px;stroke:currentColor;fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.appShell{height:100vh;display:grid;grid-template-columns:286px minmax(650px,1fr) 350px;overflow:hidden}
.leftRail{min-width:0;background:linear-gradient(180deg,rgba(4,13,23,.98),rgba(2,8,15,.99));border-right:1px solid rgba(0,216,255,.14);padding:17px 17px 20px;display:flex;flex-direction:column;gap:14px;box-shadow:16px 0 60px rgba(0,0,0,.34);z-index:10}
.brandLine{display:flex;align-items:center;gap:12px;height:64px}.wordmark{font-size:31px;font-weight:950;font-style:italic;letter-spacing:-1.5px;text-shadow:2px 0 var(--cyan),-2px 0 var(--pink),0 6px 25px rgba(0,0,0,.9)}.version{margin-left:auto;padding:6px 10px;border-radius:999px;border:1px solid rgba(0,216,255,.28);background:rgba(0,216,255,.08);color:var(--cyan2);font-size:13px;font-weight:950;box-shadow:0 0 18px rgba(0,216,255,.10)}
.logoFlower{position:relative;width:49px;height:49px;flex:0 0 auto;filter:drop-shadow(0 0 11px rgba(0,216,255,.35)) saturate(1.18)}.logoFlower .petal{position:absolute;left:18px;top:2px;width:17px;height:29px;border-radius:14px 14px 7px 7px;transform-origin:7px 23px;mix-blend-mode:screen}.logoFlower .p1{background:#ff5454;transform:rotate(0deg) translateY(-1px) skewX(-8deg)}.logoFlower .p2{background:#ffbb31;transform:rotate(60deg) translateY(0) skewX(9deg)}.logoFlower .p3{background:#79df4c;transform:rotate(120deg) translateY(1px) skewX(-8deg)}.logoFlower .p4{background:#27d6c7;transform:rotate(180deg) translateY(-1px) skewX(8deg)}.logoFlower .p5{background:#418cff;transform:rotate(240deg) translateY(1px) skewX(-10deg)}.logoFlower .p6{background:#df68ff;transform:rotate(300deg) translateY(-1px) skewX(9deg)}.logoFlower:before{content:"";position:absolute;inset:6px;border-radius:50%;box-shadow:3px 0 8px rgba(255,77,166,.45),-3px 0 8px rgba(0,216,255,.5);filter:blur(1px)}.logoFlower:after{content:"";position:absolute;inset:16px;border:2px solid rgba(245,253,255,.88);border-radius:50%;box-shadow:0 0 9px rgba(0,216,255,.9)}
.sidePrimary,.sideSecondary{height:54px;width:100%;font-size:14px}.sidePrimary{background:linear-gradient(135deg,#0962bd,#00a9c8);border-color:rgba(0,216,255,.88);box-shadow:0 0 28px rgba(0,216,255,.21)}
.sectionLabel{margin-top:8px;display:flex;align-items:center;justify-content:space-between;color:#c4d4e2;font-size:12px;font-weight:950;letter-spacing:.08em;text-transform:uppercase}.projectList{display:flex;flex-direction:column;gap:10px;overflow:auto;min-height:0;padding-right:2px}.projectCard{position:relative;padding:15px 14px;background:linear-gradient(180deg,rgba(13,29,45,.94),rgba(7,18,30,.94));border:1px solid rgba(62,113,151,.32);border-radius:15px;cursor:pointer;transition:.16s ease}.projectCard:hover,.projectCard.active{border-color:var(--cyan);box-shadow:0 0 24px rgba(0,216,255,.17)}.projectCardTitle{padding-right:24px;font-weight:900;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.projectDate{margin-top:6px;color:var(--muted);font-size:12px}.projectStats{margin-top:9px;color:#9eb4c6;font-size:12px}.projectStats .dot{color:var(--cyan)}.projectMenu{position:absolute;right:9px;top:10px;width:28px;height:32px;border:0;background:transparent;font-size:20px;box-shadow:none}.projectDelete{width:100%;height:34px;margin-top:10px;font-size:12px;display:none}.projectCard.menuOpen .projectDelete{display:block}
.leftFooter{margin-top:auto;color:#8296a8;font-size:12px;line-height:1.65}.footerLink{display:block;margin-top:10px;color:var(--cyan);text-decoration:none}
.workspace{min-width:0;display:grid;grid-template-rows:91px minmax(350px,1fr) 228px;background:rgba(2,8,14,.50)}
.topBar{display:flex;align-items:center;gap:16px;padding:14px 19px;border-bottom:1px solid rgba(0,216,255,.13);background:rgba(3,10,18,.84);backdrop-filter:blur(18px);z-index:8}.titleArea{min-width:320px;max-width:430px}.journeyTitleRow{display:flex;align-items:center;gap:9px}.journeyTitle{font-size:22px;font-weight:950;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.editTitle{border:0;background:transparent;color:var(--muted);padding:2px;box-shadow:none}.journeyMeta{display:flex;align-items:center;gap:11px;margin-top:6px;color:var(--muted);font-size:12px}.journeyMeta .liveDot{width:7px;height:7px;border-radius:50%;background:var(--green);box-shadow:0 0 8px rgba(57,217,149,.6)}.topSpacer{flex:1}.presentButton{height:54px;min-width:265px;padding:0 24px;background:linear-gradient(135deg,#633bff,#00afd0);border-color:rgba(0,216,255,.85);box-shadow:0 0 32px rgba(0,216,255,.28);font-size:15px}.presentButton span{display:block;font-size:11px;font-weight:650;opacity:.84;margin-top:2px}.topAction{height:54px;min-width:145px;padding:0 16px}.gearButton{width:54px;min-width:54px;height:54px;font-size:20px}
.mapZone{position:relative;min-height:0;padding:0 8px 0 0}.mapFrame{position:absolute;inset:0 8px 0 0;border:1px solid rgba(0,216,255,.18);border-radius:18px;overflow:hidden;box-shadow:var(--shadow);background:#9cb6be}.mapCanvas{position:absolute;inset:0}.mapShade{position:absolute;inset:0;pointer-events:none;background:linear-gradient(180deg,rgba(1,7,13,.04),rgba(1,7,13,.03))}.mapTools{position:absolute;left:17px;top:18px;z-index:4;display:flex;flex-direction:column;gap:9px}.mapTool{width:47px;height:47px;display:grid;place-items:center;border-radius:13px;background:rgba(7,19,31,.92);border:1px solid rgba(69,119,154,.42);box-shadow:0 12px 28px rgba(0,0,0,.28);color:#e7f7ff}.mapTool.active{background:linear-gradient(135deg,#0d9bc3,#00d4ee);border-color:#5af3ff}.mapZoomGroup{display:flex;flex-direction:column;margin-top:4px}.mapZoomGroup .mapTool{border-radius:0}.mapZoomGroup .mapTool:first-child{border-radius:13px 13px 0 0}.mapZoomGroup .mapTool:last-child{border-radius:0 0 13px 13px;border-top:0}.filterChip{position:absolute;right:20px;top:20px;z-index:5;display:none;align-items:center;gap:10px;padding:10px 11px 10px 14px;border-radius:14px;background:rgba(5,16,27,.94);border:1px solid rgba(73,125,161,.42);box-shadow:0 15px 36px rgba(0,0,0,.32);font-size:12px}.filterChip.show{display:flex}.filterChip button{width:30px;height:30px;padding:0}
.photoMarker{position:relative;width:54px;height:54px;border-radius:50%;padding:3px;background:#edfaff;border:3px solid var(--cyan);box-shadow:0 0 0 2px rgba(255,255,255,.55),0 0 22px rgba(0,216,255,.65);cursor:pointer;transition:.15s ease}.photoMarker:hover,.photoMarker.active{transform:scale(1.11);border-color:white;box-shadow:0 0 0 3px var(--cyan),0 0 28px rgba(0,216,255,.85)}.photoMarker img{width:100%;height:100%;display:block;object-fit:cover;border-radius:50%;background:#173149}.photoMarker .fallback{width:100%;height:100%;display:grid;place-items:center;border-radius:50%;background:radial-gradient(circle at 30% 30%,#3f819a,#0a2639);font-weight:950}.markerBadge{position:absolute;left:50%;top:-16px;transform:translateX(-50%);min-width:28px;height:28px;padding:0 6px;display:grid;place-items:center;border-radius:999px;background:#07131f;color:#fff;border:2px solid rgba(255,255,255,.72);font-size:12px;font-weight:950;box-shadow:0 5px 15px rgba(0,0,0,.45)}
.maplibregl-popup-content{padding:0!important;background:transparent!important;border-radius:18px!important;box-shadow:none!important}.maplibregl-popup-tip{border-top-color:#07131f!important}.maplibregl-popup-close-button{z-index:4;right:8px!important;top:8px!important;width:28px;height:28px;border-radius:50%!important;background:rgba(8,20,33,.82)!important;color:white!important;font-size:18px!important;border:1px solid rgba(255,255,255,.22)!important}.stopPopup{width:330px;border-radius:18px;overflow:hidden;background:#07131f;border:1px solid rgba(0,216,255,.42);box-shadow:0 0 40px rgba(0,216,255,.25),0 25px 65px rgba(0,0,0,.48)}.stopPopupImage{height:185px;background:#102a40}.stopPopupImage img{width:100%;height:100%;display:block;object-fit:cover}.stopPopupBody{padding:13px 15px 15px}.popupKicker{display:inline-flex;padding:5px 8px;border-radius:8px;background:rgba(0,216,255,.15);color:var(--cyan);font-size:11px;font-weight:900}.popupTitle{margin-top:9px;font-size:19px;font-weight:950}.popupMeta{margin-top:6px;color:var(--muted);font-size:12px}.popupButtons{display:flex;gap:8px;margin-top:12px}.popupButtons button{height:40px;flex:1;font-size:12px}.popupButtons .danger{flex:0 0 42px;color:var(--red)}
.mediaStrip{min-width:0;padding:13px 17px 15px;border-top:1px solid rgba(0,216,255,.12);background:linear-gradient(180deg,rgba(4,12,20,.72),rgba(3,9,16,.95))}.mediaHeader{height:31px;display:flex;align-items:center;gap:11px}.mediaTitle{font-size:14px;font-weight:950}.mediaCount{font-size:12px;color:var(--muted)}.mediaHeaderSpacer{flex:1}.tinyButton{width:31px;height:31px;padding:0;border-radius:10px}.gallery{height:164px;display:flex;gap:10px;overflow-x:auto;overflow-y:hidden;padding:8px 1px 4px;scrollbar-width:thin}.mediaTile{position:relative;flex:0 0 218px;height:145px;border-radius:13px;overflow:hidden;background:#102235;border:1px solid rgba(71,123,160,.35);cursor:pointer;transition:.16s ease}.mediaTile:hover,.mediaTile.active{border-color:var(--cyan);box-shadow:0 0 21px rgba(0,216,255,.24);transform:translateY(-2px)}.mediaTile img{width:100%;height:100%;object-fit:cover;display:block}.mediaTileName{position:absolute;left:0;right:0;bottom:0;padding:25px 10px 9px;background:linear-gradient(transparent,rgba(1,6,11,.9));font-size:11px;font-weight:850;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rightRail{min-width:0;background:linear-gradient(180deg,rgba(4,12,21,.97),rgba(2,8,15,.99));border-left:1px solid rgba(0,216,255,.14);padding:15px 15px 17px;display:flex;flex-direction:column;overflow:hidden}.rightTop{display:flex;align-items:center;height:40px}.rightTitle{font-size:13px;font-weight:950;text-transform:uppercase;letter-spacing:.04em}.rightCount{color:var(--muted);margin-left:5px}.rightSearch{margin-left:auto;width:35px;height:35px;padding:0;background:transparent;border:0;box-shadow:none}.stopSearchWrap{display:none;margin-bottom:10px}.stopSearchWrap.show{display:block}.stopList{display:flex;flex-direction:column;gap:9px;overflow:auto;min-height:250px;flex:1 1 0;padding:2px 4px 12px 0}.stopCard{flex:0 0 auto;min-height:76px;border-radius:13px;background:linear-gradient(180deg,rgba(13,28,44,.96),rgba(8,20,33,.96));border:1px solid rgba(61,108,143,.34);overflow:hidden;transition:.15s ease}.stopCard:hover,.stopCard.active{border-color:var(--cyan);box-shadow:inset 4px 0 0 var(--cyan),0 0 18px rgba(0,216,255,.13)}.stopSummary{min-height:76px;padding:12px 12px;display:grid;grid-template-columns:31px minmax(0,1fr) 22px;align-items:center;gap:10px;cursor:pointer}.stopNumber{width:29px;height:29px;border-radius:999px;display:grid;place-items:center;background:rgba(0,216,255,.12);border:1px solid rgba(0,216,255,.35);font-size:12px;font-weight:950;text-align:center}.stopName{font-size:13px;font-weight:950;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.stopMeta{margin-top:5px;color:var(--muted);font-size:10.5px;line-height:1.35}.stopChevron{color:var(--muted);font-size:18px;transition:.15s}.stopCard.open .stopChevron{transform:rotate(90deg)}.stopControls{display:none;padding:0 12px 12px 53px;gap:6px;flex-wrap:wrap}.stopCard.open .stopControls{display:flex}.stopControls button{height:32px;padding:0 9px;font-size:10px}.addStopButton{flex:0 0 auto;height:42px;width:100%;margin:4px 0 12px}.assetBubble{width:52px;height:52px;border-radius:50%;overflow:hidden;border:3px solid #00d8ff;background:#06111d;box-shadow:0 0 0 3px rgba(4,17,28,.92),0 0 22px rgba(0,216,255,.52);cursor:pointer;transition:.16s}.assetBubble:hover,.assetBubble.active{transform:scale(1.12);border-color:white;z-index:15}.assetBubble img{width:100%;height:100%;display:block;object-fit:cover}.assetBubble .assetDot{width:100%;height:100%;display:grid;place-items:center;color:var(--cyan);font-size:19px}
.exportBox{flex:0 0 auto;border:1px solid rgba(62,111,148,.30);border-radius:14px;background:rgba(8,19,31,.90);overflow:hidden}.exportHeader{height:48px;padding:0 13px;display:flex;align-items:center;justify-content:space-between;font-size:13px;font-weight:950;cursor:pointer}.exportBody{padding:0 12px 12px}.exportBox.collapsed .exportBody{display:none}.exportTabs{display:grid;grid-template-columns:1fr 1fr 1fr;border:1px solid rgba(63,113,150,.33);border-radius:10px;overflow:hidden;margin:7px 0 12px}.exportTabs button{border:0;border-radius:0;height:36px;background:#07131f;font-size:10px}.exportTabs button.active{background:linear-gradient(135deg,#0879c3,#00a9c9);box-shadow:none}.fieldLabel{display:block;font-size:10px;color:var(--muted);margin:10px 0 5px}.audioRow{display:flex;align-items:center;justify-content:space-between;color:var(--soft);font-size:11px}.switch{width:39px;height:21px;border-radius:999px;background:#20374a;border:1px solid #35536a;position:relative;cursor:pointer}.switch:after{content:"";position:absolute;top:2px;left:2px;width:15px;height:15px;border-radius:50%;background:#dceaf4;transition:.16s}.switch.on{background:#00a9ce;border-color:#20e1ff}.switch.on:after{left:20px}.audioInput{display:none}.renderButton{width:100%;height:55px;margin-top:11px;background:linear-gradient(135deg,#087da3,#11bace);border-color:rgba(0,216,255,.75);font-size:14px}.renderButton span{display:block;font-size:10px;font-weight:650;opacity:.85;margin-top:2px}
.modal{position:fixed;inset:0;z-index:1000;display:none;align-items:center;justify-content:center;padding:24px;background:rgba(0,4,9,.75);backdrop-filter:blur(7px)}.modal.show{display:flex}.modalCard{width:min(720px,94vw);max-height:90vh;overflow:auto;padding:21px;border-radius:19px;background:#07131f;border:1px solid rgba(0,216,255,.35);box-shadow:0 0 60px rgba(0,216,255,.18),0 35px 100px rgba(0,0,0,.55)}.modalTitle{font-size:21px;font-weight:950;margin-bottom:15px}.formGrid{display:grid;gap:11px}.twoCol{display:grid;grid-template-columns:1fr 1fr;gap:11px}.modalActions{display:flex;justify-content:flex-end;gap:9px;margin-top:6px}.modalActions button{height:42px;padding:0 16px}.primary{background:linear-gradient(135deg,#075db4,#00aecb);border-color:var(--cyan)}
.toast{position:fixed;left:305px;bottom:18px;z-index:3000;display:none;padding:11px 14px;border-radius:12px;background:rgba(6,19,31,.95);border:1px solid rgba(0,216,255,.32);box-shadow:0 15px 40px rgba(0,0,0,.35);font-size:12px}.toast.show{display:block}
.presentOverlay{position:fixed;inset:0;z-index:2200;display:none;background:#020710}.presentOverlay.show{display:grid;grid-template-rows:72px minmax(0,1fr) 170px}.presentHeader{display:flex;align-items:center;gap:13px;padding:10px 18px;border-bottom:1px solid rgba(0,216,255,.16);background:rgba(3,10,18,.90)}.presentHeaderTitle{font-size:20px;font-weight:950}.presentHeaderMeta{color:var(--muted);font-size:11px;margin-top:3px}.presentHeaderSpacer{flex:1}.presentMain{position:relative;min-height:0}.presentMap{position:absolute;inset:0}.presentStopRail{position:absolute;left:18px;top:18px;bottom:18px;width:240px;z-index:4;padding:12px;border-radius:16px;background:rgba(4,14,24,.84);border:1px solid rgba(0,216,255,.24);backdrop-filter:blur(15px);overflow:auto}.presentStopItem{padding:10px;border-radius:10px;color:#b4c8d8;font-size:12px;cursor:pointer}.presentStopItem.active{background:rgba(0,216,255,.14);color:white;box-shadow:inset 3px 0 0 var(--cyan)}.presentStopBanner{position:absolute;left:50%;top:18px;transform:translateX(-50%);z-index:7;min-width:420px;max-width:720px;padding:14px 20px;border-radius:17px;background:rgba(4,14,24,.88);border:1px solid rgba(0,216,255,.30);box-shadow:0 22px 55px rgba(0,0,0,.42),0 0 30px rgba(0,216,255,.12);backdrop-filter:blur(15px);text-align:center}.presentStopBannerTitle{font-size:24px;font-weight:950}.presentStopBannerRange{margin-top:4px;color:#b8ccda;font-size:12px}.presentPhotoCard{position:absolute;right:22px;top:96px;width:min(480px,38vw);max-height:calc(100% - 180px);z-index:8;border-radius:18px;overflow:hidden;background:rgba(5,15,25,.97);border:1px solid rgba(0,216,255,.38);box-shadow:0 0 42px rgba(0,216,255,.20),0 25px 60px rgba(0,0,0,.5);display:none}.presentPhotoCard.show{display:block}.presentPhotoCard img{width:100%;max-height:56vh;object-fit:contain;display:block;background:#010409}.presentPhotoBody{padding:14px 16px}.presentPhotoTitle{font-size:16px;font-weight:950;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.presentPhotoMeta{color:#d5e7f1;font-size:13px;margin-top:6px;letter-spacing:.02em}.presentPhotoCoords{color:var(--muted);font-size:11px;margin-top:7px;line-height:1.5}.presentPhotoActions{display:flex;gap:8px;margin-top:12px}.presentPhotoActions button{height:38px;padding:0 12px;font-size:11px}.presentPhotoActions .danger{margin-left:auto;color:#ffdbe1;border-color:rgba(255,77,102,.55);background:rgba(105,20,38,.72)}.presentHud{position:absolute;left:50%;bottom:18px;transform:translateX(-50%);z-index:6;display:flex;align-items:center;gap:8px;padding:8px;border-radius:16px;background:rgba(4,14,24,.86);border:1px solid rgba(0,216,255,.22);backdrop-filter:blur(12px)}.presentHud button{height:42px;padding:0 14px;font-size:11px}.presentHud .play{min-width:110px;background:linear-gradient(135deg,#603cff,#00adcb)}.presentBack{width:46px;height:46px;border-radius:14px;font-size:21px;padding:0}.presentHeaderAction{height:42px;padding:0 13px;font-size:11px}.focusPulse{width:34px;height:34px;border-radius:50%;border:3px solid white;background:rgba(0,216,255,.22);box-shadow:0 0 0 7px rgba(0,216,255,.20),0 0 30px rgba(0,216,255,.95);pointer-events:none;animation:focusPulse 1.8s ease-in-out infinite}.mediaTileRemove{position:absolute;right:7px;top:7px;z-index:3;width:30px;height:30px;padding:0;border-radius:50%;background:rgba(7,19,31,.88);border-color:rgba(255,255,255,.28);font-size:16px;color:#ffdbe1}.mediaTileRemove:hover{border-color:var(--red);box-shadow:0 0 16px rgba(255,77,102,.35)}@keyframes focusPulse{0%,100%{transform:scale(.92);opacity:.75}50%{transform:scale(1.08);opacity:1}}.presentFilmstrip{padding:12px 18px;background:linear-gradient(180deg,#06111d,#020711);border-top:1px solid rgba(0,216,255,.14);display:flex;gap:10px;overflow-x:auto}.presentThumb{flex:0 0 190px;height:140px;border-radius:13px;overflow:hidden;border:1px solid rgba(69,121,158,.34);cursor:pointer;position:relative}.presentThumb.active{border-color:var(--cyan);box-shadow:0 0 21px rgba(0,216,255,.28)}.presentThumb img{width:100%;height:100%;display:block;object-fit:cover}.presentThumbLabel{position:absolute;inset:auto 0 0;padding:24px 8px 7px;background:linear-gradient(transparent,rgba(0,0,0,.85));font-size:10px;font-weight:800}
@media(max-width:1300px){.appShell{grid-template-columns:250px minmax(580px,1fr) 320px}.leftRail{padding-left:13px;padding-right:13px}.wordmark{font-size:27px}.presentButton{min-width:220px}.titleArea{min-width:240px}.topAction{min-width:110px}.mediaTile{flex-basis:185px}}
</style>
<style id="TRIPPY_V103_STYLE">
/* Trippy v10.3.1 journey hierarchy */
.v103Hidden{display:none!important}
.rightRail{padding:18px 16px!important}
.journeyActions{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:7px;margin:10px 0 12px}
.journeyActions button{height:38px;padding:0 7px;font-size:10px;border-radius:11px}
.journeyActions button.active{border-color:var(--cyan);background:rgba(0,216,255,.16);box-shadow:0 0 18px rgba(0,216,255,.18)}
.journeyActions button:disabled{opacity:.38;cursor:not-allowed;transform:none;box-shadow:none}
.journeyMoreMenu{display:none;grid-template-columns:1fr;gap:7px;margin:-4px 0 12px;padding:10px;border:1px solid rgba(80,126,158,.25);border-radius:13px;background:rgba(5,15,25,.88)}
.journeyMoreMenu.show{display:grid}.journeyMoreMenu button{height:38px;font-size:11px}
.dayList{display:flex;flex-direction:column;gap:11px;min-height:0;overflow:auto;padding-right:2px}
.dayCard{border:1px solid rgba(73,116,146,.30);border-radius:16px;background:rgba(7,18,30,.72);overflow:hidden;box-shadow:0 12px 30px rgba(0,0,0,.18)}
.dayCard.open{border-color:rgba(0,216,255,.26)}
.dayHeader{display:flex;align-items:center;gap:10px;padding:13px 12px;cursor:pointer;background:linear-gradient(180deg,rgba(15,34,52,.92),rgba(8,22,36,.92))}
.dayHeader:hover{background:linear-gradient(180deg,rgba(20,45,68,.96),rgba(9,25,41,.96))}
.dayIndex{width:31px;height:31px;display:grid;place-items:center;border-radius:11px;background:linear-gradient(135deg,#5d3cff,#00b7ce);font-size:12px;font-weight:950;box-shadow:0 0 18px rgba(0,216,255,.18)}
.dayTitleWrap{min-width:0;flex:1}.dayTitle{font-weight:950;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.dayMeta{font-size:10px;color:var(--muted);margin-top:4px}.dayRename{width:31px;height:31px;padding:0;border-radius:10px;font-size:12px}.dayChevron{font-size:13px;transition:.18s}.dayCard:not(.open) .dayChevron{transform:rotate(-90deg)}
.dayBody{display:none;padding:9px;gap:8px}.dayCard.open .dayBody{display:grid}
.journeyItem{border:1px solid rgba(68,108,138,.24);border-radius:13px;background:rgba(10,25,40,.82);overflow:hidden;transition:.16s}
.journeyItem:hover,.journeyItem.active{border-color:rgba(0,216,255,.62);box-shadow:0 0 20px rgba(0,216,255,.12)}
.journeyItem.segment{background:linear-gradient(135deg,rgba(29,27,61,.82),rgba(8,31,44,.88))}
.journeyItemMain{display:flex;align-items:center;gap:10px;padding:11px;cursor:pointer}
.itemBadge{width:31px;height:31px;flex:0 0 31px;display:grid;place-items:center;border-radius:50%;font-size:11px;font-weight:950;background:linear-gradient(135deg,#00c8ed,#247cff);box-shadow:0 0 15px rgba(0,216,255,.28)}
.itemBadge.drive{background:linear-gradient(135deg,#ff8a28,#ff4d7e)}.itemBadge.hike{background:linear-gradient(135deg,#43d17c,#00a8a8)}.itemBadge.custom{background:linear-gradient(135deg,#7756ff,#d85cff)}
.itemText{min-width:0;flex:1}.itemName{font-size:12px;font-weight:900;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.itemMeta{font-size:9.5px;color:#9db2c3;margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.segmentMembers{font-size:9px;color:#6fdcf0;margin-top:5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.itemChevron{color:#8ba2b3}
.itemControls{display:none;gap:6px;padding:0 10px 10px;border-top:1px solid rgba(75,119,150,.18);padding-top:9px}.journeyItem.active .itemControls,.journeyItem:hover .itemControls{display:flex;flex-wrap:wrap}.itemControls button{height:31px;padding:0 9px;font-size:9.5px;border-radius:9px}
.stopCheck{width:25px;height:25px;padding:0;flex:0 0 25px;border-radius:8px;background:#06111d}.stopCheck.checked{background:linear-gradient(135deg,#663cff,#00b9ce);border-color:var(--cyan)}
.presentDayLabel{margin:12px 5px 6px;padding:8px 9px;border-radius:9px;background:rgba(0,216,255,.08);border-left:3px solid var(--cyan);font-size:11px;font-weight:950;cursor:pointer}.presentDayLabel span{display:block;margin-top:3px;color:var(--muted);font-size:9px;font-weight:650}.presentDayLabel:hover{background:rgba(0,216,255,.14)}
.presentStopItem{margin-left:5px}.presentStopItem .small{line-height:1.4;margin-top:3px}
#exportBox.collapsed .exportBody{display:none!important}#exportBox.collapsed .exportHeader span:last-child{transform:rotate(180deg)}
@media(max-width:1350px){.journeyActions{grid-template-columns:1fr 1fr}.journeyActions button{font-size:9.5px}}

</style>
</head>
<body>
<div class="appShell">
  <aside class="leftRail">
    <div class="brandLine">
      <div class="logoFlower"><span class="petal p1"></span><span class="petal p2"></span><span class="petal p3"></span><span class="petal p4"></span><span class="petal p5"></span><span class="petal p6"></span></div>
      <div class="wordmark">trippy</div><div class="version">v10.3.1</div>
    </div>
    <button id="newImmichButton" class="sidePrimary">＋&nbsp; New Immich Journey</button>
    <button id="uploadButton" class="sideSecondary">⇧&nbsp; Upload Media</button>
    <div class="sectionLabel"><span>Projects</span><button id="projectSearchButton" class="projectMenu">⌕</button></div>
    <input id="projectSearch" class="hidden" placeholder="Search projects…">
    <div id="projectList" class="projectList"></div>
    <div class="leftFooter">Plan, organize, and relive your adventures on the map.
      <a class="footerLink" href="#">▣&nbsp; Documentation</a><a class="footerLink" href="#">◎&nbsp; Changelog</a>
    </div>
  </aside>

  <main class="workspace">
    <header class="topBar">
      <div class="titleArea"><div class="journeyTitleRow"><div id="journeyTitle" class="journeyTitle">No journey selected</div><button id="renameProjectButton" class="editTitle">✎</button></div><div id="journeyMeta" class="journeyMeta">Load or create a journey</div></div>
      <div class="topSpacer"></div>
      <button id="presentButton" class="presentButton">▶&nbsp; Present Journey<span>Immersive route playback</span></button>
      <button id="exportJumpButton" class="topAction">▣&nbsp; Export<br><span class="small">Render, GPX, and more&nbsp;⌄</span></button>
      <button id="settingsButton" class="gearButton">⚙</button>
      <button id="accountButton" class="topAction">♙&nbsp; Account&nbsp;⌄</button>
    </header>

    <section class="mapZone"><div class="mapFrame"><div id="map" class="mapCanvas"></div><div class="mapShade"></div>
      <div class="mapTools">
        <button id="locateButton" class="mapTool">➤</button><button id="lightMapButton" class="mapTool active">◫</button><button id="darkMapButton" class="mapTool">◐</button><button id="satelliteMapButton" class="mapTool">▧</button>
        <div class="mapZoomGroup"><button id="zoomInButton" class="mapTool">＋</button><button id="zoomOutButton" class="mapTool">−</button></div>
      </div>
      <div id="filterChip" class="filterChip"><span>▾&nbsp; <b id="filterChipText">Filter: All Stops</b></span><button id="clearFilterButton">×</button></div>
    </div></section>

    <section class="mediaStrip"><div class="mediaHeader"><div id="mediaTitle" class="mediaTitle">Media</div><div id="mediaCount" class="mediaCount"></div><div class="mediaHeaderSpacer"></div><button class="tinyButton">▦</button><button class="tinyButton">☷</button></div><div id="gallery" class="gallery"></div></section>
  </main>

  <aside class="rightRail">
    <div class="rightTop"><div class="rightTitle">Stops <span id="stopCount" class="rightCount">(0)</span></div><button id="stopSearchButton" class="rightSearch">⌕</button></div>
    <div id="stopSearchWrap" class="stopSearchWrap"><input id="stopSearch" placeholder="Search stops…"></div>
    <div id="stopList" class="stopList"></div>
    <button id="addStopButton" class="addStopButton">＋&nbsp; Add Stop Manually</button>
    <section id="exportBox" class="exportBox"><div id="exportHeader" class="exportHeader"><span>Export &amp; Render</span><span>⌃</span></div><div class="exportBody">
      <span class="fieldLabel">Export Format</span><div class="exportTabs"><button class="active">Video (MP4)</button><button id="gpxButton">GPX Track</button><button id="imageSetButton">Image Set</button></div>
      <span class="fieldLabel">Quality</span><select id="qualitySelect"><option>1080p (High)</option><option>720p</option></select>
      <div class="audioRow"><div><b>Include Audio</b><div class="small">Add music to your video</div></div><div id="audioSwitch" class="switch"></div></div><input id="audioInput" class="audioInput" type="file" accept="audio/*">
      <button id="renderButton" class="renderButton">▦&nbsp; Render MP4<span>Final video export</span></button>
    </div></section>
  </aside>
</div>

<div id="immichModal" class="modal"><div class="modalCard"><div class="modalTitle">New Immich Journey</div><div class="formGrid"><input id="immichUrl" placeholder="Immich URL — for example http://192.168.68.153:2283"><input id="immichKey" type="password" placeholder="Immich API key"><div class="twoCol"><input id="startDate" type="date"><input id="endDate" type="date"></div><div class="small">Required permissions: asset.read, asset.view, asset.download, map.read, timeline.read</div><div class="modalActions"><button id="testImmichButton">Test Connection</button><button id="createJourneyButton" class="primary">Create Journey</button><button data-close="immichModal">Cancel</button></div></div></div></div>
<div id="uploadModal" class="modal"><div class="modalCard"><div class="modalTitle">Upload GPS Media</div><div class="formGrid"><input id="uploadName" value="Uploaded Journey" placeholder="Journey name"><input id="uploadFiles" type="file" accept="image/*,video/*" multiple><div class="small">Only media containing GPS metadata can appear on the map.</div><div class="modalActions"><button id="createUploadButton" class="primary">Import Media</button><button data-close="uploadModal">Cancel</button></div></div></div></div>
<div id="settingsModal" class="modal"><div class="modalCard"><div class="modalTitle">Journey Settings</div><div class="formGrid"><label class="small">Stop radius, meters</label><input id="stopRadius" type="number" min="10" value="200"><div class="twoCol"><button id="reclusterButton">Auto-cluster Stops</button><button id="reverseRouteButton">Reverse Route</button></div><label class="small">Default map</label><select id="defaultMapSelect"><option value="light">Light OSM</option><option value="dark">Dark</option><option value="satellite">Satellite</option></select><div class="modalActions"><button data-close="settingsModal">Close</button></div></div></div></div>
<div id="accountModal" class="modal"><div class="modalCard"><div class="modalTitle">Account / Immich Connection</div><div class="formGrid"><input id="accountUrl" placeholder="Immich URL"><input id="accountKey" type="password" placeholder="API key"><div class="modalActions"><button id="saveAccountButton" class="primary">Save Connection</button><button data-close="accountModal">Close</button></div></div></div></div>

<div id="presentOverlay" class="presentOverlay"><div class="presentHeader"><button id="presentBackButton" class="presentBack" title="Back">←</button><div class="logoFlower"><span class="petal p1"></span><span class="petal p2"></span><span class="petal p3"></span><span class="petal p4"></span><span class="petal p5"></span><span class="petal p6"></span></div><div><div id="presentHeaderTitle" class="presentHeaderTitle">Present Journey</div><div id="presentHeaderMeta" class="presentHeaderMeta"></div></div><div class="presentHeaderSpacer"></div><button id="centerTripButton" class="presentHeaderAction">⌖ Center on Trip</button><button id="returnStartButton" class="presentHeaderAction">↶ Return to Start</button><button id="closePresentButton" class="topAction">Close</button></div>
  <div class="presentMain"><div id="presentMap" class="presentMap"></div><div id="presentStopBanner" class="presentStopBanner"><div id="presentStopBannerTitle" class="presentStopBannerTitle">Journey Stop</div><div id="presentStopBannerRange" class="presentStopBannerRange"></div></div><div id="presentStopRail" class="presentStopRail"></div><div id="presentPhotoCard" class="presentPhotoCard"></div><div class="presentHud"><button id="previousStopButton">← Stop</button><button id="previousPhotoButton">← Photo</button><button id="playJourneyButton" class="play">▶ Play</button><button id="nextPhotoButton">Photo →</button><button id="nextStopButton">Stop →</button></div></div><div id="presentFilmstrip" class="presentFilmstrip"></div>
</div>
<div id="toast" class="toast"></div>

<script>
const MAP_STYLES={
 light:{version:8,glyphs:'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',sources:{base:{type:'raster',tiles:['https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png','https://b.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png'],tileSize:256,attribution:'© OpenStreetMap contributors © CARTO'}},layers:[{id:'base',type:'raster',source:'base',minzoom:0,maxzoom:20}]},
 dark:{version:8,glyphs:'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',sources:{base:{type:'raster',tiles:['https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png','https://b.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png'],tileSize:256,attribution:'© OpenStreetMap contributors © CARTO'}},layers:[{id:'base',type:'raster',source:'base',minzoom:0,maxzoom:20}]},
 satellite:{version:8,glyphs:'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',sources:{base:{type:'raster',tiles:['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],tileSize:256,minzoom:0,maxzoom:18,attribution:'Tiles © Esri'}},layers:[{id:'base',type:'raster',source:'base',minzoom:0,maxzoom:24,paint:{'raster-resampling':'linear'}}]}
};
let projects=[],project=null,map=null,presentMap=null,mapStyleKey=localStorage.getItem('trippy_map_style')||'light';
let markers=[],photoMarkers=[],presentMarkers=[],presentPhotoMarkers=[],activeStopId=null,filterStopId=null,activeAssetId=null,activePopup=null,presentStopIndex=0,presentPhotoIndex=-1,presentTimer=null,presentOrbitTimer=null,presentOrbitDelay=null,presentView='trip',presentFocusMarker=null;
const el=id=>document.getElementById(id);
function cloneStyle(key){return JSON.parse(JSON.stringify(MAP_STYLES[key]||MAP_STYLES.light))}
function toast(message){const t=el('toast');t.textContent=message;t.classList.add('show');clearTimeout(t._timer);t._timer=setTimeout(()=>t.classList.remove('show'),4300)}
function esc(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}
function isoDate(v){if(!v)return'';return String(v).slice(0,10)}
function prettyDate(v){if(!v)return'';const d=new Date(String(v).slice(0,10)+'T12:00:00');return Number.isNaN(d.getTime())?String(v).slice(0,10):d.toLocaleDateString(undefined,{month:'short',day:'numeric',year:'numeric'})}
function rangeText(obj){const a=obj?.immich?.start_date||obj?.start_date;const b=obj?.immich?.end_date||obj?.end_date;if(a&&b)return `${isoDate(a)} to ${isoDate(b)}`;return prettyDate(obj?.created)}
function assetDate(value){if(!value)return null;let raw=String(value).trim();if(/^\d{4}:\d{2}:\d{2}/.test(raw))raw=raw.replace(/^(\d{4}):(\d{2}):(\d{2})/,'$1-$2-$3').replace(' ','T');const d=new Date(raw);return Number.isNaN(d.getTime())?null:d}
function formatAssetDateTime(value){const d=assetDate(value);if(!d)return value?String(value):'Date unavailable';const date=d.toLocaleDateString('en-US',{month:'2-digit',day:'2-digit',year:'numeric'}).replaceAll('/','-');const time=d.toLocaleTimeString('en-US',{hour:'numeric',minute:'2-digit'});return `${date} ${time}`}function decimalToDms(value,isLat){const n=Number(value);if(!Number.isFinite(n))return'Coordinate unavailable';const abs=Math.abs(n),deg=Math.floor(abs),minutesFloat=(abs-deg)*60,min=Math.floor(minutesFloat),sec=(minutesFloat-min)*60,hem=isLat?(n>=0?'N':'S'):(n>=0?'E':'W');return `${deg}° ${String(min).padStart(2,'0')}′ ${sec.toFixed(2).padStart(5,'0')}″ ${hem}`}function assetCoordinateText(asset){return `${decimalToDms(asset?.lat,true)}  •  ${decimalToDms(asset?.lon,false)}`}
function stopDateRange(stop){const dates=stopAssets(stop).map(a=>assetDate(a.time)).filter(Boolean).sort((a,b)=>a-b);if(!dates.length)return'Date/time unavailable';const first=dates[0],last=dates[dates.length-1];const fd=first.toLocaleDateString('en-US',{month:'2-digit',day:'2-digit',year:'numeric'}).replaceAll('/','-');const ft=first.toLocaleTimeString('en-US',{hour:'numeric',minute:'2-digit'});const ld=last.toLocaleDateString('en-US',{month:'2-digit',day:'2-digit',year:'numeric'}).replaceAll('/','-');const lt=last.toLocaleTimeString('en-US',{hour:'numeric',minute:'2-digit'});return fd===ld?`${fd} ${ft} – ${lt}`:`${fd} ${ft} – ${ld} ${lt}`}
function validPoint(item){return Number.isFinite(Number(item?.lon))&&Number.isFinite(Number(item?.lat))&&Math.abs(Number(item.lat))<=90&&Math.abs(Number(item.lon))<=180}
function stopBounds(stop){const assets=stopAssets(stop).filter(validPoint);const bounds=new maplibregl.LngLatBounds();assets.forEach(a=>bounds.extend([Number(a.lon),Number(a.lat)]));if(!assets.length&&validPoint(stop))bounds.extend([Number(stop.lon),Number(stop.lat)]);return{bounds,assets}}
function conn(){return{base_url:localStorage.getItem('trippy_immich_url')||'',api_key:localStorage.getItem('trippy_immich_key')||''}}
function saveConn(url,key){localStorage.setItem('trippy_immich_url',url);localStorage.setItem('trippy_immich_key',key)}
async function api(path,options={}){const response=await fetch(path,options);const raw=await response.text();let data;try{data=JSON.parse(raw)}catch{data={detail:raw}}if(!response.ok)throw new Error(data.detail||raw||`HTTP ${response.status}`);return data}
function stopName(stop,index){const raw=(stop?.name||'').trim();return raw&&!/^Stop\s+\d+$/i.test(raw)?raw:`Stop ${index+1}`}
function stopAssets(stop){if(!project||!stop)return[];const ids=new Set(stop.asset_ids||[]);return(project.assets||[]).filter(a=>ids.has(a.asset_id))}
function firstStopAsset(stop){return stopAssets(stop)[0]||null}
function projectSummaryCount(p){return Number(p?.count??p?.assets?.length??0)}
function setModal(id,on=true){el(id).classList.toggle('show',on)}
function initForms(){const c=conn();el('immichUrl').value=c.base_url;el('immichKey').value=c.api_key;el('accountUrl').value=c.base_url;el('accountKey').value=c.api_key;const d=new Date(),s=new Date();s.setDate(s.getDate()-7);el('startDate').value=s.toISOString().slice(0,10);el('endDate').value=d.toISOString().slice(0,10);el('defaultMapSelect').value=mapStyleKey}
async function loadProjects(){projects=await api('/api/projects');renderProjects();if(!project&&projects.length)await openProject(projects[0].id);if(!projects.length)renderAll()}
function renderProjects(){const q=el('projectSearch').value.trim().toLowerCase();const list=projects.filter(p=>!q||(p.name||'').toLowerCase().includes(q));el('projectList').innerHTML=list.map(p=>`<article class="projectCard ${project?.id===p.id?'active':''}" data-id="${esc(p.id)}"><button class="projectMenu" data-menu="${esc(p.id)}">⋮</button><div class="projectCardTitle">${esc(p.name||'Untitled Journey')}</div><div class="projectDate">${esc(rangeText(p)||'')}</div><div class="projectStats"><span class="dot">●</span> ${projectSummaryCount(p)} media&nbsp; • &nbsp;${Number(p.stops||0)} stops</div><button class="projectDelete" data-delete="${esc(p.id)}">Delete</button></article>`).join('')||'<div class="small">No journeys yet.</div>';document.querySelectorAll('.projectCard').forEach(card=>card.addEventListener('click',e=>{if(e.target.closest('button'))return;openProject(card.dataset.id)}));document.querySelectorAll('[data-menu]').forEach(b=>b.addEventListener('click',e=>{e.stopPropagation();b.closest('.projectCard').classList.toggle('menuOpen')}));document.querySelectorAll('[data-delete]').forEach(b=>b.addEventListener('click',e=>{e.stopPropagation();deleteProject(b.dataset.delete)}))}
async function openProject(id){project=await api('/api/project/'+encodeURIComponent(id));activeStopId=project.stops?.[0]?.stop_id||null;filterStopId=activeStopId;activeAssetId=null;renderAll();toast(`Loaded ${project.name||'journey'}`)}
async function deleteProject(id){if(!confirm('Delete this journey and its saved export?'))return;await api('/api/project/'+encodeURIComponent(id),{method:'DELETE'});if(project?.id===id)project=null;projects=projects.filter(p=>p.id!==id);await loadProjects()}
function renderAll(){renderProjects();renderHeader();renderStops();renderGallery();renderMap(true)}
function renderHeader(){if(!project){el('journeyTitle').textContent='No journey selected';el('journeyMeta').textContent='Load or create a journey';return}el('journeyTitle').textContent=project.name||'Untitled Journey';const media=(project.assets||[]).length,stops=(project.stops||[]).length;el('journeyMeta').innerHTML=`<span>◷ ${esc(rangeText(project)||prettyDate(project.created))}</span><span class="liveDot"></span><span>${media} media</span><span>• ${stops} stops</span>`}
function ensureMap(){if(map)return;map=new maplibregl.Map({container:'map',style:cloneStyle(mapStyleKey),center:[-98,39],zoom:3,pitch:0,bearing:0,attributionControl:true});map.addControl(new maplibregl.NavigationControl({showCompass:false}),'bottom-right');map.on('load',()=>renderMap(true));map.on('zoomend',renderSelectedPhotoBubbles);map.on('moveend',renderSelectedPhotoBubbles)}
function clearBubbleMarkers(list){list.forEach(m=>{try{m.remove()}catch{}});list.length=0}
function clearMapMarkers(){clearBubbleMarkers(markers);clearBubbleMarkers(photoMarkers);if(activePopup){try{activePopup.remove()}catch{}activePopup=null}}
function removeLayerAndSource(targetMap,ids,source){ids.forEach(id=>{if(targetMap.getLayer(id))targetMap.removeLayer(id)});if(targetMap.getSource(source))targetMap.removeSource(source)}
function addRouteLayers(targetMap,idPrefix,coords){const source=idPrefix+'-route',glow=idPrefix+'-route-glow',line=idPrefix+'-route-line';removeLayerAndSource(targetMap,[line,glow],source);if(coords.length<2)return;targetMap.addSource(source,{type:'geojson',data:{type:'Feature',geometry:{type:'LineString',coordinates:coords}}});targetMap.addLayer({id:glow,type:'line',source,paint:{'line-color':'#00d8ff','line-width':11,'line-opacity':.20,'line-blur':5}});targetMap.addLayer({id:line,type:'line',source,paint:{'line-color':'#00cfee','line-width':4,'line-opacity':.95}})}
function stopFeatures(){return(project?.stops||[]).filter(validPoint).map((s,i)=>({type:'Feature',geometry:{type:'Point',coordinates:[Number(s.lon),Number(s.lat)]},properties:{stop_id:s.stop_id,index:i+1,name:stopName(s,i)}}))}
function photoFeatures(){return(project?.assets||[]).filter(validPoint).map(a=>({type:'Feature',geometry:{type:'Point',coordinates:[Number(a.lon),Number(a.lat)]},properties:{asset_id:a.asset_id,name:a.name||'Photo',time:a.time||'',stop_id:(project?.stops||[]).find(s=>(s.asset_ids||[]).includes(a.asset_id))?.stop_id||''}}))}
function addClusterLayers(targetMap,prefix){const stopSource=prefix+'-stops',photoSource=prefix+'-photos';removeLayerAndSource(targetMap,[prefix+'-stop-cluster-count',prefix+'-stop-clusters',prefix+'-stop-number',prefix+'-stop-points'],stopSource);removeLayerAndSource(targetMap,[prefix+'-photo-cluster-count',prefix+'-photo-clusters',prefix+'-photo-points'],photoSource);targetMap.addSource(stopSource,{type:'geojson',cluster:true,clusterRadius:48,clusterMaxZoom:9,data:{type:'FeatureCollection',features:stopFeatures()}});targetMap.addLayer({id:prefix+'-stop-clusters',type:'circle',source:stopSource,filter:['has','point_count'],paint:{'circle-radius':['step',['get','point_count'],20,10,25,40,31],'circle-color':'#07131f','circle-stroke-color':'#00d8ff','circle-stroke-width':3,'circle-opacity':.94}});targetMap.addLayer({id:prefix+'-stop-cluster-count',type:'symbol',source:stopSource,filter:['has','point_count'],layout:{'text-field':['get','point_count_abbreviated'],'text-size':12},paint:{'text-color':'#ffffff'}});targetMap.addLayer({id:prefix+'-stop-points',type:'circle',source:stopSource,filter:['!',['has','point_count']],paint:{'circle-radius':17,'circle-color':'#07131f','circle-stroke-color':'#00d8ff','circle-stroke-width':3,'circle-opacity':.95}});targetMap.addLayer({id:prefix+'-stop-number',type:'symbol',source:stopSource,filter:['!',['has','point_count']],layout:{'text-field':['to-string',['get','index']],'text-size':11},paint:{'text-color':'#ffffff'}});targetMap.addSource(photoSource,{type:'geojson',cluster:true,clusterRadius:42,clusterMaxZoom:13,data:{type:'FeatureCollection',features:photoFeatures()}});targetMap.addLayer({id:prefix+'-photo-clusters',type:'circle',source:photoSource,filter:['has','point_count'],minzoom:8,paint:{'circle-radius':['step',['get','point_count'],15,8,19,25,24],'circle-color':'#0a2332','circle-stroke-color':'#7deaff','circle-stroke-width':2,'circle-opacity':.88}});targetMap.addLayer({id:prefix+'-photo-cluster-count',type:'symbol',source:photoSource,filter:['has','point_count'],minzoom:8,layout:{'text-field':['get','point_count_abbreviated'],'text-size':10},paint:{'text-color':'#ffffff'}});targetMap.addLayer({id:prefix+'-photo-points',type:'circle',source:photoSource,filter:['!',['has','point_count']],minzoom:11,paint:{'circle-radius':['interpolate',['linear'],['zoom'],11,4,15,7],'circle-color':'#00d8ff','circle-stroke-color':'#ffffff','circle-stroke-width':1.5,'circle-opacity':['interpolate',['linear'],['zoom'],11,.65,14,.9,15,0]}})}
function expandCluster(targetMap,sourceId,feature){const source=targetMap.getSource(sourceId);if(!source)return;const clusterId=feature.properties.cluster_id;const result=source.getClusterExpansionZoom(clusterId);if(result&&typeof result.then==='function')result.then(zoom=>targetMap.easeTo({center:feature.geometry.coordinates,zoom,duration:700}));else source.getClusterExpansionZoom(clusterId,(err,zoom)=>{if(!err)targetMap.easeTo({center:feature.geometry.coordinates,zoom,duration:700})})}
function bindMapInteractions(targetMap,prefix,isPresent=false){const key='__trippy_'+prefix;if(targetMap[key])return;targetMap[key]=true;targetMap.on('click',prefix+'-stop-clusters',e=>expandCluster(targetMap,prefix+'-stops',e.features[0]));targetMap.on('click',prefix+'-photo-clusters',e=>expandCluster(targetMap,prefix+'-photos',e.features[0]));targetMap.on('click',prefix+'-stop-points',e=>{const id=e.features?.[0]?.properties?.stop_id;if(id){const i=(project?.stops||[]).findIndex(s=>s.stop_id===id);isPresent?goPresentStop(i):selectStop(id,{fly:true,popup:true,filter:true})}});targetMap.on('click',prefix+'-stop-number',e=>{const id=e.features?.[0]?.properties?.stop_id;if(id){const i=(project?.stops||[]).findIndex(s=>s.stop_id===id);isPresent?goPresentStop(i):selectStop(id,{fly:true,popup:true,filter:true})}});targetMap.on('click',prefix+'-photo-points',e=>{const id=e.features?.[0]?.properties?.asset_id;if(id){if(isPresent){const i=presentAssets().findIndex(a=>a.asset_id===id);if(i>=0)goPresentPhoto(i)}else focusAsset(id)}});[prefix+'-stop-clusters',prefix+'-stop-points',prefix+'-stop-number',prefix+'-photo-clusters',prefix+'-photo-points'].forEach(layer=>{targetMap.on('mouseenter',layer,()=>targetMap.getCanvas().style.cursor='pointer');targetMap.on('mouseleave',layer,()=>targetMap.getCanvas().style.cursor='')})}
function assetBubbleElement(asset,active=false){const node=document.createElement('div');node.className='assetBubble'+(active?' active':'');node.title=formatAssetDateTime(asset.time);node.innerHTML=asset.thumb?`<img src="${esc(asset.thumb)}" alt="">`:'<div class="assetDot">•</div>';return node}
function renderSelectedPhotoBubbles(){clearBubbleMarkers(photoMarkers);if(!map||map.getZoom()<13.5||!activeStopId)return;const stop=project?.stops?.find(s=>s.stop_id===activeStopId);stopAssets(stop).filter(validPoint).slice(0,120).forEach(asset=>{const node=assetBubbleElement(asset,asset.asset_id===activeAssetId);node.onclick=()=>focusAsset(asset.asset_id);photoMarkers.push(new maplibregl.Marker({element:node,anchor:'center'}).setLngLat([Number(asset.lon),Number(asset.lat)]).addTo(map))})}
function renderMap(fit=false){ensureMap();if(!map.isStyleLoaded()){map.once('load',()=>renderMap(fit));return}clearMapMarkers();const stops=project?.stops||[];if(!stops.length)return;addRouteLayers(map,'main',stops.filter(validPoint).map(s=>[Number(s.lon),Number(s.lat)]));addClusterLayers(map,'main');bindMapInteractions(map,'main',false);const bounds=new maplibregl.LngLatBounds();stops.filter(validPoint).forEach(s=>bounds.extend([Number(s.lon),Number(s.lat)]));if(fit&&!bounds.isEmpty()){try{map.fitBounds(bounds,{padding:{top:85,bottom:90,left:95,right:95},maxZoom:14.8,duration:850})}catch{}}setTimeout(renderSelectedPhotoBubbles,80)}
function setMapStyle(key){if(!MAP_STYLES[key])return;mapStyleKey=key;localStorage.setItem('trippy_map_style',key);['light','dark','satellite'].forEach(k=>el(k+'MapButton').classList.toggle('active',k===key));el('defaultMapSelect').value=key;if(map){map.setStyle(cloneStyle(key));map.once('style.load',()=>renderMap(false))}}
function bearing(a,b){const y=Math.sin((b.lon-a.lon)*Math.PI/180)*Math.cos(b.lat*Math.PI/180);const x=Math.cos(a.lat*Math.PI/180)*Math.sin(b.lat*Math.PI/180)-Math.sin(a.lat*Math.PI/180)*Math.cos(b.lat*Math.PI/180)*Math.cos((b.lon-a.lon)*Math.PI/180);return(Math.atan2(y,x)*180/Math.PI+360)%360}
function selectStop(id,{fly=true,popup=true,filter=true}={}){if(!project)return;const index=(project.stops||[]).findIndex(s=>s.stop_id===id);if(index<0)return;const stop=project.stops[index];activeStopId=id;if(filter)filterStopId=id;renderStops();renderGallery();renderMap(false);if(fly&&map){const next=project.stops[Math.min(index+1,project.stops.length-1)]||stop;map.flyTo({center:[stop.lon,stop.lat],zoom:15.7,pitch:42,bearing:bearing(stop,next),duration:1050,essential:true})}if(popup)setTimeout(()=>showStopPopup(stop,index),450)}
function showStopPopup(stop,index){if(activePopup){try{activePopup.remove()}catch{}}const assets=stopAssets(stop),first=assets[0];const content=`<div class="stopPopup"><div class="stopPopupImage">${first?.thumb?`<img src="${esc(first.thumb)}">`:''}</div><div class="stopPopupBody"><span class="popupKicker">Stop ${index+1}</span><div class="popupTitle">${esc(stopName(stop,index))}</div><div class="popupMeta">${assets.length} photos&nbsp; • &nbsp;${Math.round(stop.radius_m||200)} m radius</div><div class="popupButtons"><button data-popup-filter="${esc(stop.stop_id)}">View Photos</button><button data-popup-present="${index}">▶ Present</button><button class="danger" data-popup-delete="${esc(stop.stop_id)}">⌫</button></div></div></div>`;activePopup=new maplibregl.Popup({offset:24,closeButton:true,maxWidth:'350px'}).setLngLat([stop.lon,stop.lat]).setHTML(content).addTo(map);setTimeout(()=>{document.querySelector('[data-popup-filter]')?.addEventListener('click',()=>{filterStopId=stop.stop_id;renderGallery()});document.querySelector('[data-popup-present]')?.addEventListener('click',()=>openPresent(index));document.querySelector('[data-popup-delete]')?.addEventListener('click',()=>deleteStop(stop.stop_id))},0)}
function renderStops(){const stops=project?.stops||[],q=el('stopSearch').value.trim().toLowerCase();el('stopCount').textContent=`(${stops.length})`;el('stopList').innerHTML=stops.map((s,i)=>({s,i})).filter(x=>!q||stopName(x.s,x.i).toLowerCase().includes(q)).map(({s,i})=>{const count=(s.asset_ids||[]).length,active=s.stop_id===activeStopId;return`<article class="stopCard ${active?'active open':''}" data-stop="${esc(s.stop_id)}"><div class="stopSummary"><div class="stopNumber">${i+1}</div><div><div class="stopName">${esc(stopName(s,i))}</div><div class="stopMeta">${count} photos&nbsp; • &nbsp;${esc(stopDateRange(s))}</div></div><div class="stopChevron">›</div></div><div class="stopControls"><button data-view="${esc(s.stop_id)}">View</button><button data-rename="${esc(s.stop_id)}">Rename</button><button data-recenter="${esc(s.stop_id)}">Recenter</button><button data-delete-stop="${esc(s.stop_id)}">Delete</button></div></article>`}).join('')||'<div class="small">No stops found.</div>';document.querySelectorAll('.stopSummary').forEach(row=>row.addEventListener('click',()=>{const card=row.closest('.stopCard');const id=card.dataset.stop;if(activeStopId===id)card.classList.toggle('open');else selectStop(id,{fly:true,popup:true,filter:true})}));document.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>selectStop(b.dataset.view,{fly:true,popup:true,filter:true})));document.querySelectorAll('[data-rename]').forEach(b=>b.addEventListener('click',()=>renameStop(b.dataset.rename)));document.querySelectorAll('[data-recenter]').forEach(b=>b.addEventListener('click',()=>recenterStop(b.dataset.recenter)));document.querySelectorAll('[data-delete-stop]').forEach(b=>b.addEventListener('click',()=>deleteStop(b.dataset.deleteStop)))}
function galleryAssets(){if(!project)return[];if(filterStopId){const stop=project.stops.find(s=>s.stop_id===filterStopId);return stopAssets(stop)}return project.assets||[]}
function renderGallery(){const assets=galleryAssets(),stop=project?.stops?.find(s=>s.stop_id===filterStopId),idx=stop?project.stops.indexOf(stop):-1;el('mediaTitle').textContent=stop?`Stop ${idx+1}  •  ${stopName(stop,idx)}`:'Media';el('mediaCount').textContent=`${assets.length} items`;el('filterChip').classList.toggle('show',!!stop);el('filterChipText').textContent=stop?`Filter: ${stopName(stop,idx)}`:'Filter: All Stops';el('gallery').innerHTML=assets.map((a,i)=>`<div class="mediaTile ${a.asset_id===activeAssetId?'active':''}" data-asset="${esc(a.asset_id)}">${a.thumb?`<img src="${esc(a.thumb)}">`:''}<button class="mediaTileRemove" data-remove-asset="${esc(a.asset_id)}" title="Remove from journey">×</button><div class="mediaTileName">${esc(formatAssetDateTime(a.time)||`Photo ${i+1}`)}</div></div>`).join('')||'<div class="small">No GPS media in this view.</div>';document.querySelectorAll('.mediaTile').forEach(tile=>tile.addEventListener('click',()=>focusAsset(tile.dataset.asset)));document.querySelectorAll('[data-remove-asset]').forEach(button=>button.addEventListener('click',event=>{event.stopPropagation();removeAssetFromJourney(button.dataset.removeAsset)}))}
function focusAsset(id){const asset=(project?.assets||[]).find(a=>a.asset_id===id);if(!asset||!validPoint(asset))return;activeAssetId=id;renderGallery();renderSelectedPhotoBubbles();if(map)map.flyTo({center:[Number(asset.lon),Number(asset.lat)],zoom:18.7,pitch:50,bearing:10,duration:950,essential:true});if(activePopup){try{activePopup.remove()}catch{}}activePopup=new maplibregl.Popup({offset:24,closeButton:true,maxWidth:'420px'}).setLngLat([Number(asset.lon),Number(asset.lat)]).setHTML(`<div class="stopPopup"><div class="stopPopupImage">${asset.thumb?`<img src="${esc(asset.thumb)}">`:''}</div><div class="stopPopupBody"><span class="popupKicker">Selected photo</span><div class="popupTitle">${esc(asset.name||'Photo')}</div><div class="popupMeta">${esc(formatAssetDateTime(asset.time))}</div></div></div>`).addTo(map)}
async function saveProject(){if(!project)return;project=await api('/api/project/'+encodeURIComponent(project.id),{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(project)});await refreshProjectSummary();renderAll()}async function removeAssetFromJourney(assetId){if(!project)return;const asset=(project.assets||[]).find(a=>a.asset_id===assetId);if(!asset)return;if(!confirm('Remove this image from this Trippy journey? The original file will remain untouched in Immich.'))return;project.assets=(project.assets||[]).filter(a=>a.asset_id!==assetId);project.stops=(project.stops||[]).map(stop=>{const ids=(stop.asset_ids||[]).filter(id=>id!==assetId);if(!ids.length)return null;const points=project.assets.filter(a=>ids.includes(a.asset_id)&&validPoint(a));if(points.length){stop.lat=points.reduce((sum,a)=>sum+Number(a.lat),0)/points.length;stop.lon=points.reduce((sum,a)=>sum+Number(a.lon),0)/points.length}stop.asset_ids=ids;return stop}).filter(Boolean);activeAssetId=null;if(filterStopId&&!project.stops.some(s=>s.stop_id===filterStopId))filterStopId=null;await saveProject();toast('Removed from this journey. The original remains in Immich.');if(el('presentOverlay').classList.contains('show')){if(!project.stops.length){closePresent();return}presentStopIndex=Math.min(presentStopIndex,project.stops.length-1);const assets=presentAssets();presentPhotoIndex=Math.min(presentPhotoIndex,assets.length-1);renderPresentMapLayers();if(presentPhotoIndex>=0&&assets.length)goPresentPhoto(presentPhotoIndex);else goPresentStop(presentStopIndex)}}
async function refreshProjectSummary(){projects=await api('/api/projects')}
async function renameProject(){if(!project)return;const value=prompt('Journey name',project.name||'');if(!value?.trim())return;project.name=value.trim();project.settings=project.settings||{};project.settings.title=project.name;await saveProject()}
async function renameStop(id){const i=project.stops.findIndex(s=>s.stop_id===id);if(i<0)return;const value=prompt('Stop name',stopName(project.stops[i],i));if(!value?.trim())return;project.stops[i].name=value.trim();await saveProject()}
async function recenterStop(id){const stop=project.stops.find(s=>s.stop_id===id),assets=stopAssets(stop);if(!stop||!assets.length)return toast('This stop has no photos to recenter from.');stop.lat=assets.reduce((n,a)=>n+Number(a.lat),0)/assets.length;stop.lon=assets.reduce((n,a)=>n+Number(a.lon),0)/assets.length;await saveProject();selectStop(id,{fly:true,popup:true,filter:true})}
async function deleteStop(id){if(!confirm('Delete this stop? Photos remain in the journey.'))return;project.stops=project.stops.filter(s=>s.stop_id!==id);if(activeStopId===id)activeStopId=project.stops[0]?.stop_id||null;if(filterStopId===id)filterStopId=activeStopId;await saveProject()}
async function addStop(){if(!project||!map)return toast('Load a journey first.');const center=map.getCenter();project.stops=project.stops||[];const stop={stop_id:crypto.randomUUID().slice(0,8),name:`Stop ${project.stops.length+1}`,lat:center.lat,lon:center.lng,radius_m:Number(project.settings?.stop_radius_m||200),asset_ids:[],mode:'manual',locked:false};project.stops.push(stop);await saveProject();selectStop(stop.stop_id,{fly:true,popup:true,filter:true})}
async function recluster(){if(!project)return;const radius=Number(el('stopRadius').value||200);project=await api('/api/project/'+encodeURIComponent(project.id)+'/recluster',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({radius_m:radius})});project.settings=project.settings||{};project.settings.stop_radius_m=radius;activeStopId=project.stops[0]?.stop_id||null;filterStopId=activeStopId;await refreshProjectSummary();renderAll();setModal('settingsModal',false);toast('Stops reclustered')}
async function reverseRoute(){if(!project)return;project.stops.reverse();project.settings=project.settings||{};project.settings.reverse_route=!project.settings.reverse_route;await saveProject();toast('Route order reversed')}
async function testImmich(){const body={base_url:el('immichUrl').value.trim(),api_key:el('immichKey').value.trim()};const result=await api('/api/immich/test',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});toast(result.message||'Connection tested')}
async function createImmichJourney(){const base_url=el('immichUrl').value.trim(),api_key=el('immichKey').value.trim(),start_date=el('startDate').value,end_date=el('endDate').value;if(!base_url||!api_key||!start_date||!end_date)return toast('Complete the Immich URL, key, and dates.');saveConn(base_url,api_key);toast('Importing GPS media from Immich…');const created=await api('/api/project/immich',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:`Immich Journey ${start_date} to ${end_date}`,base_url,api_key,start_date,end_date})});setModal('immichModal',false);await refreshProjectSummary();await openProject(created.id)}
async function createUploadJourney(){const files=el('uploadFiles').files;if(!files.length)return toast('Choose media files first.');const form=new FormData();for(const file of files)form.append('files',file);form.append('name',el('uploadName').value.trim()||'Uploaded Journey');toast('Reading GPS metadata…');const created=await api('/api/project/upload',{method:'POST',body:form});setModal('uploadModal',false);await refreshProjectSummary();await openProject(created.id)}
async function renderMp4(){if(!project)return toast('Load a journey first.');project.settings=project.settings||{};project.settings.duration_min=12;await api('/api/project/'+encodeURIComponent(project.id),{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(project)});const form=new FormData();if(el('audioSwitch').classList.contains('on')&&el('audioInput').files[0])form.append('audio',el('audioInput').files[0]);toast('Rendering MP4…');const result=await api('/api/project/'+encodeURIComponent(project.id)+'/render',{method:'POST',body:form});const url=result.url||result.path||result.download_url;if(url)window.open(url,'_blank');toast('Render complete')}
function ensurePresentMap(){if(presentMap)return;presentMap=new maplibregl.Map({container:'presentMap',style:cloneStyle(mapStyleKey==='light'?'satellite':mapStyleKey),center:[-98,39],zoom:3,maxZoom:20,pitch:55,bearing:0});presentMap.addControl(new maplibregl.NavigationControl(),'bottom-right');presentMap.on('zoomend',renderPresentPhotoBubbles);presentMap.on('moveend',renderPresentPhotoBubbles);presentMap.on('error',event=>{const message=String(event?.error?.message||'');if(mapStyleKey==='satellite'&&/tile|source|404|403/i.test(message)){toast('Satellite imagery is limited here; using the closest available tile.')}})}
function presentAssets(){const stop=project?.stops?.[presentStopIndex];return stopAssets(stop)}
function renderPresentStops(){const stops=project?.stops||[];el('presentStopRail').innerHTML=`<div style="font-weight:950;margin:2px 4px 10px">Journey Stops</div>`+stops.map((s,i)=>`<div class="presentStopItem ${i===presentStopIndex?'active':''}" data-present-stop="${i}"><b>${i+1}.</b>&nbsp; ${esc(stopName(s,i))}<div class="small">${(s.asset_ids||[]).length} photos<br>${esc(stopDateRange(s))}</div></div>`).join('');document.querySelectorAll('[data-present-stop]').forEach(x=>x.addEventListener('click',()=>goPresentStop(Number(x.dataset.presentStop))))}
function renderPresentFilmstrip(){const assets=presentAssets();el('presentFilmstrip').innerHTML=assets.map((a,i)=>`<div class="presentThumb ${i===presentPhotoIndex?'active':''}" data-present-photo="${i}">${a.thumb?`<img src="${esc(a.thumb)}">`:''}<div class="presentThumbLabel">Photo ${i+1}<br>${esc(formatAssetDateTime(a.time))}</div></div>`).join('')||'<div class="small">No photos assigned to this stop.</div>';document.querySelectorAll('[data-present-photo]').forEach(x=>x.addEventListener('click',()=>goPresentPhoto(Number(x.dataset.presentPhoto))))}
function renderPresentMapLayers(){if(!presentMap||!presentMap.isStyleLoaded())return;clearBubbleMarkers(presentMarkers);clearBubbleMarkers(presentPhotoMarkers);const stops=project?.stops||[];addRouteLayers(presentMap,'present',stops.filter(validPoint).map(s=>[Number(s.lon),Number(s.lat)]));addClusterLayers(presentMap,'present');bindMapInteractions(presentMap,'present',true);renderPresentPhotoBubbles()}
function renderPresentPhotoBubbles(){clearBubbleMarkers(presentPhotoMarkers);if(!presentMap||!project?.stops?.length)return;const all=presentAssets();all.filter(validPoint).slice(0,140).forEach(asset=>{const i=all.findIndex(a=>a.asset_id===asset.asset_id);const node=assetBubbleElement(asset,i===presentPhotoIndex);node.onclick=()=>goPresentPhoto(i);presentPhotoMarkers.push(new maplibregl.Marker({element:node,anchor:'center'}).setLngLat([Number(asset.lon),Number(asset.lat)]).addTo(presentMap))})}function stopPresentOrbit(){clearTimeout(presentOrbitDelay);clearInterval(presentOrbitTimer);presentOrbitDelay=null;presentOrbitTimer=null}function startPresentOrbit(center,zoom,pitch=56){stopPresentOrbit();const orbit=()=>{if(!presentMap||!el('presentOverlay').classList.contains('show'))return;presentMap.easeTo({center,zoom:Math.min(zoom,18.15),pitch,bearing:(presentMap.getBearing()+16)%360,duration:5200,easing:t=>t,essential:true})};presentOrbitDelay=setTimeout(()=>{orbit();presentOrbitTimer=setInterval(orbit,5250)},1250)}function clearPresentFocus(){if(presentFocusMarker){presentFocusMarker.remove();presentFocusMarker=null}}function showPresentFocus(item){clearPresentFocus();if(!validPoint(item)||!presentMap)return;const node=document.createElement('div');node.className='focusPulse';presentFocusMarker=new maplibregl.Marker({element:node,anchor:'center'}).setLngLat([Number(item.lon),Number(item.lat)]).addTo(presentMap)}function tripBounds(){const bounds=new maplibregl.LngLatBounds();(project?.stops||[]).filter(validPoint).forEach(s=>bounds.extend([Number(s.lon),Number(s.lat)]));return bounds}function centerPresentTrip(){if(!presentMap||!project?.stops?.length)return;stopPresentOrbit();presentView='trip';const bounds=tripBounds();if(!bounds.isEmpty())presentMap.fitBounds(bounds,{padding:{top:110,bottom:110,left:285,right:80},maxZoom:12.8,duration:1500,essential:true});const selected=presentPhotoIndex>=0?presentAssets()[presentPhotoIndex]:project.stops[presentStopIndex];showPresentFocus(selected);el('presentStopBannerTitle').textContent=project.name||'Journey Overview';el('presentStopBannerRange').textContent=`${project.stops.length} stops  •  ${(project.assets||[]).length} photos`;el('presentPhotoCard').classList.remove('show')}function presentBack(){if(presentView==='photo'){goPresentStop(presentStopIndex);return}if(presentView==='stop'){centerPresentTrip();return}centerPresentTrip()}function returnPresentStart(){presentStopIndex=0;presentPhotoIndex=-1;goPresentStop(0)}
function goPresentStop(index){const stops=project?.stops||[];if(!stops.length)return;stopPresentOrbit();clearPresentFocus();presentView='stop';presentStopIndex=(index+stops.length)%stops.length;presentPhotoIndex=-1;const stop=stops[presentStopIndex],next=stops[(presentStopIndex+1)%stops.length]||stop;renderPresentStops();renderPresentFilmstrip();renderPresentPhotoBubbles();const range=stopDateRange(stop);el('presentHeaderTitle').textContent=stopName(stop,presentStopIndex);el('presentHeaderMeta').textContent=`Stop ${presentStopIndex+1} of ${stops.length} • ${(stop.asset_ids||[]).length} photos • ${range}`;el('presentStopBannerTitle').textContent=stopName(stop,presentStopIndex);el('presentStopBannerRange').textContent=`Stop ${presentStopIndex+1} of ${stops.length}  •  ${range}  •  ${(stop.asset_ids||[]).length} photos`;el('presentPhotoCard').classList.remove('show');showPresentFocus(stop);const data=stopBounds(stop),center=validPoint(stop)?[Number(stop.lon),Number(stop.lat)]:data.assets.length?[Number(data.assets[0].lon),Number(data.assets[0].lat)]:null;if(data.assets.length>1&&!data.bounds.isEmpty()){presentMap.fitBounds(data.bounds,{padding:{top:130,bottom:200,left:285,right:430},maxZoom:16.15,duration:1700,essential:true});setTimeout(()=>{presentMap.easeTo({pitch:58,bearing:bearing(stop,next),duration:700,essential:true});if(center)startPresentOrbit(center,Math.min(presentMap.getZoom(),16.15),58)},950)}else if(center){presentMap.flyTo({center,zoom:16,pitch:58,bearing:bearing(stop,next),duration:1600,curve:1.45,essential:true});startPresentOrbit(center,16,58)}}
function goPresentPhoto(index){const assets=presentAssets();if(!assets.length)return;stopPresentOrbit();presentView='photo';presentPhotoIndex=(index+assets.length)%assets.length;const asset=assets[presentPhotoIndex];if(!validPoint(asset))return;renderPresentFilmstrip();renderPresentPhotoBubbles();showPresentFocus(asset);el('presentStopBannerTitle').textContent=stopName(project.stops[presentStopIndex],presentStopIndex);el('presentStopBannerRange').textContent=`Photo ${presentPhotoIndex+1} of ${assets.length}  •  ${formatAssetDateTime(asset.time)}`;el('presentPhotoCard').innerHTML=`${asset.preview||asset.thumb?`<img src="${esc(asset.preview||asset.thumb)}">`:''}<div class="presentPhotoBody"><div class="presentPhotoTitle">Photo ${presentPhotoIndex+1} of ${assets.length}</div><div class="presentPhotoMeta">${esc(formatAssetDateTime(asset.time))}</div><div class="presentPhotoCoords">${esc(assetCoordinateText(asset))}</div><div class="presentPhotoActions"><button onclick="goPresentStop(presentStopIndex)">Back to Stop</button><button class="danger" onclick="removeAssetFromJourney('${esc(asset.asset_id)}')">Remove from Journey</button></div></div>`;el('presentPhotoCard').classList.add('show');const center=[Number(asset.lon),Number(asset.lat)],zoom=17.65;presentMap.flyTo({center,zoom,pitch:50,bearing:(presentPhotoIndex*17)%360,duration:1350,curve:1.3,essential:true});startPresentOrbit(center,zoom,50)}
function openPresent(index=0){if(!project?.stops?.length)return toast('Load a journey with stops first.');el('presentOverlay').classList.add('show');ensurePresentMap();setTimeout(()=>{presentMap.resize();if(presentMap.isStyleLoaded()){renderPresentMapLayers();goPresentStop(index)}else presentMap.once('load',()=>{renderPresentMapLayers();goPresentStop(index)})},90)}
function closePresent(){clearInterval(presentTimer);presentTimer=null;stopPresentOrbit();clearPresentFocus();el('playJourneyButton').textContent='▶ Play';el('presentOverlay').classList.remove('show')}
function togglePlay(){if(presentTimer){clearInterval(presentTimer);presentTimer=null;el('playJourneyButton').textContent='▶ Play';return}el('playJourneyButton').textContent='Ⅱ Pause';presentTimer=setInterval(()=>{const assets=presentAssets();if(assets.length&&presentPhotoIndex<assets.length-1)goPresentPhoto(presentPhotoIndex+1);else goPresentStop(presentStopIndex+1)},4300)}
function downloadGpx(){if(!project)return;const points=(project.stops||[]).map((s,i)=>`<wpt lat="${s.lat}" lon="${s.lon}"><name>${esc(stopName(s,i))}</name></wpt>`).join('');const gpx=`<?xml version="1.0"?><gpx version="1.1" creator="Trippy">${points}</gpx>`;const blob=new Blob([gpx],{type:'application/gpx+xml'}),a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=(project.name||'trippy')+'.gpx';a.click();URL.revokeObjectURL(a.href)}
function bind(){el('newImmichButton').onclick=()=>setModal('immichModal');el('uploadButton').onclick=()=>setModal('uploadModal');document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>setModal(b.dataset.close,false));el('projectSearchButton').onclick=()=>el('projectSearch').classList.toggle('hidden');el('projectSearch').oninput=renderProjects;el('renameProjectButton').onclick=renameProject;el('presentButton').onclick=()=>openPresent(0);el('exportJumpButton').onclick=()=>{el('exportBox').classList.remove('collapsed');el('exportBox').scrollIntoView({behavior:'smooth',block:'end'})};el('settingsButton').onclick=()=>{el('stopRadius').value=project?.settings?.stop_radius_m||200;setModal('settingsModal')};el('accountButton').onclick=()=>setModal('accountModal');el('saveAccountButton').onclick=()=>{saveConn(el('accountUrl').value.trim(),el('accountKey').value.trim());toast('Immich connection saved');setModal('accountModal',false)};el('testImmichButton').onclick=()=>testImmich().catch(e=>toast(e.message));el('createJourneyButton').onclick=()=>createImmichJourney().catch(e=>toast(e.message));el('createUploadButton').onclick=()=>createUploadJourney().catch(e=>toast(e.message));el('stopSearchButton').onclick=()=>el('stopSearchWrap').classList.toggle('show');el('stopSearch').oninput=renderStops;el('addStopButton').onclick=addStop;el('exportHeader').onclick=()=>el('exportBox').classList.toggle('collapsed');el('audioSwitch').onclick=()=>{el('audioSwitch').classList.toggle('on');if(el('audioSwitch').classList.contains('on'))el('audioInput').click()};el('renderButton').onclick=()=>renderMp4().catch(e=>toast(e.message));el('gpxButton').onclick=downloadGpx;el('imageSetButton').onclick=()=>toast('Image Set export is coming next.');el('clearFilterButton').onclick=()=>{filterStopId=null;activeStopId=null;renderGallery();renderStops();renderMap(false)};el('locateButton').onclick=()=>navigator.geolocation?.getCurrentPosition(p=>map.flyTo({center:[p.coords.longitude,p.coords.latitude],zoom:15,duration:900}),()=>toast('Location unavailable'));el('zoomInButton').onclick=()=>map?.zoomIn();el('zoomOutButton').onclick=()=>map?.zoomOut();el('lightMapButton').onclick=()=>setMapStyle('light');el('darkMapButton').onclick=()=>setMapStyle('dark');el('satelliteMapButton').onclick=()=>setMapStyle('satellite');el('defaultMapSelect').onchange=e=>setMapStyle(e.target.value);el('reclusterButton').onclick=()=>recluster().catch(e=>toast(e.message));el('reverseRouteButton').onclick=()=>reverseRoute().catch(e=>toast(e.message));el('closePresentButton').onclick=closePresent;el('presentBackButton').onclick=presentBack;el('centerTripButton').onclick=centerPresentTrip;el('returnStartButton').onclick=returnPresentStart;el('previousStopButton').onclick=()=>goPresentStop(presentStopIndex-1);el('nextStopButton').onclick=()=>goPresentStop(presentStopIndex+1);el('previousPhotoButton').onclick=()=>{const a=presentAssets();if(a.length)goPresentPhoto(presentPhotoIndex<0?a.length-1:presentPhotoIndex-1)};el('nextPhotoButton').onclick=()=>{const a=presentAssets();if(a.length)goPresentPhoto(presentPhotoIndex+1)};el('playJourneyButton').onclick=togglePlay}
initForms();bind();ensureMap();setMapStyle(mapStyleKey);loadProjects().catch(e=>toast(e.message));
</script>
<script id="TRIPPY_V103_SCRIPT">
/* Trippy v10.3.1 — Day / Segment journey model */
var v103SelectedStops=new Set();
var v103SelectMode=false;
var v103ActiveSegmentId=null;
var v103OpenDays=new Set();
var v103PoiBusy=false;
var v103PoiAttempted=new Set();
var v103PresentFlatIndex=0;
var v103PresentDayKey=null;
var v103PresentItem=null;
var v103BaseSelectStop=selectStop;
var v103BaseFocusAsset=focusAsset;
var v103PoiCache=(function(){try{return JSON.parse(localStorage.getItem('trippy_poi_cache_v1')||'{}')}catch{return{}}})();

function v103EnsureModel(){
  if(!project)return;
  project.settings=project.settings||{};
  project.settings.day_titles=project.settings.day_titles||{};
  project.settings.segments=Array.isArray(project.settings.segments)?project.settings.segments:[];
  const ids=new Set((project.stops||[]).map(s=>s.stop_id));
  project.settings.segments=project.settings.segments.map(seg=>({...seg,member_stop_ids:(seg.member_stop_ids||[]).filter(id=>ids.has(id))})).filter(seg=>seg.member_stop_ids.length>1);
}
function v103Segments(){v103EnsureModel();return project?.settings?.segments||[]}
function v103StopById(id){return(project?.stops||[]).find(s=>s.stop_id===id)}
function v103StopIndex(id){return(project?.stops||[]).findIndex(s=>s.stop_id===id)}
function v103DateKey(value){const d=assetDate(value);if(!d)return'undated';return`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`}
function v103StopDayKey(stop){if(stop?.manual_day)return stop.manual_day;const dates=stopAssets(stop).map(a=>assetDate(a.time)).filter(Boolean).sort((a,b)=>a-b);return dates.length?v103DateKey(dates[0]):'undated'}
function v103DayDate(key){return key==='undated'?null:new Date(key+'T12:00:00')}
function v103DayTitle(key,index){const custom=project?.settings?.day_titles?.[key];if(custom)return custom;const d=v103DayDate(key);return d?`Day ${index+1} · ${d.toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric',year:'numeric'})}`:`Day ${index+1} · Date unavailable`}
function v103SegmentMembers(seg){return(seg?.member_stop_ids||[]).map(v103StopById).filter(Boolean)}
function v103SegmentAssets(seg){const ids=new Set(v103SegmentMembers(seg).flatMap(s=>s.asset_ids||[]));return(project?.assets||[]).filter(a=>ids.has(a.asset_id))}
function v103ItemAssets(item){return item?.type==='segment'?v103SegmentAssets(item.segment):stopAssets(item?.stop)}
function v103ItemStops(item){return item?.type==='segment'?v103SegmentMembers(item.segment):item?.stop?[item.stop]:[]}
function v103SegmentName(seg){
  if(seg?.name?.trim())return seg.name.trim();
  const members=v103SegmentMembers(seg),names=members.map((s)=>stopName(s,v103StopIndex(s.stop_id))).filter(Boolean);
  const type=seg?.type||'custom';
  if(type==='drive'){
    const road=names.find(n=>/\b(US-|I-|Hwy|Highway|Road|Route|Drive|Scenic)\b/i.test(n));
    if(road)return /drive/i.test(road)?road:`${road} Drive`;
    if(names.length>1)return`${names[0]} to ${names[names.length-1]}`;
    return'Scenic Drive';
  }
  if(type==='hike'){
    const trail=names.find(n=>/trail|hike|path/i.test(n));
    if(trail)return /hike/i.test(trail)?trail:`${trail} Hike`;
    return names[0]?`${names[0]} Hike`:'Hiking Segment';
  }
  return names.length>1?`${names[0]} to ${names[names.length-1]}`:'Combined Segment';
}
function v103ItemName(item){return item?.type==='segment'?v103SegmentName(item.segment):stopName(item.stop,v103StopIndex(item.stop.stop_id))}
function v103ItemId(item){return item?.type==='segment'?`segment:${item.segment.id}`:`stop:${item.stop.stop_id}`}
function v103ItemRange(item){const assets=v103ItemAssets(item).map(a=>assetDate(a.time)).filter(Boolean).sort((a,b)=>a-b);if(!assets.length)return'Date/time unavailable';const a=assets[0],b=assets[assets.length-1],fd=a.toLocaleDateString('en-US',{month:'2-digit',day:'2-digit',year:'numeric'}).replaceAll('/','-'),ld=b.toLocaleDateString('en-US',{month:'2-digit',day:'2-digit',year:'numeric'}).replaceAll('/','-'),ft=a.toLocaleTimeString('en-US',{hour:'numeric',minute:'2-digit'}),lt=b.toLocaleTimeString('en-US',{hour:'numeric',minute:'2-digit'});return fd===ld?`${fd} ${ft} – ${lt}`:`${fd} ${ft} – ${ld} ${lt}`}
function v103JourneyDays(){
  if(!project)return[];v103EnsureModel();
  const stops=project.stops||[],stopOrder=new Map(stops.map((s,i)=>[s.stop_id,i]));
  const segments=v103Segments(),memberIds=new Set(segments.flatMap(s=>s.member_stop_ids||[]));
  const groups=new Map();
  const put=(key,item,order)=>{if(!groups.has(key))groups.set(key,[]);groups.get(key).push({...item,order})};
  stops.filter(s=>!memberIds.has(s.stop_id)).forEach(s=>put(v103StopDayKey(s),{type:'stop',stop:s},stopOrder.get(s.stop_id)||0));
  segments.forEach(seg=>{const members=v103SegmentMembers(seg);if(!members.length)return;const key=v103StopDayKey(members[0]);put(key,{type:'segment',segment:seg},Math.min(...members.map(s=>stopOrder.get(s.stop_id)||0)))});
  const keys=[...groups.keys()].sort((a,b)=>a==='undated'?1:b==='undated'?-1:a.localeCompare(b));
  return keys.map((key,i)=>{const items=groups.get(key).sort((a,b)=>a.order-b.order);const ids=new Set(items.flatMap(item=>v103ItemAssets(item).map(a=>a.asset_id)));return{key,index:i,title:v103DayTitle(key,i),items,assetCount:ids.size,stopCount:items.reduce((n,item)=>n+v103ItemStops(item).length,0)}})
}
function v103FlatItems(){return v103JourneyDays().flatMap(day=>day.items.map(item=>({...item,day})))}
function v103GenericName(name){return!name||/^Stop\s+\d+$/i.test(name)||/^Photo Cluster$/i.test(name)}
var v103OriginalStopName=stopName;
stopName=function(stop,index){const raw=(stop?.name||stop?.poi_name||'').trim();return raw&&!/^Stop\s+\d+$/i.test(raw)?raw:`Stop ${index+1}`};

function v103BuildRail(){
  const rail=document.querySelector('.rightRail');if(!rail)return;
  const exportBox=el('exportBox');
  rail.innerHTML=`<div class="rightTop"><div class="rightTitle">Journey <span id="stopCount" class="rightCount"></span></div><button id="stopSearchButton" class="rightSearch">⌕</button></div>
  <div id="stopSearchWrap" class="stopSearchWrap"><input id="stopSearch" placeholder="Search days, stops, and segments…"></div>
  <div class="journeyActions"><button id="selectStopsButton">Select</button><button id="combineStopsButton" disabled>Combine</button><button id="suggestNamesButton">Name from Map</button><button id="journeyMoreButton">•••</button></div>
  <div id="journeyMoreMenu" class="journeyMoreMenu"><button id="tripSettingsButton">Trip Settings</button><button id="addStopButton">Add Stop</button><button id="reverseJourneyButton">Reverse Route</button></div>
  <div id="stopList" class="stopList dayList"></div>`;
  if(exportBox){exportBox.classList.add('collapsed');rail.appendChild(exportBox)}
  el('settingsButton')?.classList.add('v103Hidden');
  el('stopSearchButton').onclick=()=>el('stopSearchWrap').classList.toggle('show');
  el('stopSearch').oninput=renderStops;
  el('selectStopsButton').onclick=v103ToggleSelectMode;
  el('combineStopsButton').onclick=v103OpenCombineModal;
  el('suggestNamesButton').onclick=()=>v103SchedulePoiNaming(true);
  el('journeyMoreButton').onclick=()=>el('journeyMoreMenu').classList.toggle('show');
  el('tripSettingsButton').onclick=()=>{el('journeyMoreMenu').classList.remove('show');el('stopRadius').value=project?.settings?.stop_radius_m||200;setModal('settingsModal')};
  el('addStopButton').onclick=()=>{el('journeyMoreMenu').classList.remove('show');addStop()};
  el('reverseJourneyButton').onclick=()=>{el('journeyMoreMenu').classList.remove('show');reverseRoute().catch(e=>toast(e.message))};
}
function v103InsertSegmentModal(){if(el('segmentModal'))return;document.body.insertAdjacentHTML('beforeend',`<div id="segmentModal" class="modal"><div class="modalCard"><div class="modalTitle">Combine Stops</div><div class="formGrid"><label class="small">Segment type</label><select id="segmentType"><option value="drive">Drive</option><option value="hike">Hike</option><option value="custom">Custom Segment</option></select><label class="small">Name</label><input id="segmentName" placeholder="Automatic name"><div id="segmentSummary" class="small"></div><div class="modalActions"><button id="createSegmentButton" class="primary">Combine Stops</button><button data-close-v103="segmentModal">Cancel</button></div></div></div></div>`);el('createSegmentButton').onclick=v103CreateSegment;document.querySelector('[data-close-v103="segmentModal"]').onclick=()=>setModal('segmentModal',false)}
function v103ToggleSelectMode(){v103SelectMode=!v103SelectMode;if(!v103SelectMode)v103SelectedStops.clear();el('selectStopsButton').classList.toggle('active',v103SelectMode);el('selectStopsButton').textContent=v103SelectMode?'Done':'Select';el('combineStopsButton').disabled=v103SelectedStops.size<2;renderStops()}
function v103ToggleStopSelection(id){if(v103SelectedStops.has(id))v103SelectedStops.delete(id);else v103SelectedStops.add(id);el('combineStopsButton').disabled=v103SelectedStops.size<2;renderStops()}
function v103OpenCombineModal(){const ids=[...v103SelectedStops];if(ids.length<2)return;const days=new Set(ids.map(id=>v103StopDayKey(v103StopById(id))));if(days.size>1)return toast('Combine stops within the same day.');const names=ids.map(id=>stopName(v103StopById(id),v103StopIndex(id)));el('segmentName').value='';el('segmentSummary').textContent=`${ids.length} stops: ${names.join(' → ')}`;setModal('segmentModal')}
async function v103CreateSegment(){const ids=[...v103SelectedStops].sort((a,b)=>v103StopIndex(a)-v103StopIndex(b));if(ids.length<2)return;const type=el('segmentType').value,name=el('segmentName').value.trim();v103EnsureModel();project.settings.segments.push({id:`seg_${Date.now().toString(36)}`,type,name,member_stop_ids:ids,created_at:new Date().toISOString()});v103SelectedStops.clear();v103SelectMode=false;setModal('segmentModal',false);await saveProject();toast('Stops combined. Original stops are preserved inside the segment.')}
async function v103UngroupSegment(id){project.settings.segments=project.settings.segments.filter(s=>s.id!==id);if(v103ActiveSegmentId===id)v103ActiveSegmentId=null;await saveProject();toast('Segment ungrouped.')}
async function v103RenameSegment(id){const seg=v103Segments().find(s=>s.id===id);if(!seg)return;const value=prompt('Segment name',v103SegmentName(seg));if(value?.trim()){seg.name=value.trim();await saveProject()}}
async function v103RenameDay(key){const days=v103JourneyDays(),day=days.find(d=>d.key===key);const value=prompt('Day title',project.settings.day_titles[key]||day?.title||'');if(value===null)return;if(value.trim())project.settings.day_titles[key]=value.trim();else delete project.settings.day_titles[key];await saveProject()}
function v103SelectSegment(id,{fly=true}={}){const seg=v103Segments().find(s=>s.id===id);if(!seg)return;v103ActiveSegmentId=id;activeStopId=null;filterStopId=null;activeAssetId=null;renderStops();renderGallery();renderSelectedPhotoBubbles();if(fly&&map){const bounds=new maplibregl.LngLatBounds();v103SegmentAssets(seg).filter(validPoint).forEach(a=>bounds.extend([Number(a.lon),Number(a.lat)]));if(!bounds.isEmpty())map.fitBounds(bounds,{padding:{top:100,bottom:120,left:110,right:110},maxZoom:16.2,duration:1200})}}
selectStop=function(id,opts={}){v103ActiveSegmentId=null;return v103BaseSelectStop(id,opts)};

renderHeader=function(){if(!project){el('journeyTitle').textContent='No journey selected';el('journeyMeta').textContent='Load or create a journey';return}const days=v103JourneyDays();el('journeyTitle').textContent=project.name||'Untitled Journey';el('journeyMeta').innerHTML=`<span>◷ ${esc(rangeText(project)||prettyDate(project.created))}</span><span class="liveDot"></span><span>${(project.assets||[]).length} media</span><span>• ${days.length} days</span><span>• ${(project.stops||[]).length} stops</span>`};
renderStops=function(){
  if(!project){el('stopCount').textContent='';el('stopList').innerHTML='<div class="small">Open a journey to begin.</div>';return}
  v103EnsureModel();const days=v103JourneyDays(),q=(el('stopSearch')?.value||'').trim().toLowerCase();if(!v103OpenDays.size&&days[0])v103OpenDays.add(days[0].key);
  el('stopCount').textContent=`(${days.length} days)`;
  el('stopList').innerHTML=days.map(day=>{
    const filtered=day.items.filter(item=>!q||`${day.title} ${v103ItemName(item)} ${item.type}`.toLowerCase().includes(q));if(q&&!filtered.length)return'';const open=q||v103OpenDays.has(day.key);
    return`<section class="dayCard ${open?'open':''}" data-day="${esc(day.key)}"><div class="dayHeader"><div class="dayIndex">${day.index+1}</div><div class="dayTitleWrap"><div class="dayTitle">${esc(day.title)}</div><div class="dayMeta">${day.assetCount} photos • ${day.stopCount} stops • ${day.items.length} items</div></div><button class="dayRename" data-day-rename="${esc(day.key)}">✎</button><div class="dayChevron">⌄</div></div><div class="dayBody">${filtered.map(item=>{
      const assets=v103ItemAssets(item),name=v103ItemName(item),range=v103ItemRange(item),isSeg=item.type==='segment',active=isSeg?v103ActiveSegmentId===item.segment.id:activeStopId===item.stop.stop_id,id=isSeg?item.segment.id:item.stop.stop_id;
      const memberText=isSeg?v103SegmentMembers(item.segment).map(s=>stopName(s,v103StopIndex(s.stop_id))).join(' → '):'';
      return`<article class="journeyItem ${isSeg?'segment':''} ${active?'active open':''}" data-kind="${item.type}" data-item="${esc(id)}"><div class="journeyItemMain">${v103SelectMode&&!isSeg?`<button class="stopCheck ${v103SelectedStops.has(id)?'checked':''}" data-select-stop="${esc(id)}">${v103SelectedStops.has(id)?'✓':''}</button>`:''}<div class="itemBadge ${isSeg?item.segment.type:'stop'}">${isSeg?(item.segment.type==='drive'?'↝':item.segment.type==='hike'?'⌁':'◇'):(v103StopIndex(id)+1)}</div><div class="itemText"><div class="itemName">${esc(name)}</div><div class="itemMeta">${assets.length} photos • ${esc(range)}</div>${isSeg?`<div class="segmentMembers">${esc(memberText)}</div>`:''}</div><div class="itemChevron">›</div></div><div class="itemControls">${isSeg?`<button data-view-segment="${esc(id)}">View</button><button data-present-segment="${esc(id)}">Present</button><button data-rename-segment="${esc(id)}">Rename</button><button data-ungroup-segment="${esc(id)}">Ungroup</button>`:`<button data-view-stop="${esc(id)}">View</button><button data-present-stop="${esc(id)}">Present</button><button data-rename-stop="${esc(id)}">Rename</button><button data-delete-stop="${esc(id)}">Delete</button>`}</div></article>`}).join('')}</div></section>`}).join('')||'<div class="small">No matching journey items.</div>';
  document.querySelectorAll('.dayHeader').forEach(h=>h.onclick=e=>{if(e.target.closest('button'))return;const key=h.closest('.dayCard').dataset.day;if(v103OpenDays.has(key))v103OpenDays.delete(key);else v103OpenDays.add(key);renderStops()});
  document.querySelectorAll('[data-day-rename]').forEach(b=>b.onclick=e=>{e.stopPropagation();v103RenameDay(b.dataset.dayRename)});
  document.querySelectorAll('.journeyItemMain').forEach(row=>row.onclick=e=>{if(e.target.closest('button'))return;const card=row.closest('.journeyItem');if(card.dataset.kind==='segment')v103SelectSegment(card.dataset.item);else selectStop(card.dataset.item,{fly:true,popup:true,filter:true})});
  document.querySelectorAll('[data-select-stop]').forEach(b=>b.onclick=e=>{e.stopPropagation();v103ToggleStopSelection(b.dataset.selectStop)});
  document.querySelectorAll('[data-view-stop]').forEach(b=>b.onclick=()=>selectStop(b.dataset.viewStop,{fly:true,popup:true,filter:true}));
  document.querySelectorAll('[data-present-stop]').forEach(b=>b.onclick=()=>openPresent(v103StopIndex(b.dataset.presentStop)));
  document.querySelectorAll('[data-rename-stop]').forEach(b=>b.onclick=()=>renameStop(b.dataset.renameStop));
  document.querySelectorAll('[data-delete-stop]').forEach(b=>b.onclick=()=>deleteStop(b.dataset.deleteStop));
  document.querySelectorAll('[data-view-segment]').forEach(b=>b.onclick=()=>v103SelectSegment(b.dataset.viewSegment));
  document.querySelectorAll('[data-present-segment]').forEach(b=>b.onclick=()=>v103OpenPresentSegment(b.dataset.presentSegment));
  document.querySelectorAll('[data-rename-segment]').forEach(b=>b.onclick=()=>v103RenameSegment(b.dataset.renameSegment));
  document.querySelectorAll('[data-ungroup-segment]').forEach(b=>b.onclick=()=>v103UngroupSegment(b.dataset.ungroupSegment));
};

galleryAssets=function(){if(!project)return[];if(v103ActiveSegmentId){const seg=v103Segments().find(s=>s.id===v103ActiveSegmentId);return v103SegmentAssets(seg)}if(filterStopId){return stopAssets(v103StopById(filterStopId))}return project.assets||[]};
renderGallery=function(){const assets=galleryAssets(),seg=v103Segments().find(s=>s.id===v103ActiveSegmentId),stop=v103StopById(filterStopId);const title=seg?v103SegmentName(seg):stop?stopName(stop,v103StopIndex(stop.stop_id)):'Media';el('mediaTitle').textContent=seg?`${seg.type==='drive'?'Drive':seg.type==='hike'?'Hike':'Segment'} • ${title}`:stop?`Stop ${v103StopIndex(stop.stop_id)+1} • ${title}`:'Media';el('mediaCount').textContent=`${assets.length} items`;el('filterChip').classList.toggle('show',!!(seg||stop));el('filterChipText').textContent=seg?`Filter: ${title}`:stop?`Filter: ${title}`:'Filter: All';el('gallery').innerHTML=assets.map((a,i)=>`<div class="mediaTile ${a.asset_id===activeAssetId?'active':''}" data-asset="${esc(a.asset_id)}">${a.thumb?`<img src="${esc(a.thumb)}">`:''}<button class="mediaTileRemove" data-remove-asset="${esc(a.asset_id)}" title="Remove from journey">×</button><div class="mediaTileName">${esc(formatAssetDateTime(a.time)||`Photo ${i+1}`)}</div></div>`).join('')||'<div class="small">No GPS media in this view.</div>';document.querySelectorAll('.mediaTile').forEach(tile=>tile.onclick=()=>focusAsset(tile.dataset.asset));document.querySelectorAll('[data-remove-asset]').forEach(b=>b.onclick=e=>{e.stopPropagation();removeAssetFromJourney(b.dataset.removeAsset)})};
renderSelectedPhotoBubbles=function(){clearBubbleMarkers(photoMarkers);if(!map||map.getZoom()<13.5)return;let assets=[];if(v103ActiveSegmentId)assets=v103SegmentAssets(v103Segments().find(s=>s.id===v103ActiveSegmentId));else if(activeStopId)assets=stopAssets(v103StopById(activeStopId));assets.filter(validPoint).slice(0,160).forEach(asset=>{const node=assetBubbleElement(asset,asset.asset_id===activeAssetId);node.onclick=()=>focusAsset(asset.asset_id);photoMarkers.push(new maplibregl.Marker({element:node,anchor:'center'}).setLngLat([Number(asset.lon),Number(asset.lat)]).addTo(map))})};
focusAsset=function(id){const asset=(project?.assets||[]).find(a=>a.asset_id===id);if(!asset||!validPoint(asset))return;activeAssetId=id;renderGallery();renderSelectedPhotoBubbles();map?.flyTo({center:[Number(asset.lon),Number(asset.lat)],zoom:18.2,pitch:50,bearing:10,duration:950,essential:true});if(activePopup){try{activePopup.remove()}catch{}}activePopup=new maplibregl.Popup({offset:24,closeButton:true,maxWidth:'420px'}).setLngLat([Number(asset.lon),Number(asset.lat)]).setHTML(`<div class="stopPopup"><div class="stopPopupImage">${asset.thumb?`<img src="${esc(asset.thumb)}">`:''}</div><div class="stopPopupBody"><span class="popupKicker">Selected photo</span><div class="popupTitle">${esc(formatAssetDateTime(asset.time))}</div><div class="popupMeta">${esc(assetCoordinateText(asset))}</div></div></div>`).addTo(map)};

async function v103SaveProjectQuiet(){if(!project)return;project=await api('/api/project/'+encodeURIComponent(project.id),{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(project)});await refreshProjectSummary()}
saveProject=async function(){if(!project)return;v103EnsureModel();await v103SaveProjectQuiet();renderAll()};
renameStop=async function(id){const i=v103StopIndex(id);if(i<0)return;const value=prompt('Stop name',stopName(project.stops[i],i));if(value?.trim()){project.stops[i].name=value.trim();project.stops[i].name_source='manual';await saveProject()}};
var v103BaseDeleteStop=deleteStop;
deleteStop=async function(id){await v103BaseDeleteStop(id);if(!project)return;v103EnsureModel();project.settings.segments=project.settings.segments.map(s=>({...s,member_stop_ids:s.member_stop_ids.filter(x=>x!==id)})).filter(s=>s.member_stop_ids.length>1);await v103SaveProjectQuiet();renderAll()};
var v103BaseRemoveAsset=removeAssetFromJourney;
removeAssetFromJourney=async function(assetId){await v103BaseRemoveAsset(assetId);if(!project)return;v103EnsureModel();project.settings.segments=project.settings.segments.map(s=>({...s,member_stop_ids:s.member_stop_ids.filter(id=>v103StopById(id))})).filter(s=>s.member_stop_ids.length>1);await v103SaveProjectQuiet();renderAll()};
openProject=async function(id){project=await api('/api/project/'+encodeURIComponent(id));v103EnsureModel();v103ActiveSegmentId=null;v103SelectedStops.clear();v103SelectMode=false;activeStopId=project.stops?.[0]?.stop_id||null;filterStopId=activeStopId;activeAssetId=null;const days=v103JourneyDays();v103OpenDays=new Set(days[0]?[days[0].key]:[]);renderAll();toast(`Loaded ${project.name||'journey'}`);setTimeout(()=>v103SchedulePoiNaming(false),1200)};

function v103CacheSave(){try{localStorage.setItem('trippy_poi_cache_v1',JSON.stringify(v103PoiCache))}catch{}}
function v103Sleep(ms){return new Promise(r=>setTimeout(r,ms))}
function v103PoiLabel(data){if(!data)return null;const a=data.address||{},raw=(data.name||'').trim(),type=String(data.type||data.category||'').toLowerCase();if(raw&&!/^\d+$/.test(raw)&&!/^unnamed/i.test(raw)){if(/trail|path|footway|cycleway/.test(type)&&!/trail|path/i.test(raw))return{label:`${raw} Trail`,type:'trail'};return{label:raw,type:type||'poi'}}const trail=a.path||a.footway||a.cycleway||a.pedestrian;if(trail)return{label:/trail|path/i.test(trail)?trail:`${trail} Trail`,type:'trail'};const road=a.road||a.highway;if(road){const ref=data.extratags?.ref||a.road_ref;return{label:ref&&!road.includes(ref)?`${ref} · ${road}`:road,type:'road'}}const park=a.park||a.nature_reserve||a.national_park;if(park)return{label:park,type:'park'};const water=a.lake||a.river||a.water;if(water)return{label:water,type:'water'};const town=a.town||a.city||a.village||a.hamlet;if(town)return{label:`${town} Stop`,type:'town'};const first=(data.display_name||'').split(',')[0].trim();return first?{label:first,type:'place'}:null}
async function v103Reverse(lat,lon){const key=`${Number(lat).toFixed(4)},${Number(lon).toFixed(4)}`;if(v103PoiCache[key])return v103PoiCache[key];await v103Sleep(1100);try{const r=await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}&zoom=17&addressdetails=1&namedetails=1`);if(!r.ok)return null;const result=v103PoiLabel(await r.json());if(result){v103PoiCache[key]=result;v103CacheSave()}return result}catch{return null}}
async function v103NameOneStop(stop){const assets=stopAssets(stop).filter(validPoint);const reps=[];[assets[0],assets[Math.floor(assets.length/2)],assets[assets.length-1]].filter(Boolean).forEach(a=>{if(!reps.some(x=>Math.abs(x.lat-a.lat)<1e-6&&Math.abs(x.lon-a.lon)<1e-6))reps.push(a)});if(!reps.length&&validPoint(stop))reps.push(stop);const results=[];for(const p of reps.slice(0,3)){const result=await v103Reverse(p.lat,p.lon);if(result)results.push(result)}if(!results.length)return false;const counts=new Map();results.forEach(r=>counts.set(r.label,(counts.get(r.label)||0)+1));results.sort((a,b)=>(counts.get(b.label)-counts.get(a.label)));const best=results[0];stop.poi_name=best.label;stop.poi_type=best.type;if(v103GenericName(stop.name)){stop.name=best.label;stop.name_source='poi'}return true}
async function v103SchedulePoiNaming(force){if(v103PoiBusy||!project)return;const queue=(project.stops||[]).filter(s=>force||(!v103PoiAttempted.has(s.stop_id)&&v103GenericName(s.name)));if(!queue.length)return toast('Stop names are already up to date.');v103PoiBusy=true;el('suggestNamesButton').textContent='Naming…';toast(`Finding map names for ${queue.length} stops in the background.`);let changed=0;for(const stop of queue){v103PoiAttempted.add(stop.stop_id);if(stop.name_source==='manual')continue;if(await v103NameOneStop(stop))changed++;if(changed&&changed%6===0){await v103SaveProjectQuiet();renderStops()}}if(changed){await v103SaveProjectQuiet();renderAll();toast(`Added map-based names to ${changed} stops.`)}else toast('No additional named map features were found.');v103PoiBusy=false;el('suggestNamesButton').textContent='Name from Map'}

function v103PresentItems(){return v103FlatItems()}
function v103CurrentPresentItem(){return v103PresentItem||v103PresentItems()[v103PresentFlatIndex]||null}
presentAssets=function(){return v103ItemAssets(v103CurrentPresentItem())};
renderPresentStops=function(){const days=v103JourneyDays();el('presentStopRail').innerHTML=days.map(day=>`<div class="presentDayLabel" data-present-day="${esc(day.key)}">${esc(day.title)}<span>${day.assetCount} photos</span></div>${day.items.map(item=>{const flat=v103PresentItems().findIndex(x=>v103ItemId(x)===v103ItemId(item));return`<div class="presentStopItem ${flat===v103PresentFlatIndex&&presentView!=='day'?'active':''}" data-present-item="${flat}">${item.type==='segment'?'◇':'•'} ${esc(v103ItemName(item))}<div class="small">${v103ItemAssets(item).length} photos • ${esc(v103ItemRange(item))}</div></div>`}).join('')}`).join('');document.querySelectorAll('[data-present-item]').forEach(x=>x.onclick=()=>v103GoPresentItem(Number(x.dataset.presentItem)));document.querySelectorAll('[data-present-day]').forEach(x=>x.onclick=()=>v103CenterPresentDay(x.dataset.presentDay))};
function v103ItemBounds(item){const bounds=new maplibregl.LngLatBounds();v103ItemAssets(item).filter(validPoint).forEach(a=>bounds.extend([Number(a.lon),Number(a.lat)]));if(bounds.isEmpty())v103ItemStops(item).filter(validPoint).forEach(s=>bounds.extend([Number(s.lon),Number(s.lat)]));return bounds}
function v103ItemCenter(item){const pts=v103ItemAssets(item).filter(validPoint);if(pts.length)return[pts.reduce((n,a)=>n+Number(a.lon),0)/pts.length,pts.reduce((n,a)=>n+Number(a.lat),0)/pts.length];const s=v103ItemStops(item)[0];return validPoint(s)?[Number(s.lon),Number(s.lat)]:null}
function v103GoPresentItem(index){const items=v103PresentItems();if(!items.length)return;stopPresentOrbit();clearPresentFocus();v103PresentFlatIndex=(index+items.length)%items.length;v103PresentItem=items[v103PresentFlatIndex];v103PresentDayKey=v103PresentItem.day.key;presentView='item';presentPhotoIndex=-1;const firstStop=v103ItemStops(v103PresentItem)[0];presentStopIndex=firstStop?v103StopIndex(firstStop.stop_id):0;renderPresentStops();renderPresentFilmstrip();renderPresentPhotoBubbles();const name=v103ItemName(v103PresentItem),range=v103ItemRange(v103PresentItem),assets=v103ItemAssets(v103PresentItem);el('presentHeaderTitle').textContent=name;el('presentHeaderMeta').textContent=`${v103PresentItem.day.title} • ${v103PresentItem.type==='segment'?(v103PresentItem.segment.type||'segment'):'stop'} • ${assets.length} photos`;el('presentStopBannerTitle').textContent=name;el('presentStopBannerRange').textContent=`${v103PresentItem.day.title} • ${range} • ${assets.length} photos`;el('presentPhotoCard').classList.remove('show');const center=v103ItemCenter(v103PresentItem),bounds=v103ItemBounds(v103PresentItem);if(center)showPresentFocus({lon:center[0],lat:center[1]});if(!bounds.isEmpty()){presentMap.fitBounds(bounds,{padding:{top:130,bottom:205,left:285,right:430},maxZoom:v103PresentItem.type==='segment'?14.8:16.1,duration:1800,essential:true});setTimeout(()=>{presentMap.easeTo({pitch:58,bearing:(v103PresentFlatIndex*29)%360,duration:750,essential:true});if(center)startPresentOrbit(center,Math.min(presentMap.getZoom(),v103PresentItem.type==='segment'?14.8:16.1),58)},1000)}}
goPresentStop=function(index){const stop=project?.stops?.[(index+(project?.stops?.length||1))%(project?.stops?.length||1)];if(!stop)return;const flat=v103PresentItems().findIndex(item=>v103ItemStops(item).some(s=>s.stop_id===stop.stop_id));v103GoPresentItem(flat<0?0:flat)};
function v103OpenPresentSegment(id){const flat=v103PresentItems().findIndex(item=>item.type==='segment'&&item.segment.id===id);openPresent(0);setTimeout(()=>v103GoPresentItem(flat<0?0:flat),180)}
function v103CenterPresentDay(key){if(!presentMap)return;stopPresentOrbit();presentView='day';v103PresentDayKey=key;const day=v103JourneyDays().find(d=>d.key===key);if(!day)return;const bounds=new maplibregl.LngLatBounds();day.items.flatMap(v103ItemAssets).filter(validPoint).forEach(a=>bounds.extend([Number(a.lon),Number(a.lat)]));if(!bounds.isEmpty())presentMap.fitBounds(bounds,{padding:{top:120,bottom:120,left:285,right:90},maxZoom:12.8,duration:1500,essential:true});el('presentHeaderTitle').textContent=day.title;el('presentHeaderMeta').textContent=`${day.items.length} stops and segments • ${day.assetCount} photos`;el('presentStopBannerTitle').textContent=day.title;el('presentStopBannerRange').textContent=`Day overview • ${day.assetCount} photos • ${day.stopCount} original stops`;el('presentPhotoCard').classList.remove('show');renderPresentStops()}
centerPresentTrip=function(){if(!presentMap||!project?.stops?.length)return;stopPresentOrbit();presentView='trip';const bounds=tripBounds();if(!bounds.isEmpty())presentMap.fitBounds(bounds,{padding:{top:110,bottom:110,left:285,right:80},maxZoom:12.5,duration:1500,essential:true});clearPresentFocus();const days=v103JourneyDays();el('presentHeaderTitle').textContent=project.name||'Journey Overview';el('presentHeaderMeta').textContent=`${days.length} days • ${project.stops.length} stops • ${(project.assets||[]).length} photos`;el('presentStopBannerTitle').textContent=project.name||'Journey Overview';el('presentStopBannerRange').textContent=`${days.length} days • ${v103PresentItems().length} stops and segments`;el('presentPhotoCard').classList.remove('show');renderPresentStops()};
presentBack=function(){if(presentView==='photo'){v103GoPresentItem(v103PresentFlatIndex);return}if(presentView==='item'){v103CenterPresentDay(v103PresentDayKey);return}if(presentView==='day'){centerPresentTrip();return}centerPresentTrip()};
returnPresentStart=function(){v103PresentFlatIndex=0;presentPhotoIndex=-1;v103GoPresentItem(0)};
goPresentPhoto=function(index){const assets=presentAssets();if(!assets.length)return;stopPresentOrbit();presentView='photo';presentPhotoIndex=(index+assets.length)%assets.length;const asset=assets[presentPhotoIndex];if(!validPoint(asset))return;renderPresentFilmstrip();renderPresentPhotoBubbles();showPresentFocus(asset);const item=v103CurrentPresentItem(),name=v103ItemName(item);el('presentStopBannerTitle').textContent=name;el('presentStopBannerRange').textContent=`Photo ${presentPhotoIndex+1} of ${assets.length} • ${formatAssetDateTime(asset.time)}`;el('presentPhotoCard').innerHTML=`${asset.preview||asset.thumb?`<img src="${esc(asset.preview||asset.thumb)}">`:''}<div class="presentPhotoBody"><div class="presentPhotoTitle">Photo ${presentPhotoIndex+1} of ${assets.length}</div><div class="presentPhotoMeta">${esc(formatAssetDateTime(asset.time))}</div><div class="presentPhotoCoords">${esc(assetCoordinateText(asset))}</div><div class="presentPhotoActions"><button onclick="v103GoPresentItem(v103PresentFlatIndex)">Back to ${item.type==='segment'?'Segment':'Stop'}</button><button class="danger" onclick="removeAssetFromJourney('${esc(asset.asset_id)}')">Remove from Journey</button></div></div>`;el('presentPhotoCard').classList.add('show');const center=[Number(asset.lon),Number(asset.lat)],zoom=17.45;presentMap.flyTo({center,zoom,pitch:50,bearing:(presentPhotoIndex*17)%360,duration:1350,curve:1.3,essential:true});startPresentOrbit(center,zoom,50)};
openPresent=function(index=0){if(!project?.stops?.length)return toast('Load a journey with stops first.');el('presentOverlay').classList.add('show');ensurePresentMap();const stop=project.stops[index]||project.stops[0],flat=v103PresentItems().findIndex(item=>v103ItemStops(item).some(s=>s.stop_id===stop.stop_id));setTimeout(()=>{presentMap.resize();const start=()=>{renderPresentMapLayers();v103GoPresentItem(flat<0?0:flat)};if(presentMap.isStyleLoaded())start();else presentMap.once('load',start)},90)};
togglePlay=function(){if(presentTimer){clearInterval(presentTimer);presentTimer=null;el('playJourneyButton').textContent='▶ Play';return}el('playJourneyButton').textContent='Ⅱ Pause';presentTimer=setInterval(()=>{const assets=presentAssets();if(presentView==='item'&&assets.length){goPresentPhoto(0);return}if(presentView==='photo'&&presentPhotoIndex<assets.length-1){goPresentPhoto(presentPhotoIndex+1);return}v103GoPresentItem(v103PresentFlatIndex+1)},4300)};

function v103RebindPresentation(){el('previousStopButton').onclick=()=>v103GoPresentItem(v103PresentFlatIndex-1);el('nextStopButton').onclick=()=>v103GoPresentItem(v103PresentFlatIndex+1);el('presentBackButton').onclick=presentBack;el('centerTripButton').onclick=centerPresentTrip;el('returnStartButton').onclick=returnPresentStart;el('playJourneyButton').onclick=togglePlay;el('clearFilterButton').onclick=()=>{filterStopId=null;activeStopId=null;v103ActiveSegmentId=null;renderGallery();renderStops();renderMap(false)}}

v103BuildRail();v103InsertSegmentModal();v103RebindPresentation();
const v103OriginalRenderAll=renderAll;
renderAll=function(){v103EnsureModel();renderProjects();renderHeader();renderStops();renderGallery();renderMap(true)};
if(project){v103EnsureModel();renderAll();setTimeout(()=>v103SchedulePoiNaming(false),1200)}

</script>
</body>
</html>
TRIPPY_FRONTEND_EOF_1031
pct push "$CTID" /tmp/trippy_index.html "$APP_DIR/frontend/index.html"
rm -f /tmp/trippy_index.html







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








pct exec "$CTID" -- bash -lc "grep -q 'Trippy v10.3.1' /opt/trippy/frontend/index.html && grep -q 'presentMap' /opt/trippy/frontend/index.html && grep -q 'photoMarker' /opt/trippy/frontend/index.html && test -s /opt/trippy/frontend/vendor/maplibre-gl.js" >/dev/null 2>&1 || {
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
printf "${CYAN}${BOLD}v10.3.1 features${RESET}\n"
printf "  ${CYAN}•${RESET} Full mockup-driven frontend replacement\n"
printf "  ${CYAN}•${RESET} Light OSM, dark, and satellite map modes\n"
printf "  ${CYAN}•${RESET} Thumbnail stop markers, route glow, and single clean popups\n"
printf "  ${CYAN}•${RESET} Cinematic Present Journey with stop and photo fly-through controls\n"
printf "  ${CYAN}•${RESET} Immich date-range import and upload-based GPS media import\n"
printf "  ${CYAN}•${RESET} Stop clustering, renaming, recentering, deletion, and route reversal\n"
printf "  ${CYAN}•${RESET} Project deletion, saved Immich connection, GPX, and MP4 export\n"
printf "  ${CYAN}•${RESET} Local MapLibre bundle for reliable frontend loading\n"
printf "  ${CYAN}•${RESET} Auto-selects the next available CTID and uses hostname Trippy\n"
printf "  ${CYAN}•${RESET} v10.3.1 organizes journeys by day, supports combined drive/hike segments, and suggests OSM-based stop names\n"
printf "${PINK}${BOLD}Go make something weird.${RESET}\n"
