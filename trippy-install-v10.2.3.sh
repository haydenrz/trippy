#!/usr/bin/env bash
set -euo pipefail
USER_SUPPLIED_CTID="${CTID:-}"

# Trippy v10.2.3: Immich-style web UI route-tour generator for Proxmox LXC
# Adds stop-based clustering, stop radius, stop review/editing, and lasso grouping.
#
#
# Install directly from GitHub:
#
#   curl -fsSL https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.2.3.sh \
#     -o trippy-install-v10.2.3.sh
#   chmod +x trippy-install-v10.2.3.sh
#   ./trippy-install-v10.2.3.sh
#
# Or with wget:
#
#   wget -O trippy-install-v10.2.3.sh \
#     https://raw.githubusercontent.com/haydenrz/trippy/main/trippy-install-v10.2.3.sh
#   chmod +x trippy-install-v10.2.3.sh
#   ./trippy-install-v10.2.3.sh
#
# Run on Proxmox host:
#   bash trippy-install-v10.2.3.sh
#
# Optional:
#   CTID=106 STORAGE=local-lvm BRIDGE=vmbr0 bash trippy-install-v10.2.3.sh

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

printf "${CYAN}${BOLD}Trippy v10.2.3 Clean Installer${RESET}\n"
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

pct set "$CTID" --description "🧭 Trippy v10.2.3
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

app = FastAPI(title="Trippy", version="1.2.3")
app.mount("/exports", StaticFiles(directory=str(EXPORTS)), name="exports")
app.mount("/uploads", StaticFiles(directory=str(UPLOADS)), name="uploads")
app.mount("/static", StaticFiles(directory=str(FRONTEND)), name="static")

@app.get("/api/health")
def health():
    return {
        "ok": True,
        "app": "trippy",
        "version": "1.2.3",
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
// Trippy v10.2.3 UI behavior upgrades
(function(){{
  function ready(fn){{ if(document.readyState!=='loading') fn(); else document.addEventListener('DOMContentLoaded',fn); }}
  window.TRIPPY_VERSION='v10.2.3';
  ready(() => {{
    if(!document.querySelector('.versionBadge')){{
      const v=document.createElement('div'); v.className='versionBadge'; v.textContent='v10.2.3'; document.body.appendChild(v);
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
      const v=document.createElement('div');v.className='versionBadge';v.textContent='v10.2.3';document.body.appendChild(v);
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

/* Trippy v10.2.3 UI refresh */
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






# v10.2.3: full frontend replacement, not an overlay.
pct exec "$CTID" -- bash -lc "cat >/tmp/trippy_frontend.b64 <<'EOF_TRIPPY_FRONTEND_B64'
PCFkb2N0eXBlIGh0bWw+CjxodG1sIGxhbmc9ImVuIj4KPGhlYWQ+CjxtZXRhIGNoYXJzZXQ9InV0Zi04Ij4KPG1ldGEgbmFtZT0idmlld3BvcnQiIGNvbnRlbnQ9IndpZHRoPWRldmljZS13aWR0aCxpbml0aWFsLXNjYWxlPTEiPgo8dGl0bGU+VHJpcHB5IHYxMC4yLjM8L3RpdGxlPgo8bGluayByZWw9InN0eWxlc2hlZXQiIGhyZWY9Ii9zdGF0aWMvdmVuZG9yL21hcGxpYnJlLWdsLmNzcyI+CjxzY3JpcHQgc3JjPSIvc3RhdGljL3ZlbmRvci9tYXBsaWJyZS1nbC5qcyI+PC9zY3JpcHQ+CjxzdHlsZT4KOnJvb3R7CiAgLS1iZzojMDMwODEzOy0tYmcyOiMwNzExMWQ7LS1wYW5lbDojMDgxNDIxOy0tcGFuZWwyOiMwZDFjMmM7LS1jYXJkOiMwYzFhMjk7CiAgLS1saW5lOiMxZDM4NTA7LS1saW5lMjojMjU0YTY4Oy0tY3lhbjojMDBkOGZmOy0tY3lhbjI6IzM2ZWRmZjstLWJsdWU6IzI2N2RmZjsKICAtLXZpb2xldDojNjg0OGZmOy0tcGluazojZmY0ZGE2Oy0tZ3JlZW46IzM5ZDk5NTstLXJlZDojZmY0ZDY2Oy0tdGV4dDojZjJmOGZmOwogIC0tbXV0ZWQ6IzhlYTNiNjstLXNvZnQ6I2I4YzhkNzstLXNoYWRvdzowIDI0cHggNzBweCByZ2JhKDAsMCwwLC40MikKfQoqe2JveC1zaXppbmc6Ym9yZGVyLWJveH0KaHRtbCxib2R5e2hlaWdodDoxMDAlO21hcmdpbjowO292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOnZhcigtLWJnKTtjb2xvcjp2YXIoLS10ZXh0KTtmb250LWZhbWlseTpJbnRlciwiU2Vnb2UgVUkiLHN5c3RlbS11aSxzYW5zLXNlcmlmfQpib2R5e2JhY2tncm91bmQ6cmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCA5JSAwJSxyZ2JhKDAsMjE2LDI1NSwuMTMpLHRyYW5zcGFyZW50IDI3JSkscmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCA4MiUgNyUscmdiYSgxMDQsNzIsMjU1LC4xMiksdHJhbnNwYXJlbnQgMzAlKSxsaW5lYXItZ3JhZGllbnQoMTQ1ZGVnLCMwMjA3MTEsIzA3MTIxZSA1OCUsIzAyMDYwZCl9CmJ1dHRvbixpbnB1dCxzZWxlY3R7Zm9udDppbmhlcml0fWJ1dHRvbntjb2xvcjp2YXIoLS10ZXh0KTtjdXJzb3I6cG9pbnRlcjtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzUsMTI2LDE2NCwuNDUpO2JvcmRlci1yYWRpdXM6MTNweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgyMCw0Myw2NiwuOTgpLHJnYmEoMTAsMjUsNDEsLjk4KSk7Zm9udC13ZWlnaHQ6ODAwO3RyYW5zaXRpb246LjE2cyBlYXNlfWJ1dHRvbjpob3Zlcntib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMjJweCByZ2JhKDAsMjE2LDI1NSwuMjIpO3RyYW5zZm9ybTp0cmFuc2xhdGVZKC0xcHgpfQppbnB1dCxzZWxlY3R7d2lkdGg6MTAwJTtjb2xvcjp2YXIoLS10ZXh0KTtiYWNrZ3JvdW5kOiMwNzExMWM7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDkwLDEzOSwxNzMsLjM4KTtib3JkZXItcmFkaXVzOjEycHg7cGFkZGluZzoxMXB4IDEycHg7b3V0bGluZTpub25lfWlucHV0OmZvY3VzLHNlbGVjdDpmb2N1c3tib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMCAzcHggcmdiYSgwLDIxNiwyNTUsLjEwKX0KLnNtYWxse2ZvbnQtc2l6ZToxMnB4O2NvbG9yOnZhcigtLW11dGVkKX0uaGlkZGVue2Rpc3BsYXk6bm9uZSFpbXBvcnRhbnR9LnN2Z0ljb257d2lkdGg6MjBweDtoZWlnaHQ6MjBweDtzdHJva2U6Y3VycmVudENvbG9yO2ZpbGw6bm9uZTtzdHJva2Utd2lkdGg6MS44O3N0cm9rZS1saW5lY2FwOnJvdW5kO3N0cm9rZS1saW5lam9pbjpyb3VuZH0KLmFwcFNoZWxse2hlaWdodDoxMDB2aDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjI4NnB4IG1pbm1heCg2NTBweCwxZnIpIDM1MHB4O292ZXJmbG93OmhpZGRlbn0KLmxlZnRSYWlse21pbi13aWR0aDowO2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDE4MGRlZyxyZ2JhKDQsMTMsMjMsLjk4KSxyZ2JhKDIsOCwxNSwuOTkpKTtib3JkZXItcmlnaHQ6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4xNCk7cGFkZGluZzoxN3B4IDE3cHggMjBweDtkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO2dhcDoxNHB4O2JveC1zaGFkb3c6MTZweCAwIDYwcHggcmdiYSgwLDAsMCwuMzQpO3otaW5kZXg6MTB9Ci5icmFuZExpbmV7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTJweDtoZWlnaHQ6NjRweH0ud29yZG1hcmt7Zm9udC1zaXplOjMxcHg7Zm9udC13ZWlnaHQ6OTUwO2ZvbnQtc3R5bGU6aXRhbGljO2xldHRlci1zcGFjaW5nOi0xLjVweDt0ZXh0LXNoYWRvdzoycHggMCB2YXIoLS1jeWFuKSwtMnB4IDAgdmFyKC0tcGluayksMCA2cHggMjVweCByZ2JhKDAsMCwwLC45KX0udmVyc2lvbnttYXJnaW4tbGVmdDphdXRvO3BhZGRpbmc6NnB4IDEwcHg7Ym9yZGVyLXJhZGl1czo5OTlweDtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4yOCk7YmFja2dyb3VuZDpyZ2JhKDAsMjE2LDI1NSwuMDgpO2NvbG9yOnZhcigtLWN5YW4yKTtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5NTA7Ym94LXNoYWRvdzowIDAgMThweCByZ2JhKDAsMjE2LDI1NSwuMTApfQoubG9nb0Zsb3dlcntwb3NpdGlvbjpyZWxhdGl2ZTt3aWR0aDo0OXB4O2hlaWdodDo0OXB4O2ZsZXg6MCAwIGF1dG87ZmlsdGVyOmRyb3Atc2hhZG93KDAgMCAxMXB4IHJnYmEoMCwyMTYsMjU1LC4zNSkpIHNhdHVyYXRlKDEuMTgpfS5sb2dvRmxvd2VyIC5wZXRhbHtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjE4cHg7dG9wOjJweDt3aWR0aDoxN3B4O2hlaWdodDoyOXB4O2JvcmRlci1yYWRpdXM6MTRweCAxNHB4IDdweCA3cHg7dHJhbnNmb3JtLW9yaWdpbjo3cHggMjNweDttaXgtYmxlbmQtbW9kZTpzY3JlZW59LmxvZ29GbG93ZXIgLnAxe2JhY2tncm91bmQ6I2ZmNTQ1NDt0cmFuc2Zvcm06cm90YXRlKDBkZWcpIHRyYW5zbGF0ZVkoLTFweCkgc2tld1goLThkZWcpfS5sb2dvRmxvd2VyIC5wMntiYWNrZ3JvdW5kOiNmZmJiMzE7dHJhbnNmb3JtOnJvdGF0ZSg2MGRlZykgdHJhbnNsYXRlWSgwKSBza2V3WCg5ZGVnKX0ubG9nb0Zsb3dlciAucDN7YmFja2dyb3VuZDojNzlkZjRjO3RyYW5zZm9ybTpyb3RhdGUoMTIwZGVnKSB0cmFuc2xhdGVZKDFweCkgc2tld1goLThkZWcpfS5sb2dvRmxvd2VyIC5wNHtiYWNrZ3JvdW5kOiMyN2Q2Yzc7dHJhbnNmb3JtOnJvdGF0ZSgxODBkZWcpIHRyYW5zbGF0ZVkoLTFweCkgc2tld1goOGRlZyl9LmxvZ29GbG93ZXIgLnA1e2JhY2tncm91bmQ6IzQxOGNmZjt0cmFuc2Zvcm06cm90YXRlKDI0MGRlZykgdHJhbnNsYXRlWSgxcHgpIHNrZXdYKC0xMGRlZyl9LmxvZ29GbG93ZXIgLnA2e2JhY2tncm91bmQ6I2RmNjhmZjt0cmFuc2Zvcm06cm90YXRlKDMwMGRlZykgdHJhbnNsYXRlWSgtMXB4KSBza2V3WCg5ZGVnKX0ubG9nb0Zsb3dlcjpiZWZvcmV7Y29udGVudDoiIjtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDo2cHg7Ym9yZGVyLXJhZGl1czo1MCU7Ym94LXNoYWRvdzozcHggMCA4cHggcmdiYSgyNTUsNzcsMTY2LC40NSksLTNweCAwIDhweCByZ2JhKDAsMjE2LDI1NSwuNSk7ZmlsdGVyOmJsdXIoMXB4KX0ubG9nb0Zsb3dlcjphZnRlcntjb250ZW50OiIiO3Bvc2l0aW9uOmFic29sdXRlO2luc2V0OjE2cHg7Ym9yZGVyOjJweCBzb2xpZCByZ2JhKDI0NSwyNTMsMjU1LC44OCk7Ym9yZGVyLXJhZGl1czo1MCU7Ym94LXNoYWRvdzowIDAgOXB4IHJnYmEoMCwyMTYsMjU1LC45KX0KLnNpZGVQcmltYXJ5LC5zaWRlU2Vjb25kYXJ5e2hlaWdodDo1NHB4O3dpZHRoOjEwMCU7Zm9udC1zaXplOjE0cHh9LnNpZGVQcmltYXJ5e2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMDk2MmJkLCMwMGE5YzgpO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuODgpO2JveC1zaGFkb3c6MCAwIDI4cHggcmdiYSgwLDIxNiwyNTUsLjIxKX0KLnNlY3Rpb25MYWJlbHttYXJnaW4tdG9wOjhweDtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuO2NvbG9yOiNjNGQ0ZTI7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwO2xldHRlci1zcGFjaW5nOi4wOGVtO3RleHQtdHJhbnNmb3JtOnVwcGVyY2FzZX0ucHJvamVjdExpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6MTBweDtvdmVyZmxvdzphdXRvO21pbi1oZWlnaHQ6MDtwYWRkaW5nLXJpZ2h0OjJweH0ucHJvamVjdENhcmR7cG9zaXRpb246cmVsYXRpdmU7cGFkZGluZzoxNXB4IDE0cHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoMTMsMjksNDUsLjk0KSxyZ2JhKDcsMTgsMzAsLjk0KSk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDYyLDExMywxNTEsLjMyKTtib3JkZXItcmFkaXVzOjE1cHg7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTZzIGVhc2V9LnByb2plY3RDYXJkOmhvdmVyLC5wcm9qZWN0Q2FyZC5hY3RpdmV7Ym9yZGVyLWNvbG9yOnZhcigtLWN5YW4pO2JveC1zaGFkb3c6MCAwIDI0cHggcmdiYSgwLDIxNiwyNTUsLjE3KX0ucHJvamVjdENhcmRUaXRsZXtwYWRkaW5nLXJpZ2h0OjI0cHg7Zm9udC13ZWlnaHQ6OTAwO2ZvbnQtc2l6ZToxNHB4O3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30ucHJvamVjdERhdGV7bWFyZ2luLXRvcDo2cHg7Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxMnB4fS5wcm9qZWN0U3RhdHN7bWFyZ2luLXRvcDo5cHg7Y29sb3I6IzllYjRjNjtmb250LXNpemU6MTJweH0ucHJvamVjdFN0YXRzIC5kb3R7Y29sb3I6dmFyKC0tY3lhbil9LnByb2plY3RNZW51e3Bvc2l0aW9uOmFic29sdXRlO3JpZ2h0OjlweDt0b3A6MTBweDt3aWR0aDoyOHB4O2hlaWdodDozMnB4O2JvcmRlcjowO2JhY2tncm91bmQ6dHJhbnNwYXJlbnQ7Zm9udC1zaXplOjIwcHg7Ym94LXNoYWRvdzpub25lfS5wcm9qZWN0RGVsZXRle3dpZHRoOjEwMCU7aGVpZ2h0OjM0cHg7bWFyZ2luLXRvcDoxMHB4O2ZvbnQtc2l6ZToxMnB4O2Rpc3BsYXk6bm9uZX0ucHJvamVjdENhcmQubWVudU9wZW4gLnByb2plY3REZWxldGV7ZGlzcGxheTpibG9ja30KLmxlZnRGb290ZXJ7bWFyZ2luLXRvcDphdXRvO2NvbG9yOiM4Mjk2YTg7Zm9udC1zaXplOjEycHg7bGluZS1oZWlnaHQ6MS42NX0uZm9vdGVyTGlua3tkaXNwbGF5OmJsb2NrO21hcmdpbi10b3A6MTBweDtjb2xvcjp2YXIoLS1jeWFuKTt0ZXh0LWRlY29yYXRpb246bm9uZX0KLndvcmtzcGFjZXttaW4td2lkdGg6MDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1yb3dzOjkxcHggbWlubWF4KDM1MHB4LDFmcikgMjI4cHg7YmFja2dyb3VuZDpyZ2JhKDIsOCwxNCwuNTApfQoudG9wQmFye2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjE2cHg7cGFkZGluZzoxNHB4IDE5cHg7Ym9yZGVyLWJvdHRvbToxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjEzKTtiYWNrZ3JvdW5kOnJnYmEoMywxMCwxOCwuODQpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDE4cHgpO3otaW5kZXg6OH0udGl0bGVBcmVhe21pbi13aWR0aDozMjBweDttYXgtd2lkdGg6NDMwcHh9LmpvdXJuZXlUaXRsZVJvd3tkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDo5cHh9LmpvdXJuZXlUaXRsZXtmb250LXNpemU6MjJweDtmb250LXdlaWdodDo5NTA7d2hpdGUtc3BhY2U6bm93cmFwO292ZXJmbG93OmhpZGRlbjt0ZXh0LW92ZXJmbG93OmVsbGlwc2lzfS5lZGl0VGl0bGV7Ym9yZGVyOjA7YmFja2dyb3VuZDp0cmFuc3BhcmVudDtjb2xvcjp2YXIoLS1tdXRlZCk7cGFkZGluZzoycHg7Ym94LXNoYWRvdzpub25lfS5qb3VybmV5TWV0YXtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMXB4O21hcmdpbi10b3A6NnB4O2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTJweH0uam91cm5leU1ldGEgLmxpdmVEb3R7d2lkdGg6N3B4O2hlaWdodDo3cHg7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDp2YXIoLS1ncmVlbik7Ym94LXNoYWRvdzowIDAgOHB4IHJnYmEoNTcsMjE3LDE0OSwuNil9LnRvcFNwYWNlcntmbGV4OjF9LnByZXNlbnRCdXR0b257aGVpZ2h0OjU0cHg7bWluLXdpZHRoOjI2NXB4O3BhZGRpbmc6MCAyNHB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjNjMzYmZmLCMwMGFmZDApO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuODUpO2JveC1zaGFkb3c6MCAwIDMycHggcmdiYSgwLDIxNiwyNTUsLjI4KTtmb250LXNpemU6MTVweH0ucHJlc2VudEJ1dHRvbiBzcGFue2Rpc3BsYXk6YmxvY2s7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6NjUwO29wYWNpdHk6Ljg0O21hcmdpbi10b3A6MnB4fS50b3BBY3Rpb257aGVpZ2h0OjU0cHg7bWluLXdpZHRoOjE0NXB4O3BhZGRpbmc6MCAxNnB4fS5nZWFyQnV0dG9ue3dpZHRoOjU0cHg7bWluLXdpZHRoOjU0cHg7aGVpZ2h0OjU0cHg7Zm9udC1zaXplOjIwcHh9Ci5tYXBab25le3Bvc2l0aW9uOnJlbGF0aXZlO21pbi1oZWlnaHQ6MDtwYWRkaW5nOjAgOHB4IDAgMH0ubWFwRnJhbWV7cG9zaXRpb246YWJzb2x1dGU7aW5zZXQ6MCA4cHggMCAwO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjE4KTtib3JkZXItcmFkaXVzOjE4cHg7b3ZlcmZsb3c6aGlkZGVuO2JveC1zaGFkb3c6dmFyKC0tc2hhZG93KTtiYWNrZ3JvdW5kOiM5Y2I2YmV9Lm1hcENhbnZhc3twb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowfS5tYXBTaGFkZXtwb3NpdGlvbjphYnNvbHV0ZTtpbnNldDowO3BvaW50ZXItZXZlbnRzOm5vbmU7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTgwZGVnLHJnYmEoMSw3LDEzLC4wNCkscmdiYSgxLDcsMTMsLjAzKSl9Lm1hcFRvb2xze3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6MTdweDt0b3A6MThweDt6LWluZGV4OjQ7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6OXB4fS5tYXBUb29se3dpZHRoOjQ3cHg7aGVpZ2h0OjQ3cHg7ZGlzcGxheTpncmlkO3BsYWNlLWl0ZW1zOmNlbnRlcjtib3JkZXItcmFkaXVzOjEzcHg7YmFja2dyb3VuZDpyZ2JhKDcsMTksMzEsLjkyKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjksMTE5LDE1NCwuNDIpO2JveC1zaGFkb3c6MCAxMnB4IDI4cHggcmdiYSgwLDAsMCwuMjgpO2NvbG9yOiNlN2Y3ZmZ9Lm1hcFRvb2wuYWN0aXZle2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMGQ5YmMzLCMwMGQ0ZWUpO2JvcmRlci1jb2xvcjojNWFmM2ZmfS5tYXBab29tR3JvdXB7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjttYXJnaW4tdG9wOjRweH0ubWFwWm9vbUdyb3VwIC5tYXBUb29se2JvcmRlci1yYWRpdXM6MH0ubWFwWm9vbUdyb3VwIC5tYXBUb29sOmZpcnN0LWNoaWxke2JvcmRlci1yYWRpdXM6MTNweCAxM3B4IDAgMH0ubWFwWm9vbUdyb3VwIC5tYXBUb29sOmxhc3QtY2hpbGR7Ym9yZGVyLXJhZGl1czowIDAgMTNweCAxM3B4O2JvcmRlci10b3A6MH0uZmlsdGVyQ2hpcHtwb3NpdGlvbjphYnNvbHV0ZTtyaWdodDoyMHB4O3RvcDoyMHB4O3otaW5kZXg6NTtkaXNwbGF5Om5vbmU7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMHB4O3BhZGRpbmc6MTBweCAxMXB4IDEwcHggMTRweDtib3JkZXItcmFkaXVzOjE0cHg7YmFja2dyb3VuZDpyZ2JhKDUsMTYsMjcsLjk0KTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzMsMTI1LDE2MSwuNDIpO2JveC1zaGFkb3c6MCAxNXB4IDM2cHggcmdiYSgwLDAsMCwuMzIpO2ZvbnQtc2l6ZToxMnB4fS5maWx0ZXJDaGlwLnNob3d7ZGlzcGxheTpmbGV4fS5maWx0ZXJDaGlwIGJ1dHRvbnt3aWR0aDozMHB4O2hlaWdodDozMHB4O3BhZGRpbmc6MH0KLnBob3RvTWFya2Vye3Bvc2l0aW9uOnJlbGF0aXZlO3dpZHRoOjU0cHg7aGVpZ2h0OjU0cHg7Ym9yZGVyLXJhZGl1czo1MCU7cGFkZGluZzozcHg7YmFja2dyb3VuZDojZWRmYWZmO2JvcmRlcjozcHggc29saWQgdmFyKC0tY3lhbik7Ym94LXNoYWRvdzowIDAgMCAycHggcmdiYSgyNTUsMjU1LDI1NSwuNTUpLDAgMCAyMnB4IHJnYmEoMCwyMTYsMjU1LC42NSk7Y3Vyc29yOnBvaW50ZXI7dHJhbnNpdGlvbjouMTVzIGVhc2V9LnBob3RvTWFya2VyOmhvdmVyLC5waG90b01hcmtlci5hY3RpdmV7dHJhbnNmb3JtOnNjYWxlKDEuMTEpO2JvcmRlci1jb2xvcjp3aGl0ZTtib3gtc2hhZG93OjAgMCAwIDNweCB2YXIoLS1jeWFuKSwwIDAgMjhweCByZ2JhKDAsMjE2LDI1NSwuODUpfS5waG90b01hcmtlciBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmJsb2NrO29iamVjdC1maXQ6Y292ZXI7Ym9yZGVyLXJhZGl1czo1MCU7YmFja2dyb3VuZDojMTczMTQ5fS5waG90b01hcmtlciAuZmFsbGJhY2t7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlci1yYWRpdXM6NTAlO2JhY2tncm91bmQ6cmFkaWFsLWdyYWRpZW50KGNpcmNsZSBhdCAzMCUgMzAlLCMzZjgxOWEsIzBhMjYzOSk7Zm9udC13ZWlnaHQ6OTUwfS5tYXJrZXJCYWRnZXtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjUwJTt0b3A6LTE2cHg7dHJhbnNmb3JtOnRyYW5zbGF0ZVgoLTUwJSk7bWluLXdpZHRoOjI4cHg7aGVpZ2h0OjI4cHg7cGFkZGluZzowIDZweDtkaXNwbGF5OmdyaWQ7cGxhY2UtaXRlbXM6Y2VudGVyO2JvcmRlci1yYWRpdXM6OTk5cHg7YmFja2dyb3VuZDojMDcxMzFmO2NvbG9yOiNmZmY7Ym9yZGVyOjJweCBzb2xpZCByZ2JhKDI1NSwyNTUsMjU1LC43Mik7Zm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6OTUwO2JveC1zaGFkb3c6MCA1cHggMTVweCByZ2JhKDAsMCwwLC40NSl9Ci5tYXBsaWJyZWdsLXBvcHVwLWNvbnRlbnR7cGFkZGluZzowIWltcG9ydGFudDtiYWNrZ3JvdW5kOnRyYW5zcGFyZW50IWltcG9ydGFudDtib3JkZXItcmFkaXVzOjE4cHghaW1wb3J0YW50O2JveC1zaGFkb3c6bm9uZSFpbXBvcnRhbnR9Lm1hcGxpYnJlZ2wtcG9wdXAtdGlwe2JvcmRlci10b3AtY29sb3I6IzA3MTMxZiFpbXBvcnRhbnR9Lm1hcGxpYnJlZ2wtcG9wdXAtY2xvc2UtYnV0dG9ue3otaW5kZXg6NDtyaWdodDo4cHghaW1wb3J0YW50O3RvcDo4cHghaW1wb3J0YW50O3dpZHRoOjI4cHg7aGVpZ2h0OjI4cHg7Ym9yZGVyLXJhZGl1czo1MCUhaW1wb3J0YW50O2JhY2tncm91bmQ6cmdiYSg4LDIwLDMzLC44MikhaW1wb3J0YW50O2NvbG9yOndoaXRlIWltcG9ydGFudDtmb250LXNpemU6MThweCFpbXBvcnRhbnQ7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDI1NSwyNTUsMjU1LC4yMikhaW1wb3J0YW50fS5zdG9wUG9wdXB7d2lkdGg6MzMwcHg7Ym9yZGVyLXJhZGl1czoxOHB4O292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOiMwNzEzMWY7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuNDIpO2JveC1zaGFkb3c6MCAwIDQwcHggcmdiYSgwLDIxNiwyNTUsLjI1KSwwIDI1cHggNjVweCByZ2JhKDAsMCwwLC40OCl9LnN0b3BQb3B1cEltYWdle2hlaWdodDoxODVweDtiYWNrZ3JvdW5kOiMxMDJhNDB9LnN0b3BQb3B1cEltYWdlIGltZ3t3aWR0aDoxMDAlO2hlaWdodDoxMDAlO2Rpc3BsYXk6YmxvY2s7b2JqZWN0LWZpdDpjb3Zlcn0uc3RvcFBvcHVwQm9keXtwYWRkaW5nOjEzcHggMTVweCAxNXB4fS5wb3B1cEtpY2tlcntkaXNwbGF5OmlubGluZS1mbGV4O3BhZGRpbmc6NXB4IDhweDtib3JkZXItcmFkaXVzOjhweDtiYWNrZ3JvdW5kOnJnYmEoMCwyMTYsMjU1LC4xNSk7Y29sb3I6dmFyKC0tY3lhbik7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6OTAwfS5wb3B1cFRpdGxle21hcmdpbi10b3A6OXB4O2ZvbnQtc2l6ZToxOXB4O2ZvbnQtd2VpZ2h0Ojk1MH0ucG9wdXBNZXRhe21hcmdpbi10b3A6NnB4O2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTJweH0ucG9wdXBCdXR0b25ze2Rpc3BsYXk6ZmxleDtnYXA6OHB4O21hcmdpbi10b3A6MTJweH0ucG9wdXBCdXR0b25zIGJ1dHRvbntoZWlnaHQ6NDBweDtmbGV4OjE7Zm9udC1zaXplOjEycHh9LnBvcHVwQnV0dG9ucyAuZGFuZ2Vye2ZsZXg6MCAwIDQycHg7Y29sb3I6dmFyKC0tcmVkKX0KLm1lZGlhU3RyaXB7bWluLXdpZHRoOjA7cGFkZGluZzoxM3B4IDE3cHggMTVweDtib3JkZXItdG9wOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMTIpO2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDE4MGRlZyxyZ2JhKDQsMTIsMjAsLjcyKSxyZ2JhKDMsOSwxNiwuOTUpKX0ubWVkaWFIZWFkZXJ7aGVpZ2h0OjMxcHg7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTFweH0ubWVkaWFUaXRsZXtmb250LXNpemU6MTRweDtmb250LXdlaWdodDo5NTB9Lm1lZGlhQ291bnR7Zm9udC1zaXplOjEycHg7Y29sb3I6dmFyKC0tbXV0ZWQpfS5tZWRpYUhlYWRlclNwYWNlcntmbGV4OjF9LnRpbnlCdXR0b257d2lkdGg6MzFweDtoZWlnaHQ6MzFweDtwYWRkaW5nOjA7Ym9yZGVyLXJhZGl1czoxMHB4fS5nYWxsZXJ5e2hlaWdodDoxNjRweDtkaXNwbGF5OmZsZXg7Z2FwOjEwcHg7b3ZlcmZsb3cteDphdXRvO292ZXJmbG93LXk6aGlkZGVuO3BhZGRpbmc6OHB4IDFweCA0cHg7c2Nyb2xsYmFyLXdpZHRoOnRoaW59Lm1lZGlhVGlsZXtwb3NpdGlvbjpyZWxhdGl2ZTtmbGV4OjAgMCAyMThweDtoZWlnaHQ6MTQ1cHg7Ym9yZGVyLXJhZGl1czoxM3B4O292ZXJmbG93OmhpZGRlbjtiYWNrZ3JvdW5kOiMxMDIyMzU7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDcxLDEyMywxNjAsLjM1KTtjdXJzb3I6cG9pbnRlcjt0cmFuc2l0aW9uOi4xNnMgZWFzZX0ubWVkaWFUaWxlOmhvdmVyLC5tZWRpYVRpbGUuYWN0aXZle2JvcmRlci1jb2xvcjp2YXIoLS1jeWFuKTtib3gtc2hhZG93OjAgMCAyMXB4IHJnYmEoMCwyMTYsMjU1LC4yNCk7dHJhbnNmb3JtOnRyYW5zbGF0ZVkoLTJweCl9Lm1lZGlhVGlsZSBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtvYmplY3QtZml0OmNvdmVyO2Rpc3BsYXk6YmxvY2t9Lm1lZGlhVGlsZU5hbWV7cG9zaXRpb246YWJzb2x1dGU7bGVmdDowO3JpZ2h0OjA7Ym90dG9tOjA7cGFkZGluZzoyNXB4IDEwcHggOXB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KHRyYW5zcGFyZW50LHJnYmEoMSw2LDExLC45KSk7Zm9udC1zaXplOjExcHg7Zm9udC13ZWlnaHQ6ODUwO3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30KLnJpZ2h0UmFpbHttaW4td2lkdGg6MDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSg0LDEyLDIxLC45NykscmdiYSgyLDgsMTUsLjk5KSk7Ym9yZGVyLWxlZnQ6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4xNCk7cGFkZGluZzoxNXB4IDE1cHggMTdweDtkaXNwbGF5OmZsZXg7ZmxleC1kaXJlY3Rpb246Y29sdW1uO292ZXJmbG93OmhpZGRlbn0ucmlnaHRUb3B7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtoZWlnaHQ6NDBweH0ucmlnaHRUaXRsZXtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo5NTA7dGV4dC10cmFuc2Zvcm06dXBwZXJjYXNlO2xldHRlci1zcGFjaW5nOi4wNGVtfS5yaWdodENvdW50e2NvbG9yOnZhcigtLW11dGVkKTttYXJnaW4tbGVmdDo1cHh9LnJpZ2h0U2VhcmNoe21hcmdpbi1sZWZ0OmF1dG87d2lkdGg6MzVweDtoZWlnaHQ6MzVweDtwYWRkaW5nOjA7YmFja2dyb3VuZDp0cmFuc3BhcmVudDtib3JkZXI6MDtib3gtc2hhZG93Om5vbmV9LnN0b3BTZWFyY2hXcmFwe2Rpc3BsYXk6bm9uZTttYXJnaW4tYm90dG9tOjEwcHh9LnN0b3BTZWFyY2hXcmFwLnNob3d7ZGlzcGxheTpibG9ja30uc3RvcExpc3R7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6OXB4O292ZXJmbG93OmF1dG87bWluLWhlaWdodDoyNTBweDtmbGV4OjEgMSAwO3BhZGRpbmc6MnB4IDRweCAxMnB4IDB9LnN0b3BDYXJke2ZsZXg6MCAwIGF1dG87bWluLWhlaWdodDo3NnB4O2JvcmRlci1yYWRpdXM6MTNweDtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxODBkZWcscmdiYSgxMywyOCw0NCwuOTYpLHJnYmEoOCwyMCwzMywuOTYpKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjEsMTA4LDE0MywuMzQpO292ZXJmbG93OmhpZGRlbjt0cmFuc2l0aW9uOi4xNXMgZWFzZX0uc3RvcENhcmQ6aG92ZXIsLnN0b3BDYXJkLmFjdGl2ZXtib3JkZXItY29sb3I6dmFyKC0tY3lhbik7Ym94LXNoYWRvdzppbnNldCA0cHggMCAwIHZhcigtLWN5YW4pLDAgMCAxOHB4IHJnYmEoMCwyMTYsMjU1LC4xMyl9LnN0b3BTdW1tYXJ5e21pbi1oZWlnaHQ6NzZweDtwYWRkaW5nOjEycHggMTJweDtkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjMxcHggbWlubWF4KDAsMWZyKSAyMnB4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTBweDtjdXJzb3I6cG9pbnRlcn0uc3RvcE51bWJlcnt3aWR0aDoyOXB4O2hlaWdodDoyOXB4O2JvcmRlci1yYWRpdXM6OTk5cHg7ZGlzcGxheTpncmlkO3BsYWNlLWl0ZW1zOmNlbnRlcjtiYWNrZ3JvdW5kOnJnYmEoMCwyMTYsMjU1LC4xMik7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzUpO2ZvbnQtc2l6ZToxMnB4O2ZvbnQtd2VpZ2h0Ojk1MDt0ZXh0LWFsaWduOmNlbnRlcn0uc3RvcE5hbWV7Zm9udC1zaXplOjEzcHg7Zm9udC13ZWlnaHQ6OTUwO3doaXRlLXNwYWNlOm5vd3JhcDtvdmVyZmxvdzpoaWRkZW47dGV4dC1vdmVyZmxvdzplbGxpcHNpc30uc3RvcE1ldGF7bWFyZ2luLXRvcDo1cHg7Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxMC41cHg7bGluZS1oZWlnaHQ6MS4zNX0uc3RvcENoZXZyb257Y29sb3I6dmFyKC0tbXV0ZWQpO2ZvbnQtc2l6ZToxOHB4O3RyYW5zaXRpb246LjE1c30uc3RvcENhcmQub3BlbiAuc3RvcENoZXZyb257dHJhbnNmb3JtOnJvdGF0ZSg5MGRlZyl9LnN0b3BDb250cm9sc3tkaXNwbGF5Om5vbmU7cGFkZGluZzowIDEycHggMTJweCA1M3B4O2dhcDo2cHg7ZmxleC13cmFwOndyYXB9LnN0b3BDYXJkLm9wZW4gLnN0b3BDb250cm9sc3tkaXNwbGF5OmZsZXh9LnN0b3BDb250cm9scyBidXR0b257aGVpZ2h0OjMycHg7cGFkZGluZzowIDlweDtmb250LXNpemU6MTBweH0uYWRkU3RvcEJ1dHRvbntmbGV4OjAgMCBhdXRvO2hlaWdodDo0MnB4O3dpZHRoOjEwMCU7bWFyZ2luOjRweCAwIDEycHh9LmFzc2V0QnViYmxle3dpZHRoOjUycHg7aGVpZ2h0OjUycHg7Ym9yZGVyLXJhZGl1czo1MCU7b3ZlcmZsb3c6aGlkZGVuO2JvcmRlcjozcHggc29saWQgIzAwZDhmZjtiYWNrZ3JvdW5kOiMwNjExMWQ7Ym94LXNoYWRvdzowIDAgMCAzcHggcmdiYSg0LDE3LDI4LC45MiksMCAwIDIycHggcmdiYSgwLDIxNiwyNTUsLjUyKTtjdXJzb3I6cG9pbnRlcjt0cmFuc2l0aW9uOi4xNnN9LmFzc2V0QnViYmxlOmhvdmVyLC5hc3NldEJ1YmJsZS5hY3RpdmV7dHJhbnNmb3JtOnNjYWxlKDEuMTIpO2JvcmRlci1jb2xvcjp3aGl0ZTt6LWluZGV4OjE1fS5hc3NldEJ1YmJsZSBpbWd7d2lkdGg6MTAwJTtoZWlnaHQ6MTAwJTtkaXNwbGF5OmJsb2NrO29iamVjdC1maXQ6Y292ZXJ9LmFzc2V0QnViYmxlIC5hc3NldERvdHt3aWR0aDoxMDAlO2hlaWdodDoxMDAlO2Rpc3BsYXk6Z3JpZDtwbGFjZS1pdGVtczpjZW50ZXI7Y29sb3I6dmFyKC0tY3lhbik7Zm9udC1zaXplOjE5cHh9Ci5leHBvcnRCb3h7ZmxleDowIDAgYXV0bztib3JkZXI6MXB4IHNvbGlkIHJnYmEoNjIsMTExLDE0OCwuMzApO2JvcmRlci1yYWRpdXM6MTRweDtiYWNrZ3JvdW5kOnJnYmEoOCwxOSwzMSwuOTApO292ZXJmbG93OmhpZGRlbn0uZXhwb3J0SGVhZGVye2hlaWdodDo0OHB4O3BhZGRpbmc6MCAxM3B4O2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OnNwYWNlLWJldHdlZW47Zm9udC1zaXplOjEzcHg7Zm9udC13ZWlnaHQ6OTUwO2N1cnNvcjpwb2ludGVyfS5leHBvcnRCb2R5e3BhZGRpbmc6MCAxMnB4IDEycHh9LmV4cG9ydEJveC5jb2xsYXBzZWQgLmV4cG9ydEJvZHl7ZGlzcGxheTpub25lfS5leHBvcnRUYWJze2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLWNvbHVtbnM6MWZyIDFmciAxZnI7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDYzLDExMywxNTAsLjMzKTtib3JkZXItcmFkaXVzOjEwcHg7b3ZlcmZsb3c6aGlkZGVuO21hcmdpbjo3cHggMCAxMnB4fS5leHBvcnRUYWJzIGJ1dHRvbntib3JkZXI6MDtib3JkZXItcmFkaXVzOjA7aGVpZ2h0OjM2cHg7YmFja2dyb3VuZDojMDcxMzFmO2ZvbnQtc2l6ZToxMHB4fS5leHBvcnRUYWJzIGJ1dHRvbi5hY3RpdmV7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLCMwODc5YzMsIzAwYTljOSk7Ym94LXNoYWRvdzpub25lfS5maWVsZExhYmVse2Rpc3BsYXk6YmxvY2s7Zm9udC1zaXplOjEwcHg7Y29sb3I6dmFyKC0tbXV0ZWQpO21hcmdpbjoxMHB4IDAgNXB4fS5hdWRpb1Jvd3tkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuO2NvbG9yOnZhcigtLXNvZnQpO2ZvbnQtc2l6ZToxMXB4fS5zd2l0Y2h7d2lkdGg6MzlweDtoZWlnaHQ6MjFweDtib3JkZXItcmFkaXVzOjk5OXB4O2JhY2tncm91bmQ6IzIwMzc0YTtib3JkZXI6MXB4IHNvbGlkICMzNTUzNmE7cG9zaXRpb246cmVsYXRpdmU7Y3Vyc29yOnBvaW50ZXJ9LnN3aXRjaDphZnRlcntjb250ZW50OiIiO3Bvc2l0aW9uOmFic29sdXRlO3RvcDoycHg7bGVmdDoycHg7d2lkdGg6MTVweDtoZWlnaHQ6MTVweDtib3JkZXItcmFkaXVzOjUwJTtiYWNrZ3JvdW5kOiNkY2VhZjQ7dHJhbnNpdGlvbjouMTZzfS5zd2l0Y2gub257YmFja2dyb3VuZDojMDBhOWNlO2JvcmRlci1jb2xvcjojMjBlMWZmfS5zd2l0Y2gub246YWZ0ZXJ7bGVmdDoyMHB4fS5hdWRpb0lucHV0e2Rpc3BsYXk6bm9uZX0ucmVuZGVyQnV0dG9ue3dpZHRoOjEwMCU7aGVpZ2h0OjU1cHg7bWFyZ2luLXRvcDoxMXB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjMDg3ZGEzLCMxMWJhY2UpO2JvcmRlci1jb2xvcjpyZ2JhKDAsMjE2LDI1NSwuNzUpO2ZvbnQtc2l6ZToxNHB4fS5yZW5kZXJCdXR0b24gc3BhbntkaXNwbGF5OmJsb2NrO2ZvbnQtc2l6ZToxMHB4O2ZvbnQtd2VpZ2h0OjY1MDtvcGFjaXR5Oi44NTttYXJnaW4tdG9wOjJweH0KLm1vZGFse3Bvc2l0aW9uOmZpeGVkO2luc2V0OjA7ei1pbmRleDoxMDAwO2Rpc3BsYXk6bm9uZTthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OmNlbnRlcjtwYWRkaW5nOjI0cHg7YmFja2dyb3VuZDpyZ2JhKDAsNCw5LC43NSk7YmFja2Ryb3AtZmlsdGVyOmJsdXIoN3B4KX0ubW9kYWwuc2hvd3tkaXNwbGF5OmZsZXh9Lm1vZGFsQ2FyZHt3aWR0aDptaW4oNzIwcHgsOTR2dyk7bWF4LWhlaWdodDo5MHZoO292ZXJmbG93OmF1dG87cGFkZGluZzoyMXB4O2JvcmRlci1yYWRpdXM6MTlweDtiYWNrZ3JvdW5kOiMwNzEzMWY7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzUpO2JveC1zaGFkb3c6MCAwIDYwcHggcmdiYSgwLDIxNiwyNTUsLjE4KSwwIDM1cHggMTAwcHggcmdiYSgwLDAsMCwuNTUpfS5tb2RhbFRpdGxle2ZvbnQtc2l6ZToyMXB4O2ZvbnQtd2VpZ2h0Ojk1MDttYXJnaW4tYm90dG9tOjE1cHh9LmZvcm1Hcmlke2Rpc3BsYXk6Z3JpZDtnYXA6MTFweH0udHdvQ29se2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLWNvbHVtbnM6MWZyIDFmcjtnYXA6MTFweH0ubW9kYWxBY3Rpb25ze2Rpc3BsYXk6ZmxleDtqdXN0aWZ5LWNvbnRlbnQ6ZmxleC1lbmQ7Z2FwOjlweDttYXJnaW4tdG9wOjZweH0ubW9kYWxBY3Rpb25zIGJ1dHRvbntoZWlnaHQ6NDJweDtwYWRkaW5nOjAgMTZweH0ucHJpbWFyeXtiYWNrZ3JvdW5kOmxpbmVhci1ncmFkaWVudCgxMzVkZWcsIzA3NWRiNCwjMDBhZWNiKTtib3JkZXItY29sb3I6dmFyKC0tY3lhbil9Ci50b2FzdHtwb3NpdGlvbjpmaXhlZDtsZWZ0OjMwNXB4O2JvdHRvbToxOHB4O3otaW5kZXg6MzAwMDtkaXNwbGF5Om5vbmU7cGFkZGluZzoxMXB4IDE0cHg7Ym9yZGVyLXJhZGl1czoxMnB4O2JhY2tncm91bmQ6cmdiYSg2LDE5LDMxLC45NSk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzIpO2JveC1zaGFkb3c6MCAxNXB4IDQwcHggcmdiYSgwLDAsMCwuMzUpO2ZvbnQtc2l6ZToxMnB4fS50b2FzdC5zaG93e2Rpc3BsYXk6YmxvY2t9Ci5wcmVzZW50T3ZlcmxheXtwb3NpdGlvbjpmaXhlZDtpbnNldDowO3otaW5kZXg6MjIwMDtkaXNwbGF5Om5vbmU7YmFja2dyb3VuZDojMDIwNzEwfS5wcmVzZW50T3ZlcmxheS5zaG93e2Rpc3BsYXk6Z3JpZDtncmlkLXRlbXBsYXRlLXJvd3M6NzJweCBtaW5tYXgoMCwxZnIpIDE3MHB4fS5wcmVzZW50SGVhZGVye2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjEzcHg7cGFkZGluZzoxMHB4IDE4cHg7Ym9yZGVyLWJvdHRvbToxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjE2KTtiYWNrZ3JvdW5kOnJnYmEoMywxMCwxOCwuOTApfS5wcmVzZW50SGVhZGVyVGl0bGV7Zm9udC1zaXplOjIwcHg7Zm9udC13ZWlnaHQ6OTUwfS5wcmVzZW50SGVhZGVyTWV0YXtjb2xvcjp2YXIoLS1tdXRlZCk7Zm9udC1zaXplOjExcHg7bWFyZ2luLXRvcDozcHh9LnByZXNlbnRIZWFkZXJTcGFjZXJ7ZmxleDoxfS5wcmVzZW50TWFpbntwb3NpdGlvbjpyZWxhdGl2ZTttaW4taGVpZ2h0OjB9LnByZXNlbnRNYXB7cG9zaXRpb246YWJzb2x1dGU7aW5zZXQ6MH0ucHJlc2VudFN0b3BSYWlse3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6MThweDt0b3A6MThweDtib3R0b206MThweDt3aWR0aDoyNDBweDt6LWluZGV4OjQ7cGFkZGluZzoxMnB4O2JvcmRlci1yYWRpdXM6MTZweDtiYWNrZ3JvdW5kOnJnYmEoNCwxNCwyNCwuODQpO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjI0KTtiYWNrZHJvcC1maWx0ZXI6Ymx1cigxNXB4KTtvdmVyZmxvdzphdXRvfS5wcmVzZW50U3RvcEl0ZW17cGFkZGluZzoxMHB4O2JvcmRlci1yYWRpdXM6MTBweDtjb2xvcjojYjRjOGQ4O2ZvbnQtc2l6ZToxMnB4O2N1cnNvcjpwb2ludGVyfS5wcmVzZW50U3RvcEl0ZW0uYWN0aXZle2JhY2tncm91bmQ6cmdiYSgwLDIxNiwyNTUsLjE0KTtjb2xvcjp3aGl0ZTtib3gtc2hhZG93Omluc2V0IDNweCAwIDAgdmFyKC0tY3lhbil9LnByZXNlbnRTdG9wQmFubmVye3Bvc2l0aW9uOmFic29sdXRlO2xlZnQ6NTAlO3RvcDoxOHB4O3RyYW5zZm9ybTp0cmFuc2xhdGVYKC01MCUpO3otaW5kZXg6NzttaW4td2lkdGg6NDIwcHg7bWF4LXdpZHRoOjcyMHB4O3BhZGRpbmc6MTRweCAyMHB4O2JvcmRlci1yYWRpdXM6MTdweDtiYWNrZ3JvdW5kOnJnYmEoNCwxNCwyNCwuODgpO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjMwKTtib3gtc2hhZG93OjAgMjJweCA1NXB4IHJnYmEoMCwwLDAsLjQyKSwwIDAgMzBweCByZ2JhKDAsMjE2LDI1NSwuMTIpO2JhY2tkcm9wLWZpbHRlcjpibHVyKDE1cHgpO3RleHQtYWxpZ246Y2VudGVyfS5wcmVzZW50U3RvcEJhbm5lclRpdGxle2ZvbnQtc2l6ZToyNHB4O2ZvbnQtd2VpZ2h0Ojk1MH0ucHJlc2VudFN0b3BCYW5uZXJSYW5nZXttYXJnaW4tdG9wOjRweDtjb2xvcjojYjhjY2RhO2ZvbnQtc2l6ZToxMnB4fS5wcmVzZW50UGhvdG9DYXJke3Bvc2l0aW9uOmFic29sdXRlO3JpZ2h0OjIycHg7dG9wOjk2cHg7d2lkdGg6bWluKDQ4MHB4LDM4dncpO21heC1oZWlnaHQ6Y2FsYygxMDAlIC0gMTgwcHgpO3otaW5kZXg6ODtib3JkZXItcmFkaXVzOjE4cHg7b3ZlcmZsb3c6aGlkZGVuO2JhY2tncm91bmQ6cmdiYSg1LDE1LDI1LC45Nyk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDAsMjE2LDI1NSwuMzgpO2JveC1zaGFkb3c6MCAwIDQycHggcmdiYSgwLDIxNiwyNTUsLjIwKSwwIDI1cHggNjBweCByZ2JhKDAsMCwwLC41KTtkaXNwbGF5Om5vbmV9LnByZXNlbnRQaG90b0NhcmQuc2hvd3tkaXNwbGF5OmJsb2NrfS5wcmVzZW50UGhvdG9DYXJkIGltZ3t3aWR0aDoxMDAlO21heC1oZWlnaHQ6NTZ2aDtvYmplY3QtZml0OmNvbnRhaW47ZGlzcGxheTpibG9jaztiYWNrZ3JvdW5kOiMwMTA0MDl9LnByZXNlbnRQaG90b0JvZHl7cGFkZGluZzoxNHB4IDE2cHh9LnByZXNlbnRQaG90b1RpdGxle2ZvbnQtc2l6ZToxNnB4O2ZvbnQtd2VpZ2h0Ojk1MDt3aGl0ZS1zcGFjZTpub3dyYXA7b3ZlcmZsb3c6aGlkZGVuO3RleHQtb3ZlcmZsb3c6ZWxsaXBzaXN9LnByZXNlbnRQaG90b01ldGF7Y29sb3I6I2Q1ZTdmMTtmb250LXNpemU6MTNweDttYXJnaW4tdG9wOjZweDtsZXR0ZXItc3BhY2luZzouMDJlbX0ucHJlc2VudFBob3RvQ29vcmRze2NvbG9yOnZhcigtLW11dGVkKTtmb250LXNpemU6MTBweDttYXJnaW4tdG9wOjVweH0ucHJlc2VudEh1ZHtwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjUwJTtib3R0b206MThweDt0cmFuc2Zvcm06dHJhbnNsYXRlWCgtNTAlKTt6LWluZGV4OjY7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6OHB4O3BhZGRpbmc6OHB4O2JvcmRlci1yYWRpdXM6MTZweDtiYWNrZ3JvdW5kOnJnYmEoNCwxNCwyNCwuODYpO2JvcmRlcjoxcHggc29saWQgcmdiYSgwLDIxNiwyNTUsLjIyKTtiYWNrZHJvcC1maWx0ZXI6Ymx1cigxMnB4KX0ucHJlc2VudEh1ZCBidXR0b257aGVpZ2h0OjQycHg7cGFkZGluZzowIDE0cHg7Zm9udC1zaXplOjExcHh9LnByZXNlbnRIdWQgLnBsYXl7bWluLXdpZHRoOjExMHB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDEzNWRlZywjNjAzY2ZmLCMwMGFkY2IpfS5wcmVzZW50RmlsbXN0cmlwe3BhZGRpbmc6MTJweCAxOHB4O2JhY2tncm91bmQ6bGluZWFyLWdyYWRpZW50KDE4MGRlZywjMDYxMTFkLCMwMjA3MTEpO2JvcmRlci10b3A6MXB4IHNvbGlkIHJnYmEoMCwyMTYsMjU1LC4xNCk7ZGlzcGxheTpmbGV4O2dhcDoxMHB4O292ZXJmbG93LXg6YXV0b30ucHJlc2VudFRodW1ie2ZsZXg6MCAwIDE5MHB4O2hlaWdodDoxNDBweDtib3JkZXItcmFkaXVzOjEzcHg7b3ZlcmZsb3c6aGlkZGVuO2JvcmRlcjoxcHggc29saWQgcmdiYSg2OSwxMjEsMTU4LC4zNCk7Y3Vyc29yOnBvaW50ZXI7cG9zaXRpb246cmVsYXRpdmV9LnByZXNlbnRUaHVtYi5hY3RpdmV7Ym9yZGVyLWNvbG9yOnZhcigtLWN5YW4pO2JveC1zaGFkb3c6MCAwIDIxcHggcmdiYSgwLDIxNiwyNTUsLjI4KX0ucHJlc2VudFRodW1iIGltZ3t3aWR0aDoxMDAlO2hlaWdodDoxMDAlO2Rpc3BsYXk6YmxvY2s7b2JqZWN0LWZpdDpjb3Zlcn0ucHJlc2VudFRodW1iTGFiZWx7cG9zaXRpb246YWJzb2x1dGU7aW5zZXQ6YXV0byAwIDA7cGFkZGluZzoyNHB4IDhweCA3cHg7YmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQodHJhbnNwYXJlbnQscmdiYSgwLDAsMCwuODUpKTtmb250LXNpemU6MTBweDtmb250LXdlaWdodDo4MDB9CkBtZWRpYShtYXgtd2lkdGg6MTMwMHB4KXsuYXBwU2hlbGx7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOjI1MHB4IG1pbm1heCg1ODBweCwxZnIpIDMyMHB4fS5sZWZ0UmFpbHtwYWRkaW5nLWxlZnQ6MTNweDtwYWRkaW5nLXJpZ2h0OjEzcHh9LndvcmRtYXJre2ZvbnQtc2l6ZToyN3B4fS5wcmVzZW50QnV0dG9ue21pbi13aWR0aDoyMjBweH0udGl0bGVBcmVhe21pbi13aWR0aDoyNDBweH0udG9wQWN0aW9ue21pbi13aWR0aDoxMTBweH0ubWVkaWFUaWxle2ZsZXgtYmFzaXM6MTg1cHh9fQo8L3N0eWxlPgo8L2hlYWQ+Cjxib2R5Pgo8ZGl2IGNsYXNzPSJhcHBTaGVsbCI+CiAgPGFzaWRlIGNsYXNzPSJsZWZ0UmFpbCI+CiAgICA8ZGl2IGNsYXNzPSJicmFuZExpbmUiPgogICAgICA8ZGl2IGNsYXNzPSJsb2dvRmxvd2VyIj48c3BhbiBjbGFzcz0icGV0YWwgcDEiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDIiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDMiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDQiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDUiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDYiPjwvc3Bhbj48L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0id29yZG1hcmsiPnRyaXBweTwvZGl2PjxkaXYgY2xhc3M9InZlcnNpb24iPnYxMC4yLjM8L2Rpdj4KICAgIDwvZGl2PgogICAgPGJ1dHRvbiBpZD0ibmV3SW1taWNoQnV0dG9uIiBjbGFzcz0ic2lkZVByaW1hcnkiPu+8iyZuYnNwOyBOZXcgSW1taWNoIEpvdXJuZXk8L2J1dHRvbj4KICAgIDxidXR0b24gaWQ9InVwbG9hZEJ1dHRvbiIgY2xhc3M9InNpZGVTZWNvbmRhcnkiPuKHpyZuYnNwOyBVcGxvYWQgTWVkaWE8L2J1dHRvbj4KICAgIDxkaXYgY2xhc3M9InNlY3Rpb25MYWJlbCI+PHNwYW4+UHJvamVjdHM8L3NwYW4+PGJ1dHRvbiBpZD0icHJvamVjdFNlYXJjaEJ1dHRvbiIgY2xhc3M9InByb2plY3RNZW51Ij7ijJU8L2J1dHRvbj48L2Rpdj4KICAgIDxpbnB1dCBpZD0icHJvamVjdFNlYXJjaCIgY2xhc3M9ImhpZGRlbiIgcGxhY2Vob2xkZXI9IlNlYXJjaCBwcm9qZWN0c+KApiI+CiAgICA8ZGl2IGlkPSJwcm9qZWN0TGlzdCIgY2xhc3M9InByb2plY3RMaXN0Ij48L2Rpdj4KICAgIDxkaXYgY2xhc3M9ImxlZnRGb290ZXIiPlBsYW4sIG9yZ2FuaXplLCBhbmQgcmVsaXZlIHlvdXIgYWR2ZW50dXJlcyBvbiB0aGUgbWFwLgogICAgICA8YSBjbGFzcz0iZm9vdGVyTGluayIgaHJlZj0iIyI+4pajJm5ic3A7IERvY3VtZW50YXRpb248L2E+PGEgY2xhc3M9ImZvb3RlckxpbmsiIGhyZWY9IiMiPuKXjiZuYnNwOyBDaGFuZ2Vsb2c8L2E+CiAgICA8L2Rpdj4KICA8L2FzaWRlPgoKICA8bWFpbiBjbGFzcz0id29ya3NwYWNlIj4KICAgIDxoZWFkZXIgY2xhc3M9InRvcEJhciI+CiAgICAgIDxkaXYgY2xhc3M9InRpdGxlQXJlYSI+PGRpdiBjbGFzcz0iam91cm5leVRpdGxlUm93Ij48ZGl2IGlkPSJqb3VybmV5VGl0bGUiIGNsYXNzPSJqb3VybmV5VGl0bGUiPk5vIGpvdXJuZXkgc2VsZWN0ZWQ8L2Rpdj48YnV0dG9uIGlkPSJyZW5hbWVQcm9qZWN0QnV0dG9uIiBjbGFzcz0iZWRpdFRpdGxlIj7inI48L2J1dHRvbj48L2Rpdj48ZGl2IGlkPSJqb3VybmV5TWV0YSIgY2xhc3M9ImpvdXJuZXlNZXRhIj5Mb2FkIG9yIGNyZWF0ZSBhIGpvdXJuZXk8L2Rpdj48L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0idG9wU3BhY2VyIj48L2Rpdj4KICAgICAgPGJ1dHRvbiBpZD0icHJlc2VudEJ1dHRvbiIgY2xhc3M9InByZXNlbnRCdXR0b24iPuKWtiZuYnNwOyBQcmVzZW50IEpvdXJuZXk8c3Bhbj5JbW1lcnNpdmUgcm91dGUgcGxheWJhY2s8L3NwYW4+PC9idXR0b24+CiAgICAgIDxidXR0b24gaWQ9ImV4cG9ydEp1bXBCdXR0b24iIGNsYXNzPSJ0b3BBY3Rpb24iPuKWoyZuYnNwOyBFeHBvcnQ8YnI+PHNwYW4gY2xhc3M9InNtYWxsIj5SZW5kZXIsIEdQWCwgYW5kIG1vcmUmbmJzcDvijIQ8L3NwYW4+PC9idXR0b24+CiAgICAgIDxidXR0b24gaWQ9InNldHRpbmdzQnV0dG9uIiBjbGFzcz0iZ2VhckJ1dHRvbiI+4pqZPC9idXR0b24+CiAgICAgIDxidXR0b24gaWQ9ImFjY291bnRCdXR0b24iIGNsYXNzPSJ0b3BBY3Rpb24iPuKZmSZuYnNwOyBBY2NvdW50Jm5ic3A74oyEPC9idXR0b24+CiAgICA8L2hlYWRlcj4KCiAgICA8c2VjdGlvbiBjbGFzcz0ibWFwWm9uZSI+PGRpdiBjbGFzcz0ibWFwRnJhbWUiPjxkaXYgaWQ9Im1hcCIgY2xhc3M9Im1hcENhbnZhcyI+PC9kaXY+PGRpdiBjbGFzcz0ibWFwU2hhZGUiPjwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJtYXBUb29scyI+CiAgICAgICAgPGJ1dHRvbiBpZD0ibG9jYXRlQnV0dG9uIiBjbGFzcz0ibWFwVG9vbCI+4p6kPC9idXR0b24+PGJ1dHRvbiBpZD0ibGlnaHRNYXBCdXR0b24iIGNsYXNzPSJtYXBUb29sIGFjdGl2ZSI+4perPC9idXR0b24+PGJ1dHRvbiBpZD0iZGFya01hcEJ1dHRvbiIgY2xhc3M9Im1hcFRvb2wiPuKXkDwvYnV0dG9uPjxidXR0b24gaWQ9InNhdGVsbGl0ZU1hcEJ1dHRvbiIgY2xhc3M9Im1hcFRvb2wiPuKWpzwvYnV0dG9uPgogICAgICAgIDxkaXYgY2xhc3M9Im1hcFpvb21Hcm91cCI+PGJ1dHRvbiBpZD0iem9vbUluQnV0dG9uIiBjbGFzcz0ibWFwVG9vbCI+77yLPC9idXR0b24+PGJ1dHRvbiBpZD0iem9vbU91dEJ1dHRvbiIgY2xhc3M9Im1hcFRvb2wiPuKIkjwvYnV0dG9uPjwvZGl2PgogICAgICA8L2Rpdj4KICAgICAgPGRpdiBpZD0iZmlsdGVyQ2hpcCIgY2xhc3M9ImZpbHRlckNoaXAiPjxzcGFuPuKWviZuYnNwOyA8YiBpZD0iZmlsdGVyQ2hpcFRleHQiPkZpbHRlcjogQWxsIFN0b3BzPC9iPjwvc3Bhbj48YnV0dG9uIGlkPSJjbGVhckZpbHRlckJ1dHRvbiI+w5c8L2J1dHRvbj48L2Rpdj4KICAgIDwvZGl2Pjwvc2VjdGlvbj4KCiAgICA8c2VjdGlvbiBjbGFzcz0ibWVkaWFTdHJpcCI+PGRpdiBjbGFzcz0ibWVkaWFIZWFkZXIiPjxkaXYgaWQ9Im1lZGlhVGl0bGUiIGNsYXNzPSJtZWRpYVRpdGxlIj5NZWRpYTwvZGl2PjxkaXYgaWQ9Im1lZGlhQ291bnQiIGNsYXNzPSJtZWRpYUNvdW50Ij48L2Rpdj48ZGl2IGNsYXNzPSJtZWRpYUhlYWRlclNwYWNlciI+PC9kaXY+PGJ1dHRvbiBjbGFzcz0idGlueUJ1dHRvbiI+4pamPC9idXR0b24+PGJ1dHRvbiBjbGFzcz0idGlueUJ1dHRvbiI+4pi3PC9idXR0b24+PC9kaXY+PGRpdiBpZD0iZ2FsbGVyeSIgY2xhc3M9ImdhbGxlcnkiPjwvZGl2Pjwvc2VjdGlvbj4KICA8L21haW4+CgogIDxhc2lkZSBjbGFzcz0icmlnaHRSYWlsIj4KICAgIDxkaXYgY2xhc3M9InJpZ2h0VG9wIj48ZGl2IGNsYXNzPSJyaWdodFRpdGxlIj5TdG9wcyA8c3BhbiBpZD0ic3RvcENvdW50IiBjbGFzcz0icmlnaHRDb3VudCI+KDApPC9zcGFuPjwvZGl2PjxidXR0b24gaWQ9InN0b3BTZWFyY2hCdXR0b24iIGNsYXNzPSJyaWdodFNlYXJjaCI+4oyVPC9idXR0b24+PC9kaXY+CiAgICA8ZGl2IGlkPSJzdG9wU2VhcmNoV3JhcCIgY2xhc3M9InN0b3BTZWFyY2hXcmFwIj48aW5wdXQgaWQ9InN0b3BTZWFyY2giIHBsYWNlaG9sZGVyPSJTZWFyY2ggc3RvcHPigKYiPjwvZGl2PgogICAgPGRpdiBpZD0ic3RvcExpc3QiIGNsYXNzPSJzdG9wTGlzdCI+PC9kaXY+CiAgICA8YnV0dG9uIGlkPSJhZGRTdG9wQnV0dG9uIiBjbGFzcz0iYWRkU3RvcEJ1dHRvbiI+77yLJm5ic3A7IEFkZCBTdG9wIE1hbnVhbGx5PC9idXR0b24+CiAgICA8c2VjdGlvbiBpZD0iZXhwb3J0Qm94IiBjbGFzcz0iZXhwb3J0Qm94Ij48ZGl2IGlkPSJleHBvcnRIZWFkZXIiIGNsYXNzPSJleHBvcnRIZWFkZXIiPjxzcGFuPkV4cG9ydCAmYW1wOyBSZW5kZXI8L3NwYW4+PHNwYW4+4oyDPC9zcGFuPjwvZGl2PjxkaXYgY2xhc3M9ImV4cG9ydEJvZHkiPgogICAgICA8c3BhbiBjbGFzcz0iZmllbGRMYWJlbCI+RXhwb3J0IEZvcm1hdDwvc3Bhbj48ZGl2IGNsYXNzPSJleHBvcnRUYWJzIj48YnV0dG9uIGNsYXNzPSJhY3RpdmUiPlZpZGVvIChNUDQpPC9idXR0b24+PGJ1dHRvbiBpZD0iZ3B4QnV0dG9uIj5HUFggVHJhY2s8L2J1dHRvbj48YnV0dG9uIGlkPSJpbWFnZVNldEJ1dHRvbiI+SW1hZ2UgU2V0PC9idXR0b24+PC9kaXY+CiAgICAgIDxzcGFuIGNsYXNzPSJmaWVsZExhYmVsIj5RdWFsaXR5PC9zcGFuPjxzZWxlY3QgaWQ9InF1YWxpdHlTZWxlY3QiPjxvcHRpb24+MTA4MHAgKEhpZ2gpPC9vcHRpb24+PG9wdGlvbj43MjBwPC9vcHRpb24+PC9zZWxlY3Q+CiAgICAgIDxkaXYgY2xhc3M9ImF1ZGlvUm93Ij48ZGl2PjxiPkluY2x1ZGUgQXVkaW88L2I+PGRpdiBjbGFzcz0ic21hbGwiPkFkZCBtdXNpYyB0byB5b3VyIHZpZGVvPC9kaXY+PC9kaXY+PGRpdiBpZD0iYXVkaW9Td2l0Y2giIGNsYXNzPSJzd2l0Y2giPjwvZGl2PjwvZGl2PjxpbnB1dCBpZD0iYXVkaW9JbnB1dCIgY2xhc3M9ImF1ZGlvSW5wdXQiIHR5cGU9ImZpbGUiIGFjY2VwdD0iYXVkaW8vKiI+CiAgICAgIDxidXR0b24gaWQ9InJlbmRlckJ1dHRvbiIgY2xhc3M9InJlbmRlckJ1dHRvbiI+4pamJm5ic3A7IFJlbmRlciBNUDQ8c3Bhbj5GaW5hbCB2aWRlbyBleHBvcnQ8L3NwYW4+PC9idXR0b24+CiAgICA8L2Rpdj48L3NlY3Rpb24+CiAgPC9hc2lkZT4KPC9kaXY+Cgo8ZGl2IGlkPSJpbW1pY2hNb2RhbCIgY2xhc3M9Im1vZGFsIj48ZGl2IGNsYXNzPSJtb2RhbENhcmQiPjxkaXYgY2xhc3M9Im1vZGFsVGl0bGUiPk5ldyBJbW1pY2ggSm91cm5leTwvZGl2PjxkaXYgY2xhc3M9ImZvcm1HcmlkIj48aW5wdXQgaWQ9ImltbWljaFVybCIgcGxhY2Vob2xkZXI9IkltbWljaCBVUkwg4oCUIGZvciBleGFtcGxlIGh0dHA6Ly8xOTIuMTY4LjY4LjE1MzoyMjgzIj48aW5wdXQgaWQ9ImltbWljaEtleSIgdHlwZT0icGFzc3dvcmQiIHBsYWNlaG9sZGVyPSJJbW1pY2ggQVBJIGtleSI+PGRpdiBjbGFzcz0idHdvQ29sIj48aW5wdXQgaWQ9InN0YXJ0RGF0ZSIgdHlwZT0iZGF0ZSI+PGlucHV0IGlkPSJlbmREYXRlIiB0eXBlPSJkYXRlIj48L2Rpdj48ZGl2IGNsYXNzPSJzbWFsbCI+UmVxdWlyZWQgcGVybWlzc2lvbnM6IGFzc2V0LnJlYWQsIGFzc2V0LnZpZXcsIGFzc2V0LmRvd25sb2FkLCBtYXAucmVhZCwgdGltZWxpbmUucmVhZDwvZGl2PjxkaXYgY2xhc3M9Im1vZGFsQWN0aW9ucyI+PGJ1dHRvbiBpZD0idGVzdEltbWljaEJ1dHRvbiI+VGVzdCBDb25uZWN0aW9uPC9idXR0b24+PGJ1dHRvbiBpZD0iY3JlYXRlSm91cm5leUJ1dHRvbiIgY2xhc3M9InByaW1hcnkiPkNyZWF0ZSBKb3VybmV5PC9idXR0b24+PGJ1dHRvbiBkYXRhLWNsb3NlPSJpbW1pY2hNb2RhbCI+Q2FuY2VsPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+PC9kaXY+CjxkaXYgaWQ9InVwbG9hZE1vZGFsIiBjbGFzcz0ibW9kYWwiPjxkaXYgY2xhc3M9Im1vZGFsQ2FyZCI+PGRpdiBjbGFzcz0ibW9kYWxUaXRsZSI+VXBsb2FkIEdQUyBNZWRpYTwvZGl2PjxkaXYgY2xhc3M9ImZvcm1HcmlkIj48aW5wdXQgaWQ9InVwbG9hZE5hbWUiIHZhbHVlPSJVcGxvYWRlZCBKb3VybmV5IiBwbGFjZWhvbGRlcj0iSm91cm5leSBuYW1lIj48aW5wdXQgaWQ9InVwbG9hZEZpbGVzIiB0eXBlPSJmaWxlIiBhY2NlcHQ9ImltYWdlLyosdmlkZW8vKiIgbXVsdGlwbGU+PGRpdiBjbGFzcz0ic21hbGwiPk9ubHkgbWVkaWEgY29udGFpbmluZyBHUFMgbWV0YWRhdGEgY2FuIGFwcGVhciBvbiB0aGUgbWFwLjwvZGl2PjxkaXYgY2xhc3M9Im1vZGFsQWN0aW9ucyI+PGJ1dHRvbiBpZD0iY3JlYXRlVXBsb2FkQnV0dG9uIiBjbGFzcz0icHJpbWFyeSI+SW1wb3J0IE1lZGlhPC9idXR0b24+PGJ1dHRvbiBkYXRhLWNsb3NlPSJ1cGxvYWRNb2RhbCI+Q2FuY2VsPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+PC9kaXY+CjxkaXYgaWQ9InNldHRpbmdzTW9kYWwiIGNsYXNzPSJtb2RhbCI+PGRpdiBjbGFzcz0ibW9kYWxDYXJkIj48ZGl2IGNsYXNzPSJtb2RhbFRpdGxlIj5Kb3VybmV5IFNldHRpbmdzPC9kaXY+PGRpdiBjbGFzcz0iZm9ybUdyaWQiPjxsYWJlbCBjbGFzcz0ic21hbGwiPlN0b3AgcmFkaXVzLCBtZXRlcnM8L2xhYmVsPjxpbnB1dCBpZD0ic3RvcFJhZGl1cyIgdHlwZT0ibnVtYmVyIiBtaW49IjEwIiB2YWx1ZT0iMjAwIj48ZGl2IGNsYXNzPSJ0d29Db2wiPjxidXR0b24gaWQ9InJlY2x1c3RlckJ1dHRvbiI+QXV0by1jbHVzdGVyIFN0b3BzPC9idXR0b24+PGJ1dHRvbiBpZD0icmV2ZXJzZVJvdXRlQnV0dG9uIj5SZXZlcnNlIFJvdXRlPC9idXR0b24+PC9kaXY+PGxhYmVsIGNsYXNzPSJzbWFsbCI+RGVmYXVsdCBtYXA8L2xhYmVsPjxzZWxlY3QgaWQ9ImRlZmF1bHRNYXBTZWxlY3QiPjxvcHRpb24gdmFsdWU9ImxpZ2h0Ij5MaWdodCBPU008L29wdGlvbj48b3B0aW9uIHZhbHVlPSJkYXJrIj5EYXJrPC9vcHRpb24+PG9wdGlvbiB2YWx1ZT0ic2F0ZWxsaXRlIj5TYXRlbGxpdGU8L29wdGlvbj48L3NlbGVjdD48ZGl2IGNsYXNzPSJtb2RhbEFjdGlvbnMiPjxidXR0b24gZGF0YS1jbG9zZT0ic2V0dGluZ3NNb2RhbCI+Q2xvc2U8L2J1dHRvbj48L2Rpdj48L2Rpdj48L2Rpdj48L2Rpdj4KPGRpdiBpZD0iYWNjb3VudE1vZGFsIiBjbGFzcz0ibW9kYWwiPjxkaXYgY2xhc3M9Im1vZGFsQ2FyZCI+PGRpdiBjbGFzcz0ibW9kYWxUaXRsZSI+QWNjb3VudCAvIEltbWljaCBDb25uZWN0aW9uPC9kaXY+PGRpdiBjbGFzcz0iZm9ybUdyaWQiPjxpbnB1dCBpZD0iYWNjb3VudFVybCIgcGxhY2Vob2xkZXI9IkltbWljaCBVUkwiPjxpbnB1dCBpZD0iYWNjb3VudEtleSIgdHlwZT0icGFzc3dvcmQiIHBsYWNlaG9sZGVyPSJBUEkga2V5Ij48ZGl2IGNsYXNzPSJtb2RhbEFjdGlvbnMiPjxidXR0b24gaWQ9InNhdmVBY2NvdW50QnV0dG9uIiBjbGFzcz0icHJpbWFyeSI+U2F2ZSBDb25uZWN0aW9uPC9idXR0b24+PGJ1dHRvbiBkYXRhLWNsb3NlPSJhY2NvdW50TW9kYWwiPkNsb3NlPC9idXR0b24+PC9kaXY+PC9kaXY+PC9kaXY+PC9kaXY+Cgo8ZGl2IGlkPSJwcmVzZW50T3ZlcmxheSIgY2xhc3M9InByZXNlbnRPdmVybGF5Ij48ZGl2IGNsYXNzPSJwcmVzZW50SGVhZGVyIj48ZGl2IGNsYXNzPSJsb2dvRmxvd2VyIj48c3BhbiBjbGFzcz0icGV0YWwgcDEiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDIiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDMiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDQiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDUiPjwvc3Bhbj48c3BhbiBjbGFzcz0icGV0YWwgcDYiPjwvc3Bhbj48L2Rpdj48ZGl2PjxkaXYgaWQ9InByZXNlbnRIZWFkZXJUaXRsZSIgY2xhc3M9InByZXNlbnRIZWFkZXJUaXRsZSI+UHJlc2VudCBKb3VybmV5PC9kaXY+PGRpdiBpZD0icHJlc2VudEhlYWRlck1ldGEiIGNsYXNzPSJwcmVzZW50SGVhZGVyTWV0YSI+PC9kaXY+PC9kaXY+PGRpdiBjbGFzcz0icHJlc2VudEhlYWRlclNwYWNlciI+PC9kaXY+PGJ1dHRvbiBpZD0iY2xvc2VQcmVzZW50QnV0dG9uIiBjbGFzcz0idG9wQWN0aW9uIj5DbG9zZTwvYnV0dG9uPjwvZGl2PgogIDxkaXYgY2xhc3M9InByZXNlbnRNYWluIj48ZGl2IGlkPSJwcmVzZW50TWFwIiBjbGFzcz0icHJlc2VudE1hcCI+PC9kaXY+PGRpdiBpZD0icHJlc2VudFN0b3BCYW5uZXIiIGNsYXNzPSJwcmVzZW50U3RvcEJhbm5lciI+PGRpdiBpZD0icHJlc2VudFN0b3BCYW5uZXJUaXRsZSIgY2xhc3M9InByZXNlbnRTdG9wQmFubmVyVGl0bGUiPkpvdXJuZXkgU3RvcDwvZGl2PjxkaXYgaWQ9InByZXNlbnRTdG9wQmFubmVyUmFuZ2UiIGNsYXNzPSJwcmVzZW50U3RvcEJhbm5lclJhbmdlIj48L2Rpdj48L2Rpdj48ZGl2IGlkPSJwcmVzZW50U3RvcFJhaWwiIGNsYXNzPSJwcmVzZW50U3RvcFJhaWwiPjwvZGl2PjxkaXYgaWQ9InByZXNlbnRQaG90b0NhcmQiIGNsYXNzPSJwcmVzZW50UGhvdG9DYXJkIj48L2Rpdj48ZGl2IGNsYXNzPSJwcmVzZW50SHVkIj48YnV0dG9uIGlkPSJwcmV2aW91c1N0b3BCdXR0b24iPuKGkCBTdG9wPC9idXR0b24+PGJ1dHRvbiBpZD0icHJldmlvdXNQaG90b0J1dHRvbiI+4oaQIFBob3RvPC9idXR0b24+PGJ1dHRvbiBpZD0icGxheUpvdXJuZXlCdXR0b24iIGNsYXNzPSJwbGF5Ij7ilrYgUGxheTwvYnV0dG9uPjxidXR0b24gaWQ9Im5leHRQaG90b0J1dHRvbiI+UGhvdG8g4oaSPC9idXR0b24+PGJ1dHRvbiBpZD0ibmV4dFN0b3BCdXR0b24iPlN0b3Ag4oaSPC9idXR0b24+PC9kaXY+PC9kaXY+PGRpdiBpZD0icHJlc2VudEZpbG1zdHJpcCIgY2xhc3M9InByZXNlbnRGaWxtc3RyaXAiPjwvZGl2Pgo8L2Rpdj4KPGRpdiBpZD0idG9hc3QiIGNsYXNzPSJ0b2FzdCI+PC9kaXY+Cgo8c2NyaXB0Pgpjb25zdCBNQVBfU1RZTEVTPXsKIGxpZ2h0Ont2ZXJzaW9uOjgsZ2x5cGhzOidodHRwczovL2RlbW90aWxlcy5tYXBsaWJyZS5vcmcvZm9udC97Zm9udHN0YWNrfS97cmFuZ2V9LnBiZicsc291cmNlczp7YmFzZTp7dHlwZToncmFzdGVyJyx0aWxlczpbJ2h0dHBzOi8vYS5iYXNlbWFwcy5jYXJ0b2Nkbi5jb20vcmFzdGVydGlsZXMvdm95YWdlci97en0ve3h9L3t5fUAyeC5wbmcnLCdodHRwczovL2IuYmFzZW1hcHMuY2FydG9jZG4uY29tL3Jhc3RlcnRpbGVzL3ZveWFnZXIve3p9L3t4fS97eX1AMngucG5nJ10sdGlsZVNpemU6MjU2LGF0dHJpYnV0aW9uOifCqSBPcGVuU3RyZWV0TWFwIGNvbnRyaWJ1dG9ycyDCqSBDQVJUTyd9fSxsYXllcnM6W3tpZDonYmFzZScsdHlwZToncmFzdGVyJyxzb3VyY2U6J2Jhc2UnLG1pbnpvb206MCxtYXh6b29tOjIwfV19LAogZGFyazp7dmVyc2lvbjo4LGdseXBoczonaHR0cHM6Ly9kZW1vdGlsZXMubWFwbGlicmUub3JnL2ZvbnQve2ZvbnRzdGFja30ve3JhbmdlfS5wYmYnLHNvdXJjZXM6e2Jhc2U6e3R5cGU6J3Jhc3RlcicsdGlsZXM6WydodHRwczovL2EuYmFzZW1hcHMuY2FydG9jZG4uY29tL2RhcmtfYWxsL3t6fS97eH0ve3l9QDJ4LnBuZycsJ2h0dHBzOi8vYi5iYXNlbWFwcy5jYXJ0b2Nkbi5jb20vZGFya19hbGwve3p9L3t4fS97eX1AMngucG5nJ10sdGlsZVNpemU6MjU2LGF0dHJpYnV0aW9uOifCqSBPcGVuU3RyZWV0TWFwIGNvbnRyaWJ1dG9ycyDCqSBDQVJUTyd9fSxsYXllcnM6W3tpZDonYmFzZScsdHlwZToncmFzdGVyJyxzb3VyY2U6J2Jhc2UnLG1pbnpvb206MCxtYXh6b29tOjIwfV19LAogc2F0ZWxsaXRlOnt2ZXJzaW9uOjgsZ2x5cGhzOidodHRwczovL2RlbW90aWxlcy5tYXBsaWJyZS5vcmcvZm9udC97Zm9udHN0YWNrfS97cmFuZ2V9LnBiZicsc291cmNlczp7YmFzZTp7dHlwZToncmFzdGVyJyx0aWxlczpbJ2h0dHBzOi8vc2VydmVyLmFyY2dpc29ubGluZS5jb20vQXJjR0lTL3Jlc3Qvc2VydmljZXMvV29ybGRfSW1hZ2VyeS9NYXBTZXJ2ZXIvdGlsZS97en0ve3l9L3t4fSddLHRpbGVTaXplOjI1NixhdHRyaWJ1dGlvbjonVGlsZXMgwqkgRXNyaSd9fSxsYXllcnM6W3tpZDonYmFzZScsdHlwZToncmFzdGVyJyxzb3VyY2U6J2Jhc2UnLG1pbnpvb206MCxtYXh6b29tOjIwfV19Cn07CmxldCBwcm9qZWN0cz1bXSxwcm9qZWN0PW51bGwsbWFwPW51bGwscHJlc2VudE1hcD1udWxsLG1hcFN0eWxlS2V5PWxvY2FsU3RvcmFnZS5nZXRJdGVtKCd0cmlwcHlfbWFwX3N0eWxlJyl8fCdsaWdodCc7CmxldCBtYXJrZXJzPVtdLHBob3RvTWFya2Vycz1bXSxwcmVzZW50TWFya2Vycz1bXSxwcmVzZW50UGhvdG9NYXJrZXJzPVtdLGFjdGl2ZVN0b3BJZD1udWxsLGZpbHRlclN0b3BJZD1udWxsLGFjdGl2ZUFzc2V0SWQ9bnVsbCxhY3RpdmVQb3B1cD1udWxsLHByZXNlbnRTdG9wSW5kZXg9MCxwcmVzZW50UGhvdG9JbmRleD0tMSxwcmVzZW50VGltZXI9bnVsbDsKY29uc3QgZWw9aWQ9PmRvY3VtZW50LmdldEVsZW1lbnRCeUlkKGlkKTsKZnVuY3Rpb24gY2xvbmVTdHlsZShrZXkpe3JldHVybiBKU09OLnBhcnNlKEpTT04uc3RyaW5naWZ5KE1BUF9TVFlMRVNba2V5XXx8TUFQX1NUWUxFUy5saWdodCkpfQpmdW5jdGlvbiB0b2FzdChtZXNzYWdlKXtjb25zdCB0PWVsKCd0b2FzdCcpO3QudGV4dENvbnRlbnQ9bWVzc2FnZTt0LmNsYXNzTGlzdC5hZGQoJ3Nob3cnKTtjbGVhclRpbWVvdXQodC5fdGltZXIpO3QuX3RpbWVyPXNldFRpbWVvdXQoKCk9PnQuY2xhc3NMaXN0LnJlbW92ZSgnc2hvdycpLDQzMDApfQpmdW5jdGlvbiBlc2Modil7cmV0dXJuIFN0cmluZyh2Pz8nJykucmVwbGFjZSgvWyY8PiciXS9nLGM9Pih7JyYnOicmYW1wOycsJzwnOicmbHQ7JywnPic6JyZndDsnLCInIjonJiMzOTsnLCciJzonJnF1b3Q7J31bY10pKX0KZnVuY3Rpb24gaXNvRGF0ZSh2KXtpZighdilyZXR1cm4nJztyZXR1cm4gU3RyaW5nKHYpLnNsaWNlKDAsMTApfQpmdW5jdGlvbiBwcmV0dHlEYXRlKHYpe2lmKCF2KXJldHVybicnO2NvbnN0IGQ9bmV3IERhdGUoU3RyaW5nKHYpLnNsaWNlKDAsMTApKydUMTI6MDA6MDAnKTtyZXR1cm4gTnVtYmVyLmlzTmFOKGQuZ2V0VGltZSgpKT9TdHJpbmcodikuc2xpY2UoMCwxMCk6ZC50b0xvY2FsZURhdGVTdHJpbmcodW5kZWZpbmVkLHttb250aDonc2hvcnQnLGRheTonbnVtZXJpYycseWVhcjonbnVtZXJpYyd9KX0KZnVuY3Rpb24gcmFuZ2VUZXh0KG9iail7Y29uc3QgYT1vYmo/LmltbWljaD8uc3RhcnRfZGF0ZXx8b2JqPy5zdGFydF9kYXRlO2NvbnN0IGI9b2JqPy5pbW1pY2g/LmVuZF9kYXRlfHxvYmo/LmVuZF9kYXRlO2lmKGEmJmIpcmV0dXJuIGAke2lzb0RhdGUoYSl9IHRvICR7aXNvRGF0ZShiKX1gO3JldHVybiBwcmV0dHlEYXRlKG9iaj8uY3JlYXRlZCl9CmZ1bmN0aW9uIGFzc2V0RGF0ZSh2YWx1ZSl7aWYoIXZhbHVlKXJldHVybiBudWxsO2xldCByYXc9U3RyaW5nKHZhbHVlKS50cmltKCk7aWYoL15cZHs0fTpcZHsyfTpcZHsyfS8udGVzdChyYXcpKXJhdz1yYXcucmVwbGFjZSgvXihcZHs0fSk6KFxkezJ9KTooXGR7Mn0pLywnJDEtJDItJDMnKS5yZXBsYWNlKCcgJywnVCcpO2NvbnN0IGQ9bmV3IERhdGUocmF3KTtyZXR1cm4gTnVtYmVyLmlzTmFOKGQuZ2V0VGltZSgpKT9udWxsOmR9CmZ1bmN0aW9uIGZvcm1hdEFzc2V0RGF0ZVRpbWUodmFsdWUpe2NvbnN0IGQ9YXNzZXREYXRlKHZhbHVlKTtpZighZClyZXR1cm4gdmFsdWU/U3RyaW5nKHZhbHVlKTonRGF0ZSB1bmF2YWlsYWJsZSc7Y29uc3QgZGF0ZT1kLnRvTG9jYWxlRGF0ZVN0cmluZygnZW4tVVMnLHttb250aDonMi1kaWdpdCcsZGF5OicyLWRpZ2l0Jyx5ZWFyOidudW1lcmljJ30pLnJlcGxhY2VBbGwoJy8nLCctJyk7Y29uc3QgdGltZT1kLnRvTG9jYWxlVGltZVN0cmluZygnZW4tVVMnLHtob3VyOidudW1lcmljJyxtaW51dGU6JzItZGlnaXQnfSk7cmV0dXJuIGAke2RhdGV9ICR7dGltZX1gfQpmdW5jdGlvbiBzdG9wRGF0ZVJhbmdlKHN0b3Ape2NvbnN0IGRhdGVzPXN0b3BBc3NldHMoc3RvcCkubWFwKGE9PmFzc2V0RGF0ZShhLnRpbWUpKS5maWx0ZXIoQm9vbGVhbikuc29ydCgoYSxiKT0+YS1iKTtpZighZGF0ZXMubGVuZ3RoKXJldHVybidEYXRlL3RpbWUgdW5hdmFpbGFibGUnO2NvbnN0IGZpcnN0PWRhdGVzWzBdLGxhc3Q9ZGF0ZXNbZGF0ZXMubGVuZ3RoLTFdO2NvbnN0IGZkPWZpcnN0LnRvTG9jYWxlRGF0ZVN0cmluZygnZW4tVVMnLHttb250aDonMi1kaWdpdCcsZGF5OicyLWRpZ2l0Jyx5ZWFyOidudW1lcmljJ30pLnJlcGxhY2VBbGwoJy8nLCctJyk7Y29uc3QgZnQ9Zmlyc3QudG9Mb2NhbGVUaW1lU3RyaW5nKCdlbi1VUycse2hvdXI6J251bWVyaWMnLG1pbnV0ZTonMi1kaWdpdCd9KTtjb25zdCBsZD1sYXN0LnRvTG9jYWxlRGF0ZVN0cmluZygnZW4tVVMnLHttb250aDonMi1kaWdpdCcsZGF5OicyLWRpZ2l0Jyx5ZWFyOidudW1lcmljJ30pLnJlcGxhY2VBbGwoJy8nLCctJyk7Y29uc3QgbHQ9bGFzdC50b0xvY2FsZVRpbWVTdHJpbmcoJ2VuLVVTJyx7aG91cjonbnVtZXJpYycsbWludXRlOicyLWRpZ2l0J30pO3JldHVybiBmZD09PWxkP2Ake2ZkfSAke2Z0fSDigJMgJHtsdH1gOmAke2ZkfSAke2Z0fSDigJMgJHtsZH0gJHtsdH1gfQpmdW5jdGlvbiB2YWxpZFBvaW50KGl0ZW0pe3JldHVybiBOdW1iZXIuaXNGaW5pdGUoTnVtYmVyKGl0ZW0/LmxvbikpJiZOdW1iZXIuaXNGaW5pdGUoTnVtYmVyKGl0ZW0/LmxhdCkpJiZNYXRoLmFicyhOdW1iZXIoaXRlbS5sYXQpKTw9OTAmJk1hdGguYWJzKE51bWJlcihpdGVtLmxvbikpPD0xODB9CmZ1bmN0aW9uIHN0b3BCb3VuZHMoc3RvcCl7Y29uc3QgYXNzZXRzPXN0b3BBc3NldHMoc3RvcCkuZmlsdGVyKHZhbGlkUG9pbnQpO2NvbnN0IGJvdW5kcz1uZXcgbWFwbGlicmVnbC5MbmdMYXRCb3VuZHMoKTthc3NldHMuZm9yRWFjaChhPT5ib3VuZHMuZXh0ZW5kKFtOdW1iZXIoYS5sb24pLE51bWJlcihhLmxhdCldKSk7aWYoIWFzc2V0cy5sZW5ndGgmJnZhbGlkUG9pbnQoc3RvcCkpYm91bmRzLmV4dGVuZChbTnVtYmVyKHN0b3AubG9uKSxOdW1iZXIoc3RvcC5sYXQpXSk7cmV0dXJue2JvdW5kcyxhc3NldHN9fQpmdW5jdGlvbiBjb25uKCl7cmV0dXJue2Jhc2VfdXJsOmxvY2FsU3RvcmFnZS5nZXRJdGVtKCd0cmlwcHlfaW1taWNoX3VybCcpfHwnJyxhcGlfa2V5OmxvY2FsU3RvcmFnZS5nZXRJdGVtKCd0cmlwcHlfaW1taWNoX2tleScpfHwnJ319CmZ1bmN0aW9uIHNhdmVDb25uKHVybCxrZXkpe2xvY2FsU3RvcmFnZS5zZXRJdGVtKCd0cmlwcHlfaW1taWNoX3VybCcsdXJsKTtsb2NhbFN0b3JhZ2Uuc2V0SXRlbSgndHJpcHB5X2ltbWljaF9rZXknLGtleSl9CmFzeW5jIGZ1bmN0aW9uIGFwaShwYXRoLG9wdGlvbnM9e30pe2NvbnN0IHJlc3BvbnNlPWF3YWl0IGZldGNoKHBhdGgsb3B0aW9ucyk7Y29uc3QgcmF3PWF3YWl0IHJlc3BvbnNlLnRleHQoKTtsZXQgZGF0YTt0cnl7ZGF0YT1KU09OLnBhcnNlKHJhdyl9Y2F0Y2h7ZGF0YT17ZGV0YWlsOnJhd319aWYoIXJlc3BvbnNlLm9rKXRocm93IG5ldyBFcnJvcihkYXRhLmRldGFpbHx8cmF3fHxgSFRUUCAke3Jlc3BvbnNlLnN0YXR1c31gKTtyZXR1cm4gZGF0YX0KZnVuY3Rpb24gc3RvcE5hbWUoc3RvcCxpbmRleCl7Y29uc3QgcmF3PShzdG9wPy5uYW1lfHwnJykudHJpbSgpO3JldHVybiByYXcmJiEvXlN0b3BccytcZCskL2kudGVzdChyYXcpP3JhdzpgU3RvcCAke2luZGV4KzF9YH0KZnVuY3Rpb24gc3RvcEFzc2V0cyhzdG9wKXtpZighcHJvamVjdHx8IXN0b3ApcmV0dXJuW107Y29uc3QgaWRzPW5ldyBTZXQoc3RvcC5hc3NldF9pZHN8fFtdKTtyZXR1cm4ocHJvamVjdC5hc3NldHN8fFtdKS5maWx0ZXIoYT0+aWRzLmhhcyhhLmFzc2V0X2lkKSl9CmZ1bmN0aW9uIGZpcnN0U3RvcEFzc2V0KHN0b3Ape3JldHVybiBzdG9wQXNzZXRzKHN0b3ApWzBdfHxudWxsfQpmdW5jdGlvbiBwcm9qZWN0U3VtbWFyeUNvdW50KHApe3JldHVybiBOdW1iZXIocD8uY291bnQ/P3A/LmFzc2V0cz8ubGVuZ3RoPz8wKX0KZnVuY3Rpb24gc2V0TW9kYWwoaWQsb249dHJ1ZSl7ZWwoaWQpLmNsYXNzTGlzdC50b2dnbGUoJ3Nob3cnLG9uKX0KZnVuY3Rpb24gaW5pdEZvcm1zKCl7Y29uc3QgYz1jb25uKCk7ZWwoJ2ltbWljaFVybCcpLnZhbHVlPWMuYmFzZV91cmw7ZWwoJ2ltbWljaEtleScpLnZhbHVlPWMuYXBpX2tleTtlbCgnYWNjb3VudFVybCcpLnZhbHVlPWMuYmFzZV91cmw7ZWwoJ2FjY291bnRLZXknKS52YWx1ZT1jLmFwaV9rZXk7Y29uc3QgZD1uZXcgRGF0ZSgpLHM9bmV3IERhdGUoKTtzLnNldERhdGUocy5nZXREYXRlKCktNyk7ZWwoJ3N0YXJ0RGF0ZScpLnZhbHVlPXMudG9JU09TdHJpbmcoKS5zbGljZSgwLDEwKTtlbCgnZW5kRGF0ZScpLnZhbHVlPWQudG9JU09TdHJpbmcoKS5zbGljZSgwLDEwKTtlbCgnZGVmYXVsdE1hcFNlbGVjdCcpLnZhbHVlPW1hcFN0eWxlS2V5fQphc3luYyBmdW5jdGlvbiBsb2FkUHJvamVjdHMoKXtwcm9qZWN0cz1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdHMnKTtyZW5kZXJQcm9qZWN0cygpO2lmKCFwcm9qZWN0JiZwcm9qZWN0cy5sZW5ndGgpYXdhaXQgb3BlblByb2plY3QocHJvamVjdHNbMF0uaWQpO2lmKCFwcm9qZWN0cy5sZW5ndGgpcmVuZGVyQWxsKCl9CmZ1bmN0aW9uIHJlbmRlclByb2plY3RzKCl7Y29uc3QgcT1lbCgncHJvamVjdFNlYXJjaCcpLnZhbHVlLnRyaW0oKS50b0xvd2VyQ2FzZSgpO2NvbnN0IGxpc3Q9cHJvamVjdHMuZmlsdGVyKHA9PiFxfHwocC5uYW1lfHwnJykudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyhxKSk7ZWwoJ3Byb2plY3RMaXN0JykuaW5uZXJIVE1MPWxpc3QubWFwKHA9PmA8YXJ0aWNsZSBjbGFzcz0icHJvamVjdENhcmQgJHtwcm9qZWN0Py5pZD09PXAuaWQ/J2FjdGl2ZSc6Jyd9IiBkYXRhLWlkPSIke2VzYyhwLmlkKX0iPjxidXR0b24gY2xhc3M9InByb2plY3RNZW51IiBkYXRhLW1lbnU9IiR7ZXNjKHAuaWQpfSI+4ouuPC9idXR0b24+PGRpdiBjbGFzcz0icHJvamVjdENhcmRUaXRsZSI+JHtlc2MocC5uYW1lfHwnVW50aXRsZWQgSm91cm5leScpfTwvZGl2PjxkaXYgY2xhc3M9InByb2plY3REYXRlIj4ke2VzYyhyYW5nZVRleHQocCl8fCcnKX08L2Rpdj48ZGl2IGNsYXNzPSJwcm9qZWN0U3RhdHMiPjxzcGFuIGNsYXNzPSJkb3QiPuKXjzwvc3Bhbj4gJHtwcm9qZWN0U3VtbWFyeUNvdW50KHApfSBtZWRpYSZuYnNwOyDigKIgJm5ic3A7JHtOdW1iZXIocC5zdG9wc3x8MCl9IHN0b3BzPC9kaXY+PGJ1dHRvbiBjbGFzcz0icHJvamVjdERlbGV0ZSIgZGF0YS1kZWxldGU9IiR7ZXNjKHAuaWQpfSI+RGVsZXRlPC9idXR0b24+PC9hcnRpY2xlPmApLmpvaW4oJycpfHwnPGRpdiBjbGFzcz0ic21hbGwiPk5vIGpvdXJuZXlzIHlldC48L2Rpdj4nO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJy5wcm9qZWN0Q2FyZCcpLmZvckVhY2goY2FyZD0+Y2FyZC5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsZT0+e2lmKGUudGFyZ2V0LmNsb3Nlc3QoJ2J1dHRvbicpKXJldHVybjtvcGVuUHJvamVjdChjYXJkLmRhdGFzZXQuaWQpfSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLW1lbnVdJykuZm9yRWFjaChiPT5iLmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJyxlPT57ZS5zdG9wUHJvcGFnYXRpb24oKTtiLmNsb3Nlc3QoJy5wcm9qZWN0Q2FyZCcpLmNsYXNzTGlzdC50b2dnbGUoJ21lbnVPcGVuJyl9KSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtZGVsZXRlXScpLmZvckVhY2goYj0+Yi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsZT0+e2Uuc3RvcFByb3BhZ2F0aW9uKCk7ZGVsZXRlUHJvamVjdChiLmRhdGFzZXQuZGVsZXRlKX0pKX0KYXN5bmMgZnVuY3Rpb24gb3BlblByb2plY3QoaWQpe3Byb2plY3Q9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytlbmNvZGVVUklDb21wb25lbnQoaWQpKTthY3RpdmVTdG9wSWQ9cHJvamVjdC5zdG9wcz8uWzBdPy5zdG9wX2lkfHxudWxsO2ZpbHRlclN0b3BJZD1hY3RpdmVTdG9wSWQ7YWN0aXZlQXNzZXRJZD1udWxsO3JlbmRlckFsbCgpO3RvYXN0KGBMb2FkZWQgJHtwcm9qZWN0Lm5hbWV8fCdqb3VybmV5J31gKX0KYXN5bmMgZnVuY3Rpb24gZGVsZXRlUHJvamVjdChpZCl7aWYoIWNvbmZpcm0oJ0RlbGV0ZSB0aGlzIGpvdXJuZXkgYW5kIGl0cyBzYXZlZCBleHBvcnQ/JykpcmV0dXJuO2F3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KGlkKSx7bWV0aG9kOidERUxFVEUnfSk7aWYocHJvamVjdD8uaWQ9PT1pZClwcm9qZWN0PW51bGw7cHJvamVjdHM9cHJvamVjdHMuZmlsdGVyKHA9PnAuaWQhPT1pZCk7YXdhaXQgbG9hZFByb2plY3RzKCl9CmZ1bmN0aW9uIHJlbmRlckFsbCgpe3JlbmRlclByb2plY3RzKCk7cmVuZGVySGVhZGVyKCk7cmVuZGVyU3RvcHMoKTtyZW5kZXJHYWxsZXJ5KCk7cmVuZGVyTWFwKHRydWUpfQpmdW5jdGlvbiByZW5kZXJIZWFkZXIoKXtpZighcHJvamVjdCl7ZWwoJ2pvdXJuZXlUaXRsZScpLnRleHRDb250ZW50PSdObyBqb3VybmV5IHNlbGVjdGVkJztlbCgnam91cm5leU1ldGEnKS50ZXh0Q29udGVudD0nTG9hZCBvciBjcmVhdGUgYSBqb3VybmV5JztyZXR1cm59ZWwoJ2pvdXJuZXlUaXRsZScpLnRleHRDb250ZW50PXByb2plY3QubmFtZXx8J1VudGl0bGVkIEpvdXJuZXknO2NvbnN0IG1lZGlhPShwcm9qZWN0LmFzc2V0c3x8W10pLmxlbmd0aCxzdG9wcz0ocHJvamVjdC5zdG9wc3x8W10pLmxlbmd0aDtlbCgnam91cm5leU1ldGEnKS5pbm5lckhUTUw9YDxzcGFuPuKXtyAke2VzYyhyYW5nZVRleHQocHJvamVjdCl8fHByZXR0eURhdGUocHJvamVjdC5jcmVhdGVkKSl9PC9zcGFuPjxzcGFuIGNsYXNzPSJsaXZlRG90Ij48L3NwYW4+PHNwYW4+JHttZWRpYX0gbWVkaWE8L3NwYW4+PHNwYW4+4oCiICR7c3RvcHN9IHN0b3BzPC9zcGFuPmB9CmZ1bmN0aW9uIGVuc3VyZU1hcCgpe2lmKG1hcClyZXR1cm47bWFwPW5ldyBtYXBsaWJyZWdsLk1hcCh7Y29udGFpbmVyOidtYXAnLHN0eWxlOmNsb25lU3R5bGUobWFwU3R5bGVLZXkpLGNlbnRlcjpbLTk4LDM5XSx6b29tOjMscGl0Y2g6MCxiZWFyaW5nOjAsYXR0cmlidXRpb25Db250cm9sOnRydWV9KTttYXAuYWRkQ29udHJvbChuZXcgbWFwbGlicmVnbC5OYXZpZ2F0aW9uQ29udHJvbCh7c2hvd0NvbXBhc3M6ZmFsc2V9KSwnYm90dG9tLXJpZ2h0Jyk7bWFwLm9uKCdsb2FkJywoKT0+cmVuZGVyTWFwKHRydWUpKTttYXAub24oJ3pvb21lbmQnLHJlbmRlclNlbGVjdGVkUGhvdG9CdWJibGVzKTttYXAub24oJ21vdmVlbmQnLHJlbmRlclNlbGVjdGVkUGhvdG9CdWJibGVzKX0KZnVuY3Rpb24gY2xlYXJCdWJibGVNYXJrZXJzKGxpc3Qpe2xpc3QuZm9yRWFjaChtPT57dHJ5e20ucmVtb3ZlKCl9Y2F0Y2h7fX0pO2xpc3QubGVuZ3RoPTB9CmZ1bmN0aW9uIGNsZWFyTWFwTWFya2Vycygpe2NsZWFyQnViYmxlTWFya2VycyhtYXJrZXJzKTtjbGVhckJ1YmJsZU1hcmtlcnMocGhvdG9NYXJrZXJzKTtpZihhY3RpdmVQb3B1cCl7dHJ5e2FjdGl2ZVBvcHVwLnJlbW92ZSgpfWNhdGNoe31hY3RpdmVQb3B1cD1udWxsfX0KZnVuY3Rpb24gcmVtb3ZlTGF5ZXJBbmRTb3VyY2UodGFyZ2V0TWFwLGlkcyxzb3VyY2Upe2lkcy5mb3JFYWNoKGlkPT57aWYodGFyZ2V0TWFwLmdldExheWVyKGlkKSl0YXJnZXRNYXAucmVtb3ZlTGF5ZXIoaWQpfSk7aWYodGFyZ2V0TWFwLmdldFNvdXJjZShzb3VyY2UpKXRhcmdldE1hcC5yZW1vdmVTb3VyY2Uoc291cmNlKX0KZnVuY3Rpb24gYWRkUm91dGVMYXllcnModGFyZ2V0TWFwLGlkUHJlZml4LGNvb3Jkcyl7Y29uc3Qgc291cmNlPWlkUHJlZml4Kyctcm91dGUnLGdsb3c9aWRQcmVmaXgrJy1yb3V0ZS1nbG93JyxsaW5lPWlkUHJlZml4Kyctcm91dGUtbGluZSc7cmVtb3ZlTGF5ZXJBbmRTb3VyY2UodGFyZ2V0TWFwLFtsaW5lLGdsb3ddLHNvdXJjZSk7aWYoY29vcmRzLmxlbmd0aDwyKXJldHVybjt0YXJnZXRNYXAuYWRkU291cmNlKHNvdXJjZSx7dHlwZTonZ2VvanNvbicsZGF0YTp7dHlwZTonRmVhdHVyZScsZ2VvbWV0cnk6e3R5cGU6J0xpbmVTdHJpbmcnLGNvb3JkaW5hdGVzOmNvb3Jkc319fSk7dGFyZ2V0TWFwLmFkZExheWVyKHtpZDpnbG93LHR5cGU6J2xpbmUnLHNvdXJjZSxwYWludDp7J2xpbmUtY29sb3InOicjMDBkOGZmJywnbGluZS13aWR0aCc6MTEsJ2xpbmUtb3BhY2l0eSc6LjIwLCdsaW5lLWJsdXInOjV9fSk7dGFyZ2V0TWFwLmFkZExheWVyKHtpZDpsaW5lLHR5cGU6J2xpbmUnLHNvdXJjZSxwYWludDp7J2xpbmUtY29sb3InOicjMDBjZmVlJywnbGluZS13aWR0aCc6NCwnbGluZS1vcGFjaXR5JzouOTV9fSl9CmZ1bmN0aW9uIHN0b3BGZWF0dXJlcygpe3JldHVybihwcm9qZWN0Py5zdG9wc3x8W10pLmZpbHRlcih2YWxpZFBvaW50KS5tYXAoKHMsaSk9Pih7dHlwZTonRmVhdHVyZScsZ2VvbWV0cnk6e3R5cGU6J1BvaW50Jyxjb29yZGluYXRlczpbTnVtYmVyKHMubG9uKSxOdW1iZXIocy5sYXQpXX0scHJvcGVydGllczp7c3RvcF9pZDpzLnN0b3BfaWQsaW5kZXg6aSsxLG5hbWU6c3RvcE5hbWUocyxpKX19KSl9CmZ1bmN0aW9uIHBob3RvRmVhdHVyZXMoKXtyZXR1cm4ocHJvamVjdD8uYXNzZXRzfHxbXSkuZmlsdGVyKHZhbGlkUG9pbnQpLm1hcChhPT4oe3R5cGU6J0ZlYXR1cmUnLGdlb21ldHJ5Ont0eXBlOidQb2ludCcsY29vcmRpbmF0ZXM6W051bWJlcihhLmxvbiksTnVtYmVyKGEubGF0KV19LHByb3BlcnRpZXM6e2Fzc2V0X2lkOmEuYXNzZXRfaWQsbmFtZTphLm5hbWV8fCdQaG90bycsdGltZTphLnRpbWV8fCcnLHN0b3BfaWQ6KHByb2plY3Q/LnN0b3BzfHxbXSkuZmluZChzPT4ocy5hc3NldF9pZHN8fFtdKS5pbmNsdWRlcyhhLmFzc2V0X2lkKSk/LnN0b3BfaWR8fCcnfX0pKX0KZnVuY3Rpb24gYWRkQ2x1c3RlckxheWVycyh0YXJnZXRNYXAscHJlZml4KXtjb25zdCBzdG9wU291cmNlPXByZWZpeCsnLXN0b3BzJyxwaG90b1NvdXJjZT1wcmVmaXgrJy1waG90b3MnO3JlbW92ZUxheWVyQW5kU291cmNlKHRhcmdldE1hcCxbcHJlZml4Kyctc3RvcC1jbHVzdGVyLWNvdW50JyxwcmVmaXgrJy1zdG9wLWNsdXN0ZXJzJyxwcmVmaXgrJy1zdG9wLW51bWJlcicscHJlZml4Kyctc3RvcC1wb2ludHMnXSxzdG9wU291cmNlKTtyZW1vdmVMYXllckFuZFNvdXJjZSh0YXJnZXRNYXAsW3ByZWZpeCsnLXBob3RvLWNsdXN0ZXItY291bnQnLHByZWZpeCsnLXBob3RvLWNsdXN0ZXJzJyxwcmVmaXgrJy1waG90by1wb2ludHMnXSxwaG90b1NvdXJjZSk7dGFyZ2V0TWFwLmFkZFNvdXJjZShzdG9wU291cmNlLHt0eXBlOidnZW9qc29uJyxjbHVzdGVyOnRydWUsY2x1c3RlclJhZGl1czo0OCxjbHVzdGVyTWF4Wm9vbTo5LGRhdGE6e3R5cGU6J0ZlYXR1cmVDb2xsZWN0aW9uJyxmZWF0dXJlczpzdG9wRmVhdHVyZXMoKX19KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOnByZWZpeCsnLXN0b3AtY2x1c3RlcnMnLHR5cGU6J2NpcmNsZScsc291cmNlOnN0b3BTb3VyY2UsZmlsdGVyOlsnaGFzJywncG9pbnRfY291bnQnXSxwYWludDp7J2NpcmNsZS1yYWRpdXMnOlsnc3RlcCcsWydnZXQnLCdwb2ludF9jb3VudCddLDIwLDEwLDI1LDQwLDMxXSwnY2lyY2xlLWNvbG9yJzonIzA3MTMxZicsJ2NpcmNsZS1zdHJva2UtY29sb3InOicjMDBkOGZmJywnY2lyY2xlLXN0cm9rZS13aWR0aCc6MywnY2lyY2xlLW9wYWNpdHknOi45NH19KTt0YXJnZXRNYXAuYWRkTGF5ZXIoe2lkOnByZWZpeCsnLXN0b3AtY2x1c3Rlci1jb3VudCcsdHlwZTonc3ltYm9sJyxzb3VyY2U6c3RvcFNvdXJjZSxmaWx0ZXI6WydoYXMnLCdwb2ludF9jb3VudCddLGxheW91dDp7J3RleHQtZmllbGQnOlsnZ2V0JywncG9pbnRfY291bnRfYWJicmV2aWF0ZWQnXSwndGV4dC1zaXplJzoxMn0scGFpbnQ6eyd0ZXh0LWNvbG9yJzonI2ZmZmZmZid9fSk7dGFyZ2V0TWFwLmFkZExheWVyKHtpZDpwcmVmaXgrJy1zdG9wLXBvaW50cycsdHlwZTonY2lyY2xlJyxzb3VyY2U6c3RvcFNvdXJjZSxmaWx0ZXI6WychJyxbJ2hhcycsJ3BvaW50X2NvdW50J11dLHBhaW50OnsnY2lyY2xlLXJhZGl1cyc6MTcsJ2NpcmNsZS1jb2xvcic6JyMwNzEzMWYnLCdjaXJjbGUtc3Ryb2tlLWNvbG9yJzonIzAwZDhmZicsJ2NpcmNsZS1zdHJva2Utd2lkdGgnOjMsJ2NpcmNsZS1vcGFjaXR5JzouOTV9fSk7dGFyZ2V0TWFwLmFkZExheWVyKHtpZDpwcmVmaXgrJy1zdG9wLW51bWJlcicsdHlwZTonc3ltYm9sJyxzb3VyY2U6c3RvcFNvdXJjZSxmaWx0ZXI6WychJyxbJ2hhcycsJ3BvaW50X2NvdW50J11dLGxheW91dDp7J3RleHQtZmllbGQnOlsndG8tc3RyaW5nJyxbJ2dldCcsJ2luZGV4J11dLCd0ZXh0LXNpemUnOjExfSxwYWludDp7J3RleHQtY29sb3InOicjZmZmZmZmJ319KTt0YXJnZXRNYXAuYWRkU291cmNlKHBob3RvU291cmNlLHt0eXBlOidnZW9qc29uJyxjbHVzdGVyOnRydWUsY2x1c3RlclJhZGl1czo0MixjbHVzdGVyTWF4Wm9vbToxMyxkYXRhOnt0eXBlOidGZWF0dXJlQ29sbGVjdGlvbicsZmVhdHVyZXM6cGhvdG9GZWF0dXJlcygpfX0pO3RhcmdldE1hcC5hZGRMYXllcih7aWQ6cHJlZml4KyctcGhvdG8tY2x1c3RlcnMnLHR5cGU6J2NpcmNsZScsc291cmNlOnBob3RvU291cmNlLGZpbHRlcjpbJ2hhcycsJ3BvaW50X2NvdW50J10sbWluem9vbTo4LHBhaW50OnsnY2lyY2xlLXJhZGl1cyc6WydzdGVwJyxbJ2dldCcsJ3BvaW50X2NvdW50J10sMTUsOCwxOSwyNSwyNF0sJ2NpcmNsZS1jb2xvcic6JyMwYTIzMzInLCdjaXJjbGUtc3Ryb2tlLWNvbG9yJzonIzdkZWFmZicsJ2NpcmNsZS1zdHJva2Utd2lkdGgnOjIsJ2NpcmNsZS1vcGFjaXR5JzouODh9fSk7dGFyZ2V0TWFwLmFkZExheWVyKHtpZDpwcmVmaXgrJy1waG90by1jbHVzdGVyLWNvdW50Jyx0eXBlOidzeW1ib2wnLHNvdXJjZTpwaG90b1NvdXJjZSxmaWx0ZXI6WydoYXMnLCdwb2ludF9jb3VudCddLG1pbnpvb206OCxsYXlvdXQ6eyd0ZXh0LWZpZWxkJzpbJ2dldCcsJ3BvaW50X2NvdW50X2FiYnJldmlhdGVkJ10sJ3RleHQtc2l6ZSc6MTB9LHBhaW50OnsndGV4dC1jb2xvcic6JyNmZmZmZmYnfX0pO3RhcmdldE1hcC5hZGRMYXllcih7aWQ6cHJlZml4KyctcGhvdG8tcG9pbnRzJyx0eXBlOidjaXJjbGUnLHNvdXJjZTpwaG90b1NvdXJjZSxmaWx0ZXI6WychJyxbJ2hhcycsJ3BvaW50X2NvdW50J11dLG1pbnpvb206MTEscGFpbnQ6eydjaXJjbGUtcmFkaXVzJzpbJ2ludGVycG9sYXRlJyxbJ2xpbmVhciddLFsnem9vbSddLDExLDQsMTUsN10sJ2NpcmNsZS1jb2xvcic6JyMwMGQ4ZmYnLCdjaXJjbGUtc3Ryb2tlLWNvbG9yJzonI2ZmZmZmZicsJ2NpcmNsZS1zdHJva2Utd2lkdGgnOjEuNSwnY2lyY2xlLW9wYWNpdHknOlsnaW50ZXJwb2xhdGUnLFsnbGluZWFyJ10sWyd6b29tJ10sMTEsLjY1LDE0LC45LDE1LDBdfX0pfQpmdW5jdGlvbiBleHBhbmRDbHVzdGVyKHRhcmdldE1hcCxzb3VyY2VJZCxmZWF0dXJlKXtjb25zdCBzb3VyY2U9dGFyZ2V0TWFwLmdldFNvdXJjZShzb3VyY2VJZCk7aWYoIXNvdXJjZSlyZXR1cm47Y29uc3QgY2x1c3RlcklkPWZlYXR1cmUucHJvcGVydGllcy5jbHVzdGVyX2lkO2NvbnN0IHJlc3VsdD1zb3VyY2UuZ2V0Q2x1c3RlckV4cGFuc2lvblpvb20oY2x1c3RlcklkKTtpZihyZXN1bHQmJnR5cGVvZiByZXN1bHQudGhlbj09PSdmdW5jdGlvbicpcmVzdWx0LnRoZW4oem9vbT0+dGFyZ2V0TWFwLmVhc2VUbyh7Y2VudGVyOmZlYXR1cmUuZ2VvbWV0cnkuY29vcmRpbmF0ZXMsem9vbSxkdXJhdGlvbjo3MDB9KSk7ZWxzZSBzb3VyY2UuZ2V0Q2x1c3RlckV4cGFuc2lvblpvb20oY2x1c3RlcklkLChlcnIsem9vbSk9PntpZighZXJyKXRhcmdldE1hcC5lYXNlVG8oe2NlbnRlcjpmZWF0dXJlLmdlb21ldHJ5LmNvb3JkaW5hdGVzLHpvb20sZHVyYXRpb246NzAwfSl9KX0KZnVuY3Rpb24gYmluZE1hcEludGVyYWN0aW9ucyh0YXJnZXRNYXAscHJlZml4LGlzUHJlc2VudD1mYWxzZSl7Y29uc3Qga2V5PSdfX3RyaXBweV8nK3ByZWZpeDtpZih0YXJnZXRNYXBba2V5XSlyZXR1cm47dGFyZ2V0TWFwW2tleV09dHJ1ZTt0YXJnZXRNYXAub24oJ2NsaWNrJyxwcmVmaXgrJy1zdG9wLWNsdXN0ZXJzJyxlPT5leHBhbmRDbHVzdGVyKHRhcmdldE1hcCxwcmVmaXgrJy1zdG9wcycsZS5mZWF0dXJlc1swXSkpO3RhcmdldE1hcC5vbignY2xpY2snLHByZWZpeCsnLXBob3RvLWNsdXN0ZXJzJyxlPT5leHBhbmRDbHVzdGVyKHRhcmdldE1hcCxwcmVmaXgrJy1waG90b3MnLGUuZmVhdHVyZXNbMF0pKTt0YXJnZXRNYXAub24oJ2NsaWNrJyxwcmVmaXgrJy1zdG9wLXBvaW50cycsZT0+e2NvbnN0IGlkPWUuZmVhdHVyZXM/LlswXT8ucHJvcGVydGllcz8uc3RvcF9pZDtpZihpZCl7Y29uc3QgaT0ocHJvamVjdD8uc3RvcHN8fFtdKS5maW5kSW5kZXgocz0+cy5zdG9wX2lkPT09aWQpO2lzUHJlc2VudD9nb1ByZXNlbnRTdG9wKGkpOnNlbGVjdFN0b3AoaWQse2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KX19KTt0YXJnZXRNYXAub24oJ2NsaWNrJyxwcmVmaXgrJy1zdG9wLW51bWJlcicsZT0+e2NvbnN0IGlkPWUuZmVhdHVyZXM/LlswXT8ucHJvcGVydGllcz8uc3RvcF9pZDtpZihpZCl7Y29uc3QgaT0ocHJvamVjdD8uc3RvcHN8fFtdKS5maW5kSW5kZXgocz0+cy5zdG9wX2lkPT09aWQpO2lzUHJlc2VudD9nb1ByZXNlbnRTdG9wKGkpOnNlbGVjdFN0b3AoaWQse2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KX19KTt0YXJnZXRNYXAub24oJ2NsaWNrJyxwcmVmaXgrJy1waG90by1wb2ludHMnLGU9Pntjb25zdCBpZD1lLmZlYXR1cmVzPy5bMF0/LnByb3BlcnRpZXM/LmFzc2V0X2lkO2lmKGlkKXtpZihpc1ByZXNlbnQpe2NvbnN0IGk9cHJlc2VudEFzc2V0cygpLmZpbmRJbmRleChhPT5hLmFzc2V0X2lkPT09aWQpO2lmKGk+PTApZ29QcmVzZW50UGhvdG8oaSl9ZWxzZSBmb2N1c0Fzc2V0KGlkKX19KTtbcHJlZml4Kyctc3RvcC1jbHVzdGVycycscHJlZml4Kyctc3RvcC1wb2ludHMnLHByZWZpeCsnLXN0b3AtbnVtYmVyJyxwcmVmaXgrJy1waG90by1jbHVzdGVycycscHJlZml4KyctcGhvdG8tcG9pbnRzJ10uZm9yRWFjaChsYXllcj0+e3RhcmdldE1hcC5vbignbW91c2VlbnRlcicsbGF5ZXIsKCk9PnRhcmdldE1hcC5nZXRDYW52YXMoKS5zdHlsZS5jdXJzb3I9J3BvaW50ZXInKTt0YXJnZXRNYXAub24oJ21vdXNlbGVhdmUnLGxheWVyLCgpPT50YXJnZXRNYXAuZ2V0Q2FudmFzKCkuc3R5bGUuY3Vyc29yPScnKX0pfQpmdW5jdGlvbiBhc3NldEJ1YmJsZUVsZW1lbnQoYXNzZXQsYWN0aXZlPWZhbHNlKXtjb25zdCBub2RlPWRvY3VtZW50LmNyZWF0ZUVsZW1lbnQoJ2RpdicpO25vZGUuY2xhc3NOYW1lPSdhc3NldEJ1YmJsZScrKGFjdGl2ZT8nIGFjdGl2ZSc6JycpO25vZGUudGl0bGU9Zm9ybWF0QXNzZXREYXRlVGltZShhc3NldC50aW1lKTtub2RlLmlubmVySFRNTD1hc3NldC50aHVtYj9gPGltZyBzcmM9IiR7ZXNjKGFzc2V0LnRodW1iKX0iIGFsdD0iIj5gOic8ZGl2IGNsYXNzPSJhc3NldERvdCI+4oCiPC9kaXY+JztyZXR1cm4gbm9kZX0KZnVuY3Rpb24gcmVuZGVyU2VsZWN0ZWRQaG90b0J1YmJsZXMoKXtjbGVhckJ1YmJsZU1hcmtlcnMocGhvdG9NYXJrZXJzKTtpZighbWFwfHxtYXAuZ2V0Wm9vbSgpPDEzLjV8fCFhY3RpdmVTdG9wSWQpcmV0dXJuO2NvbnN0IHN0b3A9cHJvamVjdD8uc3RvcHM/LmZpbmQocz0+cy5zdG9wX2lkPT09YWN0aXZlU3RvcElkKTtzdG9wQXNzZXRzKHN0b3ApLmZpbHRlcih2YWxpZFBvaW50KS5zbGljZSgwLDEyMCkuZm9yRWFjaChhc3NldD0+e2NvbnN0IG5vZGU9YXNzZXRCdWJibGVFbGVtZW50KGFzc2V0LGFzc2V0LmFzc2V0X2lkPT09YWN0aXZlQXNzZXRJZCk7bm9kZS5vbmNsaWNrPSgpPT5mb2N1c0Fzc2V0KGFzc2V0LmFzc2V0X2lkKTtwaG90b01hcmtlcnMucHVzaChuZXcgbWFwbGlicmVnbC5NYXJrZXIoe2VsZW1lbnQ6bm9kZSxhbmNob3I6J2NlbnRlcid9KS5zZXRMbmdMYXQoW051bWJlcihhc3NldC5sb24pLE51bWJlcihhc3NldC5sYXQpXSkuYWRkVG8obWFwKSl9KX0KZnVuY3Rpb24gcmVuZGVyTWFwKGZpdD1mYWxzZSl7ZW5zdXJlTWFwKCk7aWYoIW1hcC5pc1N0eWxlTG9hZGVkKCkpe21hcC5vbmNlKCdsb2FkJywoKT0+cmVuZGVyTWFwKGZpdCkpO3JldHVybn1jbGVhck1hcE1hcmtlcnMoKTtjb25zdCBzdG9wcz1wcm9qZWN0Py5zdG9wc3x8W107aWYoIXN0b3BzLmxlbmd0aClyZXR1cm47YWRkUm91dGVMYXllcnMobWFwLCdtYWluJyxzdG9wcy5maWx0ZXIodmFsaWRQb2ludCkubWFwKHM9PltOdW1iZXIocy5sb24pLE51bWJlcihzLmxhdCldKSk7YWRkQ2x1c3RlckxheWVycyhtYXAsJ21haW4nKTtiaW5kTWFwSW50ZXJhY3Rpb25zKG1hcCwnbWFpbicsZmFsc2UpO2NvbnN0IGJvdW5kcz1uZXcgbWFwbGlicmVnbC5MbmdMYXRCb3VuZHMoKTtzdG9wcy5maWx0ZXIodmFsaWRQb2ludCkuZm9yRWFjaChzPT5ib3VuZHMuZXh0ZW5kKFtOdW1iZXIocy5sb24pLE51bWJlcihzLmxhdCldKSk7aWYoZml0JiYhYm91bmRzLmlzRW1wdHkoKSl7dHJ5e21hcC5maXRCb3VuZHMoYm91bmRzLHtwYWRkaW5nOnt0b3A6ODUsYm90dG9tOjkwLGxlZnQ6OTUscmlnaHQ6OTV9LG1heFpvb206MTQuOCxkdXJhdGlvbjo4NTB9KX1jYXRjaHt9fXNldFRpbWVvdXQocmVuZGVyU2VsZWN0ZWRQaG90b0J1YmJsZXMsODApfQpmdW5jdGlvbiBzZXRNYXBTdHlsZShrZXkpe2lmKCFNQVBfU1RZTEVTW2tleV0pcmV0dXJuO21hcFN0eWxlS2V5PWtleTtsb2NhbFN0b3JhZ2Uuc2V0SXRlbSgndHJpcHB5X21hcF9zdHlsZScsa2V5KTtbJ2xpZ2h0JywnZGFyaycsJ3NhdGVsbGl0ZSddLmZvckVhY2goaz0+ZWwoaysnTWFwQnV0dG9uJykuY2xhc3NMaXN0LnRvZ2dsZSgnYWN0aXZlJyxrPT09a2V5KSk7ZWwoJ2RlZmF1bHRNYXBTZWxlY3QnKS52YWx1ZT1rZXk7aWYobWFwKXttYXAuc2V0U3R5bGUoY2xvbmVTdHlsZShrZXkpKTttYXAub25jZSgnc3R5bGUubG9hZCcsKCk9PnJlbmRlck1hcChmYWxzZSkpfX0KZnVuY3Rpb24gYmVhcmluZyhhLGIpe2NvbnN0IHk9TWF0aC5zaW4oKGIubG9uLWEubG9uKSpNYXRoLlBJLzE4MCkqTWF0aC5jb3MoYi5sYXQqTWF0aC5QSS8xODApO2NvbnN0IHg9TWF0aC5jb3MoYS5sYXQqTWF0aC5QSS8xODApKk1hdGguc2luKGIubGF0Kk1hdGguUEkvMTgwKS1NYXRoLnNpbihhLmxhdCpNYXRoLlBJLzE4MCkqTWF0aC5jb3MoYi5sYXQqTWF0aC5QSS8xODApKk1hdGguY29zKChiLmxvbi1hLmxvbikqTWF0aC5QSS8xODApO3JldHVybihNYXRoLmF0YW4yKHkseCkqMTgwL01hdGguUEkrMzYwKSUzNjB9CmZ1bmN0aW9uIHNlbGVjdFN0b3AoaWQse2ZseT10cnVlLHBvcHVwPXRydWUsZmlsdGVyPXRydWV9PXt9KXtpZighcHJvamVjdClyZXR1cm47Y29uc3QgaW5kZXg9KHByb2plY3Quc3RvcHN8fFtdKS5maW5kSW5kZXgocz0+cy5zdG9wX2lkPT09aWQpO2lmKGluZGV4PDApcmV0dXJuO2NvbnN0IHN0b3A9cHJvamVjdC5zdG9wc1tpbmRleF07YWN0aXZlU3RvcElkPWlkO2lmKGZpbHRlcilmaWx0ZXJTdG9wSWQ9aWQ7cmVuZGVyU3RvcHMoKTtyZW5kZXJHYWxsZXJ5KCk7cmVuZGVyTWFwKGZhbHNlKTtpZihmbHkmJm1hcCl7Y29uc3QgbmV4dD1wcm9qZWN0LnN0b3BzW01hdGgubWluKGluZGV4KzEscHJvamVjdC5zdG9wcy5sZW5ndGgtMSldfHxzdG9wO21hcC5mbHlUbyh7Y2VudGVyOltzdG9wLmxvbixzdG9wLmxhdF0sem9vbToxNS43LHBpdGNoOjQyLGJlYXJpbmc6YmVhcmluZyhzdG9wLG5leHQpLGR1cmF0aW9uOjEwNTAsZXNzZW50aWFsOnRydWV9KX1pZihwb3B1cClzZXRUaW1lb3V0KCgpPT5zaG93U3RvcFBvcHVwKHN0b3AsaW5kZXgpLDQ1MCl9CmZ1bmN0aW9uIHNob3dTdG9wUG9wdXAoc3RvcCxpbmRleCl7aWYoYWN0aXZlUG9wdXApe3RyeXthY3RpdmVQb3B1cC5yZW1vdmUoKX1jYXRjaHt9fWNvbnN0IGFzc2V0cz1zdG9wQXNzZXRzKHN0b3ApLGZpcnN0PWFzc2V0c1swXTtjb25zdCBjb250ZW50PWA8ZGl2IGNsYXNzPSJzdG9wUG9wdXAiPjxkaXYgY2xhc3M9InN0b3BQb3B1cEltYWdlIj4ke2ZpcnN0Py50aHVtYj9gPGltZyBzcmM9IiR7ZXNjKGZpcnN0LnRodW1iKX0iPmA6Jyd9PC9kaXY+PGRpdiBjbGFzcz0ic3RvcFBvcHVwQm9keSI+PHNwYW4gY2xhc3M9InBvcHVwS2lja2VyIj5TdG9wICR7aW5kZXgrMX08L3NwYW4+PGRpdiBjbGFzcz0icG9wdXBUaXRsZSI+JHtlc2Moc3RvcE5hbWUoc3RvcCxpbmRleCkpfTwvZGl2PjxkaXYgY2xhc3M9InBvcHVwTWV0YSI+JHthc3NldHMubGVuZ3RofSBwaG90b3MmbmJzcDsg4oCiICZuYnNwOyR7TWF0aC5yb3VuZChzdG9wLnJhZGl1c19tfHwyMDApfSBtIHJhZGl1czwvZGl2PjxkaXYgY2xhc3M9InBvcHVwQnV0dG9ucyI+PGJ1dHRvbiBkYXRhLXBvcHVwLWZpbHRlcj0iJHtlc2Moc3RvcC5zdG9wX2lkKX0iPlZpZXcgUGhvdG9zPC9idXR0b24+PGJ1dHRvbiBkYXRhLXBvcHVwLXByZXNlbnQ9IiR7aW5kZXh9Ij7ilrYgUHJlc2VudDwvYnV0dG9uPjxidXR0b24gY2xhc3M9ImRhbmdlciIgZGF0YS1wb3B1cC1kZWxldGU9IiR7ZXNjKHN0b3Auc3RvcF9pZCl9Ij7ijKs8L2J1dHRvbj48L2Rpdj48L2Rpdj48L2Rpdj5gO2FjdGl2ZVBvcHVwPW5ldyBtYXBsaWJyZWdsLlBvcHVwKHtvZmZzZXQ6MjQsY2xvc2VCdXR0b246dHJ1ZSxtYXhXaWR0aDonMzUwcHgnfSkuc2V0TG5nTGF0KFtzdG9wLmxvbixzdG9wLmxhdF0pLnNldEhUTUwoY29udGVudCkuYWRkVG8obWFwKTtzZXRUaW1lb3V0KCgpPT57ZG9jdW1lbnQucXVlcnlTZWxlY3RvcignW2RhdGEtcG9wdXAtZmlsdGVyXScpPy5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PntmaWx0ZXJTdG9wSWQ9c3RvcC5zdG9wX2lkO3JlbmRlckdhbGxlcnkoKX0pO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoJ1tkYXRhLXBvcHVwLXByZXNlbnRdJyk/LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+b3BlblByZXNlbnQoaW5kZXgpKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yKCdbZGF0YS1wb3B1cC1kZWxldGVdJyk/LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+ZGVsZXRlU3RvcChzdG9wLnN0b3BfaWQpKX0sMCl9CmZ1bmN0aW9uIHJlbmRlclN0b3BzKCl7Y29uc3Qgc3RvcHM9cHJvamVjdD8uc3RvcHN8fFtdLHE9ZWwoJ3N0b3BTZWFyY2gnKS52YWx1ZS50cmltKCkudG9Mb3dlckNhc2UoKTtlbCgnc3RvcENvdW50JykudGV4dENvbnRlbnQ9YCgke3N0b3BzLmxlbmd0aH0pYDtlbCgnc3RvcExpc3QnKS5pbm5lckhUTUw9c3RvcHMubWFwKChzLGkpPT4oe3MsaX0pKS5maWx0ZXIoeD0+IXF8fHN0b3BOYW1lKHgucyx4LmkpLnRvTG93ZXJDYXNlKCkuaW5jbHVkZXMocSkpLm1hcCgoe3MsaX0pPT57Y29uc3QgY291bnQ9KHMuYXNzZXRfaWRzfHxbXSkubGVuZ3RoLGFjdGl2ZT1zLnN0b3BfaWQ9PT1hY3RpdmVTdG9wSWQ7cmV0dXJuYDxhcnRpY2xlIGNsYXNzPSJzdG9wQ2FyZCAke2FjdGl2ZT8nYWN0aXZlIG9wZW4nOicnfSIgZGF0YS1zdG9wPSIke2VzYyhzLnN0b3BfaWQpfSI+PGRpdiBjbGFzcz0ic3RvcFN1bW1hcnkiPjxkaXYgY2xhc3M9InN0b3BOdW1iZXIiPiR7aSsxfTwvZGl2PjxkaXY+PGRpdiBjbGFzcz0ic3RvcE5hbWUiPiR7ZXNjKHN0b3BOYW1lKHMsaSkpfTwvZGl2PjxkaXYgY2xhc3M9InN0b3BNZXRhIj4ke2NvdW50fSBwaG90b3MmbmJzcDsg4oCiICZuYnNwOyR7ZXNjKHN0b3BEYXRlUmFuZ2UocykpfTwvZGl2PjwvZGl2PjxkaXYgY2xhc3M9InN0b3BDaGV2cm9uIj7igLo8L2Rpdj48L2Rpdj48ZGl2IGNsYXNzPSJzdG9wQ29udHJvbHMiPjxidXR0b24gZGF0YS12aWV3PSIke2VzYyhzLnN0b3BfaWQpfSI+VmlldzwvYnV0dG9uPjxidXR0b24gZGF0YS1yZW5hbWU9IiR7ZXNjKHMuc3RvcF9pZCl9Ij5SZW5hbWU8L2J1dHRvbj48YnV0dG9uIGRhdGEtcmVjZW50ZXI9IiR7ZXNjKHMuc3RvcF9pZCl9Ij5SZWNlbnRlcjwvYnV0dG9uPjxidXR0b24gZGF0YS1kZWxldGUtc3RvcD0iJHtlc2Mocy5zdG9wX2lkKX0iPkRlbGV0ZTwvYnV0dG9uPjwvZGl2PjwvYXJ0aWNsZT5gfSkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gc3RvcHMgZm91bmQuPC9kaXY+Jztkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCcuc3RvcFN1bW1hcnknKS5mb3JFYWNoKHJvdz0+cm93LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+e2NvbnN0IGNhcmQ9cm93LmNsb3Nlc3QoJy5zdG9wQ2FyZCcpO2NvbnN0IGlkPWNhcmQuZGF0YXNldC5zdG9wO2lmKGFjdGl2ZVN0b3BJZD09PWlkKWNhcmQuY2xhc3NMaXN0LnRvZ2dsZSgnb3BlbicpO2Vsc2Ugc2VsZWN0U3RvcChpZCx7Zmx5OnRydWUscG9wdXA6dHJ1ZSxmaWx0ZXI6dHJ1ZX0pfSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXZpZXddJykuZm9yRWFjaChiPT5iLmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+c2VsZWN0U3RvcChiLmRhdGFzZXQudmlldyx7Zmx5OnRydWUscG9wdXA6dHJ1ZSxmaWx0ZXI6dHJ1ZX0pKSk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtcmVuYW1lXScpLmZvckVhY2goYj0+Yi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PnJlbmFtZVN0b3AoYi5kYXRhc2V0LnJlbmFtZSkpKTtkb2N1bWVudC5xdWVyeVNlbGVjdG9yQWxsKCdbZGF0YS1yZWNlbnRlcl0nKS5mb3JFYWNoKGI9PmIuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5yZWNlbnRlclN0b3AoYi5kYXRhc2V0LnJlY2VudGVyKSkpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLWRlbGV0ZS1zdG9wXScpLmZvckVhY2goYj0+Yi5hZGRFdmVudExpc3RlbmVyKCdjbGljaycsKCk9PmRlbGV0ZVN0b3AoYi5kYXRhc2V0LmRlbGV0ZVN0b3ApKSl9CmZ1bmN0aW9uIGdhbGxlcnlBc3NldHMoKXtpZighcHJvamVjdClyZXR1cm5bXTtpZihmaWx0ZXJTdG9wSWQpe2NvbnN0IHN0b3A9cHJvamVjdC5zdG9wcy5maW5kKHM9PnMuc3RvcF9pZD09PWZpbHRlclN0b3BJZCk7cmV0dXJuIHN0b3BBc3NldHMoc3RvcCl9cmV0dXJuIHByb2plY3QuYXNzZXRzfHxbXX0KZnVuY3Rpb24gcmVuZGVyR2FsbGVyeSgpe2NvbnN0IGFzc2V0cz1nYWxsZXJ5QXNzZXRzKCksc3RvcD1wcm9qZWN0Py5zdG9wcz8uZmluZChzPT5zLnN0b3BfaWQ9PT1maWx0ZXJTdG9wSWQpLGlkeD1zdG9wP3Byb2plY3Quc3RvcHMuaW5kZXhPZihzdG9wKTotMTtlbCgnbWVkaWFUaXRsZScpLnRleHRDb250ZW50PXN0b3A/YFN0b3AgJHtpZHgrMX0gIOKAoiAgJHtzdG9wTmFtZShzdG9wLGlkeCl9YDonTWVkaWEnO2VsKCdtZWRpYUNvdW50JykudGV4dENvbnRlbnQ9YCR7YXNzZXRzLmxlbmd0aH0gaXRlbXNgO2VsKCdmaWx0ZXJDaGlwJykuY2xhc3NMaXN0LnRvZ2dsZSgnc2hvdycsISFzdG9wKTtlbCgnZmlsdGVyQ2hpcFRleHQnKS50ZXh0Q29udGVudD1zdG9wP2BGaWx0ZXI6ICR7c3RvcE5hbWUoc3RvcCxpZHgpfWA6J0ZpbHRlcjogQWxsIFN0b3BzJztlbCgnZ2FsbGVyeScpLmlubmVySFRNTD1hc3NldHMubWFwKGE9PmA8ZGl2IGNsYXNzPSJtZWRpYVRpbGUgJHthLmFzc2V0X2lkPT09YWN0aXZlQXNzZXRJZD8nYWN0aXZlJzonJ30iIGRhdGEtYXNzZXQ9IiR7ZXNjKGEuYXNzZXRfaWQpfSI+JHthLnRodW1iP2A8aW1nIHNyYz0iJHtlc2MoYS50aHVtYil9Ij5gOicnfTxkaXYgY2xhc3M9Im1lZGlhVGlsZU5hbWUiPiR7ZXNjKGEubmFtZXx8J1Bob3RvJyl9PC9kaXY+PC9kaXY+YCkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gR1BTIG1lZGlhIGluIHRoaXMgdmlldy48L2Rpdj4nO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJy5tZWRpYVRpbGUnKS5mb3JFYWNoKHRpbGU9PnRpbGUuYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5mb2N1c0Fzc2V0KHRpbGUuZGF0YXNldC5hc3NldCkpKX0KZnVuY3Rpb24gZm9jdXNBc3NldChpZCl7Y29uc3QgYXNzZXQ9KHByb2plY3Q/LmFzc2V0c3x8W10pLmZpbmQoYT0+YS5hc3NldF9pZD09PWlkKTtpZighYXNzZXR8fCF2YWxpZFBvaW50KGFzc2V0KSlyZXR1cm47YWN0aXZlQXNzZXRJZD1pZDtyZW5kZXJHYWxsZXJ5KCk7cmVuZGVyU2VsZWN0ZWRQaG90b0J1YmJsZXMoKTtpZihtYXApbWFwLmZseVRvKHtjZW50ZXI6W051bWJlcihhc3NldC5sb24pLE51bWJlcihhc3NldC5sYXQpXSx6b29tOjE4LjcscGl0Y2g6NTAsYmVhcmluZzoxMCxkdXJhdGlvbjo5NTAsZXNzZW50aWFsOnRydWV9KTtpZihhY3RpdmVQb3B1cCl7dHJ5e2FjdGl2ZVBvcHVwLnJlbW92ZSgpfWNhdGNoe319YWN0aXZlUG9wdXA9bmV3IG1hcGxpYnJlZ2wuUG9wdXAoe29mZnNldDoyNCxjbG9zZUJ1dHRvbjp0cnVlLG1heFdpZHRoOic0MjBweCd9KS5zZXRMbmdMYXQoW051bWJlcihhc3NldC5sb24pLE51bWJlcihhc3NldC5sYXQpXSkuc2V0SFRNTChgPGRpdiBjbGFzcz0ic3RvcFBvcHVwIj48ZGl2IGNsYXNzPSJzdG9wUG9wdXBJbWFnZSI+JHthc3NldC50aHVtYj9gPGltZyBzcmM9IiR7ZXNjKGFzc2V0LnRodW1iKX0iPmA6Jyd9PC9kaXY+PGRpdiBjbGFzcz0ic3RvcFBvcHVwQm9keSI+PHNwYW4gY2xhc3M9InBvcHVwS2lja2VyIj5TZWxlY3RlZCBwaG90bzwvc3Bhbj48ZGl2IGNsYXNzPSJwb3B1cFRpdGxlIj4ke2VzYyhhc3NldC5uYW1lfHwnUGhvdG8nKX08L2Rpdj48ZGl2IGNsYXNzPSJwb3B1cE1ldGEiPiR7ZXNjKGZvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSkpfTwvZGl2PjwvZGl2PjwvZGl2PmApLmFkZFRvKG1hcCl9CmFzeW5jIGZ1bmN0aW9uIHNhdmVQcm9qZWN0KCl7aWYoIXByb2plY3QpcmV0dXJuO3Byb2plY3Q9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytlbmNvZGVVUklDb21wb25lbnQocHJvamVjdC5pZCkse21ldGhvZDonUFVUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkocHJvamVjdCl9KTthd2FpdCByZWZyZXNoUHJvamVjdFN1bW1hcnkoKTtyZW5kZXJBbGwoKX0KYXN5bmMgZnVuY3Rpb24gcmVmcmVzaFByb2plY3RTdW1tYXJ5KCl7cHJvamVjdHM9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3RzJyl9CmFzeW5jIGZ1bmN0aW9uIHJlbmFtZVByb2plY3QoKXtpZighcHJvamVjdClyZXR1cm47Y29uc3QgdmFsdWU9cHJvbXB0KCdKb3VybmV5IG5hbWUnLHByb2plY3QubmFtZXx8JycpO2lmKCF2YWx1ZT8udHJpbSgpKXJldHVybjtwcm9qZWN0Lm5hbWU9dmFsdWUudHJpbSgpO3Byb2plY3Quc2V0dGluZ3M9cHJvamVjdC5zZXR0aW5nc3x8e307cHJvamVjdC5zZXR0aW5ncy50aXRsZT1wcm9qZWN0Lm5hbWU7YXdhaXQgc2F2ZVByb2plY3QoKX0KYXN5bmMgZnVuY3Rpb24gcmVuYW1lU3RvcChpZCl7Y29uc3QgaT1wcm9qZWN0LnN0b3BzLmZpbmRJbmRleChzPT5zLnN0b3BfaWQ9PT1pZCk7aWYoaTwwKXJldHVybjtjb25zdCB2YWx1ZT1wcm9tcHQoJ1N0b3AgbmFtZScsc3RvcE5hbWUocHJvamVjdC5zdG9wc1tpXSxpKSk7aWYoIXZhbHVlPy50cmltKCkpcmV0dXJuO3Byb2plY3Quc3RvcHNbaV0ubmFtZT12YWx1ZS50cmltKCk7YXdhaXQgc2F2ZVByb2plY3QoKX0KYXN5bmMgZnVuY3Rpb24gcmVjZW50ZXJTdG9wKGlkKXtjb25zdCBzdG9wPXByb2plY3Quc3RvcHMuZmluZChzPT5zLnN0b3BfaWQ9PT1pZCksYXNzZXRzPXN0b3BBc3NldHMoc3RvcCk7aWYoIXN0b3B8fCFhc3NldHMubGVuZ3RoKXJldHVybiB0b2FzdCgnVGhpcyBzdG9wIGhhcyBubyBwaG90b3MgdG8gcmVjZW50ZXIgZnJvbS4nKTtzdG9wLmxhdD1hc3NldHMucmVkdWNlKChuLGEpPT5uK051bWJlcihhLmxhdCksMCkvYXNzZXRzLmxlbmd0aDtzdG9wLmxvbj1hc3NldHMucmVkdWNlKChuLGEpPT5uK051bWJlcihhLmxvbiksMCkvYXNzZXRzLmxlbmd0aDthd2FpdCBzYXZlUHJvamVjdCgpO3NlbGVjdFN0b3AoaWQse2ZseTp0cnVlLHBvcHVwOnRydWUsZmlsdGVyOnRydWV9KX0KYXN5bmMgZnVuY3Rpb24gZGVsZXRlU3RvcChpZCl7aWYoIWNvbmZpcm0oJ0RlbGV0ZSB0aGlzIHN0b3A/IFBob3RvcyByZW1haW4gaW4gdGhlIGpvdXJuZXkuJykpcmV0dXJuO3Byb2plY3Quc3RvcHM9cHJvamVjdC5zdG9wcy5maWx0ZXIocz0+cy5zdG9wX2lkIT09aWQpO2lmKGFjdGl2ZVN0b3BJZD09PWlkKWFjdGl2ZVN0b3BJZD1wcm9qZWN0LnN0b3BzWzBdPy5zdG9wX2lkfHxudWxsO2lmKGZpbHRlclN0b3BJZD09PWlkKWZpbHRlclN0b3BJZD1hY3RpdmVTdG9wSWQ7YXdhaXQgc2F2ZVByb2plY3QoKX0KYXN5bmMgZnVuY3Rpb24gYWRkU3RvcCgpe2lmKCFwcm9qZWN0fHwhbWFwKXJldHVybiB0b2FzdCgnTG9hZCBhIGpvdXJuZXkgZmlyc3QuJyk7Y29uc3QgY2VudGVyPW1hcC5nZXRDZW50ZXIoKTtwcm9qZWN0LnN0b3BzPXByb2plY3Quc3RvcHN8fFtdO2NvbnN0IHN0b3A9e3N0b3BfaWQ6Y3J5cHRvLnJhbmRvbVVVSUQoKS5zbGljZSgwLDgpLG5hbWU6YFN0b3AgJHtwcm9qZWN0LnN0b3BzLmxlbmd0aCsxfWAsbGF0OmNlbnRlci5sYXQsbG9uOmNlbnRlci5sbmcscmFkaXVzX206TnVtYmVyKHByb2plY3Quc2V0dGluZ3M/LnN0b3BfcmFkaXVzX218fDIwMCksYXNzZXRfaWRzOltdLG1vZGU6J21hbnVhbCcsbG9ja2VkOmZhbHNlfTtwcm9qZWN0LnN0b3BzLnB1c2goc3RvcCk7YXdhaXQgc2F2ZVByb2plY3QoKTtzZWxlY3RTdG9wKHN0b3Auc3RvcF9pZCx7Zmx5OnRydWUscG9wdXA6dHJ1ZSxmaWx0ZXI6dHJ1ZX0pfQphc3luYyBmdW5jdGlvbiByZWNsdXN0ZXIoKXtpZighcHJvamVjdClyZXR1cm47Y29uc3QgcmFkaXVzPU51bWJlcihlbCgnc3RvcFJhZGl1cycpLnZhbHVlfHwyMDApO3Byb2plY3Q9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytlbmNvZGVVUklDb21wb25lbnQocHJvamVjdC5pZCkrJy9yZWNsdXN0ZXInLHttZXRob2Q6J1BPU1QnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sYm9keTpKU09OLnN0cmluZ2lmeSh7cmFkaXVzX206cmFkaXVzfSl9KTtwcm9qZWN0LnNldHRpbmdzPXByb2plY3Quc2V0dGluZ3N8fHt9O3Byb2plY3Quc2V0dGluZ3Muc3RvcF9yYWRpdXNfbT1yYWRpdXM7YWN0aXZlU3RvcElkPXByb2plY3Quc3RvcHNbMF0/LnN0b3BfaWR8fG51bGw7ZmlsdGVyU3RvcElkPWFjdGl2ZVN0b3BJZDthd2FpdCByZWZyZXNoUHJvamVjdFN1bW1hcnkoKTtyZW5kZXJBbGwoKTtzZXRNb2RhbCgnc2V0dGluZ3NNb2RhbCcsZmFsc2UpO3RvYXN0KCdTdG9wcyByZWNsdXN0ZXJlZCcpfQphc3luYyBmdW5jdGlvbiByZXZlcnNlUm91dGUoKXtpZighcHJvamVjdClyZXR1cm47cHJvamVjdC5zdG9wcy5yZXZlcnNlKCk7cHJvamVjdC5zZXR0aW5ncz1wcm9qZWN0LnNldHRpbmdzfHx7fTtwcm9qZWN0LnNldHRpbmdzLnJldmVyc2Vfcm91dGU9IXByb2plY3Quc2V0dGluZ3MucmV2ZXJzZV9yb3V0ZTthd2FpdCBzYXZlUHJvamVjdCgpO3RvYXN0KCdSb3V0ZSBvcmRlciByZXZlcnNlZCcpfQphc3luYyBmdW5jdGlvbiB0ZXN0SW1taWNoKCl7Y29uc3QgYm9keT17YmFzZV91cmw6ZWwoJ2ltbWljaFVybCcpLnZhbHVlLnRyaW0oKSxhcGlfa2V5OmVsKCdpbW1pY2hLZXknKS52YWx1ZS50cmltKCl9O2NvbnN0IHJlc3VsdD1hd2FpdCBhcGkoJy9hcGkvaW1taWNoL3Rlc3QnLHttZXRob2Q6J1BPU1QnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sYm9keTpKU09OLnN0cmluZ2lmeShib2R5KX0pO3RvYXN0KHJlc3VsdC5tZXNzYWdlfHwnQ29ubmVjdGlvbiB0ZXN0ZWQnKX0KYXN5bmMgZnVuY3Rpb24gY3JlYXRlSW1taWNoSm91cm5leSgpe2NvbnN0IGJhc2VfdXJsPWVsKCdpbW1pY2hVcmwnKS52YWx1ZS50cmltKCksYXBpX2tleT1lbCgnaW1taWNoS2V5JykudmFsdWUudHJpbSgpLHN0YXJ0X2RhdGU9ZWwoJ3N0YXJ0RGF0ZScpLnZhbHVlLGVuZF9kYXRlPWVsKCdlbmREYXRlJykudmFsdWU7aWYoIWJhc2VfdXJsfHwhYXBpX2tleXx8IXN0YXJ0X2RhdGV8fCFlbmRfZGF0ZSlyZXR1cm4gdG9hc3QoJ0NvbXBsZXRlIHRoZSBJbW1pY2ggVVJMLCBrZXksIGFuZCBkYXRlcy4nKTtzYXZlQ29ubihiYXNlX3VybCxhcGlfa2V5KTt0b2FzdCgnSW1wb3J0aW5nIEdQUyBtZWRpYSBmcm9tIEltbWljaOKApicpO2NvbnN0IGNyZWF0ZWQ9YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvaW1taWNoJyx7bWV0aG9kOidQT1NUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkoe25hbWU6YEltbWljaCBKb3VybmV5ICR7c3RhcnRfZGF0ZX0gdG8gJHtlbmRfZGF0ZX1gLGJhc2VfdXJsLGFwaV9rZXksc3RhcnRfZGF0ZSxlbmRfZGF0ZX0pfSk7c2V0TW9kYWwoJ2ltbWljaE1vZGFsJyxmYWxzZSk7YXdhaXQgcmVmcmVzaFByb2plY3RTdW1tYXJ5KCk7YXdhaXQgb3BlblByb2plY3QoY3JlYXRlZC5pZCl9CmFzeW5jIGZ1bmN0aW9uIGNyZWF0ZVVwbG9hZEpvdXJuZXkoKXtjb25zdCBmaWxlcz1lbCgndXBsb2FkRmlsZXMnKS5maWxlcztpZighZmlsZXMubGVuZ3RoKXJldHVybiB0b2FzdCgnQ2hvb3NlIG1lZGlhIGZpbGVzIGZpcnN0LicpO2NvbnN0IGZvcm09bmV3IEZvcm1EYXRhKCk7Zm9yKGNvbnN0IGZpbGUgb2YgZmlsZXMpZm9ybS5hcHBlbmQoJ2ZpbGVzJyxmaWxlKTtmb3JtLmFwcGVuZCgnbmFtZScsZWwoJ3VwbG9hZE5hbWUnKS52YWx1ZS50cmltKCl8fCdVcGxvYWRlZCBKb3VybmV5Jyk7dG9hc3QoJ1JlYWRpbmcgR1BTIG1ldGFkYXRh4oCmJyk7Y29uc3QgY3JlYXRlZD1hd2FpdCBhcGkoJy9hcGkvcHJvamVjdC91cGxvYWQnLHttZXRob2Q6J1BPU1QnLGJvZHk6Zm9ybX0pO3NldE1vZGFsKCd1cGxvYWRNb2RhbCcsZmFsc2UpO2F3YWl0IHJlZnJlc2hQcm9qZWN0U3VtbWFyeSgpO2F3YWl0IG9wZW5Qcm9qZWN0KGNyZWF0ZWQuaWQpfQphc3luYyBmdW5jdGlvbiByZW5kZXJNcDQoKXtpZighcHJvamVjdClyZXR1cm4gdG9hc3QoJ0xvYWQgYSBqb3VybmV5IGZpcnN0LicpO3Byb2plY3Quc2V0dGluZ3M9cHJvamVjdC5zZXR0aW5nc3x8e307cHJvamVjdC5zZXR0aW5ncy5kdXJhdGlvbl9taW49MTI7YXdhaXQgYXBpKCcvYXBpL3Byb2plY3QvJytlbmNvZGVVUklDb21wb25lbnQocHJvamVjdC5pZCkse21ldGhvZDonUFVUJyxoZWFkZXJzOnsnQ29udGVudC1UeXBlJzonYXBwbGljYXRpb24vanNvbid9LGJvZHk6SlNPTi5zdHJpbmdpZnkocHJvamVjdCl9KTtjb25zdCBmb3JtPW5ldyBGb3JtRGF0YSgpO2lmKGVsKCdhdWRpb1N3aXRjaCcpLmNsYXNzTGlzdC5jb250YWlucygnb24nKSYmZWwoJ2F1ZGlvSW5wdXQnKS5maWxlc1swXSlmb3JtLmFwcGVuZCgnYXVkaW8nLGVsKCdhdWRpb0lucHV0JykuZmlsZXNbMF0pO3RvYXN0KCdSZW5kZXJpbmcgTVA04oCmJyk7Y29uc3QgcmVzdWx0PWF3YWl0IGFwaSgnL2FwaS9wcm9qZWN0LycrZW5jb2RlVVJJQ29tcG9uZW50KHByb2plY3QuaWQpKycvcmVuZGVyJyx7bWV0aG9kOidQT1NUJyxib2R5OmZvcm19KTtjb25zdCB1cmw9cmVzdWx0LnVybHx8cmVzdWx0LnBhdGh8fHJlc3VsdC5kb3dubG9hZF91cmw7aWYodXJsKXdpbmRvdy5vcGVuKHVybCwnX2JsYW5rJyk7dG9hc3QoJ1JlbmRlciBjb21wbGV0ZScpfQpmdW5jdGlvbiBlbnN1cmVQcmVzZW50TWFwKCl7aWYocHJlc2VudE1hcClyZXR1cm47cHJlc2VudE1hcD1uZXcgbWFwbGlicmVnbC5NYXAoe2NvbnRhaW5lcjoncHJlc2VudE1hcCcsc3R5bGU6Y2xvbmVTdHlsZShtYXBTdHlsZUtleT09PSdsaWdodCc/J3NhdGVsbGl0ZSc6bWFwU3R5bGVLZXkpLGNlbnRlcjpbLTk4LDM5XSx6b29tOjMscGl0Y2g6NTUsYmVhcmluZzowfSk7cHJlc2VudE1hcC5hZGRDb250cm9sKG5ldyBtYXBsaWJyZWdsLk5hdmlnYXRpb25Db250cm9sKCksJ2JvdHRvbS1yaWdodCcpO3ByZXNlbnRNYXAub24oJ3pvb21lbmQnLHJlbmRlclByZXNlbnRQaG90b0J1YmJsZXMpO3ByZXNlbnRNYXAub24oJ21vdmVlbmQnLHJlbmRlclByZXNlbnRQaG90b0J1YmJsZXMpfQpmdW5jdGlvbiBwcmVzZW50QXNzZXRzKCl7Y29uc3Qgc3RvcD1wcm9qZWN0Py5zdG9wcz8uW3ByZXNlbnRTdG9wSW5kZXhdO3JldHVybiBzdG9wQXNzZXRzKHN0b3ApfQpmdW5jdGlvbiByZW5kZXJQcmVzZW50U3RvcHMoKXtjb25zdCBzdG9wcz1wcm9qZWN0Py5zdG9wc3x8W107ZWwoJ3ByZXNlbnRTdG9wUmFpbCcpLmlubmVySFRNTD1gPGRpdiBzdHlsZT0iZm9udC13ZWlnaHQ6OTUwO21hcmdpbjoycHggNHB4IDEwcHgiPkpvdXJuZXkgU3RvcHM8L2Rpdj5gK3N0b3BzLm1hcCgocyxpKT0+YDxkaXYgY2xhc3M9InByZXNlbnRTdG9wSXRlbSAke2k9PT1wcmVzZW50U3RvcEluZGV4PydhY3RpdmUnOicnfSIgZGF0YS1wcmVzZW50LXN0b3A9IiR7aX0iPjxiPiR7aSsxfS48L2I+Jm5ic3A7ICR7ZXNjKHN0b3BOYW1lKHMsaSkpfTxkaXYgY2xhc3M9InNtYWxsIj4keyhzLmFzc2V0X2lkc3x8W10pLmxlbmd0aH0gcGhvdG9zPGJyPiR7ZXNjKHN0b3BEYXRlUmFuZ2UocykpfTwvZGl2PjwvZGl2PmApLmpvaW4oJycpO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXByZXNlbnQtc3RvcF0nKS5mb3JFYWNoKHg9PnguYWRkRXZlbnRMaXN0ZW5lcignY2xpY2snLCgpPT5nb1ByZXNlbnRTdG9wKE51bWJlcih4LmRhdGFzZXQucHJlc2VudFN0b3ApKSkpfQpmdW5jdGlvbiByZW5kZXJQcmVzZW50RmlsbXN0cmlwKCl7Y29uc3QgYXNzZXRzPXByZXNlbnRBc3NldHMoKTtlbCgncHJlc2VudEZpbG1zdHJpcCcpLmlubmVySFRNTD1hc3NldHMubWFwKChhLGkpPT5gPGRpdiBjbGFzcz0icHJlc2VudFRodW1iICR7aT09PXByZXNlbnRQaG90b0luZGV4PydhY3RpdmUnOicnfSIgZGF0YS1wcmVzZW50LXBob3RvPSIke2l9Ij4ke2EudGh1bWI/YDxpbWcgc3JjPSIke2VzYyhhLnRodW1iKX0iPmA6Jyd9PGRpdiBjbGFzcz0icHJlc2VudFRodW1iTGFiZWwiPiR7ZXNjKGEubmFtZXx8J1Bob3RvJyl9PGJyPiR7ZXNjKGZvcm1hdEFzc2V0RGF0ZVRpbWUoYS50aW1lKSl9PC9kaXY+PC9kaXY+YCkuam9pbignJyl8fCc8ZGl2IGNsYXNzPSJzbWFsbCI+Tm8gcGhvdG9zIGFzc2lnbmVkIHRvIHRoaXMgc3RvcC48L2Rpdj4nO2RvY3VtZW50LnF1ZXJ5U2VsZWN0b3JBbGwoJ1tkYXRhLXByZXNlbnQtcGhvdG9dJykuZm9yRWFjaCh4PT54LmFkZEV2ZW50TGlzdGVuZXIoJ2NsaWNrJywoKT0+Z29QcmVzZW50UGhvdG8oTnVtYmVyKHguZGF0YXNldC5wcmVzZW50UGhvdG8pKSkpfQpmdW5jdGlvbiByZW5kZXJQcmVzZW50TWFwTGF5ZXJzKCl7aWYoIXByZXNlbnRNYXB8fCFwcmVzZW50TWFwLmlzU3R5bGVMb2FkZWQoKSlyZXR1cm47Y2xlYXJCdWJibGVNYXJrZXJzKHByZXNlbnRNYXJrZXJzKTtjbGVhckJ1YmJsZU1hcmtlcnMocHJlc2VudFBob3RvTWFya2Vycyk7Y29uc3Qgc3RvcHM9cHJvamVjdD8uc3RvcHN8fFtdO2FkZFJvdXRlTGF5ZXJzKHByZXNlbnRNYXAsJ3ByZXNlbnQnLHN0b3BzLmZpbHRlcih2YWxpZFBvaW50KS5tYXAocz0+W051bWJlcihzLmxvbiksTnVtYmVyKHMubGF0KV0pKTthZGRDbHVzdGVyTGF5ZXJzKHByZXNlbnRNYXAsJ3ByZXNlbnQnKTtiaW5kTWFwSW50ZXJhY3Rpb25zKHByZXNlbnRNYXAsJ3ByZXNlbnQnLHRydWUpO3JlbmRlclByZXNlbnRQaG90b0J1YmJsZXMoKX0KZnVuY3Rpb24gcmVuZGVyUHJlc2VudFBob3RvQnViYmxlcygpe2NsZWFyQnViYmxlTWFya2VycyhwcmVzZW50UGhvdG9NYXJrZXJzKTtpZighcHJlc2VudE1hcHx8IXByb2plY3Q/LnN0b3BzPy5sZW5ndGgpcmV0dXJuO3ByZXNlbnRBc3NldHMoKS5maWx0ZXIodmFsaWRQb2ludCkuc2xpY2UoMCwxNDApLmZvckVhY2goKGFzc2V0LGkpPT57Y29uc3Qgbm9kZT1hc3NldEJ1YmJsZUVsZW1lbnQoYXNzZXQsaT09PXByZXNlbnRQaG90b0luZGV4KTtub2RlLm9uY2xpY2s9KCk9PmdvUHJlc2VudFBob3RvKGkpO3ByZXNlbnRQaG90b01hcmtlcnMucHVzaChuZXcgbWFwbGlicmVnbC5NYXJrZXIoe2VsZW1lbnQ6bm9kZSxhbmNob3I6J2NlbnRlcid9KS5zZXRMbmdMYXQoW051bWJlcihhc3NldC5sb24pLE51bWJlcihhc3NldC5sYXQpXSkuYWRkVG8ocHJlc2VudE1hcCkpfSl9CmZ1bmN0aW9uIGdvUHJlc2VudFN0b3AoaW5kZXgpe2NvbnN0IHN0b3BzPXByb2plY3Q/LnN0b3BzfHxbXTtpZighc3RvcHMubGVuZ3RoKXJldHVybjtwcmVzZW50U3RvcEluZGV4PShpbmRleCtzdG9wcy5sZW5ndGgpJXN0b3BzLmxlbmd0aDtwcmVzZW50UGhvdG9JbmRleD0tMTtjb25zdCBzdG9wPXN0b3BzW3ByZXNlbnRTdG9wSW5kZXhdLG5leHQ9c3RvcHNbKHByZXNlbnRTdG9wSW5kZXgrMSklc3RvcHMubGVuZ3RoXXx8c3RvcDtyZW5kZXJQcmVzZW50U3RvcHMoKTtyZW5kZXJQcmVzZW50RmlsbXN0cmlwKCk7cmVuZGVyUHJlc2VudFBob3RvQnViYmxlcygpO2NvbnN0IHJhbmdlPXN0b3BEYXRlUmFuZ2Uoc3RvcCk7ZWwoJ3ByZXNlbnRIZWFkZXJUaXRsZScpLnRleHRDb250ZW50PXN0b3BOYW1lKHN0b3AscHJlc2VudFN0b3BJbmRleCk7ZWwoJ3ByZXNlbnRIZWFkZXJNZXRhJykudGV4dENvbnRlbnQ9YFN0b3AgJHtwcmVzZW50U3RvcEluZGV4KzF9IG9mICR7c3RvcHMubGVuZ3RofSDigKIgJHsoc3RvcC5hc3NldF9pZHN8fFtdKS5sZW5ndGh9IHBob3RvcyDigKIgJHtyYW5nZX1gO2VsKCdwcmVzZW50U3RvcEJhbm5lclRpdGxlJykudGV4dENvbnRlbnQ9c3RvcE5hbWUoc3RvcCxwcmVzZW50U3RvcEluZGV4KTtlbCgncHJlc2VudFN0b3BCYW5uZXJSYW5nZScpLnRleHRDb250ZW50PWBTdG9wICR7cHJlc2VudFN0b3BJbmRleCsxfSBvZiAke3N0b3BzLmxlbmd0aH0gIOKAoiAgJHtyYW5nZX0gIOKAoiAgJHsoc3RvcC5hc3NldF9pZHN8fFtdKS5sZW5ndGh9IHBob3Rvc2A7ZWwoJ3ByZXNlbnRQaG90b0NhcmQnKS5jbGFzc0xpc3QucmVtb3ZlKCdzaG93Jyk7Y29uc3QgZGF0YT1zdG9wQm91bmRzKHN0b3ApO2lmKGRhdGEuYXNzZXRzLmxlbmd0aD4xJiYhZGF0YS5ib3VuZHMuaXNFbXB0eSgpKXtwcmVzZW50TWFwLmZpdEJvdW5kcyhkYXRhLmJvdW5kcyx7cGFkZGluZzp7dG9wOjEzMCxib3R0b206MjAwLGxlZnQ6Mjg1LHJpZ2h0OjQzMH0sbWF4Wm9vbToxNi4yLGR1cmF0aW9uOjE3MDAsZXNzZW50aWFsOnRydWV9KTtzZXRUaW1lb3V0KCgpPT5wcmVzZW50TWFwLmVhc2VUbyh7cGl0Y2g6NTgsYmVhcmluZzpiZWFyaW5nKHN0b3AsbmV4dCksZHVyYXRpb246NzAwLGVzc2VudGlhbDp0cnVlfSksOTUwKX1lbHNlIHByZXNlbnRNYXAuZmx5VG8oe2NlbnRlcjpbTnVtYmVyKHN0b3AubG9uKSxOdW1iZXIoc3RvcC5sYXQpXSx6b29tOjE2LHBpdGNoOjU4LGJlYXJpbmc6YmVhcmluZyhzdG9wLG5leHQpLGR1cmF0aW9uOjE2MDAsY3VydmU6MS40NSxlc3NlbnRpYWw6dHJ1ZX0pfQpmdW5jdGlvbiBnb1ByZXNlbnRQaG90byhpbmRleCl7Y29uc3QgYXNzZXRzPXByZXNlbnRBc3NldHMoKTtpZighYXNzZXRzLmxlbmd0aClyZXR1cm47cHJlc2VudFBob3RvSW5kZXg9KGluZGV4K2Fzc2V0cy5sZW5ndGgpJWFzc2V0cy5sZW5ndGg7Y29uc3QgYXNzZXQ9YXNzZXRzW3ByZXNlbnRQaG90b0luZGV4XTtpZighdmFsaWRQb2ludChhc3NldCkpcmV0dXJuO3JlbmRlclByZXNlbnRGaWxtc3RyaXAoKTtyZW5kZXJQcmVzZW50UGhvdG9CdWJibGVzKCk7ZWwoJ3ByZXNlbnRTdG9wQmFubmVyVGl0bGUnKS50ZXh0Q29udGVudD1zdG9wTmFtZShwcm9qZWN0LnN0b3BzW3ByZXNlbnRTdG9wSW5kZXhdLHByZXNlbnRTdG9wSW5kZXgpO2VsKCdwcmVzZW50U3RvcEJhbm5lclJhbmdlJykudGV4dENvbnRlbnQ9YFBob3RvICR7cHJlc2VudFBob3RvSW5kZXgrMX0gb2YgJHthc3NldHMubGVuZ3RofSAg4oCiICAke2Zvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSl9YDtlbCgncHJlc2VudFBob3RvQ2FyZCcpLmlubmVySFRNTD1gJHthc3NldC50aHVtYj9gPGltZyBzcmM9IiR7ZXNjKGFzc2V0LnRodW1iKX0iPmA6Jyd9PGRpdiBjbGFzcz0icHJlc2VudFBob3RvQm9keSI+PGRpdiBjbGFzcz0icHJlc2VudFBob3RvVGl0bGUiPiR7ZXNjKGFzc2V0Lm5hbWV8fCdQaG90bycpfTwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRQaG90b01ldGEiPiR7ZXNjKGZvcm1hdEFzc2V0RGF0ZVRpbWUoYXNzZXQudGltZSkpfTwvZGl2PjxkaXYgY2xhc3M9InByZXNlbnRQaG90b0Nvb3JkcyI+JHtOdW1iZXIoYXNzZXQubGF0KS50b0ZpeGVkKDYpfSwgJHtOdW1iZXIoYXNzZXQubG9uKS50b0ZpeGVkKDYpfTwvZGl2PjwvZGl2PmA7ZWwoJ3ByZXNlbnRQaG90b0NhcmQnKS5jbGFzc0xpc3QuYWRkKCdzaG93Jyk7cHJlc2VudE1hcC5mbHlUbyh7Y2VudGVyOltOdW1iZXIoYXNzZXQubG9uKSxOdW1iZXIoYXNzZXQubGF0KV0sem9vbToxOSxwaXRjaDo0OCxiZWFyaW5nOihwcmVzZW50UGhvdG9JbmRleCoxNyklMzYwLGR1cmF0aW9uOjEzNTAsY3VydmU6MS4zLGVzc2VudGlhbDp0cnVlfSl9CmZ1bmN0aW9uIG9wZW5QcmVzZW50KGluZGV4PTApe2lmKCFwcm9qZWN0Py5zdG9wcz8ubGVuZ3RoKXJldHVybiB0b2FzdCgnTG9hZCBhIGpvdXJuZXkgd2l0aCBzdG9wcyBmaXJzdC4nKTtlbCgncHJlc2VudE92ZXJsYXknKS5jbGFzc0xpc3QuYWRkKCdzaG93Jyk7ZW5zdXJlUHJlc2VudE1hcCgpO3NldFRpbWVvdXQoKCk9PntwcmVzZW50TWFwLnJlc2l6ZSgpO2lmKHByZXNlbnRNYXAuaXNTdHlsZUxvYWRlZCgpKXtyZW5kZXJQcmVzZW50TWFwTGF5ZXJzKCk7Z29QcmVzZW50U3RvcChpbmRleCl9ZWxzZSBwcmVzZW50TWFwLm9uY2UoJ2xvYWQnLCgpPT57cmVuZGVyUHJlc2VudE1hcExheWVycygpO2dvUHJlc2VudFN0b3AoaW5kZXgpfSl9LDkwKX0KZnVuY3Rpb24gY2xvc2VQcmVzZW50KCl7Y2xlYXJJbnRlcnZhbChwcmVzZW50VGltZXIpO3ByZXNlbnRUaW1lcj1udWxsO2VsKCdwbGF5Sm91cm5leUJ1dHRvbicpLnRleHRDb250ZW50PSfilrYgUGxheSc7ZWwoJ3ByZXNlbnRPdmVybGF5JykuY2xhc3NMaXN0LnJlbW92ZSgnc2hvdycpfQpmdW5jdGlvbiB0b2dnbGVQbGF5KCl7aWYocHJlc2VudFRpbWVyKXtjbGVhckludGVydmFsKHByZXNlbnRUaW1lcik7cHJlc2VudFRpbWVyPW51bGw7ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykudGV4dENvbnRlbnQ9J+KWtiBQbGF5JztyZXR1cm59ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykudGV4dENvbnRlbnQ9J+KFoSBQYXVzZSc7cHJlc2VudFRpbWVyPXNldEludGVydmFsKCgpPT57Y29uc3QgYXNzZXRzPXByZXNlbnRBc3NldHMoKTtpZihhc3NldHMubGVuZ3RoJiZwcmVzZW50UGhvdG9JbmRleDxhc3NldHMubGVuZ3RoLTEpZ29QcmVzZW50UGhvdG8ocHJlc2VudFBob3RvSW5kZXgrMSk7ZWxzZSBnb1ByZXNlbnRTdG9wKHByZXNlbnRTdG9wSW5kZXgrMSl9LDQzMDApfQpmdW5jdGlvbiBkb3dubG9hZEdweCgpe2lmKCFwcm9qZWN0KXJldHVybjtjb25zdCBwb2ludHM9KHByb2plY3Quc3RvcHN8fFtdKS5tYXAoKHMsaSk9PmA8d3B0IGxhdD0iJHtzLmxhdH0iIGxvbj0iJHtzLmxvbn0iPjxuYW1lPiR7ZXNjKHN0b3BOYW1lKHMsaSkpfTwvbmFtZT48L3dwdD5gKS5qb2luKCcnKTtjb25zdCBncHg9YDw/eG1sIHZlcnNpb249IjEuMCI/PjxncHggdmVyc2lvbj0iMS4xIiBjcmVhdG9yPSJUcmlwcHkiPiR7cG9pbnRzfTwvZ3B4PmA7Y29uc3QgYmxvYj1uZXcgQmxvYihbZ3B4XSx7dHlwZTonYXBwbGljYXRpb24vZ3B4K3htbCd9KSxhPWRvY3VtZW50LmNyZWF0ZUVsZW1lbnQoJ2EnKTthLmhyZWY9VVJMLmNyZWF0ZU9iamVjdFVSTChibG9iKTthLmRvd25sb2FkPShwcm9qZWN0Lm5hbWV8fCd0cmlwcHknKSsnLmdweCc7YS5jbGljaygpO1VSTC5yZXZva2VPYmplY3RVUkwoYS5ocmVmKX0KZnVuY3Rpb24gYmluZCgpe2VsKCduZXdJbW1pY2hCdXR0b24nKS5vbmNsaWNrPSgpPT5zZXRNb2RhbCgnaW1taWNoTW9kYWwnKTtlbCgndXBsb2FkQnV0dG9uJykub25jbGljaz0oKT0+c2V0TW9kYWwoJ3VwbG9hZE1vZGFsJyk7ZG9jdW1lbnQucXVlcnlTZWxlY3RvckFsbCgnW2RhdGEtY2xvc2VdJykuZm9yRWFjaChiPT5iLm9uY2xpY2s9KCk9PnNldE1vZGFsKGIuZGF0YXNldC5jbG9zZSxmYWxzZSkpO2VsKCdwcm9qZWN0U2VhcmNoQnV0dG9uJykub25jbGljaz0oKT0+ZWwoJ3Byb2plY3RTZWFyY2gnKS5jbGFzc0xpc3QudG9nZ2xlKCdoaWRkZW4nKTtlbCgncHJvamVjdFNlYXJjaCcpLm9uaW5wdXQ9cmVuZGVyUHJvamVjdHM7ZWwoJ3JlbmFtZVByb2plY3RCdXR0b24nKS5vbmNsaWNrPXJlbmFtZVByb2plY3Q7ZWwoJ3ByZXNlbnRCdXR0b24nKS5vbmNsaWNrPSgpPT5vcGVuUHJlc2VudCgwKTtlbCgnZXhwb3J0SnVtcEJ1dHRvbicpLm9uY2xpY2s9KCk9PntlbCgnZXhwb3J0Qm94JykuY2xhc3NMaXN0LnJlbW92ZSgnY29sbGFwc2VkJyk7ZWwoJ2V4cG9ydEJveCcpLnNjcm9sbEludG9WaWV3KHtiZWhhdmlvcjonc21vb3RoJyxibG9jazonZW5kJ30pfTtlbCgnc2V0dGluZ3NCdXR0b24nKS5vbmNsaWNrPSgpPT57ZWwoJ3N0b3BSYWRpdXMnKS52YWx1ZT1wcm9qZWN0Py5zZXR0aW5ncz8uc3RvcF9yYWRpdXNfbXx8MjAwO3NldE1vZGFsKCdzZXR0aW5nc01vZGFsJyl9O2VsKCdhY2NvdW50QnV0dG9uJykub25jbGljaz0oKT0+c2V0TW9kYWwoJ2FjY291bnRNb2RhbCcpO2VsKCdzYXZlQWNjb3VudEJ1dHRvbicpLm9uY2xpY2s9KCk9PntzYXZlQ29ubihlbCgnYWNjb3VudFVybCcpLnZhbHVlLnRyaW0oKSxlbCgnYWNjb3VudEtleScpLnZhbHVlLnRyaW0oKSk7dG9hc3QoJ0ltbWljaCBjb25uZWN0aW9uIHNhdmVkJyk7c2V0TW9kYWwoJ2FjY291bnRNb2RhbCcsZmFsc2UpfTtlbCgndGVzdEltbWljaEJ1dHRvbicpLm9uY2xpY2s9KCk9PnRlc3RJbW1pY2goKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgnY3JlYXRlSm91cm5leUJ1dHRvbicpLm9uY2xpY2s9KCk9PmNyZWF0ZUltbWljaEpvdXJuZXkoKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgnY3JlYXRlVXBsb2FkQnV0dG9uJykub25jbGljaz0oKT0+Y3JlYXRlVXBsb2FkSm91cm5leSgpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpO2VsKCdzdG9wU2VhcmNoQnV0dG9uJykub25jbGljaz0oKT0+ZWwoJ3N0b3BTZWFyY2hXcmFwJykuY2xhc3NMaXN0LnRvZ2dsZSgnc2hvdycpO2VsKCdzdG9wU2VhcmNoJykub25pbnB1dD1yZW5kZXJTdG9wcztlbCgnYWRkU3RvcEJ1dHRvbicpLm9uY2xpY2s9YWRkU3RvcDtlbCgnZXhwb3J0SGVhZGVyJykub25jbGljaz0oKT0+ZWwoJ2V4cG9ydEJveCcpLmNsYXNzTGlzdC50b2dnbGUoJ2NvbGxhcHNlZCcpO2VsKCdhdWRpb1N3aXRjaCcpLm9uY2xpY2s9KCk9PntlbCgnYXVkaW9Td2l0Y2gnKS5jbGFzc0xpc3QudG9nZ2xlKCdvbicpO2lmKGVsKCdhdWRpb1N3aXRjaCcpLmNsYXNzTGlzdC5jb250YWlucygnb24nKSllbCgnYXVkaW9JbnB1dCcpLmNsaWNrKCl9O2VsKCdyZW5kZXJCdXR0b24nKS5vbmNsaWNrPSgpPT5yZW5kZXJNcDQoKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgnZ3B4QnV0dG9uJykub25jbGljaz1kb3dubG9hZEdweDtlbCgnaW1hZ2VTZXRCdXR0b24nKS5vbmNsaWNrPSgpPT50b2FzdCgnSW1hZ2UgU2V0IGV4cG9ydCBpcyBjb21pbmcgbmV4dC4nKTtlbCgnY2xlYXJGaWx0ZXJCdXR0b24nKS5vbmNsaWNrPSgpPT57ZmlsdGVyU3RvcElkPW51bGw7YWN0aXZlU3RvcElkPW51bGw7cmVuZGVyR2FsbGVyeSgpO3JlbmRlclN0b3BzKCk7cmVuZGVyTWFwKGZhbHNlKX07ZWwoJ2xvY2F0ZUJ1dHRvbicpLm9uY2xpY2s9KCk9Pm5hdmlnYXRvci5nZW9sb2NhdGlvbj8uZ2V0Q3VycmVudFBvc2l0aW9uKHA9Pm1hcC5mbHlUbyh7Y2VudGVyOltwLmNvb3Jkcy5sb25naXR1ZGUscC5jb29yZHMubGF0aXR1ZGVdLHpvb206MTUsZHVyYXRpb246OTAwfSksKCk9PnRvYXN0KCdMb2NhdGlvbiB1bmF2YWlsYWJsZScpKTtlbCgnem9vbUluQnV0dG9uJykub25jbGljaz0oKT0+bWFwPy56b29tSW4oKTtlbCgnem9vbU91dEJ1dHRvbicpLm9uY2xpY2s9KCk9Pm1hcD8uem9vbU91dCgpO2VsKCdsaWdodE1hcEJ1dHRvbicpLm9uY2xpY2s9KCk9PnNldE1hcFN0eWxlKCdsaWdodCcpO2VsKCdkYXJrTWFwQnV0dG9uJykub25jbGljaz0oKT0+c2V0TWFwU3R5bGUoJ2RhcmsnKTtlbCgnc2F0ZWxsaXRlTWFwQnV0dG9uJykub25jbGljaz0oKT0+c2V0TWFwU3R5bGUoJ3NhdGVsbGl0ZScpO2VsKCdkZWZhdWx0TWFwU2VsZWN0Jykub25jaGFuZ2U9ZT0+c2V0TWFwU3R5bGUoZS50YXJnZXQudmFsdWUpO2VsKCdyZWNsdXN0ZXJCdXR0b24nKS5vbmNsaWNrPSgpPT5yZWNsdXN0ZXIoKS5jYXRjaChlPT50b2FzdChlLm1lc3NhZ2UpKTtlbCgncmV2ZXJzZVJvdXRlQnV0dG9uJykub25jbGljaz0oKT0+cmV2ZXJzZVJvdXRlKCkuY2F0Y2goZT0+dG9hc3QoZS5tZXNzYWdlKSk7ZWwoJ2Nsb3NlUHJlc2VudEJ1dHRvbicpLm9uY2xpY2s9Y2xvc2VQcmVzZW50O2VsKCdwcmV2aW91c1N0b3BCdXR0b24nKS5vbmNsaWNrPSgpPT5nb1ByZXNlbnRTdG9wKHByZXNlbnRTdG9wSW5kZXgtMSk7ZWwoJ25leHRTdG9wQnV0dG9uJykub25jbGljaz0oKT0+Z29QcmVzZW50U3RvcChwcmVzZW50U3RvcEluZGV4KzEpO2VsKCdwcmV2aW91c1Bob3RvQnV0dG9uJykub25jbGljaz0oKT0+e2NvbnN0IGE9cHJlc2VudEFzc2V0cygpO2lmKGEubGVuZ3RoKWdvUHJlc2VudFBob3RvKHByZXNlbnRQaG90b0luZGV4PDA/YS5sZW5ndGgtMTpwcmVzZW50UGhvdG9JbmRleC0xKX07ZWwoJ25leHRQaG90b0J1dHRvbicpLm9uY2xpY2s9KCk9Pntjb25zdCBhPXByZXNlbnRBc3NldHMoKTtpZihhLmxlbmd0aClnb1ByZXNlbnRQaG90byhwcmVzZW50UGhvdG9JbmRleCsxKX07ZWwoJ3BsYXlKb3VybmV5QnV0dG9uJykub25jbGljaz10b2dnbGVQbGF5fQppbml0Rm9ybXMoKTtiaW5kKCk7ZW5zdXJlTWFwKCk7c2V0TWFwU3R5bGUobWFwU3R5bGVLZXkpO2xvYWRQcm9qZWN0cygpLmNhdGNoKGU9PnRvYXN0KGUubWVzc2FnZSkpOwo8L3NjcmlwdD4KPC9ib2R5Pgo8L2h0bWw+
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








pct exec "$CTID" -- bash -lc "grep -q 'Trippy v10.2.3' /opt/trippy/frontend/index.html && grep -q 'presentMap' /opt/trippy/frontend/index.html && grep -q 'photoMarker' /opt/trippy/frontend/index.html && test -s /opt/trippy/frontend/vendor/maplibre-gl.js" >/dev/null 2>&1 || {
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
printf "${CYAN}${BOLD}v10.2.3 features${RESET}\n"
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
