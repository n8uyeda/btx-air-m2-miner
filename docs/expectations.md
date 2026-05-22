# Honest expectations

This document tells you what mining BTX on a base M2 Air actually looks like — no marketing, no fluff.

## TL;DR — the headline numbers

On a **base MacBook Air with M2 chip and 8 GB RAM**, mining BTX with this kit:

| Metric | Realistic value |
|---|---|
| Hashrate (Metal backend) | **~1,000 nonces/sec** |
| Network total hashrate (May 2026) | ~900,000 nonces/sec |
| Your network share | **~0.11%** |
| Expected blocks per day | **~1 block / 24 hr** |
| Median wait per block | **~16 hours** (Poisson; the mean is longer) |
| Mean wait per block | **~22 hours** |
| Coinbase reward | 20 BTX per block |
| Expected BTX per day | **~20 BTX** |
| Electricity cost @ $0.16/kWh | **~$2-9/month** |
| Build/setup time | ~45 min once; ~10 min per run after |
| Disk used (chain at May 2026) | ~50 MB; grows over time |

## What "1 block per day" actually feels like in practice

Solo mining a young chain at a small share means the variance is real. The same average rate (~1 block/day) can produce:

- A **lucky run** where you find 2 blocks in the first afternoon and then nothing for 3 days
- An **unlucky run** where you mine for 48 hours with zero blocks, then suddenly hit two in 20 minutes
- The **median experience**: roughly one block every 16-30 hours

Don't panic on dry spells. The math is just statistics. At 0.11% share:
- P(zero blocks in 24 hr) = ~35%
- P(zero blocks in 48 hr) = ~12%
- P(zero blocks in 72 hr) = ~4%

Three full days without a block at this share would be unusual (1 in 25 odds) but not impossible.

## What can change the numbers (better)

| Change | Approximate hashrate impact |
|---|---|
| **M2 Pro** (vs base M2) | ~1.5-2× faster |
| **M2 Max** | ~2-3× faster |
| **M2 Ultra** (desktop) | ~3-5× faster |
| **Install full Xcode** (gets precompiled Metal kernels) | ~5-10% faster cold-start; no steady-state diff |
| **Don't use the laptop for anything else while mining** | More consistent throughput; less thermal throttling |
| **Mac plugged into power, plenty of airflow** | Reduces thermal throttling, more consistent hashrate |

## What can change the numbers (worse)

| Change | Impact |
|---|---|
| Mining on battery | macOS aggressively throttles; expect 30-50% lower hashrate |
| Closed laptop lid (clamshell mode without external display) | Some thermal headroom lost; modest hit |
| Other GPU-heavy work running (video editing, ML inference, etc.) | Significant — Metal contends for the same compute units |
| Network conditions where hashrate climbs (more miners join) | Your share shrinks proportionally |
| Chain difficulty adjustment as hashrate grows | Also shrinks your effective rate |

## The 80× calibration trap (important)

The BTX daemon's `generatetoaddress` RPC takes a `maxtries` parameter. If you write a naive mining loop that divides `maxtries / elapsed_seconds`, you'll get a number that looks ~80× higher than your actual hashrate. **This is a measurement artifact, not real performance.** `maxtries` counts outer-loop iterations, each containing a Metal batch processing many nonces.

Don't trust any "rate" you compute from `maxtries`. The truth is `btx-matmul-solve-bench --backend metal --block-height 61000`, which measures real nonces processed.

The dashboard in this kit handles this automatically — it runs the bench tool every 10 minutes and uses that number for the share calculation. The mining-loop's inflated rate is shown alongside, labeled as such, so you can see both.

## Yield interpretation — what BTX is "worth"

There is no public spot market for BTX as of May 2026. The btxprice.com page publishes a Damodaran-style scenario valuation model that projects ~$1.38 spot and ~$1,424 12-month forward. **These are model outputs, not market prices.** You cannot sell BTX for dollars today.

If you choose to mine, do so for one of these reasons:
1. **You believe in the project's long-term technical thesis** (post-quantum settlement layer, agent-economy infrastructure) and want to accumulate at zero monetary cost beyond electricity.
2. **You want hands-on diligence** before making a capital decision about the chain. Mining gives you direct on-chain observation no amount of external research can match.
3. **You're curious how Apple Silicon performs as mining hardware** and want a real-world test bed.

Do **not** mine BTX expecting to convert to USD in the short term. Liquidity doesn't exist yet.

## Cost / yield breakdown

At ~$0.16/kWh (US average) and ~30W sustained GPU load on an M2 Air:

- 30W × 24h = 0.72 kWh/day
- 0.72 × $0.16 = **~$0.12/day = ~$3.5/month**
- In peak-rate markets (CA, NY) at $0.30/kWh: ~$6.5/month

At 20 BTX/day expected yield:
- 600 BTX/month accumulating in your wallet
- No realizable USD value until a spot market exists
- The cost is real, the revenue is contingent

This is a **moderate-cost diligence position with potentially-zero short-term realizable yield.** Treat the electricity cost as the price of participation, not as an expense against revenue.

## What this kit does NOT promise

- We do not promise mining will be profitable. It may never produce realizable USD value.
- We do not promise the chain will survive long enough to develop liquidity.
- We do not promise no security issues exist in BTX. The chain has had internal audits but no major third-party audit as of May 2026.
- We do not promise these hashrate numbers will hold over time. Difficulty adjusts; network hashrate may grow as more miners arrive.

What we **do** promise:
- The numbers above are real measurements on real hardware (a base M2 Air, 8 GB RAM, macOS 14.8.7).
- The dashboard shows you YOUR numbers, calibrated against the project's own bench tool.
- You will not need to trust our claims — you can verify everything yourself.
