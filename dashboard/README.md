# Dashboard

Local browser-viewable mining dashboard. Python stdlib only (no `pip install` needed). Chart.js loaded from a CDN at first page load.

## Quick start

```bash
./dashboard/start.sh
# opens http://127.0.0.1:8765/ in your browser
```

To stop:
```bash
kill $(cat dashboard/data/server.pid)
```

## What it shows

**Top metric cards** (refreshed every 10 seconds):
- **Local Hashrate (calibrated)** — real nonces/sec from the bench tool. NOT the inflated `maxtries/sec` from the mining loop.
- **Network Hashrate** — total network from `getmininginfo`.
- **Our Share** — calibrated / network.
- **Expected BTX/day** — at current measured share.
- **Chain Tip** — current block + peer count + chain size on disk.
- **Difficulty** — current target difficulty.
- **Wallet Balance** — immature (recently mined) + mature (spendable) + pending.
- **Mining Loop** — alive / iteration count / blocks found / PID.

**Second row of cards:**
- **Mean Wait per Block** — at current share.
- **Loop rate (uncalibrated)** — the inflated number from the mining log, shown alongside for transparency. Labeled with the inflation factor.
- **Last bench** — when the calibration last ran; next run is every 10 minutes.
- **Algorithm** — matmul, with the current n/b/r parameters.

**Four time-series charts:**
- Hashrate over time (local in gold, network/10 scaled in dashed blue).
- Our share % over time.
- Difficulty over time.
- Block winners (last 20 blocks, bar chart — our address highlighted in gold when we win one).

**Two tables:**
- Recent blocks (height, coinbase address, reward, txs, time). Our blocks are highlighted with a gold row and a ★.
- Connected peers (address, BTX version, in/out direction, height).

## How the calibration works

The mining loop reports a `rate=NNNNN/s` metric calculated from `maxtries / elapsed`. This number is **wrong** — `maxtries` from `generatetoaddress` is a count of outer-loop iterations, not actual hash attempts. Each outer iteration contains a Metal GPU batch that processes many nonces in parallel. The result: the naive rate is inflated by ~80×.

The dashboard fixes this by running `btx-matmul-solve-bench --backend metal --block-height 61000` every 10 minutes. This is the project's own pure-solver microbenchmark; it measures actual nonces processed. The dashboard uses that number as the truth and shows the mining-loop's rate as a secondary "loop activity" indicator with the inflation factor labeled.

If you want to verify yourself:
```bash
~/dev/btx/build/bin/btx-matmul-solve-bench --backend metal --block-height 61000 --iterations 1 --tries 20000 | python3 -m json.tool | head -50
```
The `"nonces_per_sec": {"mean": ...}` field is the real number.

## Data files

| File | Purpose |
|---|---|
| `data/history.jsonl` | Rolling time-series, 15-sec snapshots, ~24 hour retention |
| `data/last_bench.json` | Most recent calibration result (overwritten each bench run) |
| `data/server.log` | Server stdout/stderr |
| `data/server.pid` | Server PID for clean stop |

None of these contain wallet keys or passphrases. They're safe to leave in place across reboots. `.gitignore` excludes them from version control.

## Privacy notes

- Server binds to `127.0.0.1:8765` only — never accessible from the network.
- Your payout address is **auto-discovered** from `~/.btx/mining-loop.log` (the start-mining script writes it there); the dashboard code does not hardcode any address.
- Recent-blocks data is queried in real time; no cached coinbase data persists in the dashboard's data files.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "bench: NONE YET" on the calibrated hashrate card | Wait 30-60 seconds for the first bench run after server startup. |
| Dashboard shows zero hashrate but mining is running | Check that `~/.btx/mining-loop.log` exists and has `iter ...` lines being written. |
| Charts are empty | History accumulates over time; first ~5-10 minutes will show empty charts. |
| `Address already in use` on startup | Another process is on port 8765. `lsof -i :8765` to find it, then `kill <PID>`. |
