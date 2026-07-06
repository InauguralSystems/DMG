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
2. **A forcing function for EigenScript.** Ten `GAP-DMG-NNN`
   entries have landed upstream because DMG demanded them
   (`dispatch` table, native bitwise operators, compound assign,
   buffer iteration, sign extension, sort — later hardened to
   raise on non-scalar lists — a loop-condition memory leak fix,
   and the `hex` builtin). See `GAPS.md`.

Sibling stress repo to EigenGauntlet, EigenMiniSat, EigenRegex,
and Tidepool.

## Toolchain

EigenScript is **not** vendored. Pin **v0.13.0 minimum**; **v0.27.0**
is the current tested release (`.devcontainer/Dockerfile` `EIGS_REF`).
Two binaries matter:

```bash
# Headless (no SDL2 needed) — Blargg ROMs, tests, benchmarks
EIGS=${EIGENSCRIPT_BIN:-../EigenScript/src/eigenscript}

# Graphical (requires libsdl2-dev; built with `make gfx`)
EIGS_GFX=${EIGENSCRIPT_GFX:-../EigenScript/src/eigenscript-gfx}
```

Headless is enough for `tests/test_*.eigs`, all Blargg suites, and
the Pokemon Red scripted smoke. `--gfx` mode and `run_gfx_smoke.sh`
need the gfx binary.

## Run / test

```bash
EIGS=../EigenScript/src/eigenscript

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
| `src/lcd.eigs` | PPU mode machine + STAT (0xFF41) — lazy mode, event-armed HBlank source |
| `src/opcodes.eigs` | Full SM83 decoder via `dispatch` table |
| `src/ppu.eigs` | BG / window / sprite rendering with priority |
| `src/joypad.eigs` | Button state, FF00 register, interrupt-on-press |
| `tests/test_cpu.eigs` | 17 CPU unit tests |
| `tests/test_memory.eigs` | MBC1/3/5, cartridge RAM, echo RAM, DMA |
| `tests/test_lcd.eigs` | STAT machine: modes, sources, LYC, LCD off/on |
| `tests/test_ppu.eigs` | Sprite X-priority rendering (#26) |
| `tests/test_joypad.eigs` | P1 column-gated interrupt (#33) |
| `tests/run_input_script_smoke.sh` | Input-script cycle-order smoke (#25) |
| `tests/check_twins.sh` | Twin gate — the inlined hot-loop copies must not drift (#20) |
| `tests/run_blargg_*.sh` | Blargg suite runners (cpu_instrs, timing) |
| `tests/run_gfx_smoke.sh` | Bounded SDL/dummy-driver gfx smoke |
| `tests/run_pokemon_red_smoke.sh` | Scripted Pokemon Red smoke |
| `roms/` | Blargg ROMs + `pokemon-red.gb` (local, gitignored) |
| `GAPS.md` | `GAP-DMG-NNN` ledger — ten resolved upstream |
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
- **The PPU mode is computed, not stepped** (`src/lcd.eigs`). STAT
  reads derive mode from (LY, lcd_counter); LCD events run once per
  line, and the intra-line HBlank boundary (cycle 252) is scheduled
  only while FF41 bit 3 is armed. Event-stepping every mode boundary
  cost ~2% on the canary — don't regress to it.

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
- **The inlined hot-loop copies are gated, not trusted.** The
  bus-tick, halted-skip, and inlined-exec bodies exist in multiple
  hand-synchronized copies (deliberate — a shared function there
  costs measurably, and even loop-body bytecode *growth* costs ~3%
  on the L1i-bound canary). Each copy is wrapped in `# twin:`
  markers; `tests/check_twins.sh` (CI) diffs the normalized copies
  and fails on drift, which has shipped real bugs twice (#27, #28).
  Editing one copy means editing them all — the gate tells you when
  you've missed one. Keep the `map` renames on the markers accurate.
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
