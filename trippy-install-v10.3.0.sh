#!/usr/bin/env bash
set -euo pipefail
USER_SUPPLIED_CTID="${CTID:-}"

# Trippy v10.3.0: Immich-style web UI route-tour generator for Proxmox LXC
# Adds stop-based clustering, stop radius, stop review/editing, and lasso grouping.
#
#
# Install directly from GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.3.0.sh \
#     -o trippy-install-v10.3.0.sh
#   chmod +x trippy-install-v10.3.0.sh
#   ./trippy-install-v10.3.0.sh
#
# Or with wget:
#
#   wget -O trippy-install-v10.3.0.sh \
#     https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.3.0.sh
#   chmod +x trippy-install-v10.3.0.sh
#   ./trippy-install-v10.3.0.sh
#
# Run on Proxmox host:
#   bash trippy-install-v10.3.0.sh
#
# Optional:
#   CTID=106 STORAGE=local-lvm BRIDGE=vmbr0 bash trippy-install-v10.3.0.sh

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

printf "${CYAN}${BOLD}Trippy v10.3.0 Clean Installer${RESET}\n"
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

pct set "$CTID" --description "🧭 Trippy v10.3.0
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

app = FastAPI(title="Trippy", version="1.3.0")
app.mount("/exports", StaticFiles(directory=str(EXPORTS)), name="exports")
app.mount("/uploads", StaticFiles(directory=str(UPLOADS)), name="uploads")
app.mount("/static", StaticFiles(directory=str(FRONTEND)), name="static")

@app.get("/api/health")
def health():
    return {
        "ok": True,
        "app": "trippy",
        "version": "1.3.0",
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
// Trippy v10.3.0 UI behavior upgrades
(function(){{
  function ready(fn){{ if(document.readyState!=='loading') fn(); else document.addEventListener('DOMContentLoaded',fn); }}
  window.TRIPPY_VERSION='v10.3.0';
  ready(() => {{
    if(!document.querySelector('.versionBadge')){{
      const v=document.createElement('div'); v.className='versionBadge'; v.textContent='v10.3.0'; document.body.appendChild(v);
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
      const v=document.createElement('div');v.className='versionBadge';v.textContent='v10.3.0';document.body.appendChild(v);
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

/* Trippy v10.3.0 UI refresh */
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






# v10.3.0: full frontend replacement, not an overlay.
pct exec "$CTID" -- bash -lc "cat >/tmp/trippy_frontend.b64 <<'EOF_TRIPPY_FRONTEND_B64'
PCFkb2N0eXBlIGh0bWw+CjxodG1sIGxhbmc9ImVuIj4KPGhlYWQ+CjxtZXRhIGNoYXJzZXQ9InV0Zi04Ij4KPG1ldGEgbmFtZT0idmlld3BvcnQiIGNvbnRlbnQ9IndpZHRoPWRldmljZS13aWR0aCxpbml0aWFsLXNjYWxlPTEiPgo8dGl0bGU+VHJpcHB5IHYxMC4zLjA8L3RpdGxlPgo8bGluayByZWw9InN0eWxlc2hlZXQiIGhyZWY9Ii9zdGF0aWMvdmVuZG9yL21hcGxpYnJlLWdsLmNzcyI+CjxzY3JpcHQgc3JjPSIvc3RhdGljL3ZlbmRvci9tYXBsaWJyZS1nbC5qcyI+PC9zY3JpcHQ+CjxzdHlsZT4KOnJvb3R7CiAgLS1iZzojMDMwODEzOy0tYmcyOiMwNzExMWQ7LS1wYW5lbDojMDgxNDIxOy0tcGFuZWwyOiMwZDFjMmM7LS1jYXJkOiMwYzFhMjk7CiAgLS1saW5lOiMxZDM4NTA7LS1saW5lMjojMjU0YTY4Oy0tY3lhbjojMDBkOGZmOy0tY3lhbjI6IzM2ZWRmZjstLWJsdWU6IzI2N2RmZjsKICAtLXZpb2xldDojNjg0OGZmOy0tcGluazojZmY0ZGE2Oy0tZ3JlZW46IzM5ZDk5NTstLXJlZDojZmY0ZDY2Oy0tdGV4dDojZjJmOGZmOwogIC0tbXV0ZWQ6IzhlYTNiNjstLXNvZnQ6I2I4YzhkNzstLXNoYWRvdzowIDI0cHggNzBweCByZ2JhKDAsMCwwLC40MikKfQoqe2JveC1zaXppbmc6Ym9yZGVyLWJveH0KaHRtbCxib2R5e2hlaWdodDoxMDAlO21hcmdpbjowO292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOnZhcigtLWJnKTtjb2xvcjp2YXIoLS10ZXh0KTtmb250LWZhbWlseTpJbnRlciwiU2Vnb2UgVUkiLHN5c3RlbS11aSxzYW5zLXNlcmlmfQpib2R5e2JhY2tncm91bmQ6cmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCA5JSAwJSxyZ2JhKDAsMjE2LDI1NSwuMTMpLHRyYW5zcGFyZW50IDI3JSkscmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCA4MiUgNyUscmdiYSgxMDQsNzIsMjU1LC4xMiksdHJhbnNwYXJlbnQgMzAlKSxsaW5lYXItZ3JhZGllbnQoMTQ1ZGVnLCMwMjA3MTEsIzA3MTIxZSA1OCUsIzAyMDYwZCl9CmJ1dHRvbixpbnB1dCxzZWxlY3R7Zm9udDppbmhlcml0fWJ1dHRvbntjb2xvcjp2YXIoLS10ZXh0KTtjdXJzb3I6cG9pbnRlcjtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzUsMTI2LDE2NCwuNDUpO2JvcmRlci1yYWRpdXM6MTNweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgyMCw0Myw2NiwuOTgpLHJnYmEoMTAsMjUsNDEsLjk4KSk7Zm9udC13ZWlnaHQ6ODAwO3RyYW5zaXRpb246LjE2cyBlYXNlfWJ1dHRvbjpob3Zlcntib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMjJweCByZ2JhKDAsMjE2LDI1NSwuMjIpO3RyYW5zZm9ybTp0cmFuc2xhdGVZKC0xcHgpfQppbnB1dCxzZWxlY3R7d2lkdGg6MTAwJTtjb2xvcjp2YXIoLS10ZXh0KTtiYWNrZ3JvdW5kOiMwNzExMWM7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDkwLDEzOSwxNzMsLjM4KTtib3JkZXItcmFkaXVzOjEycHg7cGFkZGluZzoxMXB4IDEycHg7b3V0bGluZTpub25lfWlucHV0OmZvY3VzLHNlbGVjdDpmb2N1c3tib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMCAzcHggcmdiYSgwLDIxNiwyNTUsLjEwKX0KLnNtYWxse2ZvbnQtc2l6ZToxMnB4O2NvbG9yOnZhcigtLW11dGVkKX0uaGlkZGVue2Rpc3BsYXk6bm9uZSFpbXBvcnRhbnR9LnN2Z0ljb257d2lkdGg6MjBweDtoZWlnaHQ6MjBweDtzdHJva2U6Y3VycmVudENvbG9yO2ZpbGw6bm9uZTtzdHJva2Utd2lkdGg6MS44O3N0cm9rZS1saW5lY2FwOnJvdW5kO3N0cm9rZS1saW5lam9pbjpyb3VuZH0KLmFwcFNoZWxse2hlaWdodDoxMDB2aDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjI4NnB4IG1pbm1heCg2NTBweCwxZnIpIDM1MHB4O292ZXJmbG93OmhpZGRlbn0KLmxlZnRSYWlse21pbi13aWR0aDowO2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDE4MGRlZyxyZ2JhKDQsMTMsMjMsLjk4KSxyZ2JhKDIsOCwxNSwuOTkpKTtib3JkZXItcmlnaHQ6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4xNCk7cGFkZGluZzoxN3B4IDE3cHggMjBweDtkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO2dhcDoxNHB4O2JveC1zaGFkb3c6MTZweCAwIDYwcHggcmdiYSgwLDAsMCwuMzQpO3otaW5kZXg6MTB9Ci5icmFuZExpbmV7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTJweDtoZWlnaHQ6NjRweH0ud29yZG1hcmt7Zm9udC1zaXplOjMxcHg7Zm9udC13ZWlnaHQ6OTUwO2ZvbnQtc3R5bGU6aXRhbGljO2xldHRlci1zcGFjaW5nOi0xLjVweDt0ZXh0LXNoYWRvdzoycHggMCB2YXIoLS1jeWFuKSwtMnB4IDAgdmFyKC0tcGluayksMCA2cHggMjVweCByZ2JhKDAsMCwwLC45KX0udmVyc2lvbnttYXJnaW4tbGVmdDphdXRvO3BhZGRpbmc6NnB4IDEwcHg7Ym9yZGVyLXJhZGl1czo5OTlweDtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4yOCk7YmFja2dyb3VuZDpyZ2JhKDAsMjE2LDI1NSwuMDgpO2NvbG9yOnZhcigtLWN5YW4yKTtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5NTA7Ym94LXNoYWRvdzowIDAgMThweCByZ2JhKDAsMjE2LDI1NSwuMTApfQoubG9nb0Zsb3dlcntwb3NpdGlvbjpyZWxhdGl2ZTt3aWR0aDo0OXB4O2hlaWdodDo0OXB4O2ZsZXg6MCAwIGF1dG87ZmlsdGVyOmRyb3Atc2hhZG93KDAgMCAxMXB4IHJnYmEoMCwyMTYsMjU1LC4zNSkpIHNhdHVyYXRlKDEuMTgpfS5sb2dvRmxvd2VyIC5wZXRhbHtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjE4cHg7dG9wOjJweDt3aWR0aDoxN3B4O2hlaWdodDoyOXB4O2JvcmRlci1yYWRpdXM6MTRweCAxNHB4IDdweCA3cHg7dHJhbnNmb3JtLW9yaWdpbjo3cHggMjNweDttaXgtYmxlbmQtbW9kZTpzY3JlZW59LmxvZ29GbG93ZXIgLnAxe2JhY2tncm91bmQ6I2ZmNTQ1NDt0cmFuc2Zvcm06cm90YXRlKDBkZWcpIHRyYW5zbGF0ZVkoLTFweCkgc2tld1goLThkZWcpfS5sb2dvRmxvd2VyIC5wMntiYWNrZ3JvdW5kOiNmZmJiMzE7dHJhbnNmb3JtOnJvdGF0ZSg2MGRlZykgdHJhbnNsYXRlWSgwKSBza2V3WCg5ZGVnKX0ubG9nb0Zsb3dlciAucDN7YmFja2dyb3VuZDojNzlkZjRjO3RyYW5zZm9ybTpyb3RhdGUoMTIwZGVnKSB0cmFuc2xhdGVZKDFweCkgc2tld1goLThkZWcpfS5sb2dvRmxvd2VyIC5wNHtiYWNrZ3JvdW5kOiMyN2Q2Yzc7dHJhbnNmb3JtOnJvdGF0ZSgxODBkZWcpIHRyYW5zbGF0ZVkoLTFweCkgc2tld1goOGRlZyl9LmxvZ29GbG93ZXIgLnA1e2JhY2tncm91bmQ6IzQxOGNmZjt0cmFuc2Zvcm06cm90YXRlKDI0MGRlZykgdHJhbnNsYXRlWSgxcHgpIHNrZXdYKC0xMGRlZyl9LmxvZ29GbG93ZXIgLnA2e2JhY2tncm91bmQ6I2RmNjhmZjt0cmFuc2Zvcm06cm90YXRlKDMwMGRlZykgdHJhbnNsYXRlWSgtMXB4KSBza2V3WCg5ZGVnKX0ubG9nb0Zsb3dlcjpiZWZvcmV7Y29udGVudDoiIjtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDo2cHg7Ym9yZGVyLXJhZGl1czo1MCU7Ym94LXNoYWRvdzozcHggMCA4cHggcmdiYSgyNTUsNzcsMTY2LC40NSksLTNweCAwIDhweCByZ2JhKDAsMjE2LDI1NSwuNSk7ZmlsdGVyOmJsdXIoMXB4KX0ubG9nb0Zsb3dlcjphZnRlcntjb250ZW50OiIiO3Bvc2l0aW9uOmFic29sdXRlO2luc2V0OjE2cHg7Ym9yZGVyOjJweCBzb2xpZCByZ2JhKDI0NSwyNTMsMjU1LC44OCk7Ym9yZGVyLXJhZGl1czo1MCU7Ym94LXNoYWRvdzowIDAgOXB4IHJnYmEoMCwyMTYsMjU1LC45KX0KLnNpZGVQcmltYXJ5LC5zaWRlU2Vjb25kYXJ5e2hlaWdodDo1NHB4O3dpZHRoOjEwMCU7Zm9udC1zaXplOjE0cHh9LnNpZGVQcmltYXJ5e2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMDk2MmJkLCMwMGE5YzgpO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuODgpO2JveC1zaGFkb3c6MCAwIDI4cHggcmdiYSgwLDIxNiwyNTUsLjIxKX0KLnNlY3Rpb25MYWJlbHttYXJnaW4tdG9wOjhweDtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuO2NvbG9yOiNjNGQ0ZTI7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwO2xldHRlci1zcGFjaW5nOi4wOGVtO3RleHQtdHJhbnNmb3JtOnVwcGVyY2FzZX0ucHJvamVjdExpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6MTBweDtvdmVyZmxvdzphdXRvO21pbi1oZWlnaHQ6MDtwYWRkaW5nLXJpZ2h0OjJweH0ucHJvamVjdENhcmR7cG9zaXRpb246cmVsYXRpdmU7cGFkZGluZzoxNXB4IDE0cHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoMTMsMjksNDUsLjk0KSxyZ2JhKDcsMTgsMzAsLjk0KSk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDYyLDExMywxNTEsLjMyKTtib3JkZXItcmFkaXVzOjE1cHg7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTZzIGVhc2V9LnByb2plY3RDYXJkOmhvdmVyLC5wcm9qZWN0Q2FyZC5hY3RpdmV7Ym9yZGVyLWNvbG9yOnZhcigtLWN5YW4pO2JveC1zaGFkb3c6MCAwIDI0cHggcmdiYSgwLDIxNiwyNTUsLjE3KX0ucHJvamVjdENhcmRUaXRsZXtwYWRkaW5nLXJpZ2h0OjI0cHg7Zm9udC13ZWlnaHQ6OTAwO2ZvbnQtc2l6ZToxNHB4O3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30ucHJvamVjdERhdGV7bWFyZ2luLXRvcDo2cHg7Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxMnB4fS5wcm9qZWN0U3RhdHN7bWFyZ2luLXRvcDo5cHg7Y29sb3I6IzllYjRjNjtmb250LXNpemU6MTJweH0ucHJvamVjdFN0YXRzIC5kb3R7Y29sb3I6dmFyKC0tY3lhbil9LnByb2plY3RNZW51e3Bvc2l0aW9uOmFic29sdXRlO3JpZ2h0OjlweDt0b3A6MTBweDt3aWR0aDoyOHB4O2hlaWdodDozMnB4O2JvcmRlcjowO2JhY2tncm91bmQ6dHJhbnNwYXJlbnQ7Zm9udC1zaXplOjIwcHg7Ym94LXNoYWRvdzpub25lfS5wcm9qZWN0RGVsZXRle3dpZHRoOjEwMCU7aGVpZ2h0OjM0cHg7bWFyZ2luLXRvcDoxMHB4O2ZvbnQtc2l6ZToxMnB4O2Rpc3BsYXk6bm9uZX0ucHJvamVjdENhcmQubWVudU9wZW4gLnByb2plY3REZWxldGV7ZGlzcGxheTpibG9ja30KLmxlZnRGb290ZXJ7bWFyZ2luLXRvcDphdXRvO2NvbG9yOiM4Mjk2YTg7Zm9udC1zaXplOjEycHg7bGluZS1oZWlnaHQ6MS42NX0uZm9vdGVyTGlua3tkaXNwbGF5OmJsb2NrO21hcmdpbi10b3A6MTBweDtjb2xvcjp2YXIoLS1jeWFuKTt0ZXh0LWRlY29yYXRpb246bm9uZX0KLndvcmtzcGFjZXttaW4td2lkdGg6MDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1yb3dzOjkxcHggbWlubWF4KDM1MHB4LDFmcikgMjI4cHg7YmFja2dyb3VuZDpyZ2JhKDIsOCwxNCwuNTApfQoudG9wQmFye2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjE2cHg7cGFkZGluZzoxNHB4IDE5cHg7Ym9yZGVyLWJvdHRvbToxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjEzKTtiYWNrZ3JvdW5kOnJnYmEoMywxMCwxOCwuODQpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDE4cHgpO3otaW5kZXg6OH0udGl0bGVBcmVhe21pbi13aWR0aDozMjBweDttYXgtd2lkdGg6NDMwcHh9LmpvdXJuZXlUaXRsZVJvd3tkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDo5cHh9LmpvdXJuZXlUaXRsZXtmb250LXNpemU6MjJweDtmb250LXdlaWdodDo5NTA7d2hpdGUtc3BhY2U6bm93cmFwO292ZXJmbG93OmhpZGRlbjt0ZXh0LW92ZXJmbG93OmVsbGlwc2lzfS5lZGl0VGl0bGV7Ym9yZGVyOjA7YmFja2dyb3VuZDp0cmFuc3BhcmVudDtjb2xvcjp2YXIoLS1tdXRlZCk7cGFkZGluZzoycHg7Ym94LXNoYWRvdzpub25lfS5qb3VybmV5TWV0YXtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMXB4O21hcmdpbi10b3A6NnB4O2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTJweH0uam91cm5leU1ldGEgLmxpdmVEb3R7d2lkdGg6N3B4O2hlaWdodDo3cHg7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDp2YXIoLS1ncmVlbik7Ym94LXNoYWRvdzowIDAgOHB4IHJnYmEoNTcsMjE3LDE0OSwuNil9LnRvcFNwYWNlcntmbGV4OjF9LnByZXNlbnRCdXR0b257aGVpZ2h0OjU0cHg7bWluLXdpZHRoOjI2NXB4O3BhZGRpbmc6MCAyNHB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjNjMzYmZmLCMwMGFmZDApO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuODUpO2JveC1zaGFkb3c6MCAwIDMycHggcmdiYSgwLDIxNiwyNTUsLjI4KTtmb250LXNpemU6MTVweH0ucHJlc2VudEJ1dHRvbiBzcGFue2Rpc3BsYXk6YmxvY2s7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6NjUwO29wYWNpdHk6Ljg0O21hcmdpbi10b3A6MnB4fS50b3BBY3Rpb257aGVpZ2h0OjU0cHg7bWluLXdpZHRoOjE0NXB4O3BhZGRpbmc6MCAxNnB4fS5nZWFyQnV0dG9ue3dpZHRoOjU0cHg7bWluLXdpZHRoOjU0cHg7aGVpZ2h0OjU0cHg7Zm9udC1zaXplOjIwcHh9Ci5tYXBab25le3Bvc2l0aW9uOnJlbGF0aXZlO21pbi1oZWlnaHQ6MDtwYWRkaW5nOjAgOHB4IDAgMH0ubWFwRnJhbWV7cG9zaXRpb246YWJzb2x1dGU7aW5zZXQ6MCA4cHggMCAwO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjE4KTtib3JkZXItcmFkaXVzOjE4cHg7b3ZlcmZsb3c6aGlkZGVuO2JveC1zaGFkb3c6dmFyKC0tc2hhZG93KTtiYWNrZ3JvdW5kOiM5Y2I2YmV9Lm1hcENhbnZhc3twb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowfS5tYXBTaGFkZXtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowO3BvaW50ZXItZXZlbnRzOm5vbmU7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoMSw3LDEzLC4wNCkscmdiYSgxLDcsMTMsLjAzKSl9Lm1hcFRvb2xze3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6MTdweDt0b3A6MThweDt6LWluZGV4OjQ7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6OXB4fS5tYXBUb29se3dpZHRoOjQ3cHg7aGVpZ2h0OjQ3cHg7ZGlzcGxheTpncmlkO3BsYWNlLWl0ZW1zOmNlbnRlcjtib3JkZXItcmFkaXVzOjEzcHg7YmFja2dyb3VuZDpyZ2JhKDcsMTksMzEsLjkyKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjksMTE5LDE1NCwuNDIpO2JveC1zaGFkb3c6MCAxMnB4IDI4cHggcmdiYSgwLDAsMCwuMjgpO2NvbG9yOiNlN2Y3ZmZ9Lm1hcFRvb2wuYWN0aXZle2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMGQ5YmMzLCMwMGQ0ZWUpO2JvcmRlci1jb2xvcjojNWFmM2ZmfS5tYXBab29tR3JvdXB7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjttYXJnaW4tdG9wOjRweH0ubWFwWm9vbUdyb3VwIC5tYXBUb29se2JvcmRlci1yYWRpdXM6MH0ubWFwWm9vbUdyb3VwIC5tYXBUb29sOmZpcnN0LWNoaWxke2JvcmRlci1yYWRpdXM6MTNweCAxM3B4IDAgMH0ubWFwWm9vbUdyb3VwIC5tYXBUb29sOmxhc3QtY2hpbGR7Ym9yZGVyLXJhZGl1czowIDAgMTNweCAxM3B4O2JvcmRlci10b3A6MH0uZmlsdGVyQ2hpcHtwb3NpdGlvbjphYnNvbHV0ZTtyaWdodDoyMHB4O3RvcDoyMHB4O3otaW5kZXg6NTtkaXNwbGF5Om5vbmU7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMHB4O3BhZGRpbmc6MTBweCAxMXB4IDEwcHggMTRweDtib3JkZXItcmFkaXVzOjE0cHg7YmFja2dyb3VuZDpyZ2JhKDUsMTYsMjcsLjk0KTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzMsMTI1LDE2MSwuNDIpO2JveC1zaGFkb3c6MCAxNXB4IDM2cHggcmdiYSgwLDAsMCwuMzIpO2ZvbnQtc2l6ZToxMnB4fS5maWx0ZXJDaGlwLnNob3d7ZGlzcGxheTpmbGV4fS5maWx0ZXJDaGlwIGJ1dHRvbnt3aWR0aDozMHB4O2hlaWdodDozMHB4O3BhZGRpbmc6MH0KLnBob3RvTWFya2Vye3Bvc2l0aW9uOnJlbGF0aXZlO3dpZHRoOjU0cHg7aGVpZ2h0OjU0cHg7Ym9yZGVyLXJhZGl1czo1MCU7cGFkZGluZzozcHg7YmFja2dyb3VuZDojZWRmYWZmO2JvcmRlcjozcHggc29saWQgdmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMCAycHggcmdiYSgyNTUsMjU1LDI1NSwuNTUpLDAgMCAyMnB4IHJnYmEoMCwyMTYsMjU1LC42NSk7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTVzIGVhc2V9LnBob3RvTWFya2VyOmhvdmVyLC5waG90b01hcmtlci5hY3RpdmV7dHJhbnNmb3JtOnNjYWxlKDEuMTEpO2JvcmRlci1jb2xvcjp3aGl0ZTtib3gtc2hhZG93OjAgMCAwIDNweCB2YXIoLS1jeWFuKSwwIDAgMjhweCByZ2JhKDAsMjE2LDI1NSwuODUpfS5waG90b01hcmtlciBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmJsb2NrO29iamVjdC1maXQ6Y292ZXI7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDojMTczMTQ5fS5waG90b01hcmtlciAuZmFsbGJhY2t7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlci1yYWRpdXM6NTAlO2JhY2tncm91bmQ6cmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCAzMCUgMzAlLCMzZjgxOWEsIzBhMjYzOSk7Zm9udC13ZWlnaHQ6OTUwfS5tYXJrZXJCYWRnZXtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjUwJTt0b3A6LTE2cHg7dHJhbnNmb3JtOnRyYW5zbGF0ZVgoLTUwJSk7bWluLXdpZHRoOjI4cHg7aGVpZ2h0OjI4cHg7cGFkZGluZzowIDZweDtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlci1yYWRpdXM6OTk5cHg7YmFja2dyb3VuZDojMDcxMzFmO2NvbG9yOiNmZmY7Ym9yZGVyOjJweCBzb2xpZCByZ2JhKDI1NSwyNTUsMjU1LC43Mik7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwO2JveC1zaGFkb3c6MCA1cHggMTVweCByZ2JhKDAsMCwwLC40NSl9Ci5tYXBsaWJyZWdsLXBvcHVwLWNvbnRlbnR7cGFkZGluZzowIWltcG9ydGFudDtiYWNrZ3JvdW5kOnRyYW5zcGFyZW50IWltcG9ydGFudDtib3JkZXItcmFkaXVzOjE4cHghaW1wb3J0YW50O2JveC1zaGFkb3c6bm9uZSFpbXBvcnRhbnR9Lm1hcGxpYnJlZ2wtcG9wdXAtdGlwe2JvcmRlci10b3AtY29sb3I6IzA3MTMxZiFpbXBvcnRhbnR9Lm1hcGxpYnJlZ2wtcG9wdXAtY2xvc2UtYnV0dG9ue3otaW5kZXg6NDtyaWdodDo4cHghaW1wb3J0YW50O3RvcDo4cHghaW1wb3J0YW50O3dpZHRoOjI4cHg7aGVpZ2h0OjI4cHg7Ym9yZGVyLXJhZGl1czo1MCUhaW1wb3J0YW50O2JhY2tncm91bmQ6cmdiYSg4LDIwLDMzLC44MikhaW1wb3J0YW50O2NvbG9yOndoaXRlIWltcG9ydGFudDtmb250LXNpemU6MThweCFpbXBvcnRhbnQ7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDI1NSwyNTUsMjU1LC4yMikhaW1wb3J0YW50fS5zdG9wUG9wdXB7d2lkdGg6MzMwcHg7Ym9yZGVyLXJhZGl1czoxOHB4O292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOiMwNzEzMWY7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuNDIpO2JveC1zaGFkb3c6MCAwIDQwcHggcmdiYSgwLDIxNiwyNTUsLjI1KSwwIDI1cHggNjVweCByZ2JhKDAsMCwwLC40OCl9LnN0b3BQb3B1cEltYWdle2hlaWdodDoxODVweDtiYWNrZ3JvdW5kOiMxMDJhNDB9LnN0b3BQb3B1cEltYWdlIGltZ3t3aWR0aDoxMDAlO2hlaWdodDoxMDAlO2Rpc3BsYXk6YmxvY2s7b2JqZWN0LWZpdDpjb3Zlcn0uc3RvcFBvcHVwQm9keXtwYWRkaW5nOjEzcHggMTVweCAxNXB4fS5wb3B1cEtpY2tlcntkaXNwbGF5OmlubGluZS1mbGV4O3BhZGRpbmc6NXB4IDhweDtib3JkZXItcmFkaXVzOjhweDtiYWNrZ3JvdW5kOnJnYmEoMCwyMTYsMjU1LC4xNSk7Y29sb3I6dmFyKC0tY3lhbik7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6OTAwfS5wb3B1cFRpdGxle21hcmdpbi10b3A6OXB4O2ZvbnQtc2l6ZToxOXB4O2ZvbnQtd2VpZ2h0Ojk1MH0ucG9wdXBNZXRhe21hcmdpbi10b3A6NnB4O2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTJweH0ucG9wdXBCdXR0b25ze2Rpc3BsYXk6ZmxleDtnYXA6OHB4O21hcmdpbi10b3A6MTJweH0ucG9wdXBCdXR0b25zIGJ1dHRvbntoZWlnaHQ6NDBweDtmbGV4OjE7Zm9udC1zaXplOjEycHh9LnBvcHVwQnV0dG9ucyAuZGFuZ2Vye2ZsZXg6MCAwIDQycHg7Y29sb3I6dmFyKC0tcmVkKX0KLm1lZGlhU3RyaXB7bWluLXdpZHRoOjA7cGFkZGluZzoxM3B4IDE3cHggMTVweDtib3JkZXItdG9wOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMTIpO2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDE4MGRlZyxyZ2JhKDQsMTIsMjAsLjcyKSxyZ2JhKDMsOSwxNiwuOTUpKX0ubWVkaWFIZWFkZXJ7aGVpZ2h0OjMxcHg7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTFweH0ubWVkaWFUaXRsZXtmb250LXNpemU6MTRweDtmb250LXdlaWdodDo5NTB9Lm1lZGlhQ291bnR7Zm9udC1zaXplOjEycHg7Y29sb3I6dmFyKC0tbXV0ZWQpfS5tZWRpYUhlYWRlclNwYWNlcntmbGV4OjF9LnRpbnlCdXR0b257d2lkdGg6MzFweDtoZWlnaHQ6MzFweDtwYWRkaW5nOjA7Ym9yZGVyLXJhZGl1czoxMHB4fS5nYWxsZXJ5e2hlaWdodDoxNjRweDtkaXNwbGF5OmZsZXg7Z2FwOjEwcHg7b3ZlcmZsb3cteDphdXRvO292ZXJmbG93LXk6aGlkZGVuO3BhZGRpbmc6OHB4IDFweCA0cHg7c2Nyb2xsYmFyLXdpZHRoOnRoaW59Lm1lZGlhVGlsZXtwb3NpdGlvbjpyZWxhdGl2ZTtmbGV4OjAgMCAyMThweDtoZWlnaHQ6MTQ1cHg7Ym9yZGVyLXJhZGl1czoxM3B4O292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOiMxMDIyMzU7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDcxLDEyMywxNjAsLjM1KTtjdXJzb3I6cG9pbnRlcjt0cmFuc2l0aW9uOi4xNnMgZWFzZX0ubWVkaWFUaWxlOmhvdmVyLC5tZWRpYVRpbGUuYWN0aXZle2JvcmRlci1jb2xvcjp2YXIoLS1jeWFuKTtib3gtc2hhZG93OjAgMCAyMXB4IHJnYmEoMCwyMTYsMjU1LC4yNCk7dHJhbnNmb3JtOnRyYW5zbGF0ZVkoLTJweCl9Lm1lZGlhVGlsZSBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtvYmplY3QtZml0OmNvdmVyO2Rpc3BsYXk6YmxvY2t9Lm1lZGlhVGlsZU5hbWV7cG9zaXRpb246YWJzb2x1dGU7bGVmdDowO3JpZ2h0OjA7Ym90dG9tOjA7cGFkZGluZzoyNXB4IDEwcHggOXB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KHRyYW5zcGFyZW50LHJnYmEoMSw2LDExLC45KSk7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6ODUwO3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30KLnJpZ2h0UmFpbHttaW4td2lkdGg6MDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSg0LDEyLDIxLC45NykscmdiYSgyLDgsMTUsLjk5KSk7Ym9yZGVyLWxlZnQ6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4xNCk7cGFkZGluZzoxNXB4IDE1cHggMTdweDtkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO292ZXJmbG93OmhpZGRlbn0ucmlnaHRUb3B7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtoZWlnaHQ6NDBweH0ucmlnaHRUaXRsZXtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5NTA7dGV4dC10cmFuc2Zvcm06dXBwZXJjYXNlO2xldHRlci1zcGFjaW5nOi4wNGVtfS5yaWdodENvdW50e2NvbG9yOnZhcigtLW11dGVkKTttYXJnaW4tbGVmdDo1cHh9LnJpZ2h0U2VhcmNoe21hcmdpbi1sZWZ0OmF1dG87d2lkdGg6MzVweDtoZWlnaHQ6MzVweDtwYWRkaW5nOjA7YmFja2dyb3VuZDp0cmFuc3BhcmVudDtib3JkZXI6MDtib3gtc2hhZG93Om5vbmV9LnN0b3BTZWFyY2hXcmFwe2Rpc3BsYXk6bm9uZTttYXJnaW4tYm90dG9tOjEwcHh9LnN0b3BTZWFyY2hXcmFwLnNob3d7ZGlzcGxheTpibG9ja30uc3RvcExpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6OXB4O292ZXJmbG93OmF1dG87bWluLWhlaWdodDoyNTBweDtmbGV4OjEgMSAwO3BhZGRpbmc6MnB4IDRweCAxMnB4IDB9LnN0b3BDYXJke2ZsZXg6MCAwIGF1dG87bWluLWhlaWdodDo3NnB4O2JvcmRlci1yYWRpdXM6MTNweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgxMywyOCw0NCwuOTYpLHJnYmEoOCwyMCwzMywuOTYpKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjEsMTA4LDE0MywuMzQpO292ZXJmbG93OmhpZGRlbjt0cmFuc2l0aW9uOi4xNXMgZWFzZX0uc3RvcENhcmQ6aG92ZXIsLnN0b3BDYXJkLmFjdGl2ZXtib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzppbnNldCA0cHggMCAwIHZhcigtLWN5YW4pLDAgMCAxOHB4IHJnYmEoMCwyMTYsMjU1LC4xMyl9LnN0b3BTdW1tYXJ5e21pbi1oZWlnaHQ6NzZweDtwYWRkaW5nOjEycHggMTJweDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjMxcHggbWlubWF4KDAsMWZyKSAyMnB4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTBweDtjdXJzb3I6cG9pbnRlcn0uc3RvcE51bWJlcnt3aWR0aDoyOXB4O2hlaWdodDoyOXB4O2JvcmRlci1yYWRpdXM6OTk5cHg7ZGlzcGxheTpncmlkO3BsYWNlLWl0ZW1zOmNlbnRlcjtiYWNrZ3JvdW5kOnJnYmEoMCwyMTYsMjU1LC4xMik7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzUpO2ZvbnQtc2l6ZToxMnB4O2ZvbnQtd2VpZ2h0Ojk1MDt0ZXh0LWFsaWduOmNlbnRlcn0uc3RvcE5hbWV7Zm9udC1zaXplOjEzcHg7Zm9udC13ZWlnaHQ6OTUwO3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30uc3RvcE1ldGF7bWFyZ2luLXRvcDo1cHg7Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxMC41cHg7bGluZS1oZWlnaHQ6MS4zNX0uc3RvcENoZXZyb257Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxOHB4O3RyYW5zaXRpb246LjE1c30uc3RvcENhcmQub3BlbiAuc3RvcENoZXZyb257dHJhbnNmb3JtOnJvdGF0ZSg5MGRlZyl9LnN0b3BDb250cm9sc3tkaXNwbGF5Om5vbmU7cGFkZGluZzowIDEycHggMTJweCA1M3B4O2dhcDo2cHg7ZmxleC13cmFwOndyYXB9LnN0b3BDYXJkLm9wZW4gLnN0b3BDb250cm9sc3tkaXNwbGF5OmZsZXh9LnN0b3BDb250cm9scyBidXR0b257aGVpZ2h0OjMycHg7cGFkZGluZzowIDlweDtmb250LXNpemU6MTBweH0uYWRkU3RvcEJ1dHRvbntmbGV4OjAgMCBhdXRvO2hlaWdodDo0MnB4O3dpZHRoOjEwMCU7bWFyZ2luOjRweCAwIDEycHh9LmFzc2V0QnViYmxle3dpZHRoOjUycHg7aGVpZ2h0OjUycHg7Ym9yZGVyLXJhZGl1czo1MCU7b3ZlcmZsb3c6aGlkZGVuO2JvcmRlcjozcHggc29saWQgIzAwZDhmZjtiYWNrZ3JvdW5kOiMwNjExMWQ7Ym94LXNoYWRvdzowIDAgMCAzcHggcmdiYSg0LDE3LDI4LC45MiksMCAwIDIycHggcmdiYSgwLDIxNiwyNTUsLjUyKTtjdXJzb3I6cG9pbnRlcjt0cmFuc2l0aW9uOi4xNnN9LmFzc2V0QnViYmxlOmhvdmVyLC5hc3NldEJ1YmJsZS5hY3RpdmV7dHJhbnNmb3JtOnNjYWxlKDEuMTIpO2JvcmRlci1jb2xvcjp3aGl0ZTt6LWluZGV4OjE1fS5hc3NldEJ1YmJsZSBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmJsb2NrO29iamVjdC1maXQ6Y292ZXJ9LmFzc2V0QnViYmxlIC5hc3NldERvdHt3aWR0aDoxMDAlO2hlaWdodDoxMDAlO2Rpc3BsYXk6Z3JpZDtwbGFjZS1pdGVtczpjZW50ZXI7Y29sb3I6dmFyKC0tY3lhbik7Zm9udC1zaXplOjE5cHh9Ci5leHBvcnRCb3h7ZmxleDowIDAgYXV0bztib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjIsMTExLDE0OCwuMzApO2JvcmRlci1yYWRpdXM6MTRweDtiYWNrZ3JvdW5kOnJnYmEoOCwxOSwzMSwuOTApO292ZXJmbG93OmhpZGRlbn0uZXhwb3J0SGVhZGVye2hlaWdodDo0OHB4O3BhZGRpbmc6MCAxM3B4O2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OnNwYWNlLWJldHdlZW47Zm9udC1zaXplOjEzcHg7Zm9udC13ZWlnaHQ6OTUwO2N1cnNvcjpwb2ludGVyfS5leHBvcnRCb2R5e3BhZGRpbmc6MCAxMnB4IDEycHh9LmV4cG9ydEJveC5jb2xsYXBzZWQgLmV4cG9ydEJvZHl7ZGlzcGxheTpub25lfS5leHBvcnRUYWJze2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLWNvbHVtbnM6MWZyIDFmciAxZnI7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDYzLDExMywxNTAsLjMzKTtib3JkZXItcmFkaXVzOjEwcHg7b3ZlcmZsb3c6aGlkZGVuO21hcmdpbjo3cHggMCAxMnB4fS5leHBvcnRUYWJzIGJ1dHRvbntib3JkZXI6MDtib3JkZXItcmFkaXVzOjA7aGVpZ2h0OjM2cHg7YmFja2dyb3VuZDojMDcxMzFmO2ZvbnQtc2l6ZToxMHB4fS5leHBvcnRUYWJzIGJ1dHRvbi5hY3RpdmV7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCMwODc5YzMsIzAwYTljOSk7Ym94LXNoYWRvdzpub25lfS5maWVsZExhYmVse2Rpc3BsYXk6YmxvY2s7Zm9udC1zaXplOjEwcHg7Y29sb3I6dmFyKC0tbXV0ZWQpO21hcmdpbjoxMHB4IDAgNXB4fS5hdWRpb1Jvd3tkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuO2NvbG9yOnZhcigtLXNvZnQpO2ZvbnQtc2l6ZToxMXB4fS5zd2l0Y2h7d2lkdGg6MzlweDtoZWlnaHQ6MjFweDtib3JkZXItcmFkaXVzOjk5OXB4O2JhY2tncm91bmQ6IzIwMzc0YTtib3JkZXI6MXB4IHNvbGlkICMzNTUzNmE7cG9zaXRpb246cmVsYXRpdmU7Y3Vyc29yOnBvaW50ZXJ9LnN3aXRjaDphZnRlcntjb250ZW50OiIiO3Bvc2l0aW9uOmFic29sdXRlO3RvcDoycHg7bGVmdDoycHg7d2lkdGg6MTVweDtoZWlnaHQ6MTVweDtib3JkZXItcmFkaXVzOjUwJTtiYWNrZ3JvdW5kOiNkY2VhZjQ7dHJhbnNpdGlvbjouMTZzfS5zd2l0Y2gub257YmFja2dyb3VuZDojMDBhOWNlO2JvcmRlci1jb2xvcjojMjBlMWZmfS5zd2l0Y2gub246YWZ0ZXJ7bGVmdDoyMHB4fS5hdWRpb0lucHV0e2Rpc3BsYXk6bm9uZX0ucmVuZGVyQnV0dG9ue3dpZHRoOjEwMCU7aGVpZ2h0OjU1cHg7bWFyZ2luLXRvcDoxMXB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMDg3ZGEzLCMxMWJhY2UpO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuNzUpO2ZvbnQtc2l6ZToxNHB4fS5yZW5kZXJCdXR0b24gc3BhbntkaXNwbGF5OmJsb2NrO2ZvbnQtc2l6ZToxMHB4O2ZvbnQtd2VpZ2h0OjY1MDtvcGFjaXR5Oi44NTttYXJnaW4tdG9wOjJweH0KLm1vZGFse3Bvc2l0aW9uOmZpeGVkO2luc2V0OjA7ei1pbmRleDoxMDAwO2Rpc3BsYXk6bm9uZTthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OmNlbnRlcjtwYWRkaW5nOjI0cHg7YmFja2dyb3VuZDpyZ2JhKDAsNCw5LC43NSk7YmFja2Ryb3AtZmlsdGVyOmJsdXIoN3B4KX0ubW9kYWwuc2hvd3tkaXNwbGF5OmZsZXh9Lm1vZGFsQ2FyZHt3aWR0aDptaW4oNzIwcHgsOTR2dyk7bWF4LWhlaWdodDo5MHZoO292ZXJmbG93OmF1dG87cGFkZGluZzoyMXB4O2JvcmRlci1yYWRpdXM6MTlweDtiYWNrZ3JvdW5kOiMwNzEzMWY7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzUpO2JveC1zaGFkb3c6MCAwIDYwcHggcmdiYSgwLDIxNiwyNTUsLjE4KSwwIDM1cHggMTAwcHggcmdiYSgwLDAsMCwuNTUpfS5tb2RhbFRpdGxle2ZvbnQtc2l6ZToyMXB4O2ZvbnQtd2VpZ2h0Ojk1MDttYXJnaW4tYm90dG9tOjE1cHh9LmZvcm1Hcmlke2Rpc3BsYXk6Z3JpZDtnYXA6MTFweH0udHdvQ29se2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLWNvbHVtbnM6MWZyIDFmcjtnYXA6MTFweH0ubW9kYWxBY3Rpb25ze2Rpc3BsYXk6ZmxleDtqdXN0aWZ5LWNvbnRlbnQ6ZmxleC1lbmQ7Z2FwOjlweDttYXJnaW4tdG9wOjZweH0ubW9kYWxBY3Rpb25zIGJ1dHRvbntoZWlnaHQ6NDJweDtwYWRkaW5nOjAgMTZweH0ucHJpbWFyeXtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxMzVkZWcsIzA3NWRiNCwjMDBhZWNiKTtib3JkZXItY29sb3I6dmFyKC0tY3lhbil9Ci50b2FzdHtwb3NpdGlvbjpmaXhlZDtsZWZ0OjMwNXB4O2JvdHRvbToxOHB4O3otaW5kZXg6MzAwMDtkaXNwbGF5Om5vbmU7cGFkZGluZzoxMXB4IDE0cHg7Ym9yZGVyLXJhZGl1czoxMnB4O2JhY2tncm91bmQ6cmdiYSg2LDE5LDMxLC45NSk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzIpO2JveC1zaGFkb3c6MCAxNXB4IDQwcHggcmdiYSgwLDAsMCwuMzUpO2ZvbnQtc2l6ZToxMnB4fS50b2FzdC5zaG93e2Rpc3BsYXk6YmxvY2t9Ci5wcmVzZW50T3ZlcmxheXtwb3NpdGlvbjpmaXhlZDtpbnNldDowO3otaW5kZXg6MjIwMDtkaXNwbGF5Om5vbmU7YmFja2dyb3VuZDojMDIwNzEwfS5wcmVzZW50T3ZlcmxheS5zaG93e2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLXJvd3M6NzJweCBtaW5tYXgoMCwxZnIpIDE3MHB4fS5wcmVzZW50SGVhZGVye2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjEzcHg7cGFkZGluZzoxMHB4IDE4cHg7Ym9yZGVyLWJvdHRvbToxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjE2KTtiYWNrZ3JvdW5kOnJnYmEoMywxMCwxOCwuOTApfS5wcmVzZW50SGVhZGVyVGl0bGV7Zm9udC1zaXplOjIwcHg7Zm9udC13ZWlnaHQ6OTUwfS5wcmVzZW50SGVhZGVyTWV0YXtjb2xvcjp2YXIoLS1tdXRlZCk7Zm9udC1zaXplOjExcHg7bWFyZ2luLXRvcDozcHh9LnByZXNlbnRIZWFkZXJTcGFjZXJ7ZmxleDoxfS5wcmVzZW50TWFpbntwb3NpdGlvbjpyZWxhdGl2ZTttaW4taGVpZ2h0OjB9LnByZXNlbnRNYXB7cG9zaXRpb246YWJzb2x1dGU7aW5zZXQ6MH0ucHJlc2VudFN0b3BSYWlse3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6MThweDt0b3A6MThweDtib3R0b206MThweDt3aWR0aDoyNDBweDt6LWluZGV4OjQ7cGFkZGluZzoxMnB4O2JvcmRlci1yYWRpdXM6MTZweDtiYWNrZ3JvdW5kOnJnYmEoNCwxNCwyNCwuODQpO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjI0KTtiYWNrZHJvcC1maWx0ZXI6Ymx1cigxNXB4KTtvdmVyZmxvdzphdXRvfS5wcmVzZW50U3RvcEl0ZW17cGFkZGluZzoxMHB4O2JvcmRlci1yYWRpdXM6MTBweDtjb2xvcjojYjRjOGQ4O2ZvbnQtc2l6ZToxMnB4O2N1cnNvcjpwb2ludGVyfS5wcmVzZW50U3RvcEl0ZW0uYWN0aXZle2JhY2tncm91bmQ6cmdiYSgwLDIxNiwyNTUsLjE0KTtjb2xvcjp3aGl0ZTtib3gtc2hhZG93Omluc2V0IDNweCAwIDAgdmFyKC0tY3lhbil9LnByZXNlbnRTdG9wQmFubmVye3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6NTAlO3RvcDoxOHB4O3RyYW5zZm9ybTp0cmFuc2xhdGVYKC01MCUpO3otaW5kZXg6NzttaW4td2lkdGg6NDIwcHg7bWF4LXdpZHRoOjcyMHB4O3BhZGRpbmc6MTRweCAyMHB4O2JvcmRlci1yYWRpdXM6MTdweDtiYWNrZ3JvdW5kOnJnYmEoNCwxNCwyNCwuODgpO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjMwKTtib3gtc2hhZG93OjAgMjJweCA1NXB4IHJnYmEoMCwwLDAsLjQyKSwwIDAgMzBweCByZ2JhKDAsMjE2LDI1NSwuMTIpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDE1cHgpO3RleHQtYWxpZ246Y2VudGVyfS5wcmVzZW50U3RvcEJhbm5lclRpdGxle2ZvbnQtc2l6ZToyNHB4O2ZvbnQtd2VpZ2h0Ojk1MH0ucHJlc2VudFN0b3BCYW5uZXJSYW5nZXttYXJnaW4tdG9wOjRweDtjb2xvcjojYjhjY2RhO2ZvbnQtc2l6ZToxMnB4fS5wcmVzZW50UGhvdG9DYXJke3Bvc2l0aW9uOmFic29sdXRlO3JpZ2h0OjIycHg7dG9wOjk2cHg7d2lkdGg6bWluKDQ4MHB4LDM4dncpO21heC1oZWlnaHQ6Y2FsYygxMDAlIC0gMTgwcHgpO3otaW5kZXg6ODtib3JkZXItcmFkaXVzOjE4cHg7b3ZlcmZsb3c6aGlkZGVuO2JhY2tncm91bmQ6cmdiYSg1LDE1LDI1LC45Nyk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzgpO2JveC1zaGFkb3c6MCAwIDQycHggcmdiYSgwLDIxNiwyNTUsLjIwKSwwIDI1cHggNjBweCByZ2JhKDAsMCwwLC41KTtkaXNwbGF5Om5vbmV9LnByZXNlbnRQaG90b0NhcmQuc2hvd3tkaXNwbGF5OmJsb2NrfS5wcmVzZW50UGhvdG9DYXJkIGltZ3t3aWR0aDoxMDAlO21heC1oZWlnaHQ6NTZ2aDtvYmplY3QtZml0OmNvbnRhaW47ZGlzcGxheTpibG9jaztiYWNrZ3JvdW5kOiMwMTA0MDl9LnByZXNlbnRQaG90b0JvZHl7cGFkZGluZzoxNHB4IDE2cHh9LnByZXNlbnRQaG90b1RpdGxle2ZvbnQtc2l6ZToxNnB4O2ZvbnQtd2VpZ2h0Ojk1MDt3aGl0ZS1zcGFjZTpub3dyYXA7b3ZlcmZsb3c6aGlkZGVuO3RleHQtb3ZlcmZsb3c6ZWxsaXBzaXN9LnByZXNlbnRQaG90b01ldGF7Y29sb3I6I2Q1ZTdmMTtmb250LXNpemU6MTNweDttYXJnaW4tdG9wOjZweDtsZXR0ZXItc3BhY2luZzouMDJlbX0ucHJlc2VudFBob3RvQ29vcmRze2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTFweDttYXJnaW4tdG9wOjdweDtsaW5lLWhlaWdodDoxLjV9LnByZXNlbnRQaG90b0FjdGlvbnN7ZGlzcGxheTpmbGV4O2dhcDo4cHg7bWFyZ2luLXRvcDoxMnB4fS5wcmVzZW50UGhvdG9BY3Rpb25zIGJ1dHRvbntoZWlnaHQ6MzhweDtwYWRkaW5nOjAgMTJweDtmb250LXNpemU6MTFweH0ucHJlc2VudFBob3RvQWN0aW9ucyAuZGFuZ2Vye21hcmdpbi1sZWZ0OmF1dG87Y29sb3I6I2ZmZGJlMTtib3JkZXItY29sb3I6cmdiYSgyNTUsNzcsMTAyLC41NSk7YmFja2dyb3VuZDpyZ2JhKDEwNSwyMCwzOCwuNzIpfS5wcmVzZW50SHVke3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6NTAlO2JvdHRvbToxOHB4O3RyYW5zZm9ybTp0cmFuc2xhdGVYKC01MCUpO3otaW5kZXg6NjtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDo4cHg7cGFkZGluZzo4cHg7Ym9yZGVyLXJhZGl1czoxNnB4O2JhY2tncm91bmQ6cmdiYSg0LDE0LDI0LC44Nik7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMjIpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDEycHgpfS5wcmVzZW50SHVkIGJ1dHRvbntoZWlnaHQ6NDJweDtwYWRkaW5nOjAgMTRweDtmb250LXNpemU6MTFweH0ucHJlc2VudEh1ZCAucGxheXttaW4td2lkdGg6MTEwcHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCM2MDNjZmYsIzAwYWRjYil9LnByZXNlbnRCYWNre3dpZHRoOjQ2cHg7aGVpZ2h0OjQ2cHg7Ym9yZGVyLXJhZGl1czoxNHB4O2ZvbnQtc2l6ZToyMXB4O3BhZGRpbmc6MH0ucHJlc2VudEhlYWRlckFjdGlvbntoZWlnaHQ6NDJweDtwYWRkaW5nOjAgMTNweDtmb250LXNpemU6MTFweH0uZm9jdXNQdWxzZXt3aWR0aDozNHB4O2hlaWdodDozNHB4O2JvcmRlci1yYWRpdXM6NTAlO2JvcmRlcjozcHggc29saWQgd2hpdGU7YmFja2dyb3VuZDpyZ2JhKDAsMjE2LDI1NSwuMjIpO2JveC1zaGFkb3c6MCAwIDAgN3B4IHJnYmEoMCwyMTYsMjU1LC4yMCksMCAwIDMwcHggcmdiYSgwLDIxNiwyNTUsLjk1KTtwb2ludGVyLWV2ZW50czpub25lO2FuaW1hdGlvbjpmb2N1c1B1bHNlIDEuOHMgZWFzZS1pbi1vdXQgaW5maW5pdGV9Lm1lZGlhVGlsZVJlbW92ZXtwb3NpdGlvbjphYnNvbHV0ZTtyaWdodDo3cHg7dG9wOjdweDt6LWluZGV4OjM7d2lkdGg6MzBweDtoZWlnaHQ6MzBweDtwYWRkaW5nOjA7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDpyZ2JhKDcsMTksMzEsLjg4KTtib3JkZXItY29sb3I6cmdiYSgyNTUsMjU1LDI1NSwuMjgpO2ZvbnQtc2l6ZToxNnB4O2NvbG9yOiNmZmRiZTF9Lm1lZGlhVGlsZVJlbW92ZTpob3Zlcntib3JkZXItY29sb3I6dmFyKC0tcmVkKTtib3gtc2hhZG93OjAgMCAxNnB4IHJnYmEoMjU1LDc3LDEwMiwuMzUpfUBrZXlmcmFtZXMgZm9jdXNQdWxzZXswJSwxMDAle3RyYW5zZm9ybTpzY2FsZSguOTIpO29wYWNpdHk6Ljc1fTUwJXt0cmFuc2Zvcm06c2NhbGUoMS4wOCk7b3BhY2l0eToxfX0ucHJlc2VudEZpbG1zdHJpcHtwYWRkaW5nOjEycHggMThweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcsIzA2MTExZCwjMDIwNzExKTtib3JkZXItdG9wOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMTQpO2Rpc3BsYXk6ZmxleDtnYXA6MTBweDtvdmVyZmxvdy14OmF1dG99LnByZXNlbnRUaHVtYntmbGV4OjAgMCAxOTBweDtoZWlnaHQ6MTQwcHg7Ym9yZGVyLXJhZGl1czoxM3B4O292ZXJmbG93OmhpZGRlbjtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjksMTIxLDE1OCwuMzQpO2N1cnNvcjpwb2ludGVyO3Bvc2l0aW9uOnJlbGF0aXZlfS5wcmVzZW50VGh1bWIuYWN0aXZle2JvcmRlci1jb2xvcjp2YXIoLS1jeWFuKTtib3gtc2hhZG93OjAgMCAyMXB4IHJnYmEoMCwyMTYsMjU1LC4yOCl9LnByZXNlbnRUaHVtYiBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmJsb2NrO29iamVjdC1maXQ6Y292ZXJ9LnByZXNlbnRUaHVtYkxhYmVse3Bvc2l0aW9uOmFic29sdXRlO2luc2V0OmF1dG8gMCAwO3BhZGRpbmc6MjRweCA4cHggN3B4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KHRyYW5zcGFyZW50LHJnYmEoMCwwLDAsLjg1KSk7Zm9udC1zaXplOjEwcHg7Zm9udC13ZWlnaHQ6ODAwfQpAbWVkaWEobWF4LXdpZHRoOjEzMDBweCl7LmFwcFNoZWxse2dyaWQtdGVtcGxhdGUtY29sdW1uczoyNTBweCBtaW5tYXgoNTgwcHgsMWZyKSAzMjBweH0ubGVmdFJhaWx7cGFkZGluZy1sZWZ0OjEzcHg7cGFkZGluZy1yaWdodDoxM3B4fS53b3JkbWFya3tmb250LXNpemU6MjdweH0ucHJlc2VudEJ1dHRvbnttaW4td2lkdGg6MjIwcHh9LnRpdGxlQXJlYXttaW4td2lkdGg6MjQwcHh9LnRvcEFjdGlvbnttaW4td2lkdGg6MTEwcHh9Lm1lZGlhVGlsZXtmbGV4LWJhc2lzOjE4NXB4fX0KPC9zdHlsZT4KPHN0eWxlIGlkPSJUUklQUFlfVjEwM19TVFlMRSI+Ci8qIFRyaXBweSB2MTAuMy4wIGpvdXJuZXkgaGllcmFyY2h5ICovCi52MTAzSGlkZGVue2Rpc3BsYXk6bm9uZSFpbXBvcnRhbnR9Ci5yaWdodFJhaWx7cGFkZGluZzoxOHB4IDE2cHghaW1wb3J0YW50fQouam91cm5leUFjdGlvbnN7ZGlzcGxheTpncmlkO2dyaWQtdGVtcGxhdGUtY29sdW1uczpyZXBlYXQoNCxtaW5tYXgoMCwxZnIpKTtnYXA6N3B4O21hcmdpbjoxMHB4IDAgMTJweH0KLmpvdXJuZXlBY3Rpb25zIGJ1dHRvbntoZWlnaHQ6MzhweDtwYWRkaW5nOjAgN3B4O2ZvbnQtc2l6ZToxMHB4O2JvcmRlci1yYWRpdXM6MTFweH0KLmpvdXJuZXlBY3Rpb25zIGJ1dHRvbi5hY3RpdmV7Ym9yZGVyLWNvbG9yOnZhcigtLWN5YW4pO2JhY2tncm91bmQ6cmdiYSgwLDIxNiwyNTUsLjE2KTtib3gtc2hhZG93OjAgMCAxOHB4IHJnYmEoMCwyMTYsMjU1LC4xOCl9Ci5qb3VybmV5QWN0aW9ucyBidXR0b246ZGlzYWJsZWR7b3BhY2l0eTouMzg7Y3Vyc29yOm5vdC1hbGxvd2VkO3RyYW5zZm9ybTpub25lO2JveC1zaGFkb3c6bm9uZX0KLmpvdXJuZXlNb3JlTWVudXtkaXNwbGF5Om5vbmU7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjFmcjtnYXA6N3B4O21hcmdpbjotNHB4IDAgMTJweDtwYWRkaW5nOjEwcHg7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDgwLDEyNiwxNTgsLjI1KTtib3JkZXItcmFkaXVzOjEzcHg7YmFja2dyb3VuZDpyZ2JhKDUsMTUsMjUsLjg4KX0KLmpvdXJuZXlNb3JlTWVudS5zaG93e2Rpc3BsYXk6Z3JpZH0uam91cm5leU1vcmVNZW51IGJ1dHRvbntoZWlnaHQ6MzhweDtmb250LXNpemU6MTFweH0KLmRheUxpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6MTFweDttaW4taGVpZ2h0OjA7b3ZlcmZsb3c6YXV0bztwYWRkaW5nLXJpZ2h0OjJweH0KLmRheUNhcmR7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDczLDExNiwxNDYsLjMwKTtib3JkZXItcmFkaXVzOjE2cHg7YmFja2dyb3VuZDpyZ2JhKDcsMTgsMzAsLjcyKTtvdmVyZmxvdzpoaWRkZW47Ym94LXNoYWRvdzowIDEycHggMzBweCByZ2JhKDAsMCwwLC4xOCl9Ci5kYXlDYXJkLm9wZW57Ym9yZGVyLWNvbG9yOnJnYmEoMCwyMTYsMjU1LC4yNil9Ci5kYXlIZWFkZXJ7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTBweDtwYWRkaW5nOjEzcHggMTJweDtjdXJzb3I6cG9pbnRlcjtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgxNSwzNCw1MiwuOTIpLHJnYmEoOCwyMiwzNiwuOTIpKX0KLmRheUhlYWRlcjpob3ZlcntiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgyMCw0NSw2OCwuOTYpLHJnYmEoOSwyNSw0MSwuOTYpKX0KLmRheUluZGV4e3dpZHRoOjMxcHg7aGVpZ2h0OjMxcHg7ZGlzcGxheTpncmlkO3BsYWNlLWl0ZW1zOmNlbnRlcjtib3JkZXItcmFkaXVzOjExcHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCM1ZDNjZmYsIzAwYjdjZSk7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwO2JveC1zaGFkb3c6MCAwIDE4cHggcmdiYSgwLDIxNiwyNTUsLjE4KX0KLmRheVRpdGxlV3JhcHttaW4td2lkdGg6MDtmbGV4OjF9LmRheVRpdGxle2ZvbnQtd2VpZ2h0Ojk1MDtmb250LXNpemU6MTNweDt3aGl0ZS1zcGFjZTpub3dyYXA7b3ZlcmZsb3c6aGlkZGVuO3RleHQtb3ZlcmZsb3c6ZWxsaXBzaXN9LmRheU1ldGF7Zm9udC1zaXplOjEwcHg7Y29sb3I6dmFyKC0tbXV0ZWQpO21hcmdpbi10b3A6NHB4fS5kYXlSZW5hbWV7d2lkdGg6MzFweDtoZWlnaHQ6MzFweDtwYWRkaW5nOjA7Ym9yZGVyLXJhZGl1czoxMHB4O2ZvbnQtc2l6ZToxMnB4fS5kYXlDaGV2cm9ue2ZvbnQtc2l6ZToxM3B4O3RyYW5zaXRpb246LjE4c30uZGF5Q2FyZDpub3QoLm9wZW4pIC5kYXlDaGV2cm9ue3RyYW5zZm9ybTpyb3RhdGUoLTkwZGVnKX0KLmRheUJvZHl7ZGlzcGxheTpub25lO3BhZGRpbmc6OXB4O2dhcDo4cHh9LmRheUNhcmQub3BlbiAuZGF5Qm9keXtkaXNwbGF5OmdyaWR9Ci5qb3VybmV5SXRlbXtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjgsMTA4LDEzOCwuMjQpO2JvcmRlci1yYWRpdXM6MTNweDtiYWNrZ3JvdW5kOnJnYmEoMTAsMjUsNDAsLjgyKTtvdmVyZmxvdzpoaWRkZW47dHJhbnNpdGlvbjouMTZzfQouam91cm5leUl0ZW06aG92ZXIsLmpvdXJuZXlJdGVtLmFjdGl2ZXtib3JkZXItY29sb3I6cmdiYSgwLDIxNiwyNTUsLjYyKTtib3gtc2hhZG93OjAgMCAyMHB4IHJnYmEoMCwyMTYsMjU1LC4xMil9Ci5qb3VybmV5SXRlbS5zZWdtZW50e2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZyxyZ2JhKDI5LDI3LDYxLC44MikscmdiYSg4LDMxLDQ0LC44OCkpfQouam91cm5leUl0ZW1NYWlue2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjEwcHg7cGFkZGluZzoxMXB4O2N1cnNvcjpwb2ludGVyfQouaXRlbUJhZGdle3dpZHRoOjMxcHg7aGVpZ2h0OjMxcHg7ZmxleDowIDAgMzFweDtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlci1yYWRpdXM6NTAlO2ZvbnQtc2l6ZToxMXB4O2ZvbnQtd2VpZ2h0Ojk1MDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxMzVkZWcsIzAwYzhlZCwjMjQ3Y2ZmKTtib3gtc2hhZG93OjAgMCAxNXB4IHJnYmEoMCwyMTYsMjU1LC4yOCl9Ci5pdGVtQmFkZ2UuZHJpdmV7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCNmZjhhMjgsI2ZmNGQ3ZSl9Lml0ZW1CYWRnZS5oaWtle2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjNDNkMTdjLCMwMGE4YTgpfS5pdGVtQmFkZ2UuY3VzdG9te2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjNzc1NmZmLCNkODVjZmYpfQouaXRlbVRleHR7bWluLXdpZHRoOjA7ZmxleDoxfS5pdGVtTmFtZXtmb250LXNpemU6MTJweDtmb250LXdlaWdodDo5MDA7d2hpdGUtc3BhY2U6bm93cmFwO292ZXJmbG93OmhpZGRlbjt0ZXh0LW92ZXJmbG93OmVsbGlwc2lzfS5pdGVtTWV0YXtmb250LXNpemU6OS41cHg7Y29sb3I6IzlkYjJjMzttYXJnaW4tdG9wOjRweDt3aGl0ZS1zcGFjZTpub3dyYXA7b3ZlcmZsb3c6aGlkZGVuO3RleHQtb3ZlcmZsb3c6ZWxsaXBzaXN9LnNlZ21lbnRNZW1iZXJze2ZvbnQtc2l6ZTo5cHg7Y29sb3I6IzZmZGNmMDttYXJnaW4tdG9wOjVweDt3aGl0ZS1zcGFjZTpub3dyYXA7b3ZlcmZsb3c6aGlkZGVuO3RleHQtb3ZlcmZsb3c6ZWxsaXBzaXN9Lml0ZW1DaGV2cm9ue2NvbG9yOiM4YmEyYjN9Ci5pdGVtQ29udHJvbHN7ZGlzcGxheTpub25lO2dhcDo2cHg7cGFkZGluZzowIDEwcHggMTBweDtib3JkZXItdG9wOjFweCBzb2xpZCByZ2JhKDc1LDExOSwxNTAsLjE4KTtwYWRkaW5nLXRvcDo5cHh9LmpvdXJuZXlJdGVtLmFjdGl2ZSAuaXRlbUNvbnRyb2xzLC5qb3VybmV5SXRlbTpob3ZlciAuaXRlbUNvbnRyb2xze2Rpc3BsYXk6ZmxleDtmbGV4LXdyYXA6d3JhcH0uaXRlbUNvbnRyb2xzIGJ1dHRvbntoZWlnaHQ6MzFweDtwYWRkaW5nOjAgOXB4O2ZvbnQtc2l6ZTo5LjVweDtib3JkZXItcmFkaXVzOjlweH0KLnN0b3BDaGVja3t3aWR0aDoyNXB4O2hlaWdodDoyNXB4O3BhZGRpbmc6MDtmbGV4OjAgMCAyNXB4O2JvcmRlci1yYWRpdXM6OHB4O2JhY2tncm91bmQ6IzA2MTExZH0uc3RvcENoZWNrLmNoZWNrZWR7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCM2NjNjZmYsIzAwYjljZSk7Ym9yZGVyLWNvbG9yOnZhcigtLWN5YW4pfQoucHJlc2VudERheUxhYmVse21hcmdpbjoxMnB4IDVweCA2cHg7cGFkZGluZzo4cHggOXB4O2JvcmRlci1yYWRpdXM6OXB4O2JhY2tncm91bmQ6cmdiYSgwLDIxNiwyNTUsLjA4KTtib3JkZXItbGVmdDozcHggc29saWQgdmFyKC0tY3lhbik7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6OTUwO2N1cnNvcjpwb2ludGVyfS5wcmVzZW50RGF5TGFiZWwgc3BhbntkaXNwbGF5OmJsb2NrO21hcmdpbi10b3A6M3B4O2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6OXB4O2ZvbnQtd2VpZ2h0OjY1MH0ucHJlc2VudERheUxhYmVsOmhvdmVye2JhY2tncm91bmQ6cmdiYSgwLDIxNiwyNTUsLjE0KX0KLnByZXNlbnRTdG9wSXRlbXttYXJnaW4tbGVmdDo1cHh9LnByZXNlbnRTdG9wSXRlbSAuc21hbGx7bGluZS1oZWlnaHQ6MS40O21hcmdpbi10b3A6M3B4fQojZXhwb3J0Qm94LmNvbGxhcHNlZCAuZXhwb3J0Qm9keXtkaXNwbGF5Om5vbmUhaW1wb3J0YW50fSNleHBvcnRCb3guY29sbGFwc2VkIC5leHBvcnRIZWFkZXIgc3BhbjpsYXN0LWNoaWxke3RyYW5zZm9ybTpyb3RhdGUoMTgwZGVnKX0KQG1lZGlhKG1heC13aWR0aDoxMzUwcHgpey5qb3VybmV5QWN0aW9uc3tncmlkLXRlbXBsYXRlLWNvbHVtbnM6MWZyIDFmcn0uam91cm5leUFjdGlvbnMgYnV0dG9ue2ZvbnQtc2l6ZTo5LjVweH19Cgo8L3N0eWxlPgo8L2hlYWQ+Cjxib2R5Pgo8ZGl2IGNsYXNzPSJhcHBTaGVsbCI+CiAgPGFzaWRlIGNsYXNzPSJsZWZ0UmFpbCI+CiAgICA8ZGl2IGNsYXNzPSJicmFuZExpbmUiPgogICAgICA8ZGl2IGNsYXNzPSJsb2dvRmxvd2VyIj48c3BhbiBjbGFzcz0icGV0YWwgcDEiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDIiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDMiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDQiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDUiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDYiPjwvc3Bhbj48L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0id29yZG1hcmsiPnRyaXBweTwvZGl2PjxkaXYgY2xhc3M9InZlcnNpb24iPnYxMC4zLjA8L2Rpdj4KICAgIDwvZGl2PgogICAgPGJ1dHRvbiBpZD0ibmV3SW1taWNoQnV0dG9uIiBjbGFzcz0ic2lkZVByaW1hcnkiPu+8iyZuYnNwOyBOZXcgSW1taWNoIEpvdXJuZXk8L2J1dHRvbj4KICAgIDxidXR0b24gaWQ9InVwbG9hZEJ1dHRvbiIgY2xhc3M9InNpZGVTZWNvbmRhcnkiPuKHpyZuYnNwOyBVcGxvYWQgTWVkaWE8L2J1dHRvbj4KICAgIDxkaXYgY2xhc3M9InNlY3Rpb25MYWJlbCI+PHNwYW4+UHJvamVjdHM8L3NwYW4+PGJ1dHRvbiBpZD0icHJvamVjdFNlYXJjaEJ1dHRvbiIgY2xhc3M9InByb2plY3RNZW51Ij7ijJU8L2J1dHRvbj48L2Rpdj4KICAgIDxpbnB1dCBpZD0icHJvamVjdFNlYXJjaCIgY2xhc3M9ImhpZGRlbiIgcGxhY2Vob2xkZXI9IlNlYXJjaCBwcm9qZWN0c+KApiI+CiAgICA8ZGl2IGlkPSJwcm9qZWN0TGlzdCIgY2xhc3M9InByb2plY3RMaXN0Ij48L2Rpdj4KICAgIDxkaXYgY2xhc3M9ImxlZnRGb290ZXIiPlBsYW4sIG9yZ2FuaXplLCBhbmQgcmVsaXZlIHlvdXIgYWR2ZW50dXJlcyBvbiB0aGUgbWFwLgogICAgICA8YSBjbGFzcz0iZm9vdGVyTGluayIgaHJlZj0iIyI+4pajJm5ic3A7IERvY3VtZW50YXRpb248L2E+PGEgY2xhc3M9ImZvb3RlckxpbmsiIGhyZWY9IiMiPuKXjiZuYnNwOyBDaGFuZ2Vsb2c8L2E+CiAgICA8L2Rpdj4KICA8L2FzaWRlPgoKICA8bWFpbiBjbGFzcz0id29ya3NwYWNlIj4KICAgIDxoZWFkZXIgY2xhc3M9InRvcEJhciI+CiAgICAgIDxkaXYgY2xhc3M9InRpdGxlQXJlYSI+PGRpdiBjbGFzcz0iam91cm5leVRpdGxlUm93Ij48ZGl2IGlkPSJqb3VybmV5VGl0bGUiIGNsYXNzPSJqb3VybmV5VGl0bGUiPk5vIGpvdXJuZXkgc2VsZWN0ZWQ8L2Rpdj48YnV0dG9uIGlkPSJyZW5hbWVQcm9qZWN0QnV0dG9uIiBjbGFzcz0iZWRpdFRpdGxlIj7inI48L2J1dHRvbj48L2Rpdj48ZGl2IGlkPSJqb3VybmV5TWV0YSIgY2xhc3M9ImpvdXJuZXlNZXRhIj5Mb2FkIG9yIGNyZWF0ZSBhIGpvdXJuZXk8L2Rpdj48L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0idG9wU3BhY2VyIj48L2Rpdj4KICAgICAgPGJ1dHRvbiBpZD0icHJlc2VudEJ1dHRvbiIgY2xhc3M9InByZXNlbnRCdXR0b24iPuKWtiZuYnNwOyBQcmVzZW50IEpvdXJuZXk8c3Bhbj5JbW1lcnNpdmUgcm91dGUgcGxheWJhY2s8L3NwYW4+PC9idXR0b24+CiAgICAgIDxidXR0b24gaWQ9ImV4cG9ydEp1bXBCdXR0b24iIGNsYXNzPSJ0b3BBY3Rpb24iPuKWoyZuYnNwOyBFeHBvcnQ8YnI+PHNwYW4gY2xhc3M9InNtYWxsIj5SZW5kZXIsIEdQWCwgYW5kIG1vcmUmbmJzcDvijIQ8L3NwYW4+PC9idXR0b24+CiAgICAgIDxidXR0b24gaWQ9InNldHRpbmdzQnV0dG9uIiBjbGFzcz0iZ2VhckJ1dHRvbiI+4pqZPC9idXR0b24+CiAgICAgIDxidXR0b24gaWQ9ImFjY291bnRCdXR0b24iIGNsYXNzPSJ0b3BBY3Rpb24iPuKZmSZuYnNwOyBBY2NvdW50Jm5ic3A74oyEPC9idXR0b24+CiAgICA8L2hlYWRlcj4KCiAgICA8c2VjdGlvbiBjbGFzcz0ibWFwWm9uZSI+PGRpdiBjbGFzcz0ibWFwRnJhbWUiPjxkaXYgaWQ9Im1hcCIgY2xhc3M9Im1hcENhbnZhcyI+PC9kaXY+PGRpdiBjbGFzcz0ibWFwU2hhZGUiPjwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJtYXBUb29scyI+CiAgICAgICAgPGJ1dHRvbiBpZD0ibG9jYXRlQnV0dG9uIiBjbGFzcz0ibWFwVG9vbCI+4p6kPC9idXR0b24+PGJ1dHRvbiBpZD0ibGlnaHRNYXBCdXR0b24iIGNsYXNzPSJtYXBUb29sIGFjdGl2ZSI+4perPC9idXR0b24+PGJ1dHRvbiBpZD0iZGFya01hcEJ1dHRvbiIgY2xhc3M9Im1hcFRvb2wiPuKXkDwvYnV0dG9uPjxidXR0b24gaWQ9InNhdGVsbGl0ZU1hcEJ1dHRvbiIgY2xhc3M9Im1hcFRvb2wiPuKWpzwvYnV0dG9uPgogICAgICAgIDxkaXYgY2xhc3M9Im1hcFpvb21Hcm91cCI+PGJ1dHRvbiBpZD0iem9vbUluQnV0dG9uIiBjbGFzcz0ibWFwVG9vbCI+77yLPC9idXR0b24+PGJ1dHRvbiBpZD0iem9vbU91dEJ1dHRvbiIgY2xhc3M9Im1hcFRvb2wiPuKIkjwvYnV0dG9uPjwvZGl2PgogICAgICA8L2Rpdj4KICAgICAgPGRpdiBpZD0iZmlsdGVyQ2hpcCIgY2xhc3M9ImZpbHRlckNoaXAiPjxzcGFuPuKWviZuYnNwOyA8YiBpZD0iZmlsdGVyQ2hpcFRleHQiPkZpbHRlcjogQWxsIFN0b3BzPC9iPjwvc3Bhbj48YnV0dG9uIGlkPSJjbGVhckZpbHRlckJ1dHRvbiI+w5c8L2J1dHRvbj48L2Rpdj4KICAgIDwvZGl2Pjwvc2VjdGlvbj4KCiAgICA8c2VjdGlvbiBjbGFzcz0ibWVkaWFTdHJpcCI+PGRpdiBjbGFzcz0ibWVkaWFIZWFkZXIiPjxkaXYgaWQ9Im1lZGlhVGl0bGUiIGNsYXNzPSJtZWRpYVRpdGxlIj5NZWRpYTwvZGl2PjxkaXYgaWQ9Im1lZGlhQ291bnQiIGNsYXNzPSJtZWRpYUNvdW50Ij48L2Rpdj48ZGl2IGNsYXNzPSJtZWRpYUhlYWRlclNwYWNlciI+PC9kaXY+PGJ1dHRvbiBjbGFzcz0idGlueUJ1dHRvbiI+4pamPC9idXR0b24+PGJ1dHRvbiBjbGFzcz0idGlueUJ1dHRvbiI+4pi3PC9idXR0b24+PC9kaXY+PGRpdiBpZD0iZ2FsbGVyeSIgY2xhc3M9ImdhbGxlcnkiPjwvZGl2Pjwvc2VjdGlvbj4KICA8L21haW4+CgogIDxhc2lkZSBjbGFzcz0icmlnaHRSYWlsIj4KICAgIDxkaXYgY2xhc3M9InJpZ2h0VG9wIj48ZGl2IGNsYXNzPSJyaWdodFRpdGxlIj5TdG9wcyA8c3BhbiBpZD0ic3RvcENvdW50IiBjbGFzcz0icmlnaHRDb3VudCI+KDApPC9zcGFuPjwvZGl2PjxidXR0b24gaWQ9InN0b3BTZWFyY2hCdXR0b24iIGNsYXNzPSJyaWdodFNlYXJjaCI+4oyVPC9idXR0b24+PC9kaXY+CiAgICA8ZGl2IGlkPSJzdG9wU2VhcmNoV3JhcCIgY2xhc3M9InN0b3BTZWFyY2hXcmFwIj48aW5wdXQgaWQ9InN0b3BTZWFyY2giIHBsYWNlaG9sZGVyPSJTZWFyY2ggc3RvcHPigKYiPjwvZGl2PgogICAgPGRpdiBpZD0ic3RvcExpc3QiIGNsYXNzPSJzdG9wTGlzdCI+PC9kaXY+CiAgICA8YnV0dG9uIGlkPSJhZGRTdG9wQnV0dG9uIiBjbGFzcz0iYWRkU3RvcEJ1dHRvbiI+77yLJm5ic3A7IEFkZCBTdG9wIE1hbnVhbGx5PC9idXR0b24+CiAgICA8c2VjdGlvbiBpZD0iZXhwb3J0Qm94IiBjbGFzcz0iZXhwb3J0Qm94Ij48ZGl2IGlkPSJleHBvcnRIZWFkZXIiIGNsYXNzPSJleHBvcnRIZWFkZXIiPjxzcGFuPkV4cG9ydCAmYW1wOyBSZW5kZXI8L3NwYW4+PHNwYW4+4oyDPC9zcGFuPjwvZGl2PjxkaXYgY2xhc3M9ImV4cG9ydEJvZHkiPgogICAgICA8c3BhbiBjbGFzcz0iZmllbGRMYWJlbCI+RXhwb3J0IEZvcm1hdDwvc3Bhbj48ZGl2IGNsYXNzPSJleHBvcnRUYWJzIj48YnV0dG9uIGNsYXNzPSJhY3RpdmUiPlZpZGVvIChNUDQpPC9idXR0b24+PGJ1dHRvbiBpZD0iZ3B4QnV0dG9uIj5HUFggVHJhY2s8L2J1dHRvbj48YnV0dG9uIGlkPSJpbWFnZVNldEJ1dHRvbiI+SW1hZ2UgU2V0PC9idXR0b24+PC9kaXY+CiAgICAgIDxzcGFuIGNsYXNzPSJmaWVsZExhYmVsIj5RdWFsaXR5PC9zcGFuPjxzZWxlY3QgaWQ9InF1YWxpdHlTZWxlY3QiPjxvcHRpb24+MTA4MHAgKEhpZ2gpPC9vcHRpb24+PG9wdGlvbj43MjBwPC9vcHRpb24+PC9zZWxlY3Q+CiAgICAgIDxkaXYgY2xhc3M9ImF1ZGlvUm93Ij48ZGl2PjxiPkluY2x1ZGUgQXVkaW88L2I+PGRpdiBjbGFzcz0ic21hbGwiPkFkZCBtdXNpYyB0byB5b3VyIHZpZGVvPC9kaXY+PC9kaXY+PGRpdiBpZD0iYXVkaW9Td2l0Y2giIGNsYXNzPSJzd2l0Y2giPjwvZGl2PjwvZGl2PjxpbnB1dCBpZD0iYXVkaW9JbnB1dCIgY2xhc3M9ImF1ZGlvSW5wdXQiIHR5cGU9ImZpbGUiIGFjY2VwdD0iYXVkaW8vKiI+CiAgICAgIDxidXR0b24gaWQ9InJlbmRlckJ1dHRvbiIgY2xhc3M9InJlbmRlckJ1dHRvbiI+4pamJm5ic3A7IFJlbmRlciBNUDQ8c3Bhbj5GaW5hbCB2aWRlbyBleHBvcnQ8L3NwYW4+PC9idXR0b24+CiAgICA8L2Rpdj48L3NlY3Rpb24+CiAgPC9hc2lkZT4KPC9kaXY+Cgo8ZGl2IGlkPSJpbW1pY2hNb2RhbCIgY2xhc3M9Im1vZGFsIj48ZGl2IGNsYXNzPSJtb2RhbENhcmQiPjxkaXYgY2xhc3M9Im1vZGFsVGl0bGUiPk5ldyBJbW1pY2ggSm91cm5leTwvZGl2PjxkaXYgY2xhc3M9ImZvcm1HcmlkIj48aW5wdXQgaWQ9ImltbWljaFVybCIgcGxhY2Vob2xkZXI9IkltbWljaCBVUkwg4oCUIGZvciBleGFtcGxlIGh0dHA6Ly8xOTIuMTY4LjY4LjE1MzoyMjgzIj48aW5wdXQgaWQ9ImltbWljaEtleSIgdHlwZT0icGFzc3dvcmQiIHBsYWNlaG9sZGVyPSJJbW1pY2ggQVBJIGtleSI+PGRpdiBjbGFzcz0idHdvQ29sIj48aW5wdXQgaWQ9InN0YXJ0RGF0ZSIgdHlwZT0iZGF0ZSI+PGlucHV0IGlkPSJlbmREYXRlIiB0eXBlPSJkYXRlIj48L2Rpdj48ZGl2IGNsYXNzPSJzbWFsbCI+UmVxdWlyZWQgcGVybWlzc2lvbnM6IGFzc2V0LnJlYWQsIGFzc2V0LnZpZXcsIGFzc2V0LmRvd25sb2FkLCBtYXAucmVhZCwgdGltZWxpbmUucmVhZDwvZGl2PjxkaXYgY2xhc3M9Im1vZGFsQWN0aW9ucyI+PGJ1dHRvbiBpZD0idGVzdEltbWljaEJ1dHRvbiI+VGVzdCBDb25uZWN0aW9uPC9idXR0b24+PGJ1dHRvbiBpZD0iY3JlYXRlSm91cm5leUJ1dHRvbiIgY2xhc3M9InByaW1hcnkiPkNyZWF0ZSBKb3VybmV5PC9idXR0b24+PGJ1dHRvbiBkYXRhLWNsb3NlPSJpbW1pY2hNb2RhbCI+Q2FuY2VsPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+PC9kaXY+CjxkaXYgaWQ9InVwbG9hZE1vZGFsIiBjbGFzcz0ibW9kYWwiPjxkaXYgY2xhc3M9Im1vZGFsQ2FyZCI+PGRpdiBjbGFzcz0ibW9kYWxUaXRsZSI+VXBsb2FkIEdQUyBNZWRpYTwvZGl2PjxkaXYgY2xhc3M9ImZvcm1HcmlkIj48aW5wdXQgaWQ9InVwbG9hZE5hbWUiIHZhbHVlPSJVcGxvYWRlZCBKb3VybmV5IiBwbGFjZWhvbGRlcj0iSm91cm5leSBuYW1lIj48aW5wdXQgaWQ9InVwbG9hZEZpbGVzIiB0eXBlPSJmaWxlIiBhY2NlcHQ9ImltYWdlLyosdmlkZW8vKiIgbXVsdGlwbGU+PGRpdiBjbGFzcz0ic21hbGwiPk9ubHkgbWVkaWEgY29udGFpbmluZyBHUFMgbWV0YWRhdGEgY2FuIGFwcGVhciBvbiB0aGUgbWFwLjwvZGl2PjxkaXYgY2xhc3M9Im1vZGFsQWN0aW9ucyI+PGJ1dHRvbiBpZD0iY3JlYXRlVXBsb2FkQnV0dG9uIiBjbGFzcz0icHJpbWFyeSI+SW1wb3J0IE1lZGlhPC9idXR0b24+PGJ1dHRvbiBkYXRhLWNsb3NlPSJ1cGxvYWRNb2RhbCI+Q2FuY2VsPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+PC9kaXY+CjxkaXYgaWQ9InNldHRpbmdzTW9kYWwiIGNsYXNzPSJtb2RhbCI+PGRpdiBjbGFzcz0ibW9kYWxDYXJkIj48ZGl2IGNsYXNzPSJtb2RhbFRpdGxlIj5Kb3VybmV5IFNldHRpbmdzPC9kaXY+PGRpdiBjbGFzcz0iZm9ybUdyaWQiPjxsYWJlbCBjbGFzcz0ic21hbGwiPlN0b3AgcmFkaXVzLCBtZXRlcnM8L2xhYmVsPjxpbnB1dCBpZD0ic3RvcFJhZGl1cyIgdHlwZT0ibnVtYmVyIiBtaW49IjEwIiB2YWx1ZT0iMjAwIj48ZGl2IGNsYXNzPSJ0d29Db2wiPjxidXR0b24gaWQ9InJlY2x1c3RlckJ1dHRvbiI+QXV0by1jbHVzdGVyIFN0b3BzPC9idXR0b24+PGJ1dHRvbiBpZD0icmV2ZXJzZVJvdXRlQnV0dG9uIj5SZXZlcnNlIFJvdXRlPC9idXR0b24+PC9kaXY+PGxhYmVsIGNsYXNzPSJzbWFsbCI+RGVmYXVsdCBtYXA8L2xhYmVsPjxzZWxlY3QgaWQ9ImRlZmF1bHRNYXBTZWxlY3QiPjxvcHRpb24gdmFsdWU9ImxpZ2h0Ij5MaWdodCBPU008L29wdGlvbj48b3B0aW9uIHZhbHVlPSJkYXJrIj5EYXJrPC9vcHRpb24+PG9wdGlvbiB2YWx1ZT0ic2F0ZWxsaXRlIj5TYXRlbGxpdGU8L29wdGlvbj48L3NlbGVjdD48ZGl2IGNsYXNzPSJtb2RhbEFjdGlvbnMiPjxidXR0b24gZGF0YS1jbG9zZT0ic2V0dGluZ3NNb2RhbCI+Q2xvc2U8L2J1dHRvbj48L2Rpdj48L2Rpdj48L2Rpdj48L2Rpdj4KPGRpdiBpZD0iYWNjb3VudE1vZGFsIiBjbGFzcz0ibW9kYWwiPjxkaXYgY2xhc3M9Im1vZGFsQ2FyZCI+PGRpdiBjbGFzcz0ibW9kYWxUaXRsZSI+QWNjb3VudCAvIEltbWljaCBDb25uZWN0aW9uPC9kaXY+PGRpdiBjbGFzcz0iZm9ybUdyaWQiPjxpbnB1dCBpZD0iYWNjb3VudFVybCIgcGxhY2Vob2xkZXI9IkltbWljaCBVUkwiPjxpbnB1dCBpZD0iYWNjb3VudEtleSIgdHlwZT0icGFzc3dvcmQiIHBsYWNlaG9sZGVyPSJBUEkga2V5Ij48ZGl2IGNsYXNzPSJtb2RhbEFjdGlvbnMiPjxidXR0b24gaWQ9InNhdmVBY2NvdW50QnV0dG9uIiBjbGFzcz0icHJpbWFyeSI+U2F2ZSBDb25uZWN0aW9uPC9idXR0b24+PGJ1dHRvbiBkYXRhLWNsb3NlPSJhY2NvdW50TW9kYWwiPkNsb3NlPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+PC9kaXY+Cgo8ZGl2IGlkPSJwcmVzZW50T3ZlcmxheSIgY2xhc3M9InByZXNlbnRPdmVybGF5Ij48ZGl2IGNsYXNzPSJwcmVzZW50SGVhZGVyIj48YnV0dG9uIGlkPSJwcmVzZW50QmFja0J1dHRvbiIgY2xhc3M9InByZXNlbnRCYWNrIiB0aXRsZT0iQmFjayI+4oaQPC9idXR0b24+PGRpdiBjbGFzcz0ibG9nb0Zsb3dlciI+PHNwYW4gY2xhc3M9InBldGFsIHAxIj48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHAyIj48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHAzIj48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHA0Ij48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHA1Ij48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHA2Ij48L3NwYW4+PC9kaXY+PGRpdj48ZGl2IGlkPSJwcmVzZW50SGVhZGVyVGl0bGUiIGNsYXNzPSJwcmVzZW50SGVhZGVyVGl0bGUiPlByZXNlbnQgSm91cm5leTwvZGl2PjxkaXYgaWQ9InByZXNlbnRIZWFkZXJNZXRhIiBjbGFzcz0icHJlc2VudEhlYWRlck1ldGEiPjwvZGl2PjwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRIZWFkZXJTcGFjZXIiPjwvZGl2PjxidXR0b24gaWQ9ImNlbnRlclRyaXBCdXR0b24iIGNsYXNzPSJwcmVzZW50SGVhZGVyQWN0aW9uIj7ijJYgQ2VudGVyIG9uIFRyaXA8L2J1dHRvbj48YnV0dG9uIGlkPSJyZXR1cm5TdGFydEJ1dHRvbiIgY2xhc3M9InByZXNlbnRIZWFkZXJBY3Rpb24iPuKGtiBSZXR1cm4gdG8gU3RhcnQ8L2J1dHRvbj48YnV0dG9uIGlkPSJjbG9zZVByZXNlbnRCdXR0b24iIGNsYXNzPSJ0b3BBY3Rpb24iPkNsb3NlPC9idXR0b24+PC9kaXY+CiAgPGRpdiBjbGFzcz0icHJlc2VudE1haW4iPjxkaXYgaWQ9InByZXNlbnRNYXAiIGNsYXNzPSJwcmVzZW50TWFwIj48L2Rpdj48ZGl2IGlkPSJwcmVzZW50U3RvcEJhbm5lciIgY2xhc3M9InByZXNlbnRTdG9wQmFubmVyIj48ZGl2IGlkPSJwcmVzZW50U3RvcEJhbm5lclRpdGxlIiBjbGFzcz0icHJlc2VudFN0b3BCYW5uZXJUaXRsZSI+Sm91cm5leSBTdG9wPC9kaXY+PGRpdiBpZD0icHJlc2VudFN0b3BCYW5uZXJSYW5nZSIgY2xhc3M9InByZXNlbnRTdG9wQmFubmVyUmFuZ2UiPjwvZGl2PjwvZGl2PjxkaXYgaWQ9InByZXNlbnRTdG9wUmFpbCIgY2xhc3M9InByZXNlbnRTdG9wUmFpbCI+PC9kaXY+PGRpdiBpZD0icHJlc2VudFBob3RvQ2FyZCIgY2xhc3M9InByZXNlbnRQaG90b0NhcmQiPjwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRIdWQiPjxidXR0b24gaWQ9InByZXZpb3VzU3RvcEJ1dHRvbiI+4oaQIFN0b3A8L2J1dHRvbj48YnV0dG9uIGlkPSJwcmV2aW91c1Bob3RvQnV0dG9uIj7ihpAgUGhvdG88L2J1dHRvbj48YnV0dG9uIGlkPSJwbGF5Sm91cm5leUJ1dHRvbiIgY2xhc3M9InBsYXkiPuKWtiBQbGF5PC9idXR0b24+PGJ1dHRvbiBpZD0ibmV4dFBob3RvQnV0dG9uIj5QaG90byDihpI8L2J1dHRvbj48YnV0dG9uIGlkPSJuZXh0U3RvcEJ1dHRvbiI+U3RvcCDihpI8L2J1dHRvbj48L2Rpdj48L2Rpdj48ZGl2IGlkPSJwcmVzZW50RmlsbXN0cmlwIiBjbGFzcz0icHJlc2VudEZpbG1zdHJpcCI+PC9kaXY+CjwvZGl2Pgo8ZGl2IGlkPSJ0b2FzdCIgY2xhc3M9InRvYXN0Ij48L2Rpdj4KCjxzY3JpcHQ+CmNvbnN0IE1BUF9TVFlMRVM9ewogbGlnaHQ6e3ZlcnNpb246OCxnbHlwaHM6J2h0dHBzOi8vZGVtb3RpbGVzLm1hcGxpYnJlLm9yZy9mb250L3tmb250c3RhY2t9L3tyYW5nZX0ucGJmJyxzb3VyY2VzOntiYXNlOnt0eXBlOidyYXN0ZXInLHRpbGVzOlsnaHR0cHM6Ly9hLmJhc2VtYXBzLmNhcnRvY2RuLmNvbS9yYXN0ZXJ0aWxlcy92b3lhZ2VyL3t6fS97eH0ve3l9QDJ4LnBuZycsJ2h0dHBzOi8vYi5iYXNlbWFwcy5jYXJ0b2Nkbi5jb20vcmFzdGVydGlsZXMvdm95YWdlci97en0ve3h9L3t5fUAyeC5wbmcnXSx0aWxlU2l6ZToyNTYsYXR0cmlidXRpb246J8KpIE9wZW5TdHJlZXRNYXAgY29udHJpYnV0b3JzIMKpIENBUlRPJ319LGxheWVyczpbe2lkOidiYXNlJyx0eXBlOidyYXN0ZXInLHNvdXJjZTonYmFzZScsbWluem9vbTowLG1heHpvb206MjB9XX0sCiBkYXJrOnt2ZXJzaW9uOjgsZ2x5cGhzOidodHRwczovL2RlbW90aWxlcy5tYXBsaWJyZS5vcmcvZm9udC97Zm9udHN0YWNrfS97cmFuZ2V9LnBiZicsc291cmNlczp7YmFzZTp7dHlwZToncmFzdGVyJyx0aWxlczpbJ2h0dHBzOi8vYS5iYXNlbWFwcy5jYXJ0b2Nkbi5jb20vZGFya19hbGwve3p9L3t4fS97eX1AMngucG5nJywnaHR0cHM6Ly9iLmJhc2VtYXBzLmNhcnRvY2RuLmNvbS9kYXJrX2FsbC97en0ve3h9L3t5fUAyeC5wbmcnXSx0aWxlU2l6ZToyNTYsYXR0cmlidXRpb246J8KpIE9wZW5TdHJlZXRNYXAgY29udHJpYnV0b3JzIMKpIENBUlRPJ319LGxheWVyczpbe2lkOidiYXNlJyx0eXBlOidyYXN0ZXInLHNvdXJjZTonYmFzZScsbWluem9vbTowLG1heHpvb206MjB9XX0sCiBzYXRlbGxpdGU6e3ZlcnNpb246OCxnbHlwaHM6J2h0dHBzOi8vZGVtb3RpbGVzLm1hcGxpYnJlLm9yZy9mb250L3tmb250c3RhY2t9L3tyYW5nZX0ucGJmJyxzb3VyY2VzOntiYXNlOnt0eXBlOidyYXN0ZXInLHRpbGVzOlsnaHR0cHM6Ly9zZXJ2ZXIuYXJjZ2lzb25saW5lLmNvbS9BcmNHSVMvcmVzdC9zZXJ2aWNlcy9Xb3JsZF9JbWFnZXJ5L01hcFNlcnZlci90aWxlL3t6fS97eX0ve3h9J10sdGlsZVNpemU6MjU2LG1pbnpvb206MCxtYXh6b29tOjE4LGF0dHJpYnV0aW9uOidUaWxlcyDCqSBFc3JpJ319LGxheWVyczpbe2lkOidiYXNlJyx0eXBlOidyYXN0ZXInLHNvdXJjZTonYmFzZScsbWluem9vbTowLG1heHpvb206MjQscGFpbnQ6eydyYXN0ZXItcmVzYW1wbGluZyc6J2xpbmVhcid9fV19Cn07CmxldCBwcm9qZWN0cz1bXSxwcm9qZWN0PW51bGwsbWFwPW51bGwscHJlc2VudE1hcD1udWxsLG1hcFN0eWxlS2V5PWxvY2FsU3RvcmFnZS5nZXRJdGVtKCd0cmlwcHlfbWFwX3N0eWxlJyl8fCdsaWdodCc7CmxldCBtYXJrZXJzPVtdLHBob3RvTWFya2Vycz1bXSxwcmVzZW50TWFya2Vycz1bXSxwcmVzZW50UGhvdG9NYXJrZXJzPVtdLGFjdGl2ZVN0b3BJZD1udWxsLGZpbHRlclN0b3BJZD1udWxsLGFjdGl2ZUFzc2V0SWQ9bnVsbCxhY3RpdmVQb3B1cD1udWxsLHByZXNlbnRTdG9wSW5kZXg9MCxwcmVzZW50UGhvdG9JbmRleD0tMSxwcmVzZW50VGltZXI9bnVsbCxwcmVzZW50T3JiaXRUaW1lcj1udWxsLHByZXNlbnRPcmJpdERlbGF5PW51bGwscHJlc2VudFZpZXc9J3RyaXAnLHByZXNlbnRGb2N1c01hcmtlcj1udWxsOwpjb25zdCBlbD1pZD0+ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoaWQpOwpmdW5jdGlvbiBjbG9uZVN0eWxlKGtleSl7cmV0dXJuIEpTT04ucGFyc2UoSlNPTi5zdHJpbmdpZnkoTUFQX1NUWUxFU1trZXldfHxNQVBfU1RZTEVTLmxpZ2h0KSl9CmZ1bmN0aW9uIHRvYXN0KG1lc3NhZ2Upe2NvbnN0IHQ9ZWwoJ3RvYXN0Jyk7dC50ZXh0Q29udGVudD1tZXNzYWdlO3QuY2xhc3NMaXN0LmFkZCgnc2hvdycpO2NsZWFyVGltZW91dCh0Ll90aW1lcik7dC5fdGltZXI9c2V0VGltZW91dCgoKT0+dC5jbGFzc0xpc3QucmVtb3ZlKCdzaG93JyksNDMwMCl9CmZ1bmN0aW9uIGVzYyh2KXtyZXR1cm4gU3RyaW5nKHY/PycnKS5yZXBsYWNlKC9bJjw+JyJdL2csYz0+KHsnJic6JyZhbXA7JywnPCc6JyZsdDsnLCc+JzonJmd0OycsIiciOicmIzM5OycsJyInOicmcXVvdDsnfVtjXSkpfQpmdW5jdGlvbiBpc29EYXRlKHYpe2lmKCF2KXJldHVybicnO3JldHVybiBTdHJpbmcodikuc2xpY2UoMCwxMCl9CmZ1bmN0aW9uIHByZXR0eURhdGUodil7aWYoIXYpcmV0dXJuJyc7Y29uc3QgZD1uZXcgRGF0ZShTdHJpbmcodikuc2xpY2UoMCwxMCkrJ1QxMjowMDowMCcpO3JldHVybiBOdW1iZXIuaXNOYU4oZC5nZXRUaW1lKCkpP1N0cmluZyh2KS5zbGljZSgwLDEwKTpkLnRvTG9jYWxlRGF0ZVN0cmluZyh1bmRlZmluZWQse21vbnRoOidzaG9ydCcsZGF5OidudW1lcmljJyx5ZWFyOidudW1lcmljJ30pfQpmdW5jdGlvbiByYW5nZVRleHQob2JqKXtjb25zdCBhPW9iaj8uaW1taWNoPy5zdGFydF9kYXRlfHxvYmo/LnN0YXJ0X2RhdGU7Y29uc3QgYj1vYmo/LmltbWljaD8uZW5kX2RhdGV8fG9iaj8uZW5kX2RhdGU7aWYoYSYmYilyZXR1cm4gYCR7aXNvRGF0ZShhKX0gdG8gJHtpc29EYXRlKGIpfWA7cmV0dXJuIHByZXR0eURhdGUob2JqPy5jcmVhdGVkKX0KZnVuY3Rpb24gYXNzZXREYXRlKHZhbHVlKXtpZighdmFsdWUpcmV0dXJuIG51bGw7bGV0IHJhdz1TdHJpbmcodmFsdWUpLnRyaW0oKTtpZigvXlxkezR9OlxkezJ9OlxkezJ9Ly50ZXN0KHJhdykpcmF3PXJhdy5yZXBsYWNlKC9eKFxkezR9KTooXGR7Mn0pOihcZHsyfSkvLCckMS0kMi0kMycpLnJlcGxhY2UoJyAnLCdUJyk7Y29uc3QgZD1uZXcgRGF0ZShyYXcpO3JldHVybiBOdW1iZXIuaXNOYU4oZC5nZXRUaW1lKCkpP251bGw6ZH0KZnVuY3Rpb24gZm9ybWF0QXNzZXREYXRlVGltZSh2YWx1ZSl7Y29uc3QgZD1hc3NldERhdGUodmFsdWUpO2lmKCFkKXJldHVybiB2YWx1ZT9TdHJpbmcodmFsdWUpOidEYXRlIHVuYXZhaWxhYmxlJztjb25zdCBkYXRlPWQudG9Mb2NhbGVEYXRlU3RyaW5nKCdlbi1VUycse21vbnRoOicyLWRpZ2l0JyxkYXk6JzItZGlnaXQnLHllYXI6J251bWVyaWMnfSkucmVwbGFjZUFsbCgnLycsJy0nKTtjb25zdCB0aW1lPWQudG9Mb2NhbGVUaW1lU3RyaW5nKCdlbi1VUycse2hvdXI6J251bWVyaWMnLG1pbnV0ZTonMi1kaWdpdCd9KTtyZXR1cm4gYCR7ZGF0ZX0gJHt0aW1lfWB9ZnVuY3Rpb24gZGVjaW1hbFRvRG1zKHZhbHVlLGlzTGF0KXtjb25zdCBuPU51bWJlcih2YWx1ZSk7aWYoIU51bWJlci5pc0Zpbml0ZShuKSlyZXR1cm4nQ29vcmRpbmF0ZSB1bmF2YWlsYWJsZSc7Y29uc3QgYWJzPU1hdGguYWJzKG4pLGRlZz1NYXRoLmZsb29yKGFicyksbWludXRlc0Zsb2F0PShhYnMtZGVnKSo2MCxtaW49TWF0aC5mbG9vcihtaW51dGVzRmxvYXQpLHNlYz0obWludXRlc0Zsb2F0LW1pbikqNjAsaGVtPWlzTGF0PyhuPj0wPydOJzonUycpOihuPj0wPydFJzonVycpO3JldHVybiBgJHtkZWd9wrAgJHtTdHJpbmcobWluKS5wYWRTdGFydCgyLCcwJyl94oCyICR7c2VjLnRvRml4ZWQoMikucGFkU3RhcnQoNSwnMCcpfeKAsyAke2hlbX1gfWZ1bmN0aW9uIGFzc2V0Q29vcmRpbmF0ZVRleHQoYXNzZXQpe3JldHVybiBgJHtkZWNpbWFsVG9EbXMoYXNzZXQ/LmxhdCx0cnVlKX0gIOKAoiAgJHtkZWNpbWFsVG9EbXMoYXNzZXQ/LmxvbixmYWxzZSl9YH0KZnVuY3Rpb24gc3RvcERhdGVSYW5nZShzdG9wKXtjb25zdCBkYXRlcz1zdG9wQXNzZXRzKHN0b3ApLm1hcChhPT5hc3NldERhdGUoYS50aW1lKSkuZmlsdGVyKEJvb2xlYW4pLnNvcnQoKGEsYik9PmEtYik7aWYoIWRhdGVzLmxlbmd0aClyZXR1cm4nRGF0ZS90aW1lIHVuYXZhaWxhYmxlJztjb25zdCBmaXJzdD1kYXRlc1swXSxsYXN0PWRhdGVzW2RhdGVzLmxlbmd0aC0xXTtjb25zdCBmZD1maXJzdC50b0xvY2FsZURhdGVTdHJpbmcoJ2VuLVVTJyx7bW9udGg6JzItZGlnaXQnLGRheTonMi1kaWdpdCcseWVhcjonbnVtZXJpYyd9KS5yZXBsYWNlQWxsKCcvJywnLScpO2NvbnN0IGZ0PWZpcnN0LnRvTG9jYWxlVGltZVN0cmluZygnZW4tVVMnLHtob3VyOidudW1lcmljJyxtaW51dGU6JzItZGlnaXQnfSk7Y29uc3QgbGQ9bGFzdC50b0xvY2FsZURhdGVTdHJpbmcoJ2VuLVVTJyx7bW9udGg6JzItZGlnaXQnLGRheTonMi1kaWdpdCcseWVhcjonbnVtZXJpYyd9KS5yZXBsYWNlQWxsKCcvJywnLScpO2NvbnN0IGx0PWxhc3QudG9Mb2NhbGVUaW1lU3RyaW5nKCdlbi1VUycse2hvdXI6J251bWVyaWMnLG1pbnV0ZTonMi1kaWdpdCd9KTtyZXR1cm4gZmQ9PT1sZD9gJHtmZH0gJHtmdH0g4oCTICR7bHR9YDpgJHtmZH0gJHtmdH0g4oCTICR7bGR9ICR7bHR9YH0KZnVuY3Rpb24gdmFsaWRQb2ludChpdGVtKXtyZXR1cm4gTnVtYmVyLmlzRmluaXRlKE51bWJlcihpdGVtPy5sb24pKSYmTnVtYmVyLmlzRmluaXRlKE51bWJlcihpdGVtPy5sYXQpKSYmTWF0aC5hYnMoTnVtYmVyKGl0ZW0ubGF0KSk8PTkwJiZNYXRoLmFicyhOdW1iZXIoaXRlbS5sb24pKTw9MTgwfQpmdW5jdGlvbiBzdG9wQm91bmRzKHN0b3Ape2NvbnN0IGFzc2V0cz1zdG9wQXNzZXRzKHN0b3ApLmZpbHRlcih2YWxpZFBvaW50KTtjb25zdCBib3VuZHM9bmV3IG1hcGxpYnJlZ2wuTG5nTGF0Qm91bmRzKCk7YXNzZXRzLmZvckVhY2goYT0+Ym91bmRzLmV4dGVuZChbTnVtYmVyKGEubG9uKSxOdW1iZXIoYS5sYXQpXSkpO2lmKCFhc3NldHMubGVuZ3RoJiZ2YWxpZFBvaW50KHN0b3ApKWJvdW5kcy5leHRlbmQoW051bWJlcihzdG9wLmxvbiksTnVtYmVyKHN0b3AubGF0KV0pO3JldHVybntib3VuZHMsYXNzZXRzfX0KZnVuY3Rpb24gY29ubigpe3JldHVybntiYXNlX3VybDpsb2NhbFN0b3JhZ2UuZ2V0SXRlbSgndHJpcHB5X2ltbWljaF91cmwnKXx8JycsYXBpX2tleTpsb2NhbFN0b3JhZ2UuZ2V0SXRlbSgndHJpcHB5X2ltbWljaF9rZXknKXx8Jyd9fQpmdW5jdGlvbiBzYXZlQ29ubih1cmwsa2V5KXtsb2NhbFN0b3JhZ2Uuc2V0SXRlbSgndHJpcHB5X2ltbWljaF91cmwnLHVybCk7bG9jYWxTdG9yYWdlLnNldEl0ZW0oJ3RyaXBweV9pbW1pY2hfa2V5JyxrZXkpfQphc3luYyBmdW5jdGlvbiBhcGkocGF0aCxvcHRpb25zPXt9KXtjb25zdCByZXNwb25zZT1hd2FpdCBmZXRjaChwYXRoLG9wdGlvbnMpO2NvbnN0IHJhdz1hd2FpdCByZXNwb25zZS50ZXh0KCk7bGV0IGRhdGE7dHJ5e2RhdGE9SlNPTi5wYXJzZShyYXcpfWNhdGNoe2RhdGE9e2RldGFpbDpyYXd9fWlmKCFyZXNwb25zZS5vayl0aHJvdyBuZXcgRXJyb3IoZGF0YS5kZXRhaWx8fHJhd3x8YEhUVFAgJHtyZXNwb25zZS5zdGF0dXN9YCk7cmV0dXJuIGRhdGF9CmZ1bmN0aW9uIHN0b3BOYW1lKHN0b3AsaW5kZXgpe2NvbnN0IHJhdz0oc3RvcD8ubmFtZXx8JycpLnRyaW0oKTtyZXR1cm4gcmF3JiYhL15TdG9wXHMrXGQrJC9pLnRlc3QocmF3KT9yYXc6YFN0b3AgJHtpbmRleCsxfWB9CmZ1bmN0aW9uIHN0b3BBc3NldHMoc3RvcCl7aWYoIXByb2plY3R8fCFzdG9wKXJldHVybltdO2NvbnN0IGlkcz1uZXcgU2V0KHN0b3AuYXNzZXRfaWRzfHxbXSk7cmV0dXJuKHByb2plY3QuYXNzZXRzfHxbXSkuZmlsdGVyKGE9Pmlkcy5oYXMoYS5hc3NldF9pZCkpfQpmdW5jdGlvbiBmaXJzdFN0b3BBc3NldChzdG9wKXtyZXR1cm4gc3RvcEFzc2V0cyhzdG9wKVswXXx8bnVsbH0KZnVuY3Rpb24gcHJvamVjdFN1bW1hcnlDb3VudChwKXtyZXR1cm4gTnVtYmVyKHA/LmNvdW50Pz9wPy5hc3NldHM/Lmxlbmd0aD8/MCl9CmZ1bmN0aW9uIHNldE1vZGFsKGlkLG9uPXRydWUpe2VsKGlkKS5jbGFzc0xpc3QudG9nZ2xlKCdzaG93Jyxvbil9CmZ1bmN0aW9uIGluaXRGb3Jtcygpe2NvbnN0IGM9Y29ubigpO2VsKCdpbW1pY2hVcmwnKS52YWx1ZT1jLmJhc2VfdXJsO2VsKCdpbW1pY2hLZXknKS52YWx1ZT1jLmFwaV9rZXk7ZWwoJ2FjY291bnRVcmwnKS52YWx1ZT1jLmJhc2VfdXJsO2VsKCdhY2NvdW50S2V5JykudmFsdWU9Yy5hcGlfa2V5O2NvbnN0IGQ9bmV3IERhdGUoKSxzPW5ldyBEYXRlKCk7cy5zZXREYXRlKHMuZ2V0RGF0ZSgpLTcpO2VsKCdzdGFydERhdGUnKS52YWx1ZT1zLnRvSVNPU3RyaW5nKCkuc2xpY2UoMCwxMCk7ZWwoJ2VuZERhdGUnKS52YWx1ZT1kLnRvSVNPU3RyaW5nKCkuc2xpY2UoMCwxMCk7ZWwoJ2RlZmF1bHRNYXBTZWxlY3QnKS52YWx1ZT1tYXBTdHlsZUtleX0KYXN5bmMgZnVuY3Rpb24gbG9hZFByb2plY3RzKCl7cHJvamVjdHM9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3RzJyk7cmVuZGVyUHJvamVjdHMoKTtpZighcHJvamVjdCYmcHJvamVjdHMubGVuZ3RoKWF3YWl0IG9wZW5Qcm9qZWN0KHByb2plY3RzWzBdLmlkKTtpZighcHJvamVjdHMubGVuZ3RoKXJlbmRlckFsbCgpfQpmdW5jdGlvbiByZW5kZXJQcm9qZWN0cygpe2NvbnN0IHE9ZWwoJ3Byb2plY3RTZWFyY2gnKS52YWx1ZS50cmltKCkudG9Mb3dlckNhc2UoKTtjb25zdCBsaXN0PXByb2plY3RzLmZpbHRlcihwPT4hcXx8KHAubmFtZXx8JycpLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocSkpO2VsKCdwcm9qZWN0TGlzdCcpLmlubmVySFRNTD1saXN0Lm1hcChwPT5gPGFydGljbGUgY2xhc3M9InByb2plY3RDYXJkICR7cHJvamVjdD8uaWQ9PT1wLmlkPydhY3RpdmUnOicnfSIgZGF0YS1pZD0iJHtlc2MocC5pZCl9Ij48YnV0dG9uIGNsYXNzPSJwcm9qZWN0TWVudSIgZGF0YS1tZW51PSIke2VzYyhwLmlkKX0iPuKLrjwvYnV0dG9uPjxkaXYgY2xhc3M9InByb2plY3RDYXJkVGl0bGUiPiR7ZXNjKHAubmFtZXx8J1VudGl0bGVkIEpvdXJuZXknKX08L2Rpdj48ZGl2IGNsYXNzPSJwcm9qZWN0RGF0ZSI+JHtlc2MocmFuZ2VUZXh0KHApfHwnJyl9PC9kaXY+PGRpdiBjbGFzcz0icHJvamVjdFN0YXRzIj48c3BhbiBjbGFzcz0iZG90Ij7il488L3NwYW4+ICR7cHJvamVjdFN1bW1hcnlDb3VudChwKX0gbWVkaWEmbmJzcDsg4oCiICZuYnNwOyR7TnVtYmVyKHAuc3RvcHN8fDApfSBzdG9wczwvZGl2PjxidXR0b24gY2xhc3M9InByb2plY3REZWxldGUiIGRhdGEtZGVsZXRlPSIke2VzYyhwLmlkKX0iPkRlbGV0ZTwvYnV0dG9uPjwvYXJ0aWNsZT5gKS5qb2luKCcnKXx8JzxkaXYgY2xhc3M9InNtYWxsIj5ObyBqb3VybmV5cyB5ZXQuPC9kaXY+Jztkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCcucHJvamVjdENhcmQnKS5mb3JFYWNoKGNhcmQ9PmNhcmQuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLGU9PntpZihlLnRhcmdldC5jbG9zZXN0KCdidXR0b24nKSlyZXR1cm47b3BlblByb2plY3QoY2FyZC5kYXRhc2V0LmlkKX0pKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1tZW51XScpLmZvckVhY2goYj0+Yi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsZT0+e2Uuc3RvcFByb3BhZ2F0aW9uKCk7Yi5jbG9zZXN0KCcucHJvamVjdENhcmQnKS5jbGFzc0xpc3QudG9nZ2xlKCdtZW51T3BlbicpfSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLWRlbGV0ZV0nKS5mb3JFYWNoKGI9PmIuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLGU9PntlLnN0b3BQcm9wYWdhdGlvbigpO2RlbGV0ZVByb2plY3QoYi5kYXRhc2V0LmRlbGV0ZSl9KSl9CmFzeW5jIGZ1bmN0aW9uIG9wZW5Qcm9qZWN0KGlkKXtwcm9qZWN0PWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KGlkKSk7YWN0aXZlU3RvcElkPXByb2plY3Quc3RvcHM/LlswXT8uc3RvcF9pZHx8bnVsbDtmaWx0ZXJTdG9wSWQ9YWN0aXZlU3RvcElkO2FjdGl2ZUFzc2V0SWQ9bnVsbDtyZW5kZXJBbGwoKTt0b2FzdChgTG9hZGVkICR7cHJvamVjdC5uYW1lfHwnam91cm5leSd9YCl9CmFzeW5jIGZ1bmN0aW9uIGRlbGV0ZVByb2plY3QoaWQpe2lmKCFjb25maXJtKCdEZWxldGUgdGhpcyBqb3VybmV5IGFuZCBpdHMgc2F2ZWQgZXhwb3J0PycpKXJldHVybjthd2FpdCBhcGkoJy9hcGkvcHJvamVjdC8nK2VuY29kZVVSSUNvbXBvbmVudChpZCkse21ldGhvZDonREVMRVRFJ30pO2lmKHByb2plY3Q/LmlkPT09aWQpcHJvamVjdD1udWxsO3Byb2plY3RzPXByb2plY3RzLmZpbHRlcihwPT5wLmlkIT09aWQpO2F3YWl0IGxvYWRQcm9qZWN0cygpfQpmdW5jdGlvbiByZW5kZXJBbGwoKXtyZW5kZXJQcm9qZWN0cygpO3JlbmRlckhlYWRlcigpO3JlbmRlclN0b3BzKCk7cmVuZGVyR2FsbGVyeSgpO3JlbmRlck1hcCh0cnVlKX0KZnVuY3Rpb24gcmVuZGVySGVhZGVyKCl7aWYoIXByb2plY3Qpe2VsKCdqb3VybmV5VGl0bGUnKS50ZXh0Q29udGVudD0nTm8gam91cm5leSBzZWxlY3RlZCc7ZWwoJ2pvdXJuZXlNZXRhJykudGV4dENvbnRlbnQ9J0xvYWQgb3IgY3JlYXRlIGEgam91cm5leSc7cmV0dXJufWVsKCdqb3VybmV5VGl0bGUnKS50ZXh0Q29udGVudD1wcm9qZWN0Lm5hbWV8fCdVbnRpdGxlZCBKb3VybmV5Jztjb25zdCBtZWRpYT0ocHJvamVjdC5hc3NldHN8fFtdKS5sZW5ndGgsc3RvcHM9KHByb2plY3Quc3RvcHN8fFtdKS5sZW5ndGg7ZWwoJ2pvdXJuZXlNZXRhJykuaW5uZXJIVE1MPWA8c3Bhbj7il7cgJHtlc2MocmFuZ2VUZXh0KHByb2plY3QpfHxwcmV0dHlEYXRlKHByb2plY3QuY3JlYXRlZCkpfTwvc3Bhbj48c3BhbiBjbGFzcz0ibGl2ZURvdCI+PC9zcGFuPjxzcGFuPiR7bWVkaWF9IG1lZGlhPC9zcGFuPjxzcGFuPuKAoiAke3N0b3BzfSBzdG9wczwvc3Bhbj5gfQpmdW5jdGlvbiBlbnN1cmVNYXAoKXtpZihtYXApcmV0dXJuO21hcD1uZXcgbWFwbGlicmVnbC5NYXAoe2NvbnRhaW5lcjonbWFwJyxzdHlsZTpjbG9uZVN0eWxlKG1hcFN0eWxlS2V5KSxjZW50ZXI6Wy05OCwzOV0sem9vbTozLHBpdGNoOjAsYmVhcmluZzowLGF0dHJpYnV0aW9uQ29udHJvbDp0cnVlfSk7bWFwLmFkZENvbnRyb2wobmV3IG1hcGxpYnJlZ2wuTmF2aWdhdGlvbkNvbnRyb2woe3Nob3dDb21wYXNzOmZhbHNlfSksJ2JvdHRvbS1yaWdodCcpO21hcC5vbignbG9hZCcsKCk9PnJlbmRlck1hcCh0cnVlKSk7bWFwLm9uKCd6b29tZW5kJyxyZW5kZXJTZWxlY3RlZFBob3RvQnViYmxlcyk7bWFwLm9uKCdtb3ZlZW5kJyxyZW5kZXJTZWxlY3RlZFBob3RvQnViYmxlcyl9CmZ1bmN0aW9uIGNsZWFyQnViYmxlTWFya2VycyhsaXN0KXtsaXN0LmZvckVhY2gobT0+e3RyeXttLnJlbW92ZSgpfWNhdGNoe319KTtsaXN0Lmxlbmd0aD0wfQpmdW5jdGlvbiBjbGVhck1hcE1hcmtlcnMoKXtjbGVhckJ1YmJsZU1hcmtlcnMobWFya2Vycyk7Y2xlYXJCdWJibGVNYXJrZXJzKHBob3RvTWFya2Vycyk7aWYoYWN0aXZlUG9wdXApe3RyeXthY3RpdmVQb3B1cC5yZW1vdmUoKX1jYXRjaHt9YWN0aXZlUG9wdXA9bnVsbH19CmZ1bmN0aW9uIHJlbW92ZUxheWVyQW5kU291cmNlKHRhcmdldE1hcCxpZHMsc291cmNlKXtpZHMuZm9yRWFjaChpZD0+e2lmKHRhcmdldE1hcC5nZXRMYXllcihpZCkpdGFyZ2V0TWFwLnJlbW92ZUxheWVyKGlkKX0pO2lmKHRhcmdldE1hcC5nZXRTb3VyY2Uoc291cmNlKSl0YXJnZXRNYXAucmVtb3ZlU291cmNlKHNvdXJjZSl9CmZ1bmN0aW9uIGFkZFJvdXRlTGF5ZXJzKHRhcmdldE1hcCxpZFByZWZpeCxjb29yZHMpe2NvbnN0IHNvdXJjZT1pZFByZWZpeCsnLXJvdXRlJyxnbG93PWlkUHJlZml4Kyctcm91dGUtZ2xvdycsbGluZT1pZFByZWZpeCsnLXJvdXRlLWxpbmUnO3JlbW92ZUxheWVyQW5kU291cmNlKHRhcmdldE1hcCxbbGluZSxnbG93XSxzb3VyY2UpO2lmKGNvb3Jkcy5sZW5ndGg8MilyZXR1cm47dGFyZ2V0TWFwLmFkZFNvdXJjZShzb3VyY2Use3R5cGU6J2dlb2pzb24nLGRhdGE6e3R5cGU6J0ZlYXR1cmUnLGdlb21ldHJ5Ont0eXBlOidMaW5lU3RyaW5nJyxjb29yZGluYXRlczpjb29yZHN9fX0pO3RhcmdldE1hcC5hZGRMYXllcih7aWQ6Z2xvdyx0eXBlOidsaW5lJyxzb3VyY2UscGFpbnQ6eydsaW5lLWNvbG9yJzonIzAwZDhmZicsJ2xpbmUtd2lkdGgnOjExLCdsaW5lLW9wYWNpdHknOi4yMCwnbGluZS1ibHVyJzo1fX0pO3RhcmdldE1hcC5hZGRMYXllcih7aWQ6bGluZSx0eXBlOidsaW5lJyxzb3VyY2UscGFpbnQ6eydsaW5lLWNvbG9yJzonIzAwY2ZlZScsJ2xpbmUtd2lkdGgnOjQsJ2xpbmUtb3BhY2l0eSc6Ljk1fX0pfQpmdW5jdGlvbiBzdG9wRmVhdHVyZXMoKXtyZXR1cm4ocHJvamVjdD8uc3RvcHN8fFtdKS5maWx0ZXIodmFsaWRQb2ludCkubWFwKChzLGkpPT4oe3R5cGU6J0ZlYXR1cmUnLGdlb21ldHJ5Ont0eXBlOidQb2ludCcsY29vcmRpbmF0ZXM6W051bWJlcihzLmxvbiksTnVtYmVyKHMubGF0KV19LHByb3BlcnRpZXM6e3N0b3BfaWQ6cy5zdG9wX2lkLGluZGV4OmkrMSxuYW1lOnN0b3BOYW1lKHMsaSl9fSkpfQpmdW5jdGlvbiBwaG90b0ZlYXR1cmVzKCl7cmV0dXJuKHByb2plY3Q/LmFzc2V0c3x8W10pLmZpbHRlcih2YWxpZFBvaW50KS5tYXAoYT0+KHt0eXBlOidGZWF0dXJlJyxnZW9tZXRyeTp7dHlwZTonUG9pbnQnLGNvb3JkaW5hdGVzOltOdW1iZXIoYS5sb24pLE51bWJlcihhLmxhdCldfSxwcm9wZXJ0aWVzOnthc3NldF9pZDphLmFzc2V0X2lkLG5hbWU6YS5uYW1lfHwnUGhvdG8nLHRpbWU6YS50aW1lfHwnJyxzdG9wX2lkOihwcm9qZWN0Py5zdG9wc3x8W10pLmZpbmQocz0+KHMuYXNzZXRfaWRzfHxbXSkuaW5jbHVkZXMoYS5hc3NldF9pZCkpPy5zdG9wX2lkfHwnJ319KSl9CmZ1bmN0aW9uIGFkZENsdXN0ZXJMYXllcnModGFyZ2V0TWFwLHByZWZpeCl7Y29uc3Qgc3RvcFNvdXJjZT1wcmVmaXgrJy1zdG9wcycscGhvdG9Tb3VyY2U9cHJlZml4KyctcGhvdG9zJztyZW1vdmVMYXllckFuZFNvdXJjZSh0YXJnZXRNYXAsW3ByZWZpeCsnLXN0b3AtY2x1c3Rlci1jb3VudCcscHJlZml4Kyctc3RvcC1jbHVzdGVycycscHJlZml4Kyctc3RvcC1udW1iZXInLHByZWZpeCsnLXN0b3AtcG9pbnRzJ10sc3RvcFNvdXJjZSk7cmVtb3ZlTGF5ZXJBbmRTb3VyY2UodGFyZ2V0TWFwLFtwcmVmaXgrJy1waG90by1jbHVzdGVyLWNvdW50JyxwcmVmaXgrJy1waG90by1jbHVzdGVycycscHJlZml4KyctcGhvdG8tcG9pbnRzJ10scGhvdG9Tb3VyY2UpO3RhcmdldE1hcC5hZGRTb3VyY2Uoc3RvcFNvdXJjZSx7dHlwZTonZ2VvanNvbicsY2x1c3Rlcjp0cnVlLGNsdXN0ZXJSYWRpdXM6NDgsY2x1c3Rlck1heFpvb206OSxkYXRhOnt0eXBlOidGZWF0dXJlQ29sbGVjdGlvbicsZmVhdHVyZXM6c3RvcEZlYXR1cmVzKCl9fSk7dGFyZ2V0TWFwLmFkZExheWVyKHtpZDpwcmVmaXgrJy1zdG9wLWNsdXN0ZXJzJyx0eXBlOidjaXJjbGUnLHNvdXJjZTpzdG9wU291cmNlLGZpbHRlcjpbJ2hhcycsJ3BvaW50X2NvdW50J10scGFpbnQ6eydjaXJjbGUtcmFkaXVzJzpbJ3N0ZXAnLFsnZ2V0JywncG9pbnRfY291bnQnXSwyMCwxMCwyNSw0MCwzMV0sJ2NpcmNsZS1jb2xvcic6JyMwNzEzMWYnLCdjaXJjbGUtc3Ryb2tlLWNvbG9yJzonIzAwZDhmZicsJ2NpcmNsZS1zdHJva2Utd2lkdGgnOjMsJ2NpcmNsZS1vcGFjaXR5JzouOTR9fSk7dGFyZ2V0TWFwLmFkZExheWVyKHtpZDpwcmVmaXgrJy1zdG9wLWNsdXN0ZXItY291bnQnLHR5cGU6J3N5bWJvbCcsc291cmNlOnN0b3BTb3VyY2UsZmlsdGVyOlsnaGFzJywncG9pbnRfY291bnQnXSxsYXlvdXQ6eyd0ZXh0LWZpZWxkJzpbJ2dldCcsJ3BvaW50X2NvdW50X2FiYnJldmlhdGVkJ10sJ3RleHQtc2l6ZSc6MTJ9LHBhaW50OnsndGV4dC1jb2xvcic6JyNmZmZmZmYnfX0pO3RhcmdldE1hcC5hZGRMYXllcih7aWQ6cHJlZml4Kyctc3RvcC1wb2ludHMnLHR5cGU6J2NpcmNsZScsc291cmNlOnN0b3BTb3VyY2UsZmlsdGVyOlsnIScsWydoYXMnLCdwb2ludF9jb3VudCddXSxwYWludDp7J2NpcmNsZS1yYWRpdXMnOjE3LCdjaXJjbGUtY29sb3InOicjMDcxMzFmJywnY2lyY2xlLXN0cm9rZS1jb2xvcic6JyMwMGQ4ZmYnLCdjaXJjbGUtc3Ryb2tlLXdpZHRoJzozLCdjaXJjbGUtb3BhY2l0eSc6Ljk1fX0pO3RhcmdldE1hcC5hZGRMYXllcih7aWQ6cHJlZml4Kyctc3RvcC1udW1iZXInLHR5cGU6J3N5bWJvbCcsc291cmNlOnN0b3BTb3VyY2UsZmlsdGVyOlsnIScsWydoYXMnLCdwb2ludF9jb3VudCddXSxsYXlvdXQ6eyd0ZXh0LWZpZWxkJzpbJ3RvLXN0cmluZycsWydnZXQnLCdpbmRleCddXSwndGV4dC1zaXplJzoxMX0scGFpbnQ6eyd0ZXh0LWNvbG9yJzonI2ZmZmZmZid9fSk7dGFyZ2V0TWFwLmFkZFNvdXJjZShwaG90b1NvdXJjZSx7dHlwZTonZ2VvanNvbicsY2x1c3Rlcjp0cnVlLGNsdXN0ZXJSYWRpdXM6NDIsY2x1c3Rlck1heFpvb206MTMsZGF0YTp7dHlwZTonRmVhdHVyZUNvbGxlY3Rpb24nLGZlYXR1cmVzOnBob3RvRmVhdHVyZXMoKX19KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOnByZWZpeCsnLXBob3RvLWNsdXN0ZXJzJyx0eXBlOidjaXJjbGUnLHNvdXJjZTpwaG90b1NvdXJjZSxmaWx0ZXI6WydoYXMnLCdwb2ludF9jb3VudCddLG1pbnpvb206OCxwYWludDp7J2NpcmNsZS1yYWRpdXMnOlsnc3RlcCcsWydnZXQnLCdwb2ludF9jb3VudCddLDE1LDgsMTksMjUsMjRdLCdjaXJjbGUtY29sb3InOicjMGEyMzMyJywnY2lyY2xlLXN0cm9rZS1jb2xvcic6JyM3ZGVhZmYnLCdjaXJjbGUtc3Ryb2tlLXdpZHRoJzoyLCdjaXJjbGUtb3BhY2l0eSc6Ljg4fX0pO3RhcmdldE1hcC5hZGRMYXllcih7aWQ6cHJlZml4KyctcGhvdG8tY2x1c3Rlci1jb3VudCcsdHlwZTonc3ltYm9sJyxzb3VyY2U6cGhvdG9Tb3VyY2UsZmlsdGVyOlsnaGFzJywncG9pbnRfY291bnQnXSxtaW56b29tOjgsbGF5b3V0OnsndGV4dC1maWVsZCc6WydnZXQnLCdwb2ludF9jb3VudF9hYmJyZXZpYXRlZCddLCd0ZXh0LXNpemUnOjEwfSxwYWludDp7J3RleHQtY29sb3InOicjZmZmZmZmJ319KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOnByZWZpeCsnLXBob3RvLXBvaW50cycsdHlwZTonY2lyY2xlJyxzb3VyY2U6cGhvdG9Tb3VyY2UsZmlsdGVyOlsnIScsWydoYXMnLCdwb2ludF9jb3VudCddXSxtaW56b29tOjExLHBhaW50OnsnY2lyY2xlLXJhZGl1cyc6WydpbnRlcnBvbGF0ZScsWydsaW5lYXInXSxbJ3pvb20nXSwxMSw0LDE1LDddLCdjaXJjbGUtY29sb3InOicjMDBkOGZmJywnY2lyY2xlLXN0cm9rZS1jb2xvcic6JyNmZmZmZmYnLCdjaXJjbGUtc3Ryb2tlLXdpZHRoJzoxLjUsJ2NpcmNsZS1vcGFjaXR5JzpbJ2ludGVycG9sYXRlJyxbJ2xpbmVhciddLFsnem9vbSddLDExLC42NSwxNCwuOSwxNSwwXX19KX0KZnVuY3Rpb24gZXhwYW5kQ2x1c3Rlcih0YXJnZXRNYXAsc291cmNlSWQsZmVhdHVyZSl7Y29uc3Qgc291cmNlPXRhcmdldE1hcC5nZXRTb3VyY2Uoc291cmNlSWQpO2lmKCFzb3VyY2UpcmV0dXJuO2NvbnN0IGNsdXN0ZXJJZD1mZWF0dXJlLnByb3BlcnRpZXMuY2x1c3Rlcl9pZDtjb25zdCByZXN1bHQ9c291cmNlLmdldENsdXN0ZXJFeHBhbnNpb25ab29tKGNsdXN0ZXJJZCk7aWYocmVzdWx0JiZ0eXBlb2YgcmVzdWx0LnRoZW49PT0nZnVuY3Rpb24nKXJlc3VsdC50aGVuKHpvb209PnRhcmdldE1hcC5lYXNlVG8oe2NlbnRlcjpmZWF0dXJlLmdlb21ldHJ5LmNvb3JkaW5hdGVzLHpvb20sZHVyYXRpb246NzAwfSkpO2Vsc2Ugc291cmNlLmdldENsdXN0ZXJFeHBhbnNpb25ab29tKGNsdXN0ZXJJZCwoZXJyLHpvb20pPT57aWYoIWVycil0YXJnZXRNYXAuZWFzZVRvKHtjZW50ZXI6ZmVhdHVyZS5nZW9tZXRyeS5jb29yZGluYXRlcyx6b29tLGR1cmF0aW9uOjcwMH0pfSl9CmZ1bmN0aW9uIGJpbmRNYXBJbnRlcmFjdGlvbnModGFyZ2V0TWFwLHByZWZpeCxpc1ByZXNlbnQ9ZmFsc2Upe2NvbnN0IGtleT0nX190cmlwcHlfJytwcmVmaXg7aWYodGFyZ2V0TWFwW2tleV0pcmV0dXJuO3RhcmdldE1hcFtrZXldPXRydWU7dGFyZ2V0TWFwLm9uKCdjbGljaycscHJlZml4Kyctc3RvcC1jbHVzdGVycycsZT0+ZXhwYW5kQ2x1c3Rlcih0YXJnZXRNYXAscHJlZml4Kyctc3RvcHMnLGUuZmVhdHVyZXNbMF0pKTt0YXJnZXRNYXAub24oJ2NsaWNrJyxwcmVmaXgrJy1waG90by1jbHVzdGVycycsZT0+ZXhwYW5kQ2x1c3Rlcih0YXJnZXRNYXAscHJlZml4KyctcGhvdG9zJyxlLmZlYXR1cmVzWzBdKSk7dGFyZ2V0TWFwLm9uKCdjbGljaycscHJlZml4Kyctc3RvcC1wb2ludHMnLGU9Pntjb25zdCBpZD1lLmZlYXR1cmVzPy5bMF0/LnByb3BlcnRpZXM/LnN0b3BfaWQ7aWYoaWQpe2NvbnN0IGk9KHByb2plY3Q/LnN0b3BzfHxbXSkuZmluZEluZGV4KHM9PnMuc3RvcF9pZD09PWlkKTtpc1ByZXNlbnQ/Z29QcmVzZW50U3RvcChpKTpzZWxlY3RTdG9wKGlkLHtmbHk6dHJ1ZSxwb3B1cDp0cnVlLGZpbHRlcjp0cnVlfSl9fSk7dGFyZ2V0TWFwLm9uKCdjbGljaycscHJlZml4Kyctc3RvcC1udW1iZXInLGU9Pntjb25zdCBpZD1lLmZlYXR1cmVzPy5bMF0/LnByb3BlcnRpZXM/LnN0b3BfaWQ7aWYoaWQpe2NvbnN0IGk9KHByb2plY3Q/LnN0b3BzfHxbXSkuZmluZEluZGV4KHM9PnMuc3RvcF9pZD09PWlkKTtpc1ByZXNlbnQ/Z29QcmVzZW50U3RvcChpKTpzZWxlY3RTdG9wKGlkLHtmbHk6dHJ1ZSxwb3B1cDp0cnVlLGZpbHRlcjp0cnVlfSl9fSk7dGFyZ2V0TWFwLm9uKCdjbGljaycscHJlZml4KyctcGhvdG8tcG9pbnRzJyxlPT57Y29uc3QgaWQ9ZS5mZWF0dXJlcz8uWzBdPy5wcm9wZXJ0aWVzPy5hc3NldF9pZDtpZihpZCl7aWYoaXNQcmVzZW50KXtjb25zdCBpPXByZXNlbnRBc3NldHMoKS5maW5kSW5kZXgoYT0+YS5hc3NldF9pZD09PWlkKTtpZihpPj0wKWdvUHJlc2VudFBob3RvKGkpfWVsc2UgZm9jdXNBc3NldChpZCl9fSk7W3ByZWZpeCsnLXN0b3AtY2x1c3RlcnMnLHByZWZpeCsnLXN0b3AtcG9pbnRzJyxwcmVmaXgrJy1zdG9wLW51bWJlcicscHJlZml4KyctcGhvdG8tY2x1c3RlcnMnLHByZWZpeCsnLXBob3RvLXBvaW50cyddLmZvckVhY2gobGF5ZXI9Pnt0YXJnZXRNYXAub24oJ21vdXNlZW50ZXInLGxheWVyLCgpPT50YXJnZXRNYXAuZ2V0Q2FudmFzKCkuc3R5bGUuY3Vyc29yPSdwb2ludGVyJyk7dGFyZ2V0TWFwLm9uKCdtb3VzZWxlYXZlJyxsYXllciwoKT0+dGFyZ2V0TWFwLmdldENhbnZhcygpLnN0eWxlLmN1cnNvcj0nJyl9KX0KZnVuY3Rpb24gYXNzZXRCdWJibGVFbGVtZW50KGFzc2V0LGFjdGl2ZT1mYWxzZSl7Y29uc3Qgbm9kZT1kb2N1bWVudC5jcmVhdGVFbGVtZW50KCdkaXYnKTtub2RlLmNsYXNzTmFtZT0nYXNzZXRCdWJibGUnKyhhY3RpdmU/JyBhY3RpdmUnOicnKTtub2RlLnRpdGxlPWZvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSk7bm9kZS5pbm5lckhUTUw9YXNzZXQudGh1bWI/YDxpbWcgc3JjPSIke2VzYyhhc3NldC50aHVtYil9IiBhbHQ9IiI+YDonPGRpdiBjbGFzcz0iYXNzZXREb3QiPuKAojwvZGl2Pic7cmV0dXJuIG5vZGV9CmZ1bmN0aW9uIHJlbmRlclNlbGVjdGVkUGhvdG9CdWJibGVzKCl7Y2xlYXJCdWJibGVNYXJrZXJzKHBob3RvTWFya2Vycyk7aWYoIW1hcHx8bWFwLmdldFpvb20oKTwxMy41fHwhYWN0aXZlU3RvcElkKXJldHVybjtjb25zdCBzdG9wPXByb2plY3Q/LnN0b3BzPy5maW5kKHM9PnMuc3RvcF9pZD09PWFjdGl2ZVN0b3BJZCk7c3RvcEFzc2V0cyhzdG9wKS5maWx0ZXIodmFsaWRQb2ludCkuc2xpY2UoMCwxMjApLmZvckVhY2goYXNzZXQ9Pntjb25zdCBub2RlPWFzc2V0QnViYmxlRWxlbWVudChhc3NldCxhc3NldC5hc3NldF9pZD09PWFjdGl2ZUFzc2V0SWQpO25vZGUub25jbGljaz0oKT0+Zm9jdXNBc3NldChhc3NldC5hc3NldF9pZCk7cGhvdG9NYXJrZXJzLnB1c2gobmV3IG1hcGxpYnJlZ2wuTWFya2VyKHtlbGVtZW50Om5vZGUsYW5jaG9yOidjZW50ZXInfSkuc2V0TG5nTGF0KFtOdW1iZXIoYXNzZXQubG9uKSxOdW1iZXIoYXNzZXQubGF0KV0pLmFkZFRvKG1hcCkpfSl9CmZ1bmN0aW9uIHJlbmRlck1hcChmaXQ9ZmFsc2Upe2Vuc3VyZU1hcCgpO2lmKCFtYXAuaXNTdHlsZUxvYWRlZCgpKXttYXAub25jZSgnbG9hZCcsKCk9PnJlbmRlck1hcChmaXQpKTtyZXR1cm59Y2xlYXJNYXBNYXJrZXJzKCk7Y29uc3Qgc3RvcHM9cHJvamVjdD8uc3RvcHN8fFtdO2lmKCFzdG9wcy5sZW5ndGgpcmV0dXJuO2FkZFJvdXRlTGF5ZXJzKG1hcCwnbWFpbicsc3RvcHMuZmlsdGVyKHZhbGlkUG9pbnQpLm1hcChzPT5bTnVtYmVyKHMubG9uKSxOdW1iZXIocy5sYXQpXSkpO2FkZENsdXN0ZXJMYXllcnMobWFwLCdtYWluJyk7YmluZE1hcEludGVyYWN0aW9ucyhtYXAsJ21haW4nLGZhbHNlKTtjb25zdCBib3VuZHM9bmV3IG1hcGxpYnJlZ2wuTG5nTGF0Qm91bmRzKCk7c3RvcHMuZmlsdGVyKHZhbGlkUG9pbnQpLmZvckVhY2gocz0+Ym91bmRzLmV4dGVuZChbTnVtYmVyKHMubG9uKSxOdW1iZXIocy5sYXQpXSkpO2lmKGZpdCYmIWJvdW5kcy5pc0VtcHR5KCkpe3RyeXttYXAuZml0Qm91bmRzKGJvdW5kcyx7cGFkZGluZzp7dG9wOjg1LGJvdHRvbTo5MCxsZWZ0Ojk1LHJpZ2h0Ojk1fSxtYXhab29tOjE0LjgsZHVyYXRpb246ODUwfSl9Y2F0Y2h7fX1zZXRUaW1lb3V0KHJlbmRlclNlbGVjdGVkUGhvdG9CdWJibGVzLDgwKX0KZnVuY3Rpb24gc2V0TWFwU3R5bGUoa2V5KXtpZighTUFQX1NUWUxFU1trZXldKXJldHVybjttYXBTdHlsZUtleT1rZXk7bG9jYWxTdG9yYWdlLnNldEl0ZW0oJ3RyaXBweV9tYXBfc3R5bGUnLGtleSk7WydsaWdodCcsJ2RhcmsnLCdzYXRlbGxpdGUnXS5mb3JFYWNoKGs9PmVsKGsrJ01hcEJ1dHRvbicpLmNsYXNzTGlzdC50b2dnbGUoJ2FjdGl2ZScsaz09PWtleSkpO2VsKCdkZWZhdWx0TWFwU2VsZWN0JykudmFsdWU9a2V5O2lmKG1hcCl7bWFwLnNldFN0eWxlKGNsb25lU3R5bGUoa2V5KSk7bWFwLm9uY2UoJ3N0eWxlLmxvYWQnLCgpPT5yZW5kZXJNYXAoZmFsc2UpKX19CmZ1bmN0aW9uIGJlYXJpbmcoYSxiKXtjb25zdCB5PU1hdGguc2luKChiLmxvbi1hLmxvbikqTWF0aC5QSS8xODApKk1hdGguY29zKGIubGF0Kk1hdGguUEkvMTgwKTtjb25zdCB4PU1hdGguY29zKGEubGF0Kk1hdGguUEkvMTgwKSpNYXRoLnNpbihiLmxhdCpNYXRoLlBJLzE4MCktTWF0aC5zaW4oYS5sYXQqTWF0aC5QSS8xODApKk1hdGguY29zKGIubGF0Kk1hdGguUEkvMTgwKSpNYXRoLmNvcygoYi5sb24tYS5sb24pKk1hdGguUEkvMTgwKTtyZXR1cm4oTWF0aC5hdGFuMih5LHgpKjE4MC9NYXRoLlBJKzM2MCklMzYwfQpmdW5jdGlvbiBzZWxlY3RTdG9wKGlkLHtmbHk9dHJ1ZSxwb3B1cD10cnVlLGZpbHRlcj10cnVlfT17fSl7aWYoIXByb2plY3QpcmV0dXJuO2NvbnN0IGluZGV4PShwcm9qZWN0LnN0b3BzfHxbXSkuZmluZEluZGV4KHM9PnMuc3RvcF9pZD09PWlkKTtpZihpbmRleDwwKXJldHVybjtjb25zdCBzdG9wPXByb2plY3Quc3RvcHNbaW5kZXhdO2FjdGl2ZVN0b3BJZD1pZDtpZihmaWx0ZXIpZmlsdGVyU3RvcElkPWlkO3JlbmRlclN0b3BzKCk7cmVuZGVyR2FsbGVyeSgpO3JlbmRlck1hcChmYWxzZSk7aWYoZmx5JiZtYXApe2NvbnN0IG5leHQ9cHJvamVjdC5zdG9wc1tNYXRoLm1pbihpbmRleCsxLHByb2plY3Quc3RvcHMubGVuZ3RoLTEpXXx8c3RvcDttYXAuZmx5VG8oe2NlbnRlcjpbc3RvcC5sb24sc3RvcC5sYXRdLHpvb206MTUuNyxwaXRjaDo0MixiZWFyaW5nOmJlYXJpbmcoc3RvcCxuZXh0KSxkdXJhdGlvbjoxMDUwLGVzc2VudGlhbDp0cnVlfSl9aWYocG9wdXApc2V0VGltZW91dCgoKT0+c2hvd1N0b3BQb3B1cChzdG9wLGluZGV4KSw0NTApfQpmdW5jdGlvbiBzaG93U3RvcFBvcHVwKHN0b3AsaW5kZXgpe2lmKGFjdGl2ZVBvcHVwKXt0cnl7YWN0aXZlUG9wdXAucmVtb3ZlKCl9Y2F0Y2h7fX1jb25zdCBhc3NldHM9c3RvcEFzc2V0cyhzdG9wKSxmaXJzdD1hc3NldHNbMF07Y29uc3QgY29udGVudD1gPGRpdiBjbGFzcz0ic3RvcFBvcHVwIj48ZGl2IGNsYXNzPSJzdG9wUG9wdXBJbWFnZSI+JHtmaXJzdD8udGh1bWI/YDxpbWcgc3JjPSIke2VzYyhmaXJzdC50aHVtYil9Ij5gOicnfTwvZGl2PjxkaXYgY2xhc3M9InN0b3BQb3B1cEJvZHkiPjxzcGFuIGNsYXNzPSJwb3B1cEtpY2tlciI+U3RvcCAke2luZGV4KzF9PC9zcGFuPjxkaXYgY2xhc3M9InBvcHVwVGl0bGUiPiR7ZXNjKHN0b3BOYW1lKHN0b3AsaW5kZXgpKX08L2Rpdj48ZGl2IGNsYXNzPSJwb3B1cE1ldGEiPiR7YXNzZXRzLmxlbmd0aH0gcGhvdG9zJm5ic3A7IOKAoiAmbmJzcDske01hdGgucm91bmQoc3RvcC5yYWRpdXNfbXx8MjAwKX0gbSByYWRpdXM8L2Rpdj48ZGl2IGNsYXNzPSJwb3B1cEJ1dHRvbnMiPjxidXR0b24gZGF0YS1wb3B1cC1maWx0ZXI9IiR7ZXNjKHN0b3Auc3RvcF9pZCl9Ij5WaWV3IFBob3RvczwvYnV0dG9uPjxidXR0b24gZGF0YS1wb3B1cC1wcmVzZW50PSIke2luZGV4fSI+4pa2IFByZXNlbnQ8L2J1dHRvbj48YnV0dG9uIGNsYXNzPSJkYW5nZXIiIGRhdGEtcG9wdXAtZGVsZXRlPSIke2VzYyhzdG9wLnN0b3BfaWQpfSI+4oyrPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+YDthY3RpdmVQb3B1cD1uZXcgbWFwbGlicmVnbC5Qb3B1cCh7b2Zmc2V0OjI0LGNsb3NlQnV0dG9uOnRydWUsbWF4V2lkdGg6JzM1MHB4J30pLnNldExuZ0xhdChbc3RvcC5sb24sc3RvcC5sYXRdKS5zZXRIVE1MKGNvbnRlbnQpLmFkZFRvKG1hcCk7c2V0VGltZW91dCgoKT0+e2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoJ1tkYXRhLXBvcHVwLWZpbHRlcl0nKT8uYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT57ZmlsdGVyU3RvcElkPXN0b3Auc3RvcF9pZDtyZW5kZXJHYWxsZXJ5KCl9KTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCdbZGF0YS1wb3B1cC1wcmVzZW50XScpPy5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9Pm9wZW5QcmVzZW50KGluZGV4KSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvcignW2RhdGEtcG9wdXAtZGVsZXRlXScpPy5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PmRlbGV0ZVN0b3Aoc3RvcC5zdG9wX2lkKSl9LDApfQpmdW5jdGlvbiByZW5kZXJTdG9wcygpe2NvbnN0IHN0b3BzPXByb2plY3Q/LnN0b3BzfHxbXSxxPWVsKCdzdG9wU2VhcmNoJykudmFsdWUudHJpbSgpLnRvTG93ZXJDYXNlKCk7ZWwoJ3N0b3BDb3VudCcpLnRleHRDb250ZW50PWAoJHtzdG9wcy5sZW5ndGh9KWA7ZWwoJ3N0b3BMaXN0JykuaW5uZXJIVE1MPXN0b3BzLm1hcCgocyxpKT0+KHtzLGl9KSkuZmlsdGVyKHg9PiFxfHxzdG9wTmFtZSh4LnMseC5pKS50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKHEpKS5tYXAoKHtzLGl9KT0+e2NvbnN0IGNvdW50PShzLmFzc2V0X2lkc3x8W10pLmxlbmd0aCxhY3RpdmU9cy5zdG9wX2lkPT09YWN0aXZlU3RvcElkO3JldHVybmA8YXJ0aWNsZSBjbGFzcz0ic3RvcENhcmQgJHthY3RpdmU/J2FjdGl2ZSBvcGVuJzonJ30iIGRhdGEtc3RvcD0iJHtlc2Mocy5zdG9wX2lkKX0iPjxkaXYgY2xhc3M9InN0b3BTdW1tYXJ5Ij48ZGl2IGNsYXNzPSJzdG9wTnVtYmVyIj4ke2krMX08L2Rpdj48ZGl2PjxkaXYgY2xhc3M9InN0b3BOYW1lIj4ke2VzYyhzdG9wTmFtZShzLGkpKX08L2Rpdj48ZGl2IGNsYXNzPSJzdG9wTWV0YSI+JHtjb3VudH0gcGhvdG9zJm5ic3A7IOKAoiAmbmJzcDske2VzYyhzdG9wRGF0ZVJhbmdlKHMpKX08L2Rpdj48L2Rpdj48ZGl2IGNsYXNzPSJzdG9wQ2hldnJvbiI+4oC6PC9kaXY+PC9kaXY+PGRpdiBjbGFzcz0ic3RvcENvbnRyb2xzIj48YnV0dG9uIGRhdGEtdmlldz0iJHtlc2Mocy5zdG9wX2lkKX0iPlZpZXc8L2J1dHRvbj48YnV0dG9uIGRhdGEtcmVuYW1lPSIke2VzYyhzLnN0b3BfaWQpfSI+UmVuYW1lPC9idXR0b24+PGJ1dHRvbiBkYXRhLXJlY2VudGVyPSIke2VzYyhzLnN0b3BfaWQpfSI+UmVjZW50ZXI8L2J1dHRvbj48YnV0dG9uIGRhdGEtZGVsZXRlLXN0b3A9IiR7ZXNjKHMuc3RvcF9pZCl9Ij5EZWxldGU8L2J1dHRvbj48L2Rpdj48L2FydGljbGU+YH0pLmpvaW4oJycpfHwnPGRpdiBjbGFzcz0ic21hbGwiPk5vIHN0b3BzIGZvdW5kLjwvZGl2Pic7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnLnN0b3BTdW1tYXJ5JykuZm9yRWFjaChyb3c9PnJvdy5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9Pntjb25zdCBjYXJkPXJvdy5jbG9zZXN0KCcuc3RvcENhcmQnKTtjb25zdCBpZD1jYXJkLmRhdGFzZXQuc3RvcDtpZihhY3RpdmVTdG9wSWQ9PT1pZCljYXJkLmNsYXNzTGlzdC50b2dnbGUoJ29wZW4nKTtlbHNlIHNlbGVjdFN0b3AoaWQse2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KX0pKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS12aWV3XScpLmZvckVhY2goYj0+Yi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PnNlbGVjdFN0b3AoYi5kYXRhc2V0LnZpZXcse2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXJlbmFtZV0nKS5mb3JFYWNoKGI9PmIuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5yZW5hbWVTdG9wKGIuZGF0YXNldC5yZW5hbWUpKSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtcmVjZW50ZXJdJykuZm9yRWFjaChiPT5iLmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+cmVjZW50ZXJTdG9wKGIuZGF0YXNldC5yZWNlbnRlcikpKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1kZWxldGUtc3RvcF0nKS5mb3JFYWNoKGI9PmIuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5kZWxldGVTdG9wKGIuZGF0YXNldC5kZWxldGVTdG9wKSkpfQpmdW5jdGlvbiBnYWxsZXJ5QXNzZXRzKCl7aWYoIXByb2plY3QpcmV0dXJuW107aWYoZmlsdGVyU3RvcElkKXtjb25zdCBzdG9wPXByb2plY3Quc3RvcHMuZmluZChzPT5zLnN0b3BfaWQ9PT1maWx0ZXJTdG9wSWQpO3JldHVybiBzdG9wQXNzZXRzKHN0b3ApfXJldHVybiBwcm9qZWN0LmFzc2V0c3x8W119CmZ1bmN0aW9uIHJlbmRlckdhbGxlcnkoKXtjb25zdCBhc3NldHM9Z2FsbGVyeUFzc2V0cygpLHN0b3A9cHJvamVjdD8uc3RvcHM/LmZpbmQocz0+cy5zdG9wX2lkPT09ZmlsdGVyU3RvcElkKSxpZHg9c3RvcD9wcm9qZWN0LnN0b3BzLmluZGV4T2Yoc3RvcCk6LTE7ZWwoJ21lZGlhVGl0bGUnKS50ZXh0Q29udGVudD1zdG9wP2BTdG9wICR7aWR4KzF9ICDigKIgICR7c3RvcE5hbWUoc3RvcCxpZHgpfWA6J01lZGlhJztlbCgnbWVkaWFDb3VudCcpLnRleHRDb250ZW50PWAke2Fzc2V0cy5sZW5ndGh9IGl0ZW1zYDtlbCgnZmlsdGVyQ2hpcCcpLmNsYXNzTGlzdC50b2dnbGUoJ3Nob3cnLCEhc3RvcCk7ZWwoJ2ZpbHRlckNoaXBUZXh0JykudGV4dENvbnRlbnQ9c3RvcD9gRmlsdGVyOiAke3N0b3BOYW1lKHN0b3AsaWR4KX1gOidGaWx0ZXI6IEFsbCBTdG9wcyc7ZWwoJ2dhbGxlcnknKS5pbm5lckhUTUw9YXNzZXRzLm1hcCgoYSxpKT0+YDxkaXYgY2xhc3M9Im1lZGlhVGlsZSAke2EuYXNzZXRfaWQ9PT1hY3RpdmVBc3NldElkPydhY3RpdmUnOicnfSIgZGF0YS1hc3NldD0iJHtlc2MoYS5hc3NldF9pZCl9Ij4ke2EudGh1bWI/YDxpbWcgc3JjPSIke2VzYyhhLnRodW1iKX0iPmA6Jyd9PGJ1dHRvbiBjbGFzcz0ibWVkaWFUaWxlUmVtb3ZlIiBkYXRhLXJlbW92ZS1hc3NldD0iJHtlc2MoYS5hc3NldF9pZCl9IiB0aXRsZT0iUmVtb3ZlIGZyb20gam91cm5leSI+w5c8L2J1dHRvbj48ZGl2IGNsYXNzPSJtZWRpYVRpbGVOYW1lIj4ke2VzYyhmb3JtYXRBc3NldERhdGVUaW1lKGEudGltZSl8fGBQaG90byAke2krMX1gKX08L2Rpdj48L2Rpdj5gKS5qb2luKCcnKXx8JzxkaXYgY2xhc3M9InNtYWxsIj5ObyBHUFMgbWVkaWEgaW4gdGhpcyB2aWV3LjwvZGl2Pic7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnLm1lZGlhVGlsZScpLmZvckVhY2godGlsZT0+dGlsZS5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PmZvY3VzQXNzZXQodGlsZS5kYXRhc2V0LmFzc2V0KSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXJlbW92ZS1hc3NldF0nKS5mb3JFYWNoKGJ1dHRvbj0+YnV0dG9uLmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJyxldmVudD0+e2V2ZW50LnN0b3BQcm9wYWdhdGlvbigpO3JlbW92ZUFzc2V0RnJvbUpvdXJuZXkoYnV0dG9uLmRhdGFzZXQucmVtb3ZlQXNzZXQpfSkpfQpmdW5jdGlvbiBmb2N1c0Fzc2V0KGlkKXtjb25zdCBhc3NldD0ocHJvamVjdD8uYXNzZXRzfHxbXSkuZmluZChhPT5hLmFzc2V0X2lkPT09aWQpO2lmKCFhc3NldHx8IXZhbGlkUG9pbnQoYXNzZXQpKXJldHVybjthY3RpdmVBc3NldElkPWlkO3JlbmRlckdhbGxlcnkoKTtyZW5kZXJTZWxlY3RlZFBob3RvQnViYmxlcygpO2lmKG1hcCltYXAuZmx5VG8oe2NlbnRlcjpbTnVtYmVyKGFzc2V0LmxvbiksTnVtYmVyKGFzc2V0LmxhdCldLHpvb206MTguNyxwaXRjaDo1MCxiZWFyaW5nOjEwLGR1cmF0aW9uOjk1MCxlc3NlbnRpYWw6dHJ1ZX0pO2lmKGFjdGl2ZVBvcHVwKXt0cnl7YWN0aXZlUG9wdXAucmVtb3ZlKCl9Y2F0Y2h7fX1hY3RpdmVQb3B1cD1uZXcgbWFwbGlicmVnbC5Qb3B1cCh7b2Zmc2V0OjI0LGNsb3NlQnV0dG9uOnRydWUsbWF4V2lkdGg6JzQyMHB4J30pLnNldExuZ0xhdChbTnVtYmVyKGFzc2V0LmxvbiksTnVtYmVyKGFzc2V0LmxhdCldKS5zZXRIVE1MKGA8ZGl2IGNsYXNzPSJzdG9wUG9wdXAiPjxkaXYgY2xhc3M9InN0b3BQb3B1cEltYWdlIj4ke2Fzc2V0LnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoYXNzZXQudGh1bWIpfSI+YDonJ308L2Rpdj48ZGl2IGNsYXNzPSJzdG9wUG9wdXBCb2R5Ij48c3BhbiBjbGFzcz0icG9wdXBLaWNrZXIiPlNlbGVjdGVkIHBob3RvPC9zcGFuPjxkaXYgY2xhc3M9InBvcHVwVGl0bGUiPiR7ZXNjKGFzc2V0Lm5hbWV8fCdQaG90bycpfTwvZGl2PjxkaXYgY2xhc3M9InBvcHVwTWV0YSI+JHtlc2MoZm9ybWF0QXNzZXREYXRlVGltZShhc3NldC50aW1lKSl9PC9kaXY+PC9kaXY+PC9kaXY+YCkuYWRkVG8obWFwKX0KYXN5bmMgZnVuY3Rpb24gc2F2ZVByb2plY3QoKXtpZighcHJvamVjdClyZXR1cm47cHJvamVjdD1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdC8nK2VuY29kZVVSSUNvbXBvbmVudChwcm9qZWN0LmlkKSx7bWV0aG9kOidQVVQnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sYm9keTpKU09OLnN0cmluZ2lmeShwcm9qZWN0KX0pO2F3YWl0IHJlZnJlc2hQcm9qZWN0U3VtbWFyeSgpO3JlbmRlckFsbCgpfWFzeW5jIGZ1bmN0aW9uIHJlbW92ZUFzc2V0RnJvbUpvdXJuZXkoYXNzZXRJZCl7aWYoIXByb2plY3QpcmV0dXJuO2NvbnN0IGFzc2V0PShwcm9qZWN0LmFzc2V0c3x8W10pLmZpbmQoYT0+YS5hc3NldF9pZD09PWFzc2V0SWQpO2lmKCFhc3NldClyZXR1cm47aWYoIWNvbmZpcm0oJ1JlbW92ZSB0aGlzIGltYWdlIGZyb20gdGhpcyBUcmlwcHkgam91cm5leT8gVGhlIG9yaWdpbmFsIGZpbGUgd2lsbCByZW1haW4gdW50b3VjaGVkIGluIEltbWljaC4nKSlyZXR1cm47cHJvamVjdC5hc3NldHM9KHByb2plY3QuYXNzZXRzfHxbXSkuZmlsdGVyKGE9PmEuYXNzZXRfaWQhPT1hc3NldElkKTtwcm9qZWN0LnN0b3BzPShwcm9qZWN0LnN0b3BzfHxbXSkubWFwKHN0b3A9Pntjb25zdCBpZHM9KHN0b3AuYXNzZXRfaWRzfHxbXSkuZmlsdGVyKGlkPT5pZCE9PWFzc2V0SWQpO2lmKCFpZHMubGVuZ3RoKXJldHVybiBudWxsO2NvbnN0IHBvaW50cz1wcm9qZWN0LmFzc2V0cy5maWx0ZXIoYT0+aWRzLmluY2x1ZGVzKGEuYXNzZXRfaWQpJiZ2YWxpZFBvaW50KGEpKTtpZihwb2ludHMubGVuZ3RoKXtzdG9wLmxhdD1wb2ludHMucmVkdWNlKChzdW0sYSk9PnN1bStOdW1iZXIoYS5sYXQpLDApL3BvaW50cy5sZW5ndGg7c3RvcC5sb249cG9pbnRzLnJlZHVjZSgoc3VtLGEpPT5zdW0rTnVtYmVyKGEubG9uKSwwKS9wb2ludHMubGVuZ3RofXN0b3AuYXNzZXRfaWRzPWlkcztyZXR1cm4gc3RvcH0pLmZpbHRlcihCb29sZWFuKTthY3RpdmVBc3NldElkPW51bGw7aWYoZmlsdGVyU3RvcElkJiYhcHJvamVjdC5zdG9wcy5zb21lKHM9PnMuc3RvcF9pZD09PWZpbHRlclN0b3BJZCkpZmlsdGVyU3RvcElkPW51bGw7YXdhaXQgc2F2ZVByb2plY3QoKTt0b2FzdCgnUmVtb3ZlZCBmcm9tIHRoaXMgam91cm5leS4gVGhlIG9yaWdpbmFsIHJlbWFpbnMgaW4gSW1taWNoLicpO2lmKGVsKCdwcmVzZW50T3ZlcmxheScpLmNsYXNzTGlzdC5jb250YWlucygnc2hvdycpKXtpZighcHJvamVjdC5zdG9wcy5sZW5ndGgpe2Nsb3NlUHJlc2VudCgpO3JldHVybn1wcmVzZW50U3RvcEluZGV4PU1hdGgubWluKHByZXNlbnRTdG9wSW5kZXgscHJvamVjdC5zdG9wcy5sZW5ndGgtMSk7Y29uc3QgYXNzZXRzPXByZXNlbnRBc3NldHMoKTtwcmVzZW50UGhvdG9JbmRleD1NYXRoLm1pbihwcmVzZW50UGhvdG9JbmRleCxhc3NldHMubGVuZ3RoLTEpO3JlbmRlclByZXNlbnRNYXBMYXllcnMoKTtpZihwcmVzZW50UGhvdG9JbmRleD49MCYmYXNzZXRzLmxlbmd0aClnb1ByZXNlbnRQaG90byhwcmVzZW50UGhvdG9JbmRleCk7ZWxzZSBnb1ByZXNlbnRTdG9wKHByZXNlbnRTdG9wSW5kZXgpfX0KYXN5bmMgZnVuY3Rpb24gcmVmcmVzaFByb2plY3RTdW1tYXJ5KCl7cHJvamVjdHM9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3RzJyl9CmFzeW5jIGZ1bmN0aW9uIHJlbmFtZVByb2plY3QoKXtpZighcHJvamVjdClyZXR1cm47Y29uc3QgdmFsdWU9cHJvbXB0KCdKb3VybmV5IG5hbWUnLHByb2plY3QubmFtZXx8JycpO2lmKCF2YWx1ZT8udHJpbSgpKXJldHVybjtwcm9qZWN0Lm5hbWU9dmFsdWUudHJpbSgpO3Byb2plY3Quc2V0dGluZ3M9cHJvamVjdC5zZXR0aW5nc3x8e307cHJvamVjdC5zZXR0aW5ncy50aXRsZT1wcm9qZWN0Lm5hbWU7YXdhaXQgc2F2ZVByb2plY3QoKX0KYXN5bmMgZnVuY3Rpb24gcmVuYW1lU3RvcChpZCl7Y29uc3QgaT1wcm9qZWN0LnN0b3BzLmZpbmRJbmRleChzPT5zLnN0b3BfaWQ9PT1pZCk7aWYoaTwwKXJldHVybjtjb25zdCB2YWx1ZT1wcm9tcHQoJ1N0b3AgbmFtZScsc3RvcE5hbWUocHJvamVjdC5zdG9wc1tpXSxpKSk7aWYoIXZhbHVlPy50cmltKCkpcmV0dXJuO3Byb2plY3Quc3RvcHNbaV0ubmFtZT12YWx1ZS50cmltKCk7YXdhaXQgc2F2ZVByb2plY3QoKX0KYXN5bmMgZnVuY3Rpb24gcmVjZW50ZXJTdG9wKGlkKXtjb25zdCBzdG9wPXByb2plY3Quc3RvcHMuZmluZChzPT5zLnN0b3BfaWQ9PT1pZCksYXNzZXRzPXN0b3BBc3NldHMoc3RvcCk7aWYoIXN0b3B8fCFhc3NldHMubGVuZ3RoKXJldHVybiB0b2FzdCgnVGhpcyBzdG9wIGhhcyBubyBwaG90b3MgdG8gcmVjZW50ZXIgZnJvbS4nKTtzdG9wLmxhdD1hc3NldHMucmVkdWNlKChuLGEpPT5uK051bWJlcihhLmxhdCksMCkvYXNzZXRzLmxlbmd0aDtzdG9wLmxvbj1hc3NldHMucmVkdWNlKChuLGEpPT5uK051bWJlcihhLmxvbiksMCkvYXNzZXRzLmxlbmd0aDthd2FpdCBzYXZlUHJvamVjdCgpO3NlbGVjdFN0b3AoaWQse2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KX0KYXN5bmMgZnVuY3Rpb24gZGVsZXRlU3RvcChpZCl7aWYoIWNvbmZpcm0oJ0RlbGV0ZSB0aGlzIHN0b3A/IFBob3RvcyByZW1haW4gaW4gdGhlIGpvdXJuZXkuJykpcmV0dXJuO3Byb2plY3Quc3RvcHM9cHJvamVjdC5zdG9wcy5maWx0ZXIocz0+cy5zdG9wX2lkIT09aWQpO2lmKGFjdGl2ZVN0b3BJZD09PWlkKWFjdGl2ZVN0b3BJZD1wcm9qZWN0LnN0b3BzWzBdPy5zdG9wX2lkfHxudWxsO2lmKGZpbHRlclN0b3BJZD09PWlkKWZpbHRlclN0b3BJZD1hY3RpdmVTdG9wSWQ7YXdhaXQgc2F2ZVByb2plY3QoKX0KYXN5bmMgZnVuY3Rpb24gYWRkU3RvcCgpe2lmKCFwcm9qZWN0fHwhbWFwKXJldHVybiB0b2FzdCgnTG9hZCBhIGpvdXJuZXkgZmlyc3QuJyk7Y29uc3QgY2VudGVyPW1hcC5nZXRDZW50ZXIoKTtwcm9qZWN0LnN0b3BzPXByb2plY3Quc3RvcHN8fFtdO2NvbnN0IHN0b3A9e3N0b3BfaWQ6Y3J5cHRvLnJhbmRvbVVVSUQoKS5zbGljZSgwLDgpLG5hbWU6YFN0b3AgJHtwcm9qZWN0LnN0b3BzLmxlbmd0aCsxfWAsbGF0OmNlbnRlci5sYXQsbG9uOmNlbnRlci5sbmcscmFkaXVzX206TnVtYmVyKHByb2plY3Quc2V0dGluZ3M/LnN0b3BfcmFkaXVzX218fDIwMCksYXNzZXRfaWRzOltdLG1vZGU6J21hbnVhbCcsbG9ja2VkOmZhbHNlfTtwcm9qZWN0LnN0b3BzLnB1c2goc3RvcCk7YXdhaXQgc2F2ZVByb2plY3QoKTtzZWxlY3RTdG9wKHN0b3Auc3RvcF9pZCx7Zmx5OnRydWUscG9wdXA6dHJ1ZSxmaWx0ZXI6dHJ1ZX0pfQphc3luYyBmdW5jdGlvbiByZWNsdXN0ZXIoKXtpZighcHJvamVjdClyZXR1cm47Y29uc3QgcmFkaXVzPU51bWJlcihlbCgnc3RvcFJhZGl1cycpLnZhbHVlfHwyMDApO3Byb2plY3Q9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytlbmNvZGVVUklDb21wb25lbnQocHJvamVjdC5pZCkrJy9yZWNsdXN0ZXInLHttZXRob2Q6J1BPU1QnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sYm9keTpKU09OLnN0cmluZ2lmeSh7cmFkaXVzX206cmFkaXVzfSl9KTtwcm9qZWN0LnNldHRpbmdzPXByb2plY3Quc2V0dGluZ3N8fHt9O3Byb2plY3Quc2V0dGluZ3Muc3RvcF9yYWRpdXNfbT1yYWRpdXM7YWN0aXZlU3RvcElkPXByb2plY3Quc3RvcHNbMF0/LnN0b3BfaWR8fG51bGw7ZmlsdGVyU3RvcElkPWFjdGl2ZVN0b3BJZDthd2FpdCByZWZyZXNoUHJvamVjdFN1bW1hcnkoKTtyZW5kZXJBbGwoKTtzZXRNb2RhbCgnc2V0dGluZ3NNb2RhbCcsZmFsc2UpO3RvYXN0KCdTdG9wcyByZWNsdXN0ZXJlZCcpfQphc3luYyBmdW5jdGlvbiByZXZlcnNlUm91dGUoKXtpZighcHJvamVjdClyZXR1cm47cHJvamVjdC5zdG9wcy5yZXZlcnNlKCk7cHJvamVjdC5zZXR0aW5ncz1wcm9qZWN0LnNldHRpbmdzfHx7fTtwcm9qZWN0LnNldHRpbmdzLnJldmVyc2Vfcm91dGU9IXByb2plY3Quc2V0dGluZ3MucmV2ZXJzZV9yb3V0ZTthd2FpdCBzYXZlUHJvamVjdCgpO3RvYXN0KCdSb3V0ZSBvcmRlciByZXZlcnNlZCcpfQphc3luYyBmdW5jdGlvbiB0ZXN0SW1taWNoKCl7Y29uc3QgYm9keT17YmFzZV91cmw6ZWwoJ2ltbWljaFVybCcpLnZhbHVlLnRyaW0oKSxhcGlfa2V5OmVsKCdpbW1pY2hLZXknKS52YWx1ZS50cmltKCl9O2NvbnN0IHJlc3VsdD1hd2FpdCBhcGkoJy9hcGkvaW1taWNoL3Rlc3QnLHttZXRob2Q6J1BPU1QnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sYm9keTpKU09OLnN0cmluZ2lmeShib2R5KX0pO3RvYXN0KHJlc3VsdC5tZXNzYWdlfHwnQ29ubmVjdGlvbiB0ZXN0ZWQnKX0KYXN5bmMgZnVuY3Rpb24gY3JlYXRlSW1taWNoSm91cm5leSgpe2NvbnN0IGJhc2VfdXJsPWVsKCdpbW1pY2hVcmwnKS52YWx1ZS50cmltKCksYXBpX2tleT1lbCgnaW1taWNoS2V5JykudmFsdWUudHJpbSgpLHN0YXJ0X2RhdGU9ZWwoJ3N0YXJ0RGF0ZScpLnZhbHVlLGVuZF9kYXRlPWVsKCdlbmREYXRlJykudmFsdWU7aWYoIWJhc2VfdXJsfHwhYXBpX2tleXx8IXN0YXJ0X2RhdGV8fCFlbmRfZGF0ZSlyZXR1cm4gdG9hc3QoJ0NvbXBsZXRlIHRoZSBJbW1pY2ggVVJMLCBrZXksIGFuZCBkYXRlcy4nKTtzYXZlQ29ubihiYXNlX3VybCxhcGlfa2V5KTt0b2FzdCgnSW1wb3J0aW5nIEdQUyBtZWRpYSBmcm9tIEltbWljaOKApicpO2NvbnN0IGNyZWF0ZWQ9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvaW1taWNoJyx7bWV0aG9kOidQT1NUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkoe25hbWU6YEltbWljaCBKb3VybmV5ICR7c3RhcnRfZGF0ZX0gdG8gJHtlbmRfZGF0ZX1gLGJhc2VfdXJsLGFwaV9rZXksc3RhcnRfZGF0ZSxlbmRfZGF0ZX0pfSk7c2V0TW9kYWwoJ2ltbWljaE1vZGFsJyxmYWxzZSk7YXdhaXQgcmVmcmVzaFByb2plY3RTdW1tYXJ5KCk7YXdhaXQgb3BlblByb2plY3QoY3JlYXRlZC5pZCl9CmFzeW5jIGZ1bmN0aW9uIGNyZWF0ZVVwbG9hZEpvdXJuZXkoKXtjb25zdCBmaWxlcz1lbCgndXBsb2FkRmlsZXMnKS5maWxlcztpZighZmlsZXMubGVuZ3RoKXJldHVybiB0b2FzdCgnQ2hvb3NlIG1lZGlhIGZpbGVzIGZpcnN0LicpO2NvbnN0IGZvcm09bmV3IEZvcm1EYXRhKCk7Zm9yKGNvbnN0IGZpbGUgb2YgZmlsZXMpZm9ybS5hcHBlbmQoJ2ZpbGVzJyxmaWxlKTtmb3JtLmFwcGVuZCgnbmFtZScsZWwoJ3VwbG9hZE5hbWUnKS52YWx1ZS50cmltKCl8fCdVcGxvYWRlZCBKb3VybmV5Jyk7dG9hc3QoJ1JlYWRpbmcgR1BTIG1ldGFkYXRh4oCmJyk7Y29uc3QgY3JlYXRlZD1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdC91cGxvYWQnLHttZXRob2Q6J1BPU1QnLGJvZHk6Zm9ybX0pO3NldE1vZGFsKCd1cGxvYWRNb2RhbCcsZmFsc2UpO2F3YWl0IHJlZnJlc2hQcm9qZWN0U3VtbWFyeSgpO2F3YWl0IG9wZW5Qcm9qZWN0KGNyZWF0ZWQuaWQpfQphc3luYyBmdW5jdGlvbiByZW5kZXJNcDQoKXtpZighcHJvamVjdClyZXR1cm4gdG9hc3QoJ0xvYWQgYSBqb3VybmV5IGZpcnN0LicpO3Byb2plY3Quc2V0dGluZ3M9cHJvamVjdC5zZXR0aW5nc3x8e307cHJvamVjdC5zZXR0aW5ncy5kdXJhdGlvbl9taW49MTI7YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytlbmNvZGVVUklDb21wb25lbnQocHJvamVjdC5pZCkse21ldGhvZDonUFVUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkocHJvamVjdCl9KTtjb25zdCBmb3JtPW5ldyBGb3JtRGF0YSgpO2lmKGVsKCdhdWRpb1N3aXRjaCcpLmNsYXNzTGlzdC5jb250YWlucygnb24nKSYmZWwoJ2F1ZGlvSW5wdXQnKS5maWxlc1swXSlmb3JtLmFwcGVuZCgnYXVkaW8nLGVsKCdhdWRpb0lucHV0JykuZmlsZXNbMF0pO3RvYXN0KCdSZW5kZXJpbmcgTVA04oCmJyk7Y29uc3QgcmVzdWx0PWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KHByb2plY3QuaWQpKycvcmVuZGVyJyx7bWV0aG9kOidQT1NUJyxib2R5OmZvcm19KTtjb25zdCB1cmw9cmVzdWx0LnVybHx8cmVzdWx0LnBhdGh8fHJlc3VsdC5kb3dubG9hZF91cmw7aWYodXJsKXdpbmRvdy5vcGVuKHVybCwnX2JsYW5rJyk7dG9hc3QoJ1JlbmRlciBjb21wbGV0ZScpfQpmdW5jdGlvbiBlbnN1cmVQcmVzZW50TWFwKCl7aWYocHJlc2VudE1hcClyZXR1cm47cHJlc2VudE1hcD1uZXcgbWFwbGlicmVnbC5NYXAoe2NvbnRhaW5lcjoncHJlc2VudE1hcCcsc3R5bGU6Y2xvbmVTdHlsZShtYXBTdHlsZUtleT09PSdsaWdodCc/J3NhdGVsbGl0ZSc6bWFwU3R5bGVLZXkpLGNlbnRlcjpbLTk4LDM5XSx6b29tOjMsbWF4Wm9vbToyMCxwaXRjaDo1NSxiZWFyaW5nOjB9KTtwcmVzZW50TWFwLmFkZENvbnRyb2wobmV3IG1hcGxpYnJlZ2wuTmF2aWdhdGlvbkNvbnRyb2woKSwnYm90dG9tLXJpZ2h0Jyk7cHJlc2VudE1hcC5vbignem9vbWVuZCcscmVuZGVyUHJlc2VudFBob3RvQnViYmxlcyk7cHJlc2VudE1hcC5vbignbW92ZWVuZCcscmVuZGVyUHJlc2VudFBob3RvQnViYmxlcyk7cHJlc2VudE1hcC5vbignZXJyb3InLGV2ZW50PT57Y29uc3QgbWVzc2FnZT1TdHJpbmcoZXZlbnQ/LmVycm9yPy5tZXNzYWdlfHwnJyk7aWYobWFwU3R5bGVLZXk9PT0nc2F0ZWxsaXRlJyYmL3RpbGV8c291cmNlfDQwNHw0MDMvaS50ZXN0KG1lc3NhZ2UpKXt0b2FzdCgnU2F0ZWxsaXRlIGltYWdlcnkgaXMgbGltaXRlZCBoZXJlOyB1c2luZyB0aGUgY2xvc2VzdCBhdmFpbGFibGUgdGlsZS4nKX19KX0KZnVuY3Rpb24gcHJlc2VudEFzc2V0cygpe2NvbnN0IHN0b3A9cHJvamVjdD8uc3RvcHM/LltwcmVzZW50U3RvcEluZGV4XTtyZXR1cm4gc3RvcEFzc2V0cyhzdG9wKX0KZnVuY3Rpb24gcmVuZGVyUHJlc2VudFN0b3BzKCl7Y29uc3Qgc3RvcHM9cHJvamVjdD8uc3RvcHN8fFtdO2VsKCdwcmVzZW50U3RvcFJhaWwnKS5pbm5lckhUTUw9YDxkaXYgc3R5bGU9ImZvbnQtd2VpZ2h0Ojk1MDttYXJnaW46MnB4IDRweCAxMHB4Ij5Kb3VybmV5IFN0b3BzPC9kaXY+YCtzdG9wcy5tYXAoKHMsaSk9PmA8ZGl2IGNsYXNzPSJwcmVzZW50U3RvcEl0ZW0gJHtpPT09cHJlc2VudFN0b3BJbmRleD8nYWN0aXZlJzonJ30iIGRhdGEtcHJlc2VudC1zdG9wPSIke2l9Ij48Yj4ke2krMX0uPC9iPiZuYnNwOyAke2VzYyhzdG9wTmFtZShzLGkpKX08ZGl2IGNsYXNzPSJzbWFsbCI+JHsocy5hc3NldF9pZHN8fFtdKS5sZW5ndGh9IHBob3Rvczxicj4ke2VzYyhzdG9wRGF0ZVJhbmdlKHMpKX08L2Rpdj48L2Rpdj5gKS5qb2luKCcnKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1wcmVzZW50LXN0b3BdJykuZm9yRWFjaCh4PT54LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+Z29QcmVzZW50U3RvcChOdW1iZXIoeC5kYXRhc2V0LnByZXNlbnRTdG9wKSkpKX0KZnVuY3Rpb24gcmVuZGVyUHJlc2VudEZpbG1zdHJpcCgpe2NvbnN0IGFzc2V0cz1wcmVzZW50QXNzZXRzKCk7ZWwoJ3ByZXNlbnRGaWxtc3RyaXAnKS5pbm5lckhUTUw9YXNzZXRzLm1hcCgoYSxpKT0+YDxkaXYgY2xhc3M9InByZXNlbnRUaHVtYiAke2k9PT1wcmVzZW50UGhvdG9JbmRleD8nYWN0aXZlJzonJ30iIGRhdGEtcHJlc2VudC1waG90bz0iJHtpfSI+JHthLnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoYS50aHVtYil9Ij5gOicnfTxkaXYgY2xhc3M9InByZXNlbnRUaHVtYkxhYmVsIj5QaG90byAke2krMX08YnI+JHtlc2MoZm9ybWF0QXNzZXREYXRlVGltZShhLnRpbWUpKX08L2Rpdj48L2Rpdj5gKS5qb2luKCcnKXx8JzxkaXYgY2xhc3M9InNtYWxsIj5ObyBwaG90b3MgYXNzaWduZWQgdG8gdGhpcyBzdG9wLjwvZGl2Pic7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtcHJlc2VudC1waG90b10nKS5mb3JFYWNoKHg9PnguYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5nb1ByZXNlbnRQaG90byhOdW1iZXIoeC5kYXRhc2V0LnByZXNlbnRQaG90bykpKSl9CmZ1bmN0aW9uIHJlbmRlclByZXNlbnRNYXBMYXllcnMoKXtpZighcHJlc2VudE1hcHx8IXByZXNlbnRNYXAuaXNTdHlsZUxvYWRlZCgpKXJldHVybjtjbGVhckJ1YmJsZU1hcmtlcnMocHJlc2VudE1hcmtlcnMpO2NsZWFyQnViYmxlTWFya2VycyhwcmVzZW50UGhvdG9NYXJrZXJzKTtjb25zdCBzdG9wcz1wcm9qZWN0Py5zdG9wc3x8W107YWRkUm91dGVMYXllcnMocHJlc2VudE1hcCwncHJlc2VudCcsc3RvcHMuZmlsdGVyKHZhbGlkUG9pbnQpLm1hcChzPT5bTnVtYmVyKHMubG9uKSxOdW1iZXIocy5sYXQpXSkpO2FkZENsdXN0ZXJMYXllcnMocHJlc2VudE1hcCwncHJlc2VudCcpO2JpbmRNYXBJbnRlcmFjdGlvbnMocHJlc2VudE1hcCwncHJlc2VudCcsdHJ1ZSk7cmVuZGVyUHJlc2VudFBob3RvQnViYmxlcygpfQpmdW5jdGlvbiByZW5kZXJQcmVzZW50UGhvdG9CdWJibGVzKCl7Y2xlYXJCdWJibGVNYXJrZXJzKHByZXNlbnRQaG90b01hcmtlcnMpO2lmKCFwcmVzZW50TWFwfHwhcHJvamVjdD8uc3RvcHM/Lmxlbmd0aClyZXR1cm47Y29uc3QgYWxsPXByZXNlbnRBc3NldHMoKTthbGwuZmlsdGVyKHZhbGlkUG9pbnQpLnNsaWNlKDAsMTQwKS5mb3JFYWNoKGFzc2V0PT57Y29uc3QgaT1hbGwuZmluZEluZGV4KGE9PmEuYXNzZXRfaWQ9PT1hc3NldC5hc3NldF9pZCk7Y29uc3Qgbm9kZT1hc3NldEJ1YmJsZUVsZW1lbnQoYXNzZXQsaT09PXByZXNlbnRQaG90b0luZGV4KTtub2RlLm9uY2xpY2s9KCk9PmdvUHJlc2VudFBob3RvKGkpO3ByZXNlbnRQaG90b01hcmtlcnMucHVzaChuZXcgbWFwbGlicmVnbC5NYXJrZXIoe2VsZW1lbnQ6bm9kZSxhbmNob3I6J2NlbnRlcid9KS5zZXRMbmdMYXQoW051bWJlcihhc3NldC5sb24pLE51bWJlcihhc3NldC5sYXQpXSkuYWRkVG8ocHJlc2VudE1hcCkpfSl9ZnVuY3Rpb24gc3RvcFByZXNlbnRPcmJpdCgpe2NsZWFyVGltZW91dChwcmVzZW50T3JiaXREZWxheSk7Y2xlYXJJbnRlcnZhbChwcmVzZW50T3JiaXRUaW1lcik7cHJlc2VudE9yYml0RGVsYXk9bnVsbDtwcmVzZW50T3JiaXRUaW1lcj1udWxsfWZ1bmN0aW9uIHN0YXJ0UHJlc2VudE9yYml0KGNlbnRlcix6b29tLHBpdGNoPTU2KXtzdG9wUHJlc2VudE9yYml0KCk7Y29uc3Qgb3JiaXQ9KCk9PntpZighcHJlc2VudE1hcHx8IWVsKCdwcmVzZW50T3ZlcmxheScpLmNsYXNzTGlzdC5jb250YWlucygnc2hvdycpKXJldHVybjtwcmVzZW50TWFwLmVhc2VUbyh7Y2VudGVyLHpvb206TWF0aC5taW4oem9vbSwxOC4xNSkscGl0Y2gsYmVhcmluZzoocHJlc2VudE1hcC5nZXRCZWFyaW5nKCkrMTYpJTM2MCxkdXJhdGlvbjo1MjAwLGVhc2luZzp0PT50LGVzc2VudGlhbDp0cnVlfSl9O3ByZXNlbnRPcmJpdERlbGF5PXNldFRpbWVvdXQoKCk9PntvcmJpdCgpO3ByZXNlbnRPcmJpdFRpbWVyPXNldEludGVydmFsKG9yYml0LDUyNTApfSwxMjUwKX1mdW5jdGlvbiBjbGVhclByZXNlbnRGb2N1cygpe2lmKHByZXNlbnRGb2N1c01hcmtlcil7cHJlc2VudEZvY3VzTWFya2VyLnJlbW92ZSgpO3ByZXNlbnRGb2N1c01hcmtlcj1udWxsfX1mdW5jdGlvbiBzaG93UHJlc2VudEZvY3VzKGl0ZW0pe2NsZWFyUHJlc2VudEZvY3VzKCk7aWYoIXZhbGlkUG9pbnQoaXRlbSl8fCFwcmVzZW50TWFwKXJldHVybjtjb25zdCBub2RlPWRvY3VtZW50LmNyZWF0ZUVsZW1lbnQoJ2RpdicpO25vZGUuY2xhc3NOYW1lPSdmb2N1c1B1bHNlJztwcmVzZW50Rm9jdXNNYXJrZXI9bmV3IG1hcGxpYnJlZ2wuTWFya2VyKHtlbGVtZW50Om5vZGUsYW5jaG9yOidjZW50ZXInfSkuc2V0TG5nTGF0KFtOdW1iZXIoaXRlbS5sb24pLE51bWJlcihpdGVtLmxhdCldKS5hZGRUbyhwcmVzZW50TWFwKX1mdW5jdGlvbiB0cmlwQm91bmRzKCl7Y29uc3QgYm91bmRzPW5ldyBtYXBsaWJyZWdsLkxuZ0xhdEJvdW5kcygpOyhwcm9qZWN0Py5zdG9wc3x8W10pLmZpbHRlcih2YWxpZFBvaW50KS5mb3JFYWNoKHM9PmJvdW5kcy5leHRlbmQoW051bWJlcihzLmxvbiksTnVtYmVyKHMubGF0KV0pKTtyZXR1cm4gYm91bmRzfWZ1bmN0aW9uIGNlbnRlclByZXNlbnRUcmlwKCl7aWYoIXByZXNlbnRNYXB8fCFwcm9qZWN0Py5zdG9wcz8ubGVuZ3RoKXJldHVybjtzdG9wUHJlc2VudE9yYml0KCk7cHJlc2VudFZpZXc9J3RyaXAnO2NvbnN0IGJvdW5kcz10cmlwQm91bmRzKCk7aWYoIWJvdW5kcy5pc0VtcHR5KCkpcHJlc2VudE1hcC5maXRCb3VuZHMoYm91bmRzLHtwYWRkaW5nOnt0b3A6MTEwLGJvdHRvbToxMTAsbGVmdDoyODUscmlnaHQ6ODB9LG1heFpvb206MTIuOCxkdXJhdGlvbjoxNTAwLGVzc2VudGlhbDp0cnVlfSk7Y29uc3Qgc2VsZWN0ZWQ9cHJlc2VudFBob3RvSW5kZXg+PTA/cHJlc2VudEFzc2V0cygpW3ByZXNlbnRQaG90b0luZGV4XTpwcm9qZWN0LnN0b3BzW3ByZXNlbnRTdG9wSW5kZXhdO3Nob3dQcmVzZW50Rm9jdXMoc2VsZWN0ZWQpO2VsKCdwcmVzZW50U3RvcEJhbm5lclRpdGxlJykudGV4dENvbnRlbnQ9cHJvamVjdC5uYW1lfHwnSm91cm5leSBPdmVydmlldyc7ZWwoJ3ByZXNlbnRTdG9wQmFubmVyUmFuZ2UnKS50ZXh0Q29udGVudD1gJHtwcm9qZWN0LnN0b3BzLmxlbmd0aH0gc3RvcHMgIOKAoiAgJHsocHJvamVjdC5hc3NldHN8fFtdKS5sZW5ndGh9IHBob3Rvc2A7ZWwoJ3ByZXNlbnRQaG90b0NhcmQnKS5jbGFzc0xpc3QucmVtb3ZlKCdzaG93Jyl9ZnVuY3Rpb24gcHJlc2VudEJhY2soKXtpZihwcmVzZW50Vmlldz09PSdwaG90bycpe2dvUHJlc2VudFN0b3AocHJlc2VudFN0b3BJbmRleCk7cmV0dXJufWlmKHByZXNlbnRWaWV3PT09J3N0b3AnKXtjZW50ZXJQcmVzZW50VHJpcCgpO3JldHVybn1jZW50ZXJQcmVzZW50VHJpcCgpfWZ1bmN0aW9uIHJldHVyblByZXNlbnRTdGFydCgpe3ByZXNlbnRTdG9wSW5kZXg9MDtwcmVzZW50UGhvdG9JbmRleD0tMTtnb1ByZXNlbnRTdG9wKDApfQpmdW5jdGlvbiBnb1ByZXNlbnRTdG9wKGluZGV4KXtjb25zdCBzdG9wcz1wcm9qZWN0Py5zdG9wc3x8W107aWYoIXN0b3BzLmxlbmd0aClyZXR1cm47c3RvcFByZXNlbnRPcmJpdCgpO2NsZWFyUHJlc2VudEZvY3VzKCk7cHJlc2VudFZpZXc9J3N0b3AnO3ByZXNlbnRTdG9wSW5kZXg9KGluZGV4K3N0b3BzLmxlbmd0aCklc3RvcHMubGVuZ3RoO3ByZXNlbnRQaG90b0luZGV4PS0xO2NvbnN0IHN0b3A9c3RvcHNbcHJlc2VudFN0b3BJbmRleF0sbmV4dD1zdG9wc1socHJlc2VudFN0b3BJbmRleCsxKSVzdG9wcy5sZW5ndGhdfHxzdG9wO3JlbmRlclByZXNlbnRTdG9wcygpO3JlbmRlclByZXNlbnRGaWxtc3RyaXAoKTtyZW5kZXJQcmVzZW50UGhvdG9CdWJibGVzKCk7Y29uc3QgcmFuZ2U9c3RvcERhdGVSYW5nZShzdG9wKTtlbCgncHJlc2VudEhlYWRlclRpdGxlJykudGV4dENvbnRlbnQ9c3RvcE5hbWUoc3RvcCxwcmVzZW50U3RvcEluZGV4KTtlbCgncHJlc2VudEhlYWRlck1ldGEnKS50ZXh0Q29udGVudD1gU3RvcCAke3ByZXNlbnRTdG9wSW5kZXgrMX0gb2YgJHtzdG9wcy5sZW5ndGh9IOKAoiAkeyhzdG9wLmFzc2V0X2lkc3x8W10pLmxlbmd0aH0gcGhvdG9zIOKAoiAke3JhbmdlfWA7ZWwoJ3ByZXNlbnRTdG9wQmFubmVyVGl0bGUnKS50ZXh0Q29udGVudD1zdG9wTmFtZShzdG9wLHByZXNlbnRTdG9wSW5kZXgpO2VsKCdwcmVzZW50U3RvcEJhbm5lclJhbmdlJykudGV4dENvbnRlbnQ9YFN0b3AgJHtwcmVzZW50U3RvcEluZGV4KzF9IG9mICR7c3RvcHMubGVuZ3RofSAg4oCiICAke3JhbmdlfSAg4oCiICAkeyhzdG9wLmFzc2V0X2lkc3x8W10pLmxlbmd0aH0gcGhvdG9zYDtlbCgncHJlc2VudFBob3RvQ2FyZCcpLmNsYXNzTGlzdC5yZW1vdmUoJ3Nob3cnKTtzaG93UHJlc2VudEZvY3VzKHN0b3ApO2NvbnN0IGRhdGE9c3RvcEJvdW5kcyhzdG9wKSxjZW50ZXI9dmFsaWRQb2ludChzdG9wKT9bTnVtYmVyKHN0b3AubG9uKSxOdW1iZXIoc3RvcC5sYXQpXTpkYXRhLmFzc2V0cy5sZW5ndGg/W051bWJlcihkYXRhLmFzc2V0c1swXS5sb24pLE51bWJlcihkYXRhLmFzc2V0c1swXS5sYXQpXTpudWxsO2lmKGRhdGEuYXNzZXRzLmxlbmd0aD4xJiYhZGF0YS5ib3VuZHMuaXNFbXB0eSgpKXtwcmVzZW50TWFwLmZpdEJvdW5kcyhkYXRhLmJvdW5kcyx7cGFkZGluZzp7dG9wOjEzMCxib3R0b206MjAwLGxlZnQ6Mjg1LHJpZ2h0OjQzMH0sbWF4Wm9vbToxNi4xNSxkdXJhdGlvbjoxNzAwLGVzc2VudGlhbDp0cnVlfSk7c2V0VGltZW91dCgoKT0+e3ByZXNlbnRNYXAuZWFzZVRvKHtwaXRjaDo1OCxiZWFyaW5nOmJlYXJpbmcoc3RvcCxuZXh0KSxkdXJhdGlvbjo3MDAsZXNzZW50aWFsOnRydWV9KTtpZihjZW50ZXIpc3RhcnRQcmVzZW50T3JiaXQoY2VudGVyLE1hdGgubWluKHByZXNlbnRNYXAuZ2V0Wm9vbSgpLDE2LjE1KSw1OCl9LDk1MCl9ZWxzZSBpZihjZW50ZXIpe3ByZXNlbnRNYXAuZmx5VG8oe2NlbnRlcix6b29tOjE2LHBpdGNoOjU4LGJlYXJpbmc6YmVhcmluZyhzdG9wLG5leHQpLGR1cmF0aW9uOjE2MDAsY3VydmU6MS40NSxlc3NlbnRpYWw6dHJ1ZX0pO3N0YXJ0UHJlc2VudE9yYml0KGNlbnRlciwxNiw1OCl9fQpmdW5jdGlvbiBnb1ByZXNlbnRQaG90byhpbmRleCl7Y29uc3QgYXNzZXRzPXByZXNlbnRBc3NldHMoKTtpZighYXNzZXRzLmxlbmd0aClyZXR1cm47c3RvcFByZXNlbnRPcmJpdCgpO3ByZXNlbnRWaWV3PSdwaG90byc7cHJlc2VudFBob3RvSW5kZXg9KGluZGV4K2Fzc2V0cy5sZW5ndGgpJWFzc2V0cy5sZW5ndGg7Y29uc3QgYXNzZXQ9YXNzZXRzW3ByZXNlbnRQaG90b0luZGV4XTtpZighdmFsaWRQb2ludChhc3NldCkpcmV0dXJuO3JlbmRlclByZXNlbnRGaWxtc3RyaXAoKTtyZW5kZXJQcmVzZW50UGhvdG9CdWJibGVzKCk7c2hvd1ByZXNlbnRGb2N1cyhhc3NldCk7ZWwoJ3ByZXNlbnRTdG9wQmFubmVyVGl0bGUnKS50ZXh0Q29udGVudD1zdG9wTmFtZShwcm9qZWN0LnN0b3BzW3ByZXNlbnRTdG9wSW5kZXhdLHByZXNlbnRTdG9wSW5kZXgpO2VsKCdwcmVzZW50U3RvcEJhbm5lclJhbmdlJykudGV4dENvbnRlbnQ9YFBob3RvICR7cHJlc2VudFBob3RvSW5kZXgrMX0gb2YgJHthc3NldHMubGVuZ3RofSAg4oCiICAke2Zvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSl9YDtlbCgncHJlc2VudFBob3RvQ2FyZCcpLmlubmVySFRNTD1gJHthc3NldC5wcmV2aWV3fHxhc3NldC50aHVtYj9gPGltZyBzcmM9IiR7ZXNjKGFzc2V0LnByZXZpZXd8fGFzc2V0LnRodW1iKX0iPmA6Jyd9PGRpdiBjbGFzcz0icHJlc2VudFBob3RvQm9keSI+PGRpdiBjbGFzcz0icHJlc2VudFBob3RvVGl0bGUiPlBob3RvICR7cHJlc2VudFBob3RvSW5kZXgrMX0gb2YgJHthc3NldHMubGVuZ3RofTwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRQaG90b01ldGEiPiR7ZXNjKGZvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSkpfTwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRQaG90b0Nvb3JkcyI+JHtlc2MoYXNzZXRDb29yZGluYXRlVGV4dChhc3NldCkpfTwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRQaG90b0FjdGlvbnMiPjxidXR0b24gb25jbGljaz0iZ29QcmVzZW50U3RvcChwcmVzZW50U3RvcEluZGV4KSI+QmFjayB0byBTdG9wPC9idXR0b24+PGJ1dHRvbiBjbGFzcz0iZGFuZ2VyIiBvbmNsaWNrPSJyZW1vdmVBc3NldEZyb21Kb3VybmV5KCcke2VzYyhhc3NldC5hc3NldF9pZCl9JykiPlJlbW92ZSBmcm9tIEpvdXJuZXk8L2J1dHRvbj48L2Rpdj48L2Rpdj5gO2VsKCdwcmVzZW50UGhvdG9DYXJkJykuY2xhc3NMaXN0LmFkZCgnc2hvdycpO2NvbnN0IGNlbnRlcj1bTnVtYmVyKGFzc2V0LmxvbiksTnVtYmVyKGFzc2V0LmxhdCldLHpvb209MTcuNjU7cHJlc2VudE1hcC5mbHlUbyh7Y2VudGVyLHpvb20scGl0Y2g6NTAsYmVhcmluZzoocHJlc2VudFBob3RvSW5kZXgqMTcpJTM2MCxkdXJhdGlvbjoxMzUwLGN1cnZlOjEuMyxlc3NlbnRpYWw6dHJ1ZX0pO3N0YXJ0UHJlc2VudE9yYml0KGNlbnRlcix6b29tLDUwKX0KZnVuY3Rpb24gb3BlblByZXNlbnQoaW5kZXg9MCl7aWYoIXByb2plY3Q/LnN0b3BzPy5sZW5ndGgpcmV0dXJuIHRvYXN0KCdMb2FkIGEgam91cm5leSB3aXRoIHN0b3BzIGZpcnN0LicpO2VsKCdwcmVzZW50T3ZlcmxheScpLmNsYXNzTGlzdC5hZGQoJ3Nob3cnKTtlbnN1cmVQcmVzZW50TWFwKCk7c2V0VGltZW91dCgoKT0+e3ByZXNlbnRNYXAucmVzaXplKCk7aWYocHJlc2VudE1hcC5pc1N0eWxlTG9hZGVkKCkpe3JlbmRlclByZXNlbnRNYXBMYXllcnMoKTtnb1ByZXNlbnRTdG9wKGluZGV4KX1lbHNlIHByZXNlbnRNYXAub25jZSgnbG9hZCcsKCk9PntyZW5kZXJQcmVzZW50TWFwTGF5ZXJzKCk7Z29QcmVzZW50U3RvcChpbmRleCl9KX0sOTApfQpmdW5jdGlvbiBjbG9zZVByZXNlbnQoKXtjbGVhckludGVydmFsKHByZXNlbnRUaW1lcik7cHJlc2VudFRpbWVyPW51bGw7c3RvcFByZXNlbnRPcmJpdCgpO2NsZWFyUHJlc2VudEZvY3VzKCk7ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykudGV4dENvbnRlbnQ9J+KWtiBQbGF5JztlbCgncHJlc2VudE92ZXJsYXknKS5jbGFzc0xpc3QucmVtb3ZlKCdzaG93Jyl9CmZ1bmN0aW9uIHRvZ2dsZVBsYXkoKXtpZihwcmVzZW50VGltZXIpe2NsZWFySW50ZXJ2YWwocHJlc2VudFRpbWVyKTtwcmVzZW50VGltZXI9bnVsbDtlbCgncGxheUpvdXJuZXlCdXR0b24nKS50ZXh0Q29udGVudD0n4pa2IFBsYXknO3JldHVybn1lbCgncGxheUpvdXJuZXlCdXR0b24nKS50ZXh0Q29udGVudD0n4oWhIFBhdXNlJztwcmVzZW50VGltZXI9c2V0SW50ZXJ2YWwoKCk9Pntjb25zdCBhc3NldHM9cHJlc2VudEFzc2V0cygpO2lmKGFzc2V0cy5sZW5ndGgmJnByZXNlbnRQaG90b0luZGV4PGFzc2V0cy5sZW5ndGgtMSlnb1ByZXNlbnRQaG90byhwcmVzZW50UGhvdG9JbmRleCsxKTtlbHNlIGdvUHJlc2VudFN0b3AocHJlc2VudFN0b3BJbmRleCsxKX0sNDMwMCl9CmZ1bmN0aW9uIGRvd25sb2FkR3B4KCl7aWYoIXByb2plY3QpcmV0dXJuO2NvbnN0IHBvaW50cz0ocHJvamVjdC5zdG9wc3x8W10pLm1hcCgocyxpKT0+YDx3cHQgbGF0PSIke3MubGF0fSIgbG9uPSIke3MubG9ufSI+PG5hbWU+JHtlc2Moc3RvcE5hbWUocyxpKSl9PC9uYW1lPjwvd3B0PmApLmpvaW4oJycpO2NvbnN0IGdweD1gPD94bWwgdmVyc2lvbj0iMS4wIj8+PGdweCB2ZXJzaW9uPSIxLjEiIGNyZWF0b3I9IlRyaXBweSI+JHtwb2ludHN9PC9ncHg+YDtjb25zdCBibG9iPW5ldyBCbG9iKFtncHhdLHt0eXBlOidhcHBsaWNhdGlvbi9ncHgreG1sJ30pLGE9ZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgnYScpO2EuaHJlZj1VUkwuY3JlYXRlT2JqZWN0VVJMKGJsb2IpO2EuZG93bmxvYWQ9KHByb2plY3QubmFtZXx8J3RyaXBweScpKycuZ3B4JzthLmNsaWNrKCk7VVJMLnJldm9rZU9iamVjdFVSTChhLmhyZWYpfQpmdW5jdGlvbiBiaW5kKCl7ZWwoJ25ld0ltbWljaEJ1dHRvbicpLm9uY2xpY2s9KCk9PnNldE1vZGFsKCdpbW1pY2hNb2RhbCcpO2VsKCd1cGxvYWRCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNb2RhbCgndXBsb2FkTW9kYWwnKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1jbG9zZV0nKS5mb3JFYWNoKGI9PmIub25jbGljaz0oKT0+c2V0TW9kYWwoYi5kYXRhc2V0LmNsb3NlLGZhbHNlKSk7ZWwoJ3Byb2plY3RTZWFyY2hCdXR0b24nKS5vbmNsaWNrPSgpPT5lbCgncHJvamVjdFNlYXJjaCcpLmNsYXNzTGlzdC50b2dnbGUoJ2hpZGRlbicpO2VsKCdwcm9qZWN0U2VhcmNoJykub25pbnB1dD1yZW5kZXJQcm9qZWN0cztlbCgncmVuYW1lUHJvamVjdEJ1dHRvbicpLm9uY2xpY2s9cmVuYW1lUHJvamVjdDtlbCgncHJlc2VudEJ1dHRvbicpLm9uY2xpY2s9KCk9Pm9wZW5QcmVzZW50KDApO2VsKCdleHBvcnRKdW1wQnV0dG9uJykub25jbGljaz0oKT0+e2VsKCdleHBvcnRCb3gnKS5jbGFzc0xpc3QucmVtb3ZlKCdjb2xsYXBzZWQnKTtlbCgnZXhwb3J0Qm94Jykuc2Nyb2xsSW50b1ZpZXcoe2JlaGF2aW9yOidzbW9vdGgnLGJsb2NrOidlbmQnfSl9O2VsKCdzZXR0aW5nc0J1dHRvbicpLm9uY2xpY2s9KCk9PntlbCgnc3RvcFJhZGl1cycpLnZhbHVlPXByb2plY3Q/LnNldHRpbmdzPy5zdG9wX3JhZGl1c19tfHwyMDA7c2V0TW9kYWwoJ3NldHRpbmdzTW9kYWwnKX07ZWwoJ2FjY291bnRCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNb2RhbCgnYWNjb3VudE1vZGFsJyk7ZWwoJ3NhdmVBY2NvdW50QnV0dG9uJykub25jbGljaz0oKT0+e3NhdmVDb25uKGVsKCdhY2NvdW50VXJsJykudmFsdWUudHJpbSgpLGVsKCdhY2NvdW50S2V5JykudmFsdWUudHJpbSgpKTt0b2FzdCgnSW1taWNoIGNvbm5lY3Rpb24gc2F2ZWQnKTtzZXRNb2RhbCgnYWNjb3VudE1vZGFsJyxmYWxzZSl9O2VsKCd0ZXN0SW1taWNoQnV0dG9uJykub25jbGljaz0oKT0+dGVzdEltbWljaCgpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdjcmVhdGVKb3VybmV5QnV0dG9uJykub25jbGljaz0oKT0+Y3JlYXRlSW1taWNoSm91cm5leSgpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdjcmVhdGVVcGxvYWRCdXR0b24nKS5vbmNsaWNrPSgpPT5jcmVhdGVVcGxvYWRKb3VybmV5KCkuY2F0Y2goZT0+dG9hc3QoZS5tZXNzYWdlKSk7ZWwoJ3N0b3BTZWFyY2hCdXR0b24nKS5vbmNsaWNrPSgpPT5lbCgnc3RvcFNlYXJjaFdyYXAnKS5jbGFzc0xpc3QudG9nZ2xlKCdzaG93Jyk7ZWwoJ3N0b3BTZWFyY2gnKS5vbmlucHV0PXJlbmRlclN0b3BzO2VsKCdhZGRTdG9wQnV0dG9uJykub25jbGljaz1hZGRTdG9wO2VsKCdleHBvcnRIZWFkZXInKS5vbmNsaWNrPSgpPT5lbCgnZXhwb3J0Qm94JykuY2xhc3NMaXN0LnRvZ2dsZSgnY29sbGFwc2VkJyk7ZWwoJ2F1ZGlvU3dpdGNoJykub25jbGljaz0oKT0+e2VsKCdhdWRpb1N3aXRjaCcpLmNsYXNzTGlzdC50b2dnbGUoJ29uJyk7aWYoZWwoJ2F1ZGlvU3dpdGNoJykuY2xhc3NMaXN0LmNvbnRhaW5zKCdvbicpKWVsKCdhdWRpb0lucHV0JykuY2xpY2soKX07ZWwoJ3JlbmRlckJ1dHRvbicpLm9uY2xpY2s9KCk9PnJlbmRlck1wNCgpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdncHhCdXR0b24nKS5vbmNsaWNrPWRvd25sb2FkR3B4O2VsKCdpbWFnZVNldEJ1dHRvbicpLm9uY2xpY2s9KCk9PnRvYXN0KCdJbWFnZSBTZXQgZXhwb3J0IGlzIGNvbWluZyBuZXh0LicpO2VsKCdjbGVhckZpbHRlckJ1dHRvbicpLm9uY2xpY2s9KCk9PntmaWx0ZXJTdG9wSWQ9bnVsbDthY3RpdmVTdG9wSWQ9bnVsbDtyZW5kZXJHYWxsZXJ5KCk7cmVuZGVyU3RvcHMoKTtyZW5kZXJNYXAoZmFsc2UpfTtlbCgnbG9jYXRlQnV0dG9uJykub25jbGljaz0oKT0+bmF2aWdhdG9yLmdlb2xvY2F0aW9uPy5nZXRDdXJyZW50UG9zaXRpb24ocD0+bWFwLmZseVRvKHtjZW50ZXI6W3AuY29vcmRzLmxvbmdpdHVkZSxwLmNvb3Jkcy5sYXRpdHVkZV0sem9vbToxNSxkdXJhdGlvbjo5MDB9KSwoKT0+dG9hc3QoJ0xvY2F0aW9uIHVuYXZhaWxhYmxlJykpO2VsKCd6b29tSW5CdXR0b24nKS5vbmNsaWNrPSgpPT5tYXA/Lnpvb21JbigpO2VsKCd6b29tT3V0QnV0dG9uJykub25jbGljaz0oKT0+bWFwPy56b29tT3V0KCk7ZWwoJ2xpZ2h0TWFwQnV0dG9uJykub25jbGljaz0oKT0+c2V0TWFwU3R5bGUoJ2xpZ2h0Jyk7ZWwoJ2RhcmtNYXBCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNYXBTdHlsZSgnZGFyaycpO2VsKCdzYXRlbGxpdGVNYXBCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNYXBTdHlsZSgnc2F0ZWxsaXRlJyk7ZWwoJ2RlZmF1bHRNYXBTZWxlY3QnKS5vbmNoYW5nZT1lPT5zZXRNYXBTdHlsZShlLnRhcmdldC52YWx1ZSk7ZWwoJ3JlY2x1c3RlckJ1dHRvbicpLm9uY2xpY2s9KCk9PnJlY2x1c3RlcigpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdyZXZlcnNlUm91dGVCdXR0b24nKS5vbmNsaWNrPSgpPT5yZXZlcnNlUm91dGUoKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgnY2xvc2VQcmVzZW50QnV0dG9uJykub25jbGljaz1jbG9zZVByZXNlbnQ7ZWwoJ3ByZXNlbnRCYWNrQnV0dG9uJykub25jbGljaz1wcmVzZW50QmFjaztlbCgnY2VudGVyVHJpcEJ1dHRvbicpLm9uY2xpY2s9Y2VudGVyUHJlc2VudFRyaXA7ZWwoJ3JldHVyblN0YXJ0QnV0dG9uJykub25jbGljaz1yZXR1cm5QcmVzZW50U3RhcnQ7ZWwoJ3ByZXZpb3VzU3RvcEJ1dHRvbicpLm9uY2xpY2s9KCk9PmdvUHJlc2VudFN0b3AocHJlc2VudFN0b3BJbmRleC0xKTtlbCgnbmV4dFN0b3BCdXR0b24nKS5vbmNsaWNrPSgpPT5nb1ByZXNlbnRTdG9wKHByZXNlbnRTdG9wSW5kZXgrMSk7ZWwoJ3ByZXZpb3VzUGhvdG9CdXR0b24nKS5vbmNsaWNrPSgpPT57Y29uc3QgYT1wcmVzZW50QXNzZXRzKCk7aWYoYS5sZW5ndGgpZ29QcmVzZW50UGhvdG8ocHJlc2VudFBob3RvSW5kZXg8MD9hLmxlbmd0aC0xOnByZXNlbnRQaG90b0luZGV4LTEpfTtlbCgnbmV4dFBob3RvQnV0dG9uJykub25jbGljaz0oKT0+e2NvbnN0IGE9cHJlc2VudEFzc2V0cygpO2lmKGEubGVuZ3RoKWdvUHJlc2VudFBob3RvKHByZXNlbnRQaG90b0luZGV4KzEpfTtlbCgncGxheUpvdXJuZXlCdXR0b24nKS5vbmNsaWNrPXRvZ2dsZVBsYXl9CmluaXRGb3JtcygpO2JpbmQoKTtlbnN1cmVNYXAoKTtzZXRNYXBTdHlsZShtYXBTdHlsZUtleSk7bG9hZFByb2plY3RzKCkuY2F0Y2goZT0+dG9hc3QoZS5tZXNzYWdlKSk7Cjwvc2NyaXB0Pgo8c2NyaXB0IGlkPSJUUklQUFlfVjEwM19TQ1JJUFQiPgovKiBUcmlwcHkgdjEwLjMuMCDigJQgRGF5IC8gU2VnbWVudCBqb3VybmV5IG1vZGVsICovCnZhciB2MTAzU2VsZWN0ZWRTdG9wcz1uZXcgU2V0KCk7CnZhciB2MTAzU2VsZWN0TW9kZT1mYWxzZTsKdmFyIHYxMDNBY3RpdmVTZWdtZW50SWQ9bnVsbDsKdmFyIHYxMDNPcGVuRGF5cz1uZXcgU2V0KCk7CnZhciB2MTAzUG9pQnVzeT1mYWxzZTsKdmFyIHYxMDNQb2lBdHRlbXB0ZWQ9bmV3IFNldCgpOwp2YXIgdjEwM1ByZXNlbnRGbGF0SW5kZXg9MDsKdmFyIHYxMDNQcmVzZW50RGF5S2V5PW51bGw7CnZhciB2MTAzUHJlc2VudEl0ZW09bnVsbDsKdmFyIHYxMDNCYXNlU2VsZWN0U3RvcD1zZWxlY3RTdG9wOwp2YXIgdjEwM0Jhc2VGb2N1c0Fzc2V0PWZvY3VzQXNzZXQ7CnZhciB2MTAzUG9pQ2FjaGU9KGZ1bmN0aW9uKCl7dHJ5e3JldHVybiBKU09OLnBhcnNlKGxvY2FsU3RvcmFnZS5nZXRJdGVtKCd0cmlwcHlfcG9pX2NhY2hlX3YxJyl8fCd7fScpfWNhdGNoe3JldHVybnt9fX0pKCk7CgpmdW5jdGlvbiB2MTAzRW5zdXJlTW9kZWwoKXsKICBpZighcHJvamVjdClyZXR1cm47CiAgcHJvamVjdC5zZXR0aW5ncz1wcm9qZWN0LnNldHRpbmdzfHx7fTsKICBwcm9qZWN0LnNldHRpbmdzLmRheV90aXRsZXM9cHJvamVjdC5zZXR0aW5ncy5kYXlfdGl0bGVzfHx7fTsKICBwcm9qZWN0LnNldHRpbmdzLnNlZ21lbnRzPUFycmF5LmlzQXJyYXkocHJvamVjdC5zZXR0aW5ncy5zZWdtZW50cyk/cHJvamVjdC5zZXR0aW5ncy5zZWdtZW50czpbXTsKICBjb25zdCBpZHM9bmV3IFNldCgocHJvamVjdC5zdG9wc3x8W10pLm1hcChzPT5zLnN0b3BfaWQpKTsKICBwcm9qZWN0LnNldHRpbmdzLnNlZ21lbnRzPXByb2plY3Quc2V0dGluZ3Muc2VnbWVudHMubWFwKHNlZz0+KHsuLi5zZWcsbWVtYmVyX3N0b3BfaWRzOihzZWcubWVtYmVyX3N0b3BfaWRzfHxbXSkuZmlsdGVyKGlkPT5pZHMuaGFzKGlkKSl9KSkuZmlsdGVyKHNlZz0+c2VnLm1lbWJlcl9zdG9wX2lkcy5sZW5ndGg+MSk7Cn0KZnVuY3Rpb24gdjEwM1NlZ21lbnRzKCl7djEwM0Vuc3VyZU1vZGVsKCk7cmV0dXJuIHByb2plY3Q/LnNldHRpbmdzPy5zZWdtZW50c3x8W119CmZ1bmN0aW9uIHYxMDNTdG9wQnlJZChpZCl7cmV0dXJuKHByb2plY3Q/LnN0b3BzfHxbXSkuZmluZChzPT5zLnN0b3BfaWQ9PT1pZCl9CmZ1bmN0aW9uIHYxMDNTdG9wSW5kZXgoaWQpe3JldHVybihwcm9qZWN0Py5zdG9wc3x8W10pLmZpbmRJbmRleChzPT5zLnN0b3BfaWQ9PT1pZCl9CmZ1bmN0aW9uIHYxMDNEYXRlS2V5KHZhbHVlKXtjb25zdCBkPWFzc2V0RGF0ZSh2YWx1ZSk7aWYoIWQpcmV0dXJuJ3VuZGF0ZWQnO3JldHVybmAke2QuZ2V0RnVsbFllYXIoKX0tJHtTdHJpbmcoZC5nZXRNb250aCgpKzEpLnBhZFN0YXJ0KDIsJzAnKX0tJHtTdHJpbmcoZC5nZXREYXRlKCkpLnBhZFN0YXJ0KDIsJzAnKX1gfQpmdW5jdGlvbiB2MTAzU3RvcERheUtleShzdG9wKXtpZihzdG9wPy5tYW51YWxfZGF5KXJldHVybiBzdG9wLm1hbnVhbF9kYXk7Y29uc3QgZGF0ZXM9c3RvcEFzc2V0cyhzdG9wKS5tYXAoYT0+YXNzZXREYXRlKGEudGltZSkpLmZpbHRlcihCb29sZWFuKS5zb3J0KChhLGIpPT5hLWIpO3JldHVybiBkYXRlcy5sZW5ndGg/djEwM0RhdGVLZXkoZGF0ZXNbMF0pOid1bmRhdGVkJ30KZnVuY3Rpb24gdjEwM0RheURhdGUoa2V5KXtyZXR1cm4ga2V5PT09J3VuZGF0ZWQnP251bGw6bmV3IERhdGUoa2V5KydUMTI6MDA6MDAnKX0KZnVuY3Rpb24gdjEwM0RheVRpdGxlKGtleSxpbmRleCl7Y29uc3QgY3VzdG9tPXByb2plY3Q/LnNldHRpbmdzPy5kYXlfdGl0bGVzPy5ba2V5XTtpZihjdXN0b20pcmV0dXJuIGN1c3RvbTtjb25zdCBkPXYxMDNEYXlEYXRlKGtleSk7cmV0dXJuIGQ/YERheSAke2luZGV4KzF9IMK3ICR7ZC50b0xvY2FsZURhdGVTdHJpbmcoJ2VuLVVTJyx7d2Vla2RheTonc2hvcnQnLG1vbnRoOidzaG9ydCcsZGF5OidudW1lcmljJyx5ZWFyOidudW1lcmljJ30pfWA6YERheSAke2luZGV4KzF9IMK3IERhdGUgdW5hdmFpbGFibGVgfQpmdW5jdGlvbiB2MTAzU2VnbWVudE1lbWJlcnMoc2VnKXtyZXR1cm4oc2VnPy5tZW1iZXJfc3RvcF9pZHN8fFtdKS5tYXAodjEwM1N0b3BCeUlkKS5maWx0ZXIoQm9vbGVhbil9CmZ1bmN0aW9uIHYxMDNTZWdtZW50QXNzZXRzKHNlZyl7Y29uc3QgaWRzPW5ldyBTZXQodjEwM1NlZ21lbnRNZW1iZXJzKHNlZykuZmxhdE1hcChzPT5zLmFzc2V0X2lkc3x8W10pKTtyZXR1cm4ocHJvamVjdD8uYXNzZXRzfHxbXSkuZmlsdGVyKGE9Pmlkcy5oYXMoYS5hc3NldF9pZCkpfQpmdW5jdGlvbiB2MTAzSXRlbUFzc2V0cyhpdGVtKXtyZXR1cm4gaXRlbT8udHlwZT09PSdzZWdtZW50Jz92MTAzU2VnbWVudEFzc2V0cyhpdGVtLnNlZ21lbnQpOnN0b3BBc3NldHMoaXRlbT8uc3RvcCl9CmZ1bmN0aW9uIHYxMDNJdGVtU3RvcHMoaXRlbSl7cmV0dXJuIGl0ZW0/LnR5cGU9PT0nc2VnbWVudCc/djEwM1NlZ21lbnRNZW1iZXJzKGl0ZW0uc2VnbWVudCk6aXRlbT8uc3RvcD9baXRlbS5zdG9wXTpbXX0KZnVuY3Rpb24gdjEwM1NlZ21lbnROYW1lKHNlZyl7CiAgaWYoc2VnPy5uYW1lPy50cmltKCkpcmV0dXJuIHNlZy5uYW1lLnRyaW0oKTsKICBjb25zdCBtZW1iZXJzPXYxMDNTZWdtZW50TWVtYmVycyhzZWcpLG5hbWVzPW1lbWJlcnMubWFwKChzKT0+c3RvcE5hbWUocyx2MTAzU3RvcEluZGV4KHMuc3RvcF9pZCkpKS5maWx0ZXIoQm9vbGVhbik7CiAgY29uc3QgdHlwZT1zZWc/LnR5cGV8fCdjdXN0b20nOwogIGlmKHR5cGU9PT0nZHJpdmUnKXsKICAgIGNvbnN0IHJvYWQ9bmFtZXMuZmluZChuPT4vXGIoVVMtfEktfEh3eXxIaWdod2F5fFJvYWR8Um91dGV8RHJpdmV8U2NlbmljKVxiL2kudGVzdChuKSk7CiAgICBpZihyb2FkKXJldHVybiAvZHJpdmUvaS50ZXN0KHJvYWQpP3JvYWQ6YCR7cm9hZH0gRHJpdmVgOwogICAgaWYobmFtZXMubGVuZ3RoPjEpcmV0dXJuYCR7bmFtZXNbMF19IHRvICR7bmFtZXNbbmFtZXMubGVuZ3RoLTFdfWA7CiAgICByZXR1cm4nU2NlbmljIERyaXZlJzsKICB9CiAgaWYodHlwZT09PSdoaWtlJyl7CiAgICBjb25zdCB0cmFpbD1uYW1lcy5maW5kKG49Pi90cmFpbHxoaWtlfHBhdGgvaS50ZXN0KG4pKTsKICAgIGlmKHRyYWlsKXJldHVybiAvaGlrZS9pLnRlc3QodHJhaWwpP3RyYWlsOmAke3RyYWlsfSBIaWtlYDsKICAgIHJldHVybiBuYW1lc1swXT9gJHtuYW1lc1swXX0gSGlrZWA6J0hpa2luZyBTZWdtZW50JzsKICB9CiAgcmV0dXJuIG5hbWVzLmxlbmd0aD4xP2Ake25hbWVzWzBdfSB0byAke25hbWVzW25hbWVzLmxlbmd0aC0xXX1gOidDb21iaW5lZCBTZWdtZW50JzsKfQpmdW5jdGlvbiB2MTAzSXRlbU5hbWUoaXRlbSl7cmV0dXJuIGl0ZW0/LnR5cGU9PT0nc2VnbWVudCc/djEwM1NlZ21lbnROYW1lKGl0ZW0uc2VnbWVudCk6c3RvcE5hbWUoaXRlbS5zdG9wLHYxMDNTdG9wSW5kZXgoaXRlbS5zdG9wLnN0b3BfaWQpKX0KZnVuY3Rpb24gdjEwM0l0ZW1JZChpdGVtKXtyZXR1cm4gaXRlbT8udHlwZT09PSdzZWdtZW50Jz9gc2VnbWVudDoke2l0ZW0uc2VnbWVudC5pZH1gOmBzdG9wOiR7aXRlbS5zdG9wLnN0b3BfaWR9YH0KZnVuY3Rpb24gdjEwM0l0ZW1SYW5nZShpdGVtKXtjb25zdCBhc3NldHM9djEwM0l0ZW1Bc3NldHMoaXRlbSkubWFwKGE9PmFzc2V0RGF0ZShhLnRpbWUpKS5maWx0ZXIoQm9vbGVhbikuc29ydCgoYSxiKT0+YS1iKTtpZighYXNzZXRzLmxlbmd0aClyZXR1cm4nRGF0ZS90aW1lIHVuYXZhaWxhYmxlJztjb25zdCBhPWFzc2V0c1swXSxiPWFzc2V0c1thc3NldHMubGVuZ3RoLTFdLGZkPWEudG9Mb2NhbGVEYXRlU3RyaW5nKCdlbi1VUycse21vbnRoOicyLWRpZ2l0JyxkYXk6JzItZGlnaXQnLHllYXI6J251bWVyaWMnfSkucmVwbGFjZUFsbCgnLycsJy0nKSxsZD1iLnRvTG9jYWxlRGF0ZVN0cmluZygnZW4tVVMnLHttb250aDonMi1kaWdpdCcsZGF5OicyLWRpZ2l0Jyx5ZWFyOidudW1lcmljJ30pLnJlcGxhY2VBbGwoJy8nLCctJyksZnQ9YS50b0xvY2FsZVRpbWVTdHJpbmcoJ2VuLVVTJyx7aG91cjonbnVtZXJpYycsbWludXRlOicyLWRpZ2l0J30pLGx0PWIudG9Mb2NhbGVUaW1lU3RyaW5nKCdlbi1VUycse2hvdXI6J251bWVyaWMnLG1pbnV0ZTonMi1kaWdpdCd9KTtyZXR1cm4gZmQ9PT1sZD9gJHtmZH0gJHtmdH0g4oCTICR7bHR9YDpgJHtmZH0gJHtmdH0g4oCTICR7bGR9ICR7bHR9YH0KZnVuY3Rpb24gdjEwM0pvdXJuZXlEYXlzKCl7CiAgaWYoIXByb2plY3QpcmV0dXJuW107djEwM0Vuc3VyZU1vZGVsKCk7CiAgY29uc3Qgc3RvcHM9cHJvamVjdC5zdG9wc3x8W10sc3RvcE9yZGVyPW5ldyBNYXAoc3RvcHMubWFwKChzLGkpPT5bcy5zdG9wX2lkLGldKSk7CiAgY29uc3Qgc2VnbWVudHM9djEwM1NlZ21lbnRzKCksbWVtYmVySWRzPW5ldyBTZXQoc2VnbWVudHMuZmxhdE1hcChzPT5zLm1lbWJlcl9zdG9wX2lkc3x8W10pKTsKICBjb25zdCBncm91cHM9bmV3IE1hcCgpOwogIGNvbnN0IHB1dD0oa2V5LGl0ZW0sb3JkZXIpPT57aWYoIWdyb3Vwcy5oYXMoa2V5KSlncm91cHMuc2V0KGtleSxbXSk7Z3JvdXBzLmdldChrZXkpLnB1c2goey4uLml0ZW0sb3JkZXJ9KX07CiAgc3RvcHMuZmlsdGVyKHM9PiFtZW1iZXJJZHMuaGFzKHMuc3RvcF9pZCkpLmZvckVhY2gocz0+cHV0KHYxMDNTdG9wRGF5S2V5KHMpLHt0eXBlOidzdG9wJyxzdG9wOnN9LHN0b3BPcmRlci5nZXQocy5zdG9wX2lkKXx8MCkpOwogIHNlZ21lbnRzLmZvckVhY2goc2VnPT57Y29uc3QgbWVtYmVycz12MTAzU2VnbWVudE1lbWJlcnMoc2VnKTtpZighbWVtYmVycy5sZW5ndGgpcmV0dXJuO2NvbnN0IGtleT12MTAzU3RvcERheUtleShtZW1iZXJzWzBdKTtwdXQoa2V5LHt0eXBlOidzZWdtZW50JyxzZWdtZW50OnNlZ30sTWF0aC5taW4oLi4ubWVtYmVycy5tYXAocz0+c3RvcE9yZGVyLmdldChzLnN0b3BfaWQpfHwwKSkpfSk7CiAgY29uc3Qga2V5cz1bLi4uZ3JvdXBzLmtleXMoKV0uc29ydCgoYSxiKT0+YT09PSd1bmRhdGVkJz8xOmI9PT0ndW5kYXRlZCc/LTE6YS5sb2NhbGVDb21wYXJlKGIpKTsKICByZXR1cm4ga2V5cy5tYXAoKGtleSxpKT0+e2NvbnN0IGl0ZW1zPWdyb3Vwcy5nZXQoa2V5KS5zb3J0KChhLGIpPT5hLm9yZGVyLWIub3JkZXIpO2NvbnN0IGlkcz1uZXcgU2V0KGl0ZW1zLmZsYXRNYXAoaXRlbT0+djEwM0l0ZW1Bc3NldHMoaXRlbSkubWFwKGE9PmEuYXNzZXRfaWQpKSk7cmV0dXJue2tleSxpbmRleDppLHRpdGxlOnYxMDNEYXlUaXRsZShrZXksaSksaXRlbXMsYXNzZXRDb3VudDppZHMuc2l6ZSxzdG9wQ291bnQ6aXRlbXMucmVkdWNlKChuLGl0ZW0pPT5uK3YxMDNJdGVtU3RvcHMoaXRlbSkubGVuZ3RoLDApfX0pCn0KZnVuY3Rpb24gdjEwM0ZsYXRJdGVtcygpe3JldHVybiB2MTAzSm91cm5leURheXMoKS5mbGF0TWFwKGRheT0+ZGF5Lml0ZW1zLm1hcChpdGVtPT4oey4uLml0ZW0sZGF5fSkpKX0KZnVuY3Rpb24gdjEwM0dlbmVyaWNOYW1lKG5hbWUpe3JldHVybiFuYW1lfHwvXlN0b3BccytcZCskL2kudGVzdChuYW1lKXx8L15QaG90byBDbHVzdGVyJC9pLnRlc3QobmFtZSl9CnZhciB2MTAzT3JpZ2luYWxTdG9wTmFtZT1zdG9wTmFtZTsKc3RvcE5hbWU9ZnVuY3Rpb24oc3RvcCxpbmRleCl7Y29uc3QgcmF3PShzdG9wPy5uYW1lfHxzdG9wPy5wb2lfbmFtZXx8JycpLnRyaW0oKTtyZXR1cm4gcmF3JiYhL15TdG9wXHMrXGQrJC9pLnRlc3QocmF3KT9yYXc6YFN0b3AgJHtpbmRleCsxfWB9OwoKZnVuY3Rpb24gdjEwM0J1aWxkUmFpbCgpewogIGNvbnN0IHJhaWw9ZG9jdW1lbnQucXVlcnlTZWxlY3RvcignLnJpZ2h0UmFpbCcpO2lmKCFyYWlsKXJldHVybjsKICBjb25zdCBleHBvcnRCb3g9ZWwoJ2V4cG9ydEJveCcpOwogIHJhaWwuaW5uZXJIVE1MPWA8ZGl2IGNsYXNzPSJyaWdodFRvcCI+PGRpdiBjbGFzcz0icmlnaHRUaXRsZSI+Sm91cm5leSA8c3BhbiBpZD0ic3RvcENvdW50IiBjbGFzcz0icmlnaHRDb3VudCI+PC9zcGFuPjwvZGl2PjxidXR0b24gaWQ9InN0b3BTZWFyY2hCdXR0b24iIGNsYXNzPSJyaWdodFNlYXJjaCI+4oyVPC9idXR0b24+PC9kaXY+CiAgPGRpdiBpZD0ic3RvcFNlYXJjaFdyYXAiIGNsYXNzPSJzdG9wU2VhcmNoV3JhcCI+PGlucHV0IGlkPSJzdG9wU2VhcmNoIiBwbGFjZWhvbGRlcj0iU2VhcmNoIGRheXMsIHN0b3BzLCBhbmQgc2VnbWVudHPigKYiPjwvZGl2PgogIDxkaXYgY2xhc3M9ImpvdXJuZXlBY3Rpb25zIj48YnV0dG9uIGlkPSJzZWxlY3RTdG9wc0J1dHRvbiI+U2VsZWN0PC9idXR0b24+PGJ1dHRvbiBpZD0iY29tYmluZVN0b3BzQnV0dG9uIiBkaXNhYmxlZD5Db21iaW5lPC9idXR0b24+PGJ1dHRvbiBpZD0ic3VnZ2VzdE5hbWVzQnV0dG9uIj5OYW1lIGZyb20gTWFwPC9idXR0b24+PGJ1dHRvbiBpZD0iam91cm5leU1vcmVCdXR0b24iPuKAouKAouKAojwvYnV0dG9uPjwvZGl2PgogIDxkaXYgaWQ9ImpvdXJuZXlNb3JlTWVudSIgY2xhc3M9ImpvdXJuZXlNb3JlTWVudSI+PGJ1dHRvbiBpZD0idHJpcFNldHRpbmdzQnV0dG9uIj5UcmlwIFNldHRpbmdzPC9idXR0b24+PGJ1dHRvbiBpZD0iYWRkU3RvcEJ1dHRvbiI+QWRkIFN0b3A8L2J1dHRvbj48YnV0dG9uIGlkPSJyZXZlcnNlSm91cm5leUJ1dHRvbiI+UmV2ZXJzZSBSb3V0ZTwvYnV0dG9uPjwvZGl2PgogIDxkaXYgaWQ9InN0b3BMaXN0IiBjbGFzcz0ic3RvcExpc3QgZGF5TGlzdCI+PC9kaXY+YDsKICBpZihleHBvcnRCb3gpe2V4cG9ydEJveC5jbGFzc0xpc3QuYWRkKCdjb2xsYXBzZWQnKTtyYWlsLmFwcGVuZENoaWxkKGV4cG9ydEJveCl9CiAgZWwoJ3NldHRpbmdzQnV0dG9uJyk/LmNsYXNzTGlzdC5hZGQoJ3YxMDNIaWRkZW4nKTsKICBlbCgnc3RvcFNlYXJjaEJ1dHRvbicpLm9uY2xpY2s9KCk9PmVsKCdzdG9wU2VhcmNoV3JhcCcpLmNsYXNzTGlzdC50b2dnbGUoJ3Nob3cnKTsKICBlbCgnc3RvcFNlYXJjaCcpLm9uaW5wdXQ9cmVuZGVyU3RvcHM7CiAgZWwoJ3NlbGVjdFN0b3BzQnV0dG9uJykub25jbGljaz12MTAzVG9nZ2xlU2VsZWN0TW9kZTsKICBlbCgnY29tYmluZVN0b3BzQnV0dG9uJykub25jbGljaz12MTAzT3BlbkNvbWJpbmVNb2RhbDsKICBlbCgnc3VnZ2VzdE5hbWVzQnV0dG9uJykub25jbGljaz0oKT0+djEwM1NjaGVkdWxlUG9pTmFtaW5nKHRydWUpOwogIGVsKCdqb3VybmV5TW9yZUJ1dHRvbicpLm9uY2xpY2s9KCk9PmVsKCdqb3VybmV5TW9yZU1lbnUnKS5jbGFzc0xpc3QudG9nZ2xlKCdzaG93Jyk7CiAgZWwoJ3RyaXBTZXR0aW5nc0J1dHRvbicpLm9uY2xpY2s9KCk9PntlbCgnam91cm5leU1vcmVNZW51JykuY2xhc3NMaXN0LnJlbW92ZSgnc2hvdycpO2VsKCdzdG9wUmFkaXVzJykudmFsdWU9cHJvamVjdD8uc2V0dGluZ3M/LnN0b3BfcmFkaXVzX218fDIwMDtzZXRNb2RhbCgnc2V0dGluZ3NNb2RhbCcpfTsKICBlbCgnYWRkU3RvcEJ1dHRvbicpLm9uY2xpY2s9KCk9PntlbCgnam91cm5leU1vcmVNZW51JykuY2xhc3NMaXN0LnJlbW92ZSgnc2hvdycpO2FkZFN0b3AoKX07CiAgZWwoJ3JldmVyc2VKb3VybmV5QnV0dG9uJykub25jbGljaz0oKT0+e2VsKCdqb3VybmV5TW9yZU1lbnUnKS5jbGFzc0xpc3QucmVtb3ZlKCdzaG93Jyk7cmV2ZXJzZVJvdXRlKCkuY2F0Y2goZT0+dG9hc3QoZS5tZXNzYWdlKSl9Owp9CmZ1bmN0aW9uIHYxMDNJbnNlcnRTZWdtZW50TW9kYWwoKXtpZihlbCgnc2VnbWVudE1vZGFsJykpcmV0dXJuO2RvY3VtZW50LmJvZHkuaW5zZXJ0QWRqYWNlbnRIVE1MKCdiZWZvcmVlbmQnLGA8ZGl2IGlkPSJzZWdtZW50TW9kYWwiIGNsYXNzPSJtb2RhbCI+PGRpdiBjbGFzcz0ibW9kYWxDYXJkIj48ZGl2IGNsYXNzPSJtb2RhbFRpdGxlIj5Db21iaW5lIFN0b3BzPC9kaXY+PGRpdiBjbGFzcz0iZm9ybUdyaWQiPjxsYWJlbCBjbGFzcz0ic21hbGwiPlNlZ21lbnQgdHlwZTwvbGFiZWw+PHNlbGVjdCBpZD0ic2VnbWVudFR5cGUiPjxvcHRpb24gdmFsdWU9ImRyaXZlIj5Ecml2ZTwvb3B0aW9uPjxvcHRpb24gdmFsdWU9Imhpa2UiPkhpa2U8L29wdGlvbj48b3B0aW9uIHZhbHVlPSJjdXN0b20iPkN1c3RvbSBTZWdtZW50PC9vcHRpb24+PC9zZWxlY3Q+PGxhYmVsIGNsYXNzPSJzbWFsbCI+TmFtZTwvbGFiZWw+PGlucHV0IGlkPSJzZWdtZW50TmFtZSIgcGxhY2Vob2xkZXI9IkF1dG9tYXRpYyBuYW1lIj48ZGl2IGlkPSJzZWdtZW50U3VtbWFyeSIgY2xhc3M9InNtYWxsIj48L2Rpdj48ZGl2IGNsYXNzPSJtb2RhbEFjdGlvbnMiPjxidXR0b24gaWQ9ImNyZWF0ZVNlZ21lbnRCdXR0b24iIGNsYXNzPSJwcmltYXJ5Ij5Db21iaW5lIFN0b3BzPC9idXR0b24+PGJ1dHRvbiBkYXRhLWNsb3NlLXYxMDM9InNlZ21lbnRNb2RhbCI+Q2FuY2VsPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+PC9kaXY+YCk7ZWwoJ2NyZWF0ZVNlZ21lbnRCdXR0b24nKS5vbmNsaWNrPXYxMDNDcmVhdGVTZWdtZW50O2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoJ1tkYXRhLWNsb3NlLXYxMDM9InNlZ21lbnRNb2RhbCJdJykub25jbGljaz0oKT0+c2V0TW9kYWwoJ3NlZ21lbnRNb2RhbCcsZmFsc2UpfQpmdW5jdGlvbiB2MTAzVG9nZ2xlU2VsZWN0TW9kZSgpe3YxMDNTZWxlY3RNb2RlPSF2MTAzU2VsZWN0TW9kZTtpZighdjEwM1NlbGVjdE1vZGUpdjEwM1NlbGVjdGVkU3RvcHMuY2xlYXIoKTtlbCgnc2VsZWN0U3RvcHNCdXR0b24nKS5jbGFzc0xpc3QudG9nZ2xlKCdhY3RpdmUnLHYxMDNTZWxlY3RNb2RlKTtlbCgnc2VsZWN0U3RvcHNCdXR0b24nKS50ZXh0Q29udGVudD12MTAzU2VsZWN0TW9kZT8nRG9uZSc6J1NlbGVjdCc7ZWwoJ2NvbWJpbmVTdG9wc0J1dHRvbicpLmRpc2FibGVkPXYxMDNTZWxlY3RlZFN0b3BzLnNpemU8MjtyZW5kZXJTdG9wcygpfQpmdW5jdGlvbiB2MTAzVG9nZ2xlU3RvcFNlbGVjdGlvbihpZCl7aWYodjEwM1NlbGVjdGVkU3RvcHMuaGFzKGlkKSl2MTAzU2VsZWN0ZWRTdG9wcy5kZWxldGUoaWQpO2Vsc2UgdjEwM1NlbGVjdGVkU3RvcHMuYWRkKGlkKTtlbCgnY29tYmluZVN0b3BzQnV0dG9uJykuZGlzYWJsZWQ9djEwM1NlbGVjdGVkU3RvcHMuc2l6ZTwyO3JlbmRlclN0b3BzKCl9CmZ1bmN0aW9uIHYxMDNPcGVuQ29tYmluZU1vZGFsKCl7Y29uc3QgaWRzPVsuLi52MTAzU2VsZWN0ZWRTdG9wc107aWYoaWRzLmxlbmd0aDwyKXJldHVybjtjb25zdCBkYXlzPW5ldyBTZXQoaWRzLm1hcChpZD0+djEwM1N0b3BEYXlLZXkodjEwM1N0b3BCeUlkKGlkKSkpKTtpZihkYXlzLnNpemU+MSlyZXR1cm4gdG9hc3QoJ0NvbWJpbmUgc3RvcHMgd2l0aGluIHRoZSBzYW1lIGRheS4nKTtjb25zdCBuYW1lcz1pZHMubWFwKGlkPT5zdG9wTmFtZSh2MTAzU3RvcEJ5SWQoaWQpLHYxMDNTdG9wSW5kZXgoaWQpKSk7ZWwoJ3NlZ21lbnROYW1lJykudmFsdWU9Jyc7ZWwoJ3NlZ21lbnRTdW1tYXJ5JykudGV4dENvbnRlbnQ9YCR7aWRzLmxlbmd0aH0gc3RvcHM6ICR7bmFtZXMuam9pbignIOKGkiAnKX1gO3NldE1vZGFsKCdzZWdtZW50TW9kYWwnKX0KYXN5bmMgZnVuY3Rpb24gdjEwM0NyZWF0ZVNlZ21lbnQoKXtjb25zdCBpZHM9Wy4uLnYxMDNTZWxlY3RlZFN0b3BzXS5zb3J0KChhLGIpPT52MTAzU3RvcEluZGV4KGEpLXYxMDNTdG9wSW5kZXgoYikpO2lmKGlkcy5sZW5ndGg8MilyZXR1cm47Y29uc3QgdHlwZT1lbCgnc2VnbWVudFR5cGUnKS52YWx1ZSxuYW1lPWVsKCdzZWdtZW50TmFtZScpLnZhbHVlLnRyaW0oKTt2MTAzRW5zdXJlTW9kZWwoKTtwcm9qZWN0LnNldHRpbmdzLnNlZ21lbnRzLnB1c2goe2lkOmBzZWdfJHtEYXRlLm5vdygpLnRvU3RyaW5nKDM2KX1gLHR5cGUsbmFtZSxtZW1iZXJfc3RvcF9pZHM6aWRzLGNyZWF0ZWRfYXQ6bmV3IERhdGUoKS50b0lTT1N0cmluZygpfSk7djEwM1NlbGVjdGVkU3RvcHMuY2xlYXIoKTt2MTAzU2VsZWN0TW9kZT1mYWxzZTtzZXRNb2RhbCgnc2VnbWVudE1vZGFsJyxmYWxzZSk7YXdhaXQgc2F2ZVByb2plY3QoKTt0b2FzdCgnU3RvcHMgY29tYmluZWQuIE9yaWdpbmFsIHN0b3BzIGFyZSBwcmVzZXJ2ZWQgaW5zaWRlIHRoZSBzZWdtZW50LicpfQphc3luYyBmdW5jdGlvbiB2MTAzVW5ncm91cFNlZ21lbnQoaWQpe3Byb2plY3Quc2V0dGluZ3Muc2VnbWVudHM9cHJvamVjdC5zZXR0aW5ncy5zZWdtZW50cy5maWx0ZXIocz0+cy5pZCE9PWlkKTtpZih2MTAzQWN0aXZlU2VnbWVudElkPT09aWQpdjEwM0FjdGl2ZVNlZ21lbnRJZD1udWxsO2F3YWl0IHNhdmVQcm9qZWN0KCk7dG9hc3QoJ1NlZ21lbnQgdW5ncm91cGVkLicpfQphc3luYyBmdW5jdGlvbiB2MTAzUmVuYW1lU2VnbWVudChpZCl7Y29uc3Qgc2VnPXYxMDNTZWdtZW50cygpLmZpbmQocz0+cy5pZD09PWlkKTtpZighc2VnKXJldHVybjtjb25zdCB2YWx1ZT1wcm9tcHQoJ1NlZ21lbnQgbmFtZScsdjEwM1NlZ21lbnROYW1lKHNlZykpO2lmKHZhbHVlPy50cmltKCkpe3NlZy5uYW1lPXZhbHVlLnRyaW0oKTthd2FpdCBzYXZlUHJvamVjdCgpfX0KYXN5bmMgZnVuY3Rpb24gdjEwM1JlbmFtZURheShrZXkpe2NvbnN0IGRheXM9djEwM0pvdXJuZXlEYXlzKCksZGF5PWRheXMuZmluZChkPT5kLmtleT09PWtleSk7Y29uc3QgdmFsdWU9cHJvbXB0KCdEYXkgdGl0bGUnLHByb2plY3Quc2V0dGluZ3MuZGF5X3RpdGxlc1trZXldfHxkYXk/LnRpdGxlfHwnJyk7aWYodmFsdWU9PT1udWxsKXJldHVybjtpZih2YWx1ZS50cmltKCkpcHJvamVjdC5zZXR0aW5ncy5kYXlfdGl0bGVzW2tleV09dmFsdWUudHJpbSgpO2Vsc2UgZGVsZXRlIHByb2plY3Quc2V0dGluZ3MuZGF5X3RpdGxlc1trZXldO2F3YWl0IHNhdmVQcm9qZWN0KCl9CmZ1bmN0aW9uIHYxMDNTZWxlY3RTZWdtZW50KGlkLHtmbHk9dHJ1ZX09e30pe2NvbnN0IHNlZz12MTAzU2VnbWVudHMoKS5maW5kKHM9PnMuaWQ9PT1pZCk7aWYoIXNlZylyZXR1cm47djEwM0FjdGl2ZVNlZ21lbnRJZD1pZDthY3RpdmVTdG9wSWQ9bnVsbDtmaWx0ZXJTdG9wSWQ9bnVsbDthY3RpdmVBc3NldElkPW51bGw7cmVuZGVyU3RvcHMoKTtyZW5kZXJHYWxsZXJ5KCk7cmVuZGVyU2VsZWN0ZWRQaG90b0J1YmJsZXMoKTtpZihmbHkmJm1hcCl7Y29uc3QgYm91bmRzPW5ldyBtYXBsaWJyZWdsLkxuZ0xhdEJvdW5kcygpO3YxMDNTZWdtZW50QXNzZXRzKHNlZykuZmlsdGVyKHZhbGlkUG9pbnQpLmZvckVhY2goYT0+Ym91bmRzLmV4dGVuZChbTnVtYmVyKGEubG9uKSxOdW1iZXIoYS5sYXQpXSkpO2lmKCFib3VuZHMuaXNFbXB0eSgpKW1hcC5maXRCb3VuZHMoYm91bmRzLHtwYWRkaW5nOnt0b3A6MTAwLGJvdHRvbToxMjAsbGVmdDoxMTAscmlnaHQ6MTEwfSxtYXhab29tOjE2LjIsZHVyYXRpb246MTIwMH0pfX0Kc2VsZWN0U3RvcD1mdW5jdGlvbihpZCxvcHRzPXt9KXt2MTAzQWN0aXZlU2VnbWVudElkPW51bGw7cmV0dXJuIHYxMDNCYXNlU2VsZWN0U3RvcChpZCxvcHRzKX07CgpyZW5kZXJIZWFkZXI9ZnVuY3Rpb24oKXtpZighcHJvamVjdCl7ZWwoJ2pvdXJuZXlUaXRsZScpLnRleHRDb250ZW50PSdObyBqb3VybmV5IHNlbGVjdGVkJztlbCgnam91cm5leU1ldGEnKS50ZXh0Q29udGVudD0nTG9hZCBvciBjcmVhdGUgYSBqb3VybmV5JztyZXR1cm59Y29uc3QgZGF5cz12MTAzSm91cm5leURheXMoKTtlbCgnam91cm5leVRpdGxlJykudGV4dENvbnRlbnQ9cHJvamVjdC5uYW1lfHwnVW50aXRsZWQgSm91cm5leSc7ZWwoJ2pvdXJuZXlNZXRhJykuaW5uZXJIVE1MPWA8c3Bhbj7il7cgJHtlc2MocmFuZ2VUZXh0KHByb2plY3QpfHxwcmV0dHlEYXRlKHByb2plY3QuY3JlYXRlZCkpfTwvc3Bhbj48c3BhbiBjbGFzcz0ibGl2ZURvdCI+PC9zcGFuPjxzcGFuPiR7KHByb2plY3QuYXNzZXRzfHxbXSkubGVuZ3RofSBtZWRpYTwvc3Bhbj48c3Bhbj7igKIgJHtkYXlzLmxlbmd0aH0gZGF5czwvc3Bhbj48c3Bhbj7igKIgJHsocHJvamVjdC5zdG9wc3x8W10pLmxlbmd0aH0gc3RvcHM8L3NwYW4+YH07CnJlbmRlclN0b3BzPWZ1bmN0aW9uKCl7CiAgaWYoIXByb2plY3Qpe2VsKCdzdG9wQ291bnQnKS50ZXh0Q29udGVudD0nJztlbCgnc3RvcExpc3QnKS5pbm5lckhUTUw9JzxkaXYgY2xhc3M9InNtYWxsIj5PcGVuIGEgam91cm5leSB0byBiZWdpbi48L2Rpdj4nO3JldHVybn0KICB2MTAzRW5zdXJlTW9kZWwoKTtjb25zdCBkYXlzPXYxMDNKb3VybmV5RGF5cygpLHE9KGVsKCdzdG9wU2VhcmNoJyk/LnZhbHVlfHwnJykudHJpbSgpLnRvTG93ZXJDYXNlKCk7aWYoIXYxMDNPcGVuRGF5cy5zaXplJiZkYXlzWzBdKXYxMDNPcGVuRGF5cy5hZGQoZGF5c1swXS5rZXkpOwogIGVsKCdzdG9wQ291bnQnKS50ZXh0Q29udGVudD1gKCR7ZGF5cy5sZW5ndGh9IGRheXMpYDsKICBlbCgnc3RvcExpc3QnKS5pbm5lckhUTUw9ZGF5cy5tYXAoZGF5PT57CiAgICBjb25zdCBmaWx0ZXJlZD1kYXkuaXRlbXMuZmlsdGVyKGl0ZW09PiFxfHxgJHtkYXkudGl0bGV9ICR7djEwM0l0ZW1OYW1lKGl0ZW0pfSAke2l0ZW0udHlwZX1gLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocSkpO2lmKHEmJiFmaWx0ZXJlZC5sZW5ndGgpcmV0dXJuJyc7Y29uc3Qgb3Blbj1xfHx2MTAzT3BlbkRheXMuaGFzKGRheS5rZXkpOwogICAgcmV0dXJuYDxzZWN0aW9uIGNsYXNzPSJkYXlDYXJkICR7b3Blbj8nb3Blbic6Jyd9IiBkYXRhLWRheT0iJHtlc2MoZGF5LmtleSl9Ij48ZGl2IGNsYXNzPSJkYXlIZWFkZXIiPjxkaXYgY2xhc3M9ImRheUluZGV4Ij4ke2RheS5pbmRleCsxfTwvZGl2PjxkaXYgY2xhc3M9ImRheVRpdGxlV3JhcCI+PGRpdiBjbGFzcz0iZGF5VGl0bGUiPiR7ZXNjKGRheS50aXRsZSl9PC9kaXY+PGRpdiBjbGFzcz0iZGF5TWV0YSI+JHtkYXkuYXNzZXRDb3VudH0gcGhvdG9zIOKAoiAke2RheS5zdG9wQ291bnR9IHN0b3BzIOKAoiAke2RheS5pdGVtcy5sZW5ndGh9IGl0ZW1zPC9kaXY+PC9kaXY+PGJ1dHRvbiBjbGFzcz0iZGF5UmVuYW1lIiBkYXRhLWRheS1yZW5hbWU9IiR7ZXNjKGRheS5rZXkpfSI+4pyOPC9idXR0b24+PGRpdiBjbGFzcz0iZGF5Q2hldnJvbiI+4oyEPC9kaXY+PC9kaXY+PGRpdiBjbGFzcz0iZGF5Qm9keSI+JHtmaWx0ZXJlZC5tYXAoaXRlbT0+ewogICAgICBjb25zdCBhc3NldHM9djEwM0l0ZW1Bc3NldHMoaXRlbSksbmFtZT12MTAzSXRlbU5hbWUoaXRlbSkscmFuZ2U9djEwM0l0ZW1SYW5nZShpdGVtKSxpc1NlZz1pdGVtLnR5cGU9PT0nc2VnbWVudCcsYWN0aXZlPWlzU2VnP3YxMDNBY3RpdmVTZWdtZW50SWQ9PT1pdGVtLnNlZ21lbnQuaWQ6YWN0aXZlU3RvcElkPT09aXRlbS5zdG9wLnN0b3BfaWQsaWQ9aXNTZWc/aXRlbS5zZWdtZW50LmlkOml0ZW0uc3RvcC5zdG9wX2lkOwogICAgICBjb25zdCBtZW1iZXJUZXh0PWlzU2VnP3YxMDNTZWdtZW50TWVtYmVycyhpdGVtLnNlZ21lbnQpLm1hcChzPT5zdG9wTmFtZShzLHYxMDNTdG9wSW5kZXgocy5zdG9wX2lkKSkpLmpvaW4oJyDihpIgJyk6Jyc7CiAgICAgIHJldHVybmA8YXJ0aWNsZSBjbGFzcz0iam91cm5leUl0ZW0gJHtpc1NlZz8nc2VnbWVudCc6Jyd9ICR7YWN0aXZlPydhY3RpdmUgb3Blbic6Jyd9IiBkYXRhLWtpbmQ9IiR7aXRlbS50eXBlfSIgZGF0YS1pdGVtPSIke2VzYyhpZCl9Ij48ZGl2IGNsYXNzPSJqb3VybmV5SXRlbU1haW4iPiR7djEwM1NlbGVjdE1vZGUmJiFpc1NlZz9gPGJ1dHRvbiBjbGFzcz0ic3RvcENoZWNrICR7djEwM1NlbGVjdGVkU3RvcHMuaGFzKGlkKT8nY2hlY2tlZCc6Jyd9IiBkYXRhLXNlbGVjdC1zdG9wPSIke2VzYyhpZCl9Ij4ke3YxMDNTZWxlY3RlZFN0b3BzLmhhcyhpZCk/J+Kckyc6Jyd9PC9idXR0b24+YDonJ308ZGl2IGNsYXNzPSJpdGVtQmFkZ2UgJHtpc1NlZz9pdGVtLnNlZ21lbnQudHlwZTonc3RvcCd9Ij4ke2lzU2VnPyhpdGVtLnNlZ21lbnQudHlwZT09PSdkcml2ZSc/J+KGnSc6aXRlbS5zZWdtZW50LnR5cGU9PT0naGlrZSc/J+KMgSc6J+KXhycpOih2MTAzU3RvcEluZGV4KGlkKSsxKX08L2Rpdj48ZGl2IGNsYXNzPSJpdGVtVGV4dCI+PGRpdiBjbGFzcz0iaXRlbU5hbWUiPiR7ZXNjKG5hbWUpfTwvZGl2PjxkaXYgY2xhc3M9Iml0ZW1NZXRhIj4ke2Fzc2V0cy5sZW5ndGh9IHBob3RvcyDigKIgJHtlc2MocmFuZ2UpfTwvZGl2PiR7aXNTZWc/YDxkaXYgY2xhc3M9InNlZ21lbnRNZW1iZXJzIj4ke2VzYyhtZW1iZXJUZXh0KX08L2Rpdj5gOicnfTwvZGl2PjxkaXYgY2xhc3M9Iml0ZW1DaGV2cm9uIj7igLo8L2Rpdj48L2Rpdj48ZGl2IGNsYXNzPSJpdGVtQ29udHJvbHMiPiR7aXNTZWc/YDxidXR0b24gZGF0YS12aWV3LXNlZ21lbnQ9IiR7ZXNjKGlkKX0iPlZpZXc8L2J1dHRvbj48YnV0dG9uIGRhdGEtcHJlc2VudC1zZWdtZW50PSIke2VzYyhpZCl9Ij5QcmVzZW50PC9idXR0b24+PGJ1dHRvbiBkYXRhLXJlbmFtZS1zZWdtZW50PSIke2VzYyhpZCl9Ij5SZW5hbWU8L2J1dHRvbj48YnV0dG9uIGRhdGEtdW5ncm91cC1zZWdtZW50PSIke2VzYyhpZCl9Ij5Vbmdyb3VwPC9idXR0b24+YDpgPGJ1dHRvbiBkYXRhLXZpZXctc3RvcD0iJHtlc2MoaWQpfSI+VmlldzwvYnV0dG9uPjxidXR0b24gZGF0YS1wcmVzZW50LXN0b3A9IiR7ZXNjKGlkKX0iPlByZXNlbnQ8L2J1dHRvbj48YnV0dG9uIGRhdGEtcmVuYW1lLXN0b3A9IiR7ZXNjKGlkKX0iPlJlbmFtZTwvYnV0dG9uPjxidXR0b24gZGF0YS1kZWxldGUtc3RvcD0iJHtlc2MoaWQpfSI+RGVsZXRlPC9idXR0b24+YH08L2Rpdj48L2FydGljbGU+YH0pLmpvaW4oJycpfTwvZGl2Pjwvc2VjdGlvbj5gfSkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gbWF0Y2hpbmcgam91cm5leSBpdGVtcy48L2Rpdj4nOwogIGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJy5kYXlIZWFkZXInKS5mb3JFYWNoKGg9Pmgub25jbGljaz1lPT57aWYoZS50YXJnZXQuY2xvc2VzdCgnYnV0dG9uJykpcmV0dXJuO2NvbnN0IGtleT1oLmNsb3Nlc3QoJy5kYXlDYXJkJykuZGF0YXNldC5kYXk7aWYodjEwM09wZW5EYXlzLmhhcyhrZXkpKXYxMDNPcGVuRGF5cy5kZWxldGUoa2V5KTtlbHNlIHYxMDNPcGVuRGF5cy5hZGQoa2V5KTtyZW5kZXJTdG9wcygpfSk7CiAgZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtZGF5LXJlbmFtZV0nKS5mb3JFYWNoKGI9PmIub25jbGljaz1lPT57ZS5zdG9wUHJvcGFnYXRpb24oKTt2MTAzUmVuYW1lRGF5KGIuZGF0YXNldC5kYXlSZW5hbWUpfSk7CiAgZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnLmpvdXJuZXlJdGVtTWFpbicpLmZvckVhY2gocm93PT5yb3cub25jbGljaz1lPT57aWYoZS50YXJnZXQuY2xvc2VzdCgnYnV0dG9uJykpcmV0dXJuO2NvbnN0IGNhcmQ9cm93LmNsb3Nlc3QoJy5qb3VybmV5SXRlbScpO2lmKGNhcmQuZGF0YXNldC5raW5kPT09J3NlZ21lbnQnKXYxMDNTZWxlY3RTZWdtZW50KGNhcmQuZGF0YXNldC5pdGVtKTtlbHNlIHNlbGVjdFN0b3AoY2FyZC5kYXRhc2V0Lml0ZW0se2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KX0pOwogIGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXNlbGVjdC1zdG9wXScpLmZvckVhY2goYj0+Yi5vbmNsaWNrPWU9PntlLnN0b3BQcm9wYWdhdGlvbigpO3YxMDNUb2dnbGVTdG9wU2VsZWN0aW9uKGIuZGF0YXNldC5zZWxlY3RTdG9wKX0pOwogIGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXZpZXctc3RvcF0nKS5mb3JFYWNoKGI9PmIub25jbGljaz0oKT0+c2VsZWN0U3RvcChiLmRhdGFzZXQudmlld1N0b3Ase2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KSk7CiAgZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtcHJlc2VudC1zdG9wXScpLmZvckVhY2goYj0+Yi5vbmNsaWNrPSgpPT5vcGVuUHJlc2VudCh2MTAzU3RvcEluZGV4KGIuZGF0YXNldC5wcmVzZW50U3RvcCkpKTsKICBkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1yZW5hbWUtc3RvcF0nKS5mb3JFYWNoKGI9PmIub25jbGljaz0oKT0+cmVuYW1lU3RvcChiLmRhdGFzZXQucmVuYW1lU3RvcCkpOwogIGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLWRlbGV0ZS1zdG9wXScpLmZvckVhY2goYj0+Yi5vbmNsaWNrPSgpPT5kZWxldGVTdG9wKGIuZGF0YXNldC5kZWxldGVTdG9wKSk7CiAgZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtdmlldy1zZWdtZW50XScpLmZvckVhY2goYj0+Yi5vbmNsaWNrPSgpPT52MTAzU2VsZWN0U2VnbWVudChiLmRhdGFzZXQudmlld1NlZ21lbnQpKTsKICBkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1wcmVzZW50LXNlZ21lbnRdJykuZm9yRWFjaChiPT5iLm9uY2xpY2s9KCk9PnYxMDNPcGVuUHJlc2VudFNlZ21lbnQoYi5kYXRhc2V0LnByZXNlbnRTZWdtZW50KSk7CiAgZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtcmVuYW1lLXNlZ21lbnRdJykuZm9yRWFjaChiPT5iLm9uY2xpY2s9KCk9PnYxMDNSZW5hbWVTZWdtZW50KGIuZGF0YXNldC5yZW5hbWVTZWdtZW50KSk7CiAgZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtdW5ncm91cC1zZWdtZW50XScpLmZvckVhY2goYj0+Yi5vbmNsaWNrPSgpPT52MTAzVW5ncm91cFNlZ21lbnQoYi5kYXRhc2V0LnVuZ3JvdXBTZWdtZW50KSk7Cn07CgpnYWxsZXJ5QXNzZXRzPWZ1bmN0aW9uKCl7aWYoIXByb2plY3QpcmV0dXJuW107aWYodjEwM0FjdGl2ZVNlZ21lbnRJZCl7Y29uc3Qgc2VnPXYxMDNTZWdtZW50cygpLmZpbmQocz0+cy5pZD09PXYxMDNBY3RpdmVTZWdtZW50SWQpO3JldHVybiB2MTAzU2VnbWVudEFzc2V0cyhzZWcpfWlmKGZpbHRlclN0b3BJZCl7cmV0dXJuIHN0b3BBc3NldHModjEwM1N0b3BCeUlkKGZpbHRlclN0b3BJZCkpfXJldHVybiBwcm9qZWN0LmFzc2V0c3x8W119OwpyZW5kZXJHYWxsZXJ5PWZ1bmN0aW9uKCl7Y29uc3QgYXNzZXRzPWdhbGxlcnlBc3NldHMoKSxzZWc9djEwM1NlZ21lbnRzKCkuZmluZChzPT5zLmlkPT09djEwM0FjdGl2ZVNlZ21lbnRJZCksc3RvcD12MTAzU3RvcEJ5SWQoZmlsdGVyU3RvcElkKTtjb25zdCB0aXRsZT1zZWc/djEwM1NlZ21lbnROYW1lKHNlZyk6c3RvcD9zdG9wTmFtZShzdG9wLHYxMDNTdG9wSW5kZXgoc3RvcC5zdG9wX2lkKSk6J01lZGlhJztlbCgnbWVkaWFUaXRsZScpLnRleHRDb250ZW50PXNlZz9gJHtzZWcudHlwZT09PSdkcml2ZSc/J0RyaXZlJzpzZWcudHlwZT09PSdoaWtlJz8nSGlrZSc6J1NlZ21lbnQnfSDigKIgJHt0aXRsZX1gOnN0b3A/YFN0b3AgJHt2MTAzU3RvcEluZGV4KHN0b3Auc3RvcF9pZCkrMX0g4oCiICR7dGl0bGV9YDonTWVkaWEnO2VsKCdtZWRpYUNvdW50JykudGV4dENvbnRlbnQ9YCR7YXNzZXRzLmxlbmd0aH0gaXRlbXNgO2VsKCdmaWx0ZXJDaGlwJykuY2xhc3NMaXN0LnRvZ2dsZSgnc2hvdycsISEoc2VnfHxzdG9wKSk7ZWwoJ2ZpbHRlckNoaXBUZXh0JykudGV4dENvbnRlbnQ9c2VnP2BGaWx0ZXI6ICR7dGl0bGV9YDpzdG9wP2BGaWx0ZXI6ICR7dGl0bGV9YDonRmlsdGVyOiBBbGwnO2VsKCdnYWxsZXJ5JykuaW5uZXJIVE1MPWFzc2V0cy5tYXAoKGEsaSk9PmA8ZGl2IGNsYXNzPSJtZWRpYVRpbGUgJHthLmFzc2V0X2lkPT09YWN0aXZlQXNzZXRJZD8nYWN0aXZlJzonJ30iIGRhdGEtYXNzZXQ9IiR7ZXNjKGEuYXNzZXRfaWQpfSI+JHthLnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoYS50aHVtYil9Ij5gOicnfTxidXR0b24gY2xhc3M9Im1lZGlhVGlsZVJlbW92ZSIgZGF0YS1yZW1vdmUtYXNzZXQ9IiR7ZXNjKGEuYXNzZXRfaWQpfSIgdGl0bGU9IlJlbW92ZSBmcm9tIGpvdXJuZXkiPsOXPC9idXR0b24+PGRpdiBjbGFzcz0ibWVkaWFUaWxlTmFtZSI+JHtlc2MoZm9ybWF0QXNzZXREYXRlVGltZShhLnRpbWUpfHxgUGhvdG8gJHtpKzF9YCl9PC9kaXY+PC9kaXY+YCkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gR1BTIG1lZGlhIGluIHRoaXMgdmlldy48L2Rpdj4nO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJy5tZWRpYVRpbGUnKS5mb3JFYWNoKHRpbGU9PnRpbGUub25jbGljaz0oKT0+Zm9jdXNBc3NldCh0aWxlLmRhdGFzZXQuYXNzZXQpKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1yZW1vdmUtYXNzZXRdJykuZm9yRWFjaChiPT5iLm9uY2xpY2s9ZT0+e2Uuc3RvcFByb3BhZ2F0aW9uKCk7cmVtb3ZlQXNzZXRGcm9tSm91cm5leShiLmRhdGFzZXQucmVtb3ZlQXNzZXQpfSl9OwpyZW5kZXJTZWxlY3RlZFBob3RvQnViYmxlcz1mdW5jdGlvbigpe2NsZWFyQnViYmxlTWFya2VycyhwaG90b01hcmtlcnMpO2lmKCFtYXB8fG1hcC5nZXRab29tKCk8MTMuNSlyZXR1cm47bGV0IGFzc2V0cz1bXTtpZih2MTAzQWN0aXZlU2VnbWVudElkKWFzc2V0cz12MTAzU2VnbWVudEFzc2V0cyh2MTAzU2VnbWVudHMoKS5maW5kKHM9PnMuaWQ9PT12MTAzQWN0aXZlU2VnbWVudElkKSk7ZWxzZSBpZihhY3RpdmVTdG9wSWQpYXNzZXRzPXN0b3BBc3NldHModjEwM1N0b3BCeUlkKGFjdGl2ZVN0b3BJZCkpO2Fzc2V0cy5maWx0ZXIodmFsaWRQb2ludCkuc2xpY2UoMCwxNjApLmZvckVhY2goYXNzZXQ9Pntjb25zdCBub2RlPWFzc2V0QnViYmxlRWxlbWVudChhc3NldCxhc3NldC5hc3NldF9pZD09PWFjdGl2ZUFzc2V0SWQpO25vZGUub25jbGljaz0oKT0+Zm9jdXNBc3NldChhc3NldC5hc3NldF9pZCk7cGhvdG9NYXJrZXJzLnB1c2gobmV3IG1hcGxpYnJlZ2wuTWFya2VyKHtlbGVtZW50Om5vZGUsYW5jaG9yOidjZW50ZXInfSkuc2V0TG5nTGF0KFtOdW1iZXIoYXNzZXQubG9uKSxOdW1iZXIoYXNzZXQubGF0KV0pLmFkZFRvKG1hcCkpfSl9Owpmb2N1c0Fzc2V0PWZ1bmN0aW9uKGlkKXtjb25zdCBhc3NldD0ocHJvamVjdD8uYXNzZXRzfHxbXSkuZmluZChhPT5hLmFzc2V0X2lkPT09aWQpO2lmKCFhc3NldHx8IXZhbGlkUG9pbnQoYXNzZXQpKXJldHVybjthY3RpdmVBc3NldElkPWlkO3JlbmRlckdhbGxlcnkoKTtyZW5kZXJTZWxlY3RlZFBob3RvQnViYmxlcygpO21hcD8uZmx5VG8oe2NlbnRlcjpbTnVtYmVyKGFzc2V0LmxvbiksTnVtYmVyKGFzc2V0LmxhdCldLHpvb206MTguMixwaXRjaDo1MCxiZWFyaW5nOjEwLGR1cmF0aW9uOjk1MCxlc3NlbnRpYWw6dHJ1ZX0pO2lmKGFjdGl2ZVBvcHVwKXt0cnl7YWN0aXZlUG9wdXAucmVtb3ZlKCl9Y2F0Y2h7fX1hY3RpdmVQb3B1cD1uZXcgbWFwbGlicmVnbC5Qb3B1cCh7b2Zmc2V0OjI0LGNsb3NlQnV0dG9uOnRydWUsbWF4V2lkdGg6JzQyMHB4J30pLnNldExuZ0xhdChbTnVtYmVyKGFzc2V0LmxvbiksTnVtYmVyKGFzc2V0LmxhdCldKS5zZXRIVE1MKGA8ZGl2IGNsYXNzPSJzdG9wUG9wdXAiPjxkaXYgY2xhc3M9InN0b3BQb3B1cEltYWdlIj4ke2Fzc2V0LnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoYXNzZXQudGh1bWIpfSI+YDonJ308L2Rpdj48ZGl2IGNsYXNzPSJzdG9wUG9wdXBCb2R5Ij48c3BhbiBjbGFzcz0icG9wdXBLaWNrZXIiPlNlbGVjdGVkIHBob3RvPC9zcGFuPjxkaXYgY2xhc3M9InBvcHVwVGl0bGUiPiR7ZXNjKGZvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSkpfTwvZGl2PjxkaXYgY2xhc3M9InBvcHVwTWV0YSI+JHtlc2MoYXNzZXRDb29yZGluYXRlVGV4dChhc3NldCkpfTwvZGl2PjwvZGl2PjwvZGl2PmApLmFkZFRvKG1hcCl9OwoKYXN5bmMgZnVuY3Rpb24gdjEwM1NhdmVQcm9qZWN0UXVpZXQoKXtpZighcHJvamVjdClyZXR1cm47cHJvamVjdD1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdC8nK2VuY29kZVVSSUNvbXBvbmVudChwcm9qZWN0LmlkKSx7bWV0aG9kOidQVVQnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sYm9keTpKU09OLnN0cmluZ2lmeShwcm9qZWN0KX0pO2F3YWl0IHJlZnJlc2hQcm9qZWN0U3VtbWFyeSgpfQpzYXZlUHJvamVjdD1hc3luYyBmdW5jdGlvbigpe2lmKCFwcm9qZWN0KXJldHVybjt2MTAzRW5zdXJlTW9kZWwoKTthd2FpdCB2MTAzU2F2ZVByb2plY3RRdWlldCgpO3JlbmRlckFsbCgpfTsKcmVuYW1lU3RvcD1hc3luYyBmdW5jdGlvbihpZCl7Y29uc3QgaT12MTAzU3RvcEluZGV4KGlkKTtpZihpPDApcmV0dXJuO2NvbnN0IHZhbHVlPXByb21wdCgnU3RvcCBuYW1lJyxzdG9wTmFtZShwcm9qZWN0LnN0b3BzW2ldLGkpKTtpZih2YWx1ZT8udHJpbSgpKXtwcm9qZWN0LnN0b3BzW2ldLm5hbWU9dmFsdWUudHJpbSgpO3Byb2plY3Quc3RvcHNbaV0ubmFtZV9zb3VyY2U9J21hbnVhbCc7YXdhaXQgc2F2ZVByb2plY3QoKX19Owp2YXIgdjEwM0Jhc2VEZWxldGVTdG9wPWRlbGV0ZVN0b3A7CmRlbGV0ZVN0b3A9YXN5bmMgZnVuY3Rpb24oaWQpe2F3YWl0IHYxMDNCYXNlRGVsZXRlU3RvcChpZCk7aWYoIXByb2plY3QpcmV0dXJuO3YxMDNFbnN1cmVNb2RlbCgpO3Byb2plY3Quc2V0dGluZ3Muc2VnbWVudHM9cHJvamVjdC5zZXR0aW5ncy5zZWdtZW50cy5tYXAocz0+KHsuLi5zLG1lbWJlcl9zdG9wX2lkczpzLm1lbWJlcl9zdG9wX2lkcy5maWx0ZXIoeD0+eCE9PWlkKX0pKS5maWx0ZXIocz0+cy5tZW1iZXJfc3RvcF9pZHMubGVuZ3RoPjEpO2F3YWl0IHYxMDNTYXZlUHJvamVjdFF1aWV0KCk7cmVuZGVyQWxsKCl9Owp2YXIgdjEwM0Jhc2VSZW1vdmVBc3NldD1yZW1vdmVBc3NldEZyb21Kb3VybmV5OwpyZW1vdmVBc3NldEZyb21Kb3VybmV5PWFzeW5jIGZ1bmN0aW9uKGFzc2V0SWQpe2F3YWl0IHYxMDNCYXNlUmVtb3ZlQXNzZXQoYXNzZXRJZCk7aWYoIXByb2plY3QpcmV0dXJuO3YxMDNFbnN1cmVNb2RlbCgpO3Byb2plY3Quc2V0dGluZ3Muc2VnbWVudHM9cHJvamVjdC5zZXR0aW5ncy5zZWdtZW50cy5tYXAocz0+KHsuLi5zLG1lbWJlcl9zdG9wX2lkczpzLm1lbWJlcl9zdG9wX2lkcy5maWx0ZXIoaWQ9PnYxMDNTdG9wQnlJZChpZCkpfSkpLmZpbHRlcihzPT5zLm1lbWJlcl9zdG9wX2lkcy5sZW5ndGg+MSk7YXdhaXQgdjEwM1NhdmVQcm9qZWN0UXVpZXQoKTtyZW5kZXJBbGwoKX07Cm9wZW5Qcm9qZWN0PWFzeW5jIGZ1bmN0aW9uKGlkKXtwcm9qZWN0PWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KGlkKSk7djEwM0Vuc3VyZU1vZGVsKCk7djEwM0FjdGl2ZVNlZ21lbnRJZD1udWxsO3YxMDNTZWxlY3RlZFN0b3BzLmNsZWFyKCk7djEwM1NlbGVjdE1vZGU9ZmFsc2U7YWN0aXZlU3RvcElkPXByb2plY3Quc3RvcHM/LlswXT8uc3RvcF9pZHx8bnVsbDtmaWx0ZXJTdG9wSWQ9YWN0aXZlU3RvcElkO2FjdGl2ZUFzc2V0SWQ9bnVsbDtjb25zdCBkYXlzPXYxMDNKb3VybmV5RGF5cygpO3YxMDNPcGVuRGF5cz1uZXcgU2V0KGRheXNbMF0/W2RheXNbMF0ua2V5XTpbXSk7cmVuZGVyQWxsKCk7dG9hc3QoYExvYWRlZCAke3Byb2plY3QubmFtZXx8J2pvdXJuZXknfWApO3NldFRpbWVvdXQoKCk9PnYxMDNTY2hlZHVsZVBvaU5hbWluZyhmYWxzZSksMTIwMCl9OwoKZnVuY3Rpb24gdjEwM0NhY2hlU2F2ZSgpe3RyeXtsb2NhbFN0b3JhZ2Uuc2V0SXRlbSgndHJpcHB5X3BvaV9jYWNoZV92MScsSlNPTi5zdHJpbmdpZnkodjEwM1BvaUNhY2hlKSl9Y2F0Y2h7fX0KZnVuY3Rpb24gdjEwM1NsZWVwKG1zKXtyZXR1cm4gbmV3IFByb21pc2Uocj0+c2V0VGltZW91dChyLG1zKSl9CmZ1bmN0aW9uIHYxMDNQb2lMYWJlbChkYXRhKXtpZighZGF0YSlyZXR1cm4gbnVsbDtjb25zdCBhPWRhdGEuYWRkcmVzc3x8e30scmF3PShkYXRhLm5hbWV8fCcnKS50cmltKCksdHlwZT1TdHJpbmcoZGF0YS50eXBlfHxkYXRhLmNhdGVnb3J5fHwnJykudG9Mb3dlckNhc2UoKTtpZihyYXcmJiEvXlxkKyQvLnRlc3QocmF3KSYmIS9edW5uYW1lZC9pLnRlc3QocmF3KSl7aWYoL3RyYWlsfHBhdGh8Zm9vdHdheXxjeWNsZXdheS8udGVzdCh0eXBlKSYmIS90cmFpbHxwYXRoL2kudGVzdChyYXcpKXJldHVybntsYWJlbDpgJHtyYXd9IFRyYWlsYCx0eXBlOid0cmFpbCd9O3JldHVybntsYWJlbDpyYXcsdHlwZTp0eXBlfHwncG9pJ319Y29uc3QgdHJhaWw9YS5wYXRofHxhLmZvb3R3YXl8fGEuY3ljbGV3YXl8fGEucGVkZXN0cmlhbjtpZih0cmFpbClyZXR1cm57bGFiZWw6L3RyYWlsfHBhdGgvaS50ZXN0KHRyYWlsKT90cmFpbDpgJHt0cmFpbH0gVHJhaWxgLHR5cGU6J3RyYWlsJ307Y29uc3Qgcm9hZD1hLnJvYWR8fGEuaGlnaHdheTtpZihyb2FkKXtjb25zdCByZWY9ZGF0YS5leHRyYXRhZ3M/LnJlZnx8YS5yb2FkX3JlZjtyZXR1cm57bGFiZWw6cmVmJiYhcm9hZC5pbmNsdWRlcyhyZWYpP2Ake3JlZn0gwrcgJHtyb2FkfWA6cm9hZCx0eXBlOidyb2FkJ319Y29uc3QgcGFyaz1hLnBhcmt8fGEubmF0dXJlX3Jlc2VydmV8fGEubmF0aW9uYWxfcGFyaztpZihwYXJrKXJldHVybntsYWJlbDpwYXJrLHR5cGU6J3BhcmsnfTtjb25zdCB3YXRlcj1hLmxha2V8fGEucml2ZXJ8fGEud2F0ZXI7aWYod2F0ZXIpcmV0dXJue2xhYmVsOndhdGVyLHR5cGU6J3dhdGVyJ307Y29uc3QgdG93bj1hLnRvd258fGEuY2l0eXx8YS52aWxsYWdlfHxhLmhhbWxldDtpZih0b3duKXJldHVybntsYWJlbDpgJHt0b3dufSBTdG9wYCx0eXBlOid0b3duJ307Y29uc3QgZmlyc3Q9KGRhdGEuZGlzcGxheV9uYW1lfHwnJykuc3BsaXQoJywnKVswXS50cmltKCk7cmV0dXJuIGZpcnN0P3tsYWJlbDpmaXJzdCx0eXBlOidwbGFjZSd9Om51bGx9CmFzeW5jIGZ1bmN0aW9uIHYxMDNSZXZlcnNlKGxhdCxsb24pe2NvbnN0IGtleT1gJHtOdW1iZXIobGF0KS50b0ZpeGVkKDQpfSwke051bWJlcihsb24pLnRvRml4ZWQoNCl9YDtpZih2MTAzUG9pQ2FjaGVba2V5XSlyZXR1cm4gdjEwM1BvaUNhY2hlW2tleV07YXdhaXQgdjEwM1NsZWVwKDExMDApO3RyeXtjb25zdCByPWF3YWl0IGZldGNoKGBodHRwczovL25vbWluYXRpbS5vcGVuc3RyZWV0bWFwLm9yZy9yZXZlcnNlP2Zvcm1hdD1qc29udjImbGF0PSR7ZW5jb2RlVVJJQ29tcG9uZW50KGxhdCl9Jmxvbj0ke2VuY29kZVVSSUNvbXBvbmVudChsb24pfSZ6b29tPTE3JmFkZHJlc3NkZXRhaWxzPTEmbmFtZWRldGFpbHM9MWApO2lmKCFyLm9rKXJldHVybiBudWxsO2NvbnN0IHJlc3VsdD12MTAzUG9pTGFiZWwoYXdhaXQgci5qc29uKCkpO2lmKHJlc3VsdCl7djEwM1BvaUNhY2hlW2tleV09cmVzdWx0O3YxMDNDYWNoZVNhdmUoKX1yZXR1cm4gcmVzdWx0fWNhdGNoe3JldHVybiBudWxsfX0KYXN5bmMgZnVuY3Rpb24gdjEwM05hbWVPbmVTdG9wKHN0b3Ape2NvbnN0IGFzc2V0cz1zdG9wQXNzZXRzKHN0b3ApLmZpbHRlcih2YWxpZFBvaW50KTtjb25zdCByZXBzPVtdO1thc3NldHNbMF0sYXNzZXRzW01hdGguZmxvb3IoYXNzZXRzLmxlbmd0aC8yKV0sYXNzZXRzW2Fzc2V0cy5sZW5ndGgtMV1dLmZpbHRlcihCb29sZWFuKS5mb3JFYWNoKGE9PntpZighcmVwcy5zb21lKHg9Pk1hdGguYWJzKHgubGF0LWEubGF0KTwxZS02JiZNYXRoLmFicyh4Lmxvbi1hLmxvbik8MWUtNikpcmVwcy5wdXNoKGEpfSk7aWYoIXJlcHMubGVuZ3RoJiZ2YWxpZFBvaW50KHN0b3ApKXJlcHMucHVzaChzdG9wKTtjb25zdCByZXN1bHRzPVtdO2Zvcihjb25zdCBwIG9mIHJlcHMuc2xpY2UoMCwzKSl7Y29uc3QgcmVzdWx0PWF3YWl0IHYxMDNSZXZlcnNlKHAubGF0LHAubG9uKTtpZihyZXN1bHQpcmVzdWx0cy5wdXNoKHJlc3VsdCl9aWYoIXJlc3VsdHMubGVuZ3RoKXJldHVybiBmYWxzZTtjb25zdCBjb3VudHM9bmV3IE1hcCgpO3Jlc3VsdHMuZm9yRWFjaChyPT5jb3VudHMuc2V0KHIubGFiZWwsKGNvdW50cy5nZXQoci5sYWJlbCl8fDApKzEpKTtyZXN1bHRzLnNvcnQoKGEsYik9Pihjb3VudHMuZ2V0KGIubGFiZWwpLWNvdW50cy5nZXQoYS5sYWJlbCkpKTtjb25zdCBiZXN0PXJlc3VsdHNbMF07c3RvcC5wb2lfbmFtZT1iZXN0LmxhYmVsO3N0b3AucG9pX3R5cGU9YmVzdC50eXBlO2lmKHYxMDNHZW5lcmljTmFtZShzdG9wLm5hbWUpKXtzdG9wLm5hbWU9YmVzdC5sYWJlbDtzdG9wLm5hbWVfc291cmNlPSdwb2knfXJldHVybiB0cnVlfQphc3luYyBmdW5jdGlvbiB2MTAzU2NoZWR1bGVQb2lOYW1pbmcoZm9yY2Upe2lmKHYxMDNQb2lCdXN5fHwhcHJvamVjdClyZXR1cm47Y29uc3QgcXVldWU9KHByb2plY3Quc3RvcHN8fFtdKS5maWx0ZXIocz0+Zm9yY2V8fCghdjEwM1BvaUF0dGVtcHRlZC5oYXMocy5zdG9wX2lkKSYmdjEwM0dlbmVyaWNOYW1lKHMubmFtZSkpKTtpZighcXVldWUubGVuZ3RoKXJldHVybiB0b2FzdCgnU3RvcCBuYW1lcyBhcmUgYWxyZWFkeSB1cCB0byBkYXRlLicpO3YxMDNQb2lCdXN5PXRydWU7ZWwoJ3N1Z2dlc3ROYW1lc0J1dHRvbicpLnRleHRDb250ZW50PSdOYW1pbmfigKYnO3RvYXN0KGBGaW5kaW5nIG1hcCBuYW1lcyBmb3IgJHtxdWV1ZS5sZW5ndGh9IHN0b3BzIGluIHRoZSBiYWNrZ3JvdW5kLmApO2xldCBjaGFuZ2VkPTA7Zm9yKGNvbnN0IHN0b3Agb2YgcXVldWUpe3YxMDNQb2lBdHRlbXB0ZWQuYWRkKHN0b3Auc3RvcF9pZCk7aWYoc3RvcC5uYW1lX3NvdXJjZT09PSdtYW51YWwnKWNvbnRpbnVlO2lmKGF3YWl0IHYxMDNOYW1lT25lU3RvcChzdG9wKSljaGFuZ2VkKys7aWYoY2hhbmdlZCYmY2hhbmdlZCU2PT09MCl7YXdhaXQgdjEwM1NhdmVQcm9qZWN0UXVpZXQoKTtyZW5kZXJTdG9wcygpfX1pZihjaGFuZ2VkKXthd2FpdCB2MTAzU2F2ZVByb2plY3RRdWlldCgpO3JlbmRlckFsbCgpO3RvYXN0KGBBZGRlZCBtYXAtYmFzZWQgbmFtZXMgdG8gJHtjaGFuZ2VkfSBzdG9wcy5gKX1lbHNlIHRvYXN0KCdObyBhZGRpdGlvbmFsIG5hbWVkIG1hcCBmZWF0dXJlcyB3ZXJlIGZvdW5kLicpO3YxMDNQb2lCdXN5PWZhbHNlO2VsKCdzdWdnZXN0TmFtZXNCdXR0b24nKS50ZXh0Q29udGVudD0nTmFtZSBmcm9tIE1hcCd9CgpmdW5jdGlvbiB2MTAzUHJlc2VudEl0ZW1zKCl7cmV0dXJuIHYxMDNGbGF0SXRlbXMoKX0KZnVuY3Rpb24gdjEwM0N1cnJlbnRQcmVzZW50SXRlbSgpe3JldHVybiB2MTAzUHJlc2VudEl0ZW18fHYxMDNQcmVzZW50SXRlbXMoKVt2MTAzUHJlc2VudEZsYXRJbmRleF18fG51bGx9CnByZXNlbnRBc3NldHM9ZnVuY3Rpb24oKXtyZXR1cm4gdjEwM0l0ZW1Bc3NldHModjEwM0N1cnJlbnRQcmVzZW50SXRlbSgpKX07CnJlbmRlclByZXNlbnRTdG9wcz1mdW5jdGlvbigpe2NvbnN0IGRheXM9djEwM0pvdXJuZXlEYXlzKCk7ZWwoJ3ByZXNlbnRTdG9wUmFpbCcpLmlubmVySFRNTD1kYXlzLm1hcChkYXk9PmA8ZGl2IGNsYXNzPSJwcmVzZW50RGF5TGFiZWwiIGRhdGEtcHJlc2VudC1kYXk9IiR7ZXNjKGRheS5rZXkpfSI+JHtlc2MoZGF5LnRpdGxlKX08c3Bhbj4ke2RheS5hc3NldENvdW50fSBwaG90b3M8L3NwYW4+PC9kaXY+JHtkYXkuaXRlbXMubWFwKGl0ZW09Pntjb25zdCBmbGF0PXYxMDNQcmVzZW50SXRlbXMoKS5maW5kSW5kZXgoeD0+djEwM0l0ZW1JZCh4KT09PXYxMDNJdGVtSWQoaXRlbSkpO3JldHVybmA8ZGl2IGNsYXNzPSJwcmVzZW50U3RvcEl0ZW0gJHtmbGF0PT09djEwM1ByZXNlbnRGbGF0SW5kZXgmJnByZXNlbnRWaWV3IT09J2RheSc/J2FjdGl2ZSc6Jyd9IiBkYXRhLXByZXNlbnQtaXRlbT0iJHtmbGF0fSI+JHtpdGVtLnR5cGU9PT0nc2VnbWVudCc/J+KXhyc6J+KAoid9ICR7ZXNjKHYxMDNJdGVtTmFtZShpdGVtKSl9PGRpdiBjbGFzcz0ic21hbGwiPiR7djEwM0l0ZW1Bc3NldHMoaXRlbSkubGVuZ3RofSBwaG90b3Mg4oCiICR7ZXNjKHYxMDNJdGVtUmFuZ2UoaXRlbSkpfTwvZGl2PjwvZGl2PmB9KS5qb2luKCcnKX1gKS5qb2luKCcnKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1wcmVzZW50LWl0ZW1dJykuZm9yRWFjaCh4PT54Lm9uY2xpY2s9KCk9PnYxMDNHb1ByZXNlbnRJdGVtKE51bWJlcih4LmRhdGFzZXQucHJlc2VudEl0ZW0pKSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtcHJlc2VudC1kYXldJykuZm9yRWFjaCh4PT54Lm9uY2xpY2s9KCk9PnYxMDNDZW50ZXJQcmVzZW50RGF5KHguZGF0YXNldC5wcmVzZW50RGF5KSl9OwpmdW5jdGlvbiB2MTAzSXRlbUJvdW5kcyhpdGVtKXtjb25zdCBib3VuZHM9bmV3IG1hcGxpYnJlZ2wuTG5nTGF0Qm91bmRzKCk7djEwM0l0ZW1Bc3NldHMoaXRlbSkuZmlsdGVyKHZhbGlkUG9pbnQpLmZvckVhY2goYT0+Ym91bmRzLmV4dGVuZChbTnVtYmVyKGEubG9uKSxOdW1iZXIoYS5sYXQpXSkpO2lmKGJvdW5kcy5pc0VtcHR5KCkpdjEwM0l0ZW1TdG9wcyhpdGVtKS5maWx0ZXIodmFsaWRQb2ludCkuZm9yRWFjaChzPT5ib3VuZHMuZXh0ZW5kKFtOdW1iZXIocy5sb24pLE51bWJlcihzLmxhdCldKSk7cmV0dXJuIGJvdW5kc30KZnVuY3Rpb24gdjEwM0l0ZW1DZW50ZXIoaXRlbSl7Y29uc3QgcHRzPXYxMDNJdGVtQXNzZXRzKGl0ZW0pLmZpbHRlcih2YWxpZFBvaW50KTtpZihwdHMubGVuZ3RoKXJldHVybltwdHMucmVkdWNlKChuLGEpPT5uK051bWJlcihhLmxvbiksMCkvcHRzLmxlbmd0aCxwdHMucmVkdWNlKChuLGEpPT5uK051bWJlcihhLmxhdCksMCkvcHRzLmxlbmd0aF07Y29uc3Qgcz12MTAzSXRlbVN0b3BzKGl0ZW0pWzBdO3JldHVybiB2YWxpZFBvaW50KHMpP1tOdW1iZXIocy5sb24pLE51bWJlcihzLmxhdCldOm51bGx9CmZ1bmN0aW9uIHYxMDNHb1ByZXNlbnRJdGVtKGluZGV4KXtjb25zdCBpdGVtcz12MTAzUHJlc2VudEl0ZW1zKCk7aWYoIWl0ZW1zLmxlbmd0aClyZXR1cm47c3RvcFByZXNlbnRPcmJpdCgpO2NsZWFyUHJlc2VudEZvY3VzKCk7djEwM1ByZXNlbnRGbGF0SW5kZXg9KGluZGV4K2l0ZW1zLmxlbmd0aCklaXRlbXMubGVuZ3RoO3YxMDNQcmVzZW50SXRlbT1pdGVtc1t2MTAzUHJlc2VudEZsYXRJbmRleF07djEwM1ByZXNlbnREYXlLZXk9djEwM1ByZXNlbnRJdGVtLmRheS5rZXk7cHJlc2VudFZpZXc9J2l0ZW0nO3ByZXNlbnRQaG90b0luZGV4PS0xO2NvbnN0IGZpcnN0U3RvcD12MTAzSXRlbVN0b3BzKHYxMDNQcmVzZW50SXRlbSlbMF07cHJlc2VudFN0b3BJbmRleD1maXJzdFN0b3A/djEwM1N0b3BJbmRleChmaXJzdFN0b3Auc3RvcF9pZCk6MDtyZW5kZXJQcmVzZW50U3RvcHMoKTtyZW5kZXJQcmVzZW50RmlsbXN0cmlwKCk7cmVuZGVyUHJlc2VudFBob3RvQnViYmxlcygpO2NvbnN0IG5hbWU9djEwM0l0ZW1OYW1lKHYxMDNQcmVzZW50SXRlbSkscmFuZ2U9djEwM0l0ZW1SYW5nZSh2MTAzUHJlc2VudEl0ZW0pLGFzc2V0cz12MTAzSXRlbUFzc2V0cyh2MTAzUHJlc2VudEl0ZW0pO2VsKCdwcmVzZW50SGVhZGVyVGl0bGUnKS50ZXh0Q29udGVudD1uYW1lO2VsKCdwcmVzZW50SGVhZGVyTWV0YScpLnRleHRDb250ZW50PWAke3YxMDNQcmVzZW50SXRlbS5kYXkudGl0bGV9IOKAoiAke3YxMDNQcmVzZW50SXRlbS50eXBlPT09J3NlZ21lbnQnPyh2MTAzUHJlc2VudEl0ZW0uc2VnbWVudC50eXBlfHwnc2VnbWVudCcpOidzdG9wJ30g4oCiICR7YXNzZXRzLmxlbmd0aH0gcGhvdG9zYDtlbCgncHJlc2VudFN0b3BCYW5uZXJUaXRsZScpLnRleHRDb250ZW50PW5hbWU7ZWwoJ3ByZXNlbnRTdG9wQmFubmVyUmFuZ2UnKS50ZXh0Q29udGVudD1gJHt2MTAzUHJlc2VudEl0ZW0uZGF5LnRpdGxlfSDigKIgJHtyYW5nZX0g4oCiICR7YXNzZXRzLmxlbmd0aH0gcGhvdG9zYDtlbCgncHJlc2VudFBob3RvQ2FyZCcpLmNsYXNzTGlzdC5yZW1vdmUoJ3Nob3cnKTtjb25zdCBjZW50ZXI9djEwM0l0ZW1DZW50ZXIodjEwM1ByZXNlbnRJdGVtKSxib3VuZHM9djEwM0l0ZW1Cb3VuZHModjEwM1ByZXNlbnRJdGVtKTtpZihjZW50ZXIpc2hvd1ByZXNlbnRGb2N1cyh7bG9uOmNlbnRlclswXSxsYXQ6Y2VudGVyWzFdfSk7aWYoIWJvdW5kcy5pc0VtcHR5KCkpe3ByZXNlbnRNYXAuZml0Qm91bmRzKGJvdW5kcyx7cGFkZGluZzp7dG9wOjEzMCxib3R0b206MjA1LGxlZnQ6Mjg1LHJpZ2h0OjQzMH0sbWF4Wm9vbTp2MTAzUHJlc2VudEl0ZW0udHlwZT09PSdzZWdtZW50Jz8xNC44OjE2LjEsZHVyYXRpb246MTgwMCxlc3NlbnRpYWw6dHJ1ZX0pO3NldFRpbWVvdXQoKCk9PntwcmVzZW50TWFwLmVhc2VUbyh7cGl0Y2g6NTgsYmVhcmluZzoodjEwM1ByZXNlbnRGbGF0SW5kZXgqMjkpJTM2MCxkdXJhdGlvbjo3NTAsZXNzZW50aWFsOnRydWV9KTtpZihjZW50ZXIpc3RhcnRQcmVzZW50T3JiaXQoY2VudGVyLE1hdGgubWluKHByZXNlbnRNYXAuZ2V0Wm9vbSgpLHYxMDNQcmVzZW50SXRlbS50eXBlPT09J3NlZ21lbnQnPzE0Ljg6MTYuMSksNTgpfSwxMDAwKX19CmdvUHJlc2VudFN0b3A9ZnVuY3Rpb24oaW5kZXgpe2NvbnN0IHN0b3A9cHJvamVjdD8uc3RvcHM/LlsoaW5kZXgrKHByb2plY3Q/LnN0b3BzPy5sZW5ndGh8fDEpKSUocHJvamVjdD8uc3RvcHM/Lmxlbmd0aHx8MSldO2lmKCFzdG9wKXJldHVybjtjb25zdCBmbGF0PXYxMDNQcmVzZW50SXRlbXMoKS5maW5kSW5kZXgoaXRlbT0+djEwM0l0ZW1TdG9wcyhpdGVtKS5zb21lKHM9PnMuc3RvcF9pZD09PXN0b3Auc3RvcF9pZCkpO3YxMDNHb1ByZXNlbnRJdGVtKGZsYXQ8MD8wOmZsYXQpfTsKZnVuY3Rpb24gdjEwM09wZW5QcmVzZW50U2VnbWVudChpZCl7Y29uc3QgZmxhdD12MTAzUHJlc2VudEl0ZW1zKCkuZmluZEluZGV4KGl0ZW09Pml0ZW0udHlwZT09PSdzZWdtZW50JyYmaXRlbS5zZWdtZW50LmlkPT09aWQpO29wZW5QcmVzZW50KDApO3NldFRpbWVvdXQoKCk9PnYxMDNHb1ByZXNlbnRJdGVtKGZsYXQ8MD8wOmZsYXQpLDE4MCl9CmZ1bmN0aW9uIHYxMDNDZW50ZXJQcmVzZW50RGF5KGtleSl7aWYoIXByZXNlbnRNYXApcmV0dXJuO3N0b3BQcmVzZW50T3JiaXQoKTtwcmVzZW50Vmlldz0nZGF5Jzt2MTAzUHJlc2VudERheUtleT1rZXk7Y29uc3QgZGF5PXYxMDNKb3VybmV5RGF5cygpLmZpbmQoZD0+ZC5rZXk9PT1rZXkpO2lmKCFkYXkpcmV0dXJuO2NvbnN0IGJvdW5kcz1uZXcgbWFwbGlicmVnbC5MbmdMYXRCb3VuZHMoKTtkYXkuaXRlbXMuZmxhdE1hcCh2MTAzSXRlbUFzc2V0cykuZmlsdGVyKHZhbGlkUG9pbnQpLmZvckVhY2goYT0+Ym91bmRzLmV4dGVuZChbTnVtYmVyKGEubG9uKSxOdW1iZXIoYS5sYXQpXSkpO2lmKCFib3VuZHMuaXNFbXB0eSgpKXByZXNlbnRNYXAuZml0Qm91bmRzKGJvdW5kcyx7cGFkZGluZzp7dG9wOjEyMCxib3R0b206MTIwLGxlZnQ6Mjg1LHJpZ2h0OjkwfSxtYXhab29tOjEyLjgsZHVyYXRpb246MTUwMCxlc3NlbnRpYWw6dHJ1ZX0pO2VsKCdwcmVzZW50SGVhZGVyVGl0bGUnKS50ZXh0Q29udGVudD1kYXkudGl0bGU7ZWwoJ3ByZXNlbnRIZWFkZXJNZXRhJykudGV4dENvbnRlbnQ9YCR7ZGF5Lml0ZW1zLmxlbmd0aH0gc3RvcHMgYW5kIHNlZ21lbnRzIOKAoiAke2RheS5hc3NldENvdW50fSBwaG90b3NgO2VsKCdwcmVzZW50U3RvcEJhbm5lclRpdGxlJykudGV4dENvbnRlbnQ9ZGF5LnRpdGxlO2VsKCdwcmVzZW50U3RvcEJhbm5lclJhbmdlJykudGV4dENvbnRlbnQ9YERheSBvdmVydmlldyDigKIgJHtkYXkuYXNzZXRDb3VudH0gcGhvdG9zIOKAoiAke2RheS5zdG9wQ291bnR9IG9yaWdpbmFsIHN0b3BzYDtlbCgncHJlc2VudFBob3RvQ2FyZCcpLmNsYXNzTGlzdC5yZW1vdmUoJ3Nob3cnKTtyZW5kZXJQcmVzZW50U3RvcHMoKX0KY2VudGVyUHJlc2VudFRyaXA9ZnVuY3Rpb24oKXtpZighcHJlc2VudE1hcHx8IXByb2plY3Q/LnN0b3BzPy5sZW5ndGgpcmV0dXJuO3N0b3BQcmVzZW50T3JiaXQoKTtwcmVzZW50Vmlldz0ndHJpcCc7Y29uc3QgYm91bmRzPXRyaXBCb3VuZHMoKTtpZighYm91bmRzLmlzRW1wdHkoKSlwcmVzZW50TWFwLmZpdEJvdW5kcyhib3VuZHMse3BhZGRpbmc6e3RvcDoxMTAsYm90dG9tOjExMCxsZWZ0OjI4NSxyaWdodDo4MH0sbWF4Wm9vbToxMi41LGR1cmF0aW9uOjE1MDAsZXNzZW50aWFsOnRydWV9KTtjbGVhclByZXNlbnRGb2N1cygpO2NvbnN0IGRheXM9djEwM0pvdXJuZXlEYXlzKCk7ZWwoJ3ByZXNlbnRIZWFkZXJUaXRsZScpLnRleHRDb250ZW50PXByb2plY3QubmFtZXx8J0pvdXJuZXkgT3ZlcnZpZXcnO2VsKCdwcmVzZW50SGVhZGVyTWV0YScpLnRleHRDb250ZW50PWAke2RheXMubGVuZ3RofSBkYXlzIOKAoiAke3Byb2plY3Quc3RvcHMubGVuZ3RofSBzdG9wcyDigKIgJHsocHJvamVjdC5hc3NldHN8fFtdKS5sZW5ndGh9IHBob3Rvc2A7ZWwoJ3ByZXNlbnRTdG9wQmFubmVyVGl0bGUnKS50ZXh0Q29udGVudD1wcm9qZWN0Lm5hbWV8fCdKb3VybmV5IE92ZXJ2aWV3JztlbCgncHJlc2VudFN0b3BCYW5uZXJSYW5nZScpLnRleHRDb250ZW50PWAke2RheXMubGVuZ3RofSBkYXlzIOKAoiAke3YxMDNQcmVzZW50SXRlbXMoKS5sZW5ndGh9IHN0b3BzIGFuZCBzZWdtZW50c2A7ZWwoJ3ByZXNlbnRQaG90b0NhcmQnKS5jbGFzc0xpc3QucmVtb3ZlKCdzaG93Jyk7cmVuZGVyUHJlc2VudFN0b3BzKCl9OwpwcmVzZW50QmFjaz1mdW5jdGlvbigpe2lmKHByZXNlbnRWaWV3PT09J3Bob3RvJyl7djEwM0dvUHJlc2VudEl0ZW0odjEwM1ByZXNlbnRGbGF0SW5kZXgpO3JldHVybn1pZihwcmVzZW50Vmlldz09PSdpdGVtJyl7djEwM0NlbnRlclByZXNlbnREYXkodjEwM1ByZXNlbnREYXlLZXkpO3JldHVybn1pZihwcmVzZW50Vmlldz09PSdkYXknKXtjZW50ZXJQcmVzZW50VHJpcCgpO3JldHVybn1jZW50ZXJQcmVzZW50VHJpcCgpfTsKcmV0dXJuUHJlc2VudFN0YXJ0PWZ1bmN0aW9uKCl7djEwM1ByZXNlbnRGbGF0SW5kZXg9MDtwcmVzZW50UGhvdG9JbmRleD0tMTt2MTAzR29QcmVzZW50SXRlbSgwKX07CmdvUHJlc2VudFBob3RvPWZ1bmN0aW9uKGluZGV4KXtjb25zdCBhc3NldHM9cHJlc2VudEFzc2V0cygpO2lmKCFhc3NldHMubGVuZ3RoKXJldHVybjtzdG9wUHJlc2VudE9yYml0KCk7cHJlc2VudFZpZXc9J3Bob3RvJztwcmVzZW50UGhvdG9JbmRleD0oaW5kZXgrYXNzZXRzLmxlbmd0aCklYXNzZXRzLmxlbmd0aDtjb25zdCBhc3NldD1hc3NldHNbcHJlc2VudFBob3RvSW5kZXhdO2lmKCF2YWxpZFBvaW50KGFzc2V0KSlyZXR1cm47cmVuZGVyUHJlc2VudEZpbG1zdHJpcCgpO3JlbmRlclByZXNlbnRQaG90b0J1YmJsZXMoKTtzaG93UHJlc2VudEZvY3VzKGFzc2V0KTtjb25zdCBpdGVtPXYxMDNDdXJyZW50UHJlc2VudEl0ZW0oKSxuYW1lPXYxMDNJdGVtTmFtZShpdGVtKTtlbCgncHJlc2VudFN0b3BCYW5uZXJUaXRsZScpLnRleHRDb250ZW50PW5hbWU7ZWwoJ3ByZXNlbnRTdG9wQmFubmVyUmFuZ2UnKS50ZXh0Q29udGVudD1gUGhvdG8gJHtwcmVzZW50UGhvdG9JbmRleCsxfSBvZiAke2Fzc2V0cy5sZW5ndGh9IOKAoiAke2Zvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSl9YDtlbCgncHJlc2VudFBob3RvQ2FyZCcpLmlubmVySFRNTD1gJHthc3NldC5wcmV2aWV3fHxhc3NldC50aHVtYj9gPGltZyBzcmM9IiR7ZXNjKGFzc2V0LnByZXZpZXd8fGFzc2V0LnRodW1iKX0iPmA6Jyd9PGRpdiBjbGFzcz0icHJlc2VudFBob3RvQm9keSI+PGRpdiBjbGFzcz0icHJlc2VudFBob3RvVGl0bGUiPlBob3RvICR7cHJlc2VudFBob3RvSW5kZXgrMX0gb2YgJHthc3NldHMubGVuZ3RofTwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRQaG90b01ldGEiPiR7ZXNjKGZvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSkpfTwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRQaG90b0Nvb3JkcyI+JHtlc2MoYXNzZXRDb29yZGluYXRlVGV4dChhc3NldCkpfTwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRQaG90b0FjdGlvbnMiPjxidXR0b24gb25jbGljaz0idjEwM0dvUHJlc2VudEl0ZW0odjEwM1ByZXNlbnRGbGF0SW5kZXgpIj5CYWNrIHRvICR7aXRlbS50eXBlPT09J3NlZ21lbnQnPydTZWdtZW50JzonU3RvcCd9PC9idXR0b24+PGJ1dHRvbiBjbGFzcz0iZGFuZ2VyIiBvbmNsaWNrPSJyZW1vdmVBc3NldEZyb21Kb3VybmV5KCcke2VzYyhhc3NldC5hc3NldF9pZCl9JykiPlJlbW92ZSBmcm9tIEpvdXJuZXk8L2J1dHRvbj48L2Rpdj48L2Rpdj5gO2VsKCdwcmVzZW50UGhvdG9DYXJkJykuY2xhc3NMaXN0LmFkZCgnc2hvdycpO2NvbnN0IGNlbnRlcj1bTnVtYmVyKGFzc2V0LmxvbiksTnVtYmVyKGFzc2V0LmxhdCldLHpvb209MTcuNDU7cHJlc2VudE1hcC5mbHlUbyh7Y2VudGVyLHpvb20scGl0Y2g6NTAsYmVhcmluZzoocHJlc2VudFBob3RvSW5kZXgqMTcpJTM2MCxkdXJhdGlvbjoxMzUwLGN1cnZlOjEuMyxlc3NlbnRpYWw6dHJ1ZX0pO3N0YXJ0UHJlc2VudE9yYml0KGNlbnRlcix6b29tLDUwKX07Cm9wZW5QcmVzZW50PWZ1bmN0aW9uKGluZGV4PTApe2lmKCFwcm9qZWN0Py5zdG9wcz8ubGVuZ3RoKXJldHVybiB0b2FzdCgnTG9hZCBhIGpvdXJuZXkgd2l0aCBzdG9wcyBmaXJzdC4nKTtlbCgncHJlc2VudE92ZXJsYXknKS5jbGFzc0xpc3QuYWRkKCdzaG93Jyk7ZW5zdXJlUHJlc2VudE1hcCgpO2NvbnN0IHN0b3A9cHJvamVjdC5zdG9wc1tpbmRleF18fHByb2plY3Quc3RvcHNbMF0sZmxhdD12MTAzUHJlc2VudEl0ZW1zKCkuZmluZEluZGV4KGl0ZW09PnYxMDNJdGVtU3RvcHMoaXRlbSkuc29tZShzPT5zLnN0b3BfaWQ9PT1zdG9wLnN0b3BfaWQpKTtzZXRUaW1lb3V0KCgpPT57cHJlc2VudE1hcC5yZXNpemUoKTtjb25zdCBzdGFydD0oKT0+e3JlbmRlclByZXNlbnRNYXBMYXllcnMoKTt2MTAzR29QcmVzZW50SXRlbShmbGF0PDA/MDpmbGF0KX07aWYocHJlc2VudE1hcC5pc1N0eWxlTG9hZGVkKCkpc3RhcnQoKTtlbHNlIHByZXNlbnRNYXAub25jZSgnbG9hZCcsc3RhcnQpfSw5MCl9Owp0b2dnbGVQbGF5PWZ1bmN0aW9uKCl7aWYocHJlc2VudFRpbWVyKXtjbGVhckludGVydmFsKHByZXNlbnRUaW1lcik7cHJlc2VudFRpbWVyPW51bGw7ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykudGV4dENvbnRlbnQ9J+KWtiBQbGF5JztyZXR1cm59ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykudGV4dENvbnRlbnQ9J+KFoSBQYXVzZSc7cHJlc2VudFRpbWVyPXNldEludGVydmFsKCgpPT57Y29uc3QgYXNzZXRzPXByZXNlbnRBc3NldHMoKTtpZihwcmVzZW50Vmlldz09PSdpdGVtJyYmYXNzZXRzLmxlbmd0aCl7Z29QcmVzZW50UGhvdG8oMCk7cmV0dXJufWlmKHByZXNlbnRWaWV3PT09J3Bob3RvJyYmcHJlc2VudFBob3RvSW5kZXg8YXNzZXRzLmxlbmd0aC0xKXtnb1ByZXNlbnRQaG90byhwcmVzZW50UGhvdG9JbmRleCsxKTtyZXR1cm59djEwM0dvUHJlc2VudEl0ZW0odjEwM1ByZXNlbnRGbGF0SW5kZXgrMSl9LDQzMDApfTsKCmZ1bmN0aW9uIHYxMDNSZWJpbmRQcmVzZW50YXRpb24oKXtlbCgncHJldmlvdXNTdG9wQnV0dG9uJykub25jbGljaz0oKT0+djEwM0dvUHJlc2VudEl0ZW0odjEwM1ByZXNlbnRGbGF0SW5kZXgtMSk7ZWwoJ25leHRTdG9wQnV0dG9uJykub25jbGljaz0oKT0+djEwM0dvUHJlc2VudEl0ZW0odjEwM1ByZXNlbnRGbGF0SW5kZXgrMSk7ZWwoJ3ByZXNlbnRCYWNrQnV0dG9uJykub25jbGljaz1wcmVzZW50QmFjaztlbCgnY2VudGVyVHJpcEJ1dHRvbicpLm9uY2xpY2s9Y2VudGVyUHJlc2VudFRyaXA7ZWwoJ3JldHVyblN0YXJ0QnV0dG9uJykub25jbGljaz1yZXR1cm5QcmVzZW50U3RhcnQ7ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykub25jbGljaz10b2dnbGVQbGF5O2VsKCdjbGVhckZpbHRlckJ1dHRvbicpLm9uY2xpY2s9KCk9PntmaWx0ZXJTdG9wSWQ9bnVsbDthY3RpdmVTdG9wSWQ9bnVsbDt2MTAzQWN0aXZlU2VnbWVudElkPW51bGw7cmVuZGVyR2FsbGVyeSgpO3JlbmRlclN0b3BzKCk7cmVuZGVyTWFwKGZhbHNlKX19Cgp2MTAzQnVpbGRSYWlsKCk7djEwM0luc2VydFNlZ21lbnRNb2RhbCgpO3YxMDNSZWJpbmRQcmVzZW50YXRpb24oKTsKY29uc3QgdjEwM09yaWdpbmFsUmVuZGVyQWxsPXJlbmRlckFsbDsKcmVuZGVyQWxsPWZ1bmN0aW9uKCl7djEwM0Vuc3VyZU1vZGVsKCk7cmVuZGVyUHJvamVjdHMoKTtyZW5kZXJIZWFkZXIoKTtyZW5kZXJTdG9wcygpO3JlbmRlckdhbGxlcnkoKTtyZW5kZXJNYXAodHJ1ZSl9OwppZihwcm9qZWN0KXt2MTAzRW5zdXJlTW9kZWwoKTtyZW5kZXJBbGwoKTtzZXRUaW1lb3V0KCgpPT52MTAzU2NoZWR1bGVQb2lOYW1pbmcoZmFsc2UpLDEyMDApfQoKPC9zY3JpcHQ+CjwvYm9keT4KPC9odG1sPg==
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








pct exec "$CTID" -- bash -lc "grep -q 'Trippy v10.3.0' /opt/trippy/frontend/index.html && grep -q 'presentMap' /opt/trippy/frontend/index.html && grep -q 'photoMarker' /opt/trippy/frontend/index.html && test -s /opt/trippy/frontend/vendor/maplibre-gl.js" >/dev/null 2>&1 || {
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
printf "${CYAN}${BOLD}v10.3.0 features${RESET}\n"
printf "  ${CYAN}•${RESET} Full mockup-driven frontend replacement\n"
printf "  ${CYAN}•${RESET} Light OSM, dark, and satellite map modes\n"
printf "  ${CYAN}•${RESET} Thumbnail stop markers, route glow, and single clean popups\n"
printf "  ${CYAN}•${RESET} Cinematic Present Journey with stop and photo fly-through controls\n"
printf "  ${CYAN}•${RESET} Immich date-range import and upload-based GPS media import\n"
printf "  ${CYAN}•${RESET} Stop clustering, renaming, recentering, deletion, and route reversal\n"
printf "  ${CYAN}•${RESET} Project deletion, saved Immich connection, GPX, and MP4 export\n"
printf "  ${CYAN}•${RESET} Local MapLibre bundle for reliable frontend loading\n"
printf "  ${CYAN}•${RESET} Auto-selects the next available CTID and uses hostname Trippy\n"
printf "  ${CYAN}•${RESET} v10.3.0 organizes journeys by day, supports combined drive/hike segments, and suggests OSM-based stop names\n"
printf "${PINK}${BOLD}Go make something weird.${RESET}\n"
