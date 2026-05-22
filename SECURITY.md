# SECURITY.md — risk awareness, threat model, no-affiliation

## This kit is not affiliated with the BTX project

`btx-air-m2-miner` is an independent third-party setup kit by [@n8uyeda](https://github.com/n8uyeda). It is **not** maintained by, endorsed by, or affiliated with the BTX team at [btx.dev](https://btx.dev) or [github.com/btxchain/btx](https://github.com/btxchain/btx). All BTX-side trademarks, code, and protocols are the property of their respective owners.

The kit clones BTX source code from the official upstream repository during install. It applies two compatibility patches needed to build on macOS 14.x Command Line Tools + AppleClang 15. The kit does not modify BTX consensus, cryptography, or networking behavior.

For BTX-side issues (consensus bugs, protocol questions, official support), file with the BTX project at <https://github.com/btxchain/btx>. For issues with this kit (install scripts, dashboard, documentation), file at <https://github.com/n8uyeda/btx-air-m2-miner>.

## Risk awareness

Mining a cryptocurrency, especially a young one, carries financial, legal, and operational risks. Read this section in full before using this kit.

### BTX-side risks

- **BTX is a young chain.** Mainnet launched **2026-03-19**. The codebase has had internal audits and a structured vulnerability tracker but no public third-party audit by an established firm (Trail of Bits, NCC, Halborn, etc.) as of May 2026. Consensus or cryptographic bugs may exist that are not yet known.
- **No public spot market exists.** Mined BTX has no documented exchange listing as of May 2026. The token's USD value is purely modeled (see [btxprice.com](https://btxprice.com/valuation-model)), not market-discovered. Expect to hold mined coins for some unknown period before any liquidity exists, if ever.
- **The project team is partially anonymous.** Numair Faraz (founder, doxxed via [daia.ai](https://daia.ai)), Long Nguyen, and qubixt are named in commit history. Other contributors are pseudonymous. The legal entity behind the project is not disclosed publicly as of May 2026.

### Self-custody risks

- **You are responsible for your wallet's backup.** This kit walks you through `backupwalletbundlearchive` and a test-restore verification, but ultimately the encrypted bundle file on your USB drive is your only off-machine record of your keys. If you lose the file AND your Mac, your keys are gone forever. There is no "forgot password" recovery in self-custodial crypto.
- **The wallet passphrase is irrecoverable.** If you forget it, your wallet is permanently inaccessible regardless of whether you have the backup file. Write it on paper and store it offline.
- **The archive passphrase is also irrecoverable.** Same deal. Recommended approach: same passphrase as the wallet (kit defaults to this).

### Regulatory / legal risks

- **Tax treatment of mining income varies by jurisdiction.** In the US, mining rewards are typically ordinary income at fair market value at the time of receipt, plus a capital gains event when later spent or sold. Talk to a tax professional in your jurisdiction.
- **Some jurisdictions restrict cryptocurrency mining.** Check local law before running this on machines you control.

### Operational risks specific to this kit

- **The kit applies two patches to the BTX source code.** These patches are correct (per Apple's documentation for the Metal API; per the C++20 standard for the wallet fix) but they ARE modifications to the production code. They are clearly visible in `patches/` and can be reviewed before applying.
- **The kit codesigns binaries with an ad-hoc signature** (`codesign --force --deep --sign -`). This is the minimum required for macOS to allow the binaries to access Metal. It is NOT a Developer ID signature; the binaries are not notarized.
- **The mining loop runs the GPU near 100% indefinitely.** This is normal for mining but accelerates thermal wear on the laptop. Expect fan noise and faster battery drain. Do not mine on battery; always plug in.

## Threat model — what this kit DOES and DOES NOT protect against

| Threat | Protection |
|---|---|
| Laptop stolen with you logged in | Wallet passphrase prevents key extraction even with disk access |
| Laptop stolen + FileVault unlocked | Wallet passphrase still required to spend |
| USB stolen | Archive passphrase prevents reading the bundle |
| Forgot wallet passphrase | **No protection.** Your keys are gone. Write the passphrase on paper offline. |
| RPC port exposed to internet | Kit binds RPC to 127.0.0.1 only; firewall opens only P2P port 19335 |
| Mining-loop crashes mid-block | No work lost (Bitcoin-style PoW is stateless across attempts) |
| BTX network attacks (51%, etc.) | Inherits Bitcoin Core's defenses; not specific to this kit |
| Cryptographic bug in BTX post-quantum implementation | **No protection.** Same risk as anyone running BTX. |

## Reporting vulnerabilities

For security issues in **this kit** (install scripts, dashboard, documentation): open a GitHub issue at <https://github.com/n8uyeda/btx-air-m2-miner/issues> tagged `security`, or contact privately via GitHub.

For security issues in **BTX itself** (consensus, cryptography, networking): see <https://github.com/btxchain/btx/blob/main/SECURITY.md>.

## No warranty

This software is provided "as is," without warranty of any kind. See [LICENSE](LICENSE) for the full disclaimer.
