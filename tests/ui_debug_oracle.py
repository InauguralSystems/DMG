#!/usr/bin/env python3
"""Render-decode + mouse oracle for the DMG debugger chrome (#53).

Two independent paths that must agree, per the fleet UI-oracle standard:

  core   = the chrome's own stdout state dump (=== STATE DUMP === blocks,
           printed by the same formatter --dump-state uses — and gated
           byte-identical against the headless hot engine by
           run_debug_equivalence.sh)
  render = a screenshot of the registers panel, DECODED back into text
           from the pixels via a glyph atlas built from real rendered
           output (tests/atlas_app.eigs) — never a golden image.

If the panel drops a line, shows a stale value, or paints the wrong
glyph, the decode diverges from the dump and this fails — even though
panel and dump share the formatter, because the render+decode legs are
independent. The checker itself is validated by --plant-render-fault:
a run whose PANEL lies (PC=DEAD, first line dropped) while the dump
stays truthful MUST be caught.

The mouse phase drives the REAL flow with real pointer input (xdotool
mousemove/click): hover Step -> click Step (new dump, CYC advances,
decode matches), click-away on the LCD (no dump may appear), click Run
then Pause (resume/pause round-trip, decode matches again).

Assumes an X display (CI wraps in xvfb-run). Requires the gfx build
(EIGENSCRIPT env), xdotool, xwd, PIL. The registers panel is a
code_view: scale-1 glyphs on a 6px advance, 18px line pitch, text
origin (+4, +2) inside the panel body rect reported by DBG_GEOM.
"""
import os, re, struct, subprocess, sys, tempfile, time

from PIL import Image

EIGS = os.environ.get("EIGENSCRIPT", "eigenscript")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROM = os.path.join(REPO, "roms", "cpu_instrs.gb")
ENV = dict(os.environ, SDL_VIDEODRIVER="x11",
           EIGS_GFX_FONT="/nonexistent/force-bitmap.ttf")

CELL_W, GLYPH_H, LINE_H = 6, 7, 18   # code_view @ scale 1
TEXT_DX, TEXT_DY = 4, 2              # text origin inside the panel body
INK = lambda r, g, b: min(r, g, b) > 130
DUMP_PANEL_LINES = 11                # panel shows the dump head, not SERLEN/MEMSUM
CHARSET = "".join(chr(c) for c in range(33, 127))


def xwd_to_image(path):
    d = open(path, "rb").read()
    f = struct.unpack(">25I", d[:100])
    hs, pw, ph, bpl, ncolors = f[0], f[4], f[5], f[12], f[19]
    off = hs + ncolors * 12
    img = Image.new("RGB", (pw, ph))
    px = img.load()
    for y in range(ph):
        row = off + y * bpl
        for x in range(pw):
            p = struct.unpack_from("<I", d, row + x * 4)[0]
            px[x, y] = ((p >> 16) & 255, (p >> 8) & 255, p & 255)
    return img


def wait_window(title, timeout=30):
    t0 = time.time()
    while time.time() - t0 < timeout:
        r = subprocess.run(["xdotool", "search", "--name", title],
                           capture_output=True, text=True, env=ENV)
        wids = r.stdout.split()
        if wids:
            return wids[0]
        time.sleep(0.3)
    raise RuntimeError("window %r never appeared" % title)


def screenshot(wid, tmp, tries=25):
    """xwd until the frame has ink (cold presents race, transient fails ok)."""
    path = os.path.join(tmp, "shot.xwd")
    for _ in range(tries):
        r = subprocess.run(["xwd", "-id", wid, "-out", path], env=ENV,
                           capture_output=True)
        if r.returncode == 0:
            img = xwd_to_image(path)
            px = img.load()
            if any(sum(px[x, y]) > 90 for y in range(0, img.size[1], 17)
                   for x in range(0, img.size[0], 13)):
                return img
        time.sleep(0.4)
    raise RuntimeError("no frame with content from window " + wid)


def kill_window(wid):
    subprocess.run(["xdotool", "windowkill", wid], env=ENV, capture_output=True)


def cell_sig(px, cx, cy):
    sig = 0
    for dy in range(GLYPH_H):
        for dx in range(CELL_W):
            if INK(*px[cx + dx, cy + dy]):
                sig |= 1 << (dy * CELL_W + dx)
    return sig


def build_atlas(tmp):
    """Render the charset via atlas_app.eigs and cut per-glyph signatures."""
    proc = subprocess.Popen([EIGS, os.path.join(REPO, "tests", "atlas_app.eigs")],
                            env=ENV, cwd=REPO,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wid = wait_window("DMG atlas")
        img = screenshot(wid, tmp)
        px = img.load()
        atlas = {}
        for i, ch in enumerate(CHARSET):
            row, col = divmod(i, 47)   # two lines of 47 chars
            sig = cell_sig(px, TEXT_DX + col * CELL_W, TEXT_DY + row * LINE_H)
            if sig:
                atlas.setdefault(sig, ch)
        kill_window(wid)
    finally:
        proc.terminate()
        proc.wait(timeout=10)
    if len(atlas) < 80:
        raise RuntimeError("atlas too small (%d glyphs) — wrong grid?" % len(atlas))
    return atlas


def decode_panel(img, atlas, rx, ry, rw):
    """Decode the registers panel rect back to text lines."""
    px = img.load()
    ncols = (rw - TEXT_DX - 4) // CELL_W
    lines = []
    for li in range(DUMP_PANEL_LINES):
        cy = ry + TEXT_DY + li * LINE_H
        if cy + GLYPH_H >= img.size[1]:
            break
        out = []
        for col in range(ncols):
            cx = rx + TEXT_DX + col * CELL_W
            if cx + CELL_W >= img.size[0]:
                break
            sig = cell_sig(px, cx, cy)
            out.append(atlas.get(sig, " " if sig == 0 else "?"))
        lines.append("".join(out).rstrip())
    return lines


class Chrome:
    """One --debug session: stdout tailing, geometry, dumps, clicks."""

    def __init__(self, tmp, extra_args):
        self.log = os.path.join(tmp, "chrome.log")
        self.f = open(self.log, "w")
        self.proc = subprocess.Popen(
            [EIGS, "dmg.eigs", ROM, "--debug", "--scale", "2"] + extra_args,
            env=ENV, cwd=REPO, stdout=self.f, stderr=subprocess.STDOUT)
        self.tmp = tmp
        self.wid = wait_window("DMG debugger")
        # Client-area origin via xwininfo: xdotool's getwindowgeometry
        # reports the FRAME origin under a reparenting WM, which put every
        # click one titlebar-height low (Step hit Frame — caught by this
        # oracle's own decode + reason asserts on first run).
        g = subprocess.run(["xwininfo", "-id", self.wid],
                           capture_output=True, text=True, env=ENV).stdout
        self.wx = int(re.search(r"Absolute upper-left X:\s+(-?\d+)", g).group(1))
        self.wy = int(re.search(r"Absolute upper-left Y:\s+(-?\d+)", g).group(1))

    def read_log(self):
        return open(self.log).read()

    def wait_blocks(self, n, reason=None, timeout=45):
        """Wait for n complete pause blocks; return the n-th as
        (dump_lines, raw_block_text).

        With reason set, the n-th block's '=== DBG PAUSE (reason) ==='
        header must match — a click that hit the wrong control emits the
        wrong reason and fails here instead of passing by coincidence.
        """
        t0 = time.time()
        while time.time() - t0 < timeout:
            txt = self.read_log()
            blocks = re.findall(r"=== DBG PAUSE \((\w+)\) ===\n(.*?)"
                                r"=== STATE DUMP ===\n(.*?)\n=== END DUMP ===",
                                txt, re.S)
            if len(blocks) >= n:
                got_reason, pre, body = blocks[n - 1]
                if reason is not None and got_reason != reason:
                    raise RuntimeError("dump #%d reason %r, expected %r"
                                       % (n, got_reason, reason))
                return body.split("\n"), pre
            time.sleep(0.3)
        raise RuntimeError("dump #%d never appeared; log tail:\n%s"
                           % (n, self.read_log()[-800:]))

    def wait_dumps(self, n, reason=None, timeout=45):
        return self.wait_blocks(n, reason, timeout)[0]

    def count_dumps(self):
        return len(re.findall(r"=== END DUMP ===", self.read_log()))

    def geom(self, name):
        m = re.search(r"^DBG_GEOM %s (-?\d+) (-?\d+) (\d+) (\d+)$" % name,
                      self.read_log(), re.M)
        if not m:
            raise RuntimeError("no DBG_GEOM %s in log" % name)
        return tuple(int(v) for v in m.groups())

    def click(self, name):
        """Real pointer: hover the widget, then click its center."""
        x, y, w, h = self.geom(name)
        sx, sy = self.wx + x + w // 2, self.wy + y + h // 2
        subprocess.run(["xdotool", "mousemove", str(sx), str(sy)], env=ENV)
        time.sleep(0.3)   # hover state must render before the press
        subprocess.run(["xdotool", "click", "1"], env=ENV)

    def click_at(self, x, y):
        subprocess.run(["xdotool", "mousemove",
                        str(self.wx + x), str(self.wy + y)], env=ENV)
        time.sleep(0.2)
        subprocess.run(["xdotool", "click", "1"], env=ENV)

    def wait_select(self, timeout=10):
        """Last DBG_SELECT (addr, value) emitted by a byte click."""
        t0 = time.time()
        while time.time() - t0 < timeout:
            m = re.findall(r"^DBG_SELECT ([0-9A-Fa-f]{4}) ([0-9A-Fa-f]{2})$",
                           self.read_log(), re.M)
            if m:
                return m[-1]
            time.sleep(0.2)
        raise RuntimeError("no DBG_SELECT after byte click")

    def shot(self):
        time.sleep(0.6)   # let the post-event frame present
        return screenshot(self.wid, self.tmp)

    def close(self):
        kill_window(self.wid)
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.f.close()


def parse_mem(block_text):
    """DBG_MEMGEOM + DBG_MEM rows out of a pause block."""
    g = re.search(r"^DBG_MEMGEOM (\d+) (\d+) (\d+) (\d+) (\d+)$",
                  block_text, re.M)
    if not g:
        raise RuntimeError("no DBG_MEMGEOM in pause block")
    gutter, cell_w, half_gap, cw, row_h = (int(v) for v in g.groups())
    rows = [(int(dy), addr, hx) for dy, addr, hx in
            re.findall(r"^DBG_MEM (\d+) ([0-9A-Fa-f]{4}) ([0-9A-Fa-f]+)$",
                       block_text, re.M)]
    if not rows:
        raise RuntimeError("no DBG_MEM rows in pause block")
    return {"gutter": gutter, "cell_w": cell_w, "half_gap": half_gap,
            "cw": cw, "row_h": row_h, "rows": rows}


def check_mem_panel(chrome, atlas, block_text, label, img=None):
    """Decode the memory panel's hex cells and diff vs the DBG_MEM seam."""
    mx, my, mw, mh = chrome.geom("mem")
    m = parse_mem(block_text)
    if img is None:
        img = chrome.shot()
    px = img.load()
    bad = []
    for dy, addr, hx in m["rows"]:
        for ci in range(len(hx) // 2):
            cx = mx + m["gutter"] + ci * m["cell_w"]
            if ci >= 8:
                cx += m["half_gap"]
            cy = my + dy
            got = (atlas.get(cell_sig(px, cx, cy), "?")
                   + atlas.get(cell_sig(px, cx + m["cw"], cy), "?"))
            want = hx[ci * 2:ci * 2 + 2]
            if got != want:
                bad.append((addr, ci, want, got))
    if bad:
        print("FAIL: %s — %d/%d memory cells diverge (first: %s+%d want %r got %r)"
              % (label, len(bad), len(m["rows"]) * 16,
                 bad[0][0], bad[0][1], bad[0][2], bad[0][3]))
        return False
    print("PASS: %s — %d memory rows decode byte-identical"
          % (label, len(m["rows"])))
    return True


def check_panel(chrome, atlas, dump_lines, label):
    rx, ry, rw, rh = chrome.geom("regs")
    img = chrome.shot()
    got = decode_panel(img, atlas, rx, ry, rw)
    want = [l.rstrip() for l in dump_lines[:DUMP_PANEL_LINES]]
    got = got[:len(want)]
    if got != want:
        print("FAIL: %s — decoded panel != core dump" % label)
        for a, b in zip(want, got + [""] * len(want)):
            mark = "  " if a == b else "!!"
            print("%s want %-24r got %r" % (mark, a, b))
        return False
    print("PASS: %s — %d panel lines decode byte-identical" % (label, len(want)))
    return True


def main():
    tmp = tempfile.mkdtemp()
    atlas = build_atlas(tmp)
    print("atlas: %d glyph signatures" % len(atlas))
    ok = True

    # ---- phases 1+2: break-pause decode, then real-input stepping ----
    c = Chrome(tmp, ["--break-cycle", "400000"])
    try:
        d1, b1 = c.wait_blocks(1, reason="paused")
        ok &= check_panel(c, atlas, d1, "auto-break pause")
        ok &= check_mem_panel(c, atlas, b1, "auto-break memory panel")

        # Click-away guard: a click on the LCD center must not step/dump.
        rx, ry, rw, rh = c.geom("regs")
        c.click_at(rx + rw + 150, ry + 100)
        time.sleep(0.8)
        if c.count_dumps() != 1:
            print("FAIL: click-away on the LCD produced a dump")
            ok = False
        else:
            print("PASS: click-away is inert")

        # Byte click: real pointer on a nonzero cell; DBG_SELECT (core
        # leg, mem_read direct) must name that exact addr and value.
        mx, my, mw, mh = c.geom("mem")
        m = parse_mem(b1)
        target = None
        for dy, addr, hx in m["rows"]:
            for ci in range(len(hx) // 2):
                if hx[ci * 2:ci * 2 + 2] != "00":
                    target = (dy, addr, ci, hx[ci * 2:ci * 2 + 2])
                    break
            if target:
                break
        if target is None:
            target = (m["rows"][0][0], m["rows"][0][1], 0,
                      m["rows"][0][2][0:2])
        dy, addr, ci, want_val = target
        cx = mx + m["gutter"] + ci * m["cell_w"] + m["cell_w"] // 2 - 1
        if ci >= 8:
            cx += m["half_gap"]
        c.click_at(cx, my + dy + m["row_h"] // 2 - 1)
        sel_addr, sel_val = c.wait_select()
        want_addr = "%04X" % (int(addr, 16) + ci)
        if (sel_addr.upper(), sel_val.upper()) != (want_addr, want_val.upper()):
            print("FAIL: byte click selected %s=%s, wanted %s=%s"
                  % (sel_addr, sel_val, want_addr, want_val))
            ok = False
        else:
            print("PASS: byte click selects %s = %s" % (sel_addr, sel_val))

        c.click("btn_step")
        d2 = c.wait_dumps(2, reason="step")
        cyc1 = int(d1[0].split("=")[1])
        cyc2 = int(d2[0].split("=")[1])
        if not (cyc1 < cyc2 <= cyc1 + 24):
            print("FAIL: Step instr advanced CYC by %d, not one instruction"
                  % (cyc2 - cyc1))
            ok = False
        ok &= check_panel(c, atlas, d2, "after mouse Step (CYC %d->%d)" % (cyc1, cyc2))

        c.click("btn_pause")          # Run (resume)
        time.sleep(1.0)               # emulate a bit
        c.click("btn_pause")          # Pause again
        d3, b3 = c.wait_blocks(3, reason="paused")
        cyc3 = int(d3[0].split("=")[1])
        if not (cyc3 > cyc2):
            print("FAIL: Run/Pause round-trip did not advance CYC")
            ok = False
        ok &= check_panel(c, atlas, d3, "after mouse Run->Pause (CYC %d)" % cyc3)
        ok &= check_mem_panel(c, atlas, b3, "post-resume memory panel")
    finally:
        c.close()

    # ---- phase 3: the planted render fault MUST be caught ----
    c = Chrome(tmp, ["--break-cycle", "400000", "--plant-render-fault"])
    try:
        d = c.wait_dumps(1)
        rx, ry, rw, rh = c.geom("regs")
        img = c.shot()
        got = decode_panel(img, atlas, rx, ry, rw)
        want = [l.rstrip() for l in d[:DUMP_PANEL_LINES]]
        if got[:len(want)] == want:
            print("FAIL: planted render fault NOT caught — the checker is blind")
            ok = False
        else:
            print("PASS: planted render fault caught")
    finally:
        c.close()

    # ---- phase 4: the planted MEMORY fault MUST be caught ----
    c = Chrome(tmp, ["--break-cycle", "400000", "--plant-mem-fault"])
    try:
        _, b = c.wait_blocks(1, reason="paused")
        if check_mem_panel(c, atlas, b, "(plant probe, must fail)"):
            print("FAIL: planted mem fault NOT caught — the mem checker is blind")
            ok = False
        else:
            print("PASS: planted mem fault caught")
    finally:
        c.close()

    print("PASS: debugger UI oracle" if ok else "FAIL: debugger UI oracle")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
