# btx-air-m2-miner

**Mine BTX on the cheapest Apple Silicon Mac.** Tested on a MacBook Air with the base M2 chip and 8 GB RAM. Includes an automated installer, a wallet-setup walkthrough, and a local dashboard that shows real-time mining metrics with calibrated (not inflated) hashrate numbers.

This is the kit I wish I'd had when I started. If you've ever wondered *"can I actually mine on a normal laptop?"* — read on. The answer is yes, with the right setup and honest expectations.

---

## What is BTX?

[BTX](https://btx.dev) is a post-quantum, AI-infrastructure-friendly blockchain — a Bitcoin Knots v29.2 derivative with a matrix-multiplication proof-of-work, ML-DSA-44 + SLH-DSA-SHAKE-128s signatures from genesis, and a shielded transaction pool. Mainnet launched **2026-03-19.** Source: [github.com/btxchain/btx](https://github.com/btxchain/btx).

This repo is **not affiliated with the BTX project.** It's a third-party setup kit for Apple Silicon Macs. See [`SECURITY.md`](SECURITY.md) for risk warnings and attribution.

---

## What you actually get out of this

Honest expectations on a base M2 Air (8 GB RAM), with all current network conditions (May 2026):

| Metric | Realistic value |
|---|---|
| Local hashrate (Metal backend) | **~1,000 nonces/sec** |
| Network total hashrate | ~900,000 nonces/sec |
| Your network share | **~0.11%** |
| Expected blocks per day | **~1 block/day** |
| Mean wait between blocks | **~22 hours** |
| Coinbase reward per block | 20 BTX |
| Expected BTX per day | **~20 BTX/day** |
| Sustained electricity at $0.16/kWh | **~$2-9/month** |
| Disk space (for the chain) | **~50 MB** today, grows over time |
| Build time (one-time) | ~30-45 minutes |
| Setup time (after build) | ~15-30 minutes interactive (wallet) |

These numbers are **measured on real hardware**, not extrapolated. The dashboard in this repo recalculates them every 10 minutes by running the project's own bench tool, so you'll see *your* numbers, not mine.

---

## Quickstart (the fast path)

> **Prerequisites:** macOS 14.x or later, Apple Silicon (M1/M2/M3/M4 — designed for M2 base), Homebrew installed, ~5 GB free disk for the build, an external USB drive for the wallet backup.

```bash
# 1. Clone this repo
git clone https://github.com/n8uyeda/btx-air-m2-miner.git
cd btx-air-m2-miner

# 2. Run the installer (Homebrew deps + clone BTX + patch + build + codesign)
./install.sh

# 3. Set up your wallet (interactive — passphrase will be asked, never echoed)
./scripts/wallet-setup.sh

# 4. Start the daemon (chain sync takes 4-8 hours first time)
./scripts/start-daemon.sh

# 5. Once synced (the script tells you), start mining
./scripts/start-mining.sh <your-btx1z-payout-address>

# 6. In another terminal, launch the dashboard
./dashboard/start.sh
# → opens http://127.0.0.1:8765/ in your browser
```

That's it. The longest part is the build (~30 min) and the initial chain sync (~4-8 hours, runs in the background).

---

## Full guide

| Topic | Doc |
|---|---|
| **Step-by-step install with explanations** | [`docs/install-guide.md`](docs/install-guide.md) |
| **Wallet creation + encrypted backup + test-restore** | [`docs/wallet-setup.md`](docs/wallet-setup.md) |
| **The honest hashrate / yield math** | [`docs/expectations.md`](docs/expectations.md) |
| **Troubleshooting (Metal-CLI bug, AppleClang 15 wallet bug, etc.)** | [`docs/troubleshooting.md`](docs/troubleshooting.md) |
| **Dashboard internals** | [`dashboard/README.md`](dashboard/README.md) |
| **Why the patches exist + how to remove them once upstream merges** | [`patches/README.md`](patches/README.md) |

---

## What this kit handles for you

Things that took me days of debugging to figure out, baked into the installer + scripts:

1. **The Metal-CLI bug.** `MTLCreateSystemDefaultDevice()` doesn't work from CLI/daemon contexts on macOS 14+. Apple restricts it to interactive apps. BTX's three Metal modules use this API by default, so the daemon silently falls back to CPU mining (orders of magnitude slower). The kit applies a 3-file patch using `MTLCopyAllDevices()` instead. [Upstream PR pending — see `patches/README.md`.]

2. **The AppleClang 15 wallet build bug.** `src/wallet/shielded_wallet.cpp` uses a C++20 structured-binding capture in a lambda that AppleClang 15 (shipped with macOS 14 Command Line Tools) rejects, even though newer clang accepts it. Kit applies a 5-line alias patch.

3. **The missing `xcrun metal` problem.** Full Xcode (~15 GB) ships the Metal shader compiler; Command Line Tools alone does not. Kit configures cmake with `-DBTX_MATMUL_METAL_PRECOMPILE_KERNELS=OFF` so the build skips the precompile step and uses runtime shader compilation instead. Slight startup-time cost, no functional difference.

4. **The "where does sqlite live" problem.** Homebrew's sqlite is keg-only; cmake needs an explicit `-DCMAKE_PREFIX_PATH=$(brew --prefix sqlite)`. Installer handles it.

5. **Codesigning.** macOS rejects unsigned binaries from certain API calls. Installer ad-hoc-signs every binary post-build.

6. **The `maxtries` calibration trap.** `getblocktemplate`'s `maxtries` parameter is **not** 1:1 with hash attempts — it counts outer loop iterations. Using it naively makes your hashrate look ~80× higher than it actually is. Dashboard self-calibrates with the project's own bench tool to show real numbers.

7. **The canonical wallet backup workflow.** `listdescriptors true` exports descriptor structure but NOT the post-quantum (ML-DSA-44) signing keys — you get a backup that looks valid but can't actually spend coins. The correct RPC is `backupwalletbundlearchive`, which produces a complete encrypted bundle. The wallet-setup script walks you through it, including the test-restore step that verifies your backup is real.

8. **The pruning + shielded-state recovery trap.** Discovered 2026-05-23. If you enable pruning and the daemon does a clean shutdown that catches the shielded subsystem mid-write, the next startup tries to rebuild shielded state from chain — and needs old blocks that pruning has deleted. The daemon then crashes on every restart attempt and the only recovery is a full re-sync. Kit defaults to **`prune=4096` commented out** so the rebuild path always has data. Costs you ~6-10 GB of extra disk going forward and prevents the trap entirely.

9. **GPU tuning for M2 (and likely M1) base hardware.** Measured 2026-05-23: setting `BTX_MATMUL_SOLVER_THREADS=2` gives roughly **2× the nonces/sec** of the daemon's default of 1, on M2 base. The GPU is the bottleneck — more solver threads don't help and bigger batch sizes actually hurt (smaller unified-memory pool). The kit's `start-daemon.sh` sets this automatically; override by exporting `BTX_MATMUL_SOLVER_THREADS=N` before launch if you're on beefier hardware (M-series Pro/Max/Ultra → try 4 or 6).

---

## Repository structure

```
btx-air-m2-miner/
├── README.md                    you are here
├── LICENSE                      MIT
├── SECURITY.md                  risks, threat model, attribution, no-affiliation
├── install.sh                   one-command installer
├── docs/
│   ├── install-guide.md         step-by-step with explanations
│   ├── wallet-setup.md          encrypted wallet + backup + verify
│   ├── expectations.md          the honest hashrate / yield numbers
│   └── troubleshooting.md       known issues + fixes
├── patches/
│   ├── README.md                what these are, why, when to remove
│   ├── 0001-metal-use-MTLCopyAllDevices.patch
│   └── 0002-wallet-alias-structured-binding.patch
├── scripts/
│   ├── wallet-setup.sh          interactive wallet creation + backup
│   ├── start-daemon.sh          launches btxd with proper datadir
│   ├── start-mining.sh          the mining loop (with your payout address)
│   └── stop-mining.sh           clean stop
└── dashboard/
    ├── README.md                dashboard internals
    ├── server.py                Python stdlib HTTP server
    ├── index.html               single-page Chart.js dashboard
    └── start.sh                 launcher
```

---

## Limits + what this kit does NOT do

- **Does not include the BTX source code.** Cloned from upstream during install.
- **Does not host or distribute binaries.** Everything is built from source on your machine.
- **Does not include a wallet for you.** Generates fresh keys on your machine; they never leave it.
- **Does not include a payout address.** You generate your own during wallet setup.
- **Does not handle Pool mining.** No public BTX pool exists as of May 2026. Solo mining only.
- **Does not work on Intel Macs.** Apple Silicon only (M1, M2, M3, M4).
- **Does not provide cloud-mining options.** The CUDA backend in BTX is currently scaffolded/disabled; renting NVIDIA GPUs doesn't help. Stick to M-series Macs.

---

## License

[MIT](LICENSE). Fork, modify, redistribute freely. Attribution appreciated but not required.

---

## Acknowledgments

- The **BTX project** ([btx.dev](https://btx.dev), [github.com/btxchain/btx](https://github.com/btxchain/btx)) — for shipping a real, technically credible chain. Specifically: Numair Faraz (founder), Long Nguyen, qubixt (internal audit + vulnerability tracking).
- **Bitcoin Knots / Bitcoin Core** — the upstream foundation BTX derives from.
- The **MatMul PoW** paper: *"Proofs of Useful Work from Arbitrary Matrix Multiplication"* (Komargodski, Schen, Weinstein — [arXiv:2504.09971](https://arxiv.org/abs/2504.09971)).

---

Built by **[@n8uyeda](https://github.com/n8uyeda)**. Issues, PRs, and "this didn't work on my Mac" reports welcome.
