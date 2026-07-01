# Changelog

## [Unreleased]

### Accuracy
- Intra-instruction timer/LCD/APU stepping for `mem_timing` accuracy
- Timer cycle-accounting fix — Blargg `cpu_instrs` aggregate suite now passes
  (alongside `instr_timing` and `mem_timing`)

### Performance
- Deferred bus-tick with inlined post-instruction `bus_flush` and `exec_op`
  in the headless and graphical hot loops
- Headless hot loop lifted into `run_headless_loop` so temporaries land in
  bytecode-frame slots
- Inlined memory access hot path in fetch8 and cpu_mem_read (ROM fast path)
- Inlined set_flags and flag_c out of all ALU operations
- Canary speed: ~1.1 MHz on the T3200 baseline, ~5.2 MHz in the cloud
  devcontainer (above real DMG's 4.19 MHz). Per-host, not comparable across
  machines — see `BASELINE.md`.

### Tooling
- Pinned EigenScript runtime bumped to v0.21.2 (`.devcontainer/Dockerfile`
  `EIGS_REF`)
- Reproducible gfx devcontainer runs the unit tests in CI
- Cloud/Codespace canary baseline recorded in `BASELINE.md`
- Open-source readiness: LICENSE, SECURITY.md, ROM provenance note

### Testing
- Memory/MBC regression test suite (MBC1/3/5 banking, cartridge RAM, echo RAM, DMA)
- Blargg CPU instruction suite runner
- Blargg timing suite runner
- Pokemon Red scripted smoke test
- Bounded graphics smoke test

## [Initial Release]

- Full SM83 CPU core (256 base + 256 CB-prefix opcodes)
- 64KB memory bus with MBC1, MBC3, MBC5 cartridge support
- Timer, LCD, VBlank, and interrupt handling
- PPU rendering (background, window, sprites with priority)
- Joypad input (SDL2 or scripted)
- Dual mode: headless (Blargg ROM testing) and graphical (SDL2)
- 8 language gaps identified and resolved upstream in EigenScript
