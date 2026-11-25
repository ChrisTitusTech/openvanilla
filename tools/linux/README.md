# Linux build support (fork-only)

Files in this directory exist only in the `ChrisTitusTech/openvanilla` fork.
They support building MacroQuest on Linux for EverQuest Live running under
Wine. See `SPEC.md` at the repository root for the full plan.

## Filename case

Windows ignores letter case in file names. The Linux build (`clang-cl` and
`lld-link` against an xwin splat) does not. So `#include <Windowsx.h>` or
`#pragma comment(lib, "Crypt32.lib")` works on Windows but fails on Linux.
At runtime nothing changes, because Wine looks up files without regard to
case inside the prefix.

Rules for every file reference:

- **Repository files:** `#include`, `.vcxproj`, `.vcxproj.filters`, `.rc`,
  and `CMakeLists.txt` paths must match the real file name exactly.
- **Windows SDK and MSVC headers:** use the name as it appears in the xwin
  splat, for example `windowsx.h`, `WbemIdl.h`, `TlHelp32.h`, or
  `CommCtrl.h`.
- **System and vcpkg libraries:** write them in lower case, such as
  `crypt32.lib` or `ws2_32.lib`. xwin always provides lower-case names.
- **Libraries built by this repository:** use the project name exactly, for
  example `MQ2Main.lib`.

### Fixes in upstream-owned files

These are one-line changes that are harmless on Windows and small enough to
offer upstream as a single PR. They live in:

- `src/loader/MacroQuest.h`, `src/loader/MacroQuest.cpp`, and
  `src/loader/MacroQuest.vcxproj`;
- `src/main/MacroQuest.cpp`, `src/main/MQ2Main.h`, `src/login/Login.cpp`,
  `src/plugins/autologin/MQ2AutoLogin.cpp`, `src/routing/Network.cpp`, and
  `src/Plugin.props`;
- `extras/plugins/MQ2Telnet/*` and `tools/mkplugin/mkplugin.rc`.

`test_check_filename_case.py` pins each fixed spelling in `KNOWN_FIXES`, so a
merge that brings back an old spelling fails the tests.

### Case shims for submodules

The fork can't edit submodules such as `src/eqlib`. A mismatch there gets a
relative symlink under `case-shims/`, placed at the path the bad include uses
and pointing at the real file. For example,
`case-shims/eqlib/graphics/SceneGraphinterface.h` points to
`src/eqlib/include/eqlib/graphics/SceneGraphInterface.h`.

The Linux toolchain must add `tools/linux/case-shims` to the include path
(`/I`). The compiler resolves quoted includes inside a shimmed header from
the shim's directory, so a shim works only when the target header includes
by full path (such as `"eqlib/game/Actors.h"`), as eqlib does. The checker fails if a shim is broken, or if it is no longer used
because upstream fixed the name. In that case, delete the shim.

## Checking

Run the checker from the repository root:

```sh
python3 tools/linux/check_filename_case.py
```

It also checks Windows SDK header names when an xwin splat is at
`$XWIN_ROOT` or `~/.local/share/xwin`. Add `--require-xwin` to fail when
no splat is found.

Run the tests:

```sh
python3 -m unittest discover -s tools/linux -p "test_*.py"
```

The checker and tests also run:

- **In CI:** `.github/workflows/linux_case_check.yaml` runs on every push and
  pull request. It runs without xwin, so `KNOWN_FIXES` covers SDK header
  names there.
- **After every local merge or pull:** enable the hook once per clone:

  ```sh
  git config core.hooksPath tools/linux/hooks
  ```

## After pulling from upstream

1. Run the checker and the tests.
2. Fix each new mismatch in place by correcting the reference's case. If the
   reference is in a submodule, add a case shim.
3. Add every new fixed spelling to `KNOWN_FIXES`.
