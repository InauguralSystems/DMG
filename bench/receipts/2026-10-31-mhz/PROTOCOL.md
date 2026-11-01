# Frozen sampling policy — DMG#89

Written before building or running correctness/performance workloads. Source and
binary identities are sealed in `manifest.json` after the builds and before the
correctness phase. No performance run is permitted before that seal and the
relevant correctness gates. Do not edit the sealed manifest to fit results.

- DMG: `3451eeba1ae1a14ee8e08d90721f09458a585197`.
- ouroboros: current remote main at inspection,
  `4afbfdde8b070f9aa196e37a8fb0229c50ee586b`.
- Both Dockerfiles declare EigenScript `v0.48.0`, resolved to
  `546848c0a7123ea7066923ebadb06f0af29af953`. The older shared ouroboros
  checkout is not used. All builds live under this worktree's `.bench-build/`.
- Build the standard Make release with gcc, serially, and the native programs
  with unchanged `aot/build.sh` defaults. No sanitizer or tuning override.
- Inherit the host's schedutil governor, AC power, turbo and CPU mask 0–1;
  make no host configuration changes. No forced OSR. Remove inherited
  EigenScript/AOT, allocator and sanitizer tuning variables. Interpreter:
  `EIGS_JIT_OFF=1`; default JIT: `EIGS_JIT_OFF` absent.
- Every runtime, transpiler and native binary inherits `ulimit -v 1500000`
  (KiB). One heavy job at a time. Build timeout 1800 s per command; unit
  tests/parity/warmups/canaries 180 s. Existing Blargg scripts retain their
  default cycle budgets, per-ROM timeouts and RSS guards.
- Before timing: CPU and memory unit tests and both existing Blargg scripts,
  for interpreter, default JIT, and native AOT where buildable. A logging
  adapter preserves each child stdout/stderr/status before the existing
  scripts remove their temporary logs. Native adapter drops the source-file
  CLI argument and invokes its prebuilt native counterpart; no emulation
  source or gate is changed.
- Compare interpreter/default JIT/AOT stdout bytes, stderr bytes and status at
  requests 0, 500000 and 2000000, and also with `--dump-state` at 500000 and
  2000000. Only complete lines beginning `Time: ` and `Speed: ` are removed;
  preserve those lines separately in the original stdout. Actual cycles come
  from exactly one `Cycles:` line, never the requested limit.
- VM measurement: standard `roms/cpu_instrs.gb`, request 500000 cycles,
  startup-inclusive external monotonic wall from immediately before launching
  `timeout 180 <explicit release binary> dmg.eigs ...` until that child is
  reaped. Python `perf_counter_ns`, resolution recorded in manifest. DMG's
  internal millisecond Time/Speed fields are context, not the external result.
- One unmeasured 500K warmup per VM arm after correctness. No cache flushing;
  results describe warm filesystem caches. Correctness itself warms caches.
- Seven scheduled rounds, no replacements: odd rounds interpreter, JIT,
  identical-JIT-repeat; even rounds identical-JIT-repeat, JIT, interpreter.
  The repeat is the same binary, arguments and environment, with its own
  seven samples. Pair by round; report median of per-round deltas, not a
  ratio of independently aggregated arms.
- AOT: invoke unchanged `aot/k_oracle.sh` with `K_REPS=7`, `K_BIN` fixed,
  `DMG_DIR` fixed and its unchanged budget (BASELINE 0, WINDOW 2000000).
  The oracle pairs baseline then window, subtracts actual reported cycles and
  elapsed times, and measures retired instructions separately as K. Preserve
  each point if the oracle is runnable. If perf or correctness refuses, retain
  the refusal, mark AOT blocked, and publish no substitute speed result. Never
  change perf privileges, the budget, or inject fake measurement points.
- Quiet check before the timing block: a 10 s `/proc/stat` sample with at most
  0.25 busy CPU-equivalents, CPU temperatures below 60 C, and the Phase 2
  handoff complete. Wait and record checks if not quiet; do not stop competing
  work. Host process names are unavailable across the sandbox PID namespace;
  record that observability limit. Capture load, thermal/frequency/power,
  CPU counters, memory and PSI before/after every sample. Use before/after
  counters to report excess host CPU activity, with no polling inside timing.
- Exclusions declared now: nonzero exit, timeout, missing/duplicate/short
  cycle count, normalized output/stderr mismatch, changed binary/ROM hash,
  sanitizer binary, temperature >=70 C or excess host busy CPU >0.50
  CPU-equivalents beyond the child during a run. No statistical outlier
  trimming. Keep every invalid or excluded sample and reason. No retry until
  green; a failed gate blocks that arm and is not rerun. Continue independent
  arms. An arm with <=5 valid samples remains incomplete.
- Summaries: n scheduled/attempted/valid, median wall seconds and derived MHz,
  min/max and IQR (Tukey hinges: median of lower/upper halves excluding the
  median for n=7), and paired VM deltas. A/A establishes this session's noise
  floor; no optimization or historical improvement is claimed. Cross-tier
  windows/scopes differ and are non-comparable. If AOT subtraction is not
  positive or is at/below timing resolution, report unresolved, never MHz.
- Link ouroboros#333 as an independent unresolved instruction-cost issue;
  this receipt neither changes its budget nor resolves that issue.
