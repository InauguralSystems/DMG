# DMG

A Game Boy (DMG) emulator written in EigenScript. Built to stress-test the
language with a demanding, spec-precise workload — the real deliverable is
the gap analysis (`GAPS.md`), where every `GAP-DMG-NNN` is a primitive that
landed upstream because the emulator demanded it.

## Status

CPU core implemented (SM83 full instruction set including CB prefix), with
opcode dispatch via the new `dispatch` builtin (GAP-DMG-001 resolved),
native bitwise operators (GAP-DMG-004 resolved), typed-buffer memory bank,
and timer / LCD / VBlank timing. First Blargg `cpu_instrs` output captured
via the serial port. Memory growth on multi-million-cycle runs is partially
mitigated (GAP-DMG-003) — see `GAPS.md` for the remaining work.

## Architecture

- `src/cpu.eigs` — Registers, flags, ALU operations, rotate/shift
- `src/memory.eigs` — 64KB address space, MBC1/MBC3, serial capture
- `src/opcodes.eigs` — Full SM83 instruction decoder (256 + 256 CB) via `dispatch`
- `dmg.eigs` — Main loop with timer, interrupts, Blargg test harness

## Goal

Pass Blargg's `cpu_instrs` test ROM, then run Tetris and Pokemon Red.
Each blocker found along the way becomes a language gap, and each language
gap becomes the next upstream EigenScript feature.
