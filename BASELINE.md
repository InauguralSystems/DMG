# DMG baseline

Machine: T3200 (2008 Gateway laptop, ~2007-era CPU). Use as local
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
/home/jon/EigenScript/src/eigenscript dmg.eigs roms/cpu_instrs.gb --cycles 500000
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
