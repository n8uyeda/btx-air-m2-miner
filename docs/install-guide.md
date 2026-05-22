# Install guide

Step-by-step walkthrough of what `./install.sh` does, with explanations. If you want to run things manually instead of using the script, this guide shows you exactly which commands to run.

## Prerequisites

- macOS 14.x or later
- Apple Silicon (M1, M2, M3, or M4)
- [Homebrew](https://brew.sh)
- Xcode Command Line Tools (`xcode-select --install`)
- At least 6 GB free disk space in `$HOME`

## Step 1 — Install Homebrew dependencies

```bash
brew install cmake boost libevent sqlite pkgconf
```

| Package | Used for |
|---|---|
| cmake | The build system |
| boost | C++ libraries BTX depends on |
| libevent | The async-I/O library |
| sqlite | Descriptor wallets store keys in SQLite |
| pkgconf | Modern replacement for pkg-config |

## Step 2 — Clone BTX from upstream

```bash
mkdir -p ~/dev/btx
cd ~/dev/btx
git clone https://github.com/btxchain/btx.git .
git checkout v0.30.1   # or the latest stable tag
```

## Step 3 — Apply the two compatibility patches

The patches live in this repo at `patches/`. From the kit's directory:

```bash
cd ~/dev/btx
git apply /path/to/btx-air-m2-miner/patches/0001-metal-use-MTLCopyAllDevices.patch
git apply /path/to/btx-air-m2-miner/patches/0002-wallet-alias-structured-binding.patch
```

These patches:
1. **0001-metal-use-MTLCopyAllDevices** — Replace `MTLCreateSystemDefaultDevice()` (restricted to interactive apps on macOS 14+) with `MTLCopyAllDevices()` (works in any context). Without this, the daemon silently falls back to CPU mining.
2. **0002-wallet-alias-structured-binding** — Alias a structured binding to a regular variable so AppleClang 15 accepts the C++20 lambda capture. Without this, the wallet code doesn't compile.

See [`patches/README.md`](../patches/README.md) for the full background.

## Step 4 — Configure cmake

```bash
cd ~/dev/btx
SQLITE_PREFIX=$(brew --prefix sqlite)
cmake -B build \
    -DBTX_MATMUL_METAL_PRECOMPILE_KERNELS=OFF \
    -DENABLE_WALLET=ON \
    -DCMAKE_PREFIX_PATH="$SQLITE_PREFIX"
```

| Flag | Why |
|---|---|
| `-DBTX_MATMUL_METAL_PRECOMPILE_KERNELS=OFF` | Skip pre-compiling Metal shaders (we don't have full Xcode's `xcrun metal`). Runtime compiles inline shaders instead — slight startup cost, no functional diff. |
| `-DENABLE_WALLET=ON` | Build the wallet code. We need it for `createwallet`, `getnewaddress`, and `backupwalletbundlearchive`. |
| `-DCMAKE_PREFIX_PATH=$(brew --prefix sqlite)` | Point cmake at Homebrew's keg-only sqlite (otherwise wallet build fails). |

## Step 5 — Compile

```bash
cmake --build build -j$(sysctl -n hw.logicalcpu)
```

Takes about **30-45 minutes on a base M2**. Compiles in parallel across all your CPU cores.

You may see a linker error at the very end for `test_btx` (the unit-test binary). That's **non-fatal** — your production binaries (`btxd`, `btx-cli`, etc.) are already built by then. The installer detects this case and continues.

## Step 6 — Codesign the binaries

```bash
for bin in btxd btx-cli btx-tx btx-util btx-wallet btx-genesis \
           btx-matmul-backend-info btx-matmul-solve-bench btx-matmul-metal-bench; do
    codesign --force --deep --sign - ~/dev/btx/build/bin/$bin
done
```

macOS requires binaries to have at least an ad-hoc signature to access Metal. Without this, Metal mining falls back to CPU.

## Step 7 — Verify Metal works

```bash
~/dev/btx/build/bin/btx-matmul-backend-info --backend metal
```

Look for `"active_backend": "metal"` and `"runtime_probe_ok"` in the output. If you see `metal_unavailable_fallback_to_cpu`, see the [troubleshooting guide](troubleshooting.md#metal-mining-reports-active_backend-cpu-instead-of-metal).

## What's next

- **Wallet setup** → [`docs/wallet-setup.md`](wallet-setup.md)
- **Starting the daemon** → `./scripts/start-daemon.sh` (creates fresh `~/.btx/btx.conf` with a random RPC password)
- **Starting mining** → `./scripts/start-mining.sh <your-btx1z-address>`
- **Launching the dashboard** → `./dashboard/start.sh`
