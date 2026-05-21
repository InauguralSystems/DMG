# Contributing

DMG is a Game Boy emulator written in [EigenScript](https://github.com/InauguralSystems/EigenScript).
It serves as a performance stress test for the EigenScript runtime.

## Getting Started

1. Build EigenScript:
   ```
   git clone https://github.com/InauguralSystems/EigenScript.git
   cd EigenScript && make build && make install
   ```

2. Clone this repo and run tests:
   ```
   git clone https://github.com/InauguralSystems/DMG.git
   cd DMG
   eigenscript tests/test_cpu.eigs
   eigenscript tests/test_memory.eigs
   ```

3. Run the emulator (headless, with Blargg test ROM):
   ```
   eigenscript dmg.eigs roms/cpu_instrs.gb --cycles 5000000
   ```

## Project Structure

- `dmg.eigs` — main loop (timer, LCD, interrupts, headless + graphical modes)
- `src/cpu.eigs` — SM83 CPU core (registers, ALU, flags)
- `src/memory.eigs` — 64KB address space, MBC1/3/5 banking
- `src/opcodes.eigs` — 512 opcode handlers via dispatch table
- `src/ppu.eigs` — pixel rendering (BG, window, sprites)
- `src/joypad.eigs` — button input
- `tests/` — CPU unit tests, MBC regression tests, Blargg test runners

## License

MIT. See [LICENSE](LICENSE).
