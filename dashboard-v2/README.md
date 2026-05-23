# BTX Mining Cockpit (v2)

A live, animated dashboard for your BTX miner. Runs **alongside** the v1 dashboard, not as a replacement — pick whichever you prefer.

| | v1 (`../dashboard/`) | v2 (this directory) |
|---|---|---|
| Port | `:8765` | `:8766` |
| Style | Utilitarian, Chart.js line graphs | Cockpit, animated canvas + WebGL |
| Refresh | 10s | 5s poll, 60fps interpolation |
| Reads | Same `/api/snapshot` endpoint | Same `/api/snapshot` endpoint |
| Dependencies | Chart.js (CDN) | Three.js (CDN) |

Both serve the same backend data; v2 just renders it more dynamically.

## What you'll see

- **Aurora ribbon** — full-width animated gradient at the top. Wave speed and brightness scale with live hashrate. Gold flash on every new block.
- **Radial hashrate gauge** — tachometer-style with a glowing needle and pulsing halo. Auto-scales to your measured rate.
- **Post-quantum lattice** — slowly rotating 3D wireframe icosahedrons (ML-DSA / SLH-DSA visual reference). Spin speed tracks mining intensity; pulses on new blocks.
- **Network share ring** — circular progress with concentric rotating dashed rings. Log-scaled so even tiny shares are visible.
- **Live hash attempt field** — flowing particles, density tied to actual nonces/sec. Rare lucky-nonce particles flash gold.
- **Peer constellation** — your node at center, peers orbiting; connection-line brightness tied to latency; nodes twinkle.
- **Block lottery wheel** — radar-sweep dial showing position in expected-block interval (24-hour scale).
- **Live metric strip** — network hashrate, difficulty, expected BTX/day, wallet balance, blocks found, loop status — with smooth number transitions.
- **Miner log stream** — last lines from `mining-loop.log`, latest highlighted.

## Running

```bash
./start.sh
```

Then open `http://127.0.0.1:8766/`.

The script refuses to start if `:8766` is already taken (so you don't accidentally double-launch).

## Running v1 and v2 together

They're independent processes on different ports. Either order is fine:

```bash
# v1
../dashboard/start.sh &
# v2
./start.sh &
```

Stop one without affecting the other.

## How the smoothness works

The snapshot RPC underneath is the same as v1 (15s collector + on-demand fetch). To make the visuals feel live:

- Frontend polls `/api/snapshot` every **5 seconds**.
- Every numeric metric is *interpolated* toward its new target value over ~400ms (exponential ease).
- A small amount of micro-jitter (±1.5%) is added to the displayed numbers so they don't sit perfectly flat between polls. This is *visual only* — the underlying smoothed value is unjittered, and the metric strip text shows the smoothed value.
- All canvas animations run at 60fps via `requestAnimationFrame`, decoupled from snapshot polling.

## Notes

- The "lucky nonce" gold flashes in the particle field are **visual only** — ~1 in 600 particles flash gold so there's something fun to watch. They are not literal block wins. Real block wins trigger the gold flash across the whole aurora ribbon and a pulse on the lattice.
- No personal data leaves the machine. Same as v1: all rendering is local, all RPCs are to `127.0.0.1`.
