# Security Policy

`DMG` is a Game Boy (DMG) emulator written entirely in pure EigenScript. It opens
no network sockets. It does take one piece of external input — a Game Boy ROM file
loaded from disk — so malformed-ROM handling (a crash or hang on a truncated or
hostile ROM) is the one thing worth a report. The realistic attack surface is
otherwise small, but reports are welcome.

## Reporting a vulnerability

Please report security issues privately rather than in a public issue — via
[GitHub private vulnerability reporting](https://github.com/InauguralSystems/DMG/security/advisories/new)
or by contacting the maintainer at the address on the
[InauguralSystems](https://github.com/InauguralSystems) profile
(`contact@inauguralsystems.com`, subject prefix `[SECURITY]`). Include the ROM or
steps to reproduce and the affected EigenScript version.

## Scope

- Issues in the EigenScript interpreter, runtime, or JIT belong in the
  [EigenScript](https://github.com/InauguralSystems/EigenScript) repository, which
  has its own security process.
- `DMG`'s own scope is the `.eigs` emulator sources and its handling of the ROM
  file it loads.

## Supported versions

The latest commit on `master` is supported. `DMG` tracks a pinned EigenScript
version (see `.devcontainer/Dockerfile`'s `EIGS_REF`); run against that pin or
newer.
