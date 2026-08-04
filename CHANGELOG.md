# Changelog

## [Unreleased]

### Debugger — memory panel (#53, second artifact)
- South `hex_view` panel over the live bus (pure reader, whole 64K,
  opens at the stack); click a byte → `DBG_SELECT addr value` from
  `mem_read` directly. Pause seam emits the visible window
  (`DBG_MEMGEOM`/`DBG_MEM`) read straight off the core, independent of
  the widget's render reader — `--plant-mem-fault` corrupts only the
  render leg and the decode oracle must catch it (it does, 1 cell).
- `tests/ui_debug_oracle.py` grew the memory-panel legs: hex cells
  decoded from screenshots vs the `DBG_MEM` seam, a real-pointer byte
  click verified against `DBG_SELECT`, and the planted mem fault.

### Debugger (#53, fleet UI ladder rung 5 slice 3, first artifact)
- `--debug` opens a dock-workspace debugger chrome (needs the dock
  widget — EigenScript main post-v0.37.0): center = live LCD, west =
  registers panel + Pause/Run, Step-instr, Step-frame controls;
  `--break-cycle N` auto-pauses; space/s/f keyboard equivalents
- `src/debug.eigs`: non-inlined single-instruction stepper + canonical
  state dump; `--dump-state` and `--engine debug` on the headless CLI
- `run_frame(cpu, mem)` lifted out of the gfx loop (twin markers moved
  intact) and shared by gfx mode and the chrome's RUN state
- Oracles: `tests/run_debug_equivalence.sh` (hot vs debug engine dump
  byte-diff + a Blargg ROM Passed through the debug engine; CI, any
  pin) and `tests/run_debug_ui_oracle.sh` (registers panel decoded
  back out of real screenshots and byte-diffed against the core dump,
  real-pointer pause/step flow, planted render fault caught; SKIPs
  until the pin carries dock, then self-arms as REQUIRED)

### Accuracy
- STAT register + LCD mode machine and serial-complete IRQ
- Window internal line counter, P1 upper bits, and illegal-opcode hex
  diagnostics; reload-window cap, LCD-off, STOP, and joypad IRQ fixes
- MBC1 mode-1 bank0 remap fix in `fetch8`

### Fixed
- Replaced silent no-op `sort of` with `sort_by` at both record-sort
  sites (sprite X-priority and input-script event ordering)

### Tooling
- Twin gate in CI (`tests/check_twins.sh`) — the inlined hot-loop copies
  must not drift
- Pinned EigenScript runtime bumped v0.23.0 → v0.26.0

## [0.1.0] — 2026-07-01

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
