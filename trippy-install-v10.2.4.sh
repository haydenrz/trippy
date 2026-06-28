#!/usr/bin/env bash
set -euo pipefail
USER_SUPPLIED_CTID="${CTID:-}"

# Trippy v10.2.4: Immich-style web UI route-tour generator for Proxmox LXC
# Adds stop-based clustering, stop radius, stop review/editing, and lasso grouping.
#
#
# Install directly from GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.2.4.sh \
#     -o trippy-install-v10.2.4.sh
#   chmod +x trippy-install-v10.2.4.sh
#   ./trippy-install-v10.2.4.sh
#
# Or with wget:
#
#   wget -O trippy-install-v10.2.4.sh \
#     https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.2.4.sh
#   chmod +x trippy-install-v10.2.4.sh
#   ./trippy-install-v10.2.4.sh
#
# Run on Proxmox host:
#   bash trippy-install-v10.2.4.sh
#
# Optional:
#   CTID=106 STORAGE=local-lvm BRIDGE=vmbr0 bash trippy-install-v10.2.4.sh

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

printf "${CYAN}${BOLD}Trippy v10.2.4 Clean Installer${RESET}\n"
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

pct set "$CTID" --description "🧭 Trippy v10.2.4
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

app = FastAPI(title="Trippy", version="1.2.4")
app.mount("/exports", StaticFiles(directory=str(EXPORTS)), name="exports")
app.mount("/uploads", StaticFiles(directory=str(UPLOADS)), name="uploads")
app.mount("/static", StaticFiles(directory=str(FRONTEND)), name="static")

@app.get("/api/health")
def health():
    return {
        "ok": True,
        "app": "trippy",
        "version": "1.2.4",
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
// Trippy v10.2.4 UI behavior upgrades
(function(){{
  function ready(fn){{ if(document.readyState!=='loading') fn(); else document.addEventListener('DOMContentLoaded',fn); }}
  window.TRIPPY_VERSION='v10.2.4';
  ready(() => {{
    if(!document.querySelector('.versionBadge')){{
      const v=document.createElement('div'); v.className='versionBadge'; v.textContent='v10.2.4'; document.body.appendChild(v);
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
      const v=document.createElement('div');v.className='versionBadge';v.textContent='v10.2.4';document.body.appendChild(v);
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

/* Trippy v10.2.4 UI refresh */
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






# v10.2.4: full frontend replacement, not an overlay.
pct exec "$CTID" -- bash -lc "cat >/tmp/trippy_frontend.b64 <<'EOF_TRIPPY_FRONTEND_B64'
PCFkb2N0eXBlIGh0bWw+CjxodG1sIGxhbmc9ImVuIj4KPGhlYWQ+CjxtZXRhIGNoYXJzZXQ9InV0Zi04Ij4KPG1ldGEgbmFtZT0idmlld3BvcnQiIGNvbnRlbnQ9IndpZHRoPWRldmljZS13aWR0aCxpbml0aWFsLXNjYWxlPTEiPgo8dGl0bGU+VHJpcHB5IHYxMC4yLjQ8L3RpdGxlPgo8bGluayByZWw9InN0eWxlc2hlZXQiIGhyZWY9Ii9zdGF0aWMvdmVuZG9yL21hcGxpYnJlLWdsLmNzcyI+CjxzY3JpcHQgc3JjPSIvc3RhdGljL3ZlbmRvci9tYXBsaWJyZS1nbC5qcyI+PC9zY3JpcHQ+CjxzdHlsZT4KOnJvb3R7CiAgLS1iZzojMDMwODEzOy0tYmcyOiMwNzExMWQ7LS1wYW5lbDojMDgxNDIxOy0tcGFuZWwyOiMwZDFjMmM7LS1jYXJkOiMwYzFhMjk7CiAgLS1saW5lOiMxZDM4NTA7LS1saW5lMjojMjU0YTY4Oy0tY3lhbjojMDBkOGZmOy0tY3lhbjI6IzM2ZWRmZjstLWJsdWU6IzI2N2RmZjsKICAtLXZpb2xldDojNjg0OGZmOy0tcGluazojZmY0ZGE2Oy0tZ3JlZW46IzM5ZDk5NTstLXJlZDojZmY0ZDY2Oy0tdGV4dDojZjJmOGZmOwogIC0tbXV0ZWQ6IzhlYTNiNjstLXNvZnQ6I2I4YzhkNzstLXNoYWRvdzowIDI0cHggNzBweCByZ2JhKDAsMCwwLC40MikKfQoqe2JveC1zaXppbmc6Ym9yZGVyLWJveH0KaHRtbCxib2R5e2hlaWdodDoxMDAlO21hcmdpbjowO292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOnZhcigtLWJnKTtjb2xvcjp2YXIoLS10ZXh0KTtmb250LWZhbWlseTpJbnRlciwiU2Vnb2UgVUkiLHN5c3RlbS11aSxzYW5zLXNlcmlmfQpib2R5e2JhY2tncm91bmQ6cmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCA5JSAwJSxyZ2JhKDAsMjE2LDI1NSwuMTMpLHRyYW5zcGFyZW50IDI3JSkscmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCA4MiUgNyUscmdiYSgxMDQsNzIsMjU1LC4xMiksdHJhbnNwYXJlbnQgMzAlKSxsaW5lYXItZ3JhZGllbnQoMTQ1ZGVnLCMwMjA3MTEsIzA3MTIxZSA1OCUsIzAyMDYwZCl9CmJ1dHRvbixpbnB1dCxzZWxlY3R7Zm9udDppbmhlcml0fWJ1dHRvbntjb2xvcjp2YXIoLS10ZXh0KTtjdXJzb3I6cG9pbnRlcjtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzUsMTI2LDE2NCwuNDUpO2JvcmRlci1yYWRpdXM6MTNweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgyMCw0Myw2NiwuOTgpLHJnYmEoMTAsMjUsNDEsLjk4KSk7Zm9udC13ZWlnaHQ6ODAwO3RyYW5zaXRpb246LjE2cyBlYXNlfWJ1dHRvbjpob3Zlcntib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMjJweCByZ2JhKDAsMjE2LDI1NSwuMjIpO3RyYW5zZm9ybTp0cmFuc2xhdGVZKC0xcHgpfQppbnB1dCxzZWxlY3R7d2lkdGg6MTAwJTtjb2xvcjp2YXIoLS10ZXh0KTtiYWNrZ3JvdW5kOiMwNzExMWM7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDkwLDEzOSwxNzMsLjM4KTtib3JkZXItcmFkaXVzOjEycHg7cGFkZGluZzoxMXB4IDEycHg7b3V0bGluZTpub25lfWlucHV0OmZvY3VzLHNlbGVjdDpmb2N1c3tib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMCAzcHggcmdiYSgwLDIxNiwyNTUsLjEwKX0KLnNtYWxse2ZvbnQtc2l6ZToxMnB4O2NvbG9yOnZhcigtLW11dGVkKX0uaGlkZGVue2Rpc3BsYXk6bm9uZSFpbXBvcnRhbnR9LnN2Z0ljb257d2lkdGg6MjBweDtoZWlnaHQ6MjBweDtzdHJva2U6Y3VycmVudENvbG9yO2ZpbGw6bm9uZTtzdHJva2Utd2lkdGg6MS44O3N0cm9rZS1saW5lY2FwOnJvdW5kO3N0cm9rZS1saW5lam9pbjpyb3VuZH0KLmFwcFNoZWxse2hlaWdodDoxMDB2aDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjI4NnB4IG1pbm1heCg2NTBweCwxZnIpIDM1MHB4O292ZXJmbG93OmhpZGRlbn0KLmxlZnRSYWlse21pbi13aWR0aDowO2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDE4MGRlZyxyZ2JhKDQsMTMsMjMsLjk4KSxyZ2JhKDIsOCwxNSwuOTkpKTtib3JkZXItcmlnaHQ6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4xNCk7cGFkZGluZzoxN3B4IDE3cHggMjBweDtkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO2dhcDoxNHB4O2JveC1zaGFkb3c6MTZweCAwIDYwcHggcmdiYSgwLDAsMCwuMzQpO3otaW5kZXg6MTB9Ci5icmFuZExpbmV7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTJweDtoZWlnaHQ6NjRweH0ud29yZG1hcmt7Zm9udC1zaXplOjMxcHg7Zm9udC13ZWlnaHQ6OTUwO2ZvbnQtc3R5bGU6aXRhbGljO2xldHRlci1zcGFjaW5nOi0xLjVweDt0ZXh0LXNoYWRvdzoycHggMCB2YXIoLS1jeWFuKSwtMnB4IDAgdmFyKC0tcGluayksMCA2cHggMjVweCByZ2JhKDAsMCwwLC45KX0udmVyc2lvbnttYXJnaW4tbGVmdDphdXRvO3BhZGRpbmc6NnB4IDEwcHg7Ym9yZGVyLXJhZGl1czo5OTlweDtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4yOCk7YmFja2dyb3VuZDpyZ2JhKDAsMjE2LDI1NSwuMDgpO2NvbG9yOnZhcigtLWN5YW4yKTtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5NTA7Ym94LXNoYWRvdzowIDAgMThweCByZ2JhKDAsMjE2LDI1NSwuMTApfQoubG9nb0Zsb3dlcntwb3NpdGlvbjpyZWxhdGl2ZTt3aWR0aDo0OXB4O2hlaWdodDo0OXB4O2ZsZXg6MCAwIGF1dG87ZmlsdGVyOmRyb3Atc2hhZG93KDAgMCAxMXB4IHJnYmEoMCwyMTYsMjU1LC4zNSkpIHNhdHVyYXRlKDEuMTgpfS5sb2dvRmxvd2VyIC5wZXRhbHtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjE4cHg7dG9wOjJweDt3aWR0aDoxN3B4O2hlaWdodDoyOXB4O2JvcmRlci1yYWRpdXM6MTRweCAxNHB4IDdweCA3cHg7dHJhbnNmb3JtLW9yaWdpbjo3cHggMjNweDttaXgtYmxlbmQtbW9kZTpzY3JlZW59LmxvZ29GbG93ZXIgLnAxe2JhY2tncm91bmQ6I2ZmNTQ1NDt0cmFuc2Zvcm06cm90YXRlKDBkZWcpIHRyYW5zbGF0ZVkoLTFweCkgc2tld1goLThkZWcpfS5sb2dvRmxvd2VyIC5wMntiYWNrZ3JvdW5kOiNmZmJiMzE7dHJhbnNmb3JtOnJvdGF0ZSg2MGRlZykgdHJhbnNsYXRlWSgwKSBza2V3WCg5ZGVnKX0ubG9nb0Zsb3dlciAucDN7YmFja2dyb3VuZDojNzlkZjRjO3RyYW5zZm9ybTpyb3RhdGUoMTIwZGVnKSB0cmFuc2xhdGVZKDFweCkgc2tld1goLThkZWcpfS5sb2dvRmxvd2VyIC5wNHtiYWNrZ3JvdW5kOiMyN2Q2Yzc7dHJhbnNmb3JtOnJvdGF0ZSgxODBkZWcpIHRyYW5zbGF0ZVkoLTFweCkgc2tld1goOGRlZyl9LmxvZ29GbG93ZXIgLnA1e2JhY2tncm91bmQ6IzQxOGNmZjt0cmFuc2Zvcm06cm90YXRlKDI0MGRlZykgdHJhbnNsYXRlWSgxcHgpIHNrZXdYKC0xMGRlZyl9LmxvZ29GbG93ZXIgLnA2e2JhY2tncm91bmQ6I2RmNjhmZjt0cmFuc2Zvcm06cm90YXRlKDMwMGRlZykgdHJhbnNsYXRlWSgtMXB4KSBza2V3WCg5ZGVnKX0ubG9nb0Zsb3dlcjpiZWZvcmV7Y29udGVudDoiIjtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDo2cHg7Ym9yZGVyLXJhZGl1czo1MCU7Ym94LXNoYWRvdzozcHggMCA4cHggcmdiYSgyNTUsNzcsMTY2LC40NSksLTNweCAwIDhweCByZ2JhKDAsMjE2LDI1NSwuNSk7ZmlsdGVyOmJsdXIoMXB4KX0ubG9nb0Zsb3dlcjphZnRlcntjb250ZW50OiIiO3Bvc2l0aW9uOmFic29sdXRlO2luc2V0OjE2cHg7Ym9yZGVyOjJweCBzb2xpZCByZ2JhKDI0NSwyNTMsMjU1LC44OCk7Ym9yZGVyLXJhZGl1czo1MCU7Ym94LXNoYWRvdzowIDAgOXB4IHJnYmEoMCwyMTYsMjU1LC45KX0KLnNpZGVQcmltYXJ5LC5zaWRlU2Vjb25kYXJ5e2hlaWdodDo1NHB4O3dpZHRoOjEwMCU7Zm9udC1zaXplOjE0cHh9LnNpZGVQcmltYXJ5e2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMDk2MmJkLCMwMGE5YzgpO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuODgpO2JveC1zaGFkb3c6MCAwIDI4cHggcmdiYSgwLDIxNiwyNTUsLjIxKX0KLnNlY3Rpb25MYWJlbHttYXJnaW4tdG9wOjhweDtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuO2NvbG9yOiNjNGQ0ZTI7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwO2xldHRlci1zcGFjaW5nOi4wOGVtO3RleHQtdHJhbnNmb3JtOnVwcGVyY2FzZX0ucHJvamVjdExpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6MTBweDtvdmVyZmxvdzphdXRvO21pbi1oZWlnaHQ6MDtwYWRkaW5nLXJpZ2h0OjJweH0ucHJvamVjdENhcmR7cG9zaXRpb246cmVsYXRpdmU7cGFkZGluZzoxNXB4IDE0cHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoMTMsMjksNDUsLjk0KSxyZ2JhKDcsMTgsMzAsLjk0KSk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDYyLDExMywxNTEsLjMyKTtib3JkZXItcmFkaXVzOjE1cHg7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTZzIGVhc2V9LnByb2plY3RDYXJkOmhvdmVyLC5wcm9qZWN0Q2FyZC5hY3RpdmV7Ym9yZGVyLWNvbG9yOnZhcigtLWN5YW4pO2JveC1zaGFkb3c6MCAwIDI0cHggcmdiYSgwLDIxNiwyNTUsLjE3KX0ucHJvamVjdENhcmRUaXRsZXtwYWRkaW5nLXJpZ2h0OjI0cHg7Zm9udC13ZWlnaHQ6OTAwO2ZvbnQtc2l6ZToxNHB4O3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30ucHJvamVjdERhdGV7bWFyZ2luLXRvcDo2cHg7Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxMnB4fS5wcm9qZWN0U3RhdHN7bWFyZ2luLXRvcDo5cHg7Y29sb3I6IzllYjRjNjtmb250LXNpemU6MTJweH0ucHJvamVjdFN0YXRzIC5kb3R7Y29sb3I6dmFyKC0tY3lhbil9LnByb2plY3RNZW51e3Bvc2l0aW9uOmFic29sdXRlO3JpZ2h0OjlweDt0b3A6MTBweDt3aWR0aDoyOHB4O2hlaWdodDozMnB4O2JvcmRlcjowO2JhY2tncm91bmQ6dHJhbnNwYXJlbnQ7Zm9udC1zaXplOjIwcHg7Ym94LXNoYWRvdzpub25lfS5wcm9qZWN0RGVsZXRle3dpZHRoOjEwMCU7aGVpZ2h0OjM0cHg7bWFyZ2luLXRvcDoxMHB4O2ZvbnQtc2l6ZToxMnB4O2Rpc3BsYXk6bm9uZX0ucHJvamVjdENhcmQubWVudU9wZW4gLnByb2plY3REZWxldGV7ZGlzcGxheTpibG9ja30KLmxlZnRGb290ZXJ7bWFyZ2luLXRvcDphdXRvO2NvbG9yOiM4Mjk2YTg7Zm9udC1zaXplOjEycHg7bGluZS1oZWlnaHQ6MS42NX0uZm9vdGVyTGlua3tkaXNwbGF5OmJsb2NrO21hcmdpbi10b3A6MTBweDtjb2xvcjp2YXIoLS1jeWFuKTt0ZXh0LWRlY29yYXRpb246bm9uZX0KLndvcmtzcGFjZXttaW4td2lkdGg6MDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1yb3dzOjkxcHggbWlubWF4KDM1MHB4LDFmcikgMjI4cHg7YmFja2dyb3VuZDpyZ2JhKDIsOCwxNCwuNTApfQoudG9wQmFye2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjE2cHg7cGFkZGluZzoxNHB4IDE5cHg7Ym9yZGVyLWJvdHRvbToxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjEzKTtiYWNrZ3JvdW5kOnJnYmEoMywxMCwxOCwuODQpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDE4cHgpO3otaW5kZXg6OH0udGl0bGVBcmVhe21pbi13aWR0aDozMjBweDttYXgtd2lkdGg6NDMwcHh9LmpvdXJuZXlUaXRsZVJvd3tkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDo5cHh9LmpvdXJuZXlUaXRsZXtmb250LXNpemU6MjJweDtmb250LXdlaWdodDo5NTA7d2hpdGUtc3BhY2U6bm93cmFwO292ZXJmbG93OmhpZGRlbjt0ZXh0LW92ZXJmbG93OmVsbGlwc2lzfS5lZGl0VGl0bGV7Ym9yZGVyOjA7YmFja2dyb3VuZDp0cmFuc3BhcmVudDtjb2xvcjp2YXIoLS1tdXRlZCk7cGFkZGluZzoycHg7Ym94LXNoYWRvdzpub25lfS5qb3VybmV5TWV0YXtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMXB4O21hcmdpbi10b3A6NnB4O2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTJweH0uam91cm5leU1ldGEgLmxpdmVEb3R7d2lkdGg6N3B4O2hlaWdodDo3cHg7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDp2YXIoLS1ncmVlbik7Ym94LXNoYWRvdzowIDAgOHB4IHJnYmEoNTcsMjE3LDE0OSwuNil9LnRvcFNwYWNlcntmbGV4OjF9LnByZXNlbnRCdXR0b257aGVpZ2h0OjU0cHg7bWluLXdpZHRoOjI2NXB4O3BhZGRpbmc6MCAyNHB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjNjMzYmZmLCMwMGFmZDApO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuODUpO2JveC1zaGFkb3c6MCAwIDMycHggcmdiYSgwLDIxNiwyNTUsLjI4KTtmb250LXNpemU6MTVweH0ucHJlc2VudEJ1dHRvbiBzcGFue2Rpc3BsYXk6YmxvY2s7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6NjUwO29wYWNpdHk6Ljg0O21hcmdpbi10b3A6MnB4fS50b3BBY3Rpb257aGVpZ2h0OjU0cHg7bWluLXdpZHRoOjE0NXB4O3BhZGRpbmc6MCAxNnB4fS5nZWFyQnV0dG9ue3dpZHRoOjU0cHg7bWluLXdpZHRoOjU0cHg7aGVpZ2h0OjU0cHg7Zm9udC1zaXplOjIwcHh9Ci5tYXBab25le3Bvc2l0aW9uOnJlbGF0aXZlO21pbi1oZWlnaHQ6MDtwYWRkaW5nOjAgOHB4IDAgMH0ubWFwRnJhbWV7cG9zaXRpb246YWJzb2x1dGU7aW5zZXQ6MCA4cHggMCAwO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjE4KTtib3JkZXItcmFkaXVzOjE4cHg7b3ZlcmZsb3c6aGlkZGVuO2JveC1zaGFkb3c6dmFyKC0tc2hhZG93KTtiYWNrZ3JvdW5kOiM5Y2I2YmV9Lm1hcENhbnZhc3twb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowfS5tYXBTaGFkZXtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowO3BvaW50ZXItZXZlbnRzOm5vbmU7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoMSw3LDEzLC4wNCkscmdiYSgxLDcsMTMsLjAzKSl9Lm1hcFRvb2xze3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6MTdweDt0b3A6MThweDt6LWluZGV4OjQ7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6OXB4fS5tYXBUb29se3dpZHRoOjQ3cHg7aGVpZ2h0OjQ3cHg7ZGlzcGxheTpncmlkO3BsYWNlLWl0ZW1zOmNlbnRlcjtib3JkZXItcmFkaXVzOjEzcHg7YmFja2dyb3VuZDpyZ2JhKDcsMTksMzEsLjkyKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjksMTE5LDE1NCwuNDIpO2JveC1zaGFkb3c6MCAxMnB4IDI4cHggcmdiYSgwLDAsMCwuMjgpO2NvbG9yOiNlN2Y3ZmZ9Lm1hcFRvb2wuYWN0aXZle2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMGQ5YmMzLCMwMGQ0ZWUpO2JvcmRlci1jb2xvcjojNWFmM2ZmfS5tYXBab29tR3JvdXB7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjttYXJnaW4tdG9wOjRweH0ubWFwWm9vbUdyb3VwIC5tYXBUb29se2JvcmRlci1yYWRpdXM6MH0ubWFwWm9vbUdyb3VwIC5tYXBUb29sOmZpcnN0LWNoaWxke2JvcmRlci1yYWRpdXM6MTNweCAxM3B4IDAgMH0ubWFwWm9vbUdyb3VwIC5tYXBUb29sOmxhc3QtY2hpbGR7Ym9yZGVyLXJhZGl1czowIDAgMTNweCAxM3B4O2JvcmRlci10b3A6MH0uZmlsdGVyQ2hpcHtwb3NpdGlvbjphYnNvbHV0ZTtyaWdodDoyMHB4O3RvcDoyMHB4O3otaW5kZXg6NTtkaXNwbGF5Om5vbmU7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMHB4O3BhZGRpbmc6MTBweCAxMXB4IDEwcHggMTRweDtib3JkZXItcmFkaXVzOjE0cHg7YmFja2dyb3VuZDpyZ2JhKDUsMTYsMjcsLjk0KTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzMsMTI1LDE2MSwuNDIpO2JveC1zaGFkb3c6MCAxNXB4IDM2cHggcmdiYSgwLDAsMCwuMzIpO2ZvbnQtc2l6ZToxMnB4fS5maWx0ZXJDaGlwLnNob3d7ZGlzcGxheTpmbGV4fS5maWx0ZXJDaGlwIGJ1dHRvbnt3aWR0aDozMHB4O2hlaWdodDozMHB4O3BhZGRpbmc6MH0KLnBob3RvTWFya2Vye3Bvc2l0aW9uOnJlbGF0aXZlO3dpZHRoOjU0cHg7aGVpZ2h0OjU0cHg7Ym9yZGVyLXJhZGl1czo1MCU7cGFkZGluZzozcHg7YmFja2dyb3VuZDojZWRmYWZmO2JvcmRlcjozcHggc29saWQgdmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMCAycHggcmdiYSgyNTUsMjU1LDI1NSwuNTUpLDAgMCAyMnB4IHJnYmEoMCwyMTYsMjU1LC42NSk7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTVzIGVhc2V9LnBob3RvTWFya2VyOmhvdmVyLC5waG90b01hcmtlci5hY3RpdmV7dHJhbnNmb3JtOnNjYWxlKDEuMTEpO2JvcmRlci1jb2xvcjp3aGl0ZTtib3gtc2hhZG93OjAgMCAwIDNweCB2YXIoLS1jeWFuKSwwIDAgMjhweCByZ2JhKDAsMjE2LDI1NSwuODUpfS5waG90b01hcmtlciBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmJsb2NrO29iamVjdC1maXQ6Y292ZXI7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDojMTczMTQ5fS5waG90b01hcmtlciAuZmFsbGJhY2t7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlci1yYWRpdXM6NTAlO2JhY2tncm91bmQ6cmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCAzMCUgMzAlLCMzZjgxOWEsIzBhMjYzOSk7Zm9udC13ZWlnaHQ6OTUwfS5tYXJrZXJCYWRnZXtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjUwJTt0b3A6LTE2cHg7dHJhbnNmb3JtOnRyYW5zbGF0ZVgoLTUwJSk7bWluLXdpZHRoOjI4cHg7aGVpZ2h0OjI4cHg7cGFkZGluZzowIDZweDtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlci1yYWRpdXM6OTk5cHg7YmFja2dyb3VuZDojMDcxMzFmO2NvbG9yOiNmZmY7Ym9yZGVyOjJweCBzb2xpZCByZ2JhKDI1NSwyNTUsMjU1LC43Mik7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwO2JveC1zaGFkb3c6MCA1cHggMTVweCByZ2JhKDAsMCwwLC40NSl9Ci5tYXBsaWJyZWdsLXBvcHVwLWNvbnRlbnR7cGFkZGluZzowIWltcG9ydGFudDtiYWNrZ3JvdW5kOnRyYW5zcGFyZW50IWltcG9ydGFudDtib3JkZXItcmFkaXVzOjE4cHghaW1wb3J0YW50O2JveC1zaGFkb3c6bm9uZSFpbXBvcnRhbnR9Lm1hcGxpYnJlZ2wtcG9wdXAtdGlwe2JvcmRlci10b3AtY29sb3I6IzA3MTMxZiFpbXBvcnRhbnR9Lm1hcGxpYnJlZ2wtcG9wdXAtY2xvc2UtYnV0dG9ue3otaW5kZXg6NDtyaWdodDo4cHghaW1wb3J0YW50O3RvcDo4cHghaW1wb3J0YW50O3dpZHRoOjI4cHg7aGVpZ2h0OjI4cHg7Ym9yZGVyLXJhZGl1czo1MCUhaW1wb3J0YW50O2JhY2tncm91bmQ6cmdiYSg4LDIwLDMzLC44MikhaW1wb3J0YW50O2NvbG9yOndoaXRlIWltcG9ydGFudDtmb250LXNpemU6MThweCFpbXBvcnRhbnQ7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDI1NSwyNTUsMjU1LC4yMikhaW1wb3J0YW50fS5zdG9wUG9wdXB7d2lkdGg6MzMwcHg7Ym9yZGVyLXJhZGl1czoxOHB4O292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOiMwNzEzMWY7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuNDIpO2JveC1zaGFkb3c6MCAwIDQwcHggcmdiYSgwLDIxNiwyNTUsLjI1KSwwIDI1cHggNjVweCByZ2JhKDAsMCwwLC40OCl9LnN0b3BQb3B1cEltYWdle2hlaWdodDoxODVweDtiYWNrZ3JvdW5kOiMxMDJhNDB9LnN0b3BQb3B1cEltYWdlIGltZ3t3aWR0aDoxMDAlO2hlaWdodDoxMDAlO2Rpc3BsYXk6YmxvY2s7b2JqZWN0LWZpdDpjb3Zlcn0uc3RvcFBvcHVwQm9keXtwYWRkaW5nOjEzcHggMTVweCAxNXB4fS5wb3B1cEtpY2tlcntkaXNwbGF5OmlubGluZS1mbGV4O3BhZGRpbmc6NXB4IDhweDtib3JkZXItcmFkaXVzOjhweDtiYWNrZ3JvdW5kOnJnYmEoMCwyMTYsMjU1LC4xNSk7Y29sb3I6dmFyKC0tY3lhbik7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6OTAwfS5wb3B1cFRpdGxle21hcmdpbi10b3A6OXB4O2ZvbnQtc2l6ZToxOXB4O2ZvbnQtd2VpZ2h0Ojk1MH0ucG9wdXBNZXRhe21hcmdpbi10b3A6NnB4O2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTJweH0ucG9wdXBCdXR0b25ze2Rpc3BsYXk6ZmxleDtnYXA6OHB4O21hcmdpbi10b3A6MTJweH0ucG9wdXBCdXR0b25zIGJ1dHRvbntoZWlnaHQ6NDBweDtmbGV4OjE7Zm9udC1zaXplOjEycHh9LnBvcHVwQnV0dG9ucyAuZGFuZ2Vye2ZsZXg6MCAwIDQycHg7Y29sb3I6dmFyKC0tcmVkKX0KLm1lZGlhU3RyaXB7bWluLXdpZHRoOjA7cGFkZGluZzoxM3B4IDE3cHggMTVweDtib3JkZXItdG9wOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMTIpO2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDE4MGRlZyxyZ2JhKDQsMTIsMjAsLjcyKSxyZ2JhKDMsOSwxNiwuOTUpKX0ubWVkaWFIZWFkZXJ7aGVpZ2h0OjMxcHg7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTFweH0ubWVkaWFUaXRsZXtmb250LXNpemU6MTRweDtmb250LXdlaWdodDo5NTB9Lm1lZGlhQ291bnR7Zm9udC1zaXplOjEycHg7Y29sb3I6dmFyKC0tbXV0ZWQpfS5tZWRpYUhlYWRlclNwYWNlcntmbGV4OjF9LnRpbnlCdXR0b257d2lkdGg6MzFweDtoZWlnaHQ6MzFweDtwYWRkaW5nOjA7Ym9yZGVyLXJhZGl1czoxMHB4fS5nYWxsZXJ5e2hlaWdodDoxNjRweDtkaXNwbGF5OmZsZXg7Z2FwOjEwcHg7b3ZlcmZsb3cteDphdXRvO292ZXJmbG93LXk6aGlkZGVuO3BhZGRpbmc6OHB4IDFweCA0cHg7c2Nyb2xsYmFyLXdpZHRoOnRoaW59Lm1lZGlhVGlsZXtwb3NpdGlvbjpyZWxhdGl2ZTtmbGV4OjAgMCAyMThweDtoZWlnaHQ6MTQ1cHg7Ym9yZGVyLXJhZGl1czoxM3B4O292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOiMxMDIyMzU7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDcxLDEyMywxNjAsLjM1KTtjdXJzb3I6cG9pbnRlcjt0cmFuc2l0aW9uOi4xNnMgZWFzZX0ubWVkaWFUaWxlOmhvdmVyLC5tZWRpYVRpbGUuYWN0aXZle2JvcmRlci1jb2xvcjp2YXIoLS1jeWFuKTtib3gtc2hhZG93OjAgMCAyMXB4IHJnYmEoMCwyMTYsMjU1LC4yNCk7dHJhbnNmb3JtOnRyYW5zbGF0ZVkoLTJweCl9Lm1lZGlhVGlsZSBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtvYmplY3QtZml0OmNvdmVyO2Rpc3BsYXk6YmxvY2t9Lm1lZGlhVGlsZU5hbWV7cG9zaXRpb246YWJzb2x1dGU7bGVmdDowO3JpZ2h0OjA7Ym90dG9tOjA7cGFkZGluZzoyNXB4IDEwcHggOXB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KHRyYW5zcGFyZW50LHJnYmEoMSw2LDExLC45KSk7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6ODUwO3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30KLnJpZ2h0UmFpbHttaW4td2lkdGg6MDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSg0LDEyLDIxLC45NykscmdiYSgyLDgsMTUsLjk5KSk7Ym9yZGVyLWxlZnQ6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4xNCk7cGFkZGluZzoxNXB4IDE1cHggMTdweDtkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO292ZXJmbG93OmhpZGRlbn0ucmlnaHRUb3B7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtoZWlnaHQ6NDBweH0ucmlnaHRUaXRsZXtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5NTA7dGV4dC10cmFuc2Zvcm06dXBwZXJjYXNlO2xldHRlci1zcGFjaW5nOi4wNGVtfS5yaWdodENvdW50e2NvbG9yOnZhcigtLW11dGVkKTttYXJnaW4tbGVmdDo1cHh9LnJpZ2h0U2VhcmNoe21hcmdpbi1sZWZ0OmF1dG87d2lkdGg6MzVweDtoZWlnaHQ6MzVweDtwYWRkaW5nOjA7YmFja2dyb3VuZDp0cmFuc3BhcmVudDtib3JkZXI6MDtib3gtc2hhZG93Om5vbmV9LnN0b3BTZWFyY2hXcmFwe2Rpc3BsYXk6bm9uZTttYXJnaW4tYm90dG9tOjEwcHh9LnN0b3BTZWFyY2hXcmFwLnNob3d7ZGlzcGxheTpibG9ja30uc3RvcExpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6OXB4O292ZXJmbG93OmF1dG87bWluLWhlaWdodDoyNTBweDtmbGV4OjEgMSAwO3BhZGRpbmc6MnB4IDRweCAxMnB4IDB9LnN0b3BDYXJke2ZsZXg6MCAwIGF1dG87bWluLWhlaWdodDo3NnB4O2JvcmRlci1yYWRpdXM6MTNweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgxMywyOCw0NCwuOTYpLHJnYmEoOCwyMCwzMywuOTYpKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjEsMTA4LDE0MywuMzQpO292ZXJmbG93OmhpZGRlbjt0cmFuc2l0aW9uOi4xNXMgZWFzZX0uc3RvcENhcmQ6aG92ZXIsLnN0b3BDYXJkLmFjdGl2ZXtib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzppbnNldCA0cHggMCAwIHZhcigtLWN5YW4pLDAgMCAxOHB4IHJnYmEoMCwyMTYsMjU1LC4xMyl9LnN0b3BTdW1tYXJ5e21pbi1oZWlnaHQ6NzZweDtwYWRkaW5nOjEycHggMTJweDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjMxcHggbWlubWF4KDAsMWZyKSAyMnB4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTBweDtjdXJzb3I6cG9pbnRlcn0uc3RvcE51bWJlcnt3aWR0aDoyOXB4O2hlaWdodDoyOXB4O2JvcmRlci1yYWRpdXM6OTk5cHg7ZGlzcGxheTpncmlkO3BsYWNlLWl0ZW1zOmNlbnRlcjtiYWNrZ3JvdW5kOnJnYmEoMCwyMTYsMjU1LC4xMik7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzUpO2ZvbnQtc2l6ZToxMnB4O2ZvbnQtd2VpZ2h0Ojk1MDt0ZXh0LWFsaWduOmNlbnRlcn0uc3RvcE5hbWV7Zm9udC1zaXplOjEzcHg7Zm9udC13ZWlnaHQ6OTUwO3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30uc3RvcE1ldGF7bWFyZ2luLXRvcDo1cHg7Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxMC41cHg7bGluZS1oZWlnaHQ6MS4zNX0uc3RvcENoZXZyb257Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxOHB4O3RyYW5zaXRpb246LjE1c30uc3RvcENhcmQub3BlbiAuc3RvcENoZXZyb257dHJhbnNmb3JtOnJvdGF0ZSg5MGRlZyl9LnN0b3BDb250cm9sc3tkaXNwbGF5Om5vbmU7cGFkZGluZzowIDEycHggMTJweCA1M3B4O2dhcDo2cHg7ZmxleC13cmFwOndyYXB9LnN0b3BDYXJkLm9wZW4gLnN0b3BDb250cm9sc3tkaXNwbGF5OmZsZXh9LnN0b3BDb250cm9scyBidXR0b257aGVpZ2h0OjMycHg7cGFkZGluZzowIDlweDtmb250LXNpemU6MTBweH0uYWRkU3RvcEJ1dHRvbntmbGV4OjAgMCBhdXRvO2hlaWdodDo0MnB4O3dpZHRoOjEwMCU7bWFyZ2luOjRweCAwIDEycHh9LmFzc2V0QnViYmxle3dpZHRoOjUycHg7aGVpZ2h0OjUycHg7Ym9yZGVyLXJhZGl1czo1MCU7b3ZlcmZsb3c6aGlkZGVuO2JvcmRlcjozcHggc29saWQgIzAwZDhmZjtiYWNrZ3JvdW5kOiMwNjExMWQ7Ym94LXNoYWRvdzowIDAgMCAzcHggcmdiYSg0LDE3LDI4LC45MiksMCAwIDIycHggcmdiYSgwLDIxNiwyNTUsLjUyKTtjdXJzb3I6cG9pbnRlcjt0cmFuc2l0aW9uOi4xNnN9LmFzc2V0QnViYmxlOmhvdmVyLC5hc3NldEJ1YmJsZS5hY3RpdmV7dHJhbnNmb3JtOnNjYWxlKDEuMTIpO2JvcmRlci1jb2xvcjp3aGl0ZTt6LWluZGV4OjE1fS5hc3NldEJ1YmJsZSBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmJsb2NrO29iamVjdC1maXQ6Y292ZXJ9LmFzc2V0QnViYmxlIC5hc3NldERvdHt3aWR0aDoxMDAlO2hlaWdodDoxMDAlO2Rpc3BsYXk6Z3JpZDtwbGFjZS1pdGVtczpjZW50ZXI7Y29sb3I6dmFyKC0tY3lhbik7Zm9udC1zaXplOjE5cHh9Ci5leHBvcnRCb3h7ZmxleDowIDAgYXV0bztib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjIsMTExLDE0OCwuMzApO2JvcmRlci1yYWRpdXM6MTRweDtiYWNrZ3JvdW5kOnJnYmEoOCwxOSwzMSwuOTApO292ZXJmbG93OmhpZGRlbn0uZXhwb3J0SGVhZGVye2hlaWdodDo0OHB4O3BhZGRpbmc6MCAxM3B4O2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OnNwYWNlLWJldHdlZW47Zm9udC1zaXplOjEzcHg7Zm9udC13ZWlnaHQ6OTUwO2N1cnNvcjpwb2ludGVyfS5leHBvcnRCb2R5e3BhZGRpbmc6MCAxMnB4IDEycHh9LmV4cG9ydEJveC5jb2xsYXBzZWQgLmV4cG9ydEJvZHl7ZGlzcGxheTpub25lfS5leHBvcnRUYWJze2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLWNvbHVtbnM6MWZyIDFmciAxZnI7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDYzLDExMywxNTAsLjMzKTtib3JkZXItcmFkaXVzOjEwcHg7b3ZlcmZsb3c6aGlkZGVuO21hcmdpbjo3cHggMCAxMnB4fS5leHBvcnRUYWJzIGJ1dHRvbntib3JkZXI6MDtib3JkZXItcmFkaXVzOjA7aGVpZ2h0OjM2cHg7YmFja2dyb3VuZDojMDcxMzFmO2ZvbnQtc2l6ZToxMHB4fS5leHBvcnRUYWJzIGJ1dHRvbi5hY3RpdmV7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCMwODc5YzMsIzAwYTljOSk7Ym94LXNoYWRvdzpub25lfS5maWVsZExhYmVse2Rpc3BsYXk6YmxvY2s7Zm9udC1zaXplOjEwcHg7Y29sb3I6dmFyKC0tbXV0ZWQpO21hcmdpbjoxMHB4IDAgNXB4fS5hdWRpb1Jvd3tkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuO2NvbG9yOnZhcigtLXNvZnQpO2ZvbnQtc2l6ZToxMXB4fS5zd2l0Y2h7d2lkdGg6MzlweDtoZWlnaHQ6MjFweDtib3JkZXItcmFkaXVzOjk5OXB4O2JhY2tncm91bmQ6IzIwMzc0YTtib3JkZXI6MXB4IHNvbGlkICMzNTUzNmE7cG9zaXRpb246cmVsYXRpdmU7Y3Vyc29yOnBvaW50ZXJ9LnN3aXRjaDphZnRlcntjb250ZW50OiIiO3Bvc2l0aW9uOmFic29sdXRlO3RvcDoycHg7bGVmdDoycHg7d2lkdGg6MTVweDtoZWlnaHQ6MTVweDtib3JkZXItcmFkaXVzOjUwJTtiYWNrZ3JvdW5kOiNkY2VhZjQ7dHJhbnNpdGlvbjouMTZzfS5zd2l0Y2gub257YmFja2dyb3VuZDojMDBhOWNlO2JvcmRlci1jb2xvcjojMjBlMWZmfS5zd2l0Y2gub246YWZ0ZXJ7bGVmdDoyMHB4fS5hdWRpb0lucHV0e2Rpc3BsYXk6bm9uZX0ucmVuZGVyQnV0dG9ue3dpZHRoOjEwMCU7aGVpZ2h0OjU1cHg7bWFyZ2luLXRvcDoxMXB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMDg3ZGEzLCMxMWJhY2UpO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuNzUpO2ZvbnQtc2l6ZToxNHB4fS5yZW5kZXJCdXR0b24gc3BhbntkaXNwbGF5OmJsb2NrO2ZvbnQtc2l6ZToxMHB4O2ZvbnQtd2VpZ2h0OjY1MDtvcGFjaXR5Oi44NTttYXJnaW4tdG9wOjJweH0KLm1vZGFse3Bvc2l0aW9uOmZpeGVkO2luc2V0OjA7ei1pbmRleDoxMDAwO2Rpc3BsYXk6bm9uZTthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OmNlbnRlcjtwYWRkaW5nOjI0cHg7YmFja2dyb3VuZDpyZ2JhKDAsNCw5LC43NSk7YmFja2Ryb3AtZmlsdGVyOmJsdXIoN3B4KX0ubW9kYWwuc2hvd3tkaXNwbGF5OmZsZXh9Lm1vZGFsQ2FyZHt3aWR0aDptaW4oNzIwcHgsOTR2dyk7bWF4LWhlaWdodDo5MHZoO292ZXJmbG93OmF1dG87cGFkZGluZzoyMXB4O2JvcmRlci1yYWRpdXM6MTlweDtiYWNrZ3JvdW5kOiMwNzEzMWY7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzUpO2JveC1zaGFkb3c6MCAwIDYwcHggcmdiYSgwLDIxNiwyNTUsLjE4KSwwIDM1cHggMTAwcHggcmdiYSgwLDAsMCwuNTUpfS5tb2RhbFRpdGxle2ZvbnQtc2l6ZToyMXB4O2ZvbnQtd2VpZ2h0Ojk1MDttYXJnaW4tYm90dG9tOjE1cHh9LmZvcm1Hcmlke2Rpc3BsYXk6Z3JpZDtnYXA6MTFweH0udHdvQ29se2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLWNvbHVtbnM6MWZyIDFmcjtnYXA6MTFweH0ubW9kYWxBY3Rpb25ze2Rpc3BsYXk6ZmxleDtqdXN0aWZ5LWNvbnRlbnQ6ZmxleC1lbmQ7Z2FwOjlweDttYXJnaW4tdG9wOjZweH0ubW9kYWxBY3Rpb25zIGJ1dHRvbntoZWlnaHQ6NDJweDtwYWRkaW5nOjAgMTZweH0ucHJpbWFyeXtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxMzVkZWcsIzA3NWRiNCwjMDBhZWNiKTtib3JkZXItY29sb3I6dmFyKC0tY3lhbil9Ci50b2FzdHtwb3NpdGlvbjpmaXhlZDtsZWZ0OjMwNXB4O2JvdHRvbToxOHB4O3otaW5kZXg6MzAwMDtkaXNwbGF5Om5vbmU7cGFkZGluZzoxMXB4IDE0cHg7Ym9yZGVyLXJhZGl1czoxMnB4O2JhY2tncm91bmQ6cmdiYSg2LDE5LDMxLC45NSk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzIpO2JveC1zaGFkb3c6MCAxNXB4IDQwcHggcmdiYSgwLDAsMCwuMzUpO2ZvbnQtc2l6ZToxMnB4fS50b2FzdC5zaG93e2Rpc3BsYXk6YmxvY2t9Ci5wcmVzZW50T3ZlcmxheXtwb3NpdGlvbjpmaXhlZDtpbnNldDowO3otaW5kZXg6MjIwMDtkaXNwbGF5Om5vbmU7YmFja2dyb3VuZDojMDIwNzEwfS5wcmVzZW50T3ZlcmxheS5zaG93e2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLXJvd3M6NzJweCBtaW5tYXgoMCwxZnIpIDE3MHB4fS5wcmVzZW50SGVhZGVye2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjEzcHg7cGFkZGluZzoxMHB4IDE4cHg7Ym9yZGVyLWJvdHRvbToxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjE2KTtiYWNrZ3JvdW5kOnJnYmEoMywxMCwxOCwuOTApfS5wcmVzZW50SGVhZGVyVGl0bGV7Zm9udC1zaXplOjIwcHg7Zm9udC13ZWlnaHQ6OTUwfS5wcmVzZW50SGVhZGVyTWV0YXtjb2xvcjp2YXIoLS1tdXRlZCk7Zm9udC1zaXplOjExcHg7bWFyZ2luLXRvcDozcHh9LnByZXNlbnRIZWFkZXJTcGFjZXJ7ZmxleDoxfS5wcmVzZW50TWFpbntwb3NpdGlvbjpyZWxhdGl2ZTttaW4taGVpZ2h0OjB9LnByZXNlbnRNYXB7cG9zaXRpb246YWJzb2x1dGU7aW5zZXQ6MH0ucHJlc2VudFN0b3BSYWlse3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6MThweDt0b3A6MThweDtib3R0b206MThweDt3aWR0aDoyNDBweDt6LWluZGV4OjQ7cGFkZGluZzoxMnB4O2JvcmRlci1yYWRpdXM6MTZweDtiYWNrZ3JvdW5kOnJnYmEoNCwxNCwyNCwuODQpO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjI0KTtiYWNrZHJvcC1maWx0ZXI6Ymx1cigxNXB4KTtvdmVyZmxvdzphdXRvfS5wcmVzZW50U3RvcEl0ZW17cGFkZGluZzoxMHB4O2JvcmRlci1yYWRpdXM6MTBweDtjb2xvcjojYjRjOGQ4O2ZvbnQtc2l6ZToxMnB4O2N1cnNvcjpwb2ludGVyfS5wcmVzZW50U3RvcEl0ZW0uYWN0aXZle2JhY2tncm91bmQ6cmdiYSgwLDIxNiwyNTUsLjE0KTtjb2xvcjp3aGl0ZTtib3gtc2hhZG93Omluc2V0IDNweCAwIDAgdmFyKC0tY3lhbil9LnByZXNlbnRTdG9wQmFubmVye3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6NTAlO3RvcDoxOHB4O3RyYW5zZm9ybTp0cmFuc2xhdGVYKC01MCUpO3otaW5kZXg6NzttaW4td2lkdGg6NDIwcHg7bWF4LXdpZHRoOjcyMHB4O3BhZGRpbmc6MTRweCAyMHB4O2JvcmRlci1yYWRpdXM6MTdweDtiYWNrZ3JvdW5kOnJnYmEoNCwxNCwyNCwuODgpO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjMwKTtib3gtc2hhZG93OjAgMjJweCA1NXB4IHJnYmEoMCwwLDAsLjQyKSwwIDAgMzBweCByZ2JhKDAsMjE2LDI1NSwuMTIpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDE1cHgpO3RleHQtYWxpZ246Y2VudGVyfS5wcmVzZW50U3RvcEJhbm5lclRpdGxle2ZvbnQtc2l6ZToyNHB4O2ZvbnQtd2VpZ2h0Ojk1MH0ucHJlc2VudFN0b3BCYW5uZXJSYW5nZXttYXJnaW4tdG9wOjRweDtjb2xvcjojYjhjY2RhO2ZvbnQtc2l6ZToxMnB4fS5wcmVzZW50UGhvdG9DYXJke3Bvc2l0aW9uOmFic29sdXRlO3JpZ2h0OjIycHg7dG9wOjk2cHg7d2lkdGg6bWluKDQ4MHB4LDM4dncpO21heC1oZWlnaHQ6Y2FsYygxMDAlIC0gMTgwcHgpO3otaW5kZXg6ODtib3JkZXItcmFkaXVzOjE4cHg7b3ZlcmZsb3c6aGlkZGVuO2JhY2tncm91bmQ6cmdiYSg1LDE1LDI1LC45Nyk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzgpO2JveC1zaGFkb3c6MCAwIDQycHggcmdiYSgwLDIxNiwyNTUsLjIwKSwwIDI1cHggNjBweCByZ2JhKDAsMCwwLC41KTtkaXNwbGF5Om5vbmV9LnByZXNlbnRQaG90b0NhcmQuc2hvd3tkaXNwbGF5OmJsb2NrfS5wcmVzZW50UGhvdG9DYXJkIGltZ3t3aWR0aDoxMDAlO21heC1oZWlnaHQ6NTZ2aDtvYmplY3QtZml0OmNvbnRhaW47ZGlzcGxheTpibG9jaztiYWNrZ3JvdW5kOiMwMTA0MDl9LnByZXNlbnRQaG90b0JvZHl7cGFkZGluZzoxNHB4IDE2cHh9LnByZXNlbnRQaG90b1RpdGxle2ZvbnQtc2l6ZToxNnB4O2ZvbnQtd2VpZ2h0Ojk1MDt3aGl0ZS1zcGFjZTpub3dyYXA7b3ZlcmZsb3c6aGlkZGVuO3RleHQtb3ZlcmZsb3c6ZWxsaXBzaXN9LnByZXNlbnRQaG90b01ldGF7Y29sb3I6I2Q1ZTdmMTtmb250LXNpemU6MTNweDttYXJnaW4tdG9wOjZweDtsZXR0ZXItc3BhY2luZzouMDJlbX0ucHJlc2VudFBob3RvQ29vcmRze2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTFweDttYXJnaW4tdG9wOjdweDtsaW5lLWhlaWdodDoxLjV9LnByZXNlbnRQaG90b0FjdGlvbnN7ZGlzcGxheTpmbGV4O2dhcDo4cHg7bWFyZ2luLXRvcDoxMnB4fS5wcmVzZW50UGhvdG9BY3Rpb25zIGJ1dHRvbntoZWlnaHQ6MzhweDtwYWRkaW5nOjAgMTJweDtmb250LXNpemU6MTFweH0ucHJlc2VudFBob3RvQWN0aW9ucyAuZGFuZ2Vye21hcmdpbi1sZWZ0OmF1dG87Y29sb3I6I2ZmZGJlMTtib3JkZXItY29sb3I6cmdiYSgyNTUsNzcsMTAyLC41NSk7YmFja2dyb3VuZDpyZ2JhKDEwNSwyMCwzOCwuNzIpfS5wcmVzZW50SHVke3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6NTAlO2JvdHRvbToxOHB4O3RyYW5zZm9ybTp0cmFuc2xhdGVYKC01MCUpO3otaW5kZXg6NjtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDo4cHg7cGFkZGluZzo4cHg7Ym9yZGVyLXJhZGl1czoxNnB4O2JhY2tncm91bmQ6cmdiYSg0LDE0LDI0LC44Nik7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMjIpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDEycHgpfS5wcmVzZW50SHVkIGJ1dHRvbntoZWlnaHQ6NDJweDtwYWRkaW5nOjAgMTRweDtmb250LXNpemU6MTFweH0ucHJlc2VudEh1ZCAucGxheXttaW4td2lkdGg6MTEwcHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCM2MDNjZmYsIzAwYWRjYil9LnByZXNlbnRCYWNre3dpZHRoOjQ2cHg7aGVpZ2h0OjQ2cHg7Ym9yZGVyLXJhZGl1czoxNHB4O2ZvbnQtc2l6ZToyMXB4O3BhZGRpbmc6MH0ucHJlc2VudEhlYWRlckFjdGlvbntoZWlnaHQ6NDJweDtwYWRkaW5nOjAgMTNweDtmb250LXNpemU6MTFweH0uZm9jdXNQdWxzZXt3aWR0aDozNHB4O2hlaWdodDozNHB4O2JvcmRlci1yYWRpdXM6NTAlO2JvcmRlcjozcHggc29saWQgd2hpdGU7YmFja2dyb3VuZDpyZ2JhKDAsMjE2LDI1NSwuMjIpO2JveC1zaGFkb3c6MCAwIDAgN3B4IHJnYmEoMCwyMTYsMjU1LC4yMCksMCAwIDMwcHggcmdiYSgwLDIxNiwyNTUsLjk1KTtwb2ludGVyLWV2ZW50czpub25lO2FuaW1hdGlvbjpmb2N1c1B1bHNlIDEuOHMgZWFzZS1pbi1vdXQgaW5maW5pdGV9Lm1lZGlhVGlsZVJlbW92ZXtwb3NpdGlvbjphYnNvbHV0ZTtyaWdodDo3cHg7dG9wOjdweDt6LWluZGV4OjM7d2lkdGg6MzBweDtoZWlnaHQ6MzBweDtwYWRkaW5nOjA7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDpyZ2JhKDcsMTksMzEsLjg4KTtib3JkZXItY29sb3I6cmdiYSgyNTUsMjU1LDI1NSwuMjgpO2ZvbnQtc2l6ZToxNnB4O2NvbG9yOiNmZmRiZTF9Lm1lZGlhVGlsZVJlbW92ZTpob3Zlcntib3JkZXItY29sb3I6dmFyKC0tcmVkKTtib3gtc2hhZG93OjAgMCAxNnB4IHJnYmEoMjU1LDc3LDEwMiwuMzUpfUBrZXlmcmFtZXMgZm9jdXNQdWxzZXswJSwxMDAle3RyYW5zZm9ybTpzY2FsZSguOTIpO29wYWNpdHk6Ljc1fTUwJXt0cmFuc2Zvcm06c2NhbGUoMS4wOCk7b3BhY2l0eToxfX0ucHJlc2VudEZpbG1zdHJpcHtwYWRkaW5nOjEycHggMThweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcsIzA2MTExZCwjMDIwNzExKTtib3JkZXItdG9wOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMTQpO2Rpc3BsYXk6ZmxleDtnYXA6MTBweDtvdmVyZmxvdy14OmF1dG99LnByZXNlbnRUaHVtYntmbGV4OjAgMCAxOTBweDtoZWlnaHQ6MTQwcHg7Ym9yZGVyLXJhZGl1czoxM3B4O292ZXJmbG93OmhpZGRlbjtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjksMTIxLDE1OCwuMzQpO2N1cnNvcjpwb2ludGVyO3Bvc2l0aW9uOnJlbGF0aXZlfS5wcmVzZW50VGh1bWIuYWN0aXZle2JvcmRlci1jb2xvcjp2YXIoLS1jeWFuKTtib3gtc2hhZG93OjAgMCAyMXB4IHJnYmEoMCwyMTYsMjU1LC4yOCl9LnByZXNlbnRUaHVtYiBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmJsb2NrO29iamVjdC1maXQ6Y292ZXJ9LnByZXNlbnRUaHVtYkxhYmVse3Bvc2l0aW9uOmFic29sdXRlO2luc2V0OmF1dG8gMCAwO3BhZGRpbmc6MjRweCA4cHggN3B4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KHRyYW5zcGFyZW50LHJnYmEoMCwwLDAsLjg1KSk7Zm9udC1zaXplOjEwcHg7Zm9udC13ZWlnaHQ6ODAwfQpAbWVkaWEobWF4LXdpZHRoOjEzMDBweCl7LmFwcFNoZWxse2dyaWQtdGVtcGxhdGUtY29sdW1uczoyNTBweCBtaW5tYXgoNTgwcHgsMWZyKSAzMjBweH0ubGVmdFJhaWx7cGFkZGluZy1sZWZ0OjEzcHg7cGFkZGluZy1yaWdodDoxM3B4fS53b3JkbWFya3tmb250LXNpemU6MjdweH0ucHJlc2VudEJ1dHRvbnttaW4td2lkdGg6MjIwcHh9LnRpdGxlQXJlYXttaW4td2lkdGg6MjQwcHh9LnRvcEFjdGlvbnttaW4td2lkdGg6MTEwcHh9Lm1lZGlhVGlsZXtmbGV4LWJhc2lzOjE4NXB4fX0KPC9zdHlsZT4KPC9oZWFkPgo8Ym9keT4KPGRpdiBjbGFzcz0iYXBwU2hlbGwiPgogIDxhc2lkZSBjbGFzcz0ibGVmdFJhaWwiPgogICAgPGRpdiBjbGFzcz0iYnJhbmRMaW5lIj4KICAgICAgPGRpdiBjbGFzcz0ibG9nb0Zsb3dlciI+PHNwYW4gY2xhc3M9InBldGFsIHAxIj48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHAyIj48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHAzIj48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHA0Ij48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHA1Ij48L3NwYW4+PHNwYW4gY2xhc3M9InBldGFsIHA2Ij48L3NwYW4+PC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9IndvcmRtYXJrIj50cmlwcHk8L2Rpdj48ZGl2IGNsYXNzPSJ2ZXJzaW9uIj52MTAuMi40PC9kaXY+CiAgICA8L2Rpdj4KICAgIDxidXR0b24gaWQ9Im5ld0ltbWljaEJ1dHRvbiIgY2xhc3M9InNpZGVQcmltYXJ5Ij7vvIsmbmJzcDsgTmV3IEltbWljaCBKb3VybmV5PC9idXR0b24+CiAgICA8YnV0dG9uIGlkPSJ1cGxvYWRCdXR0b24iIGNsYXNzPSJzaWRlU2Vjb25kYXJ5Ij7ih6cmbmJzcDsgVXBsb2FkIE1lZGlhPC9idXR0b24+CiAgICA8ZGl2IGNsYXNzPSJzZWN0aW9uTGFiZWwiPjxzcGFuPlByb2plY3RzPC9zcGFuPjxidXR0b24gaWQ9InByb2plY3RTZWFyY2hCdXR0b24iIGNsYXNzPSJwcm9qZWN0TWVudSI+4oyVPC9idXR0b24+PC9kaXY+CiAgICA8aW5wdXQgaWQ9InByb2plY3RTZWFyY2giIGNsYXNzPSJoaWRkZW4iIHBsYWNlaG9sZGVyPSJTZWFyY2ggcHJvamVjdHPigKYiPgogICAgPGRpdiBpZD0icHJvamVjdExpc3QiIGNsYXNzPSJwcm9qZWN0TGlzdCI+PC9kaXY+CiAgICA8ZGl2IGNsYXNzPSJsZWZ0Rm9vdGVyIj5QbGFuLCBvcmdhbml6ZSwgYW5kIHJlbGl2ZSB5b3VyIGFkdmVudHVyZXMgb24gdGhlIG1hcC4KICAgICAgPGEgY2xhc3M9ImZvb3RlckxpbmsiIGhyZWY9IiMiPuKWoyZuYnNwOyBEb2N1bWVudGF0aW9uPC9hPjxhIGNsYXNzPSJmb290ZXJMaW5rIiBocmVmPSIjIj7il44mbmJzcDsgQ2hhbmdlbG9nPC9hPgogICAgPC9kaXY+CiAgPC9hc2lkZT4KCiAgPG1haW4gY2xhc3M9IndvcmtzcGFjZSI+CiAgICA8aGVhZGVyIGNsYXNzPSJ0b3BCYXIiPgogICAgICA8ZGl2IGNsYXNzPSJ0aXRsZUFyZWEiPjxkaXYgY2xhc3M9ImpvdXJuZXlUaXRsZVJvdyI+PGRpdiBpZD0iam91cm5leVRpdGxlIiBjbGFzcz0iam91cm5leVRpdGxlIj5ObyBqb3VybmV5IHNlbGVjdGVkPC9kaXY+PGJ1dHRvbiBpZD0icmVuYW1lUHJvamVjdEJ1dHRvbiIgY2xhc3M9ImVkaXRUaXRsZSI+4pyOPC9idXR0b24+PC9kaXY+PGRpdiBpZD0iam91cm5leU1ldGEiIGNsYXNzPSJqb3VybmV5TWV0YSI+TG9hZCBvciBjcmVhdGUgYSBqb3VybmV5PC9kaXY+PC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9InRvcFNwYWNlciI+PC9kaXY+CiAgICAgIDxidXR0b24gaWQ9InByZXNlbnRCdXR0b24iIGNsYXNzPSJwcmVzZW50QnV0dG9uIj7ilrYmbmJzcDsgUHJlc2VudCBKb3VybmV5PHNwYW4+SW1tZXJzaXZlIHJvdXRlIHBsYXliYWNrPC9zcGFuPjwvYnV0dG9uPgogICAgICA8YnV0dG9uIGlkPSJleHBvcnRKdW1wQnV0dG9uIiBjbGFzcz0idG9wQWN0aW9uIj7ilqMmbmJzcDsgRXhwb3J0PGJyPjxzcGFuIGNsYXNzPSJzbWFsbCI+UmVuZGVyLCBHUFgsIGFuZCBtb3JlJm5ic3A74oyEPC9zcGFuPjwvYnV0dG9uPgogICAgICA8YnV0dG9uIGlkPSJzZXR0aW5nc0J1dHRvbiIgY2xhc3M9ImdlYXJCdXR0b24iPuKamTwvYnV0dG9uPgogICAgICA8YnV0dG9uIGlkPSJhY2NvdW50QnV0dG9uIiBjbGFzcz0idG9wQWN0aW9uIj7imZkmbmJzcDsgQWNjb3VudCZuYnNwO+KMhDwvYnV0dG9uPgogICAgPC9oZWFkZXI+CgogICAgPHNlY3Rpb24gY2xhc3M9Im1hcFpvbmUiPjxkaXYgY2xhc3M9Im1hcEZyYW1lIj48ZGl2IGlkPSJtYXAiIGNsYXNzPSJtYXBDYW52YXMiPjwvZGl2PjxkaXYgY2xhc3M9Im1hcFNoYWRlIj48L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0ibWFwVG9vbHMiPgogICAgICAgIDxidXR0b24gaWQ9ImxvY2F0ZUJ1dHRvbiIgY2xhc3M9Im1hcFRvb2wiPuKepDwvYnV0dG9uPjxidXR0b24gaWQ9ImxpZ2h0TWFwQnV0dG9uIiBjbGFzcz0ibWFwVG9vbCBhY3RpdmUiPuKXqzwvYnV0dG9uPjxidXR0b24gaWQ9ImRhcmtNYXBCdXR0b24iIGNsYXNzPSJtYXBUb29sIj7il5A8L2J1dHRvbj48YnV0dG9uIGlkPSJzYXRlbGxpdGVNYXBCdXR0b24iIGNsYXNzPSJtYXBUb29sIj7ilqc8L2J1dHRvbj4KICAgICAgICA8ZGl2IGNsYXNzPSJtYXBab29tR3JvdXAiPjxidXR0b24gaWQ9Inpvb21JbkJ1dHRvbiIgY2xhc3M9Im1hcFRvb2wiPu+8izwvYnV0dG9uPjxidXR0b24gaWQ9Inpvb21PdXRCdXR0b24iIGNsYXNzPSJtYXBUb29sIj7iiJI8L2J1dHRvbj48L2Rpdj4KICAgICAgPC9kaXY+CiAgICAgIDxkaXYgaWQ9ImZpbHRlckNoaXAiIGNsYXNzPSJmaWx0ZXJDaGlwIj48c3Bhbj7ilr4mbmJzcDsgPGIgaWQ9ImZpbHRlckNoaXBUZXh0Ij5GaWx0ZXI6IEFsbCBTdG9wczwvYj48L3NwYW4+PGJ1dHRvbiBpZD0iY2xlYXJGaWx0ZXJCdXR0b24iPsOXPC9idXR0b24+PC9kaXY+CiAgICA8L2Rpdj48L3NlY3Rpb24+CgogICAgPHNlY3Rpb24gY2xhc3M9Im1lZGlhU3RyaXAiPjxkaXYgY2xhc3M9Im1lZGlhSGVhZGVyIj48ZGl2IGlkPSJtZWRpYVRpdGxlIiBjbGFzcz0ibWVkaWFUaXRsZSI+TWVkaWE8L2Rpdj48ZGl2IGlkPSJtZWRpYUNvdW50IiBjbGFzcz0ibWVkaWFDb3VudCI+PC9kaXY+PGRpdiBjbGFzcz0ibWVkaWFIZWFkZXJTcGFjZXIiPjwvZGl2PjxidXR0b24gY2xhc3M9InRpbnlCdXR0b24iPuKWpjwvYnV0dG9uPjxidXR0b24gY2xhc3M9InRpbnlCdXR0b24iPuKYtzwvYnV0dG9uPjwvZGl2PjxkaXYgaWQ9ImdhbGxlcnkiIGNsYXNzPSJnYWxsZXJ5Ij48L2Rpdj48L3NlY3Rpb24+CiAgPC9tYWluPgoKICA8YXNpZGUgY2xhc3M9InJpZ2h0UmFpbCI+CiAgICA8ZGl2IGNsYXNzPSJyaWdodFRvcCI+PGRpdiBjbGFzcz0icmlnaHRUaXRsZSI+U3RvcHMgPHNwYW4gaWQ9InN0b3BDb3VudCIgY2xhc3M9InJpZ2h0Q291bnQiPigwKTwvc3Bhbj48L2Rpdj48YnV0dG9uIGlkPSJzdG9wU2VhcmNoQnV0dG9uIiBjbGFzcz0icmlnaHRTZWFyY2giPuKMlTwvYnV0dG9uPjwvZGl2PgogICAgPGRpdiBpZD0ic3RvcFNlYXJjaFdyYXAiIGNsYXNzPSJzdG9wU2VhcmNoV3JhcCI+PGlucHV0IGlkPSJzdG9wU2VhcmNoIiBwbGFjZWhvbGRlcj0iU2VhcmNoIHN0b3Bz4oCmIj48L2Rpdj4KICAgIDxkaXYgaWQ9InN0b3BMaXN0IiBjbGFzcz0ic3RvcExpc3QiPjwvZGl2PgogICAgPGJ1dHRvbiBpZD0iYWRkU3RvcEJ1dHRvbiIgY2xhc3M9ImFkZFN0b3BCdXR0b24iPu+8iyZuYnNwOyBBZGQgU3RvcCBNYW51YWxseTwvYnV0dG9uPgogICAgPHNlY3Rpb24gaWQ9ImV4cG9ydEJveCIgY2xhc3M9ImV4cG9ydEJveCI+PGRpdiBpZD0iZXhwb3J0SGVhZGVyIiBjbGFzcz0iZXhwb3J0SGVhZGVyIj48c3Bhbj5FeHBvcnQgJmFtcDsgUmVuZGVyPC9zcGFuPjxzcGFuPuKMgzwvc3Bhbj48L2Rpdj48ZGl2IGNsYXNzPSJleHBvcnRCb2R5Ij4KICAgICAgPHNwYW4gY2xhc3M9ImZpZWxkTGFiZWwiPkV4cG9ydCBGb3JtYXQ8L3NwYW4+PGRpdiBjbGFzcz0iZXhwb3J0VGFicyI+PGJ1dHRvbiBjbGFzcz0iYWN0aXZlIj5WaWRlbyAoTVA0KTwvYnV0dG9uPjxidXR0b24gaWQ9ImdweEJ1dHRvbiI+R1BYIFRyYWNrPC9idXR0b24+PGJ1dHRvbiBpZD0iaW1hZ2VTZXRCdXR0b24iPkltYWdlIFNldDwvYnV0dG9uPjwvZGl2PgogICAgICA8c3BhbiBjbGFzcz0iZmllbGRMYWJlbCI+UXVhbGl0eTwvc3Bhbj48c2VsZWN0IGlkPSJxdWFsaXR5U2VsZWN0Ij48b3B0aW9uPjEwODBwIChIaWdoKTwvb3B0aW9uPjxvcHRpb24+NzIwcDwvb3B0aW9uPjwvc2VsZWN0PgogICAgICA8ZGl2IGNsYXNzPSJhdWRpb1JvdyI+PGRpdj48Yj5JbmNsdWRlIEF1ZGlvPC9iPjxkaXYgY2xhc3M9InNtYWxsIj5BZGQgbXVzaWMgdG8geW91ciB2aWRlbzwvZGl2PjwvZGl2PjxkaXYgaWQ9ImF1ZGlvU3dpdGNoIiBjbGFzcz0ic3dpdGNoIj48L2Rpdj48L2Rpdj48aW5wdXQgaWQ9ImF1ZGlvSW5wdXQiIGNsYXNzPSJhdWRpb0lucHV0IiB0eXBlPSJmaWxlIiBhY2NlcHQ9ImF1ZGlvLyoiPgogICAgICA8YnV0dG9uIGlkPSJyZW5kZXJCdXR0b24iIGNsYXNzPSJyZW5kZXJCdXR0b24iPuKWpiZuYnNwOyBSZW5kZXIgTVA0PHNwYW4+RmluYWwgdmlkZW8gZXhwb3J0PC9zcGFuPjwvYnV0dG9uPgogICAgPC9kaXY+PC9zZWN0aW9uPgogIDwvYXNpZGU+CjwvZGl2PgoKPGRpdiBpZD0iaW1taWNoTW9kYWwiIGNsYXNzPSJtb2RhbCI+PGRpdiBjbGFzcz0ibW9kYWxDYXJkIj48ZGl2IGNsYXNzPSJtb2RhbFRpdGxlIj5OZXcgSW1taWNoIEpvdXJuZXk8L2Rpdj48ZGl2IGNsYXNzPSJmb3JtR3JpZCI+PGlucHV0IGlkPSJpbW1pY2hVcmwiIHBsYWNlaG9sZGVyPSJJbW1pY2ggVVJMIOKAlCBmb3IgZXhhbXBsZSBodHRwOi8vMTkyLjE2OC42OC4xNTM6MjI4MyI+PGlucHV0IGlkPSJpbW1pY2hLZXkiIHR5cGU9InBhc3N3b3JkIiBwbGFjZWhvbGRlcj0iSW1taWNoIEFQSSBrZXkiPjxkaXYgY2xhc3M9InR3b0NvbCI+PGlucHV0IGlkPSJzdGFydERhdGUiIHR5cGU9ImRhdGUiPjxpbnB1dCBpZD0iZW5kRGF0ZSIgdHlwZT0iZGF0ZSI+PC9kaXY+PGRpdiBjbGFzcz0ic21hbGwiPlJlcXVpcmVkIHBlcm1pc3Npb25zOiBhc3NldC5yZWFkLCBhc3NldC52aWV3LCBhc3NldC5kb3dubG9hZCwgbWFwLnJlYWQsIHRpbWVsaW5lLnJlYWQ8L2Rpdj48ZGl2IGNsYXNzPSJtb2RhbEFjdGlvbnMiPjxidXR0b24gaWQ9InRlc3RJbW1pY2hCdXR0b24iPlRlc3QgQ29ubmVjdGlvbjwvYnV0dG9uPjxidXR0b24gaWQ9ImNyZWF0ZUpvdXJuZXlCdXR0b24iIGNsYXNzPSJwcmltYXJ5Ij5DcmVhdGUgSm91cm5leTwvYnV0dG9uPjxidXR0b24gZGF0YS1jbG9zZT0iaW1taWNoTW9kYWwiPkNhbmNlbDwvYnV0dG9uPjwvZGl2PjwvZGl2PjwvZGl2PjwvZGl2Pgo8ZGl2IGlkPSJ1cGxvYWRNb2RhbCIgY2xhc3M9Im1vZGFsIj48ZGl2IGNsYXNzPSJtb2RhbENhcmQiPjxkaXYgY2xhc3M9Im1vZGFsVGl0bGUiPlVwbG9hZCBHUFMgTWVkaWE8L2Rpdj48ZGl2IGNsYXNzPSJmb3JtR3JpZCI+PGlucHV0IGlkPSJ1cGxvYWROYW1lIiB2YWx1ZT0iVXBsb2FkZWQgSm91cm5leSIgcGxhY2Vob2xkZXI9IkpvdXJuZXkgbmFtZSI+PGlucHV0IGlkPSJ1cGxvYWRGaWxlcyIgdHlwZT0iZmlsZSIgYWNjZXB0PSJpbWFnZS8qLHZpZGVvLyoiIG11bHRpcGxlPjxkaXYgY2xhc3M9InNtYWxsIj5Pbmx5IG1lZGlhIGNvbnRhaW5pbmcgR1BTIG1ldGFkYXRhIGNhbiBhcHBlYXIgb24gdGhlIG1hcC48L2Rpdj48ZGl2IGNsYXNzPSJtb2RhbEFjdGlvbnMiPjxidXR0b24gaWQ9ImNyZWF0ZVVwbG9hZEJ1dHRvbiIgY2xhc3M9InByaW1hcnkiPkltcG9ydCBNZWRpYTwvYnV0dG9uPjxidXR0b24gZGF0YS1jbG9zZT0idXBsb2FkTW9kYWwiPkNhbmNlbDwvYnV0dG9uPjwvZGl2PjwvZGl2PjwvZGl2PjwvZGl2Pgo8ZGl2IGlkPSJzZXR0aW5nc01vZGFsIiBjbGFzcz0ibW9kYWwiPjxkaXYgY2xhc3M9Im1vZGFsQ2FyZCI+PGRpdiBjbGFzcz0ibW9kYWxUaXRsZSI+Sm91cm5leSBTZXR0aW5nczwvZGl2PjxkaXYgY2xhc3M9ImZvcm1HcmlkIj48bGFiZWwgY2xhc3M9InNtYWxsIj5TdG9wIHJhZGl1cywgbWV0ZXJzPC9sYWJlbD48aW5wdXQgaWQ9InN0b3BSYWRpdXMiIHR5cGU9Im51bWJlciIgbWluPSIxMCIgdmFsdWU9IjIwMCI+PGRpdiBjbGFzcz0idHdvQ29sIj48YnV0dG9uIGlkPSJyZWNsdXN0ZXJCdXR0b24iPkF1dG8tY2x1c3RlciBTdG9wczwvYnV0dG9uPjxidXR0b24gaWQ9InJldmVyc2VSb3V0ZUJ1dHRvbiI+UmV2ZXJzZSBSb3V0ZTwvYnV0dG9uPjwvZGl2PjxsYWJlbCBjbGFzcz0ic21hbGwiPkRlZmF1bHQgbWFwPC9sYWJlbD48c2VsZWN0IGlkPSJkZWZhdWx0TWFwU2VsZWN0Ij48b3B0aW9uIHZhbHVlPSJsaWdodCI+TGlnaHQgT1NNPC9vcHRpb24+PG9wdGlvbiB2YWx1ZT0iZGFyayI+RGFyazwvb3B0aW9uPjxvcHRpb24gdmFsdWU9InNhdGVsbGl0ZSI+U2F0ZWxsaXRlPC9vcHRpb24+PC9zZWxlY3Q+PGRpdiBjbGFzcz0ibW9kYWxBY3Rpb25zIj48YnV0dG9uIGRhdGEtY2xvc2U9InNldHRpbmdzTW9kYWwiPkNsb3NlPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+PC9kaXY+CjxkaXYgaWQ9ImFjY291bnRNb2RhbCIgY2xhc3M9Im1vZGFsIj48ZGl2IGNsYXNzPSJtb2RhbENhcmQiPjxkaXYgY2xhc3M9Im1vZGFsVGl0bGUiPkFjY291bnQgLyBJbW1pY2ggQ29ubmVjdGlvbjwvZGl2PjxkaXYgY2xhc3M9ImZvcm1HcmlkIj48aW5wdXQgaWQ9ImFjY291bnRVcmwiIHBsYWNlaG9sZGVyPSJJbW1pY2ggVVJMIj48aW5wdXQgaWQ9ImFjY291bnRLZXkiIHR5cGU9InBhc3N3b3JkIiBwbGFjZWhvbGRlcj0iQVBJIGtleSI+PGRpdiBjbGFzcz0ibW9kYWxBY3Rpb25zIj48YnV0dG9uIGlkPSJzYXZlQWNjb3VudEJ1dHRvbiIgY2xhc3M9InByaW1hcnkiPlNhdmUgQ29ubmVjdGlvbjwvYnV0dG9uPjxidXR0b24gZGF0YS1jbG9zZT0iYWNjb3VudE1vZGFsIj5DbG9zZTwvYnV0dG9uPjwvZGl2PjwvZGl2PjwvZGl2PjwvZGl2PgoKPGRpdiBpZD0icHJlc2VudE92ZXJsYXkiIGNsYXNzPSJwcmVzZW50T3ZlcmxheSI+PGRpdiBjbGFzcz0icHJlc2VudEhlYWRlciI+PGJ1dHRvbiBpZD0icHJlc2VudEJhY2tCdXR0b24iIGNsYXNzPSJwcmVzZW50QmFjayIgdGl0bGU9IkJhY2siPuKGkDwvYnV0dG9uPjxkaXYgY2xhc3M9ImxvZ29GbG93ZXIiPjxzcGFuIGNsYXNzPSJwZXRhbCBwMSI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMiI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwMyI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNCI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNSI+PC9zcGFuPjxzcGFuIGNsYXNzPSJwZXRhbCBwNiI+PC9zcGFuPjwvZGl2PjxkaXY+PGRpdiBpZD0icHJlc2VudEhlYWRlclRpdGxlIiBjbGFzcz0icHJlc2VudEhlYWRlclRpdGxlIj5QcmVzZW50IEpvdXJuZXk8L2Rpdj48ZGl2IGlkPSJwcmVzZW50SGVhZGVyTWV0YSIgY2xhc3M9InByZXNlbnRIZWFkZXJNZXRhIj48L2Rpdj48L2Rpdj48ZGl2IGNsYXNzPSJwcmVzZW50SGVhZGVyU3BhY2VyIj48L2Rpdj48YnV0dG9uIGlkPSJjZW50ZXJUcmlwQnV0dG9uIiBjbGFzcz0icHJlc2VudEhlYWRlckFjdGlvbiI+4oyWIENlbnRlciBvbiBUcmlwPC9idXR0b24+PGJ1dHRvbiBpZD0icmV0dXJuU3RhcnRCdXR0b24iIGNsYXNzPSJwcmVzZW50SGVhZGVyQWN0aW9uIj7ihrYgUmV0dXJuIHRvIFN0YXJ0PC9idXR0b24+PGJ1dHRvbiBpZD0iY2xvc2VQcmVzZW50QnV0dG9uIiBjbGFzcz0idG9wQWN0aW9uIj5DbG9zZTwvYnV0dG9uPjwvZGl2PgogIDxkaXYgY2xhc3M9InByZXNlbnRNYWluIj48ZGl2IGlkPSJwcmVzZW50TWFwIiBjbGFzcz0icHJlc2VudE1hcCI+PC9kaXY+PGRpdiBpZD0icHJlc2VudFN0b3BCYW5uZXIiIGNsYXNzPSJwcmVzZW50U3RvcEJhbm5lciI+PGRpdiBpZD0icHJlc2VudFN0b3BCYW5uZXJUaXRsZSIgY2xhc3M9InByZXNlbnRTdG9wQmFubmVyVGl0bGUiPkpvdXJuZXkgU3RvcDwvZGl2PjxkaXYgaWQ9InByZXNlbnRTdG9wQmFubmVyUmFuZ2UiIGNsYXNzPSJwcmVzZW50U3RvcEJhbm5lclJhbmdlIj48L2Rpdj48L2Rpdj48ZGl2IGlkPSJwcmVzZW50U3RvcFJhaWwiIGNsYXNzPSJwcmVzZW50U3RvcFJhaWwiPjwvZGl2PjxkaXYgaWQ9InByZXNlbnRQaG90b0NhcmQiIGNsYXNzPSJwcmVzZW50UGhvdG9DYXJkIj48L2Rpdj48ZGl2IGNsYXNzPSJwcmVzZW50SHVkIj48YnV0dG9uIGlkPSJwcmV2aW91c1N0b3BCdXR0b24iPuKGkCBTdG9wPC9idXR0b24+PGJ1dHRvbiBpZD0icHJldmlvdXNQaG90b0J1dHRvbiI+4oaQIFBob3RvPC9idXR0b24+PGJ1dHRvbiBpZD0icGxheUpvdXJuZXlCdXR0b24iIGNsYXNzPSJwbGF5Ij7ilrYgUGxheTwvYnV0dG9uPjxidXR0b24gaWQ9Im5leHRQaG90b0J1dHRvbiI+UGhvdG8g4oaSPC9idXR0b24+PGJ1dHRvbiBpZD0ibmV4dFN0b3BCdXR0b24iPlN0b3Ag4oaSPC9idXR0b24+PC9kaXY+PC9kaXY+PGRpdiBpZD0icHJlc2VudEZpbG1zdHJpcCIgY2xhc3M9InByZXNlbnRGaWxtc3RyaXAiPjwvZGl2Pgo8L2Rpdj4KPGRpdiBpZD0idG9hc3QiIGNsYXNzPSJ0b2FzdCI+PC9kaXY+Cgo8c2NyaXB0Pgpjb25zdCBNQVBfU1RZTEVTPXsKIGxpZ2h0Ont2ZXJzaW9uOjgsZ2x5cGhzOidodHRwczovL2RlbW90aWxlcy5tYXBsaWJyZS5vcmcvZm9udC97Zm9udHN0YWNrfS97cmFuZ2V9LnBiZicsc291cmNlczp7YmFzZTp7dHlwZToncmFzdGVyJyx0aWxlczpbJ2h0dHBzOi8vYS5iYXNlbWFwcy5jYXJ0b2Nkbi5jb20vcmFzdGVydGlsZXMvdm95YWdlci97en0ve3h9L3t5fUAyeC5wbmcnLCdodHRwczovL2IuYmFzZW1hcHMuY2FydG9jZG4uY29tL3Jhc3RlcnRpbGVzL3ZveWFnZXIve3p9L3t4fS97eX1AMngucG5nJ10sdGlsZVNpemU6MjU2LGF0dHJpYnV0aW9uOifCqSBPcGVuU3RyZWV0TWFwIGNvbnRyaWJ1dG9ycyDCqSBDQVJUTyd9fSxsYXllcnM6W3tpZDonYmFzZScsdHlwZToncmFzdGVyJyxzb3VyY2U6J2Jhc2UnLG1pbnpvb206MCxtYXh6b29tOjIwfV19LAogZGFyazp7dmVyc2lvbjo4LGdseXBoczonaHR0cHM6Ly9kZW1vdGlsZXMubWFwbGlicmUub3JnL2ZvbnQve2ZvbnRzdGFja30ve3JhbmdlfS5wYmYnLHNvdXJjZXM6e2Jhc2U6e3R5cGU6J3Jhc3RlcicsdGlsZXM6WydodHRwczovL2EuYmFzZW1hcHMuY2FydG9jZG4uY29tL2RhcmtfYWxsL3t6fS97eH0ve3l9QDJ4LnBuZycsJ2h0dHBzOi8vYi5iYXNlbWFwcy5jYXJ0b2Nkbi5jb20vZGFya19hbGwve3p9L3t4fS97eX1AMngucG5nJ10sdGlsZVNpemU6MjU2LGF0dHJpYnV0aW9uOifCqSBPcGVuU3RyZWV0TWFwIGNvbnRyaWJ1dG9ycyDCqSBDQVJUTyd9fSxsYXllcnM6W3tpZDonYmFzZScsdHlwZToncmFzdGVyJyxzb3VyY2U6J2Jhc2UnLG1pbnpvb206MCxtYXh6b29tOjIwfV19LAogc2F0ZWxsaXRlOnt2ZXJzaW9uOjgsZ2x5cGhzOidodHRwczovL2RlbW90aWxlcy5tYXBsaWJyZS5vcmcvZm9udC97Zm9udHN0YWNrfS97cmFuZ2V9LnBiZicsc291cmNlczp7YmFzZTp7dHlwZToncmFzdGVyJyx0aWxlczpbJ2h0dHBzOi8vc2VydmVyLmFyY2dpc29ubGluZS5jb20vQXJjR0lTL3Jlc3Qvc2VydmljZXMvV29ybGRfSW1hZ2VyeS9NYXBTZXJ2ZXIvdGlsZS97en0ve3l9L3t4fSddLHRpbGVTaXplOjI1NixtaW56b29tOjAsbWF4em9vbToxOCxhdHRyaWJ1dGlvbjonVGlsZXMgwqkgRXNyaSd9fSxsYXllcnM6W3tpZDonYmFzZScsdHlwZToncmFzdGVyJyxzb3VyY2U6J2Jhc2UnLG1pbnpvb206MCxtYXh6b29tOjI0LHBhaW50OnsncmFzdGVyLXJlc2FtcGxpbmcnOidsaW5lYXInfX1dfQp9OwpsZXQgcHJvamVjdHM9W10scHJvamVjdD1udWxsLG1hcD1udWxsLHByZXNlbnRNYXA9bnVsbCxtYXBTdHlsZUtleT1sb2NhbFN0b3JhZ2UuZ2V0SXRlbSgndHJpcHB5X21hcF9zdHlsZScpfHwnbGlnaHQnOwpsZXQgbWFya2Vycz1bXSxwaG90b01hcmtlcnM9W10scHJlc2VudE1hcmtlcnM9W10scHJlc2VudFBob3RvTWFya2Vycz1bXSxhY3RpdmVTdG9wSWQ9bnVsbCxmaWx0ZXJTdG9wSWQ9bnVsbCxhY3RpdmVBc3NldElkPW51bGwsYWN0aXZlUG9wdXA9bnVsbCxwcmVzZW50U3RvcEluZGV4PTAscHJlc2VudFBob3RvSW5kZXg9LTEscHJlc2VudFRpbWVyPW51bGwscHJlc2VudE9yYml0VGltZXI9bnVsbCxwcmVzZW50T3JiaXREZWxheT1udWxsLHByZXNlbnRWaWV3PSd0cmlwJyxwcmVzZW50Rm9jdXNNYXJrZXI9bnVsbDsKY29uc3QgZWw9aWQ9PmRvY3VtZW50LmdldEVsZW1lbnRCeUlkKGlkKTsKZnVuY3Rpb24gY2xvbmVTdHlsZShrZXkpe3JldHVybiBKU09OLnBhcnNlKEpTT04uc3RyaW5naWZ5KE1BUF9TVFlMRVNba2V5XXx8TUFQX1NUWUxFUy5saWdodCkpfQpmdW5jdGlvbiB0b2FzdChtZXNzYWdlKXtjb25zdCB0PWVsKCd0b2FzdCcpO3QudGV4dENvbnRlbnQ9bWVzc2FnZTt0LmNsYXNzTGlzdC5hZGQoJ3Nob3cnKTtjbGVhclRpbWVvdXQodC5fdGltZXIpO3QuX3RpbWVyPXNldFRpbWVvdXQoKCk9PnQuY2xhc3NMaXN0LnJlbW92ZSgnc2hvdycpLDQzMDApfQpmdW5jdGlvbiBlc2Modil7cmV0dXJuIFN0cmluZyh2Pz8nJykucmVwbGFjZSgvWyY8PiciXS9nLGM9Pih7JyYnOicmYW1wOycsJzwnOicmbHQ7JywnPic6JyZndDsnLCInIjonJiMzOTsnLCciJzonJnF1b3Q7J31bY10pKX0KZnVuY3Rpb24gaXNvRGF0ZSh2KXtpZighdilyZXR1cm4nJztyZXR1cm4gU3RyaW5nKHYpLnNsaWNlKDAsMTApfQpmdW5jdGlvbiBwcmV0dHlEYXRlKHYpe2lmKCF2KXJldHVybicnO2NvbnN0IGQ9bmV3IERhdGUoU3RyaW5nKHYpLnNsaWNlKDAsMTApKydUMTI6MDA6MDAnKTtyZXR1cm4gTnVtYmVyLmlzTmFOKGQuZ2V0VGltZSgpKT9TdHJpbmcodikuc2xpY2UoMCwxMCk6ZC50b0xvY2FsZURhdGVTdHJpbmcodW5kZWZpbmVkLHttb250aDonc2hvcnQnLGRheTonbnVtZXJpYycseWVhcjonbnVtZXJpYyd9KX0KZnVuY3Rpb24gcmFuZ2VUZXh0KG9iail7Y29uc3QgYT1vYmo/LmltbWljaD8uc3RhcnRfZGF0ZXx8b2JqPy5zdGFydF9kYXRlO2NvbnN0IGI9b2JqPy5pbW1pY2g/LmVuZF9kYXRlfHxvYmo/LmVuZF9kYXRlO2lmKGEmJmIpcmV0dXJuIGAke2lzb0RhdGUoYSl9IHRvICR7aXNvRGF0ZShiKX1gO3JldHVybiBwcmV0dHlEYXRlKG9iaj8uY3JlYXRlZCl9CmZ1bmN0aW9uIGFzc2V0RGF0ZSh2YWx1ZSl7aWYoIXZhbHVlKXJldHVybiBudWxsO2xldCByYXc9U3RyaW5nKHZhbHVlKS50cmltKCk7aWYoL15cZHs0fTpcZHsyfTpcZHsyfS8udGVzdChyYXcpKXJhdz1yYXcucmVwbGFjZSgvXihcZHs0fSk6KFxkezJ9KTooXGR7Mn0pLywnJDEtJDItJDMnKS5yZXBsYWNlKCcgJywnVCcpO2NvbnN0IGQ9bmV3IERhdGUocmF3KTtyZXR1cm4gTnVtYmVyLmlzTmFOKGQuZ2V0VGltZSgpKT9udWxsOmR9CmZ1bmN0aW9uIGZvcm1hdEFzc2V0RGF0ZVRpbWUodmFsdWUpe2NvbnN0IGQ9YXNzZXREYXRlKHZhbHVlKTtpZighZClyZXR1cm4gdmFsdWU/U3RyaW5nKHZhbHVlKTonRGF0ZSB1bmF2YWlsYWJsZSc7Y29uc3QgZGF0ZT1kLnRvTG9jYWxlRGF0ZVN0cmluZygnZW4tVVMnLHttb250aDonMi1kaWdpdCcsZGF5OicyLWRpZ2l0Jyx5ZWFyOidudW1lcmljJ30pLnJlcGxhY2VBbGwoJy8nLCctJyk7Y29uc3QgdGltZT1kLnRvTG9jYWxlVGltZVN0cmluZygnZW4tVVMnLHtob3VyOidudW1lcmljJyxtaW51dGU6JzItZGlnaXQnfSk7cmV0dXJuIGAke2RhdGV9ICR7dGltZX1gfWZ1bmN0aW9uIGRlY2ltYWxUb0Rtcyh2YWx1ZSxpc0xhdCl7Y29uc3Qgbj1OdW1iZXIodmFsdWUpO2lmKCFOdW1iZXIuaXNGaW5pdGUobikpcmV0dXJuJ0Nvb3JkaW5hdGUgdW5hdmFpbGFibGUnO2NvbnN0IGFicz1NYXRoLmFicyhuKSxkZWc9TWF0aC5mbG9vcihhYnMpLG1pbnV0ZXNGbG9hdD0oYWJzLWRlZykqNjAsbWluPU1hdGguZmxvb3IobWludXRlc0Zsb2F0KSxzZWM9KG1pbnV0ZXNGbG9hdC1taW4pKjYwLGhlbT1pc0xhdD8obj49MD8nTic6J1MnKToobj49MD8nRSc6J1cnKTtyZXR1cm4gYCR7ZGVnfcKwICR7U3RyaW5nKG1pbikucGFkU3RhcnQoMiwnMCcpfeKAsiAke3NlYy50b0ZpeGVkKDIpLnBhZFN0YXJ0KDUsJzAnKX3igLMgJHtoZW19YH1mdW5jdGlvbiBhc3NldENvb3JkaW5hdGVUZXh0KGFzc2V0KXtyZXR1cm4gYCR7ZGVjaW1hbFRvRG1zKGFzc2V0Py5sYXQsdHJ1ZSl9ICDigKIgICR7ZGVjaW1hbFRvRG1zKGFzc2V0Py5sb24sZmFsc2UpfWB9CmZ1bmN0aW9uIHN0b3BEYXRlUmFuZ2Uoc3RvcCl7Y29uc3QgZGF0ZXM9c3RvcEFzc2V0cyhzdG9wKS5tYXAoYT0+YXNzZXREYXRlKGEudGltZSkpLmZpbHRlcihCb29sZWFuKS5zb3J0KChhLGIpPT5hLWIpO2lmKCFkYXRlcy5sZW5ndGgpcmV0dXJuJ0RhdGUvdGltZSB1bmF2YWlsYWJsZSc7Y29uc3QgZmlyc3Q9ZGF0ZXNbMF0sbGFzdD1kYXRlc1tkYXRlcy5sZW5ndGgtMV07Y29uc3QgZmQ9Zmlyc3QudG9Mb2NhbGVEYXRlU3RyaW5nKCdlbi1VUycse21vbnRoOicyLWRpZ2l0JyxkYXk6JzItZGlnaXQnLHllYXI6J251bWVyaWMnfSkucmVwbGFjZUFsbCgnLycsJy0nKTtjb25zdCBmdD1maXJzdC50b0xvY2FsZVRpbWVTdHJpbmcoJ2VuLVVTJyx7aG91cjonbnVtZXJpYycsbWludXRlOicyLWRpZ2l0J30pO2NvbnN0IGxkPWxhc3QudG9Mb2NhbGVEYXRlU3RyaW5nKCdlbi1VUycse21vbnRoOicyLWRpZ2l0JyxkYXk6JzItZGlnaXQnLHllYXI6J251bWVyaWMnfSkucmVwbGFjZUFsbCgnLycsJy0nKTtjb25zdCBsdD1sYXN0LnRvTG9jYWxlVGltZVN0cmluZygnZW4tVVMnLHtob3VyOidudW1lcmljJyxtaW51dGU6JzItZGlnaXQnfSk7cmV0dXJuIGZkPT09bGQ/YCR7ZmR9ICR7ZnR9IOKAkyAke2x0fWA6YCR7ZmR9ICR7ZnR9IOKAkyAke2xkfSAke2x0fWB9CmZ1bmN0aW9uIHZhbGlkUG9pbnQoaXRlbSl7cmV0dXJuIE51bWJlci5pc0Zpbml0ZShOdW1iZXIoaXRlbT8ubG9uKSkmJk51bWJlci5pc0Zpbml0ZShOdW1iZXIoaXRlbT8ubGF0KSkmJk1hdGguYWJzKE51bWJlcihpdGVtLmxhdCkpPD05MCYmTWF0aC5hYnMoTnVtYmVyKGl0ZW0ubG9uKSk8PTE4MH0KZnVuY3Rpb24gc3RvcEJvdW5kcyhzdG9wKXtjb25zdCBhc3NldHM9c3RvcEFzc2V0cyhzdG9wKS5maWx0ZXIodmFsaWRQb2ludCk7Y29uc3QgYm91bmRzPW5ldyBtYXBsaWJyZWdsLkxuZ0xhdEJvdW5kcygpO2Fzc2V0cy5mb3JFYWNoKGE9PmJvdW5kcy5leHRlbmQoW051bWJlcihhLmxvbiksTnVtYmVyKGEubGF0KV0pKTtpZighYXNzZXRzLmxlbmd0aCYmdmFsaWRQb2ludChzdG9wKSlib3VuZHMuZXh0ZW5kKFtOdW1iZXIoc3RvcC5sb24pLE51bWJlcihzdG9wLmxhdCldKTtyZXR1cm57Ym91bmRzLGFzc2V0c319CmZ1bmN0aW9uIGNvbm4oKXtyZXR1cm57YmFzZV91cmw6bG9jYWxTdG9yYWdlLmdldEl0ZW0oJ3RyaXBweV9pbW1pY2hfdXJsJyl8fCcnLGFwaV9rZXk6bG9jYWxTdG9yYWdlLmdldEl0ZW0oJ3RyaXBweV9pbW1pY2hfa2V5Jyl8fCcnfX0KZnVuY3Rpb24gc2F2ZUNvbm4odXJsLGtleSl7bG9jYWxTdG9yYWdlLnNldEl0ZW0oJ3RyaXBweV9pbW1pY2hfdXJsJyx1cmwpO2xvY2FsU3RvcmFnZS5zZXRJdGVtKCd0cmlwcHlfaW1taWNoX2tleScsa2V5KX0KYXN5bmMgZnVuY3Rpb24gYXBpKHBhdGgsb3B0aW9ucz17fSl7Y29uc3QgcmVzcG9uc2U9YXdhaXQgZmV0Y2gocGF0aCxvcHRpb25zKTtjb25zdCByYXc9YXdhaXQgcmVzcG9uc2UudGV4dCgpO2xldCBkYXRhO3RyeXtkYXRhPUpTT04ucGFyc2UocmF3KX1jYXRjaHtkYXRhPXtkZXRhaWw6cmF3fX1pZighcmVzcG9uc2Uub2spdGhyb3cgbmV3IEVycm9yKGRhdGEuZGV0YWlsfHxyYXd8fGBIVFRQICR7cmVzcG9uc2Uuc3RhdHVzfWApO3JldHVybiBkYXRhfQpmdW5jdGlvbiBzdG9wTmFtZShzdG9wLGluZGV4KXtjb25zdCByYXc9KHN0b3A/Lm5hbWV8fCcnKS50cmltKCk7cmV0dXJuIHJhdyYmIS9eU3RvcFxzK1xkKyQvaS50ZXN0KHJhdyk/cmF3OmBTdG9wICR7aW5kZXgrMX1gfQpmdW5jdGlvbiBzdG9wQXNzZXRzKHN0b3Ape2lmKCFwcm9qZWN0fHwhc3RvcClyZXR1cm5bXTtjb25zdCBpZHM9bmV3IFNldChzdG9wLmFzc2V0X2lkc3x8W10pO3JldHVybihwcm9qZWN0LmFzc2V0c3x8W10pLmZpbHRlcihhPT5pZHMuaGFzKGEuYXNzZXRfaWQpKX0KZnVuY3Rpb24gZmlyc3RTdG9wQXNzZXQoc3RvcCl7cmV0dXJuIHN0b3BBc3NldHMoc3RvcClbMF18fG51bGx9CmZ1bmN0aW9uIHByb2plY3RTdW1tYXJ5Q291bnQocCl7cmV0dXJuIE51bWJlcihwPy5jb3VudD8/cD8uYXNzZXRzPy5sZW5ndGg/PzApfQpmdW5jdGlvbiBzZXRNb2RhbChpZCxvbj10cnVlKXtlbChpZCkuY2xhc3NMaXN0LnRvZ2dsZSgnc2hvdycsb24pfQpmdW5jdGlvbiBpbml0Rm9ybXMoKXtjb25zdCBjPWNvbm4oKTtlbCgnaW1taWNoVXJsJykudmFsdWU9Yy5iYXNlX3VybDtlbCgnaW1taWNoS2V5JykudmFsdWU9Yy5hcGlfa2V5O2VsKCdhY2NvdW50VXJsJykudmFsdWU9Yy5iYXNlX3VybDtlbCgnYWNjb3VudEtleScpLnZhbHVlPWMuYXBpX2tleTtjb25zdCBkPW5ldyBEYXRlKCkscz1uZXcgRGF0ZSgpO3Muc2V0RGF0ZShzLmdldERhdGUoKS03KTtlbCgnc3RhcnREYXRlJykudmFsdWU9cy50b0lTT1N0cmluZygpLnNsaWNlKDAsMTApO2VsKCdlbmREYXRlJykudmFsdWU9ZC50b0lTT1N0cmluZygpLnNsaWNlKDAsMTApO2VsKCdkZWZhdWx0TWFwU2VsZWN0JykudmFsdWU9bWFwU3R5bGVLZXl9CmFzeW5jIGZ1bmN0aW9uIGxvYWRQcm9qZWN0cygpe3Byb2plY3RzPWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0cycpO3JlbmRlclByb2plY3RzKCk7aWYoIXByb2plY3QmJnByb2plY3RzLmxlbmd0aClhd2FpdCBvcGVuUHJvamVjdChwcm9qZWN0c1swXS5pZCk7aWYoIXByb2plY3RzLmxlbmd0aClyZW5kZXJBbGwoKX0KZnVuY3Rpb24gcmVuZGVyUHJvamVjdHMoKXtjb25zdCBxPWVsKCdwcm9qZWN0U2VhcmNoJykudmFsdWUudHJpbSgpLnRvTG93ZXJDYXNlKCk7Y29uc3QgbGlzdD1wcm9qZWN0cy5maWx0ZXIocD0+IXF8fChwLm5hbWV8fCcnKS50b0xvd2VyQ2FzZSgpLmluY2x1ZGVzKHEpKTtlbCgncHJvamVjdExpc3QnKS5pbm5lckhUTUw9bGlzdC5tYXAocD0+YDxhcnRpY2xlIGNsYXNzPSJwcm9qZWN0Q2FyZCAke3Byb2plY3Q/LmlkPT09cC5pZD8nYWN0aXZlJzonJ30iIGRhdGEtaWQ9IiR7ZXNjKHAuaWQpfSI+PGJ1dHRvbiBjbGFzcz0icHJvamVjdE1lbnUiIGRhdGEtbWVudT0iJHtlc2MocC5pZCl9Ij7ii648L2J1dHRvbj48ZGl2IGNsYXNzPSJwcm9qZWN0Q2FyZFRpdGxlIj4ke2VzYyhwLm5hbWV8fCdVbnRpdGxlZCBKb3VybmV5Jyl9PC9kaXY+PGRpdiBjbGFzcz0icHJvamVjdERhdGUiPiR7ZXNjKHJhbmdlVGV4dChwKXx8JycpfTwvZGl2PjxkaXYgY2xhc3M9InByb2plY3RTdGF0cyI+PHNwYW4gY2xhc3M9ImRvdCI+4pePPC9zcGFuPiAke3Byb2plY3RTdW1tYXJ5Q291bnQocCl9IG1lZGlhJm5ic3A7IOKAoiAmbmJzcDske051bWJlcihwLnN0b3BzfHwwKX0gc3RvcHM8L2Rpdj48YnV0dG9uIGNsYXNzPSJwcm9qZWN0RGVsZXRlIiBkYXRhLWRlbGV0ZT0iJHtlc2MocC5pZCl9Ij5EZWxldGU8L2J1dHRvbj48L2FydGljbGU+YCkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gam91cm5leXMgeWV0LjwvZGl2Pic7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnLnByb2plY3RDYXJkJykuZm9yRWFjaChjYXJkPT5jYXJkLmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJyxlPT57aWYoZS50YXJnZXQuY2xvc2VzdCgnYnV0dG9uJykpcmV0dXJuO29wZW5Qcm9qZWN0KGNhcmQuZGF0YXNldC5pZCl9KSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtbWVudV0nKS5mb3JFYWNoKGI9PmIuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLGU9PntlLnN0b3BQcm9wYWdhdGlvbigpO2IuY2xvc2VzdCgnLnByb2plY3RDYXJkJykuY2xhc3NMaXN0LnRvZ2dsZSgnbWVudU9wZW4nKX0pKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1kZWxldGVdJykuZm9yRWFjaChiPT5iLmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJyxlPT57ZS5zdG9wUHJvcGFnYXRpb24oKTtkZWxldGVQcm9qZWN0KGIuZGF0YXNldC5kZWxldGUpfSkpfQphc3luYyBmdW5jdGlvbiBvcGVuUHJvamVjdChpZCl7cHJvamVjdD1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdC8nK2VuY29kZVVSSUNvbXBvbmVudChpZCkpO2FjdGl2ZVN0b3BJZD1wcm9qZWN0LnN0b3BzPy5bMF0/LnN0b3BfaWR8fG51bGw7ZmlsdGVyU3RvcElkPWFjdGl2ZVN0b3BJZDthY3RpdmVBc3NldElkPW51bGw7cmVuZGVyQWxsKCk7dG9hc3QoYExvYWRlZCAke3Byb2plY3QubmFtZXx8J2pvdXJuZXknfWApfQphc3luYyBmdW5jdGlvbiBkZWxldGVQcm9qZWN0KGlkKXtpZighY29uZmlybSgnRGVsZXRlIHRoaXMgam91cm5leSBhbmQgaXRzIHNhdmVkIGV4cG9ydD8nKSlyZXR1cm47YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytlbmNvZGVVUklDb21wb25lbnQoaWQpLHttZXRob2Q6J0RFTEVURSd9KTtpZihwcm9qZWN0Py5pZD09PWlkKXByb2plY3Q9bnVsbDtwcm9qZWN0cz1wcm9qZWN0cy5maWx0ZXIocD0+cC5pZCE9PWlkKTthd2FpdCBsb2FkUHJvamVjdHMoKX0KZnVuY3Rpb24gcmVuZGVyQWxsKCl7cmVuZGVyUHJvamVjdHMoKTtyZW5kZXJIZWFkZXIoKTtyZW5kZXJTdG9wcygpO3JlbmRlckdhbGxlcnkoKTtyZW5kZXJNYXAodHJ1ZSl9CmZ1bmN0aW9uIHJlbmRlckhlYWRlcigpe2lmKCFwcm9qZWN0KXtlbCgnam91cm5leVRpdGxlJykudGV4dENvbnRlbnQ9J05vIGpvdXJuZXkgc2VsZWN0ZWQnO2VsKCdqb3VybmV5TWV0YScpLnRleHRDb250ZW50PSdMb2FkIG9yIGNyZWF0ZSBhIGpvdXJuZXknO3JldHVybn1lbCgnam91cm5leVRpdGxlJykudGV4dENvbnRlbnQ9cHJvamVjdC5uYW1lfHwnVW50aXRsZWQgSm91cm5leSc7Y29uc3QgbWVkaWE9KHByb2plY3QuYXNzZXRzfHxbXSkubGVuZ3RoLHN0b3BzPShwcm9qZWN0LnN0b3BzfHxbXSkubGVuZ3RoO2VsKCdqb3VybmV5TWV0YScpLmlubmVySFRNTD1gPHNwYW4+4pe3ICR7ZXNjKHJhbmdlVGV4dChwcm9qZWN0KXx8cHJldHR5RGF0ZShwcm9qZWN0LmNyZWF0ZWQpKX08L3NwYW4+PHNwYW4gY2xhc3M9ImxpdmVEb3QiPjwvc3Bhbj48c3Bhbj4ke21lZGlhfSBtZWRpYTwvc3Bhbj48c3Bhbj7igKIgJHtzdG9wc30gc3RvcHM8L3NwYW4+YH0KZnVuY3Rpb24gZW5zdXJlTWFwKCl7aWYobWFwKXJldHVybjttYXA9bmV3IG1hcGxpYnJlZ2wuTWFwKHtjb250YWluZXI6J21hcCcsc3R5bGU6Y2xvbmVTdHlsZShtYXBTdHlsZUtleSksY2VudGVyOlstOTgsMzldLHpvb206MyxwaXRjaDowLGJlYXJpbmc6MCxhdHRyaWJ1dGlvbkNvbnRyb2w6dHJ1ZX0pO21hcC5hZGRDb250cm9sKG5ldyBtYXBsaWJyZWdsLk5hdmlnYXRpb25Db250cm9sKHtzaG93Q29tcGFzczpmYWxzZX0pLCdib3R0b20tcmlnaHQnKTttYXAub24oJ2xvYWQnLCgpPT5yZW5kZXJNYXAodHJ1ZSkpO21hcC5vbignem9vbWVuZCcscmVuZGVyU2VsZWN0ZWRQaG90b0J1YmJsZXMpO21hcC5vbignbW92ZWVuZCcscmVuZGVyU2VsZWN0ZWRQaG90b0J1YmJsZXMpfQpmdW5jdGlvbiBjbGVhckJ1YmJsZU1hcmtlcnMobGlzdCl7bGlzdC5mb3JFYWNoKG09Pnt0cnl7bS5yZW1vdmUoKX1jYXRjaHt9fSk7bGlzdC5sZW5ndGg9MH0KZnVuY3Rpb24gY2xlYXJNYXBNYXJrZXJzKCl7Y2xlYXJCdWJibGVNYXJrZXJzKG1hcmtlcnMpO2NsZWFyQnViYmxlTWFya2VycyhwaG90b01hcmtlcnMpO2lmKGFjdGl2ZVBvcHVwKXt0cnl7YWN0aXZlUG9wdXAucmVtb3ZlKCl9Y2F0Y2h7fWFjdGl2ZVBvcHVwPW51bGx9fQpmdW5jdGlvbiByZW1vdmVMYXllckFuZFNvdXJjZSh0YXJnZXRNYXAsaWRzLHNvdXJjZSl7aWRzLmZvckVhY2goaWQ9PntpZih0YXJnZXRNYXAuZ2V0TGF5ZXIoaWQpKXRhcmdldE1hcC5yZW1vdmVMYXllcihpZCl9KTtpZih0YXJnZXRNYXAuZ2V0U291cmNlKHNvdXJjZSkpdGFyZ2V0TWFwLnJlbW92ZVNvdXJjZShzb3VyY2UpfQpmdW5jdGlvbiBhZGRSb3V0ZUxheWVycyh0YXJnZXRNYXAsaWRQcmVmaXgsY29vcmRzKXtjb25zdCBzb3VyY2U9aWRQcmVmaXgrJy1yb3V0ZScsZ2xvdz1pZFByZWZpeCsnLXJvdXRlLWdsb3cnLGxpbmU9aWRQcmVmaXgrJy1yb3V0ZS1saW5lJztyZW1vdmVMYXllckFuZFNvdXJjZSh0YXJnZXRNYXAsW2xpbmUsZ2xvd10sc291cmNlKTtpZihjb29yZHMubGVuZ3RoPDIpcmV0dXJuO3RhcmdldE1hcC5hZGRTb3VyY2Uoc291cmNlLHt0eXBlOidnZW9qc29uJyxkYXRhOnt0eXBlOidGZWF0dXJlJyxnZW9tZXRyeTp7dHlwZTonTGluZVN0cmluZycsY29vcmRpbmF0ZXM6Y29vcmRzfX19KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOmdsb3csdHlwZTonbGluZScsc291cmNlLHBhaW50OnsnbGluZS1jb2xvcic6JyMwMGQ4ZmYnLCdsaW5lLXdpZHRoJzoxMSwnbGluZS1vcGFjaXR5JzouMjAsJ2xpbmUtYmx1cic6NX19KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOmxpbmUsdHlwZTonbGluZScsc291cmNlLHBhaW50OnsnbGluZS1jb2xvcic6JyMwMGNmZWUnLCdsaW5lLXdpZHRoJzo0LCdsaW5lLW9wYWNpdHknOi45NX19KX0KZnVuY3Rpb24gc3RvcEZlYXR1cmVzKCl7cmV0dXJuKHByb2plY3Q/LnN0b3BzfHxbXSkuZmlsdGVyKHZhbGlkUG9pbnQpLm1hcCgocyxpKT0+KHt0eXBlOidGZWF0dXJlJyxnZW9tZXRyeTp7dHlwZTonUG9pbnQnLGNvb3JkaW5hdGVzOltOdW1iZXIocy5sb24pLE51bWJlcihzLmxhdCldfSxwcm9wZXJ0aWVzOntzdG9wX2lkOnMuc3RvcF9pZCxpbmRleDppKzEsbmFtZTpzdG9wTmFtZShzLGkpfX0pKX0KZnVuY3Rpb24gcGhvdG9GZWF0dXJlcygpe3JldHVybihwcm9qZWN0Py5hc3NldHN8fFtdKS5maWx0ZXIodmFsaWRQb2ludCkubWFwKGE9Pih7dHlwZTonRmVhdHVyZScsZ2VvbWV0cnk6e3R5cGU6J1BvaW50Jyxjb29yZGluYXRlczpbTnVtYmVyKGEubG9uKSxOdW1iZXIoYS5sYXQpXX0scHJvcGVydGllczp7YXNzZXRfaWQ6YS5hc3NldF9pZCxuYW1lOmEubmFtZXx8J1Bob3RvJyx0aW1lOmEudGltZXx8Jycsc3RvcF9pZDoocHJvamVjdD8uc3RvcHN8fFtdKS5maW5kKHM9PihzLmFzc2V0X2lkc3x8W10pLmluY2x1ZGVzKGEuYXNzZXRfaWQpKT8uc3RvcF9pZHx8Jyd9fSkpfQpmdW5jdGlvbiBhZGRDbHVzdGVyTGF5ZXJzKHRhcmdldE1hcCxwcmVmaXgpe2NvbnN0IHN0b3BTb3VyY2U9cHJlZml4Kyctc3RvcHMnLHBob3RvU291cmNlPXByZWZpeCsnLXBob3Rvcyc7cmVtb3ZlTGF5ZXJBbmRTb3VyY2UodGFyZ2V0TWFwLFtwcmVmaXgrJy1zdG9wLWNsdXN0ZXItY291bnQnLHByZWZpeCsnLXN0b3AtY2x1c3RlcnMnLHByZWZpeCsnLXN0b3AtbnVtYmVyJyxwcmVmaXgrJy1zdG9wLXBvaW50cyddLHN0b3BTb3VyY2UpO3JlbW92ZUxheWVyQW5kU291cmNlKHRhcmdldE1hcCxbcHJlZml4KyctcGhvdG8tY2x1c3Rlci1jb3VudCcscHJlZml4KyctcGhvdG8tY2x1c3RlcnMnLHByZWZpeCsnLXBob3RvLXBvaW50cyddLHBob3RvU291cmNlKTt0YXJnZXRNYXAuYWRkU291cmNlKHN0b3BTb3VyY2Use3R5cGU6J2dlb2pzb24nLGNsdXN0ZXI6dHJ1ZSxjbHVzdGVyUmFkaXVzOjQ4LGNsdXN0ZXJNYXhab29tOjksZGF0YTp7dHlwZTonRmVhdHVyZUNvbGxlY3Rpb24nLGZlYXR1cmVzOnN0b3BGZWF0dXJlcygpfX0pO3RhcmdldE1hcC5hZGRMYXllcih7aWQ6cHJlZml4Kyctc3RvcC1jbHVzdGVycycsdHlwZTonY2lyY2xlJyxzb3VyY2U6c3RvcFNvdXJjZSxmaWx0ZXI6WydoYXMnLCdwb2ludF9jb3VudCddLHBhaW50OnsnY2lyY2xlLXJhZGl1cyc6WydzdGVwJyxbJ2dldCcsJ3BvaW50X2NvdW50J10sMjAsMTAsMjUsNDAsMzFdLCdjaXJjbGUtY29sb3InOicjMDcxMzFmJywnY2lyY2xlLXN0cm9rZS1jb2xvcic6JyMwMGQ4ZmYnLCdjaXJjbGUtc3Ryb2tlLXdpZHRoJzozLCdjaXJjbGUtb3BhY2l0eSc6Ljk0fX0pO3RhcmdldE1hcC5hZGRMYXllcih7aWQ6cHJlZml4Kyctc3RvcC1jbHVzdGVyLWNvdW50Jyx0eXBlOidzeW1ib2wnLHNvdXJjZTpzdG9wU291cmNlLGZpbHRlcjpbJ2hhcycsJ3BvaW50X2NvdW50J10sbGF5b3V0OnsndGV4dC1maWVsZCc6WydnZXQnLCdwb2ludF9jb3VudF9hYmJyZXZpYXRlZCddLCd0ZXh0LXNpemUnOjEyfSxwYWludDp7J3RleHQtY29sb3InOicjZmZmZmZmJ319KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOnByZWZpeCsnLXN0b3AtcG9pbnRzJyx0eXBlOidjaXJjbGUnLHNvdXJjZTpzdG9wU291cmNlLGZpbHRlcjpbJyEnLFsnaGFzJywncG9pbnRfY291bnQnXV0scGFpbnQ6eydjaXJjbGUtcmFkaXVzJzoxNywnY2lyY2xlLWNvbG9yJzonIzA3MTMxZicsJ2NpcmNsZS1zdHJva2UtY29sb3InOicjMDBkOGZmJywnY2lyY2xlLXN0cm9rZS13aWR0aCc6MywnY2lyY2xlLW9wYWNpdHknOi45NX19KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOnByZWZpeCsnLXN0b3AtbnVtYmVyJyx0eXBlOidzeW1ib2wnLHNvdXJjZTpzdG9wU291cmNlLGZpbHRlcjpbJyEnLFsnaGFzJywncG9pbnRfY291bnQnXV0sbGF5b3V0OnsndGV4dC1maWVsZCc6Wyd0by1zdHJpbmcnLFsnZ2V0JywnaW5kZXgnXV0sJ3RleHQtc2l6ZSc6MTF9LHBhaW50OnsndGV4dC1jb2xvcic6JyNmZmZmZmYnfX0pO3RhcmdldE1hcC5hZGRTb3VyY2UocGhvdG9Tb3VyY2Use3R5cGU6J2dlb2pzb24nLGNsdXN0ZXI6dHJ1ZSxjbHVzdGVyUmFkaXVzOjQyLGNsdXN0ZXJNYXhab29tOjEzLGRhdGE6e3R5cGU6J0ZlYXR1cmVDb2xsZWN0aW9uJyxmZWF0dXJlczpwaG90b0ZlYXR1cmVzKCl9fSk7dGFyZ2V0TWFwLmFkZExheWVyKHtpZDpwcmVmaXgrJy1waG90by1jbHVzdGVycycsdHlwZTonY2lyY2xlJyxzb3VyY2U6cGhvdG9Tb3VyY2UsZmlsdGVyOlsnaGFzJywncG9pbnRfY291bnQnXSxtaW56b29tOjgscGFpbnQ6eydjaXJjbGUtcmFkaXVzJzpbJ3N0ZXAnLFsnZ2V0JywncG9pbnRfY291bnQnXSwxNSw4LDE5LDI1LDI0XSwnY2lyY2xlLWNvbG9yJzonIzBhMjMzMicsJ2NpcmNsZS1zdHJva2UtY29sb3InOicjN2RlYWZmJywnY2lyY2xlLXN0cm9rZS13aWR0aCc6MiwnY2lyY2xlLW9wYWNpdHknOi44OH19KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOnByZWZpeCsnLXBob3RvLWNsdXN0ZXItY291bnQnLHR5cGU6J3N5bWJvbCcsc291cmNlOnBob3RvU291cmNlLGZpbHRlcjpbJ2hhcycsJ3BvaW50X2NvdW50J10sbWluem9vbTo4LGxheW91dDp7J3RleHQtZmllbGQnOlsnZ2V0JywncG9pbnRfY291bnRfYWJicmV2aWF0ZWQnXSwndGV4dC1zaXplJzoxMH0scGFpbnQ6eyd0ZXh0LWNvbG9yJzonI2ZmZmZmZid9fSk7dGFyZ2V0TWFwLmFkZExheWVyKHtpZDpwcmVmaXgrJy1waG90by1wb2ludHMnLHR5cGU6J2NpcmNsZScsc291cmNlOnBob3RvU291cmNlLGZpbHRlcjpbJyEnLFsnaGFzJywncG9pbnRfY291bnQnXV0sbWluem9vbToxMSxwYWludDp7J2NpcmNsZS1yYWRpdXMnOlsnaW50ZXJwb2xhdGUnLFsnbGluZWFyJ10sWyd6b29tJ10sMTEsNCwxNSw3XSwnY2lyY2xlLWNvbG9yJzonIzAwZDhmZicsJ2NpcmNsZS1zdHJva2UtY29sb3InOicjZmZmZmZmJywnY2lyY2xlLXN0cm9rZS13aWR0aCc6MS41LCdjaXJjbGUtb3BhY2l0eSc6WydpbnRlcnBvbGF0ZScsWydsaW5lYXInXSxbJ3pvb20nXSwxMSwuNjUsMTQsLjksMTUsMF19fSl9CmZ1bmN0aW9uIGV4cGFuZENsdXN0ZXIodGFyZ2V0TWFwLHNvdXJjZUlkLGZlYXR1cmUpe2NvbnN0IHNvdXJjZT10YXJnZXRNYXAuZ2V0U291cmNlKHNvdXJjZUlkKTtpZighc291cmNlKXJldHVybjtjb25zdCBjbHVzdGVySWQ9ZmVhdHVyZS5wcm9wZXJ0aWVzLmNsdXN0ZXJfaWQ7Y29uc3QgcmVzdWx0PXNvdXJjZS5nZXRDbHVzdGVyRXhwYW5zaW9uWm9vbShjbHVzdGVySWQpO2lmKHJlc3VsdCYmdHlwZW9mIHJlc3VsdC50aGVuPT09J2Z1bmN0aW9uJylyZXN1bHQudGhlbih6b29tPT50YXJnZXRNYXAuZWFzZVRvKHtjZW50ZXI6ZmVhdHVyZS5nZW9tZXRyeS5jb29yZGluYXRlcyx6b29tLGR1cmF0aW9uOjcwMH0pKTtlbHNlIHNvdXJjZS5nZXRDbHVzdGVyRXhwYW5zaW9uWm9vbShjbHVzdGVySWQsKGVycix6b29tKT0+e2lmKCFlcnIpdGFyZ2V0TWFwLmVhc2VUbyh7Y2VudGVyOmZlYXR1cmUuZ2VvbWV0cnkuY29vcmRpbmF0ZXMsem9vbSxkdXJhdGlvbjo3MDB9KX0pfQpmdW5jdGlvbiBiaW5kTWFwSW50ZXJhY3Rpb25zKHRhcmdldE1hcCxwcmVmaXgsaXNQcmVzZW50PWZhbHNlKXtjb25zdCBrZXk9J19fdHJpcHB5XycrcHJlZml4O2lmKHRhcmdldE1hcFtrZXldKXJldHVybjt0YXJnZXRNYXBba2V5XT10cnVlO3RhcmdldE1hcC5vbignY2xpY2snLHByZWZpeCsnLXN0b3AtY2x1c3RlcnMnLGU9PmV4cGFuZENsdXN0ZXIodGFyZ2V0TWFwLHByZWZpeCsnLXN0b3BzJyxlLmZlYXR1cmVzWzBdKSk7dGFyZ2V0TWFwLm9uKCdjbGljaycscHJlZml4KyctcGhvdG8tY2x1c3RlcnMnLGU9PmV4cGFuZENsdXN0ZXIodGFyZ2V0TWFwLHByZWZpeCsnLXBob3RvcycsZS5mZWF0dXJlc1swXSkpO3RhcmdldE1hcC5vbignY2xpY2snLHByZWZpeCsnLXN0b3AtcG9pbnRzJyxlPT57Y29uc3QgaWQ9ZS5mZWF0dXJlcz8uWzBdPy5wcm9wZXJ0aWVzPy5zdG9wX2lkO2lmKGlkKXtjb25zdCBpPShwcm9qZWN0Py5zdG9wc3x8W10pLmZpbmRJbmRleChzPT5zLnN0b3BfaWQ9PT1pZCk7aXNQcmVzZW50P2dvUHJlc2VudFN0b3AoaSk6c2VsZWN0U3RvcChpZCx7Zmx5OnRydWUscG9wdXA6dHJ1ZSxmaWx0ZXI6dHJ1ZX0pfX0pO3RhcmdldE1hcC5vbignY2xpY2snLHByZWZpeCsnLXN0b3AtbnVtYmVyJyxlPT57Y29uc3QgaWQ9ZS5mZWF0dXJlcz8uWzBdPy5wcm9wZXJ0aWVzPy5zdG9wX2lkO2lmKGlkKXtjb25zdCBpPShwcm9qZWN0Py5zdG9wc3x8W10pLmZpbmRJbmRleChzPT5zLnN0b3BfaWQ9PT1pZCk7aXNQcmVzZW50P2dvUHJlc2VudFN0b3AoaSk6c2VsZWN0U3RvcChpZCx7Zmx5OnRydWUscG9wdXA6dHJ1ZSxmaWx0ZXI6dHJ1ZX0pfX0pO3RhcmdldE1hcC5vbignY2xpY2snLHByZWZpeCsnLXBob3RvLXBvaW50cycsZT0+e2NvbnN0IGlkPWUuZmVhdHVyZXM/LlswXT8ucHJvcGVydGllcz8uYXNzZXRfaWQ7aWYoaWQpe2lmKGlzUHJlc2VudCl7Y29uc3QgaT1wcmVzZW50QXNzZXRzKCkuZmluZEluZGV4KGE9PmEuYXNzZXRfaWQ9PT1pZCk7aWYoaT49MClnb1ByZXNlbnRQaG90byhpKX1lbHNlIGZvY3VzQXNzZXQoaWQpfX0pO1twcmVmaXgrJy1zdG9wLWNsdXN0ZXJzJyxwcmVmaXgrJy1zdG9wLXBvaW50cycscHJlZml4Kyctc3RvcC1udW1iZXInLHByZWZpeCsnLXBob3RvLWNsdXN0ZXJzJyxwcmVmaXgrJy1waG90by1wb2ludHMnXS5mb3JFYWNoKGxheWVyPT57dGFyZ2V0TWFwLm9uKCdtb3VzZWVudGVyJyxsYXllciwoKT0+dGFyZ2V0TWFwLmdldENhbnZhcygpLnN0eWxlLmN1cnNvcj0ncG9pbnRlcicpO3RhcmdldE1hcC5vbignbW91c2VsZWF2ZScsbGF5ZXIsKCk9PnRhcmdldE1hcC5nZXRDYW52YXMoKS5zdHlsZS5jdXJzb3I9JycpfSl9CmZ1bmN0aW9uIGFzc2V0QnViYmxlRWxlbWVudChhc3NldCxhY3RpdmU9ZmFsc2Upe2NvbnN0IG5vZGU9ZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgnZGl2Jyk7bm9kZS5jbGFzc05hbWU9J2Fzc2V0QnViYmxlJysoYWN0aXZlPycgYWN0aXZlJzonJyk7bm9kZS50aXRsZT1mb3JtYXRBc3NldERhdGVUaW1lKGFzc2V0LnRpbWUpO25vZGUuaW5uZXJIVE1MPWFzc2V0LnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoYXNzZXQudGh1bWIpfSIgYWx0PSIiPmA6JzxkaXYgY2xhc3M9ImFzc2V0RG90Ij7igKI8L2Rpdj4nO3JldHVybiBub2RlfQpmdW5jdGlvbiByZW5kZXJTZWxlY3RlZFBob3RvQnViYmxlcygpe2NsZWFyQnViYmxlTWFya2VycyhwaG90b01hcmtlcnMpO2lmKCFtYXB8fG1hcC5nZXRab29tKCk8MTMuNXx8IWFjdGl2ZVN0b3BJZClyZXR1cm47Y29uc3Qgc3RvcD1wcm9qZWN0Py5zdG9wcz8uZmluZChzPT5zLnN0b3BfaWQ9PT1hY3RpdmVTdG9wSWQpO3N0b3BBc3NldHMoc3RvcCkuZmlsdGVyKHZhbGlkUG9pbnQpLnNsaWNlKDAsMTIwKS5mb3JFYWNoKGFzc2V0PT57Y29uc3Qgbm9kZT1hc3NldEJ1YmJsZUVsZW1lbnQoYXNzZXQsYXNzZXQuYXNzZXRfaWQ9PT1hY3RpdmVBc3NldElkKTtub2RlLm9uY2xpY2s9KCk9PmZvY3VzQXNzZXQoYXNzZXQuYXNzZXRfaWQpO3Bob3RvTWFya2Vycy5wdXNoKG5ldyBtYXBsaWJyZWdsLk1hcmtlcih7ZWxlbWVudDpub2RlLGFuY2hvcjonY2VudGVyJ30pLnNldExuZ0xhdChbTnVtYmVyKGFzc2V0LmxvbiksTnVtYmVyKGFzc2V0LmxhdCldKS5hZGRUbyhtYXApKX0pfQpmdW5jdGlvbiByZW5kZXJNYXAoZml0PWZhbHNlKXtlbnN1cmVNYXAoKTtpZighbWFwLmlzU3R5bGVMb2FkZWQoKSl7bWFwLm9uY2UoJ2xvYWQnLCgpPT5yZW5kZXJNYXAoZml0KSk7cmV0dXJufWNsZWFyTWFwTWFya2VycygpO2NvbnN0IHN0b3BzPXByb2plY3Q/LnN0b3BzfHxbXTtpZighc3RvcHMubGVuZ3RoKXJldHVybjthZGRSb3V0ZUxheWVycyhtYXAsJ21haW4nLHN0b3BzLmZpbHRlcih2YWxpZFBvaW50KS5tYXAocz0+W051bWJlcihzLmxvbiksTnVtYmVyKHMubGF0KV0pKTthZGRDbHVzdGVyTGF5ZXJzKG1hcCwnbWFpbicpO2JpbmRNYXBJbnRlcmFjdGlvbnMobWFwLCdtYWluJyxmYWxzZSk7Y29uc3QgYm91bmRzPW5ldyBtYXBsaWJyZWdsLkxuZ0xhdEJvdW5kcygpO3N0b3BzLmZpbHRlcih2YWxpZFBvaW50KS5mb3JFYWNoKHM9PmJvdW5kcy5leHRlbmQoW051bWJlcihzLmxvbiksTnVtYmVyKHMubGF0KV0pKTtpZihmaXQmJiFib3VuZHMuaXNFbXB0eSgpKXt0cnl7bWFwLmZpdEJvdW5kcyhib3VuZHMse3BhZGRpbmc6e3RvcDo4NSxib3R0b206OTAsbGVmdDo5NSxyaWdodDo5NX0sbWF4Wm9vbToxNC44LGR1cmF0aW9uOjg1MH0pfWNhdGNoe319c2V0VGltZW91dChyZW5kZXJTZWxlY3RlZFBob3RvQnViYmxlcyw4MCl9CmZ1bmN0aW9uIHNldE1hcFN0eWxlKGtleSl7aWYoIU1BUF9TVFlMRVNba2V5XSlyZXR1cm47bWFwU3R5bGVLZXk9a2V5O2xvY2FsU3RvcmFnZS5zZXRJdGVtKCd0cmlwcHlfbWFwX3N0eWxlJyxrZXkpO1snbGlnaHQnLCdkYXJrJywnc2F0ZWxsaXRlJ10uZm9yRWFjaChrPT5lbChrKydNYXBCdXR0b24nKS5jbGFzc0xpc3QudG9nZ2xlKCdhY3RpdmUnLGs9PT1rZXkpKTtlbCgnZGVmYXVsdE1hcFNlbGVjdCcpLnZhbHVlPWtleTtpZihtYXApe21hcC5zZXRTdHlsZShjbG9uZVN0eWxlKGtleSkpO21hcC5vbmNlKCdzdHlsZS5sb2FkJywoKT0+cmVuZGVyTWFwKGZhbHNlKSl9fQpmdW5jdGlvbiBiZWFyaW5nKGEsYil7Y29uc3QgeT1NYXRoLnNpbigoYi5sb24tYS5sb24pKk1hdGguUEkvMTgwKSpNYXRoLmNvcyhiLmxhdCpNYXRoLlBJLzE4MCk7Y29uc3QgeD1NYXRoLmNvcyhhLmxhdCpNYXRoLlBJLzE4MCkqTWF0aC5zaW4oYi5sYXQqTWF0aC5QSS8xODApLU1hdGguc2luKGEubGF0Kk1hdGguUEkvMTgwKSpNYXRoLmNvcyhiLmxhdCpNYXRoLlBJLzE4MCkqTWF0aC5jb3MoKGIubG9uLWEubG9uKSpNYXRoLlBJLzE4MCk7cmV0dXJuKE1hdGguYXRhbjIoeSx4KSoxODAvTWF0aC5QSSszNjApJTM2MH0KZnVuY3Rpb24gc2VsZWN0U3RvcChpZCx7Zmx5PXRydWUscG9wdXA9dHJ1ZSxmaWx0ZXI9dHJ1ZX09e30pe2lmKCFwcm9qZWN0KXJldHVybjtjb25zdCBpbmRleD0ocHJvamVjdC5zdG9wc3x8W10pLmZpbmRJbmRleChzPT5zLnN0b3BfaWQ9PT1pZCk7aWYoaW5kZXg8MClyZXR1cm47Y29uc3Qgc3RvcD1wcm9qZWN0LnN0b3BzW2luZGV4XTthY3RpdmVTdG9wSWQ9aWQ7aWYoZmlsdGVyKWZpbHRlclN0b3BJZD1pZDtyZW5kZXJTdG9wcygpO3JlbmRlckdhbGxlcnkoKTtyZW5kZXJNYXAoZmFsc2UpO2lmKGZseSYmbWFwKXtjb25zdCBuZXh0PXByb2plY3Quc3RvcHNbTWF0aC5taW4oaW5kZXgrMSxwcm9qZWN0LnN0b3BzLmxlbmd0aC0xKV18fHN0b3A7bWFwLmZseVRvKHtjZW50ZXI6W3N0b3AubG9uLHN0b3AubGF0XSx6b29tOjE1LjcscGl0Y2g6NDIsYmVhcmluZzpiZWFyaW5nKHN0b3AsbmV4dCksZHVyYXRpb246MTA1MCxlc3NlbnRpYWw6dHJ1ZX0pfWlmKHBvcHVwKXNldFRpbWVvdXQoKCk9PnNob3dTdG9wUG9wdXAoc3RvcCxpbmRleCksNDUwKX0KZnVuY3Rpb24gc2hvd1N0b3BQb3B1cChzdG9wLGluZGV4KXtpZihhY3RpdmVQb3B1cCl7dHJ5e2FjdGl2ZVBvcHVwLnJlbW92ZSgpfWNhdGNoe319Y29uc3QgYXNzZXRzPXN0b3BBc3NldHMoc3RvcCksZmlyc3Q9YXNzZXRzWzBdO2NvbnN0IGNvbnRlbnQ9YDxkaXYgY2xhc3M9InN0b3BQb3B1cCI+PGRpdiBjbGFzcz0ic3RvcFBvcHVwSW1hZ2UiPiR7Zmlyc3Q/LnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoZmlyc3QudGh1bWIpfSI+YDonJ308L2Rpdj48ZGl2IGNsYXNzPSJzdG9wUG9wdXBCb2R5Ij48c3BhbiBjbGFzcz0icG9wdXBLaWNrZXIiPlN0b3AgJHtpbmRleCsxfTwvc3Bhbj48ZGl2IGNsYXNzPSJwb3B1cFRpdGxlIj4ke2VzYyhzdG9wTmFtZShzdG9wLGluZGV4KSl9PC9kaXY+PGRpdiBjbGFzcz0icG9wdXBNZXRhIj4ke2Fzc2V0cy5sZW5ndGh9IHBob3RvcyZuYnNwOyDigKIgJm5ic3A7JHtNYXRoLnJvdW5kKHN0b3AucmFkaXVzX218fDIwMCl9IG0gcmFkaXVzPC9kaXY+PGRpdiBjbGFzcz0icG9wdXBCdXR0b25zIj48YnV0dG9uIGRhdGEtcG9wdXAtZmlsdGVyPSIke2VzYyhzdG9wLnN0b3BfaWQpfSI+VmlldyBQaG90b3M8L2J1dHRvbj48YnV0dG9uIGRhdGEtcG9wdXAtcHJlc2VudD0iJHtpbmRleH0iPuKWtiBQcmVzZW50PC9idXR0b24+PGJ1dHRvbiBjbGFzcz0iZGFuZ2VyIiBkYXRhLXBvcHVwLWRlbGV0ZT0iJHtlc2Moc3RvcC5zdG9wX2lkKX0iPuKMqzwvYnV0dG9uPjwvZGl2PjwvZGl2PjwvZGl2PmA7YWN0aXZlUG9wdXA9bmV3IG1hcGxpYnJlZ2wuUG9wdXAoe29mZnNldDoyNCxjbG9zZUJ1dHRvbjp0cnVlLG1heFdpZHRoOiczNTBweCd9KS5zZXRMbmdMYXQoW3N0b3AubG9uLHN0b3AubGF0XSkuc2V0SFRNTChjb250ZW50KS5hZGRUbyhtYXApO3NldFRpbWVvdXQoKCk9Pntkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCdbZGF0YS1wb3B1cC1maWx0ZXJdJyk/LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+e2ZpbHRlclN0b3BJZD1zdG9wLnN0b3BfaWQ7cmVuZGVyR2FsbGVyeSgpfSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvcignW2RhdGEtcG9wdXAtcHJlc2VudF0nKT8uYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5vcGVuUHJlc2VudChpbmRleCkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoJ1tkYXRhLXBvcHVwLWRlbGV0ZV0nKT8uYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5kZWxldGVTdG9wKHN0b3Auc3RvcF9pZCkpfSwwKX0KZnVuY3Rpb24gcmVuZGVyU3RvcHMoKXtjb25zdCBzdG9wcz1wcm9qZWN0Py5zdG9wc3x8W10scT1lbCgnc3RvcFNlYXJjaCcpLnZhbHVlLnRyaW0oKS50b0xvd2VyQ2FzZSgpO2VsKCdzdG9wQ291bnQnKS50ZXh0Q29udGVudD1gKCR7c3RvcHMubGVuZ3RofSlgO2VsKCdzdG9wTGlzdCcpLmlubmVySFRNTD1zdG9wcy5tYXAoKHMsaSk9Pih7cyxpfSkpLmZpbHRlcih4PT4hcXx8c3RvcE5hbWUoeC5zLHguaSkudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyhxKSkubWFwKCh7cyxpfSk9Pntjb25zdCBjb3VudD0ocy5hc3NldF9pZHN8fFtdKS5sZW5ndGgsYWN0aXZlPXMuc3RvcF9pZD09PWFjdGl2ZVN0b3BJZDtyZXR1cm5gPGFydGljbGUgY2xhc3M9InN0b3BDYXJkICR7YWN0aXZlPydhY3RpdmUgb3Blbic6Jyd9IiBkYXRhLXN0b3A9IiR7ZXNjKHMuc3RvcF9pZCl9Ij48ZGl2IGNsYXNzPSJzdG9wU3VtbWFyeSI+PGRpdiBjbGFzcz0ic3RvcE51bWJlciI+JHtpKzF9PC9kaXY+PGRpdj48ZGl2IGNsYXNzPSJzdG9wTmFtZSI+JHtlc2Moc3RvcE5hbWUocyxpKSl9PC9kaXY+PGRpdiBjbGFzcz0ic3RvcE1ldGEiPiR7Y291bnR9IHBob3RvcyZuYnNwOyDigKIgJm5ic3A7JHtlc2Moc3RvcERhdGVSYW5nZShzKSl9PC9kaXY+PC9kaXY+PGRpdiBjbGFzcz0ic3RvcENoZXZyb24iPuKAujwvZGl2PjwvZGl2PjxkaXYgY2xhc3M9InN0b3BDb250cm9scyI+PGJ1dHRvbiBkYXRhLXZpZXc9IiR7ZXNjKHMuc3RvcF9pZCl9Ij5WaWV3PC9idXR0b24+PGJ1dHRvbiBkYXRhLXJlbmFtZT0iJHtlc2Mocy5zdG9wX2lkKX0iPlJlbmFtZTwvYnV0dG9uPjxidXR0b24gZGF0YS1yZWNlbnRlcj0iJHtlc2Mocy5zdG9wX2lkKX0iPlJlY2VudGVyPC9idXR0b24+PGJ1dHRvbiBkYXRhLWRlbGV0ZS1zdG9wPSIke2VzYyhzLnN0b3BfaWQpfSI+RGVsZXRlPC9idXR0b24+PC9kaXY+PC9hcnRpY2xlPmB9KS5qb2luKCcnKXx8JzxkaXYgY2xhc3M9InNtYWxsIj5ObyBzdG9wcyBmb3VuZC48L2Rpdj4nO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJy5zdG9wU3VtbWFyeScpLmZvckVhY2gocm93PT5yb3cuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT57Y29uc3QgY2FyZD1yb3cuY2xvc2VzdCgnLnN0b3BDYXJkJyk7Y29uc3QgaWQ9Y2FyZC5kYXRhc2V0LnN0b3A7aWYoYWN0aXZlU3RvcElkPT09aWQpY2FyZC5jbGFzc0xpc3QudG9nZ2xlKCdvcGVuJyk7ZWxzZSBzZWxlY3RTdG9wKGlkLHtmbHk6dHJ1ZSxwb3B1cDp0cnVlLGZpbHRlcjp0cnVlfSl9KSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtdmlld10nKS5mb3JFYWNoKGI9PmIuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5zZWxlY3RTdG9wKGIuZGF0YXNldC52aWV3LHtmbHk6dHJ1ZSxwb3B1cDp0cnVlLGZpbHRlcjp0cnVlfSkpKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1yZW5hbWVdJykuZm9yRWFjaChiPT5iLmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+cmVuYW1lU3RvcChiLmRhdGFzZXQucmVuYW1lKSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXJlY2VudGVyXScpLmZvckVhY2goYj0+Yi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PnJlY2VudGVyU3RvcChiLmRhdGFzZXQucmVjZW50ZXIpKSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtZGVsZXRlLXN0b3BdJykuZm9yRWFjaChiPT5iLmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+ZGVsZXRlU3RvcChiLmRhdGFzZXQuZGVsZXRlU3RvcCkpKX0KZnVuY3Rpb24gZ2FsbGVyeUFzc2V0cygpe2lmKCFwcm9qZWN0KXJldHVybltdO2lmKGZpbHRlclN0b3BJZCl7Y29uc3Qgc3RvcD1wcm9qZWN0LnN0b3BzLmZpbmQocz0+cy5zdG9wX2lkPT09ZmlsdGVyU3RvcElkKTtyZXR1cm4gc3RvcEFzc2V0cyhzdG9wKX1yZXR1cm4gcHJvamVjdC5hc3NldHN8fFtdfQpmdW5jdGlvbiByZW5kZXJHYWxsZXJ5KCl7Y29uc3QgYXNzZXRzPWdhbGxlcnlBc3NldHMoKSxzdG9wPXByb2plY3Q/LnN0b3BzPy5maW5kKHM9PnMuc3RvcF9pZD09PWZpbHRlclN0b3BJZCksaWR4PXN0b3A/cHJvamVjdC5zdG9wcy5pbmRleE9mKHN0b3ApOi0xO2VsKCdtZWRpYVRpdGxlJykudGV4dENvbnRlbnQ9c3RvcD9gU3RvcCAke2lkeCsxfSAg4oCiICAke3N0b3BOYW1lKHN0b3AsaWR4KX1gOidNZWRpYSc7ZWwoJ21lZGlhQ291bnQnKS50ZXh0Q29udGVudD1gJHthc3NldHMubGVuZ3RofSBpdGVtc2A7ZWwoJ2ZpbHRlckNoaXAnKS5jbGFzc0xpc3QudG9nZ2xlKCdzaG93JywhIXN0b3ApO2VsKCdmaWx0ZXJDaGlwVGV4dCcpLnRleHRDb250ZW50PXN0b3A/YEZpbHRlcjogJHtzdG9wTmFtZShzdG9wLGlkeCl9YDonRmlsdGVyOiBBbGwgU3RvcHMnO2VsKCdnYWxsZXJ5JykuaW5uZXJIVE1MPWFzc2V0cy5tYXAoKGEsaSk9PmA8ZGl2IGNsYXNzPSJtZWRpYVRpbGUgJHthLmFzc2V0X2lkPT09YWN0aXZlQXNzZXRJZD8nYWN0aXZlJzonJ30iIGRhdGEtYXNzZXQ9IiR7ZXNjKGEuYXNzZXRfaWQpfSI+JHthLnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoYS50aHVtYil9Ij5gOicnfTxidXR0b24gY2xhc3M9Im1lZGlhVGlsZVJlbW92ZSIgZGF0YS1yZW1vdmUtYXNzZXQ9IiR7ZXNjKGEuYXNzZXRfaWQpfSIgdGl0bGU9IlJlbW92ZSBmcm9tIGpvdXJuZXkiPsOXPC9idXR0b24+PGRpdiBjbGFzcz0ibWVkaWFUaWxlTmFtZSI+JHtlc2MoZm9ybWF0QXNzZXREYXRlVGltZShhLnRpbWUpfHxgUGhvdG8gJHtpKzF9YCl9PC9kaXY+PC9kaXY+YCkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gR1BTIG1lZGlhIGluIHRoaXMgdmlldy48L2Rpdj4nO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJy5tZWRpYVRpbGUnKS5mb3JFYWNoKHRpbGU9PnRpbGUuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5mb2N1c0Fzc2V0KHRpbGUuZGF0YXNldC5hc3NldCkpKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1yZW1vdmUtYXNzZXRdJykuZm9yRWFjaChidXR0b249PmJ1dHRvbi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsZXZlbnQ9PntldmVudC5zdG9wUHJvcGFnYXRpb24oKTtyZW1vdmVBc3NldEZyb21Kb3VybmV5KGJ1dHRvbi5kYXRhc2V0LnJlbW92ZUFzc2V0KX0pKX0KZnVuY3Rpb24gZm9jdXNBc3NldChpZCl7Y29uc3QgYXNzZXQ9KHByb2plY3Q/LmFzc2V0c3x8W10pLmZpbmQoYT0+YS5hc3NldF9pZD09PWlkKTtpZighYXNzZXR8fCF2YWxpZFBvaW50KGFzc2V0KSlyZXR1cm47YWN0aXZlQXNzZXRJZD1pZDtyZW5kZXJHYWxsZXJ5KCk7cmVuZGVyU2VsZWN0ZWRQaG90b0J1YmJsZXMoKTtpZihtYXApbWFwLmZseVRvKHtjZW50ZXI6W051bWJlcihhc3NldC5sb24pLE51bWJlcihhc3NldC5sYXQpXSx6b29tOjE4LjcscGl0Y2g6NTAsYmVhcmluZzoxMCxkdXJhdGlvbjo5NTAsZXNzZW50aWFsOnRydWV9KTtpZihhY3RpdmVQb3B1cCl7dHJ5e2FjdGl2ZVBvcHVwLnJlbW92ZSgpfWNhdGNoe319YWN0aXZlUG9wdXA9bmV3IG1hcGxpYnJlZ2wuUG9wdXAoe29mZnNldDoyNCxjbG9zZUJ1dHRvbjp0cnVlLG1heFdpZHRoOic0MjBweCd9KS5zZXRMbmdMYXQoW051bWJlcihhc3NldC5sb24pLE51bWJlcihhc3NldC5sYXQpXSkuc2V0SFRNTChgPGRpdiBjbGFzcz0ic3RvcFBvcHVwIj48ZGl2IGNsYXNzPSJzdG9wUG9wdXBJbWFnZSI+JHthc3NldC50aHVtYj9gPGltZyBzcmM9IiR7ZXNjKGFzc2V0LnRodW1iKX0iPmA6Jyd9PC9kaXY+PGRpdiBjbGFzcz0ic3RvcFBvcHVwQm9keSI+PHNwYW4gY2xhc3M9InBvcHVwS2lja2VyIj5TZWxlY3RlZCBwaG90bzwvc3Bhbj48ZGl2IGNsYXNzPSJwb3B1cFRpdGxlIj4ke2VzYyhhc3NldC5uYW1lfHwnUGhvdG8nKX08L2Rpdj48ZGl2IGNsYXNzPSJwb3B1cE1ldGEiPiR7ZXNjKGZvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSkpfTwvZGl2PjwvZGl2PjwvZGl2PmApLmFkZFRvKG1hcCl9CmFzeW5jIGZ1bmN0aW9uIHNhdmVQcm9qZWN0KCl7aWYoIXByb2plY3QpcmV0dXJuO3Byb2plY3Q9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytlbmNvZGVVUklDb21wb25lbnQocHJvamVjdC5pZCkse21ldGhvZDonUFVUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkocHJvamVjdCl9KTthd2FpdCByZWZyZXNoUHJvamVjdFN1bW1hcnkoKTtyZW5kZXJBbGwoKX1hc3luYyBmdW5jdGlvbiByZW1vdmVBc3NldEZyb21Kb3VybmV5KGFzc2V0SWQpe2lmKCFwcm9qZWN0KXJldHVybjtjb25zdCBhc3NldD0ocHJvamVjdC5hc3NldHN8fFtdKS5maW5kKGE9PmEuYXNzZXRfaWQ9PT1hc3NldElkKTtpZighYXNzZXQpcmV0dXJuO2lmKCFjb25maXJtKCdSZW1vdmUgdGhpcyBpbWFnZSBmcm9tIHRoaXMgVHJpcHB5IGpvdXJuZXk/IFRoZSBvcmlnaW5hbCBmaWxlIHdpbGwgcmVtYWluIHVudG91Y2hlZCBpbiBJbW1pY2guJykpcmV0dXJuO3Byb2plY3QuYXNzZXRzPShwcm9qZWN0LmFzc2V0c3x8W10pLmZpbHRlcihhPT5hLmFzc2V0X2lkIT09YXNzZXRJZCk7cHJvamVjdC5zdG9wcz0ocHJvamVjdC5zdG9wc3x8W10pLm1hcChzdG9wPT57Y29uc3QgaWRzPShzdG9wLmFzc2V0X2lkc3x8W10pLmZpbHRlcihpZD0+aWQhPT1hc3NldElkKTtpZighaWRzLmxlbmd0aClyZXR1cm4gbnVsbDtjb25zdCBwb2ludHM9cHJvamVjdC5hc3NldHMuZmlsdGVyKGE9Pmlkcy5pbmNsdWRlcyhhLmFzc2V0X2lkKSYmdmFsaWRQb2ludChhKSk7aWYocG9pbnRzLmxlbmd0aCl7c3RvcC5sYXQ9cG9pbnRzLnJlZHVjZSgoc3VtLGEpPT5zdW0rTnVtYmVyKGEubGF0KSwwKS9wb2ludHMubGVuZ3RoO3N0b3AubG9uPXBvaW50cy5yZWR1Y2UoKHN1bSxhKT0+c3VtK051bWJlcihhLmxvbiksMCkvcG9pbnRzLmxlbmd0aH1zdG9wLmFzc2V0X2lkcz1pZHM7cmV0dXJuIHN0b3B9KS5maWx0ZXIoQm9vbGVhbik7YWN0aXZlQXNzZXRJZD1udWxsO2lmKGZpbHRlclN0b3BJZCYmIXByb2plY3Quc3RvcHMuc29tZShzPT5zLnN0b3BfaWQ9PT1maWx0ZXJTdG9wSWQpKWZpbHRlclN0b3BJZD1udWxsO2F3YWl0IHNhdmVQcm9qZWN0KCk7dG9hc3QoJ1JlbW92ZWQgZnJvbSB0aGlzIGpvdXJuZXkuIFRoZSBvcmlnaW5hbCByZW1haW5zIGluIEltbWljaC4nKTtpZihlbCgncHJlc2VudE92ZXJsYXknKS5jbGFzc0xpc3QuY29udGFpbnMoJ3Nob3cnKSl7aWYoIXByb2plY3Quc3RvcHMubGVuZ3RoKXtjbG9zZVByZXNlbnQoKTtyZXR1cm59cHJlc2VudFN0b3BJbmRleD1NYXRoLm1pbihwcmVzZW50U3RvcEluZGV4LHByb2plY3Quc3RvcHMubGVuZ3RoLTEpO2NvbnN0IGFzc2V0cz1wcmVzZW50QXNzZXRzKCk7cHJlc2VudFBob3RvSW5kZXg9TWF0aC5taW4ocHJlc2VudFBob3RvSW5kZXgsYXNzZXRzLmxlbmd0aC0xKTtyZW5kZXJQcmVzZW50TWFwTGF5ZXJzKCk7aWYocHJlc2VudFBob3RvSW5kZXg+PTAmJmFzc2V0cy5sZW5ndGgpZ29QcmVzZW50UGhvdG8ocHJlc2VudFBob3RvSW5kZXgpO2Vsc2UgZ29QcmVzZW50U3RvcChwcmVzZW50U3RvcEluZGV4KX19CmFzeW5jIGZ1bmN0aW9uIHJlZnJlc2hQcm9qZWN0U3VtbWFyeSgpe3Byb2plY3RzPWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0cycpfQphc3luYyBmdW5jdGlvbiByZW5hbWVQcm9qZWN0KCl7aWYoIXByb2plY3QpcmV0dXJuO2NvbnN0IHZhbHVlPXByb21wdCgnSm91cm5leSBuYW1lJyxwcm9qZWN0Lm5hbWV8fCcnKTtpZighdmFsdWU/LnRyaW0oKSlyZXR1cm47cHJvamVjdC5uYW1lPXZhbHVlLnRyaW0oKTtwcm9qZWN0LnNldHRpbmdzPXByb2plY3Quc2V0dGluZ3N8fHt9O3Byb2plY3Quc2V0dGluZ3MudGl0bGU9cHJvamVjdC5uYW1lO2F3YWl0IHNhdmVQcm9qZWN0KCl9CmFzeW5jIGZ1bmN0aW9uIHJlbmFtZVN0b3AoaWQpe2NvbnN0IGk9cHJvamVjdC5zdG9wcy5maW5kSW5kZXgocz0+cy5zdG9wX2lkPT09aWQpO2lmKGk8MClyZXR1cm47Y29uc3QgdmFsdWU9cHJvbXB0KCdTdG9wIG5hbWUnLHN0b3BOYW1lKHByb2plY3Quc3RvcHNbaV0saSkpO2lmKCF2YWx1ZT8udHJpbSgpKXJldHVybjtwcm9qZWN0LnN0b3BzW2ldLm5hbWU9dmFsdWUudHJpbSgpO2F3YWl0IHNhdmVQcm9qZWN0KCl9CmFzeW5jIGZ1bmN0aW9uIHJlY2VudGVyU3RvcChpZCl7Y29uc3Qgc3RvcD1wcm9qZWN0LnN0b3BzLmZpbmQocz0+cy5zdG9wX2lkPT09aWQpLGFzc2V0cz1zdG9wQXNzZXRzKHN0b3ApO2lmKCFzdG9wfHwhYXNzZXRzLmxlbmd0aClyZXR1cm4gdG9hc3QoJ1RoaXMgc3RvcCBoYXMgbm8gcGhvdG9zIHRvIHJlY2VudGVyIGZyb20uJyk7c3RvcC5sYXQ9YXNzZXRzLnJlZHVjZSgobixhKT0+bitOdW1iZXIoYS5sYXQpLDApL2Fzc2V0cy5sZW5ndGg7c3RvcC5sb249YXNzZXRzLnJlZHVjZSgobixhKT0+bitOdW1iZXIoYS5sb24pLDApL2Fzc2V0cy5sZW5ndGg7YXdhaXQgc2F2ZVByb2plY3QoKTtzZWxlY3RTdG9wKGlkLHtmbHk6dHJ1ZSxwb3B1cDp0cnVlLGZpbHRlcjp0cnVlfSl9CmFzeW5jIGZ1bmN0aW9uIGRlbGV0ZVN0b3AoaWQpe2lmKCFjb25maXJtKCdEZWxldGUgdGhpcyBzdG9wPyBQaG90b3MgcmVtYWluIGluIHRoZSBqb3VybmV5LicpKXJldHVybjtwcm9qZWN0LnN0b3BzPXByb2plY3Quc3RvcHMuZmlsdGVyKHM9PnMuc3RvcF9pZCE9PWlkKTtpZihhY3RpdmVTdG9wSWQ9PT1pZClhY3RpdmVTdG9wSWQ9cHJvamVjdC5zdG9wc1swXT8uc3RvcF9pZHx8bnVsbDtpZihmaWx0ZXJTdG9wSWQ9PT1pZClmaWx0ZXJTdG9wSWQ9YWN0aXZlU3RvcElkO2F3YWl0IHNhdmVQcm9qZWN0KCl9CmFzeW5jIGZ1bmN0aW9uIGFkZFN0b3AoKXtpZighcHJvamVjdHx8IW1hcClyZXR1cm4gdG9hc3QoJ0xvYWQgYSBqb3VybmV5IGZpcnN0LicpO2NvbnN0IGNlbnRlcj1tYXAuZ2V0Q2VudGVyKCk7cHJvamVjdC5zdG9wcz1wcm9qZWN0LnN0b3BzfHxbXTtjb25zdCBzdG9wPXtzdG9wX2lkOmNyeXB0by5yYW5kb21VVUlEKCkuc2xpY2UoMCw4KSxuYW1lOmBTdG9wICR7cHJvamVjdC5zdG9wcy5sZW5ndGgrMX1gLGxhdDpjZW50ZXIubGF0LGxvbjpjZW50ZXIubG5nLHJhZGl1c19tOk51bWJlcihwcm9qZWN0LnNldHRpbmdzPy5zdG9wX3JhZGl1c19tfHwyMDApLGFzc2V0X2lkczpbXSxtb2RlOidtYW51YWwnLGxvY2tlZDpmYWxzZX07cHJvamVjdC5zdG9wcy5wdXNoKHN0b3ApO2F3YWl0IHNhdmVQcm9qZWN0KCk7c2VsZWN0U3RvcChzdG9wLnN0b3BfaWQse2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KX0KYXN5bmMgZnVuY3Rpb24gcmVjbHVzdGVyKCl7aWYoIXByb2plY3QpcmV0dXJuO2NvbnN0IHJhZGl1cz1OdW1iZXIoZWwoJ3N0b3BSYWRpdXMnKS52YWx1ZXx8MjAwKTtwcm9qZWN0PWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KHByb2plY3QuaWQpKycvcmVjbHVzdGVyJyx7bWV0aG9kOidQT1NUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkoe3JhZGl1c19tOnJhZGl1c30pfSk7cHJvamVjdC5zZXR0aW5ncz1wcm9qZWN0LnNldHRpbmdzfHx7fTtwcm9qZWN0LnNldHRpbmdzLnN0b3BfcmFkaXVzX209cmFkaXVzO2FjdGl2ZVN0b3BJZD1wcm9qZWN0LnN0b3BzWzBdPy5zdG9wX2lkfHxudWxsO2ZpbHRlclN0b3BJZD1hY3RpdmVTdG9wSWQ7YXdhaXQgcmVmcmVzaFByb2plY3RTdW1tYXJ5KCk7cmVuZGVyQWxsKCk7c2V0TW9kYWwoJ3NldHRpbmdzTW9kYWwnLGZhbHNlKTt0b2FzdCgnU3RvcHMgcmVjbHVzdGVyZWQnKX0KYXN5bmMgZnVuY3Rpb24gcmV2ZXJzZVJvdXRlKCl7aWYoIXByb2plY3QpcmV0dXJuO3Byb2plY3Quc3RvcHMucmV2ZXJzZSgpO3Byb2plY3Quc2V0dGluZ3M9cHJvamVjdC5zZXR0aW5nc3x8e307cHJvamVjdC5zZXR0aW5ncy5yZXZlcnNlX3JvdXRlPSFwcm9qZWN0LnNldHRpbmdzLnJldmVyc2Vfcm91dGU7YXdhaXQgc2F2ZVByb2plY3QoKTt0b2FzdCgnUm91dGUgb3JkZXIgcmV2ZXJzZWQnKX0KYXN5bmMgZnVuY3Rpb24gdGVzdEltbWljaCgpe2NvbnN0IGJvZHk9e2Jhc2VfdXJsOmVsKCdpbW1pY2hVcmwnKS52YWx1ZS50cmltKCksYXBpX2tleTplbCgnaW1taWNoS2V5JykudmFsdWUudHJpbSgpfTtjb25zdCByZXN1bHQ9YXdhaXQgYXBpKCcvYXBpL2ltbWljaC90ZXN0Jyx7bWV0aG9kOidQT1NUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkoYm9keSl9KTt0b2FzdChyZXN1bHQubWVzc2FnZXx8J0Nvbm5lY3Rpb24gdGVzdGVkJyl9CmFzeW5jIGZ1bmN0aW9uIGNyZWF0ZUltbWljaEpvdXJuZXkoKXtjb25zdCBiYXNlX3VybD1lbCgnaW1taWNoVXJsJykudmFsdWUudHJpbSgpLGFwaV9rZXk9ZWwoJ2ltbWljaEtleScpLnZhbHVlLnRyaW0oKSxzdGFydF9kYXRlPWVsKCdzdGFydERhdGUnKS52YWx1ZSxlbmRfZGF0ZT1lbCgnZW5kRGF0ZScpLnZhbHVlO2lmKCFiYXNlX3VybHx8IWFwaV9rZXl8fCFzdGFydF9kYXRlfHwhZW5kX2RhdGUpcmV0dXJuIHRvYXN0KCdDb21wbGV0ZSB0aGUgSW1taWNoIFVSTCwga2V5LCBhbmQgZGF0ZXMuJyk7c2F2ZUNvbm4oYmFzZV91cmwsYXBpX2tleSk7dG9hc3QoJ0ltcG9ydGluZyBHUFMgbWVkaWEgZnJvbSBJbW1pY2jigKYnKTtjb25zdCBjcmVhdGVkPWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0L2ltbWljaCcse21ldGhvZDonUE9TVCcsaGVhZGVyczp7J0NvbnRlbnQtVHlwZSc6J2FwcGxpY2F0aW9uL2pzb24nfSxib2R5OkpTT04uc3RyaW5naWZ5KHtuYW1lOmBJbW1pY2ggSm91cm5leSAke3N0YXJ0X2RhdGV9IHRvICR7ZW5kX2RhdGV9YCxiYXNlX3VybCxhcGlfa2V5LHN0YXJ0X2RhdGUsZW5kX2RhdGV9KX0pO3NldE1vZGFsKCdpbW1pY2hNb2RhbCcsZmFsc2UpO2F3YWl0IHJlZnJlc2hQcm9qZWN0U3VtbWFyeSgpO2F3YWl0IG9wZW5Qcm9qZWN0KGNyZWF0ZWQuaWQpfQphc3luYyBmdW5jdGlvbiBjcmVhdGVVcGxvYWRKb3VybmV5KCl7Y29uc3QgZmlsZXM9ZWwoJ3VwbG9hZEZpbGVzJykuZmlsZXM7aWYoIWZpbGVzLmxlbmd0aClyZXR1cm4gdG9hc3QoJ0Nob29zZSBtZWRpYSBmaWxlcyBmaXJzdC4nKTtjb25zdCBmb3JtPW5ldyBGb3JtRGF0YSgpO2Zvcihjb25zdCBmaWxlIG9mIGZpbGVzKWZvcm0uYXBwZW5kKCdmaWxlcycsZmlsZSk7Zm9ybS5hcHBlbmQoJ25hbWUnLGVsKCd1cGxvYWROYW1lJykudmFsdWUudHJpbSgpfHwnVXBsb2FkZWQgSm91cm5leScpO3RvYXN0KCdSZWFkaW5nIEdQUyBtZXRhZGF0YeKApicpO2NvbnN0IGNyZWF0ZWQ9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvdXBsb2FkJyx7bWV0aG9kOidQT1NUJyxib2R5OmZvcm19KTtzZXRNb2RhbCgndXBsb2FkTW9kYWwnLGZhbHNlKTthd2FpdCByZWZyZXNoUHJvamVjdFN1bW1hcnkoKTthd2FpdCBvcGVuUHJvamVjdChjcmVhdGVkLmlkKX0KYXN5bmMgZnVuY3Rpb24gcmVuZGVyTXA0KCl7aWYoIXByb2plY3QpcmV0dXJuIHRvYXN0KCdMb2FkIGEgam91cm5leSBmaXJzdC4nKTtwcm9qZWN0LnNldHRpbmdzPXByb2plY3Quc2V0dGluZ3N8fHt9O3Byb2plY3Quc2V0dGluZ3MuZHVyYXRpb25fbWluPTEyO2F3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KHByb2plY3QuaWQpLHttZXRob2Q6J1BVVCcsaGVhZGVyczp7J0NvbnRlbnQtVHlwZSc6J2FwcGxpY2F0aW9uL2pzb24nfSxib2R5OkpTT04uc3RyaW5naWZ5KHByb2plY3QpfSk7Y29uc3QgZm9ybT1uZXcgRm9ybURhdGEoKTtpZihlbCgnYXVkaW9Td2l0Y2gnKS5jbGFzc0xpc3QuY29udGFpbnMoJ29uJykmJmVsKCdhdWRpb0lucHV0JykuZmlsZXNbMF0pZm9ybS5hcHBlbmQoJ2F1ZGlvJyxlbCgnYXVkaW9JbnB1dCcpLmZpbGVzWzBdKTt0b2FzdCgnUmVuZGVyaW5nIE1QNOKApicpO2NvbnN0IHJlc3VsdD1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdC8nK2VuY29kZVVSSUNvbXBvbmVudChwcm9qZWN0LmlkKSsnL3JlbmRlcicse21ldGhvZDonUE9TVCcsYm9keTpmb3JtfSk7Y29uc3QgdXJsPXJlc3VsdC51cmx8fHJlc3VsdC5wYXRofHxyZXN1bHQuZG93bmxvYWRfdXJsO2lmKHVybCl3aW5kb3cub3Blbih1cmwsJ19ibGFuaycpO3RvYXN0KCdSZW5kZXIgY29tcGxldGUnKX0KZnVuY3Rpb24gZW5zdXJlUHJlc2VudE1hcCgpe2lmKHByZXNlbnRNYXApcmV0dXJuO3ByZXNlbnRNYXA9bmV3IG1hcGxpYnJlZ2wuTWFwKHtjb250YWluZXI6J3ByZXNlbnRNYXAnLHN0eWxlOmNsb25lU3R5bGUobWFwU3R5bGVLZXk9PT0nbGlnaHQnPydzYXRlbGxpdGUnOm1hcFN0eWxlS2V5KSxjZW50ZXI6Wy05OCwzOV0sem9vbTozLG1heFpvb206MjAscGl0Y2g6NTUsYmVhcmluZzowfSk7cHJlc2VudE1hcC5hZGRDb250cm9sKG5ldyBtYXBsaWJyZWdsLk5hdmlnYXRpb25Db250cm9sKCksJ2JvdHRvbS1yaWdodCcpO3ByZXNlbnRNYXAub24oJ3pvb21lbmQnLHJlbmRlclByZXNlbnRQaG90b0J1YmJsZXMpO3ByZXNlbnRNYXAub24oJ21vdmVlbmQnLHJlbmRlclByZXNlbnRQaG90b0J1YmJsZXMpO3ByZXNlbnRNYXAub24oJ2Vycm9yJyxldmVudD0+e2NvbnN0IG1lc3NhZ2U9U3RyaW5nKGV2ZW50Py5lcnJvcj8ubWVzc2FnZXx8JycpO2lmKG1hcFN0eWxlS2V5PT09J3NhdGVsbGl0ZScmJi90aWxlfHNvdXJjZXw0MDR8NDAzL2kudGVzdChtZXNzYWdlKSl7dG9hc3QoJ1NhdGVsbGl0ZSBpbWFnZXJ5IGlzIGxpbWl0ZWQgaGVyZTsgdXNpbmcgdGhlIGNsb3Nlc3QgYXZhaWxhYmxlIHRpbGUuJyl9fSl9CmZ1bmN0aW9uIHByZXNlbnRBc3NldHMoKXtjb25zdCBzdG9wPXByb2plY3Q/LnN0b3BzPy5bcHJlc2VudFN0b3BJbmRleF07cmV0dXJuIHN0b3BBc3NldHMoc3RvcCl9CmZ1bmN0aW9uIHJlbmRlclByZXNlbnRTdG9wcygpe2NvbnN0IHN0b3BzPXByb2plY3Q/LnN0b3BzfHxbXTtlbCgncHJlc2VudFN0b3BSYWlsJykuaW5uZXJIVE1MPWA8ZGl2IHN0eWxlPSJmb250LXdlaWdodDo5NTA7bWFyZ2luOjJweCA0cHggMTBweCI+Sm91cm5leSBTdG9wczwvZGl2PmArc3RvcHMubWFwKChzLGkpPT5gPGRpdiBjbGFzcz0icHJlc2VudFN0b3BJdGVtICR7aT09PXByZXNlbnRTdG9wSW5kZXg/J2FjdGl2ZSc6Jyd9IiBkYXRhLXByZXNlbnQtc3RvcD0iJHtpfSI+PGI+JHtpKzF9LjwvYj4mbmJzcDsgJHtlc2Moc3RvcE5hbWUocyxpKSl9PGRpdiBjbGFzcz0ic21hbGwiPiR7KHMuYXNzZXRfaWRzfHxbXSkubGVuZ3RofSBwaG90b3M8YnI+JHtlc2Moc3RvcERhdGVSYW5nZShzKSl9PC9kaXY+PC9kaXY+YCkuam9pbignJyk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtcHJlc2VudC1zdG9wXScpLmZvckVhY2goeD0+eC5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PmdvUHJlc2VudFN0b3AoTnVtYmVyKHguZGF0YXNldC5wcmVzZW50U3RvcCkpKSl9CmZ1bmN0aW9uIHJlbmRlclByZXNlbnRGaWxtc3RyaXAoKXtjb25zdCBhc3NldHM9cHJlc2VudEFzc2V0cygpO2VsKCdwcmVzZW50RmlsbXN0cmlwJykuaW5uZXJIVE1MPWFzc2V0cy5tYXAoKGEsaSk9PmA8ZGl2IGNsYXNzPSJwcmVzZW50VGh1bWIgJHtpPT09cHJlc2VudFBob3RvSW5kZXg/J2FjdGl2ZSc6Jyd9IiBkYXRhLXByZXNlbnQtcGhvdG89IiR7aX0iPiR7YS50aHVtYj9gPGltZyBzcmM9IiR7ZXNjKGEudGh1bWIpfSI+YDonJ308ZGl2IGNsYXNzPSJwcmVzZW50VGh1bWJMYWJlbCI+UGhvdG8gJHtpKzF9PGJyPiR7ZXNjKGZvcm1hdEFzc2V0RGF0ZVRpbWUoYS50aW1lKSl9PC9kaXY+PC9kaXY+YCkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gcGhvdG9zIGFzc2lnbmVkIHRvIHRoaXMgc3RvcC48L2Rpdj4nO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXByZXNlbnQtcGhvdG9dJykuZm9yRWFjaCh4PT54LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+Z29QcmVzZW50UGhvdG8oTnVtYmVyKHguZGF0YXNldC5wcmVzZW50UGhvdG8pKSkpfQpmdW5jdGlvbiByZW5kZXJQcmVzZW50TWFwTGF5ZXJzKCl7aWYoIXByZXNlbnRNYXB8fCFwcmVzZW50TWFwLmlzU3R5bGVMb2FkZWQoKSlyZXR1cm47Y2xlYXJCdWJibGVNYXJrZXJzKHByZXNlbnRNYXJrZXJzKTtjbGVhckJ1YmJsZU1hcmtlcnMocHJlc2VudFBob3RvTWFya2Vycyk7Y29uc3Qgc3RvcHM9cHJvamVjdD8uc3RvcHN8fFtdO2FkZFJvdXRlTGF5ZXJzKHByZXNlbnRNYXAsJ3ByZXNlbnQnLHN0b3BzLmZpbHRlcih2YWxpZFBvaW50KS5tYXAocz0+W051bWJlcihzLmxvbiksTnVtYmVyKHMubGF0KV0pKTthZGRDbHVzdGVyTGF5ZXJzKHByZXNlbnRNYXAsJ3ByZXNlbnQnKTtiaW5kTWFwSW50ZXJhY3Rpb25zKHByZXNlbnRNYXAsJ3ByZXNlbnQnLHRydWUpO3JlbmRlclByZXNlbnRQaG90b0J1YmJsZXMoKX0KZnVuY3Rpb24gcmVuZGVyUHJlc2VudFBob3RvQnViYmxlcygpe2NsZWFyQnViYmxlTWFya2VycyhwcmVzZW50UGhvdG9NYXJrZXJzKTtpZighcHJlc2VudE1hcHx8IXByb2plY3Q/LnN0b3BzPy5sZW5ndGgpcmV0dXJuO2NvbnN0IGFsbD1wcmVzZW50QXNzZXRzKCk7YWxsLmZpbHRlcih2YWxpZFBvaW50KS5zbGljZSgwLDE0MCkuZm9yRWFjaChhc3NldD0+e2NvbnN0IGk9YWxsLmZpbmRJbmRleChhPT5hLmFzc2V0X2lkPT09YXNzZXQuYXNzZXRfaWQpO2NvbnN0IG5vZGU9YXNzZXRCdWJibGVFbGVtZW50KGFzc2V0LGk9PT1wcmVzZW50UGhvdG9JbmRleCk7bm9kZS5vbmNsaWNrPSgpPT5nb1ByZXNlbnRQaG90byhpKTtwcmVzZW50UGhvdG9NYXJrZXJzLnB1c2gobmV3IG1hcGxpYnJlZ2wuTWFya2VyKHtlbGVtZW50Om5vZGUsYW5jaG9yOidjZW50ZXInfSkuc2V0TG5nTGF0KFtOdW1iZXIoYXNzZXQubG9uKSxOdW1iZXIoYXNzZXQubGF0KV0pLmFkZFRvKHByZXNlbnRNYXApKX0pfWZ1bmN0aW9uIHN0b3BQcmVzZW50T3JiaXQoKXtjbGVhclRpbWVvdXQocHJlc2VudE9yYml0RGVsYXkpO2NsZWFySW50ZXJ2YWwocHJlc2VudE9yYml0VGltZXIpO3ByZXNlbnRPcmJpdERlbGF5PW51bGw7cHJlc2VudE9yYml0VGltZXI9bnVsbH1mdW5jdGlvbiBzdGFydFByZXNlbnRPcmJpdChjZW50ZXIsem9vbSxwaXRjaD01Nil7c3RvcFByZXNlbnRPcmJpdCgpO2NvbnN0IG9yYml0PSgpPT57aWYoIXByZXNlbnRNYXB8fCFlbCgncHJlc2VudE92ZXJsYXknKS5jbGFzc0xpc3QuY29udGFpbnMoJ3Nob3cnKSlyZXR1cm47cHJlc2VudE1hcC5lYXNlVG8oe2NlbnRlcix6b29tOk1hdGgubWluKHpvb20sMTguMTUpLHBpdGNoLGJlYXJpbmc6KHByZXNlbnRNYXAuZ2V0QmVhcmluZygpKzE2KSUzNjAsZHVyYXRpb246NTIwMCxlYXNpbmc6dD0+dCxlc3NlbnRpYWw6dHJ1ZX0pfTtwcmVzZW50T3JiaXREZWxheT1zZXRUaW1lb3V0KCgpPT57b3JiaXQoKTtwcmVzZW50T3JiaXRUaW1lcj1zZXRJbnRlcnZhbChvcmJpdCw1MjUwKX0sMTI1MCl9ZnVuY3Rpb24gY2xlYXJQcmVzZW50Rm9jdXMoKXtpZihwcmVzZW50Rm9jdXNNYXJrZXIpe3ByZXNlbnRGb2N1c01hcmtlci5yZW1vdmUoKTtwcmVzZW50Rm9jdXNNYXJrZXI9bnVsbH19ZnVuY3Rpb24gc2hvd1ByZXNlbnRGb2N1cyhpdGVtKXtjbGVhclByZXNlbnRGb2N1cygpO2lmKCF2YWxpZFBvaW50KGl0ZW0pfHwhcHJlc2VudE1hcClyZXR1cm47Y29uc3Qgbm9kZT1kb2N1bWVudC5jcmVhdGVFbGVtZW50KCdkaXYnKTtub2RlLmNsYXNzTmFtZT0nZm9jdXNQdWxzZSc7cHJlc2VudEZvY3VzTWFya2VyPW5ldyBtYXBsaWJyZWdsLk1hcmtlcih7ZWxlbWVudDpub2RlLGFuY2hvcjonY2VudGVyJ30pLnNldExuZ0xhdChbTnVtYmVyKGl0ZW0ubG9uKSxOdW1iZXIoaXRlbS5sYXQpXSkuYWRkVG8ocHJlc2VudE1hcCl9ZnVuY3Rpb24gdHJpcEJvdW5kcygpe2NvbnN0IGJvdW5kcz1uZXcgbWFwbGlicmVnbC5MbmdMYXRCb3VuZHMoKTsocHJvamVjdD8uc3RvcHN8fFtdKS5maWx0ZXIodmFsaWRQb2ludCkuZm9yRWFjaChzPT5ib3VuZHMuZXh0ZW5kKFtOdW1iZXIocy5sb24pLE51bWJlcihzLmxhdCldKSk7cmV0dXJuIGJvdW5kc31mdW5jdGlvbiBjZW50ZXJQcmVzZW50VHJpcCgpe2lmKCFwcmVzZW50TWFwfHwhcHJvamVjdD8uc3RvcHM/Lmxlbmd0aClyZXR1cm47c3RvcFByZXNlbnRPcmJpdCgpO3ByZXNlbnRWaWV3PSd0cmlwJztjb25zdCBib3VuZHM9dHJpcEJvdW5kcygpO2lmKCFib3VuZHMuaXNFbXB0eSgpKXByZXNlbnRNYXAuZml0Qm91bmRzKGJvdW5kcyx7cGFkZGluZzp7dG9wOjExMCxib3R0b206MTEwLGxlZnQ6Mjg1LHJpZ2h0OjgwfSxtYXhab29tOjEyLjgsZHVyYXRpb246MTUwMCxlc3NlbnRpYWw6dHJ1ZX0pO2NvbnN0IHNlbGVjdGVkPXByZXNlbnRQaG90b0luZGV4Pj0wP3ByZXNlbnRBc3NldHMoKVtwcmVzZW50UGhvdG9JbmRleF06cHJvamVjdC5zdG9wc1twcmVzZW50U3RvcEluZGV4XTtzaG93UHJlc2VudEZvY3VzKHNlbGVjdGVkKTtlbCgncHJlc2VudFN0b3BCYW5uZXJUaXRsZScpLnRleHRDb250ZW50PXByb2plY3QubmFtZXx8J0pvdXJuZXkgT3ZlcnZpZXcnO2VsKCdwcmVzZW50U3RvcEJhbm5lclJhbmdlJykudGV4dENvbnRlbnQ9YCR7cHJvamVjdC5zdG9wcy5sZW5ndGh9IHN0b3BzICDigKIgICR7KHByb2plY3QuYXNzZXRzfHxbXSkubGVuZ3RofSBwaG90b3NgO2VsKCdwcmVzZW50UGhvdG9DYXJkJykuY2xhc3NMaXN0LnJlbW92ZSgnc2hvdycpfWZ1bmN0aW9uIHByZXNlbnRCYWNrKCl7aWYocHJlc2VudFZpZXc9PT0ncGhvdG8nKXtnb1ByZXNlbnRTdG9wKHByZXNlbnRTdG9wSW5kZXgpO3JldHVybn1pZihwcmVzZW50Vmlldz09PSdzdG9wJyl7Y2VudGVyUHJlc2VudFRyaXAoKTtyZXR1cm59Y2VudGVyUHJlc2VudFRyaXAoKX1mdW5jdGlvbiByZXR1cm5QcmVzZW50U3RhcnQoKXtwcmVzZW50U3RvcEluZGV4PTA7cHJlc2VudFBob3RvSW5kZXg9LTE7Z29QcmVzZW50U3RvcCgwKX0KZnVuY3Rpb24gZ29QcmVzZW50U3RvcChpbmRleCl7Y29uc3Qgc3RvcHM9cHJvamVjdD8uc3RvcHN8fFtdO2lmKCFzdG9wcy5sZW5ndGgpcmV0dXJuO3N0b3BQcmVzZW50T3JiaXQoKTtjbGVhclByZXNlbnRGb2N1cygpO3ByZXNlbnRWaWV3PSdzdG9wJztwcmVzZW50U3RvcEluZGV4PShpbmRleCtzdG9wcy5sZW5ndGgpJXN0b3BzLmxlbmd0aDtwcmVzZW50UGhvdG9JbmRleD0tMTtjb25zdCBzdG9wPXN0b3BzW3ByZXNlbnRTdG9wSW5kZXhdLG5leHQ9c3RvcHNbKHByZXNlbnRTdG9wSW5kZXgrMSklc3RvcHMubGVuZ3RoXXx8c3RvcDtyZW5kZXJQcmVzZW50U3RvcHMoKTtyZW5kZXJQcmVzZW50RmlsbXN0cmlwKCk7cmVuZGVyUHJlc2VudFBob3RvQnViYmxlcygpO2NvbnN0IHJhbmdlPXN0b3BEYXRlUmFuZ2Uoc3RvcCk7ZWwoJ3ByZXNlbnRIZWFkZXJUaXRsZScpLnRleHRDb250ZW50PXN0b3BOYW1lKHN0b3AscHJlc2VudFN0b3BJbmRleCk7ZWwoJ3ByZXNlbnRIZWFkZXJNZXRhJykudGV4dENvbnRlbnQ9YFN0b3AgJHtwcmVzZW50U3RvcEluZGV4KzF9IG9mICR7c3RvcHMubGVuZ3RofSDigKIgJHsoc3RvcC5hc3NldF9pZHN8fFtdKS5sZW5ndGh9IHBob3RvcyDigKIgJHtyYW5nZX1gO2VsKCdwcmVzZW50U3RvcEJhbm5lclRpdGxlJykudGV4dENvbnRlbnQ9c3RvcE5hbWUoc3RvcCxwcmVzZW50U3RvcEluZGV4KTtlbCgncHJlc2VudFN0b3BCYW5uZXJSYW5nZScpLnRleHRDb250ZW50PWBTdG9wICR7cHJlc2VudFN0b3BJbmRleCsxfSBvZiAke3N0b3BzLmxlbmd0aH0gIOKAoiAgJHtyYW5nZX0gIOKAoiAgJHsoc3RvcC5hc3NldF9pZHN8fFtdKS5sZW5ndGh9IHBob3Rvc2A7ZWwoJ3ByZXNlbnRQaG90b0NhcmQnKS5jbGFzc0xpc3QucmVtb3ZlKCdzaG93Jyk7c2hvd1ByZXNlbnRGb2N1cyhzdG9wKTtjb25zdCBkYXRhPXN0b3BCb3VuZHMoc3RvcCksY2VudGVyPXZhbGlkUG9pbnQoc3RvcCk/W051bWJlcihzdG9wLmxvbiksTnVtYmVyKHN0b3AubGF0KV06ZGF0YS5hc3NldHMubGVuZ3RoP1tOdW1iZXIoZGF0YS5hc3NldHNbMF0ubG9uKSxOdW1iZXIoZGF0YS5hc3NldHNbMF0ubGF0KV06bnVsbDtpZihkYXRhLmFzc2V0cy5sZW5ndGg+MSYmIWRhdGEuYm91bmRzLmlzRW1wdHkoKSl7cHJlc2VudE1hcC5maXRCb3VuZHMoZGF0YS5ib3VuZHMse3BhZGRpbmc6e3RvcDoxMzAsYm90dG9tOjIwMCxsZWZ0OjI4NSxyaWdodDo0MzB9LG1heFpvb206MTYuMTUsZHVyYXRpb246MTcwMCxlc3NlbnRpYWw6dHJ1ZX0pO3NldFRpbWVvdXQoKCk9PntwcmVzZW50TWFwLmVhc2VUbyh7cGl0Y2g6NTgsYmVhcmluZzpiZWFyaW5nKHN0b3AsbmV4dCksZHVyYXRpb246NzAwLGVzc2VudGlhbDp0cnVlfSk7aWYoY2VudGVyKXN0YXJ0UHJlc2VudE9yYml0KGNlbnRlcixNYXRoLm1pbihwcmVzZW50TWFwLmdldFpvb20oKSwxNi4xNSksNTgpfSw5NTApfWVsc2UgaWYoY2VudGVyKXtwcmVzZW50TWFwLmZseVRvKHtjZW50ZXIsem9vbToxNixwaXRjaDo1OCxiZWFyaW5nOmJlYXJpbmcoc3RvcCxuZXh0KSxkdXJhdGlvbjoxNjAwLGN1cnZlOjEuNDUsZXNzZW50aWFsOnRydWV9KTtzdGFydFByZXNlbnRPcmJpdChjZW50ZXIsMTYsNTgpfX0KZnVuY3Rpb24gZ29QcmVzZW50UGhvdG8oaW5kZXgpe2NvbnN0IGFzc2V0cz1wcmVzZW50QXNzZXRzKCk7aWYoIWFzc2V0cy5sZW5ndGgpcmV0dXJuO3N0b3BQcmVzZW50T3JiaXQoKTtwcmVzZW50Vmlldz0ncGhvdG8nO3ByZXNlbnRQaG90b0luZGV4PShpbmRleCthc3NldHMubGVuZ3RoKSVhc3NldHMubGVuZ3RoO2NvbnN0IGFzc2V0PWFzc2V0c1twcmVzZW50UGhvdG9JbmRleF07aWYoIXZhbGlkUG9pbnQoYXNzZXQpKXJldHVybjtyZW5kZXJQcmVzZW50RmlsbXN0cmlwKCk7cmVuZGVyUHJlc2VudFBob3RvQnViYmxlcygpO3Nob3dQcmVzZW50Rm9jdXMoYXNzZXQpO2VsKCdwcmVzZW50U3RvcEJhbm5lclRpdGxlJykudGV4dENvbnRlbnQ9c3RvcE5hbWUocHJvamVjdC5zdG9wc1twcmVzZW50U3RvcEluZGV4XSxwcmVzZW50U3RvcEluZGV4KTtlbCgncHJlc2VudFN0b3BCYW5uZXJSYW5nZScpLnRleHRDb250ZW50PWBQaG90byAke3ByZXNlbnRQaG90b0luZGV4KzF9IG9mICR7YXNzZXRzLmxlbmd0aH0gIOKAoiAgJHtmb3JtYXRBc3NldERhdGVUaW1lKGFzc2V0LnRpbWUpfWA7ZWwoJ3ByZXNlbnRQaG90b0NhcmQnKS5pbm5lckhUTUw9YCR7YXNzZXQucHJldmlld3x8YXNzZXQudGh1bWI/YDxpbWcgc3JjPSIke2VzYyhhc3NldC5wcmV2aWV3fHxhc3NldC50aHVtYil9Ij5gOicnfTxkaXYgY2xhc3M9InByZXNlbnRQaG90b0JvZHkiPjxkaXYgY2xhc3M9InByZXNlbnRQaG90b1RpdGxlIj5QaG90byAke3ByZXNlbnRQaG90b0luZGV4KzF9IG9mICR7YXNzZXRzLmxlbmd0aH08L2Rpdj48ZGl2IGNsYXNzPSJwcmVzZW50UGhvdG9NZXRhIj4ke2VzYyhmb3JtYXRBc3NldERhdGVUaW1lKGFzc2V0LnRpbWUpKX08L2Rpdj48ZGl2IGNsYXNzPSJwcmVzZW50UGhvdG9Db29yZHMiPiR7ZXNjKGFzc2V0Q29vcmRpbmF0ZVRleHQoYXNzZXQpKX08L2Rpdj48ZGl2IGNsYXNzPSJwcmVzZW50UGhvdG9BY3Rpb25zIj48YnV0dG9uIG9uY2xpY2s9ImdvUHJlc2VudFN0b3AocHJlc2VudFN0b3BJbmRleCkiPkJhY2sgdG8gU3RvcDwvYnV0dG9uPjxidXR0b24gY2xhc3M9ImRhbmdlciIgb25jbGljaz0icmVtb3ZlQXNzZXRGcm9tSm91cm5leSgnJHtlc2MoYXNzZXQuYXNzZXRfaWQpfScpIj5SZW1vdmUgZnJvbSBKb3VybmV5PC9idXR0b24+PC9kaXY+PC9kaXY+YDtlbCgncHJlc2VudFBob3RvQ2FyZCcpLmNsYXNzTGlzdC5hZGQoJ3Nob3cnKTtjb25zdCBjZW50ZXI9W051bWJlcihhc3NldC5sb24pLE51bWJlcihhc3NldC5sYXQpXSx6b29tPTE3LjY1O3ByZXNlbnRNYXAuZmx5VG8oe2NlbnRlcix6b29tLHBpdGNoOjUwLGJlYXJpbmc6KHByZXNlbnRQaG90b0luZGV4KjE3KSUzNjAsZHVyYXRpb246MTM1MCxjdXJ2ZToxLjMsZXNzZW50aWFsOnRydWV9KTtzdGFydFByZXNlbnRPcmJpdChjZW50ZXIsem9vbSw1MCl9CmZ1bmN0aW9uIG9wZW5QcmVzZW50KGluZGV4PTApe2lmKCFwcm9qZWN0Py5zdG9wcz8ubGVuZ3RoKXJldHVybiB0b2FzdCgnTG9hZCBhIGpvdXJuZXkgd2l0aCBzdG9wcyBmaXJzdC4nKTtlbCgncHJlc2VudE92ZXJsYXknKS5jbGFzc0xpc3QuYWRkKCdzaG93Jyk7ZW5zdXJlUHJlc2VudE1hcCgpO3NldFRpbWVvdXQoKCk9PntwcmVzZW50TWFwLnJlc2l6ZSgpO2lmKHByZXNlbnRNYXAuaXNTdHlsZUxvYWRlZCgpKXtyZW5kZXJQcmVzZW50TWFwTGF5ZXJzKCk7Z29QcmVzZW50U3RvcChpbmRleCl9ZWxzZSBwcmVzZW50TWFwLm9uY2UoJ2xvYWQnLCgpPT57cmVuZGVyUHJlc2VudE1hcExheWVycygpO2dvUHJlc2VudFN0b3AoaW5kZXgpfSl9LDkwKX0KZnVuY3Rpb24gY2xvc2VQcmVzZW50KCl7Y2xlYXJJbnRlcnZhbChwcmVzZW50VGltZXIpO3ByZXNlbnRUaW1lcj1udWxsO3N0b3BQcmVzZW50T3JiaXQoKTtjbGVhclByZXNlbnRGb2N1cygpO2VsKCdwbGF5Sm91cm5leUJ1dHRvbicpLnRleHRDb250ZW50PSfilrYgUGxheSc7ZWwoJ3ByZXNlbnRPdmVybGF5JykuY2xhc3NMaXN0LnJlbW92ZSgnc2hvdycpfQpmdW5jdGlvbiB0b2dnbGVQbGF5KCl7aWYocHJlc2VudFRpbWVyKXtjbGVhckludGVydmFsKHByZXNlbnRUaW1lcik7cHJlc2VudFRpbWVyPW51bGw7ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykudGV4dENvbnRlbnQ9J+KWtiBQbGF5JztyZXR1cm59ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykudGV4dENvbnRlbnQ9J+KFoSBQYXVzZSc7cHJlc2VudFRpbWVyPXNldEludGVydmFsKCgpPT57Y29uc3QgYXNzZXRzPXByZXNlbnRBc3NldHMoKTtpZihhc3NldHMubGVuZ3RoJiZwcmVzZW50UGhvdG9JbmRleDxhc3NldHMubGVuZ3RoLTEpZ29QcmVzZW50UGhvdG8ocHJlc2VudFBob3RvSW5kZXgrMSk7ZWxzZSBnb1ByZXNlbnRTdG9wKHByZXNlbnRTdG9wSW5kZXgrMSl9LDQzMDApfQpmdW5jdGlvbiBkb3dubG9hZEdweCgpe2lmKCFwcm9qZWN0KXJldHVybjtjb25zdCBwb2ludHM9KHByb2plY3Quc3RvcHN8fFtdKS5tYXAoKHMsaSk9PmA8d3B0IGxhdD0iJHtzLmxhdH0iIGxvbj0iJHtzLmxvbn0iPjxuYW1lPiR7ZXNjKHN0b3BOYW1lKHMsaSkpfTwvbmFtZT48L3dwdD5gKS5qb2luKCcnKTtjb25zdCBncHg9YDw/eG1sIHZlcnNpb249IjEuMCI/PjxncHggdmVyc2lvbj0iMS4xIiBjcmVhdG9yPSJUcmlwcHkiPiR7cG9pbnRzfTwvZ3B4PmA7Y29uc3QgYmxvYj1uZXcgQmxvYihbZ3B4XSx7dHlwZTonYXBwbGljYXRpb24vZ3B4K3htbCd9KSxhPWRvY3VtZW50LmNyZWF0ZUVsZW1lbnQoJ2EnKTthLmhyZWY9VVJMLmNyZWF0ZU9iamVjdFVSTChibG9iKTthLmRvd25sb2FkPShwcm9qZWN0Lm5hbWV8fCd0cmlwcHknKSsnLmdweCc7YS5jbGljaygpO1VSTC5yZXZva2VPYmplY3RVUkwoYS5ocmVmKX0KZnVuY3Rpb24gYmluZCgpe2VsKCduZXdJbW1pY2hCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNb2RhbCgnaW1taWNoTW9kYWwnKTtlbCgndXBsb2FkQnV0dG9uJykub25jbGljaz0oKT0+c2V0TW9kYWwoJ3VwbG9hZE1vZGFsJyk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtY2xvc2VdJykuZm9yRWFjaChiPT5iLm9uY2xpY2s9KCk9PnNldE1vZGFsKGIuZGF0YXNldC5jbG9zZSxmYWxzZSkpO2VsKCdwcm9qZWN0U2VhcmNoQnV0dG9uJykub25jbGljaz0oKT0+ZWwoJ3Byb2plY3RTZWFyY2gnKS5jbGFzc0xpc3QudG9nZ2xlKCdoaWRkZW4nKTtlbCgncHJvamVjdFNlYXJjaCcpLm9uaW5wdXQ9cmVuZGVyUHJvamVjdHM7ZWwoJ3JlbmFtZVByb2plY3RCdXR0b24nKS5vbmNsaWNrPXJlbmFtZVByb2plY3Q7ZWwoJ3ByZXNlbnRCdXR0b24nKS5vbmNsaWNrPSgpPT5vcGVuUHJlc2VudCgwKTtlbCgnZXhwb3J0SnVtcEJ1dHRvbicpLm9uY2xpY2s9KCk9PntlbCgnZXhwb3J0Qm94JykuY2xhc3NMaXN0LnJlbW92ZSgnY29sbGFwc2VkJyk7ZWwoJ2V4cG9ydEJveCcpLnNjcm9sbEludG9WaWV3KHtiZWhhdmlvcjonc21vb3RoJyxibG9jazonZW5kJ30pfTtlbCgnc2V0dGluZ3NCdXR0b24nKS5vbmNsaWNrPSgpPT57ZWwoJ3N0b3BSYWRpdXMnKS52YWx1ZT1wcm9qZWN0Py5zZXR0aW5ncz8uc3RvcF9yYWRpdXNfbXx8MjAwO3NldE1vZGFsKCdzZXR0aW5nc01vZGFsJyl9O2VsKCdhY2NvdW50QnV0dG9uJykub25jbGljaz0oKT0+c2V0TW9kYWwoJ2FjY291bnRNb2RhbCcpO2VsKCdzYXZlQWNjb3VudEJ1dHRvbicpLm9uY2xpY2s9KCk9PntzYXZlQ29ubihlbCgnYWNjb3VudFVybCcpLnZhbHVlLnRyaW0oKSxlbCgnYWNjb3VudEtleScpLnZhbHVlLnRyaW0oKSk7dG9hc3QoJ0ltbWljaCBjb25uZWN0aW9uIHNhdmVkJyk7c2V0TW9kYWwoJ2FjY291bnRNb2RhbCcsZmFsc2UpfTtlbCgndGVzdEltbWljaEJ1dHRvbicpLm9uY2xpY2s9KCk9PnRlc3RJbW1pY2goKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgnY3JlYXRlSm91cm5leUJ1dHRvbicpLm9uY2xpY2s9KCk9PmNyZWF0ZUltbWljaEpvdXJuZXkoKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgnY3JlYXRlVXBsb2FkQnV0dG9uJykub25jbGljaz0oKT0+Y3JlYXRlVXBsb2FkSm91cm5leSgpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdzdG9wU2VhcmNoQnV0dG9uJykub25jbGljaz0oKT0+ZWwoJ3N0b3BTZWFyY2hXcmFwJykuY2xhc3NMaXN0LnRvZ2dsZSgnc2hvdycpO2VsKCdzdG9wU2VhcmNoJykub25pbnB1dD1yZW5kZXJTdG9wcztlbCgnYWRkU3RvcEJ1dHRvbicpLm9uY2xpY2s9YWRkU3RvcDtlbCgnZXhwb3J0SGVhZGVyJykub25jbGljaz0oKT0+ZWwoJ2V4cG9ydEJveCcpLmNsYXNzTGlzdC50b2dnbGUoJ2NvbGxhcHNlZCcpO2VsKCdhdWRpb1N3aXRjaCcpLm9uY2xpY2s9KCk9PntlbCgnYXVkaW9Td2l0Y2gnKS5jbGFzc0xpc3QudG9nZ2xlKCdvbicpO2lmKGVsKCdhdWRpb1N3aXRjaCcpLmNsYXNzTGlzdC5jb250YWlucygnb24nKSllbCgnYXVkaW9JbnB1dCcpLmNsaWNrKCl9O2VsKCdyZW5kZXJCdXR0b24nKS5vbmNsaWNrPSgpPT5yZW5kZXJNcDQoKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgnZ3B4QnV0dG9uJykub25jbGljaz1kb3dubG9hZEdweDtlbCgnaW1hZ2VTZXRCdXR0b24nKS5vbmNsaWNrPSgpPT50b2FzdCgnSW1hZ2UgU2V0IGV4cG9ydCBpcyBjb21pbmcgbmV4dC4nKTtlbCgnY2xlYXJGaWx0ZXJCdXR0b24nKS5vbmNsaWNrPSgpPT57ZmlsdGVyU3RvcElkPW51bGw7YWN0aXZlU3RvcElkPW51bGw7cmVuZGVyR2FsbGVyeSgpO3JlbmRlclN0b3BzKCk7cmVuZGVyTWFwKGZhbHNlKX07ZWwoJ2xvY2F0ZUJ1dHRvbicpLm9uY2xpY2s9KCk9Pm5hdmlnYXRvci5nZW9sb2NhdGlvbj8uZ2V0Q3VycmVudFBvc2l0aW9uKHA9Pm1hcC5mbHlUbyh7Y2VudGVyOltwLmNvb3Jkcy5sb25naXR1ZGUscC5jb29yZHMubGF0aXR1ZGVdLHpvb206MTUsZHVyYXRpb246OTAwfSksKCk9PnRvYXN0KCdMb2NhdGlvbiB1bmF2YWlsYWJsZScpKTtlbCgnem9vbUluQnV0dG9uJykub25jbGljaz0oKT0+bWFwPy56b29tSW4oKTtlbCgnem9vbU91dEJ1dHRvbicpLm9uY2xpY2s9KCk9Pm1hcD8uem9vbU91dCgpO2VsKCdsaWdodE1hcEJ1dHRvbicpLm9uY2xpY2s9KCk9PnNldE1hcFN0eWxlKCdsaWdodCcpO2VsKCdkYXJrTWFwQnV0dG9uJykub25jbGljaz0oKT0+c2V0TWFwU3R5bGUoJ2RhcmsnKTtlbCgnc2F0ZWxsaXRlTWFwQnV0dG9uJykub25jbGljaz0oKT0+c2V0TWFwU3R5bGUoJ3NhdGVsbGl0ZScpO2VsKCdkZWZhdWx0TWFwU2VsZWN0Jykub25jaGFuZ2U9ZT0+c2V0TWFwU3R5bGUoZS50YXJnZXQudmFsdWUpO2VsKCdyZWNsdXN0ZXJCdXR0b24nKS5vbmNsaWNrPSgpPT5yZWNsdXN0ZXIoKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgncmV2ZXJzZVJvdXRlQnV0dG9uJykub25jbGljaz0oKT0+cmV2ZXJzZVJvdXRlKCkuY2F0Y2goZT0+dG9hc3QoZS5tZXNzYWdlKSk7ZWwoJ2Nsb3NlUHJlc2VudEJ1dHRvbicpLm9uY2xpY2s9Y2xvc2VQcmVzZW50O2VsKCdwcmVzZW50QmFja0J1dHRvbicpLm9uY2xpY2s9cHJlc2VudEJhY2s7ZWwoJ2NlbnRlclRyaXBCdXR0b24nKS5vbmNsaWNrPWNlbnRlclByZXNlbnRUcmlwO2VsKCdyZXR1cm5TdGFydEJ1dHRvbicpLm9uY2xpY2s9cmV0dXJuUHJlc2VudFN0YXJ0O2VsKCdwcmV2aW91c1N0b3BCdXR0b24nKS5vbmNsaWNrPSgpPT5nb1ByZXNlbnRTdG9wKHByZXNlbnRTdG9wSW5kZXgtMSk7ZWwoJ25leHRTdG9wQnV0dG9uJykub25jbGljaz0oKT0+Z29QcmVzZW50U3RvcChwcmVzZW50U3RvcEluZGV4KzEpO2VsKCdwcmV2aW91c1Bob3RvQnV0dG9uJykub25jbGljaz0oKT0+e2NvbnN0IGE9cHJlc2VudEFzc2V0cygpO2lmKGEubGVuZ3RoKWdvUHJlc2VudFBob3RvKHByZXNlbnRQaG90b0luZGV4PDA/YS5sZW5ndGgtMTpwcmVzZW50UGhvdG9JbmRleC0xKX07ZWwoJ25leHRQaG90b0J1dHRvbicpLm9uY2xpY2s9KCk9Pntjb25zdCBhPXByZXNlbnRBc3NldHMoKTtpZihhLmxlbmd0aClnb1ByZXNlbnRQaG90byhwcmVzZW50UGhvdG9JbmRleCsxKX07ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykub25jbGljaz10b2dnbGVQbGF5fQppbml0Rm9ybXMoKTtiaW5kKCk7ZW5zdXJlTWFwKCk7c2V0TWFwU3R5bGUobWFwU3R5bGVLZXkpO2xvYWRQcm9qZWN0cygpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpOwo8L3NjcmlwdD4KPC9ib2R5Pgo8L2h0bWw+
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








pct exec "$CTID" -- bash -lc "grep -q 'Trippy v10.2.4' /opt/trippy/frontend/index.html && grep -q 'presentMap' /opt/trippy/frontend/index.html && grep -q 'photoMarker' /opt/trippy/frontend/index.html && test -s /opt/trippy/frontend/vendor/maplibre-gl.js" >/dev/null 2>&1 || {
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
printf "${CYAN}${BOLD}v10.2.4 features${RESET}\n"
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
