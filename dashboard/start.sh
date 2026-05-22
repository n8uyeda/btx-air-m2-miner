#!/usr/bin/env bash
# Launch the dashboard server in background; open browser.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDFILE="$HERE/data/server.pid"
LOG="$HERE/data/server.log"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "✓ Dashboard already running (PID $(cat "$PIDFILE"))"
    echo "  Open: http://127.0.0.1:8765/"
    open http://127.0.0.1:8765/ 2>/dev/null || true
    exit 0
fi

mkdir -p "$HERE/data"
nohup python3 "$HERE/server.py" > "$LOG" 2>&1 &
echo $! > "$PIDFILE"
sleep 3

if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "✓ Dashboard started (PID $(cat "$PIDFILE"))"
    echo "  URL:  http://127.0.0.1:8765/"
    echo "  Log:  $LOG"
    echo
    echo "Opening in browser..."
    open http://127.0.0.1:8765/ 2>/dev/null || echo "  (couldn't auto-open; visit http://127.0.0.1:8765/ manually)"
    echo
    echo "Stop with: kill \$(cat $PIDFILE)"
else
    echo "✗ Dashboard failed to start. Log:"
    cat "$LOG"
    rm -f "$PIDFILE"
    exit 1
fi
