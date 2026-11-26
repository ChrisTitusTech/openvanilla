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

1. Regenerate the CMake files: `pwsh ./batch-convert.ps1` (see
   [Regenerating CMake files](#regenerating-cmake-files)).
2. Run the checker and the tests.
3. Fix each new mismatch in place by correcting the reference's case. If the
   reference is in a submodule, add a case shim.
4. Add every new fixed spelling to `KNOWN_FIXES`.
5. If `test_linux_build_fixes.py` fails, re-apply the clang or converter fix
   that the merge reverted, or refresh the eqlib patch.

## Regenerating CMake files

The `.vcxproj` files are the source of truth (`ANSWERS.md` Q-021). The
`CMakeLists.txt` files are generated from them, so never edit them by hand.

- **`batch-convert.ps1`** (repository root, upstream-owned) lists every
  converted project and runs `tools/conversions/Convert-VcxprojToCMake.ps1`
  on each one. Run it from the repository root with `pwsh ./batch-convert.ps1`.
  Afterwards, revert its changes in the `src/eqlib` submodule
  (`git -C src/eqlib checkout CMakeLists.txt`), because upstream eqlib owns
  that file. Its `*-conversion-analysis.txt` reports are ignored by git.
- **`gen_solution.ps1`** (upstream-owned) generates a Visual Studio solution
  on Windows. The Linux build doesn't use it.

The converter carries these fixes, which are offered upstream:

- It resolves project references that use backslash paths, so plugins link
  `MQ2Main` rather than `..\..\main\MQ2Main`.
- It expands a project's own `UserMacros`, such as the loader's
  `LoaderDependencies*` library lists.
- It drops every known vcpkg library, including transitive ones such as
  `fmt` and `zlib`.
- It maps `$(MQBinaryDirName)` to `debug`/`release`.
- It uses `find_package(CURL)`, which matches case-sensitive file systems.
- It skips empty `<Link />` elements.
- Its output is deterministic: entries keep `.vcxproj` order instead of
  hashtable order, and files are written as UTF-8 without a BOM.

`ConverterRegeneration` in `test_linux_build_fixes.py` runs the converter
twice. It fails if the two runs differ, or if any committed
`CMakeLists.txt` differs from the converter's output.

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
   - redirects `powershell.exe` to `pwsh` through `bin/powershell.exe`;
   - compiles the loader with `/Zc:twoPhase-`. It targets Windows 7, which
     hides `RoTransformError`, yet `<wrl/event.h>` calls it from templates.
     MSVC defers that lookup, but clang's C++20 two-phase lookup does not.

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

`tools/linux/mq-launch.sh` does this for you. It starts `MacroQuest.exe`
if it isn't running, then for each entry in `TAGS` (default `3 4 5 6`, one
client per tag) it switches to the tag, launches a client, waits for its
window and pins the window to the tag. It needs `wmctrl` and an EWMH window
manager such as dwm-titus. Override `PROTON`, `EQ_DIR`, `MQ_DIR`,
`LAUNCH_DELAY` (default 2s), `WINDOW_TIMEOUT` or `LOGIN_TIMEOUT` as needed:

```sh
TAGS="3 4 5 6" tools/linux/mq-launch.sh
```

To auto-login, set `CHARS` to one `server:character` per tag (`-` skips a
tag). Each client gets `/login:server:character`, which MQ2AutoLogin looks
up in `config/login.db`. Add characters there from the MacroQuest tray menu
(AutoLogin profiles), or log in once by hand and AutoLogin saves the account.

```sh
TAGS="3 4 5 6" CHARS="erollisi:Main erollisi:Alt1 erollisi:Alt2 -" tools/linux/mq-launch.sh
```

To keep a setup, put the same variables in `~/.config/openvanilla/mq-launch.conf`
(`MQ_LAUNCH_CONF` overrides the path). Environment variables still win:

```sh
TAGS="3 4 5 6"
CHARS="erollisi:Main erollisi:Alt1 erollisi:Alt2 erollisi:Alt3"
```

A character missing from `login.db` stops at the login screen; log in by hand
once and the next launch logs in automatically.

Each tag runs EverQuest from its own directory,
`~/.local/share/openvanilla/eq-instances/tag<N>` (`EQ_INSTANCES` overrides
the base). It holds the client's own `eqclient.ini` and `Logs/`; every other
entry is a symlink to the install, refreshed on each launch. The first launch
copies the install's `eqclient.ini`, after which each client keeps its own
settings. Mount-namespace tricks (bwrap, overlays) cannot do this: Wine's
shared wineserver opens files outside the client's namespace.

Before each launch the script writes the client's size to its `eqclient.ini`:
`WindowedWidth`/`WindowedHeight`, zero window offsets and windowed mode.
EverQuest reads this file at startup, so each client opens at exactly the
size of its tile. Other settings in the file are left alone. `GS_RES` sets the size, either one value for every client
or one per `TAGS` entry. The default `auto` uses the monitor that shows the
tag, minus any panel docked to its edges. dwm-titus gives each monitor its
own tags, so on a 2560x1440 + 1920x1080 setup with a 30px bar, tag 3 gets
2560x1410 and tags 4 to 6 get 1920x1050.

```sh
GS_RES="2560x1410 1920x1050 1920x1050 1920x1050" tools/linux/mq-launch.sh
```

By default, clients run directly under Proton. The launcher explicitly
activates each window and, for AutoLogin characters, waits for the game to
finish entering the world before switching to another tag. This avoids the
login stalls seen when focus changes during startup. `LOGIN_TIMEOUT` defaults
to 120 seconds per client; a timeout allows the remaining clients to launch
and the character to be logged in manually. Set `LOGIN_TIMEOUT=0` to skip
the wait. Each client's `Logs/launch.log` captures Proton and compositor output.

Set `GAMESCOPE=1` to opt into independent nested
[gamescope](https://github.com/ValveSoftware/gamescope) instances at the
configured resolutions. `GS_ARGS` defaults to `--force-grab-cursor`.
On X11, concurrent EverQuest clients have been observed to fail with
`BadWindow (X_UnmapWindow)` even when standalone graphics clients at the
same resolutions work. Plain Proton is the tested workaround.
The launcher starts gamescope under `setpriv --no-new-privs`, which drops its file
`CAP_SYS_NICE` (gamescope logs "No CAP_SYS_NICE, falling back to
regular-priority"). On NVIDIA, two gamescopes that both use realtime Vulkan
queues fault the GPU (`Xid 51 BAD_TSG`, then `NV_ERR_RESET_REQUIRED` in
`journalctl -k`; see
[ublue-os/bazzite#6089](https://github.com/ublue-os/bazzite/issues/6089)).
After that fault every new Vulkan or GL program fails, including gamescope
(`vkCreateDevice failed (VkResult: -3)`) and the Quickshell panel, until you
reboot.

Wine tray icons use the X11 XEmbed protocol. Panels that only host
StatusNotifierItem icons (Quickshell, Waybar) need a bridge, or the
MacroQuest icon ends up in an off-screen Wine tray window. A lightweight
option is [wine-sni-bridge](https://github.com/waliori/wine-sni-bridge)
(needs `python3-xlib`, `python3-dbus`, `python3-gobject`). Run it as a
systemd user service (`Restart=always`) and start it before MacroQuest; if
the bridge restarts, restart MacroQuest to get its icon back. On X11 tiling
window managers such as dwm, change its tray window to
`override_redirect=True`. Otherwise the WM tiles that hidden window, and
closing it kills the bridge.

- Use absolute paths.
- Patch the game through Steam after each EverQuest update.
- The eqlib offsets must match the client build.
- Logs are written to `bin/release/Logs`. Crashpad errors there are expected.
