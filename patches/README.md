# Patches

Two patches applied to BTX source code at build time. These are **compatibility fixes for the macOS 14.x + Command Line Tools 15.x + AppleClang 15 toolchain combination**. They are not consensus, cryptography, or networking changes.

| Patch | Lines changed | Why |
|---|---|---|
| `0001-metal-use-MTLCopyAllDevices.patch` | +18 / -6 | `MTLCreateSystemDefaultDevice()` is restricted by macOS 14+ to interactive apps. From CLI / daemon contexts (which is how `btxd` runs), it returns `nil` with the system log: *"Use of MTLCreateSystemDefaultDevice is not supported for non-interactive (commandline or daemon) apps. Use MTLCopyAllDevices(WithObserver) instead."* The patch replaces the API call in all three Metal modules (`matmul_accel.mm`, `oracle_accel.mm`, `nonce_accel.mm`) with `MTLCopyAllDevices()`, picking the first available device. This is exactly Apple's documented recommendation for non-interactive contexts. |
| `0002-wallet-alias-structured-binding.patch` | +5 / -1 | AppleClang 15 (`clang-1500.3.9.4`) shipped with macOS 14 Command Line Tools rejects C++20 structured-binding captures in lambdas under strict mode. The `search` lambda in `src/wallet/shielded_wallet.cpp` captures `group_notes` from a structured binding in the enclosing for-each loop. The patch aliases the structured binding to a regular variable; the inner lambda then captures the alias, which is unambiguously permitted. Newer clang versions (16+) accept the original code without the alias. |

## Why these aren't upstream yet

Both patches are slated for upstream submission to <https://github.com/btxchain/btx>. **When upstream merges them, this directory becomes empty and the installer skips patch application.** The `install.sh` script handles all three states:

1. **Patch applies cleanly** (upstream has not merged) → apply, proceed
2. **Patch applies in reverse cleanly** (upstream has merged, source already has the fix) → skip silently
3. **Patch doesn't apply** (upstream has applied a different fix) → warn, continue (build may still succeed)

To check if upstream has merged a patch:
```bash
cd ~/dev/btx
grep -l "MTLCopyAllDevices" src/metal/*.mm
# If you see all three .mm files in the output, Metal patch is upstream.

grep -B 1 -A 1 "alias structured binding" src/wallet/shielded_wallet.cpp
# If you see the alias comment, wallet patch is upstream.
```

If you see both, you can delete this `patches/` directory entirely.

## How to apply manually (if you're not using `install.sh`)

```bash
cd ~/dev/btx
git apply /path/to/btx-air-m2-miner/patches/0001-metal-use-MTLCopyAllDevices.patch
git apply /path/to/btx-air-m2-miner/patches/0002-wallet-alias-structured-binding.patch
```

## How to remove patches (if you want to test without them)

```bash
cd ~/dev/btx
git stash      # save any uncommitted changes
git checkout v0.30.1 -- src/metal/ src/wallet/   # revert patched files
```

Then rebuild. Mining will fall back to CPU (Metal API issue), and wallet support won't be available (compile error). This is mostly useful if you're submitting your own patches and want a clean baseline.

## Provenance

The patches were originally developed during a hands-on diligence project on a base M2 MacBook Air running macOS 14.2.1 (later updated to 14.8.7). The Metal-CLI issue was diagnosed via `log stream --predicate 'process == "btx-matmul-backend-info"' --info` which surfaced Apple's explicit error message about `MTLCreateSystemDefaultDevice` being non-interactive-only. The wallet patch was diagnosed via standard `make` output during the build.

Both patches are tested end-to-end on:
- macOS 14.8.7, AppleClang 15.0.0.15000309, Apple Silicon M2 base, 8 GB RAM

They have NOT been tested on:
- macOS 13.x or earlier
- Intel Macs
- M3 / M4 (likely fine but not verified)
- Full Xcode-installed systems (likely fine but not verified)

Report broken builds at <https://github.com/n8uyeda/btx-air-m2-miner/issues>.
