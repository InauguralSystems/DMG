# Test ROMs

These are **Blargg's Game Boy test ROMs**, authored by Shay Green ("blargg"):

- `cpu_instrs.gb` and `individual/*.gb` — CPU instruction correctness
- `instr_timing.gb` — instruction timing
- `mem_timing.gb`, `mem_timing-2/`, `mem_timing_individual/` — memory-access timing
- `interrupt_time/` — interrupt timing

They are freely redistributable diagnostic ROMs, widely bundled by open-source
Game Boy emulators for automated conformance testing. They are **not** commercial
game ROMs and **not** a copyrighted boot ROM.

They are included here solely to drive DMG's automated Blargg conformance tests
(see `tests/run_blargg_*.sh`). No copyrighted game data ships with this repo.
