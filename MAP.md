# Wayfinder Map

## Destination

See [SPEC.md](SPEC.md#destination).

## Frontier

- [ ] **Feature parity bar** (`Q-008`) - Which components are required,
      optional, or dropped under Wine? Candidates: loader UI and tray,
      WinToast notifications, AutoLogin, the PostOffice/multibox IPC,
      Crashpad, Lua and luarocks, and each bundled plugin. (The in-game
      overlay is already excluded; see **Overlay requirement**.)
- [ ] **Linux launch wrapper scope** (`Q-014`) - The launch method is
      settled (see **Multibox IPC across instances**). Should a fork-only
      script start N clients and `MacroQuest.exe` with `proton run`, or is
      documentation alone enough?
- [ ] **Verification environment** (`Q-013`) - What Live accounts, hardware
      (Vulkan-capable GPU), and Linux distribution/display server are
      available for testing, and how many clients make up the multibox test?
- [ ] **Linux CI and release pipeline** (`Q-012`) - Decide what runs on Linux
      runners (fork-only `ov_` workflow files, if any) and how artifacts are
      packaged without shipping the non-redistributable xwin SDK.

## Blocked

None.

## Fog

- Window management for multiboxing on Linux (positioning windows, focus,
  and input broadcast under X11 compared with Wayland/XWayland).
- Distribution and installation on Linux (installing into a prefix, a
  Lutris or Bottles recipe, or packaging).
- Whether Daybreak policy or client-side detection treats Wine-hosted
  injection differently from Windows.
- Path and INI-location assumptions in `mq2main.dll` and plugins when
  running under a Wine prefix (case is settled; see **Filename case
  sensitivity**).

## Completed

- [x] [Current attachment architecture](ANSWERS.md#q-001-current-attachment-architecture)
      (`Q-001`) - Fully Windows-native: DLL injection with `CreateRemoteThread`,
      DirectX hooks, named-pipe IPC, and an MSVC-only build.
- [x] [Rewrite architecture model](ANSWERS.md#q-002-rewrite-architecture-model)
      (`Q-002`) - Option A: Windows MacroQuest runs inside the same Wine
      prefix as `eqgame.exe`.
- [x] [Target Wine runtime](ANSWERS.md#q-005-target-wine-runtime)
      (`Q-005`) - Superseded by **Steam and GE-Proton runtime**.
- [x] [Wine version and graphics layer](ANSWERS.md#q-015-wine-version-and-graphics-layer)
      (`Q-015`) - DXVK is required; the Wine version is superseded by
      **Steam and GE-Proton runtime**.
- [x] [Injection mechanism](ANSWERS.md#q-009-injection-mechanism)
      (`Q-009`) - Keep the existing `MacroQuest.exe` injection of
      `mq2main.dll` into `eqgame.exe`; no new mechanism.
- [x] [Overlay requirement](ANSWERS.md#q-011-overlay-requirement)
      (`Q-011`) - The overlay is not used; no overlay work is planned.
- [x] [Supported EverQuest clients](ANSWERS.md#q-003-supported-everquest-clients)
      (`Q-003`) - Live x64 only; Test and Emulator clients are dropped.
- [x] [Upstream sync policy](ANSWERS.md#q-007-upstream-sync-policy)
      (`Q-007`) - Stay mergeable with `RedGuides/openvanilla`; keep changes
      small and isolated; small upstream PRs are optional.
- [x] [Retiring non-Live files](ANSWERS.md#q-016-retiring-non-live-files)
      (`Q-016`) - Keep the files; disable the non-Live workflows on the fork;
      leave the README unchanged.
- [x] [Windows support retention](ANSWERS.md#q-006-windows-support-retention)
      (`Q-006`) - Linux plus Wine only; Windows support comes only from
      upstream.
- [x] [Build host](ANSWERS.md#q-004-build-host) (`Q-004`) - Build on Linux,
      with no Windows machine or VM; output stays MSVC-ABI x64 PE.
- [x] [Linux compiler toolchain](ANSWERS.md#q-017-linux-compiler-toolchain)
      (`Q-017`) - Native `clang-cl`, `lld-link`, `llvm-rc`, and NASM; no
      Wine at build time.
- [x] [CMake sync with upstream vcxproj](ANSWERS.md#q-021-cmake-sync-with-upstream-vcxproj)
      (`Q-021`) - Regenerate the CMake files with the converter under `pwsh`
      after each upstream merge.
- [x] [MSVC/WinSDK header and library source](ANSWERS.md#q-020-msvcwinsdk-header-and-library-source)
      (`Q-020`) - `xwin` with CRT 14.44 and SDK 10.0.26100 in
      `~/.local/share/xwin`; toolchain smoke-tested under Wine.
- [x] [CMake entry point for Linux builds](ANSWERS.md#q-018-cmake-entry-point-for-linux-builds)
      (`Q-018`) - Minimal upstreamable guard patches plus fork-only toolchain,
      preset, and NASM files.
- [x] [vcpkg dependencies on a Linux host](ANSWERS.md#q-019-vcpkg-dependencies-on-a-linux-host)
      (`Q-019`) - Overlay triplet plus chainloaded `clang-cl` toolchain built
      23 of 26 ports; detours, luajit, and pe-parse need fork-only overlays;
      crashpad is open.
- [x] [Filename case sensitivity](ANSWERS.md#q-024-filename-case-sensitivity)
      (`Q-024`) - Fix references to match real names (one small upstreamable
      PR); symlink shims for submodules; case check after each merge.
- [x] [Steam and GE-Proton runtime](ANSWERS.md#q-025-steam-and-ge-proton-runtime)
      (`Q-025`) - Steam EverQuest Live under GE-Proton10-34 (Wine 10.0
      Staging, DXVK 2.7.1); MacroQuest runs in the game's Proton prefix.
- [x] [Multibox IPC across instances](ANSWERS.md#q-010-multibox-ipc-across-instances)
      (`Q-010`) - Launch every client with `eqgame.exe patchme` through
      `proton run` in the shared Steam prefix, outside Steam and LaunchPad;
      one wineserver keeps named pipes working.
- [x] [clang-cl source compatibility](ANSWERS.md#q-022-clang-cl-source-compatibility)
      (`Q-022`) - Small MSVC-neutral source patches; eqlib fixes carried as
      fork patches; full tree builds and injects under GE-Proton.
- [x] [Crashpad on Linux builds](ANSWERS.md#q-023-crashpad-on-linux-builds)
      (`Q-023`) - Fork-only stub port; no crash dumps on Linux builds.
