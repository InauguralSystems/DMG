# DMG baseline

Machine: T3200 (2008 Gateway laptop, ~2007-era CPU). Use as local
trend numbers, not universal performance claims. Modern HW will be
substantially faster — most prior CHANGELOG/memory perf figures
(e.g. 5 MHz cpu_instrs, 116 ms bench_dmg_shape) were modern HW.

## v0.12.0 baseline — 2026-06-10

EigenScript v0.12.0 (JIT Stage 5 inline matrix + temporal compile-gate),
DMG at HEAD `8f83ec9` (deferred bus-tick + inlined exec_op).

### Headline: cpu_instrs aggregate (Blargg)

```bash
BLARGG_CPU_INSTRS_MODE=aggregate bash tests/run_blargg_cpu_instrs_suite.sh
```

ROM completes at 225,000,004 simulated cycles. All runs PASS Blargg.
Peak RSS ~13.6 MB.

| variant | n | median wall | MHz |
|---|---|---|---|
| JIT-on (default) | 3 | 4m23.8s | **0.853** |
| JIT-off (`EIGS_JIT_OFF=1`) | 1 | 4m15.2s | **0.882** |

JIT-on spread n=3: 0.848 / 0.853 / 0.874 MHz (3.0%). JIT-off n=1
(0.882) sits within JIT-on's spread, so the JIT contribution on
DMG cpu_instrs on T3200 is **at most ~3%, indistinguishable from
noise** at n=1 vs n=3. If we wanted a real signal here we'd need
JIT-off n=3 too, but a 30-minute test for a sub-3% effect is not
a good trade on this hardware.

This contradicts the proxy `bench_dmg_shape` (in EigenScript repo),
which clearly benefits from JIT on T3200:

| bench_dmg_shape (T3200, n=3 median) | ms |
|---|---|
| JIT-on | 435 |
| JIT-off | 615 |

JIT cuts the proxy by ~30% on T3200. **The proxy does not predict
DMG's real-workload behavior on this hardware.** Likely cause: the
proxy is a tight dispatch-table loop over 8 trivial ops on a fixed
buffer; DMG's actual hot loop has wider opcode coverage, more
varied bail-paths through `cpu_mem_read` / interrupt checks, and
likely thrashes T3200's tiny L1i cache where the proxy fits.

### Note on the 1.02 MHz prior figure

The session memory noted "~1.02 MHz after deferred bus-tick +
inlining (2026-06-08)" — likely the same workload as this
baseline but either (a) measured on a different day's system load,
(b) memory-rounded from a similar number, or (c) measured with a
different cycle budget. The CHANGELOG only persists 0.177 MHz
(pre-inlining). Treat 1.02 MHz as approximate; 0.853 MHz is the
n=3 v0.12.0 number on T3200.

### What to compare against in the future

When measuring future EigenScript or DMG perf work on T3200:
- **Headline number:** cpu_instrs aggregate MHz, n=3 minimum.
  Baseline = 0.853 MHz median.
- **Confidence band:** ±3% within the same session is typical;
  larger gaps over multiple sessions usually mean background
  load shifted, not real perf change.
- **JIT diagnostic:** Compare bench_dmg_shape JIT-on vs JIT-off
  on T3200 (cheap, ~3 sec each n=3). If their ratio changes
  substantially, that's signal — but a proxy ratio change does
  *not* imply a real-workload change on this hardware.

Raw run logs were not persisted (one-shot timing via the test
suite). Re-running is cheap (~5 min) if a specific log is needed.
