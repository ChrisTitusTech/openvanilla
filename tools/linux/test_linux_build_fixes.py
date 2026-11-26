#!/usr/bin/env python3
"""Guards against upstream merges reverting the fork's Linux build fixes
(clang-cl compatibility and CMake path fixes). Run from the repository root:

    python3 -m unittest discover -s tools/linux -p "test_*.py"
"""

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
EQLIB = REPO / "src/eqlib"
EQLIB_PATCHES = sorted((REPO / "tools/linux/patches/eqlib").glob("*.patch"))

# file -> strings that must be present
REQUIRED = {
    "CMakeLists.txt": ["MQ_PLATFORM"],
    "src/Common.cmake": ['"${CMAKE_BINARY_DIR}/lib/${MQBinaryDirName}"'],
    "src/loader/CMakeLists.txt": ["find_package(CURL REQUIRED)", "CURL::libcurl", '"d3d11.lib"', '"setupapi.lib"',
                                  '"imm32.lib"', '"secur32.lib"', '"ws2_32.lib"', '"wldap32.lib"', '"version.lib"'],
    "src/loader/PostOffice.h": ["#include <windows.h>"],
    "src/login/Login.h": ["return typename Iterator::Sentinel();"],
    "src/imgui/CMakeLists.txt": ["imanim/im_anim.cpp"],
    "src/main/CMakeLists.txt": ["MQGameFaceInspector.cpp", "/bin/$<IF:$<CONFIG:Debug>,debug,release>"],
    "src/main/MQGameFaceInspector.cpp": ["R (*detour)(Args...)"],
    "src/plugins/autologin/StateMachine.cpp": ["static bool IsInConnectState();"],
    "include/mq/contrib/glm/glmUtils.h": ["#include <array>"],
    "tools/build_scripts/MQ2Main_PostBuild.ps1": ["$File1 = (Resolve-Path -Path $File1).Path"],
    # Converter fixes: regenerating CMake files (batch-convert.ps1) must keep the fixes above.
    "tools/conversions/Convert-VcxprojToCMake.ps1": [
        '"curl"               { "CURL" }', "$refInclude = $_.Include -replace '\\\\', '/'",
        "$userMacros[$_.LocalName] = $_.InnerText", "[System.Text.UTF8Encoding]::new($false)",
        "$ex = [ordered]@{}"],
    "tools/conversions/Modules/ConversionCommon.psm1": ["'$<IF:$<CONFIG:Debug>,debug,release>'"],
    "tools/conversions/Modules/ItemDefinitionProcessing.psm1": [
        "$linkLibraries = [ordered]@{}", "-IncludeAllKnown", "'^vcpkg_crashpad_.*\\.lib$'"],
}

# file -> strings that must be absent
FORBIDDEN = {
    "src/Common.cmake": ['"/std:c++17"'],
    "src/loader/portfile.cmake": ["vcpkg_install_empty_package()"],
    "src/loader/CMakeLists.txt": ["LoaderDependencies", "fmt.lib", "zlib.lib", '"libcurl', "vcpkg_crashpad_"],
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
    # Project references must be target names, not backslash vcxproj paths.
    "src/**/CMakeLists.txt": [r"^target_link_libraries\(.*\\"],
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


class ExternalPluginPatches(unittest.TestCase):
    def test_patches_apply_or_are_applied(self):
        patches = sorted((REPO / "tools/linux/patches/plugins").glob("*/*.patch"))
        checked = 0
        for patch in patches:
            plugin = REPO / "plugins" / patch.parent.name
            if not (plugin / ".git").exists():
                continue
            checked += 1
            with self.subTest(plugin=plugin.name, patch=patch.name):
                command = ["git", "-C", str(plugin), "apply", "--check"]
                forward = subprocess.run([*command, str(patch)], capture_output=True, text=True)
                if forward.returncode == 0:
                    continue
                reverse = subprocess.run([*command, "--reverse", str(patch)],
                                         capture_output=True, text=True)
                self.assertEqual(reverse.returncode, 0,
                                 f"{patch} neither applies nor is applied:\n{forward.stderr}")
        if not checked:
            self.skipTest("external plugin submodules not checked out")


# batch-convert.ps1 also regenerates the eqlib submodule, which upstream eqlib owns.
CONVERTER_SKIP = {"src/eqlib/eqlib.vcxproj"}


def batch_convert_projects():
    text = read("batch-convert.ps1")
    for vcxproj, folder in re.findall(r"'([^']+\.vcxproj)'\s*=\s*'([^']*)'", text):
        vcxproj = vcxproj.replace("\\", "/")
        if vcxproj not in CONVERTER_SKIP:
            yield vcxproj, folder


def run_converter(projects, out_dir):
    lines = ["$ErrorActionPreference = 'Stop'"]
    outputs = {}
    out_dir.mkdir(parents=True)
    for i, (vcxproj, folder) in enumerate(projects):
        out = Path(out_dir) / f"{i}.txt"
        outputs[vcxproj] = out
        lines.append(f"& ./tools/conversions/Convert-VcxprojToCMake.ps1 -VcxprojPath '{vcxproj}' "
                     f"-OutputPath '{out}' -Force -SolutionFolder '{folder}' *> $null")
    subprocess.run(["pwsh", "-NoProfile", "-NonInteractive", "-Command", "\n".join(lines)],
                   cwd=REPO, check=True, capture_output=True, text=True)
    return outputs


@unittest.skipUnless(shutil.which("pwsh"), "pwsh is required to run the vcxproj converter")
class ConverterRegeneration(unittest.TestCase):
    """The committed CMake files are the converter's output, so regenerating them after an
    upstream merge (pwsh ./batch-convert.ps1) cannot silently drop a fix or reorder flags."""

    @classmethod
    def setUpClass(cls):
        cls.projects = list(batch_convert_projects())
        cls.tmp = tempfile.TemporaryDirectory()
        cls.first = run_converter(cls.projects, Path(cls.tmp.name) / "a")
        cls.second = run_converter(cls.projects, Path(cls.tmp.name) / "b")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_projects_listed(self):
        self.assertIn("src/loader/MacroQuest.vcxproj", dict(self.projects))

    def test_output_is_deterministic(self):
        for vcxproj, _ in self.projects:
            with self.subTest(vcxproj=vcxproj):
                self.assertEqual(self.first[vcxproj].read_bytes(), self.second[vcxproj].read_bytes())

    def test_committed_files_match_converter(self):
        for vcxproj, _ in self.projects:
            committed = Path(vcxproj).parent / "CMakeLists.txt"
            with self.subTest(file=str(committed)):
                self.assertEqual(self.first[vcxproj].read_text(encoding="utf-8"), read(committed),
                                 "Out of date; regenerate with: pwsh ./batch-convert.ps1")


if __name__ == "__main__":
    unittest.main()
