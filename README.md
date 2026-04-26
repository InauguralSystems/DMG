# DMG

A Game Boy (DMG) emulator written in EigenScript. Built to stress-test the
language with a demanding, spec-precise workload.

## Status

CPU core implemented (SM83 full instruction set including CB prefix).
**Blocked on GAP-DMG-001**: opcode dispatch via if-chain is too slow for
the tree-walking interpreter. A single instruction decode checks ~100+
conditions sequentially. Needs jump table or compiled dispatch.

## Architecture

- `src/cpu.eigs` — Registers, flags, ALU operations, rotate/shift
- `src/memory.eigs` — 64KB address space, MBC1/MBC3, serial capture
- `src/opcodes.eigs` — Full SM83 instruction decoder (256 + 256 CB)
- `dmg.eigs` — Main loop with timer, interrupts, Blargg test harness

## Goal

Pass Blargg's cpu_instrs test ROM, then run Tetris and Pokemon Red.
The real deliverable is the gap analysis — what EigenScript needs to
support interpreter/emulator class workloads.
