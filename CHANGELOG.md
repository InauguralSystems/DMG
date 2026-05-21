# Changelog

## [Unreleased]

### Performance
- Inlined memory access hot path in fetch8 and cpu_mem_read (ROM fast path)
- Inlined set_flags and flag_c out of all ALU operations
- Current speed: 0.177 MHz through EigenScript bytecode VM

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
