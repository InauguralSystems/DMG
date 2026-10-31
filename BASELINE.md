# DMG baseline

## Fresh wall receipt — 2026-10-31, ASUS X540NA

These are headless **VM-tier, startup-inclusive external wall** results on the
bare-metal Celeron N3350 dev box (two cores, 4 GB), using the standard
`cpu_instrs.gb --cycles 500000` canary. All samples reported **500,004 actual
cycles**. The dated [auditable receipt](bench/receipts/2026-10-31-mhz/RECEIPT.md)
contains the frozen manifest, exact commands, all raw samples/failures,
correctness evidence, host conditions, IQRs and paired comparisons.

Frozen sources: DMG `3451eeba1ae1a14ee8e08d90721f09458a585197`;
both DMG and ouroboros declare EigenScript **v0.48.0**, resolved to
`546848c0a7123ea7066923ebadb06f0af29af953`;
ouroboros `4afbfdde8b070f9aa196e37a8fb0229c50ee586b` (remote main at inspection).
Builds used worktree-local directories and the unchanged release/AOT defaults.

| Execution tier / role | Valid n | Median external wall | Median wall MHz | MHz range |
|---|---:|---:|---:|---|
| VM interpreter (`EIGS_JIT_OFF=1`) | 7 | 0.542594 s | **0.922** | 0.860–0.963 |
| VM default JIT | 7 | 0.564606 s | **0.886** | 0.856–0.919 |
| VM identical-JIT A/A control | 7 | 0.566054 s | **0.883** | 0.858–0.948 |
| AOT, requested startup-subtracted 0/2M protocol | 0 | — | **blocked** | — |

Seven counterbalanced rounds retained every sample, with no exclusions or
timed failures. Interpreter and default JIT passed the unit and Blargg CPU /
timing gates and all declared byte-exact parity checks before timing. The
paired JIT/interpreter wall delta was +4.057%; unchanged-binary A/A wall-delta
IQR was 5.161 percentage points, so a small tier effect is unresolved beyond
the measured noise. Residual host activity and observation limits are in the
receipt; these figures do not establish a historical regression or speedup.

**AOT is incomplete.** Its CPU unit-test compilation was refused (the binding
order class tracked by [ouroboros#335](https://github.com/InauguralSystems/ouroboros/issues/335));
native CPU/timing gates and 2M parity probes timed out, and `k_oracle.sh`
refused perf access (`perf_event_paranoid=4`). The receipt preserves every
failure; no AOT MHz or K is published. This complements
[ouroboros#333](https://github.com/InauguralSystems/ouroboros/issues/333)
without changing its budget or treating the instruction-cost regression as
resolved. Historical AOT numbers remain historical context.

The sections below retain their original dates, pins, hosts and timing
methodologies. They are **historical receipts**, not v0.48.0 results. In
particular, the historical 5M VM/JIT and 2M AOT receipts cited by DMG#89 are not
replaced by this 500K VM canary, and unmatched rows do not support speedup claims.

Historical machine: T3200 (2008 Gateway laptop, ~2007-era CPU). Use as local
trend numbers, not universal performance claims. Modern HW will be
substantially faster — most prior CHANGELOG/memory perf figures
(e.g. 5 MHz cpu_instrs, 116 ms bench_dmg_shape) were modern HW.

## v0.12.0 baseline — 2026-06-10

EigenScript v0.12.0 (JIT Stage 5 inline matrix + temporal compile-gate),
DMG at HEAD `8f83ec9` (deferred bus-tick + inlined exec_op).

### Headline canary: cpu_instrs.gb, 500K simulated cycles

This is the **standard regression-tracking probe** (matches the
n=10 median methodology used historically in session memory).
500K cycles is startup-dominated — memset/memcpy/simple loops —
and gives a stable, low-variance reading for VM hot-path comparisons.

```bash
../EigenScript/src/eigenscript dmg.eigs roms/cpu_instrs.gb --cycles 500000
```

| variant | n | MHz (median) | range |
|---|---|---|---|
| JIT-on (default) | 5 | **1.101** | 1.087 – 1.127 (3.7%) |

Prior memory-recorded figure: ~1.02 MHz (2026-06-08, n=10, same
methodology). v0.12.0 is ~8% above that — within the variance of
multi-day measurements, but trend is non-negative. **No regression.**

### Full aggregate: cpu_instrs Blargg suite (225M cycles)

A longer, opcode-coverage-heavy workload (~4 min wall). Different
shape than the canary because it exercises arithmetic, jumps,
memory ops, etc. — not a substitute for the canary.

```bash
BLARGG_CPU_INSTRS_MODE=aggregate bash tests/run_blargg_cpu_instrs_suite.sh
```

ROM completes at 225,000,004 simulated cycles. All runs PASS Blargg.
Peak RSS ~13.6 MB.

| variant | n | median wall | MHz |
|---|---|---|---|
| JIT-on (default) | 3 | 4m23.8s | 0.853 (0.848–0.874, 3.0%) |
| JIT-off (`EIGS_JIT_OFF=1`) | 1 | 4m15.2s | 0.882 |

JIT contribution at n=1 vs n=3 is **at most ~3%, indistinguishable
from noise**. Wall-clock under 5 min per run, but JIT-off at n=3
would be ~15 minutes for a sub-3% effect — poor trade.

### Proxy ≠ real workload on this hardware

`tests/bench_dmg_shape.eigs` (in EigenScript repo) is the "DMG
dispatch shape" stand-in CHANGELOGed for JIT Stage 5. T3200 n=3:

| bench_dmg_shape (T3200, n=3 median) | ms |
|---|---|
| JIT-on | 435 |
| JIT-off | 615 |

JIT cuts the proxy by **~30% on T3200**. That win does NOT
propagate to either the canary (small JIT-on/off gap likely, not
tested) or the full aggregate (3% within noise). The proxy is a
tight 8-op dispatch loop on a fixed buffer that fits in L1i; DMG's
real opcode coverage doesn't. **Don't extrapolate proxy gains to
DMG perf claims on cache-constrained hardware.**

CHANGELOG-claimed `bench_dmg_shape` 239 → 116 ms (2.06×) was
modern-HW measurement. On T3200 the proxy itself runs at ~435 ms
(3.7× modern); the JIT delta still applies as a ratio but the
absolute floor is hardware-bound.

### What to compare against in the future

- **Canary** (cpu_instrs 500K cycles, n=5): expect ~1.1 MHz median,
  ±4%. This is the right probe for VM hot-path change regression.
- **Full aggregate** (225M cycles, n=3): expect ~0.85 MHz median.
  Use this when you want to characterize opcode-coverage-heavy
  workload behavior, not for quick regression checks.
- If canary regresses below ~1.0 MHz or full aggregate below
  ~0.80 MHz, that's signal worth investigating.

Raw run logs were not persisted; re-running is cheap (~30 sec
canary, ~5 min full).

## Cloud devcontainer baseline — 2026-06-25 (EigenScript v0.18.0)

Captured in the reproducible devcontainer (`.devcontainer/`, EigenScript
pinned `v0.18.0`) on a GitHub-hosted cloud runner — **the same image a
Codespace opens**. Different host from the T3200 above: a trend number for
the cloud/Codespace target, **not comparable to the T3200 figures as a
runtime delta** (per the no-cross-host-comparison rule).

Host: **AMD EPYC 7763** (Zen 3 server), **2 vCPU** allocated — the default
GitHub Actions runner / basic Codespace SKU. DMG emulation is
single-threaded, so only per-core speed matters; a larger Codespace machine
type adds cores/RAM, not canary MHz.

### Headline canary: cpu_instrs.gb, 500K cycles, n=5

| variant | n | MHz (median) | range |
|---|---|---|---|
| JIT-on (default) | 5 | **5.22** | 4.36 – 5.46 |

Runs: 5.22, 5.22, 5.46, 4.36, 5.44 (mean 5.14). The 4.36 is a shared-cloud
noisy-neighbor dip; the warm cluster is 5.22–5.46 (~4.6%).

**Above real Game Boy speed (4.19 MHz) — ~1.25× real-time.** The
interpreted/JIT VM emulates a DMG *faster than the original hardware* in the
cloud. For cross-host context only (NOT a runtime trend): ~4.7× the T3200
v0.12.0 canary (1.101 MHz) and ~4.3× the local N3350 Goldmont dev box
measured the same day (1.21 MHz median, v0.18.0). Consistent with the
"~5 MHz cpu_instrs on modern HW" figure noted at the top.

Re-measure: launch a Codespace and run
`eigenscript dmg.eigs roms/cpu_instrs.gb --cycles 500000`, or add the n=5
canary to the devcontainer `runCmd` on a throwaway CI branch (how this was
captured; AOT extrapolation off this number is the future headroom).
