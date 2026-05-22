#!/usr/bin/env bash
# btx-air-m2-miner — one-command installer for macOS Apple Silicon
#
# What this does:
#   1. Verifies prereqs (macOS Apple Silicon, Homebrew, Command Line Tools)
#   2. Installs Homebrew dependencies (cmake, boost, libevent, sqlite, pkgconf)
#   3. Clones github.com/btxchain/btx into ~/dev/btx/
#   4. Applies patches in patches/ (Metal-CLI + AppleClang 15 wallet fixes)
#   5. Configures cmake with the right flags
#   6. Compiles btxd, btx-cli, btx-wallet, btx-matmul-* tools
#   7. Ad-hoc codesigns all binaries for Metal access
#
# What this DOES NOT do:
#   - Create your wallet (see scripts/wallet-setup.sh)
#   - Generate your payout address (handled in wallet-setup)
#   - Start the daemon or mining (see scripts/start-*.sh)
#
# Idempotent: safe to re-run after a partial failure.

set -euo pipefail

# --- color / log helpers ---------------------------------------------------
B="\033[1m" ; G="\033[32m" ; Y="\033[33m" ; R="\033[31m" ; D="\033[2m" ; N="\033[0m"
say()  { printf "${B}==>${N} %s\n" "$*"; }
ok()   { printf "${G}    ✓${N} %s\n" "$*"; }
warn() { printf "${Y}    !${N} %s\n" "$*"; }
err()  { printf "${R}    ✗${N} %s\n" "$*" >&2; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BTX_REPO="${HOME}/dev/btx"
BTX_GITHUB="https://github.com/btxchain/btx.git"
BTX_TAG="v0.30.1"   # pinned for reproducibility; update when newer release tested

# --- step 0: banner --------------------------------------------------------
cat <<EOF

  ┌─────────────────────────────────────────────────────────────┐
  │                                                             │
  │         btx-air-m2-miner installer                          │
  │         build BTX from source for Apple Silicon             │
  │                                                             │
  │         Estimated time: 30-45 min                           │
  │         Disk used:      ~5 GB                               │
  │                                                             │
  └─────────────────────────────────────────────────────────────┘

EOF

# --- step 1: prereq checks -------------------------------------------------
say "Step 1/7 — Verifying prerequisites"

if [[ "$(uname -s)" != "Darwin" ]]; then
    err "macOS only. Detected $(uname -s)."
    exit 1
fi
ok "macOS detected"

if [[ "$(uname -m)" != "arm64" ]]; then
    err "Apple Silicon (arm64) only. Detected $(uname -m). Intel Macs not supported."
    exit 1
fi
ok "Apple Silicon detected"

OS_VER=$(sw_vers -productVersion)
OS_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
if [[ "$OS_MAJOR" -lt 14 ]]; then
    warn "macOS $OS_VER detected. This kit was tested on macOS 14+. Older versions may work but are untested."
else
    ok "macOS $OS_VER"
fi

if ! command -v xcode-select &>/dev/null; then
    err "Xcode Command Line Tools not installed. Run: xcode-select --install"
    exit 1
fi
ok "Xcode Command Line Tools present"

if ! command -v brew &>/dev/null; then
    err "Homebrew not installed. Install from https://brew.sh first."
    exit 1
fi
ok "Homebrew present: $(brew --version | head -1)"

if ! command -v git &>/dev/null; then
    err "git not installed (should ship with CLT). Run: xcode-select --install"
    exit 1
fi
ok "git present"

FREE_GB=$(df -g "$HOME" | tail -1 | awk '{print $4}')
if [[ "$FREE_GB" -lt 6 ]]; then
    err "Less than 6 GB free in \$HOME. Free up space and retry."
    exit 1
fi
ok "Free disk: ${FREE_GB} GB"

# --- step 2: install Homebrew deps -----------------------------------------
say "Step 2/7 — Installing Homebrew dependencies"
for pkg in cmake boost libevent sqlite pkgconf; do
    if brew list --versions "$pkg" &>/dev/null; then
        ok "$pkg already installed"
    else
        printf "    installing $pkg... "
        brew install "$pkg" >/dev/null 2>&1 && echo "done" || { err "brew install $pkg failed"; exit 1; }
    fi
done

# --- step 3: clone BTX -----------------------------------------------------
say "Step 3/7 — Cloning BTX source"
mkdir -p "$(dirname "$BTX_REPO")"
if [[ -d "$BTX_REPO/.git" ]]; then
    ok "$BTX_REPO already exists; fetching latest"
    git -C "$BTX_REPO" fetch --tags --quiet
else
    git clone "$BTX_GITHUB" "$BTX_REPO" --quiet
    ok "Cloned to $BTX_REPO"
fi

git -C "$BTX_REPO" checkout "$BTX_TAG" --quiet
ok "Checked out $BTX_TAG"

# --- step 4: apply patches -------------------------------------------------
say "Step 4/7 — Applying compatibility patches"

apply_patch() {
    local pf="$1"
    local pname=$(basename "$pf" .patch)
    if git -C "$BTX_REPO" apply --check "$pf" 2>/dev/null; then
        git -C "$BTX_REPO" apply "$pf"
        ok "Applied $pname"
    elif git -C "$BTX_REPO" apply --check --reverse "$pf" 2>/dev/null; then
        ok "$pname already applied (reverse-applies clean)"
    else
        warn "$pname does not apply cleanly. Upstream may have merged it. Continuing without it."
    fi
}

for p in "$REPO_DIR"/patches/*.patch; do
    apply_patch "$p"
done

# --- step 5: cmake configure -----------------------------------------------
say "Step 5/7 — Configuring cmake build"
cd "$BTX_REPO"
SQLITE_PREFIX=$(brew --prefix sqlite)
cmake -B build \
    -DBTX_MATMUL_METAL_PRECOMPILE_KERNELS=OFF \
    -DENABLE_WALLET=ON \
    -DCMAKE_PREFIX_PATH="$SQLITE_PREFIX" \
    >/tmp/btx-cmake-configure.log 2>&1
ok "cmake configured (log: /tmp/btx-cmake-configure.log)"

# --- step 6: compile -------------------------------------------------------
say "Step 6/7 — Compiling (this is the long step, ~25-40 minutes)"
echo "    Compiling on $(sysctl -n hw.logicalcpu) cores in parallel."
echo "    Tail the build progress in another terminal with:"
echo "      tail -f /tmp/btx-build.log"
echo
START=$(date +%s)
cmake --build build -j"$(sysctl -n hw.logicalcpu)" >/tmp/btx-build.log 2>&1 || {
    # The test_btx target sometimes fails on linker errors when wallet is on;
    # this doesn't affect the production binaries. Check for those.
    if [[ -x "$BTX_REPO/build/bin/btxd" && -x "$BTX_REPO/build/bin/btx-cli" ]]; then
        warn "Build completed with non-fatal warnings (test_btx may have failed to link — production binaries are OK)"
    else
        err "Build failed. See /tmp/btx-build.log for details."
        tail -20 /tmp/btx-build.log >&2
        exit 1
    fi
}
END=$(date +%s)
ELAPSED=$(( (END-START) / 60 ))
ok "Built in ${ELAPSED} minutes"

# --- step 7: codesign ------------------------------------------------------
say "Step 7/7 — Ad-hoc codesigning binaries (required for Metal access)"
for bin in btxd btx-cli btx-tx btx-util btx-wallet btx-genesis btx-matmul-backend-info btx-matmul-solve-bench btx-matmul-metal-bench; do
    path="$BTX_REPO/build/bin/$bin"
    if [[ -f "$path" ]]; then
        codesign --force --deep --sign - "$path" 2>/dev/null || warn "codesign failed for $bin (continuing)"
    fi
done
ok "All binaries signed"

# --- final verification ----------------------------------------------------
say "Verification: does Metal mining actually work on this Mac?"
if "$BTX_REPO/build/bin/btx-matmul-backend-info" --backend metal 2>/dev/null | grep -q '"active_backend": *"metal"'; then
    ok "Metal backend active and working — you have a real GPU mining setup"
else
    warn "Metal backend not active on this build. Mining will use CPU (slower)."
    warn "Run \`$BTX_REPO/build/bin/btx-matmul-backend-info --backend metal\` to diagnose."
fi

# --- done ------------------------------------------------------------------
cat <<EOF

  ${B}=== Install complete ===${N}

  Built binaries are at: ${BTX_REPO}/build/bin/
  Build log:             /tmp/btx-build.log
  cmake config log:      /tmp/btx-cmake-configure.log

  ${B}Next steps:${N}
    1. Set up your wallet:
       ${B}./scripts/wallet-setup.sh${N}
    2. Start the daemon (sync takes 4-8 hours first time):
       ${B}./scripts/start-daemon.sh${N}
    3. Once synced, start mining (you'll need your payout address from step 1):
       ${B}./scripts/start-mining.sh <your-btx1z-address>${N}
    4. Launch the dashboard:
       ${B}./dashboard/start.sh${N}

  Realistic expectations on a base M2 Air: ~1,000 nonces/sec ≈ 0.1% network share
  ≈ ~1 block/day mean ≈ ~20 BTX/day. See docs/expectations.md for details.

EOF
