## What this is

DMG is a **Game Boy (DMG) emulator written in EigenScript** —
full SM83 CPU, 64KB bus with MBC1/3/5 banking, timer/LCD/VBlank,
interrupt handling, joypad, and PPU rendering. Two run modes:
headless (Blargg test ROMs via serial port capture) and graphical
(SDL2 window).

Two missions, same as the other stress repos:

1. A real, spec-precise emulator: all Blargg `cpu_instrs` and
   `instr_timing` / `mem_timing` suites green, Tetris and Pokemon
   Red boot under `--gfx`.
2. **A forcing function for EigenScript.** Eight `GAP-DMG-NNN`
   primitives have landed upstream because DMG demanded them
   (`dispatch` table, native bitwise operators, compound assign,
   buffer iteration, sign extension, sort, and a loop-condition
   memory leak fix). See `GAPS.md`.

Sibling stress repo to EigenGauntlet, EigenMiniSat, EigenRegex,
and Tidepool.

## Toolchain

EigenScript is **not** vendored. Pin **v0.13.0 minimum**; **v0.14.2**
is the current tested release. Two binaries matter:

```bash
# Headless (no SDL2 needed) — Blargg ROMs, tests, benchmarks
EIGS=${EIGENSCRIPT_BIN:-/home/jon/EigenScript/src/eigenscript}

# Graphical (requires libsdl2-dev; built with `make gfx`)
EIGS_GFX=${EIGENSCRIPT_GFX:-/home/jon/EigenScript/src/eigenscript-gfx}
```

Headless is enough for `tests/test_*.eigs`, all Blargg suites, and
the Pokemon Red scripted smoke. `--gfx` mode and `run_gfx_smoke.sh`
need the gfx binary.

## Run / test

```bash
EIGS=/home/jon/EigenScript/src/eigenscript

# CPU + memory unit tests
$EIGS tests/test_cpu.eigs
$EIGS tests/test_memory.eigs

# Blargg cpu_instrs suite (individual + aggregate, ~4 min wall at full)
tests/run_blargg_cpu_instrs_suite.sh
# Tunables: BLARGG_CPU_INSTRS_MODE=all|aggregate|individual,
#           BLARGG_CPU_INSTRS_AGGREGATE_CYCLES,
#           BLARGG_CPU_INSTRS_INDIVIDUAL_CYCLES, *_TIMEOUT_SECONDS

# Blargg instr_timing + mem_timing (the accuracy-sensitive ones)
tests/run_blargg_timing_suite.sh

# Standard regression-tracking canary — 500K cycles, low variance
$EIGS dmg.eigs roms/cpu_instrs.gb --cycles 500000

# Optional Pokemon Red scripted smoke (ROM is not committed)
POKEMON_RED_ROM=/path/to/pokemon-red.gb tests/run_pokemon_red_smoke.sh

# Bounded gfx smoke (uses SDL_VIDEODRIVER=dummy by default)
EIGENSCRIPT_GFX=/path/to/eigenscript-gfx tests/run_gfx_smoke.sh

# Play
$EIGS_GFX dmg.eigs roms/pokemon-red.gb --gfx --scale 3 --frameskip 2
```

Keys: arrows = D-pad, Z = A, X = B, Return = Start, Backspace =
Select, Escape = quit.

## Layout

| Path | Role |
|---|---|
| `dmg.eigs` | Main loop, timer, interrupts, headless + gfx dispatch |
| `src/cpu.eigs` | Registers, flags, ALU, rotate/shift, DAA |
| `src/memory.eigs` | 64KB bus, MBC1/3/5, lazy bank switching, DMA |
| `src/opcodes.eigs` | Full SM83 decoder via `dispatch` table |
| `src/ppu.eigs` | BG / window / sprite rendering with priority |
| `src/joypad.eigs` | Button state, FF00 register, interrupt-on-press |
| `tests/test_cpu.eigs` | 14 CPU unit tests |
| `tests/test_memory.eigs` | MBC1/3/5, cartridge RAM, echo RAM, DMA |
| `tests/run_blargg_*.sh` | Blargg suite runners (cpu_instrs, timing) |
| `tests/run_gfx_smoke.sh` | Bounded SDL/dummy-driver gfx smoke |
| `tests/run_pokemon_red_smoke.sh` | Scripted Pokemon Red smoke |
| `roms/` | Blargg ROMs + `pokemon-red.gb` (local, gitignored) |
| `GAPS.md` | `GAP-DMG-NNN` ledger — eight resolved upstream |
| `BASELINE.md` | T3200 timings with methodology + JIT contribution |

## Architecture notes

- **`dispatch of [table, key, arg]`** is the opcode core. SM83 has
  256 + 256 CB-prefix entries; linear if/elif was the original
  blocker (GAP-DMG-001).
- **Deferred bus-tick + intra-instruction stepping.** `mem_timing`
  accuracy requires timer/lcd/apu stepping *inside* the instruction,
  not just after. The recovery move was inlining `bus_flush` and
  `exec_op` into the hot loop so the per-instruction overhead got
  paid back. Don't undo this without rerunning the timing suite.
- **Memory access is inlined in `fetch8` and `cpu_mem_read`**
  along the ROM fast path. Same hot-path discipline as
  EigenMiniSat's `Inline tiny accessors` pattern.
- **ALU flags are inlined out of every op** (`set_flags`, `flag_c`).
  Don't re-introduce a flag-setter helper inside the ALU branches.
- **MBC1 / MBC3 / MBC5** banking is lazy: bank registers update
  pointers, but the resolved offset is recomputed only when the
  bus actually reads/writes the banked region.

## Hard-won rules

- **Friction → GAPS.md, not local workaround.** Every entry in
  GAPS.md became an upstream EigenScript feature — that's the
  whole point of the repo. If a workaround would be cleaner with
  a builtin, log it.
- **Inline 1-call/iter first in hot loops** (DMG playbook). Lift
  helpers out, hoist module globals to function locals so the
  v0.12.0+ JIT's inline caches fire. Same pattern used by
  EigenMiniSat and Tidepool's `game_tick`.
- **Cycle-accuracy is non-negotiable for timing ROMs.** If a perf
  change makes `instr_timing` or `mem_timing` regress, the perf
  change is wrong, not the test.
- **n=5 for any perf claim, with the canary methodology.** The
  500K-cycle `cpu_instrs.gb` probe is the standard regression
  canary (low variance, startup-dominated, comparable across
  sessions). Aggregate suite is opcode-coverage-heavy and has a
  different shape — *don't* substitute one for the other (see
  `feedback_methodology_match`).
- **Don't compare numbers across hosts.** `BASELINE.md` is T3200;
  every modern-HW figure in older changelogs was on a different
  machine.

## Current state

All Blargg suites pass (cpu_instrs aggregate + individual,
instr_timing, mem_timing). Cycle accuracy holds with the
intra-instruction stepping. T3200 cpu_instrs canary at ~1.02–1.10
MHz on v0.12.0 with deferred bus-tick + inlined exec_op. JIT
contribution measured on the canary; aggregate suite is too L1i-
constrained for JIT to dominate (`feedback_proxy_vs_real_bench`).

## Gotchas

- `gmon.out`, `massif.out.*`, `jit_stops.log` are profiling
  artifacts — don't commit them.
- `roms/pokemon-red.gb` is gitignored and pulled per-host. Blargg
  ROMs are committed (public domain test ROMs).
- The gfx smoke uses `SDL_VIDEODRIVER=dummy` by default, so it
  runs in CI without a display. Override only when actually
  watching pixels.
- The intra-instruction stepping in `exec_op` is structured so
  the inner timer/lcd/apu calls are *the* per-cycle bottleneck.
  Adding an indirection there is multiplicative — measure before
  refactoring.
