#!/usr/bin/env python3
"""Exercise the real debugger wrappers with isolated runtime/tool sentinels."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME_ENV = (
    "EIGENSCRIPT", "EIGS", "EIGENSCRIPT_BIN", "EIGENSCRIPT_GFX", "EIGS_DIR",
)


class DebugWrappers(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="dmg-wrappers-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.repo = self.root / "DMG"
        shutil.copytree(ROOT / "tests", self.repo / "tests",
                        ignore=shutil.ignore_patterns("__pycache__"))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls"
        self.env = {k: v for k, v in os.environ.items() if k not in RUNTIME_ENV}
        self.env.update(PATH=f"{self.bin}:/usr/bin:/bin", DISPLAY=":sentinel",
                        DMG_TEST_LOG=str(self.log), DMG_TEST_GFX="yes",
                        DMG_TEST_DOCK="yes", DMG_TEST_PIL="yes", DMG_TEST_ORACLE_RC="0",
                        DMG_TEST_XDISPLAY="yes", DMG_DEBUG_UI_MEM_KB="1500000")
        self.runtime(self.root / "EigenScript/src/eigenscript", "sibling")
        self.runtime(self.bin / "eigenscript", "path")
        self.candidate = self.root / "candidate runtime"
        self.runtime(self.candidate, "candidate")
        for tool in ("xdotool", "xwd", "xwininfo"):
            self.script(self.bin / tool, "exit 0\n")
        self.script(self.bin / "xwininfo", '[[ "$DMG_TEST_XDISPLAY" = yes ]]\n')
        self.script(self.bin / "python3", '''
if [[ "$1" = -c ]]; then [[ "$DMG_TEST_PIL" = yes ]]; exit; fi
printf 'oracle:%s\\n' "$EIGENSCRIPT" >> "$DMG_TEST_LOG"
exit "$DMG_TEST_ORACLE_RC"
''')

    def script(self, path, body):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#!/bin/bash\n" + body)
        path.chmod(0o755)

    def runtime(self, path, label):
        self.script(path, f'printf "{label}:%s\\n" "$1" >> "$DMG_TEST_LOG"\n' + '''
case "$1" in
    *probe_gfx.eigs) [[ "$DMG_TEST_GFX" = yes ]];;
    *probe_debug_ui.eigs) [[ "$DMG_TEST_DOCK" = yes ]];;
    *) exit 73;;
esac
''')

    def run_wrapper(self, name):
        self.log.unlink(missing_ok=True)
        result = subprocess.run(["/bin/bash", str(self.repo / "tests" / name)],
                                env=self.env, capture_output=True, text=True,
                                timeout=10)
        calls = self.log.read_text().splitlines() if self.log.exists() else []
        return result, calls

    def isolated_tools(self):
        """Only these tools are discoverable; the host cannot rescue a plant."""
        directory = self.root / "tools"
        directory.mkdir()
        for name in ("dirname", "timeout", "mktemp", "rm", "sed"):
            (directory / name).symlink_to(shutil.which(name))
        for name in ("xdotool", "xwd", "xwininfo", "python3"):
            (directory / name).symlink_to(self.bin / name)
        self.env["PATH"] = str(directory)
        self.env["EIGENSCRIPT_GFX"] = str(self.candidate)
        return directory

    def test_runtime_selection(self):
        for wrapper in ("run_debug_equivalence.sh", "run_debug_ui_oracle.sh"):
            selectors = [None, "EIGENSCRIPT", "EIGS", "EIGENSCRIPT_BIN", "EIGS_DIR"]
            if wrapper == "run_debug_ui_oracle.sh":
                selectors.append("EIGENSCRIPT_GFX")
            for selector in selectors:
                with self.subTest(wrapper=wrapper, selector=selector or "PATH"):
                    for key in RUNTIME_ENV:
                        self.env.pop(key, None)
                    if selector == "EIGS_DIR":
                        tree = self.root / "candidate tree"
                        self.runtime(tree / "src/eigenscript", "candidate")
                        self.env[selector] = str(tree)
                        chosen = tree / "src/eigenscript"
                    elif selector:
                        self.env[selector] = str(self.candidate)
                        chosen = self.candidate
                    else:
                        chosen = self.bin / "eigenscript"
                    result, calls = self.run_wrapper(wrapper)
                    expected = "candidate:" if selector else "path:"
                    self.assertTrue(calls, "wrapper never called a runtime")
                    self.assertTrue(calls[0].startswith(expected), calls)
                    self.assertFalse(any(c.startswith("sibling:") for c in calls), calls)
                    if wrapper == "run_debug_ui_oracle.sh":
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertEqual(calls[-1], f"oracle:{chosen}")
                    else:
                        self.assertEqual(result.returncode, 73, result.stdout + result.stderr)

    def test_gfx_override_reaches_oracle(self):
        self.env.update(EIGENSCRIPT=str(self.bin / "eigenscript"),
                        EIGENSCRIPT_GFX=str(self.candidate))
        result, calls = self.run_wrapper("run_debug_ui_oracle.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls[-1], f"oracle:{self.candidate}")
        self.assertFalse(any(c.startswith(("path:", "sibling:")) for c in calls), calls)

    def test_missing_gfx_fails_before_oracle(self):
        self.env.update(EIGENSCRIPT_GFX=str(self.candidate), DMG_TEST_GFX="no")
        result, calls = self.run_wrapper("run_debug_ui_oracle.sh")
        self.assertNotEqual(result.returncode, 0, "missing gfx was accepted")
        self.assertIn("PREREQ MISSING: gfx build", result.stdout + result.stderr)
        self.assertFalse(any(c.startswith("oracle:") for c in calls), calls)

    def test_explicit_missing_runtime_does_not_fall_back(self):
        self.env["EIGENSCRIPT"] = str(self.root / "missing")
        for wrapper in ("run_debug_equivalence.sh", "run_debug_ui_oracle.sh"):
            with self.subTest(wrapper=wrapper):
                result, calls = self.run_wrapper(wrapper)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("PREREQ MISSING: eigenscript", result.stdout + result.stderr)
                self.assertEqual(calls, [])

    def test_sibling_is_still_a_last_fallback(self):
        self.isolated_tools()
        self.env.pop("EIGENSCRIPT_GFX")
        for wrapper in ("run_debug_equivalence.sh", "run_debug_ui_oracle.sh"):
            with self.subTest(wrapper=wrapper):
                _, calls = self.run_wrapper(wrapper)
                self.assertTrue(calls and calls[0].startswith("sibling:"), calls)

    def test_missing_dock_fails_before_oracle(self):
        self.env.update(EIGENSCRIPT_GFX=str(self.candidate), DMG_TEST_DOCK="no")
        result, calls = self.run_wrapper("run_debug_ui_oracle.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PREREQ MISSING: dock widget", result.stdout + result.stderr)
        self.assertFalse(any(c.startswith("oracle:") for c in calls), calls)

    def test_missing_host_tool_fails_before_oracle(self):
        directory = self.isolated_tools()
        for tool in ("timeout", "xdotool", "xwd", "xwininfo", "python3"):
            with self.subTest(tool=tool):
                target = (directory / tool).readlink()
                (directory / tool).unlink()
                try:
                    result, calls = self.run_wrapper("run_debug_ui_oracle.sh")
                finally:
                    (directory / tool).symlink_to(target)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"PREREQ MISSING: {tool}", result.stdout + result.stderr)
                self.assertFalse(any(c.startswith("oracle:") for c in calls), calls)

    def test_missing_pil_fails_before_oracle(self):
        self.env.update(EIGENSCRIPT_GFX=str(self.candidate), DMG_TEST_PIL="no")
        result, calls = self.run_wrapper("run_debug_ui_oracle.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PREREQ MISSING: python3-pil", result.stdout + result.stderr)
        self.assertFalse(any(c.startswith("oracle:") for c in calls), calls)

    def test_display_requires_either_display_or_xvfb(self):
        directory = self.isolated_tools()
        self.env.pop("DISPLAY")
        result, calls = self.run_wrapper("run_debug_ui_oracle.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PREREQ MISSING: X display", result.stdout + result.stderr)
        self.assertFalse(any(c.startswith("oracle:") for c in calls), calls)
        self.script(directory / "xvfb-run", '''
[[ "$1" = -a && "$2" = -s && "$3" = "-screen 0 1280x800x24" ]] || exit 74
shift 3
exec "$@"
''')
        result, calls = self.run_wrapper("run_debug_ui_oracle.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls[-1], f"oracle:{self.candidate}")

    def test_oracle_failure_is_not_accepted(self):
        self.env.update(EIGENSCRIPT_GFX=str(self.candidate), DMG_TEST_ORACLE_RC="75")
        result, calls = self.run_wrapper("run_debug_ui_oracle.sh")
        self.assertEqual(calls[-1], f"oracle:{self.candidate}")
        self.assertEqual(result.returncode, 75, result.stdout + result.stderr)

    def test_unusable_display_fails_before_oracle(self):
        self.env.update(EIGENSCRIPT_GFX=str(self.candidate), DMG_TEST_XDISPLAY="no")
        result, calls = self.run_wrapper("run_debug_ui_oracle.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PREREQ MISSING: usable X display", result.stdout + result.stderr)
        self.assertFalse(any(c.startswith("oracle:") for c in calls), calls)

    def test_prerequisites_are_declared(self):
        manifest = json.loads((ROOT / "eigs.json").read_text())
        prereqs = manifest.get("acceptance", {}).get("prerequisites", {})
        self.assertIn("gfx", prereqs.get("runtime", []))
        self.assertIn("dock", prereqs.get("runtime", []))
        self.assertIn("PIL", prereqs.get("python_modules", []))
        self.assertEqual(prereqs.get("display"), {"any_of": ["DISPLAY", "xvfb-run"]})
        for command in ("timeout", "python3", "xdotool", "xwd", "xwininfo"):
            self.assertIn(command, prereqs.get("commands", []))


if __name__ == "__main__":
    unittest.main(verbosity=2)
