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
4. If `test_linux_build_fixes.py` fails, re-apply the clang fix that the
   merge reverted, or refresh the eqlib patch.

## Building

Prerequisites: LLVM (`clang-cl`, `lld-link`, `llvm-rc`, `llvm-lib`,
`llvm-mt`), `nasm`, `ninja`, `cmake`, `pwsh`, `iconv`, and an xwin splat
(CRT 14.44, SDK 10.0.26100) at `~/.local/share/xwin` or `$XWIN_ROOT`.

```sh
git submodule update --init src/eqlib contrib/vcpkg
tools/linux/build.sh            # output: build/linux-x64/bin/release
```

`build.sh` does the following:

1. Applies `patches/eqlib/*.patch` to the `src/eqlib` submodule. This is
   idempotent, and leaves the submodule showing as modified.
2. Configures vcpkg with the `x64-windows-static` overlay triplet. The
   overlay ports in `vcpkg/ports` are detours, luajit, pe-parse, sol2, and
   a crashpad stub.
3. Injects `cmake/mq-linux.cmake` into the root project. That file:
   - maps the Visual Studio-only settings to Ninja;
   - converts UTF-16 `.rc` files;
   - redirects `powershell.exe` to `pwsh` through `bin/powershell.exe`.

### Clang compatibility fixes

Clang rejects some code that MSVC accepts. The fixes stay valid for MSVC and
are offered upstream; see `ANSWERS.md` Q-022.

- **Upstream-owned files:** fixed in place. `test_linux_build_fixes.py` pins
  each fix, so a merge that reverts one fails the tests.
- **`src/eqlib`:** fixes live in `patches/eqlib/`. After changing eqlib,
  refresh the patch:

  ```sh
  git -C src/eqlib diff > tools/linux/patches/eqlib/0001-clang-compat.patch
  ```

- **Namespace-scope trampolines:** use `DETOUR_TRAMPOLINE_FN`. Keep
  `DETOUR_TRAMPOLINE_DEF` for class scope only.

## Running (multibox)

Run every process in the game's Proton prefix so they share one
wineserver. Start `MacroQuest.exe` first, then each client with `patchme`;
MacroQuest injects into each `eqgame.exe` as it appears.

```sh
export STEAM_COMPAT_DATA_PATH=~/.steam/steam/steamapps/compatdata/205710
export STEAM_COMPAT_CLIENT_INSTALL_PATH=~/.steam/steam
export SteamAppId=205710 SteamGameId=205710
proton=~/.steam/steam/compatibilitytools.d/GE-Proton10-34/proton
eq="$HOME/.steam/steam/steamapps/common/Everquest F2P"
"$proton" run "$PWD/build/linux-x64/bin/release/MacroQuest.exe" &
sleep 15; "$proton" run "$eq/eqgame.exe" patchme &
sleep 15; "$proton" run "$eq/eqgame.exe" patchme &
```

- Use absolute paths.
- Patch the game through Steam after each EverQuest update.
- The eqlib offsets must match the client build.
- Logs are written to `bin/release/Logs`. Crashpad errors there are expected.
