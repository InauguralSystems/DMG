# DMG

A Game Boy (DMG) emulator written in EigenScript. Built to stress-test the
language with a demanding, spec-precise workload — the real deliverable is
the gap analysis (`GAPS.md`), where every `GAP-DMG-NNN` is a primitive that
landed upstream because the emulator demanded it.

## Status

Full SM83 CPU core (256 + 256 CB-prefix opcodes), 64KB memory bus with
MBC1/MBC3 bank switching, timer/LCD/VBlank timing, interrupt handling,
joypad input, and PPU rendering (background, window, sprites with priority).

Runs in two modes:
- **Headless**: Blargg test ROMs via serial port capture
- **Graphical**: SDL2 window with keyboard input (`--gfx`)

8 language gaps found and resolved upstream (see `GAPS.md`), including
dispatch tables, native bitwise operators, compound assignment, buffer
iteration, sign extension, sort, and loop condition memory leak fixes.

## Architecture

- `src/cpu.eigs` — Registers, flags, ALU operations, rotate/shift, DAA
- `src/memory.eigs` — 64KB address space, MBC1/MBC3, lazy bank switching, DMA
- `src/opcodes.eigs` — Full SM83 instruction decoder via `dispatch`
- `src/ppu.eigs` — Pixel Processing Unit: BG/window/sprite rendering
- `src/joypad.eigs` — Button state, FF00 register, interrupt on press
- `dmg.eigs` — Main loop, timer, interrupts, graphical + headless modes
- `tests/test_cpu.eigs` — 14 CPU unit tests

## Usage

```
# Headless (Blargg tests)
eigenscript dmg.eigs roms/cpu_instrs.gb --cycles 50000000

# Optional Pokemon Red smoke test (ROM is local-only, not committed)
POKEMON_RED_ROM=/path/to/pokemon-red.gb tests/run_pokemon_red_smoke.sh
# Tunables: POKEMON_RED_CHECKPOINTS, POKEMON_RED_TIMEOUT_SECONDS, POKEMON_RED_MAX_RSS_KB
# Back-compat single budget: POKEMON_RED_CYCLES=5000000 tests/run_pokemon_red_smoke.sh

# Graphical
eigenscript dmg.eigs roms/pokemon-red.gb --gfx --scale 3 --frameskip 2
```

Keys: arrows = D-pad, Z = A, X = B, Return = Start, Backspace = Select, Escape = quit.

## Goal

Pass Blargg's `cpu_instrs` test ROM, then run Tetris and Pokemon Red.
Each blocker found along the way becomes a language gap, and each language
gap becomes the next upstream EigenScript feature.
