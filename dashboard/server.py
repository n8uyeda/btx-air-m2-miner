#!/usr/bin/env python3
"""
BTX Mining Dashboard — local HTTP server, Python stdlib only.

Polls btx-cli for live data, maintains a rolling JSONL history, and serves
a single-page dashboard at http://127.0.0.1:8765/ with Chart.js graphs.

The dashboard self-calibrates by running the project's bench tool periodically,
so the displayed hashrate / share / expected-yield numbers reflect REAL mining
throughput — not the inflated maxtries-based counter that `generatetoaddress`
exposes.

Your payout address is auto-discovered from ~/.btx/mining-loop.log on first
read. No address is hardcoded.

Usage:
    python3 dashboard/server.py
    open http://127.0.0.1:8765/
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

# --- config ----------------------------------------------------------------
BTX_CLI = os.path.expanduser("~/dev/btx/build/bin/btx-cli")
BTX_BENCH = os.path.expanduser("~/dev/btx/build/bin/btx-matmul-solve-bench")
DATADIR = os.path.expanduser("~/.btx")
MINING_LOG = os.path.expanduser("~/.btx/mining-loop.log")
MINING_PID_FILE = os.path.expanduser("~/.btx/mining-loop.pid")

# Dashboard data lives next to this script (under the repo) — NOT in ~/.btx
HERE = Path(__file__).parent.resolve()
DATA_DIR = HERE / "data"
HISTORY_FILE = DATA_DIR / "history.jsonl"
BENCH_FILE = DATA_DIR / "last_bench.json"

PORT = 8765
HOST = "127.0.0.1"
COLLECT_INTERVAL = 15  # seconds between snapshots
HISTORY_MAX_ENTRIES = 5760  # ~24 hours at 15-sec intervals
BENCH_INTERVAL_SEC = 600  # re-benchmark every 10 minutes


# --- helpers ---------------------------------------------------------------
def discover_payout_address() -> str | None:
    """Read ~/.btx/mining-loop.log and extract the user's payout address.
    Returns the address string, or None if not found.

    Looks for the 'payout=<btx1z...>' token written by start-mining.sh.
    """
    if not Path(MINING_LOG).exists():
        return None
    try:
        for line in Path(MINING_LOG).read_text().splitlines():
            m = re.search(r"payout=(btx1z[a-z0-9]+)", line)
            if m:
                return m.group(1)
    except Exception:
        pass
    return None


def cli(*args, wallet=None, timeout=8):
    """Invoke btx-cli; return parsed JSON or raw string. Returns None on error."""
    cmd = [BTX_CLI, f"-datadir={DATADIR}"]
    if wallet:
        cmd.append(f"-rpcwallet={wallet}")
    cmd.extend(args)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if result.returncode != 0:
            return None
        out = result.stdout.strip()
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            return out
    except Exception:
        return None


def parse_mining_log_tail(n_lines: int = 300) -> dict:
    """Parse the last N lines of the mining loop log for headline stats."""
    stats = {
        "loop_alive": False,
        "iters": 0,
        "total_tries": 0,
        "blocks_found": 0,
        "elapsed_sec": 0,
        "rate_per_sec": 0,
        "rate_history": [],
        "blocks_history": [],
        "log_lines": [],
    }
    pid_file = Path(MINING_PID_FILE)
    if pid_file.exists():
        try:
            pid = int(pid_file.read_text().strip())
            os.kill(pid, 0)
            stats["loop_alive"] = True
            stats["pid"] = pid
        except (ProcessLookupError, ValueError):
            pass

    if not Path(MINING_LOG).exists():
        return stats

    lines = Path(MINING_LOG).read_text().splitlines()
    stats["log_lines"] = lines[-n_lines:]

    iter_re = re.compile(
        r"\[(\d{2}:\d{2}:\d{2})\] iter (\d+): tries=(\d+) blocks=(\d+) elapsed=(\d+)s rate=(\d+)/s"
    )
    block_re = re.compile(r"\[(\d{2}:\d{2}:\d{2})\] iter (\d+): . BLOCK FOUND! hash=\"?([a-f0-9]+)")

    for ln in lines:
        m = iter_re.search(ln)
        if m:
            tm, iters, tries, blocks, elapsed, rate = m.groups()
            stats["iters"] = int(iters)
            stats["total_tries"] = int(tries)
            stats["blocks_found"] = int(blocks)
            stats["elapsed_sec"] = int(elapsed)
            stats["rate_per_sec"] = int(rate)
            stats["rate_history"].append({"t": tm, "rate": int(rate)})
        m = block_re.search(ln)
        if m:
            tm, iters, h = m.groups()
            stats["blocks_history"].append({"t": tm, "iter": int(iters), "hash": h[:16] + "..."})

    stats["rate_history"] = stats["rate_history"][-100:]
    return stats


def snapshot_recent_blocks(n: int = 20, payout_addr: str | None = None) -> list:
    """Pull the last N blocks; flag which were ours (if we know our address)."""
    height = cli("getblockcount")
    if height is None:
        return []
    blocks = []
    for i in range(n):
        h = height - i
        block_hash = cli("getblockhash", str(h))
        if block_hash is None:
            continue
        b = cli("getblock", block_hash, "2", timeout=4)
        if not isinstance(b, dict):
            continue
        cb = b.get("tx", [{}])[0]
        cb_out = cb.get("vout", [{}])[0]
        cb_addr = cb_out.get("scriptPubKey", {}).get("address", "?")
        cb_value = cb_out.get("value", 0)
        blocks.append({
            "height": h,
            "hash": b.get("hash", "?"),
            "time": b.get("time"),
            "n_txs": len(b.get("tx", [])),
            "coinbase_addr": cb_addr,
            "coinbase_value": cb_value,
            "is_ours": payout_addr is not None and cb_addr == payout_addr,
            "size": b.get("size", 0),
        })
    return blocks


def measure_real_hashrate() -> dict | None:
    """Run btx-matmul-solve-bench to get a CALIBRATED nonces/sec measurement.

    The mining loop's 'maxtries/sec' counter is NOT 1:1 with hash attempts —
    `maxtries` from `generatetoaddress` counts outer iterations, each containing
    a Metal batch dispatch. This bench tool measures actual nonces processed.

    Returns dict with 'nonces_per_sec', 'mean_ms', 'measured_at'; or None on error.
    """
    if not Path(BTX_BENCH).exists():
        return None
    try:
        # --solver-threads 2 matches the env-var tuning baked into start-daemon.sh
        # (BTX_MATMUL_SOLVER_THREADS=2 for M2 base). Without this flag, the bench
        # would default to solver-threads=1 and report the OLD baseline rate, making
        # the dashboard cards show ~half the true production hashrate.
        result = subprocess.run(
            [BTX_BENCH, "--backend", "metal", "--block-height", "61000",
             "--iterations", "1", "--tries", "20000",
             "--solver-threads", "2"],
            capture_output=True, text=True, timeout=90)
        if result.returncode != 0:
            return None
        bench = json.loads(result.stdout)
        rate = bench.get("nonces_per_sec", {}).get("mean")
        elapsed_s = bench.get("elapsed_s", {}).get("mean")
        if rate is None:
            return None
        data = {
            "nonces_per_sec": rate,
            "mean_ms": (elapsed_s * 1000) if elapsed_s else None,
            "measured_at": time.time(),
        }
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        BENCH_FILE.write_text(json.dumps(data))
        return data
    except Exception as e:
        print(f"[bench error] {e}")
    return None


def read_last_bench() -> dict | None:
    if not BENCH_FILE.exists():
        return None
    try:
        return json.loads(BENCH_FILE.read_text())
    except Exception:
        return None


def collect_snapshot() -> dict:
    """Collect a single snapshot of all dashboard metrics."""
    now = time.time()
    snap: dict = {"timestamp": now, "isotime": datetime.fromtimestamp(now).isoformat()}
    payout = discover_payout_address()
    snap["payout_address"] = payout  # may be None if mining loop hasn't started

    chain = cli("getblockchaininfo") or {}
    snap["chain"] = {
        "blocks": chain.get("blocks"),
        "headers": chain.get("headers"),
        "verificationprogress": chain.get("verificationprogress"),
        "ibd": chain.get("initialblockdownload"),
        "size_on_disk": chain.get("size_on_disk"),
        "bestblockhash": chain.get("bestblockhash"),
        "difficulty": chain.get("difficulty"),
    }

    mining = cli("getmininginfo") or {}
    snap["mining"] = {
        "difficulty": mining.get("difficulty"),
        "networkhashps": mining.get("networkhashps"),
        "algorithm": mining.get("algorithm"),
        "matmul_n": mining.get("matmul_n"),
        "matmul_b": mining.get("matmul_b"),
        "matmul_r": mining.get("matmul_r"),
        "pooledtx": mining.get("pooledtx"),
    }

    netinfo = cli("getnetworkinfo") or {}
    peers = cli("getpeerinfo") or []
    snap["network"] = {
        "version": netinfo.get("version"),
        "subversion": netinfo.get("subversion"),
        "protocol": netinfo.get("protocolversion"),
        "connections": netinfo.get("connections"),
        "in": netinfo.get("connections_in"),
        "out": netinfo.get("connections_out"),
    }
    snap["peers"] = [
        {
            "addr": p.get("addr", ""),
            "subver": p.get("subver", ""),
            "inbound": p.get("inbound", False),
            "startingheight": p.get("startingheight"),
            "bytessent": p.get("bytessent", 0),
            "bytesrecv": p.get("bytesrecv", 0),
            "latency": p.get("pingtime", None),
        }
        for p in peers if isinstance(p, dict)
    ]

    balances = cli("getbalances", wallet="miner") or {}
    mine = balances.get("mine", {})
    snap["wallet"] = {
        "loaded": balances != {},
        "immature": mine.get("immature", 0),
        "trusted": mine.get("trusted", 0),
        "untrusted_pending": mine.get("untrusted_pending", 0),
        "total": (mine.get("immature", 0) + mine.get("trusted", 0) + mine.get("untrusted_pending", 0)),
    }

    snap["miner"] = parse_mining_log_tail()

    bench = read_last_bench()
    snap["bench"] = bench

    if bench and bench.get("nonces_per_sec"):
        effective_rate = bench["nonces_per_sec"]
        snap["effective_rate_source"] = "bench"
    elif snap["miner"]["rate_per_sec"]:
        effective_rate = snap["miner"]["rate_per_sec"]
        snap["effective_rate_source"] = "mining_loop_uncalibrated"
    else:
        effective_rate = None
        snap["effective_rate_source"] = "none"
    snap["effective_hashrate"] = effective_rate

    if effective_rate and snap["mining"].get("networkhashps"):
        snap["share_pct"] = (effective_rate / snap["mining"]["networkhashps"]) * 100
    else:
        snap["share_pct"] = None

    if snap["share_pct"]:
        snap["expected_blocks_per_day"] = round((snap["share_pct"] / 100) * 960, 3)
        snap["expected_btx_per_day"] = round(snap["expected_blocks_per_day"] * 20, 2)
        if snap["expected_blocks_per_day"] > 0:
            snap["expected_hours_per_block"] = round(24 / snap["expected_blocks_per_day"], 2)
        else:
            snap["expected_hours_per_block"] = None
    else:
        snap["expected_blocks_per_day"] = None
        snap["expected_btx_per_day"] = None
        snap["expected_hours_per_block"] = None

    return snap


def append_history(snapshot: dict) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    row = {
        "t": snapshot["timestamp"],
        "rate": snapshot["effective_hashrate"],
        "loop_rate": snapshot["miner"]["rate_per_sec"],
        "net_hps": snapshot["mining"]["networkhashps"],
        "share_pct": snapshot["share_pct"],
        "blocks": snapshot["chain"]["blocks"],
        "difficulty": snapshot["chain"]["difficulty"],
        "peers": snapshot["network"]["connections"],
        "wallet_total": snapshot["wallet"]["total"],
        "blocks_found_local": snapshot["miner"]["blocks_found"],
    }
    with HISTORY_FILE.open("a") as f:
        f.write(json.dumps(row) + "\n")

    # Truncate periodically (cheap; only does work when file is over the limit)
    lines = HISTORY_FILE.read_text().splitlines()
    if len(lines) > HISTORY_MAX_ENTRIES:
        HISTORY_FILE.write_text("\n".join(lines[-HISTORY_MAX_ENTRIES:]) + "\n")


def read_history() -> list:
    if not HISTORY_FILE.exists():
        return []
    rows = []
    for line in HISTORY_FILE.read_text().splitlines():
        if line.strip():
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


# --- background threads ----------------------------------------------------
def collector_loop():
    while True:
        try:
            snap = collect_snapshot()
            append_history(snap)
        except Exception as e:
            print(f"[collector error] {e}")
        time.sleep(COLLECT_INTERVAL)


def _mining_loop_alive() -> bool:
    """True if the mining-loop process is currently running."""
    pid_file = os.path.expanduser("~/.btx/mining-loop.pid")
    if not os.path.exists(pid_file):
        return False
    try:
        pid = int(open(pid_file).read().strip())
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


def bench_loop():
    """Periodic calibration bench.

    Skip while the mining loop is alive — bench and mining share the GPU, and
    a co-running bench shows ~30% of the real production rate, which would
    mis-represent the daemon's actual throughput in the dashboard cards. Keep
    the last clean cached bench (run while mining was paused) and use that.
    """
    time.sleep(10)
    while True:
        try:
            if _mining_loop_alive():
                pass  # keep cached unloaded measurement
            else:
                measure_real_hashrate()
        except Exception as e:
            print(f"[bench loop error] {e}")
        time.sleep(BENCH_INTERVAL_SEC)


# --- HTTP handler ----------------------------------------------------------
class DashboardHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # silence default access logs

    def _send_json(self, payload, status=200):
        body = json.dumps(payload, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html):
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index"):
            html_path = HERE / "index.html"
            if html_path.exists():
                self._send_html(html_path.read_text())
                return
            self._send_html("<h1>index.html missing</h1>")
            return
        if self.path == "/api/snapshot":
            payout = discover_payout_address()
            snap = collect_snapshot()
            snap["recent_blocks"] = snapshot_recent_blocks(20, payout)
            self._send_json(snap)
            return
        if self.path == "/api/history":
            self._send_json(read_history())
            return
        if self.path == "/api/recent-blocks":
            self._send_json(snapshot_recent_blocks(20, discover_payout_address()))
            return
        self.send_response(404)
        self.end_headers()


# --- main ------------------------------------------------------------------
if __name__ == "__main__":
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    threading.Thread(target=collector_loop, daemon=True).start()
    threading.Thread(target=bench_loop, daemon=True).start()
    print(f"BTX Mining Dashboard")
    print(f"  Open in browser:  http://{HOST}:{PORT}/")
    print(f"  Data directory:   {DATA_DIR}")
    print(f"  Mining log:       {MINING_LOG}")
    print(f"  Press Ctrl-C to stop")
    httpd = HTTPServer((HOST, PORT), DashboardHandler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
