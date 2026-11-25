#!/usr/bin/env python3
"""Find file references whose letter case differs from the real file name.

Windows ignores case in file names; the Linux (clang-cl + lld-link) build does
not. This checks:

* ``#include`` directives against files in the repository and, when an xwin
  splat is available, against the Windows SDK and MSVC headers;
* ``#pragma comment(lib, ...)`` and ``.lib`` names in project and CMake files;
* relative file paths in ``.vcxproj``, ``.vcxproj.filters``, ``.rc`` and
  ``CMakeLists.txt`` files;
* the symlinks in ``tools/linux/case-shims``.

Exit status is 1 when any problem is found.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

EXCLUDED_PREFIXES = ("contrib/vcpkg/",)
SHIM_DIR = "tools/linux/case-shims"

SOURCE_EXTS = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".inl", ".ipp", ".rc", ".rc2"}
PROJECT_EXTS = (".vcxproj", ".vcxproj.filters", ".props", ".targets")
PATH_EXTS = (
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".inl", ".asm", ".rc", ".def",
    ".ico", ".bmp", ".png", ".cur", ".manifest", ".txt", ".lua", ".json",
)

INCLUDE_RE = re.compile(r'^\s*#\s*include\s*([<"])([^>"]+)[>"]')
PRAGMA_LIB_RE = re.compile(r'#\s*pragma\s+comment\s*\(\s*lib\s*,\s*"([^"]+)"')
LIB_TOKEN_RE = re.compile(r"(?<![\w$.%(-])([A-Za-z0-9_+-][A-Za-z0-9_.+-]*\.lib)\b", re.IGNORECASE)
PROJECT_ITEM_RE = re.compile(r'\bInclude="([^"]+)"')
QUOTED_PATH_RE = re.compile(r'"([^"<>|*?$%]+)"')

# Libraries that may keep upper-case letters. Every other .lib reference must
# be lower case so it matches the lower-case names that xwin always provides.
LIB_CASE_ALLOWLIST: set[str] = set()


@dataclass(frozen=True)
class Issue:
    path: str
    line: int
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.message}"


class FileIndex:
    def __init__(self, files: list[str]):
        self.files = set(files)
        self.by_lower_name: dict[str, list[str]] = defaultdict(list)
        self.lower_paths: dict[str, str] = {}
        for f in files:
            self.by_lower_name[os.path.basename(f).lower()].append(f)
            self.lower_paths.setdefault(f.lower(), f)

    def match_suffix(self, ref: str) -> tuple[list[str], list[str]]:
        """Return (exact, case-insensitive) matches for a path suffix."""
        ref = ref.lstrip("./")
        low = ref.lower()
        exact, loose = [], []
        for f in self.by_lower_name.get(os.path.basename(low), ()):
            if f == ref or f.endswith("/" + ref):
                exact.append(f)
            elif f.lower() == low or f.lower().endswith("/" + low):
                loose.append(f)
        return exact, loose


def tracked_files(root: Path) -> list[str]:
    def git(*args: str) -> list[str]:
        out = subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout
        return [f for f in out.splitlines() if f]

    try:
        # Include new, unignored files so the check works before committing.
        files = sorted(set(git("ls-files", "--recurse-submodules")) | set(git("ls-files", "--others", "--exclude-standard")))
    except (OSError, subprocess.CalledProcessError):
        files = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for n in filenames:
                files.append(Path(dirpath, n).relative_to(root).as_posix())
    return [f for f in files if not f.startswith(EXCLUDED_PREFIXES)]


def index_xwin(xwin: Path) -> tuple[FileIndex, set[str], set[str]]:
    headers, libs = [], []
    for dirpath, _, filenames in os.walk(xwin):
        rel = Path(dirpath).relative_to(xwin).as_posix()
        for n in filenames:
            ln = n.lower()
            if ln.endswith(".lib"):
                libs.append(n)
            elif "include" in rel.lower():
                headers.append(f"{rel}/{n}")
    return FileIndex(headers), set(libs), {l.lower() for l in libs}


def read_lines(root: Path, rel: str) -> list[str]:
    try:
        return (root / rel).read_text(encoding="utf-8-sig", errors="replace").splitlines()
    except OSError:
        return []


def check(root: Path, xwin: Path | None = None, files: list[str] | None = None) -> list[Issue]:
    root = Path(root)
    files = tracked_files(root) if files is None else files
    repo = FileIndex(files)
    sdk = sdk_libs = sdk_libs_lower = None
    if xwin is not None:
        sdk, sdk_libs, sdk_libs_lower = index_xwin(Path(xwin))

    issues: list[Issue] = []
    used_shims: set[str] = set()

    projects = {os.path.basename(f)[: -len(".vcxproj")] for f in files if f.endswith(".vcxproj")}
    projects_lower = {p.lower(): p for p in projects}

    def check_lib(rel: str, lineno: int, name: str) -> None:
        name = os.path.basename(name.replace("\\", "/"))
        if not name.lower().endswith(".lib"):
            name += ".lib"
        stem = re.sub(r"-(static|64)$", "", name[:-4], flags=re.IGNORECASE)
        if stem in projects:
            return
        if stem.lower() in projects_lower:
            issues.append(Issue(rel, lineno, f"library '{name}' differs in case from project '{projects_lower[stem.lower()]}'"))
            return
        if name in LIB_CASE_ALLOWLIST or name == name.lower():
            return
        if sdk_libs is not None and name not in sdk_libs and name.lower() not in sdk_libs_lower:
            return
        issues.append(Issue(rel, lineno, f"library '{name}' must be lower case ('{name.lower()}')"))

    def check_relative(rel: str, lineno: int, ref: str) -> None:
        ref = ref.replace("\\\\", "/").replace("\\", "/")
        if not ref.lower().endswith(PATH_EXTS) or "://" in ref or ref.startswith("/"):
            return
        target = os.path.normpath(os.path.join(os.path.dirname(rel), ref)).replace("\\", "/")
        if target in repo.files:
            return
        real = repo.lower_paths.get(target.lower())
        if real:
            issues.append(Issue(rel, lineno, f"'{ref}' differs in case from '{real}'"))

    for rel in files:
        lower = rel.lower()
        ext = os.path.splitext(lower)[1]
        is_source = ext in SOURCE_EXTS
        is_project = lower.endswith(PROJECT_EXTS)
        is_cmake = os.path.basename(lower) == "cmakelists.txt" or ext == ".cmake"
        if not (is_source or is_project or is_cmake) or rel.startswith(SHIM_DIR + "/"):
            continue
        for lineno, line in enumerate(read_lines(root, rel), 1):
            if is_source:
                m = INCLUDE_RE.match(line)
                if m:
                    issues.extend(check_include(rel, lineno, m.group(1), m.group(2), repo, sdk, used_shims))
                for lib in PRAGMA_LIB_RE.findall(line):
                    check_lib(rel, lineno, lib)
                if ext in (".rc", ".rc2") and not m:
                    for ref in QUOTED_PATH_RE.findall(line):
                        check_relative(rel, lineno, ref)
            elif is_project:
                for ref in PROJECT_ITEM_RE.findall(line):
                    if "$(" not in ref and "%(" not in ref and "*" not in ref:
                        check_relative(rel, lineno, ref)
                if not line.lstrip().startswith("<!--"):
                    for lib in LIB_TOKEN_RE.findall(line):
                        check_lib(rel, lineno, lib)
            else:
                code = line.split("#", 1)[0]
                for lib in LIB_TOKEN_RE.findall(code):
                    check_lib(rel, lineno, lib)
                for ref in QUOTED_PATH_RE.findall(code):
                    check_relative(rel, lineno, ref)

    issues.extend(check_shims(root, files, used_shims))
    return issues


def check_include(rel, lineno, kind, ref, repo: FileIndex, sdk: FileIndex | None, used_shims: set[str]) -> list[Issue]:
    ref = ref.replace("\\", "/")
    if kind == '"':
        local = os.path.normpath(os.path.join(os.path.dirname(rel), ref)).replace("\\", "/")
        if local in repo.files:
            return []
    exact, loose = repo.match_suffix(ref)
    if exact:
        real = [f for f in exact if not f.startswith(SHIM_DIR + "/")]
        if not real:
            used_shims.update(exact)
        return []
    bare = "/" not in ref.strip("/")
    sdk_exact, sdk_loose = sdk.match_suffix(ref) if sdk is not None and bare else ([], [])
    if bare and (sdk_exact or sdk is None):
        # A bare name such as <signal.h> may be a system header, so only a
        # file next to the includer counts as a repository match.
        loose = [f for f in loose if os.path.dirname(f) == os.path.dirname(rel)]
    if loose:
        return [Issue(rel, lineno, f"include '{ref}' differs in case from '{sorted(loose)[0]}'")]
    if sdk is not None and bare:
        if not sdk_exact and sdk_loose:
            names = sorted({os.path.basename(f) for f in sdk_loose})
            return [Issue(rel, lineno, f"SDK header '{ref}' not found; real name is {' or '.join(names)}")]
    return []


def check_shims(root: Path, files: list[str], used: set[str]) -> list[Issue]:
    issues = []
    for rel in files:
        if not rel.startswith(SHIM_DIR + "/") or rel.endswith(".md"):
            continue
        path = root / rel
        if not path.is_symlink():
            issues.append(Issue(rel, 1, "case shim must be a symlink"))
            continue
        target = Path(os.path.normpath(path.parent / os.readlink(path)))
        if not target.is_file():
            issues.append(Issue(rel, 1, f"case shim target '{os.readlink(path)}' does not exist"))
        elif target.name.lower() != path.name.lower() or target.name == path.name:
            issues.append(Issue(rel, 1, f"case shim must differ from '{target.name}' by case only"))
        elif rel not in used:
            issues.append(Issue(rel, 1, "case shim is no longer used; upstream fixed it, so delete the shim"))
    return issues


def default_xwin() -> Path | None:
    env = os.environ.get("XWIN_ROOT")
    path = Path(env) if env else Path.home() / ".local/share/xwin"
    return path if path.is_dir() else None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--xwin", type=Path, help="xwin splat (default: $XWIN_ROOT or ~/.local/share/xwin)")
    parser.add_argument("--no-xwin", action="store_true", help="skip Windows SDK header checks")
    parser.add_argument("--require-xwin", action="store_true", help="fail if no xwin splat is found")
    args = parser.parse_args(argv)

    xwin = None if args.no_xwin else (args.xwin or default_xwin())
    if xwin is None:
        if args.require_xwin:
            print("error: xwin splat not found", file=sys.stderr)
            return 2
        print("note: no xwin splat; Windows SDK header names are not checked", file=sys.stderr)

    issues = check(args.root, xwin)
    for issue in issues:
        print(issue)
    print(f"{len(issues)} filename case problem(s) found", file=sys.stderr)
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
