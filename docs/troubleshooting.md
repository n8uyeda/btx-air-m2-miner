# Troubleshooting

Problems you may hit on a base M2 Air and how to fix them. Roughly ordered by the install / setup / mining phase.

## Install phase

### `xcrun: error: unable to find utility "metal"`

**Symptom:** During `./install.sh`, the build fails near 1% with this error.

**Cause:** You have Command Line Tools installed but not full Xcode. The Metal shader compiler (`metal`) ships only with full Xcode.

**Fix:** The installer already passes `-DBTX_MATMUL_METAL_PRECOMPILE_KERNELS=OFF` to avoid this. If you somehow see it, check that `cmake` is being called with that flag. The runtime falls back to inline-source Metal compilation, which is slightly slower at startup but fine. If you want the precompiled path, install Xcode from the App Store (~15 GB).

### `Wallet functionality requested but no BDB or SQLite support available`

**Symptom:** cmake configure fails with this error during step 5/7 of `install.sh`.

**Cause:** Homebrew's `sqlite` is "keg-only" — it doesn't symlink to `/usr/local`, so cmake can't find it via the standard search paths.

**Fix:** The installer passes `-DCMAKE_PREFIX_PATH=$(brew --prefix sqlite)`. If you see this error anyway, verify Homebrew sqlite is installed (`brew list --versions sqlite`).

### `error: reference to local binding 'group_notes' declared in enclosing function`

**Symptom:** Build fails around 53% in `src/wallet/shielded_wallet.cpp:600,606,607`.

**Cause:** AppleClang 15 (shipped with macOS 14 Command Line Tools) is stricter than newer clang versions about C++20 structured-binding captures in lambdas.

**Fix:** The installer applies `patches/0002-wallet-alias-structured-binding.patch` which aliases the structured binding to a regular variable. If you see this error, the patch failed to apply. Try:
```bash
cd ~/dev/btx
git stash  # discard local changes
git checkout v0.30.1
cd -
./install.sh
```

### Build linker error in `test_btx`

**Symptom:** Near 100% of the build, `test_btx` fails to link with "undefined symbols for wallet:: ...".

**Cause:** When `ENABLE_WALLET=ON` is set but the wallet code has a non-mergeable conflict (rare), the unit-test binary fails to link.

**Fix:** This is non-fatal. Your production binaries (`btxd`, `btx-cli`, etc.) are already built. The installer detects this and continues. The `test_btx` binary is for unit tests, not for actual mining.

## Daemon phase

### `btxd` won't start, "lock file" error

**Symptom:** Running `./scripts/start-daemon.sh` produces `Cannot obtain a lock on data directory`.

**Cause:** A previous `btxd` process didn't shut down cleanly and left a stale lock.

**Fix:**
```bash
rm ~/.btx/.lock
./scripts/start-daemon.sh
```

### `btxd` starts but stays at 0 peers

**Symptom:** After 5+ minutes, `btx-cli getconnectioncount` returns 0.

**Cause:** Could be:
- macOS firewall blocking outbound on port 19335
- The seed nodes in `~/.btx/btx.conf` are temporarily unreachable
- Local network restrictions

**Fix:**
```bash
# Test seed reachability directly
nc -z -w 5 node.btx.tools 19335 && echo "reachable"
nc -z -w 5 146.190.179.86 19335 && echo "reachable"
nc -z -w 5 164.90.246.229 19335 && echo "reachable"
```
If none are reachable, your network blocks outbound on 19335. Try from a different network. If at least one is reachable, restart the daemon:
```bash
~/dev/btx/build/bin/btx-cli -datadir=$HOME/.btx stop
sleep 3
./scripts/start-daemon.sh
```

### Sync stuck at the same block height for 10+ minutes

**Symptom:** `getblockchaininfo` shows the same `blocks` number for an extended period.

**Cause:** Could be a slow peer, a chain reorg, or a stalled connection.

**Fix:**
```bash
# See what peers we have
~/dev/btx/build/bin/btx-cli -datadir=$HOME/.btx getpeerinfo | grep '"addr"' | head
# If stuck, restart the daemon — it'll find better peers
~/dev/btx/build/bin/btx-cli -datadir=$HOME/.btx stop
sleep 5
./scripts/start-daemon.sh
```

## Wallet phase

### "Error: Could not connect to the server" during wallet-setup.sh

**Symptom:** Wallet setup fails because the daemon isn't reachable.

**Fix:** Make sure `btxd` is running:
```bash
~/dev/btx/build/bin/btx-cli -datadir=$HOME/.btx getblockchaininfo
```
If you get an error, run `./scripts/start-daemon.sh` and wait 30 seconds.

### "Error: The wallet passphrase entered was incorrect"

**Symptom:** `walletpassphrase` rejects your passphrase.

**Cause:** Typo, or pasted from somewhere that injected formatting (smart quotes, leading whitespace, etc.).

**Fix:** Type the passphrase manually from your paper backup. Use a simple text editor (TextEdit in plain-text mode) to compose passphrases before pasting into Terminal — rich text apps insert non-printable characters.

### `restorewalletbundlearchive` fails with "Wrong type passed: Position 4 (load_on_startup): JSON value of type string is not of expected type bool"

**Symptom:** Test-restore step in wallet-setup fails with this error.

**Cause:** Argument-parsing quirk in the `-stdinbundlepassphrase` flag — passing an empty `""` placeholder for the passphrase position confuses argument-shifting.

**Fix:** This is handled in the bundled `scripts/wallet-setup.sh`. If you're calling restorewalletbundlearchive manually, omit the empty placeholder:
```bash
btx-cli -stdinbundlepassphrase restorewalletbundlearchive "wallet-name" "/path/to/archive.tar.zst"
```
(No trailing `""`.)

## Mining phase

### `getaddressinfo` shows `"solvable": false` on my own address

**Symptom:** Even though `ismine` is `true`, `solvable` is `false`.

**Cause:** Normal for BTX P2MR addresses. The standard descriptor solver doesn't know about ML-DSA-44 post-quantum signatures. It's reporting that it can't "solve" (construct a spending transaction template for) the address from the descriptor alone.

**Fix:** None needed. Mining and spending both still work; `solvable: false` is a UX quirk in the descriptor solver's reporting, not a real problem.

### Metal mining reports `"active_backend": "cpu"` instead of `"metal"`

**Symptom:** `btx-matmul-backend-info --backend metal` shows `"selection_reason": "metal_unavailable_fallback_to_cpu"`.

**Causes (in priority order):**

1. **Codesigning got invalidated** — macOS sometimes invalidates ad-hoc signatures after updates. Re-sign:
   ```bash
   for bin in ~/dev/btx/build/bin/btxd ~/dev/btx/build/bin/btx-cli \
              ~/dev/btx/build/bin/btx-matmul-backend-info \
              ~/dev/btx/build/bin/btx-matmul-solve-bench \
              ~/dev/btx/build/bin/btx-wallet ~/dev/btx/build/bin/btx-genesis; do
     codesign --force --deep --sign - "$bin"
   done
   ```

2. **The Metal patch didn't apply** — verify with:
   ```bash
   grep -l "MTLCopyAllDevices" ~/dev/btx/src/metal/*.mm
   ```
   You should see all three `.mm` files listed. If not, re-run `./install.sh`.

3. **macOS version mismatch** — the kit was tested on macOS 14.8.7. Older 14.x versions might have additional Metal-CLI restrictions. Update macOS via System Settings → Software Update.

### Mining loop reports `rate=80000/s` but I have no blocks after many hours

**Symptom:** The mining log shows a high rate, but no blocks materialize.

**Cause:** The `maxtries`-based rate is inflated by ~80×. Your real hashrate is closer to 1,000 nonces/sec.

**Fix:** The dashboard handles this. Open it (`./dashboard/start.sh`) and look at the "Local Hashrate (calibrated)" card — that's the real number. Expected wait per block at ~1,000 nonces/sec on a 900k network = ~22 hours. Zero blocks in 22 hours is the literal median outcome.

### Laptop fans loud, getting hot

**Symptom:** Sustained mining causes fan noise and warm bottom case.

**Cause:** Normal. Mining = GPU at near-100% load = real heat output.

**Fix:**
- **Plug in to power** (running on battery makes thermals worse because the chip throttles more aggressively).
- Use a hard, flat surface (not a bed or couch) for airflow.
- Don't run other GPU-heavy apps simultaneously.
- Consider a cooling pad / external fan for sustained 24/7 mining.
- Take periodic breaks (run `./scripts/stop-mining.sh`, wait 30 min, restart) if temps concern you.

### Mining loop process disappears

**Symptom:** `cat ~/.btx/mining-loop.pid` references a non-existent process.

**Cause:** Something killed it — could be the kernel under memory pressure, a sleep/wake cycle, or an unhandled bash error.

**Fix:**
```bash
rm ~/.btx/mining-loop.pid  # remove stale PID file
./scripts/start-mining.sh <your-address>
```

## Dashboard phase

### "bench: NONE YET" on the calibrated hashrate card

**Symptom:** Dashboard shows `(calibrating…)` instead of a hashrate.

**Cause:** The first bench run takes ~30 seconds and runs 10 seconds after server startup.

**Fix:** Wait ~40 seconds after starting the dashboard. If still missing after 2 minutes, check `dashboard/data/server.log` for errors.

### Dashboard charts are empty

**Symptom:** Cards show numbers but the time-series charts are blank.

**Cause:** Charts plot historical data. First ~5-10 minutes have no history yet.

**Fix:** Wait. History accumulates in `dashboard/data/history.jsonl`.

### Port 8765 already in use

**Symptom:** Dashboard fails to start with "Address already in use".

**Fix:**
```bash
lsof -i :8765  # find what's using it
# Either kill that process, or edit dashboard/server.py PORT = ... to a different port
```

## Still stuck?

1. Check `/tmp/btx-build.log` for build errors.
2. Check `~/.btx/debug.log` for daemon errors.
3. Check `~/.btx/mining-loop.log` for mining errors.
4. Check `dashboard/data/server.log` for dashboard errors.
5. File an issue at <https://github.com/n8uyeda/btx-air-m2-miner/issues> with:
   - macOS version (`sw_vers`)
   - Mac chip (`sysctl -n machdep.cpu.brand_string`)
   - Step where it failed
   - Relevant log excerpts (scrub any addresses or passphrases first)
