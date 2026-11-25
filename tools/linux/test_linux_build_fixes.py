#!/usr/bin/env python3
"""Guards against upstream merges reverting the fork's Linux build fixes
(clang-cl compatibility and CMake path fixes). Run from the repository root:

    python3 -m unittest discover -s tools/linux -p "test_*.py"
"""

import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
EQLIB = REPO / "src/eqlib"
EQLIB_PATCHES = sorted((REPO / "tools/linux/patches/eqlib").glob("*.patch"))

# file -> strings that must be present
REQUIRED = {
    "CMakeLists.txt": ["MQ_PLATFORM"],
    "src/Common.cmake": ['"${CMAKE_BINARY_DIR}/lib/${MQBinaryDirName}"'],
    "src/loader/CMakeLists.txt": ["find_package(CURL REQUIRED)", "CURL::libcurl", "d3d11 setupapi imm32 secur32 ws2_32 wldap32 version"],
    "src/loader/PostOffice.h": ["#include <windows.h>"],
    "src/login/Login.h": ["return typename Iterator::Sentinel();"],
    "src/imgui/CMakeLists.txt": ["imanim/im_anim.cpp"],
    "src/main/CMakeLists.txt": ["MQGameFaceInspector.cpp", "/bin/$<IF:$<CONFIG:Debug>,debug,release>"],
    "src/main/MQGameFaceInspector.cpp": ["R (*detour)(Args...)"],
    "src/plugins/autologin/StateMachine.cpp": ["static bool IsInConnectState();"],
    "include/mq/contrib/glm/glmUtils.h": ["#include <array>"],
    "tools/build_scripts/MQ2Main_PostBuild.ps1": ["$File1 = (Resolve-Path -Path $File1).Path"],
}

# file -> strings that must be absent
FORBIDDEN = {
    "src/Common.cmake": ['"/std:c++17"'],
    "src/loader/portfile.cmake": ["vcpkg_install_empty_package()"],
    "src/loader/CMakeLists.txt": ["LoaderDependenciesRelease}"],
    "src/main/CMakeLists.txt": ["ImGuiAlphaMask.h", "ItemDB.txt"],
    "src/main/MQ2Utilities.cpp": ["]##do_assign", ")##op##RightSide", "StackTop()##op", "StackSetTop(##op", "=op##("],
    "src/main/MQCommands.cpp": ["pItem->Item, pItem->DropID"],
    "src/plugins/lua/bindings/lua_MQBindings.cpp": ["file_path.data(), ec.message());"],
    "tools/build_scripts/MQ2Main_PostBuild.ps1": ["[System.IO.File]::Exists"],
}

# file glob -> regexes that must not match
FORBIDDEN_PATTERNS = {
    # Dependent function-pointer type aliases used as casts need `typename` under clang.
    "src/main/MQ2Spells.cpp": [r"(?<!typename )\bDSL::(Term|Reducer|Modifier)\("],
    # Namespace-scope trampolines must use the portable DETOUR_TRAMPOLINE_FN.
    "src/**/*.cpp": [r"^DETOUR_TRAMPOLINE_DEF\("],
}


def read(rel):
    return (REPO / rel).read_text(encoding="utf-8", errors="replace")


class UpstreamFileGuards(unittest.TestCase):
    def test_required(self):
        for rel, needles in REQUIRED.items():
            text = read(rel)
            for needle in needles:
                with self.subTest(file=rel, needle=needle):
                    self.assertIn(needle, text)

    def test_forbidden(self):
        for rel, needles in FORBIDDEN.items():
            text = read(rel)
            for needle in needles:
                with self.subTest(file=rel, needle=needle):
                    self.assertNotIn(needle, text)

    def test_forbidden_patterns(self):
        for pattern_glob, regexes in FORBIDDEN_PATTERNS.items():
            for path in REPO.glob(pattern_glob):
                if EQLIB in path.parents:
                    continue
                text = path.read_text(encoding="utf-8", errors="replace")
                for regex in regexes:
                    with self.subTest(file=str(path.relative_to(REPO)), regex=regex):
                        self.assertIsNone(re.search(regex, text, re.MULTILINE))


@unittest.skipUnless((EQLIB / ".git").exists(), "src/eqlib submodule not checked out")
class EqlibPatches(unittest.TestCase):
    def git_apply(self, *args):
        return subprocess.run(["git", "-C", str(EQLIB), "apply", "--check", *args],
                              capture_output=True, text=True)

    def test_patches_exist(self):
        self.assertTrue(EQLIB_PATCHES)

    def test_patches_apply_or_are_applied(self):
        for patch in EQLIB_PATCHES:
            with self.subTest(patch=patch.name):
                forward = self.git_apply(str(patch))
                if forward.returncode == 0:
                    continue
                reverse = self.git_apply("--reverse", str(patch))
                self.assertEqual(reverse.returncode, 0,
                                 f"{patch.name} neither applies nor is applied; refresh it against "
                                 f"the current eqlib:\n{forward.stderr}")


if __name__ == "__main__":
    unittest.main()
