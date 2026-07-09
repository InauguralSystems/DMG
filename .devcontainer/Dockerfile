# Self-contained dev/CI image for DMG (a Game Boy emulator in EigenScript).
#
# DMG runs .eigs directly against the runtime and has both a headless mode
# (Blargg serial-output tests) and an SDL2 --gfx mode. This image carries a
# full EigenScript source tree at a pinned tag, builds the gfx variant (a
# strict superset of headless — runs the unit tests fine), puts it on PATH, and
# ships SDL2 + Xvfb so a Codespace can run the emulator graphically. CI uses
# the same image for the ROM-free unit tests; the tag IS the version pin.
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        libsdl2-2.0-0 \
        xvfb \
 && rm -rf /var/lib/apt/lists/*

# Full EigenScript source at the pinned tag; build the gfx variant (SDL2 is
# dlopen'd, so building needs no -dev headers). stdlib resolves at ../lib.
ARG EIGS_REF=v0.28.0
RUN git clone --depth 1 --branch "${EIGS_REF}" \
        https://github.com/InauguralSystems/EigenScript.git /opt/eigenscript \
 && make -C /opt/eigenscript gfx CC=gcc

ENV EIGS_DIR=/opt/eigenscript
ENV PATH="/opt/eigenscript/src:${PATH}"
WORKDIR /workspaces/DMG
