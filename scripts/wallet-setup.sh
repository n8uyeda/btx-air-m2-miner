#!/usr/bin/env bash
# Interactive wallet setup — encrypted wallet, payout address, encrypted backup archive,
# verified test-restore, then a clean handoff to mining.
#
# This script PAUSES at each security-critical step so you read the prompts.
# It NEVER asks for your passphrase on the command line (always via stdin,
# no echo). It NEVER stores your passphrase to disk.
#
# Outputs:
#   - Wallet "miner" created and encrypted in ~/.btx/wallets/miner/
#   - One P2MR payout address (printed; you copy it for the mining step)
#   - One encrypted backup archive on a USB drive you specify
#   - Verified test-restore (a throwaway wallet, deleted after verification)

set -euo pipefail

B="\033[1m" ; G="\033[32m" ; Y="\033[33m" ; R="\033[31m" ; D="\033[2m" ; N="\033[0m"

DATADIR="${HOME}/.btx"
BTX_CLI="${HOME}/dev/btx/build/bin/btx-cli"
TODAY=$(date +%Y-%m-%d)

# --- preflight -------------------------------------------------------------
if [[ ! -x "$BTX_CLI" ]]; then
    echo "${R}❌ btx-cli not found.${N} Run ./install.sh first." >&2
    exit 1
fi

if ! pgrep -f "btxd.*-datadir=$DATADIR" >/dev/null; then
    echo "${R}❌ btxd is not running.${N} Run ./scripts/start-daemon.sh first." >&2
    exit 1
fi

# --- banner ----------------------------------------------------------------
cat <<EOF

${B}┌─────────────────────────────────────────────────────────────┐
│  BTX Wallet Setup — interactive, security-critical          │
└─────────────────────────────────────────────────────────────┘${N}

Before you proceed, you should have:

  ${B}1. A wallet passphrase chosen and written on PAPER, off-Mac.${N}
     Minimum 20 chars or 6+ diceware words. This passphrase will
     ALSO protect your USB backup archive. Lose it = lose your coins.

  ${B}2. A USB drive plugged in.${N}
     Will receive your encrypted backup file. Encrypted volume is
     recommended; if not encrypted, the archive's own encryption
     still protects the keys (single-layer crypto + physical security).

  ${B}3. Pen and paper for a secondary copy of the descriptor.${N}
     Belt-and-suspenders for the case where the USB fails AND you
     forget which drawer it's in.

EOF

# Disable shell history for this session
unset HISTFILE
set +o history 2>/dev/null || true

read -rp "Ready to begin? [yes/no]: " READY
if [[ "$READY" != "yes" ]]; then
    echo "Bailing. Re-run this script when you're ready."
    exit 0
fi

# --- ask for USB mount path ------------------------------------------------
echo
echo "${B}USB drive path${N}"
echo "Currently mounted volumes:"
ls -1 /Volumes/ | sed 's/^/  /'
echo
read -rp "Which volume should hold the encrypted backup? (e.g. 'MYBACKUP'): " USB_NAME
USB_PATH="/Volumes/$USB_NAME"
if [[ ! -d "$USB_PATH" ]]; then
    echo "${R}❌ $USB_PATH does not exist.${N}" >&2
    exit 1
fi
echo "  ✓ Will write backup to $USB_PATH"

# --- step 1: create wallet -------------------------------------------------
echo
echo "${B}Step 1/6 — Creating wallet 'miner' (unencrypted at first)${N}"
"$BTX_CLI" -datadir="$DATADIR" createwallet "miner" >/dev/null 2>&1 || {
    if "$BTX_CLI" -datadir="$DATADIR" listwallets | grep -q '"miner"'; then
        echo "  ${Y}!${N} Wallet 'miner' already exists. Continuing with existing wallet."
    else
        echo "  ${R}✗${N} createwallet failed."
        exit 1
    fi
}
echo "  ${G}✓${N} Wallet created"

# --- step 2: encrypt -------------------------------------------------------
ENCRYPTED=$("$BTX_CLI" -datadir="$DATADIR" -rpcwallet=miner getwalletinfo | python3 -c 'import sys,json;d=json.load(sys.stdin);print("yes" if "unlocked_until" in d else "no")')
if [[ "$ENCRYPTED" == "no" ]]; then
    echo
    echo "${B}Step 2/6 — Encrypt wallet${N}"
    echo "Type your wallet passphrase now (will not echo). Press Enter when done."
    read -rsp "Wallet passphrase: " PASS
    echo
    read -rsp "Confirm passphrase: " PASS2
    echo
    if [[ "$PASS" != "$PASS2" ]]; then
        echo "${R}✗ Passphrases don't match. Bailing.${N}"
        exit 1
    fi
    if [[ ${#PASS} -lt 20 ]]; then
        echo "${R}✗ Passphrase too short (need ≥ 20 chars). Bailing for your safety.${N}"
        exit 1
    fi
    "$BTX_CLI" -datadir="$DATADIR" -rpcwallet=miner encryptwallet "$PASS" >/dev/null
    unset PASS PASS2
    echo "  ${G}✓${N} Wallet encrypted"
else
    echo
    echo "${B}Step 2/6 — Wallet already encrypted (skipping)${N}"
fi

# --- step 3: unlock briefly to generate address + backup -------------------
echo
echo "${B}Step 3/6 — Unlock wallet briefly (1 hour) to generate address + backup${N}"
echo "Type your wallet passphrase again (same one). Will not echo."
read -rsp "Wallet passphrase: " PASS
echo
if ! "$BTX_CLI" -datadir="$DATADIR" -rpcwallet=miner walletpassphrase "$PASS" 3600 >/dev/null 2>&1; then
    echo "${R}✗ Passphrase rejected.${N} Re-run the script and try again."
    unset PASS
    exit 1
fi
echo "  ${G}✓${N} Unlocked for 1 hour"

# --- step 4: generate payout address ---------------------------------------
echo
echo "${B}Step 4/6 — Generate P2MR payout address${N}"
ADDR=$("$BTX_CLI" -datadir="$DATADIR" -rpcwallet=miner getnewaddress "miner-payout" 2>&1)
if [[ ! "$ADDR" =~ ^btx1z ]]; then
    echo "${R}✗ Address generation failed: $ADDR${N}"
    unset PASS
    exit 1
fi
echo "  ${G}✓${N} Payout address: ${B}$ADDR${N}"
echo
echo "  ${Y}WRITE THIS ADDRESS DOWN.${N} You'll need it for the mining command."
echo "  It's safe to share publicly — only the private key (encrypted in your wallet) lets you spend."

# --- step 5: backup with backupwalletbundlearchive ------------------------
echo
echo "${B}Step 5/6 — Encrypted backup to USB${N}"
BACKUP_FILE="$USB_PATH/btx-miner-bundle-$TODAY.tar.zst"
if [[ -f "$BACKUP_FILE" ]]; then
    echo "  ${Y}!${N} A backup already exists at $BACKUP_FILE."
    read -rp "    Overwrite? [yes/no]: " OW
    if [[ "$OW" != "yes" ]]; then
        echo "  Skipping backup. Existing backup retained."
        BACKUP_FILE=""
    fi
fi
if [[ -n "$BACKUP_FILE" ]]; then
    echo "Using your wallet passphrase as the archive passphrase (single-credential model)."
    echo "Writing encrypted bundle archive..."
    RESULT=$(echo "$PASS" | "$BTX_CLI" -datadir="$DATADIR" -stdinbundlepassphrase -rpcwallet=miner backupwalletbundlearchive "$BACKUP_FILE" "")
    SHA=$(echo "$RESULT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["archive_sha256"])' 2>/dev/null || echo "?")
    echo "  ${G}✓${N} Backup written to $BACKUP_FILE"
    echo "    archive_sha256 (per RPC, of inner bundle): $SHA"
    echo "    file size: $(ls -lh "$BACKUP_FILE" | awk '{print $5}')"
fi

# --- step 6: test restore --------------------------------------------------
echo
echo "${B}Step 6/6 — Test the backup by restoring it into a throwaway wallet${N}"
echo "This proves the backup actually works. If it fails here, FIX IT before relying on the backup."
"$BTX_CLI" -datadir="$DATADIR" unloadwallet "restore-test" >/dev/null 2>&1 || true
rm -rf "$DATADIR/restore-test" "$DATADIR/wallets/restore-test"

if [[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]]; then
    RESTORE_RESULT=$(echo "$PASS" | "$BTX_CLI" -datadir="$DATADIR" -stdinbundlepassphrase restorewalletbundlearchive "restore-test" "$BACKUP_FILE" 2>&1) || {
        echo "${R}✗ restorewalletbundlearchive failed.${N} Backup may be corrupted."
        echo "$RESTORE_RESULT"
        unset PASS
        exit 1
    }
    # Verify: does restore-test see our address as ismine + matching ischange?
    MATCH=$("$BTX_CLI" -datadir="$DATADIR" -rpcwallet=restore-test getaddressinfo "$ADDR" 2>&1 | python3 -c 'import sys,json;d=json.load(sys.stdin);print("yes" if d.get("ismine") and not d.get("ischange") else "no")')
    if [[ "$MATCH" == "yes" ]]; then
        echo "  ${G}✓${N} Test restore SUCCESS — backup is verified functional"
    else
        echo "  ${R}✗${N} Test restore mismatch — restore wallet does not own the payout address correctly."
        echo "       DO NOT RELY ON THIS BACKUP. Re-run wallet setup."
        unset PASS
        exit 1
    fi
    # Clean up the throwaway
    "$BTX_CLI" -datadir="$DATADIR" unloadwallet "restore-test" >/dev/null 2>&1 || true
    rm -rf "$DATADIR/restore-test" "$DATADIR/wallets/restore-test"
    echo "  ${G}✓${N} Throwaway restore-test wallet deleted"
fi

# --- lock + cleanup --------------------------------------------------------
"$BTX_CLI" -datadir="$DATADIR" -rpcwallet=miner walletlock >/dev/null 2>&1 || true
unset PASS

cat <<EOF

${B}=== Wallet setup complete ===${N}

  Payout address:    ${B}$ADDR${N}
  Backup archive:    $BACKUP_FILE
  Wallet status:     encrypted, currently LOCKED

  ${Y}Critical reminders:${N}
    • Eject the USB drive: ${B}diskutil eject "$USB_PATH"${N}
    • Re-write the descriptor on PAPER as a redundancy
    • The wallet passphrase is irrecoverable — write it on paper, store offline

  ${B}Next step — start mining:${N}
    ./scripts/start-mining.sh $ADDR

EOF
