#!/usr/bin/env bash
# Stop the mining loop. Graceful — the current iteration completes before exit.

set -euo pipefail

DATADIR="${HOME}/.btx"
PIDFILE="$DATADIR/mining-loop.pid"

if [[ ! -f "$PIDFILE" ]]; then
    echo "No mining-loop.pid found. Mining loop not running."
    exit 0
fi

PID=$(cat "$PIDFILE")
if ! kill -0 "$PID" 2>/dev/null; then
    echo "Mining loop PID $PID is dead. Cleaning up stale PID file."
    rm -f "$PIDFILE"
    exit 0
fi

echo "Sending SIGTERM to mining loop (PID $PID)..."
kill -TERM "$PID"

# Wait up to 30 seconds for graceful exit
for i in {1..30}; do
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "✓ Mining loop stopped cleanly."
        rm -f "$PIDFILE"
        exit 0
    fi
    sleep 1
done

echo "Mining loop didn't exit gracefully within 30s. Sending SIGKILL."
kill -KILL "$PID" 2>/dev/null || true
rm -f "$PIDFILE"
echo "✓ Stopped."
