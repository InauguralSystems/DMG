# Next Session Handoff

Date: 2026-05-16

## Where We Left Off

DMG `master` now includes PR #5:

- PR: https://github.com/InauguralSystems/DMG/pull/5
- Merge commit: `3ebaa10`
- Added headless Pokemon Red scripted input.
- Added headless render probe coverage.
- Added bounded real SDL/gfx smoke coverage through `--gfx-frames`.

DMG `master` also includes PR #6:

- PR: https://github.com/InauguralSystems/DMG/pull/6
- Merge commit: `a507221`
- Timing-suite commit: `6f18d25 Add Blargg timing suite runner`
- Added `tests/run_blargg_timing_suite.sh`.
- Added README documentation for the Blargg timing-suite command.

DMG `master` also includes PR #8:

- PR: https://github.com/InauguralSystems/DMG/pull/8
- Merge commit: `99ef673`
- Added `tests/run_blargg_cpu_instrs_suite.sh`.
- Verified aggregate and individual Blargg CPU instruction ROM coverage.

Current branch adds memory/MBC durability:

- MBC1 high ROM bits, RAM banking mode, and cartridge RAM storage.
- MBC3 cartridge RAM banking.
- MBC5 9-bit ROM banking and RAM bank selection.
- Blargg RAM-result reporting now reads through the memory bus, so MBC cartridge RAM results are visible.
- New `tests/test_memory.eigs` regression suite.

Current local DMG note:

- This branch is memory/MBC follow-up work after PR #8.
- Status: clean except local-only untracked ROM/profiler files:
  - `roms/pokemon-red.gb`
  - `roms/Pokemon - Red Version (USA, Europe) (SGB Enhanced).gb`
  - `massif.out.130480`

Current EigenScript note:

- Use `/home/jon/EigenScript/src/eigenscript` for current-root validation.
- Local EigenScript `main` may still have the intentional local `Makefile` edit.
- Do not touch EigenScript unless a DMG run exposes a root language/runtime issue.

## Validation Already Completed

Pokemon Red smoke:

```bash
tests/run_pokemon_red_smoke.sh
```

Passed with local `roms/pokemon-red.gb`:

- checkpoints: `1000000 3000000 5000000 10000000 25000000`
- input events: `6/6`
- final cycles: `25000000`
- final PC: `20863`
- render peak: `nonzero=12325 unique=4`
- final render hash: `680870503`
- peak RSS: `19456 KB`

Bounded gfx smoke:

```bash
make gfx
EIGENSCRIPT_GFX=/home/jon/EigenScript/src/eigenscript tests/run_gfx_smoke.sh
```

Passed:

- frames: `2`
- cycles: `140448`
- runs with `SDL_VIDEODRIVER=dummy` by default

Blargg timing suite:

```bash
tests/run_blargg_timing_suite.sh
```

Passed:

- `instr_timing`, cycles `3000004`
- `mem_timing`, cycles `7000008`
- `mem_timing_2`, cycles `12000004`
- `interrupt_time`, cycles `3000000`
- peak RSS: `11136 KB`

Blargg CPU instruction aggregate:

```bash
BLARGG_CPU_INSTRS_MODE=aggregate tests/run_blargg_cpu_instrs_suite.sh
```

Passed:

- `cpu_instrs`, cycles `225000004`
- peak RSS: `11008 KB`

CPU tests:

```bash
/home/jon/EigenScript/src/eigenscript tests/test_cpu.eigs
```

Passed all CPU unit tests.

Memory/MBC tests:

```bash
/home/jon/EigenScript/src/eigenscript tests/test_memory.eigs
```

Passed:

- MBC1 ROM low/high bits and RAM banking mode
- MBC1 cartridge RAM enable/bank preservation
- MBC3 cartridge RAM banking
- MBC5 9-bit ROM banking and RAM bank 15 preservation
- Echo RAM and DMA transfer

New CPU instruction suite runner:

```bash
tests/run_blargg_cpu_instrs_suite.sh
```

Runs the aggregate `roms/cpu_instrs.gb` and every committed individual
`roms/individual/01.gb` through `roms/individual/11.gb` serially with separate
aggregate/individual cycle and timeout guards plus an RSS guard. Use
`BLARGG_CPU_INSTRS_MODE=aggregate` or `BLARGG_CPU_INSTRS_MODE=individual` for
targeted reruns.

## Next Session Plan

1. Sync local `master` to the latest GitHub state:

```bash
cd /home/jon/DMG
git status -sb
git fetch origin
git switch master
git merge --ff-only origin/master
```

2. Confirm the merged PR state if needed:

```bash
gh pr view 6 --json state,mergedAt,mergeCommit,url
```

3. Run the memory/MBC regression suite after any memory-bus edit:

```bash
/home/jon/EigenScript/src/eigenscript tests/test_memory.eigs
```

Then run `tests/run_blargg_timing_suite.sh` because the Blargg RAM-result path
depends on cartridge RAM visibility.

4. If any CPU or memory ROM fails:

- reproduce with a single-ROM command and a bounded cycle count
- inspect the failing serial output or Blargg RAM result
- fix the root cause in DMG or EigenScript, not by bypassing the test
- only change EigenScript if the failure is a language/runtime bug

5. Next high-signal target after this branch: save/RAM persistence and PPU/OAM edge-case regressions. Keep long emulator runs serial; earlier memory pressure caused freezes.

## Useful Commands

Single ROM:

```bash
timeout 1500s /home/jon/EigenScript/src/eigenscript dmg.eigs roms/cpu_instrs.gb --cycles 260000000
```

Pokemon smoke:

```bash
tests/run_pokemon_red_smoke.sh
```

Timing suite:

```bash
tests/run_blargg_timing_suite.sh
```

CPU instruction suite:

```bash
tests/run_blargg_cpu_instrs_suite.sh
```

Memory/MBC unit tests:

```bash
/home/jon/EigenScript/src/eigenscript tests/test_memory.eigs
```

Gfx smoke:

```bash
EIGENSCRIPT_GFX=/home/jon/EigenScript/src/eigenscript tests/run_gfx_smoke.sh
```
