#!/usr/bin/env python3
"""Tests for check_filename_case.py, plus guards against upstream merges
reverting the fork's filename case fixes. Run from the repository root:

    python3 -m unittest discover -s tools/linux -p "test_*.py"
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_filename_case as cfc  # noqa: E402

REPO = Path(__file__).resolve().parents[2]

# Spellings that broke the Linux build. Windows SDK header names can only be
# checked with an xwin splat, so these are also pinned here for CI.
KNOWN_FIXES = {
    "src/loader/MacroQuest.h": ["<Windowsx.h>", "<Wbemidl.h>", "<Tlhelp32.h>", "<Commctrl.h>"],
    "src/loader/MacroQuest.cpp": ['"Psapi.lib"', '"Crypt32.lib"'],
    "src/main/MacroQuest.cpp": ['"Psapi.lib"'],
    "src/login/Login.cpp": ['"Crypt32.lib"'],
    "src/plugins/autologin/MQ2AutoLogin.cpp": ['"Crypt32.lib"'],
    "src/routing/Network.cpp": ['"Iphlpapi.lib"'],
    "src/main/MQ2Main.h": ['"blech/Blech.h"'],
    "src/loader/MacroQuest.vcxproj": ["Setupapi.lib", "Secur32.lib", "Ws2_32.lib", "Wldap32.lib"],
    "src/Plugin.props": ["mq2main.lib"],
    "extras/plugins/MQ2Telnet/TelnetServer.cpp": ["<Ws2tcpip.h>"],
    "extras/plugins/MQ2Telnet/WinTelnet.cpp": ['"wintelnet.h"', "<Ws2tcpip.h>"],
    "extras/plugins/MQ2Telnet/MQ2Telnet.vcxproj.filters": ['"mq2telnet.cpp"'],
    "tools/mkplugin/mkplugin.rc": ["Resource.h"],
}


class FixtureTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text=""):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def check(self, xwin=None):
        files = []
        for dirpath, _, names in os.walk(self.root):
            files += [Path(dirpath, n).relative_to(self.root).as_posix() for n in names]
        return [str(i) for i in cfc.check(self.root, xwin, sorted(files))]

    def test_include_case_mismatch(self):
        self.write("include/mq/Foo.h")
        self.write("src/a.cpp", '#include "mq/foo.h"\n#include <mq/Foo.h>\n')
        self.assertEqual(self.check(), ["src/a.cpp:1: include 'mq/foo.h' differs in case from 'include/mq/Foo.h'"])

    def test_bare_system_header_is_not_a_repo_file(self):
        self.write("include/mq/base/Signal.h")
        self.write("src/a.cpp", "#include <signal.h>\n")
        self.assertEqual(self.check(), [])

    def test_bare_include_next_to_includer(self):
        self.write("src/WinTelnet.h")
        self.write("src/WinTelnet.cpp", '#include "wintelnet.h"\n')
        self.assertEqual(len(self.check()), 1)

    def test_sdk_header_case_with_xwin(self):
        self.write("xwin/sdk/include/um/windowsx.h")
        self.write("repo/src/a.cpp", "#include <Windowsx.h>\n#include <windowsx.h>\n")
        files = ["src/a.cpp"]
        issues = [str(i) for i in cfc.check(self.root / "repo", self.root / "xwin", files)]
        self.assertEqual(issues, ["src/a.cpp:1: SDK header 'Windowsx.h' not found; real name is windowsx.h"])

    def test_system_library_must_be_lower_case(self):
        self.write("src/a.cpp", '#pragma comment(lib, "Crypt32.lib")\n#pragma comment(lib, "psapi")\n')
        self.write("src/a.vcxproj", "<D>Ws2_32.lib;$(Other);d3d11.lib</D>\n")
        self.assertEqual(sorted(self.check()), [
            "src/a.cpp:1: library 'Crypt32.lib' must be lower case ('crypt32.lib')",
            "src/a.vcxproj:1: library 'Ws2_32.lib' must be lower case ('ws2_32.lib')",
        ])

    def test_project_library_must_match_project_name(self):
        self.write("src/main/MQ2Main.vcxproj")
        self.write("src/Plugin.props", "<D>mq2main.lib;MQ2Main-static.lib;MQ2Main.lib</D>\n")
        self.assertEqual(self.check(), ["src/Plugin.props:1: library 'mq2main.lib' differs in case from project 'MQ2Main'"])

    def test_project_and_resource_paths(self):
        self.write("p/Telnet.cpp")
        self.write("p/res/icon.ico")
        self.write("p/p.vcxproj.filters", '<ClCompile Include="telnet.cpp">\n<ClCompile Include="Telnet.cpp">\n')
        self.write("p/p.rc", 'IDI_ICON ICON "res\\\\Icon.ico"\n')
        self.assertEqual(sorted(self.check()), [
            "p/p.rc:1: 'res/Icon.ico' differs in case from 'p/res/icon.ico'",
            "p/p.vcxproj.filters:1: 'telnet.cpp' differs in case from 'p/Telnet.cpp'",
        ])

    def test_case_shim_resolves_include(self):
        self.write("lib/include/lib/Real.h")
        shim = self.root / cfc.SHIM_DIR / "lib/real.h"
        shim.parent.mkdir(parents=True)
        shim.symlink_to(os.path.relpath(self.root / "lib/include/lib/Real.h", shim.parent))
        self.write("lib/src/a.cpp", '#include "lib/real.h"\n')
        self.assertEqual(self.check(), [])

    def test_stale_and_broken_shims(self):
        self.write("lib/Real.h")
        shims = self.root / cfc.SHIM_DIR
        shims.mkdir(parents=True)
        (shims / "real.h").symlink_to(os.path.relpath(self.root / "lib/Real.h", shims))
        (shims / "gone.h").symlink_to("missing/Gone.h")
        issues = self.check()
        self.assertEqual(len(issues), 2)
        self.assertTrue(any("gone.h" in i and "does not exist" in i for i in issues))
        self.assertTrue(any("real.h" in i and "no longer used" in i for i in issues))


class RepositoryTest(unittest.TestCase):
    def test_repository_has_no_case_problems(self):
        issues = cfc.check(REPO, cfc.default_xwin())
        self.assertEqual([str(i) for i in issues], [])

    def test_known_fixes_not_reverted(self):
        reverted = []
        for rel, spellings in KNOWN_FIXES.items():
            text = (REPO / rel).read_text(encoding="utf-8-sig", errors="replace")
            reverted += [f"{rel}: {s}" for s in spellings if s in text]
        self.assertEqual(reverted, [], "an upstream merge reverted a filename case fix")


if __name__ == "__main__":
    unittest.main()
