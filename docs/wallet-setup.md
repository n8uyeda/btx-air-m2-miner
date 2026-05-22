# Wallet setup

The single most security-critical part of mining BTX is your wallet. Read this whole doc before you run `./scripts/wallet-setup.sh`.

## Before you start — what you need on hand

1. **A wallet passphrase, chosen and written on PAPER, off-Mac.** Minimum 20 characters or 6+ diceware words. This passphrase will also protect your USB backup archive. Lose this passphrase = lose your coins forever. There is no recovery.

2. **A USB drive plugged in.** Will receive your encrypted backup. The kit defaults to an unencrypted USB volume — the archive's own encryption protects the keys, and physical security of the USB (e.g., a locked drawer) provides a second layer. You can optionally use an APFS-encrypted USB for an additional defense layer; see the "Threat model variations" section at the end.

3. **Pen and paper for a secondary copy of the descriptor.** Belt-and-suspenders for the case where the USB fails AND you forget which drawer it's in.

## How to choose a strong passphrase

**Don't** use a sentence from a book, a memorable date, your kid's name, or any password you've used elsewhere. Brute-force attackers run massive dictionaries.

**Do** use one of:
- **Diceware** (recommended): roll a physical die 5 times, look up the result in the [EFF Diceware list](https://www.eff.org/dice). Repeat 6-7 times. Result: a passphrase like `correct horse battery staple drift mantel`. Each word adds ~13 bits of entropy.
- **Password manager generator**: Bitwarden, KeePassXC, 1Password can generate strong passphrases. **Verify your password manager isn't syncing this entry to a cloud service.**
- **Random Latin-alphabet string**: `openssl rand -base64 24` produces ~20 char strings. Less memorable but very strong.

Write it down on paper. Multiple copies if you can. Store in different physical locations. Treat it like cash.

## Run the script

```bash
./scripts/wallet-setup.sh
```

The script walks you through six steps:

1. **Create wallet** — `createwallet "miner"` (unencrypted at first)
2. **Encrypt the wallet** — you type your passphrase silently (no echo)
3. **Unlock briefly** — for the next ~1 hour (single time window for steps 4-6)
4. **Generate payout address** — a `btx1z...` P2MR address; printed publicly
5. **Backup to USB** — `backupwalletbundlearchive` creates an encrypted bundle file
6. **Test restore** — restores into a throwaway wallet and verifies the backup is functional

After all six steps succeed, the throwaway test wallet is deleted, the miner wallet is re-locked, and you're shown your payout address.

## What `backupwalletbundlearchive` actually does

This is the **canonical** BTX backup RPC. It produces a single encrypted file (`btx-miner-bundle-YYYY-MM-DD.tar.zst`) containing:
- The wallet's SQLite database file
- All descriptors (private + public)
- All shielded-pool spending keys
- The master HD seed
- Manifest with integrity hashes
- Optional shielded viewing keys (disabled by default after the post-block-61000 privacy fork)

The bundle is encrypted with a passphrase (the kit defaults to your wallet passphrase — single-credential model). Restore via `restorewalletbundlearchive`.

**Critical:** `listdescriptors true` is NOT a complete backup. It exports descriptor *structure* but NOT the post-quantum (ML-DSA-44) signing key material. A wallet restored from `listdescriptors` alone produces addresses that look right but can't actually spend coins. Always use `backupwalletbundlearchive`.

## Why we test-restore inline

Most crypto-self-custody tutorials skip this step. They shouldn't. An untested backup is not a backup — it's a hope.

The script:
1. Creates a throwaway wallet (`restore-test`)
2. Restores from your USB bundle into it
3. Verifies that the restore wallet recognizes your original payout address as `ismine: True` and `ischange: False` (matching the source wallet)
4. If verification passes: deletes the test wallet, you can trust the backup
5. If verification fails: bails with an error; do not rely on that backup

This catches backup failures while you can still fix them.

## After wallet setup

Your encrypted backup is on the USB. **Eject the drive** and store it physically secure:
```bash
diskutil eject /Volumes/<your-usb-name>
```

**Write the descriptor to paper** as an additional layer if you want maximum redundancy:
```bash
# Briefly unlock wallet
~/dev/btx/build/bin/btx-cli -datadir=$HOME/.btx -rpcwallet=miner walletpassphrase "<your-passphrase>" 300
# View descriptors (private)
~/dev/btx/build/bin/btx-cli -datadir=$HOME/.btx -rpcwallet=miner listdescriptors true
# Handwrite the `desc` strings onto paper
# Re-lock
~/dev/btx/build/bin/btx-cli -datadir=$HOME/.btx -rpcwallet=miner walletlock
```

Note: paper descriptor backup alone is NOT a complete backup for spending (same caveat as above — missing PQ keys). It's a verification anchor for the case where you have the USB but it's corrupted at the bit level.

## Threat model variations

The kit's default model assumes:
- USB drive is in a locked physical location you control
- Wallet passphrase = archive passphrase (single strong credential)
- Mac has FileVault on (recommended; gives at-rest encryption for the working wallet on disk)

If you want a higher-security setup:

| Upgrade | What it protects against |
|---|---|
| Encrypted USB volume (APFS Encrypted) | Adds a third crypto layer even if archive passphrase leaks |
| Separate archive passphrase ≠ wallet passphrase | Compartmentalization — leak of one doesn't compromise the other |
| Second backup at different physical location | Catastrophic loss of primary location (fire, theft) |
| Hardware-isolated signer (cold-storage Mac, never online) | Online-attack defense; substantial complexity cost |
| Multi-sig (BTX supports `addpqmultisigaddress`) | Single-key compromise no longer enough to steal |

For diligence-phase work (<$2K position size), the default model is sufficient. For real treasury work, upgrade.

## What's NOT backed up

- **Your RPC password** (in `~/.btx/btx.conf`) — regenerable, no value to anyone but you
- **Your peer list** (`~/.btx/peers.dat`) — auto-regenerates from DNS seeds
- **The chain itself** — re-syncable from network in 4-8 hours

These don't need backup. The only thing that matters is **the keys** (wallet bundle) and **the passphrase** (on paper).

## If something goes wrong

The wallet-setup script bails early at any failure. It does NOT silently produce a broken backup. Read the error message, check `~/.btx/debug.log` if needed, and re-run. Common gotchas in [`troubleshooting.md`](troubleshooting.md#wallet-phase).
