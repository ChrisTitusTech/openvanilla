# Specification

## Destination

Rework Open Vanilla so that Linux machines can run MacroQuest with
`eqgame.exe` running under Wine. The user's stated goal is: "rewrite this to
be based on Linux machines accessing eqgame.exe through Wine."

The chosen approach is to keep MacroQuest as Windows binaries that run inside
the same Wine prefix as `eqgame.exe`, rather than replacing them with native
Linux code. The work is to find and fix whatever breaks under Wine. See
[rewrite architecture model](ANSWERS.md#q-002-rewrite-architecture-model).
Planning stops once the supported clients, build approach, Wine runtime, and
feature-parity bar are decided so that implementation can be phased.

## Success criteria

Provisional; finalize after **Feature parity bar** is answered.

- [ ] On a supported Linux distribution, a documented procedure starts
      `eqgame.exe` (Steam, GE-Proton) and `MacroQuest.exe` in the same Proton prefix, and
      `mq2main.dll` loads into the client automatically.
- [ ] Each component listed as required by **Feature parity bar** works in
      that environment, verified by a written manual test checklist.
- [ ] Two or more clients on one Linux host can be multiboxed with
      MacroQuest active in each.
- [ ] After an upstream merge, one documented command regenerates the CMake
      files, and the Linux build picks up newly added upstream sources
      (for example, `MQGameFaceInspector.cpp`).
- [ ] On a Linux host, a documented command produces `MacroQuest.exe`,
      `mq2main.dll`, and the required plugin DLLs for Live x64, and they load
      in the GE-Proton prefix.

## In scope

- Getting MacroQuest (loader, `mq2main.dll`, and plugins in this repository)
  to attach to and operate with `eqgame.exe` running under Wine on Linux.
- Linux-side launch, configuration, and documentation needed for that.

## Out of scope

- Running EverQuest itself natively on Linux (EverQuest stays a Windows
  binary running under Wine).
- macOS support.
- Supporting, testing, or documenting native Windows use of this fork.
  Windows keeps working only to the extent upstream code does.
- EverQuest Test and Emulator clients (RoF2, ToB) and their `eqlib` branches.
- Official support for Lutris, Bottles, plain Wine, or Proton builds other
  than the GE-Proton baseline (they may work, but are not tested or
  documented).
- A native Linux (ELF) MacroQuest, loader, or memory-reading tool (options B
  and C in Q-002).
- Injecting from Linux via `ptrace` or `/proc/<pid>/mem`.
- MinGW/GCC builds (incompatible C++ ABI).
- Running Microsoft's `cl.exe`/`link.exe` through Wine (msvc-wine wrappers).
- Building with Visual Studio or MSBuild on Windows.
- Large patches or refactors of upstream code, and pushing the whole Linux
  effort upstream.
- Alternative injection methods (proxy DLLs, `WINEDLLOVERRIDES` loading,
  launch-time loading).
- Getting the in-game ImGui overlay working, or adapting the DX9/DX11 hooks
  for DXVK. The existing hook code stays as-is but is not a success
  requirement.

## Requirements

- MacroQuest stays a set of Windows binaries; the loader and `mq2main.dll`
  run inside the Wine prefix alongside `eqgame.exe`.
- The supported runtime is EverQuest Live installed through Steam (app
  205710) and run with GE-Proton. MacroQuest runs in the game's Proton
  prefix (`steamapps/compatdata/205710/pfx`) with the same Proton build and
  wineserver as `eqgame.exe`.
- The fork's target platform is Linux running `eqgame.exe` and MacroQuest
  under Wine. Changes must not deliberately break Windows behavior shared
  with upstream (so small fixes stay upstreamable), but Windows is not
  tested.
- Binaries are built on a Linux host, with no Windows machine or VM, using
  native LLVM tools (`clang-cl`, `lld-link`, `llvm-rc`, `llvm-lib`) plus
  NASM for the `.asm` sources. No Wine is used at build time. The
  output must be x64 PE built for the MSVC ABI, so it is binary-compatible
  with `eqgame.exe` and with upstream-built plugins.
- MSVC CRT/STL and Windows SDK headers and libraries come from `xwin`
  (VS 17 manifest, CRT 14.44.17.14, SDK 10.0.26100), splatted in
  `/winsysroot` layout to `~/.local/share/xwin`, outside the repo.
  Each builder accepts Microsoft's license; the files are never committed.
- Linux builds use CMake with the Ninja generator, a fork-only toolchain file
  (`clang-cl`, `lld-link`, `llvm-rc`, `llvm-lib`, `llvm-mt`, xwin paths), and
  fork-only presets. Edits to upstream build files are limited to small,
  upstreamable guards (non-VS generator, explicit architecture, `pwsh`
  instead of `powershell.exe`).
- vcpkg ports are built on Linux with a fork-only `x64-windows-static`
  overlay triplet (Release only, static CRT) that chainloads the fork
  toolchain. Ports that need nmake or `/analyze` (detours, luajit, pe-parse)
  get fork-only overlay ports that take precedence only in Linux builds.
- Every file, header, and library reference matches the real name's case,
  because the Linux build is case-sensitive. Upstream-owned references are
  fixed in place as small upstreamable patches. Submodule mismatches use
  fork-only symlink shims until fixed upstream. A fork-only case-check
  script runs after each upstream merge. Runtime needs no change, because
  Wine is case-insensitive. The policy and checks are documented in
  `tools/linux/README.md`. They run in CI, in a `post-merge` hook, and in
  `python3 -m unittest discover -s tools/linux`, and must pass after every
  upstream merge.
- Linux build host prerequisites: LLVM/Clang with `clang-cl` and `lld`
  (tested with 23.1.5), `nasm` (3.02), `ninja`, `cmake` 3.30 or newer,
  PowerShell 7 (`pwsh`, tested with 7.7.0), and `xwin` (0.10.0).
- The `CMakeLists.txt` files are generated from upstream's `.vcxproj` files by
  `tools/conversions/Convert-VcxprojToCMake.ps1` running under `pwsh` on
  Linux, and are regenerated after every upstream merge. They are never
  hand-edited.
- The only supported client is EverQuest Live (x64), built from the `live`
  `eqlib` branch.
- Do not delete or edit the Test and Emulator workflow files or the README
  "Building for Test or Emulator" section. Disable these workflows on
  `ChrisTitusTech/openvanilla` with `gh workflow disable`:
  `build_beta_emu_rof2`, `build_release_emu_rof2`, `build_release_emu_tob`,
  `ci_emu_rof2`, `ci_emu_tob`, `ov_build_beta_emu_rof2`,
  `ov_build_release_emu_rof2`, `ov_build_release_emu_tob`,
  `ov_build_release_test`.
- The baseline runtime is GE-Proton10-34 (`wine-10.0 (Staging)`, DXVK 2.7.1).
  Direct3D goes through DXVK; WineD3D is not supported.
- Injection uses the existing, already-written implementation unchanged:
  `MacroQuest.exe` injects `mq2main.dll` into `eqgame.exe` with
  `CreateRemoteThread`/`LoadLibraryA` inside Wine. No new injection
  mechanism, and nothing injects from the Linux side.
- The fork must keep merging cleanly from `upstream`
  (`RedGuides/openvanilla`). Changes to upstream-owned files must be small,
  isolated, and few; put Linux-specific material in new files where possible.
- Any fix to upstream code must be small enough to offer upstream as a
  focused PR. Large upstream refactors or wholesale contributions are out of
  scope.

## Constraints

- `eqgame.exe` is a closed-source Windows binary; it can only run on Linux
  through Wine or a Wine derivative.
- MacroQuest's core (`mq2main.dll`, plugins, `eqlib`) works by running inside
  the `eqgame.exe` process and reading or hooking its memory; see
  [current attachment architecture](ANSWERS.md#q-001-current-attachment-architecture).
