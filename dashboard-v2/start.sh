#!/usr/bin/env bash
# BTX Mining Cockpit (v2) launcher — runs alongside v1.
#
# v1 (utilitarian, Chart.js)  :  http://127.0.0.1:8765/
# v2 (cockpit, live visuals)  :  http://127.0.0.1:8766/
#
# This script starts only v2. v1 has its own start.sh in ../dashboard/.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Port collision check — v2 lives on 8766.
if lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "[start.sh] something is already listening on :8766"
  echo "[start.sh] either it's already running (open http://127.0.0.1:8766/)"
  echo "[start.sh] or kill the other process first:  lsof -nP -iTCP:8766 -sTCP:LISTEN"
  exit 1
fi

cd "$HERE"
echo "[start.sh] launching cockpit on :8766"
echo "[start.sh] open http://127.0.0.1:8766/ in a browser"
echo "[start.sh] press ctrl-c to stop"
exec python3 server.py
