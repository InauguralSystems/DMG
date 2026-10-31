# DMG#89 — 2026-10-31, ASUS X540NA

**Interpreter and default-JIT measurements are complete; AOT remains blocked.**
All 21 scheduled VM/control samples are valid, with no exclusions or timed
failures. No measurement was repeated or replaced. These are headless,
startup-inclusive external wall figures for the requested 500K canary,
not refreshed historical 5M figures or a completed native speed result.

The experiment was sealed at **2026-10-31 16:08:22 UTC**, before correctness
and performance workloads: [manifest](manifest.json),
[manifest checksum](manifest.sha256), [sampling policy](PROTOCOL.md),
[exact commands and runner](COMMANDS.md), [independent review](REVIEW.md),
[classifier calibration](calibration.json).

| Source | Frozen revision |
|---|---|
| DMG, `fix-89-mhz` | `3451eeba1ae1a14ee8e08d90721f09458a585197` |
| EigenScript, both declared pins `v0.48.0` | `546848c0a7123ea7066923ebadb06f0af29af953` |
| ouroboros, current remote main at inspection | `4afbfdde8b070f9aa196e37a8fb0229c50ee586b` |

The shared checkouts were not built or modified. Worktree-local builds are
under `.bench-build/`, with explicit binary paths and SHA-256 identities in the
manifest. Source content maps cover every tracked file; the two build clones
were clean at seal. DMG had only the new receipt files untracked. Binary and
source identities are checked before each timed sample. Release symbols and
linked libraries show no ASan/UBSan instrumentation.

Both VM arms use one standard gcc release binary. The AOT uses unchanged
`aot/build.sh`. gcc is Ubuntu **13.3.0-6ubuntu2~24.04.1**; glibc is **2.39**.
VM compile flags are `-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE`,
the Makefile warning flags, HTTP/MODEL/DB off, GFX on, version `0.48.0`;
link flags include `-pie -Wl,-z,relro,-z,now -lm -lpthread -ldl`.
The complete expanded commands are in [the release build log](build/runtime.stdout).
AOT flags are `-O3 -ffp-contract=off -falign-functions=64 -falign-jumps=32
-falign-loops=32 -march=native`, HTTP/MODEL/DB off, version `aot`, with
the script/runtime resolution anchors baked by the unchanged build script.
These differences are not an optimization A/B.

The machine is bare-metal **ASUS X540NA**, Intel Celeron **N3350**, two cores /
two hardware threads, **3,870,484 KiB** physical RAM, Ubuntu **24.04.5 LTS**,
kernel **6.8.0-147-generic**. Commands run in a sandbox PID namespace, so `ps`
cannot inventory other host jobs. The completed Phase 2 handoff and quiet-box
reservation are retained in [handoff evidence](handoff-evidence.txt); host CPU,
load, memory, thermal and PSI counters supply the independent activity check.
AC is online; governor is `schedutil`; affinity remains CPUs `0–1`, without
CPU isolation or governor changes. Additional read-only power/ASLR observations
are in [host settings](host-settings-extra.json). Every runtime/transpiler/native
launch inherits a **1,500,000 KiB virtual-memory cap**. No arms overlap.

ROM: `roms/cpu_instrs.gb`, SHA-256
`8c5e12f41e0ba5bbca796944f92ffe6de28809198682c4332e38d1b3cf56fcf2`.

## Fresh wall measurements

Collected **17:09:14–17:10:14 UTC**. Each request was **500,000** cycles;
every sample reported **500,004 actual cycles**, which is the numerator used.
One unmeasured warmup per VM configuration preceded the quiet check. Odd
rounds were interpreter / JIT / identical-JIT-repeat; even rounds reversed
that order. The repeat uses the same binary, argv and environment as JIT.

| Tier / role | Scheduled / attempted / valid | Wall median (s) | Wall range (s) | Wall IQR (s) | MHz median | MHz range | MHz IQR |
|---|---|---:|---|---:|---:|---|---:|
| Interpreter, `EIGS_JIT_OFF=1` | 7 / 7 / 7 | 0.542594 | 0.519344–0.581606 | 0.028320 | **0.922** | 0.860–0.963 | 0.049 |
| Default JIT, off switch absent | 7 / 7 / 7 | 0.564606 | 0.543872–0.584375 | 0.007609 | **0.886** | 0.856–0.919 | 0.012 |
| Identical default-JIT A/A repeat | 7 / 7 / 7 | 0.566054 | 0.527193–0.582587 | 0.036351 | **0.883** | 0.858–0.948 | 0.058 |
| AOT, requested 0/2M two-point protocol | 7 pairs / 0 / 0 | — | — | — | **blocked** | — | — |

IQR uses the frozen explicit algorithm: median of the lower and upper halves,
excluding the overall median. For n=7, Q1 is sorted sample 2 and Q3 sample 6.
The operational definition, rather than the policy's informal “Tukey” label,
specifies the calculation. Exact statistics, quartiles and individual pairs
are in [summary.json](summary.json); [summarize.py](summarize.py) derives them
from the retained samples. [raw-samples.csv](raw-samples.csv) indexes all 21
sample logs and statuses; UTC timestamps preserve actual execution order.
[attempt-index.json](attempt-index.json) indexes every retained command/ROM
child record; [failure-index.json](failure-index.json) lists all nonzero
statuses, keeping gate and child outcomes distinct. The final independent
audit is in [FINAL-AUDIT.md](FINAL-AUDIT.md). [SHA256SUMS](SHA256SUMS) covers
the receipt files; verify it from this directory with `sha256sum -c SHA256SUMS`.

Only the following comparisons match host, binary, workload/window and scope.
Each row is the **median of seven round-paired deltas**, with B relative to A;
percentages are not ratios of independently aggregated medians.

| A → B | Median wall delta | Wall-delta range | Wall-delta IQR | Median MHz delta |
|---|---:|---|---:|---:|
| Interpreter → default JIT | +0.022012 s / **+4.057%** | −2.150% to +11.546% | 5.041 percentage points | −3.899% |
| JIT → identical-JIT repeat (A/A) | −0.004126 s / **−0.725%** | −6.197% to +3.635% | **5.161 percentage points** | +0.730% |

The A/A median absolute wall delta is **2.026%**, with maximum **6.197%**.
The observed JIT/interpreter median delta is smaller than the A/A IQR and
maximum absolute shift. A small tier effect is **unresolved beyond this
session's noise floor**; no small improvement or regression is claimed.
The A/A control describes this VM canary/time scale, not AOT subtraction noise.

The [quiet check](quiet-checks.jsonl) measured **0.207 busy CPU-equivalents**
over 10 s, below the predeclared 0.25 start threshold. During collection,
one-minute load was **0.72–1.19** (including decay from preceding validation),
recorded thermal endpoints never exceeded **42 C**, and available memory was
**2,258,960–2,282,528 KiB**. Host CPU counters show residual activity beyond
the measured child of **0.027–0.477 CPU-equivalents**; the predeclared exclusion
threshold was strictly greater than 0.50. This was not a zero-background host.
All samples remain included; no outlier trimming or discretionary exclusions
were applied. Process attribution is unavailable across the PID namespace;
thermal/frequency readings are endpoints, not continuous observations.
[postcollection-audit.json](postcollection-audit.json) records these conditions,
21 started/completed/valid attempts, and unchanged source/binary/ROM identities
before the requested BASELINE documentation edit.

## Correctness and blockers

Interpreter and default JIT each passed the CPU and memory unit tests, the
Blargg aggregate plus all eleven individual CPU ROMs, and all four timing ROMs.
Each CPU gate reported **456,000,068** total actual cycles and **12,416 KiB**
peak RSS; timing gate peak RSS was also **12,416 KiB**. Exact stdout, stderr,
status and actual cycles are retained under [interpreter](correctness/interpreter/)
and [default JIT](correctness/jit/), including each ROM child before the shell
gates remove their temporary logs. The diagnostic-only JIT witness reports
`scanned=70 compiled=44`; interpreter reports `scanned=0 compiled=0`.
`EIGS_JIT_STATS` is absent from measured runs.

[Final gate accounting](correctness/gates.json) and
[byte-exact parity accounting](correctness/parity.json) precede the first
warmup/sample. Interpreter and JIT match stdout, stderr and status at requests
0, 500K and 2M, plus both 500K and 2M state dumps. Native AOT also matches at
0 and 500K and with the 500K state dump. Its two 2M probes timed out at the
declared **180 s**, status **124**, leaving the AOT window unvalidated. Only
complete `Time: ` and `Speed: ` lines were excluded from comparisons; original
stdout and separate stderr are retained alongside `.normalized` files.

AOT has **no completed speed result**:

- [Native CPU unit-test compilation](build/native-cpu.stderr) exited **1**:
  the `_op_cb` write to `cycles` is refused by the module binding-order guard.
  This is the refusal class tracked by
  [ouroboros#335](https://github.com/InauguralSystems/ouroboros/issues/335),
  with the fetched issue snapshot in [upstream-335.json](upstream-335.json).
  No source workaround or retry was made. Native DMG and memory-test binaries
  did build; the native memory unit test passed.
- The unchanged [oracle refusal](aot-oracle/attempt.stderr) exited **2**:
  `perf` cannot count instructions with `perf_event_paranoid=4`.
  [The manifest](manifest.json) preserves the actual perf capability failure.
  This measurement-environment blocker remains owned by
  [DMG#89](https://github.com/InauguralSystems/DMG/issues/89).
  The refusal-only attempt uses a nonexistent `K_BIN` interlock, explicitly
  documented in [COMMANDS.md](COMMANDS.md), so changed permissions cannot
  accidentally start points whose raw logs the oracle would delete.
- Native correctness is also blocked by timeouts: the
  [CPU aggregate gate](correctness/aot/blargg-cpu_instrs.stdout) timed out at
  **1500 s**, and the [timing gate](correctness/aot/blargg-timing.stdout)
  timed out on its first ROM, `instr_timing`, at **180 s**. Both gate statuses
  are **1**; retained child status is **-15 (SIGTERM)**. Neither child reported
  `Passed` or a final actual cycle count. The CPU gate's eleven individual ROMs
  and the timing gate's remaining three ROMs were not reached. No timeout was
  retried. Their cause is unresolved in this measurement; do not infer a wall
  slowdown or attribute it to #333. The bounded parity probes also timed out
  at 2M cycles, with and without `--dump-state`; neither was retried. These
  timeouts leave correctness unestablished for those workloads, rather than
  proving a wrong emulated answer. Evidence remains attached to
  [DMG#89](https://github.com/InauguralSystems/DMG/issues/89) for follow-up.

## Scope and comparison limits

The VM rows use the standard **500K-cycle canary**, with external,
startup-inclusive wall time from launching `timeout` until it is reaped.
DMG's internal `Time:`/`Speed:` fields exclude some process startup and are
retained as raw output, not used for the headline wall MHz. MHz is actual
reported emulated cycles divided by external seconds and by one million.
The clock is non-adjustable `CLOCK_MONOTONIC`, nominal resolution **1 ns**;
this is not the practical scheduling/noise resolution.

The requested AOT protocol is the unchanged budget's **0 / 2,000,000** requests,
seven baseline-then-window pairs, subtracting both elapsed time and actual
reported cycles. The instrument refused before any performance point, so there
are **no paired baseline/window elapsed times, cycle deltas, K or AOT MHz**.
Subtraction stability/resolution cannot be assessed. Internal timing fields in
native correctness logs are not substitutes for that measurement.

Historical 5M-cycle VM/JIT receipts, historical AOT startup-subtracted receipts,
the old T3200 measurements and cloud-host MHz remain context. Host, pins,
workload/window and timing scope must all match before claiming a speedup.
This receipt makes no cross-tier or historical speedup claim.

[ouroboros#333](https://github.com/InauguralSystems/ouroboros/issues/333)
continues to own the separate instruction-cost regression. K and wall MHz are
different observations. No budget is changed or waived, no K regression is
converted into an inferred wall slowdown, and this receipt does not resolve
that issue. Its fetched snapshot is [upstream-333.json](upstream-333.json).

## Acceptance accounting and follow-up

- [x] Frozen source/binary/host/ROM/commands/sampling manifest:
  [manifest.json](manifest.json), [PROTOCOL.md](PROTOCOL.md), [COMMANDS.md](COMMANDS.md).
- [x] Correctness attached before performance claims for every measured arm:
  [gates](correctness/gates.json), [parity](correctness/parity.json).
- [ ] All three tiers have >5 valid speed samples: interpreter 7, default JIT 7,
  A/A control 7; **AOT 0, blocked** by the recorded refusal and timeouts above.
  Its CPU-test refusal class is owned by ouroboros#335; measurement completion
  and the unresolved timeout observations remain on DMG#89. AOT remains unchecked.
- [x] Raw samples, failed attempts and reproducible commands are retained:
  [CSV](raw-samples.csv), [samples](samples/), [build logs](build/),
  [correctness logs](correctness/), [oracle refusal](aot-oracle/attempt.json).
- [x] [BASELINE.md](../../../BASELINE.md) distinguishes these dated results and
  pins from historical context, with a link to this receipt.
- [x] Linked ouroboros#333; its budget and regression-resolution work are unchanged.

Required deviations/blockers are explicit: no native performance points or
native A/A were collected; the preflight oracle invocation was refusal-only
and executed no DMG workload. There is no independent fresh K observation.
To complete the native arm, the owner must address the known compilation
refusal, establish the required correctness/window within declared bounds,
provide perf access, and retain raw oracle points before its cleanup. No
budget waiver or re-baseline is part of that work.

The distillation pass found the existing gate discipline paid directly: a
successful native DMG build and matching 500K state did not qualify as a speed
result when the CPU unit test was refused and required longer checks timed out.
That repo-specific evidence and its owning issues live here; no new general
skill rule was needed. Nothing was committed or pushed by this builder.
