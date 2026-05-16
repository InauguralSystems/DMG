# Next Session Handoff

Date: 2026-05-16

## Where We Left Off

DMG `master` now includes PR #5:

- PR: https://github.com/InauguralSystems/DMG/pull/5
- Merge commit: `3ebaa10`
- Added headless Pokemon Red scripted input.
- Added headless render probe coverage.
- Added bounded real SDL/gfx smoke coverage through `--gfx-frames`.

Current DMG branch:

- Branch: `codex/dmg-blargg-timing-suite`
- Draft PR: https://github.com/InauguralSystems/DMG/pull/6
- Timing-suite commit: `6f18d25 Add Blargg timing suite runner`
- Status: clean except local-only untracked ROM/profiler files:
  - `roms/pokemon-red.gb`
  - `roms/Pokemon - Red Version (USA, Europe) (SGB Enhanced).gb`
  - `massif.out.130480`

Current EigenScript note:

- EigenScript still has a separate draft PR open for AST identifier hash caching:
  https://github.com/InauguralSystems/EigenScript/pull/114
- Local EigenScript `main` has an unrelated `Makefile` edit and is ahead/behind `org/main`.
- Do not touch EigenScript unless the next DMG run exposes a root language/runtime issue.

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
- peak RSS: `18816 KB`

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
- peak RSS: `10752 KB`

CPU tests:

```bash
/home/jon/EigenScript/src/eigenscript tests/test_cpu.eigs
```

Passed all CPU unit tests.

## Next Session Plan

1. Confirm PR #6 state:

```bash
cd /home/jon/DMG
git status -sb
gh pr view 6 --json number,title,url,isDraft,mergeStateStatus,statusCheckRollup
```

2. If still clean, mark PR #6 ready and merge it into `master`.

3. Sync local `master` after merge:

```bash
git fetch origin
git switch master
git merge --ff-only origin/master
```

4. Start the next Blargg bucket. The likely next target is durable CPU instruction ROM coverage:

- run the aggregate `roms/cpu_instrs.gb`
- run all committed individual ROMs in `roms/individual/01.gb` through `roms/individual/11.gb`
- add a serial runner with timeout and RSS guard, similar to `tests/run_blargg_timing_suite.sh`

5. If any individual CPU ROM fails:

- reproduce with a single-ROM command and a bounded cycle count
- inspect the failing serial output or Blargg RAM result
- fix the root cause in DMG or EigenScript, not by bypassing the test
- only change EigenScript if the failure is a language/runtime bug

6. Keep long emulator runs serial. Do not parallelize ROM stress runs on this machine; earlier memory pressure caused freezes.

## Useful Commands

Single ROM:

```bash
timeout 180s /home/jon/EigenScript/src/eigenscript dmg.eigs roms/cpu_instrs.gb --cycles 50000000
```

Pokemon smoke:

```bash
tests/run_pokemon_red_smoke.sh
```

Timing suite:

```bash
tests/run_blargg_timing_suite.sh
```

Gfx smoke:

```bash
EIGENSCRIPT_GFX=/home/jon/EigenScript/src/eigenscript tests/run_gfx_smoke.sh
```
