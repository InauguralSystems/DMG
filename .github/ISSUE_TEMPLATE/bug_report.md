---
name: Bug Report
about: Report an emulation bug in DMG (a Blargg regression, wrong CPU/PPU/timing behavior, a game misrenders)
title: ""
labels: bug
assignees: ""
---

**Describe the bug**
What went wrong — e.g. a Blargg test that used to pass now fails, a CPU/PPU/timing
result is wrong, or a game misrenders or hangs.

**To reproduce**
Which ROM and how you ran it:
```sh
eigenscript dmg.eigs roms/cpu_instrs.gb --cycles 5000000
# or a suite runner:
tests/run_blargg_cpu_instrs_suite.sh
```

**Expected vs actual**
What the hardware/Blargg output should be vs what DMG produced (include serial
output or a screenshot).

**Environment**
- OS: [e.g., Ubuntu 24.04]
- EigenScript version: [output of `eigenscript --version`]
- DMG version/tag or commit: [e.g. commit sha]

> If the root cause is the EigenScript language, runtime, or JIT itself (a
> primitive is missing or misbehaves), it belongs in the
> [EigenScript repo](https://github.com/InauguralSystems/EigenScript/issues) —
> and it's likely worth a note in [GAPS.md](../../GAPS.md).
