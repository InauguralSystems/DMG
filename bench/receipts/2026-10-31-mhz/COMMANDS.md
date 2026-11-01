# Exact execution recipe

Run from `/home/jon/src/wt/dmg-89`. All child argv, selected environment,
UTC boundaries and status are retained in each adjacent JSON; `*.started.json`
reserves the attempt before launching. The Python drivers impose the virtual
memory limit on themselves and all descendants. No command below may be rerun
over an existing attempt. Build logs record the effective compiler commands.

Preparation (performed once):

```sh
mkdir -p .bench-build
printf '*\n' > .bench-build/.gitignore
git clone --shared --no-checkout /home/jon/src/InauguralSystems/EigenScriptEcosystem/EigenScript .bench-build/eigs-dmg
git -C .bench-build/eigs-dmg checkout --detach 546848c0a7123ea7066923ebadb06f0af29af953
git init -q .bench-build/ouroboros
git -C .bench-build/ouroboros remote add origin https://github.com/InauguralSystems/ouroboros.git
git -C .bench-build/ouroboros fetch --depth 1 origin 4afbfdde8b070f9aa196e37a8fb0229c50ee586b
git -C .bench-build/ouroboros checkout --detach FETCH_HEAD
touch .bench-build/eigs-dmg/.git/builder-owned .bench-build/ouroboros/.git/builder-owned
chmod +x bench/receipts/2026-10-31-mhz/capture-runtime.sh
```

Phases, strictly sequential (some phases intentionally take many minutes):

```sh
python3 bench/receipts/2026-10-31-mhz/experiment.py build
python3 bench/receipts/2026-10-31-mhz/experiment.py seal
python3 bench/receipts/2026-10-31-mhz/calibrate.py
python3 bench/receipts/2026-10-31-mhz/experiment.py oracle
python3 bench/receipts/2026-10-31-mhz/experiment.py correct
python3 bench/receipts/2026-10-31-mhz/experiment.py parity
python3 bench/receipts/2026-10-31-mhz/experiment.py measure
python3 bench/receipts/2026-10-31-mhz/summarize.py
```

`oracle` here only permits a known instrument-refusal path. The frozen perf
capability probe must have failed. If perf becomes available this runner refuses
before launching AOT measurement, because unchanged `k_oracle.sh` cleans its
per-point temporary logs and a raw-point retention adapter is still needed.
Do not interpret that as an AOT timing result.

The canonical VM commands, after environment cleaning, are:

```sh
ulimit -v 1500000
EIGS_JIT_OFF=1 timeout --signal=TERM --kill-after=5 180 /home/jon/src/wt/dmg-89/.bench-build/eigs-dmg/build/release/eigenscript /home/jon/src/wt/dmg-89/dmg.eigs /home/jon/src/wt/dmg-89/roms/cpu_instrs.gb --cycles 500000
# Default JIT: identical argv, EIGS_JIT_OFF absent.
```

Correctness uses the same binary and environment switch. The lossless adapter
is passed as `EIGENSCRIPT` to the unchanged `tests/run_blargg_cpu_instrs_suite.sh`
and `tests/run_blargg_timing_suite.sh`. Separate diagnostic-only 500K runs enable
`EIGS_JIT_STATS=1` to witness default JIT engagement and interpreter disablement;
that switch is absent from every measured sample.

For AOT, the refusal-only attempt runs unchanged `aot/k_oracle.sh` with
`DMG_DIR` this worktree, `K_REPS=7` and the runtime/source paths above.
`K_BIN` deliberately names the nonexistent receipt path
`aot-oracle/MEASUREMENT_DISABLED`: this interlock ensures that a surprise
change in perf access cannot start a real measurement whose point logs would
be deleted. Expected failure is earlier, in the oracle's own perf check.
The planned measurement binary was `.bench-build/dmg-aot` (absolute).
No `K_BUDGET` override; no fake points; default
BASELINE 0/WINDOW 2000000 and 1800 s point timeout. A future runnable collection
must preserve all seven baseline/window stdout/stderr/perf/elapsed/actual-cycle
tuples before the oracle's cleanup, retain any verdict failure, and repeat the
unchanged native binary as a separate A/A control. That work is blocked here.
