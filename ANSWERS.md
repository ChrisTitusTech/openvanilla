# Wayfinder Answers

## Q-001: Current attachment architecture

- **Resolved:** 2026-11-25
- **Answer:** MacroQuest is entirely Windows-native. The loader
  (`MacroQuest.exe`) finds running `eqgame.exe` processes and injects
  `mq2main.dll` using `VirtualAllocEx`, `WriteProcessMemory`, and
  `CreateRemoteThread` calls into `SetDllDirectoryA` and `LoadLibraryA`.
  Inside the game, `mq2main.dll` hooks DirectX 9 or 11 to draw an ImGui
  overlay. Multibox messaging (PostOffice) uses Windows named pipes. The
  build only supports Visual Studio 2022 generators with the v143 MSVC
  toolset, and release CI runs on self-hosted Windows runners.
- **Rationale:** You need to know how the code attaches today before choosing
  what to rewrite.
- **Evidence:** `src/loader/ProcessList.cpp` (injection, about lines
  1010-1050); `src/main/GraphicsEngineDX9.cpp`, `GraphicsEngineDX11.cpp`,
  `ImGuiBackendDX11.cpp`; `src/routing/NamedPipes.cpp` (`CreateNamedPipeW`);
  `CMakeLists.txt` line 35 (`FATAL_ERROR` for non-VS generators);
  `CMakePresets.json` (v143); `.github/workflows/*` (`runs-on: Windows`);
  `src/loader/WinToastLib.cpp` and `Crashpad.cpp` (Windows-only loader
  features); `src/eqlib` submodule (client offsets per Live, Test, and Emu
  branch).
- **Consequences:** Every rewrite option has to decide what happens to
  in-process injection, the DirectX hooks, named-pipe IPC, and the MSVC-only
  build. This raises **Rewrite architecture model** and the dependent
  questions in MAP.md.
- **Revisit when:** Upstream MacroQuest changes its injection, rendering, or
  IPC design.

## Q-002: Rewrite architecture model

- **Resolved:** 2026-11-25
- **Answer:** Option A. Keep MacroQuest (`MacroQuest.exe`, `mq2main.dll`,
  plugins) as Windows binaries that run inside the same Wine prefix as
  `eqgame.exe`, and fix whatever breaks under Wine. Options B (a native Linux
  launcher that injects a Windows DLL) and C (a native Linux tool that reads
  the game from outside the process) were rejected.
- **Rationale:** A needs the least code change, keeps every in-process
  feature (overlay, plugins, Lua, macros), stays mergeable with upstream, and
  keeps Windows support. It is also the most stable option. All injection
  calls stay inside Wine, which implements them. Under B, a native Linux
  process cannot call Win32 APIs like `CreateRemoteThread` on a process
  running in Wine. B would therefore need either a Windows helper inside the
  prefix (which is A plus an extra layer) or `ptrace`/`/proc` injection,
  which depends on Wine internals and on `ptrace_scope`. C would require
  rewriting `eqlib` and losing the overlay and hooks.
- **Evidence:** User decision ("Do option A") after an A vs B stability
  comparison. Repository architecture in
  [Q-001](#q-001-current-attachment-architecture).
- **Consequences:** Native Linux and cross-boundary injection are out of
  scope. **Feature parity bar** is unblocked. Injection planning becomes a
  check of whether the existing method works on the chosen runtime. A Linux
  launch wrapper question is added. The build can stay Windows-target (PE)
  whatever build host is chosen.
- **Revisit when:** Injection or the overlay proves unworkable on every
  supported Wine runtime.

## Q-005: Target Wine runtime

- **Status:** Superseded by [Steam and GE-Proton runtime](#q-025-steam-and-ge-proton-runtime).
- **Resolved:** 2026-11-25
- **Answer:** Plain Wine (WineHQ or distro packages) is the only supported
  runtime. Proton, Lutris, and Bottles are not supported targets.
- **Rationale:** User choice. Plain Wine gives one predictable
  `WINEPREFIX`/`wineserver` model to design and test against, and it fits
  option A (everything running in the same prefix).
- **Evidence:** User statement: "plain wine".
- **Consequences:** Injection reliability, multibox IPC, and launch wrapper
  scope are unblocked and are evaluated against plain Wine. The minimum
  version and whether DXVK is required stay open as **Wine version and
  graphics layer** (`Q-015`); overlay rendering now depends on that question.
- **Revisit when:** Plain Wine cannot run the client or MacroQuest acceptably,
  or demand for Proton/Lutris/Bottles support appears.

## Q-015: Wine version and graphics layer

- **Status:** The Wine version is superseded by [Steam and GE-Proton runtime](#q-025-steam-and-ge-proton-runtime). The DXVK requirement still stands.
- **Resolved:** 2026-11-25
- **Answer:** The baseline and minimum tested Wine is `wine-11.20 (Staging)`.
  DXVK is required to translate Direct3D 9/11 to Vulkan. WineD3D is not
  supported.
- **Rationale:** User choice, matching the user's working setup. Targeting
  one Wine build and one graphics path keeps the overlay and hook testing
  bounded.
- **Evidence:** User statement: "wine-11.20 (Staging) and with DXVK".
- **Consequences:** The DX9/DX11 hooks and the ImGui overlay must work on top
  of DXVK. **Overlay rendering under DXVK** now depends only on **Supported
  EverQuest clients**. Users need a Vulkan-capable GPU and driver. The DXVK
  version is not pinned; record the version actually used in the
  verification environment. Wine releases older than 11.20 and non-Staging
  builds are untested.
- **Revisit when:** A later Wine release fixes or breaks injection or the
  overlay, or DXVK stops supporting the client's Direct3D version.

## Q-009: Injection mechanism

- **Resolved:** 2026-11-25
- **Answer:** Keep the existing implementation. `MacroQuest.exe`, running
  inside the Wine prefix, injects `mq2main.dll` into `eqgame.exe` using
  `VirtualAllocEx`, `WriteProcessMemory`, and `CreateRemoteThread` into
  `SetDllDirectoryA`/`LoadLibraryA`. No alternative or fallback mechanism is
  planned.
- **Rationale:** User direction: "keep the project using the already coded
  implementation". This matches option A and avoids changing upstream code.
- **Evidence:** User statement. Implementation in `src/loader/ProcessList.cpp`
  (about lines 1010-1050).
- **Consequences:** Proxy-DLL, `WINEDLLOVERRIDES`, and launch-time loading
  are out of scope. If injection fails on Wine Staging 11.20, fix it within
  the existing code path rather than replacing it. Checking that it works is
  part of verification, not a planning decision.
- **Revisit when:** The existing injection cannot be made to work on the
  baseline Wine.

## Q-011: Overlay requirement

- **Resolved:** 2026-11-25
- **Answer:** The in-game ImGui overlay is not used and is not a requirement.
  There is no overlay or DXVK hook work. The existing DX9/DX11 hook code
  stays in `mq2main.dll` unchanged.
- **Rationale:** User statement: "We aren't using an overlay". Dropping it
  removes the riskiest DXVK interaction from scope.
- **Evidence:** User statement. Hook code in `src/main/GraphicsEngineDX9.cpp`,
  `GraphicsEngineDX11.cpp`, and `ImGuiBackendDX11.cpp`.
- **Consequences:** Success criteria do not test the overlay. Any feature
  that depends on the overlay is treated as optional under **Feature parity
  bar**. If the hooks cause a crash under DXVK, that becomes a defect to
  investigate (for example, disabling the hooks), not overlay work.
- **Revisit when:** The overlay becomes desired, or the hooks destabilize the
  client under DXVK.

## Q-003: Supported EverQuest clients

- **Resolved:** 2026-11-25
- **Answer:** Only EverQuest Live (x64) is supported. Test, Emu RoF2 (Win32),
  and Emu ToB are dropped.
- **Rationale:** User direction: "just live clients discard others". With one
  client there is one `eqlib` branch, one architecture (x64), and one
  verification target.
- **Evidence:** User statement. Non-Live workflows: `build_beta_emu_rof2`,
  `build_release_emu_rof2`, `build_release_emu_tob`, `ci_emu_rof2`,
  `ci_emu_tob`, `ov_build_beta_emu_rof2`, `ov_build_release_emu_rof2`,
  `ov_build_release_emu_tob`, `ov_build_release_test` (all `.yaml`). README
  section "Building for Test or Emulator".
- **Consequences:** The non-Live workflows and README section are to be
  retired (the method was later settled in
  [Q-016](#q-016-retiring-non-live-files): disable, don't delete). Win32 build handling is no
  longer needed. **Verification environment** is unblocked and only needs
  Live. Removing upstream-shared workflows (the ones without the `ov_` prefix)
  may cause merge conflicts; **Upstream sync policy** should account for
  that.
- **Revisit when:** Emulator or Test server play becomes a goal.

## Q-007: Upstream sync policy

- **Resolved:** 2026-11-25
- **Answer:** The fork stays mergeable with `upstream`
  (`RedGuides/openvanilla`) so upstream changes can be pulled regularly.
  Changes to upstream-owned files stay small and isolated. Small, focused
  patches may be offered upstream as PRs. Large patches or the whole effort
  will not be pushed upstream.
- **Rationale:** User direction. MacroQuest and `eqlib` change often (see
  `eqlib: advance live pointer` commits), so staying current matters more
  than freedom to restructure.
- **Evidence:** User statement. `git remote -v` shows `upstream` set to
  `RedGuides/openvanilla`. History contains `Merge remote-tracking branch
  'upstream/master'`. Every file under `.github/workflows/` (including the
  `ov_*` files) and `README.md` comes from upstream. The reusable shared
  workflows only run when `github.repository == 'redguides/openvanilla'`, so
  on this fork the Test and Emulator workflows effectively do nothing.
- **Consequences:**
  - Linux docs and scripts should go in new files, with at most a small link
    from the README.
  - Deleting the upstream-owned Test and Emulator workflows, as Q-003
    implied, would cause modify/delete conflicts on future merges. That
    choice moves to **Retiring non-Live files** (`Q-016`).
  - **Build host and toolchain** no longer depends on this question. It must
    still not require restructuring upstream build files.
- **Revisit when:** The fork stops pulling from upstream, or the effort is
  proposed upstream as a whole.

## Q-016: Retiring non-Live files

- **Resolved:** 2026-11-25
- **Answer:** Keep every Test and Emulator workflow file and the README
  "Building for Test or Emulator" section unchanged. Disable the nine
  non-Live workflows on the fork with `gh workflow disable`, which is a
  repository setting and changes no files.
- **Rationale:** Deleting files that upstream owns would cause modify/delete
  conflicts on every upstream merge that touches them, which goes against
  the [upstream sync policy](#q-007-upstream-sync-policy). The workflows
  already effectively do nothing on the fork because of the reusable
  workflows' `github.repository == 'redguides/openvanilla'` guards, so
  disabling them costs nothing.
- **Evidence:** User approval ("go with that"). Workflow guard check in
  `.github/workflows/*_shared.yaml`.
- **Consequences:** Live-only is enforced through scope and documentation,
  not by removing code. Disabling the workflows is a one-time
  implementation step. Workflows that upstream adds later for non-Live
  clients may need disabling too.
- **Applied:** On 2026-11-25, all nine non-Live workflows were disabled on
  `ChrisTitusTech/openvanilla` with `gh workflow disable`:
  - `build_beta_emu_rof2`, `build_release_emu_rof2`, and
    `build_release_emu_tob`;
  - `ci_emu_rof2` and `ci_emu_tob`;
  - `ov_build_beta_emu_rof2`, `ov_build_release_emu_rof2`,
    `ov_build_release_emu_tob`, and `ov_build_release_test`.

  When running `gh` against the fork, pass `-R ChrisTitusTech/openvanilla`.
  Otherwise it targets upstream.
- **Revisit when:** The fork stops syncing from upstream.

## Q-006: Windows support retention

- **Resolved:** 2026-11-25
- **Answer:** The fork targets Linux with Wine only. Native Windows use isn't
  supported, tested, or documented by this fork. It keeps working only
  because the fork inherits upstream code.
- **Rationale:** User direction. This narrows testing and docs to one
  platform, while the [upstream sync policy](#q-007-upstream-sync-policy)
  keeps the code itself close to upstream.
- **Evidence:** User statement: "only for Linux and Wine, with Windows support
  coming along only as a side effect of upstream".
- **Consequences:** Wine-specific fixes don't need Windows testing. Any patch
  meant for an upstream PR still must not break Windows. **Build host and
  toolchain** is unblocked; it only has to produce binaries that run under
  Wine.
- **Revisit when:** Windows users of the fork need support.

## Q-004: Build host

- **Resolved:** 2026-11-25
- **Answer:** Build on Linux. No Windows machine, VM, or Visual
  Studio/MSBuild install is part of the workflow. The output stays x64
  Windows PE built for the MSVC ABI.
- **Rationale:** User direction ("I want to build in Linux"). The ABI
  requirement follows from the code. `eqlib` calls `eqgame.exe`'s C++ member
  functions and mirrors its MSVC class and vtable layouts, and plugins share
  C++ types with `mq2main.dll`. So MinGW/GCC, which uses a different C++ ABI,
  is not viable. Only MSVC or `clang-cl` can produce compatible binaries.
- **Evidence:**
  - User statement.
  - `CMakeLists.txt` line 35 (`FATAL_ERROR` unless the Visual Studio
    generator is used); lines 41-57 (vcpkg triplet derived from
    `CMAKE_GENERATOR_PLATFORM`); lines 250-254 (the normal build path is
    plain `add_subdirectory`).
  - `src/Common.cmake` (MSVC flags such as `/MP`).
  - MASM sources: `src/main/AssemblyFunctions64.asm`,
    `src/plugins/map/AssemblyFunctions.asm`,
    `src/plugins/itemdisplay/AssemblyFunctions.asm`.
  - Six `.rc` resource files.
  - msvc-wine (https://github.com/mstorsjo/msvc-wine) documents running real
    MSVC through Wine with CMake 3.23+ (Ninja or Makefiles, `winbind`, or
    `CMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded`), and supplying headers
    for native `clang-cl`/`lld-link`.
  - This host has `wine-11.20 (Staging)`, `cmake`, and MinGW installed, but
    no `clang-cl` or `lld-link`.
- **Consequences:**
  - The Visual Studio generator can't be used on Linux, so a non-VS CMake
    entry point is needed (**CMake entry point for Linux builds**).
  - vcpkg's Windows triplets have to be built from a Linux host (**vcpkg
    dependencies on a Linux host**).
  - The compiler choice is **Linux compiler toolchain**.
  - The MSVC/WinSDK license forbids redistributing the toolchain, so each
    builder downloads it with `vsdownload.py`.
- **Revisit when:** A Linux-hosted build cannot produce working binaries
  without large upstream changes.

## Q-017: Linux compiler toolchain

- **Resolved:** 2026-11-25
- **Answer:** Build with native LLVM tools: `clang-cl` (compiler),
  `lld-link` (linker), `llvm-rc` (resources), `llvm-lib` (static libs), and
  native `nasm` for the three `.asm` files. MSVC and the Windows SDK supply
  only headers and libraries. No Microsoft tools run under Wine during the
  build.
- **Rationale:** User choice. Native tools are faster and avoid depending on
  Wine during builds, and `clang-cl` produces MSVC-ABI binaries, as
  [build host](#q-004-build-host) requires. The cost is possible source
  incompatibilities, which are tracked as **clang-cl source compatibility**.
- **Evidence:**
  - User statement ("native clang-cl").
  - The `.asm` sources are NASM syntax, not MASM: `.vcxproj` files use
    `<NASM Include=...>`, and CMake calls `add_nasm_sources`. So `llvm-ml`
    is not needed.
  - Upstream CI builds with MSBuild on `.sln`/`.vcxproj`
    (`.github/workflows/ci_shared.yaml` line 51,
    `ov_build_release_shared.yaml` lines 332-335). The CMake path is
    secondary: `add_nasm_sources` is never defined in the repo, the loader
    is marked "TODO: Fix the loader cmake" and defaults to off, and
    `src/main/CMakeLists.txt` is missing `MQGameFaceInspector.cpp`, which
    `MQ2Main.vcxproj` includes.
  - This Fedora 45 host has `ninja` and `cmake`, but not `clang`, `lld`,
    `llvm-rc`, or `nasm`.
- **Consequences:**
  - The Linux build depends on the incomplete CMake path, which raises
    **CMake sync with upstream vcxproj** and widens **CMake entry point for
    Linux builds**.
  - The MSVC/WinSDK headers need a source (**MSVC/WinSDK header and library
    source**).
  - The build host needs `clang`, `lld`, `llvm`, and `nasm` packages.
- **Revisit when:** `clang-cl` incompatibilities would need patches too large
  for the upstream sync policy; the fallback is MSVC under msvc-wine.

## Q-021: CMake sync with upstream vcxproj

- **Resolved:** 2026-11-25
- **Answer:** Treat the `.vcxproj` files as the source of truth. After every
  upstream merge, regenerate the `CMakeLists.txt` files with the existing
  `tools/conversions/Convert-VcxprojToCMake.ps1` run under PowerShell 7
  (`pwsh`) on Linux. Never edit them by hand.
- **Rationale:** User accepted the recommendation. Upstream maintains only
  the `.vcxproj` files (that is what CI builds), so regenerating is the only
  way to keep up without ongoing manual work. The converter already exists
  in upstream, so no new tool is needed.
- **Evidence:**
  - The converter takes `-VcxprojPath`, `-OutputPath`, `-Force`, and
    `-VcpkgManifest`, and imports `ConversionCommon.psm1` and
    `PathUtilities.psm1`.
  - `cmake/plugins.cmake` (lines 82-90) runs it as `powershell.exe`, which
    doesn't exist on Linux.
  - Drift already exists: `MQGameFaceInspector.cpp` is in `MQ2Main.vcxproj`
    but not in `src/main/CMakeLists.txt` (last changed 2026-03-30, while
    the `.vcxproj` was last changed 2026-11-16).
  - `pwsh` is not installed on this host.
- **Consequences:**
  - The build host needs `pwsh`.
  - The `powershell.exe` call is part of **CMake entry point for Linux
    builds**.
  - Regenerated `CMakeLists.txt` files are tracked upstream files, so an
    upstream change to them can conflict on merge. Resolve such conflicts
    by taking upstream's version and regenerating.
  - Not yet verified: whether the converter runs cleanly on Linux (path
    separators) and produces the same output when nothing has changed. If
    not, the fixes are candidates for a small upstream PR.
- **Revisit when:** Upstream starts maintaining the CMake files itself, or
  the converter can't run on Linux without large changes.

## Q-020: MSVC/WinSDK header and library source

- **Resolved:** 2026-11-25
- **Answer:** Use `xwin` to download and "splat" the MSVC CRT/STL and
  Windows SDK headers and libraries into a fixed directory outside the repo
  (`~/.local/share/xwin`). Use the `/winsysroot` layout. Pin to the VS 17
  manifest (to match upstream's v143 toolset), **MSVC CRT 14.44.17.14** and
  **Windows SDK 10.0.26100**, x64 desktop only, without debug libraries or
  ATL. The exact command is:

  ```sh
  xwin --accept-license --cache-dir ~/.cache/xwin --manifest-version 17 \
    --arch x86_64 --crt-version 14.44.17.14 --sdk-version 10.0.26100 \
    --http-retry 3 splat --use-winsysroot-style --preserve-ms-arch-notation \
    --output ~/.local/share/xwin
  ```
- **Rationale:** User accepted the recommendation. `xwin` needs no Wine,
  lays out files case-correctly for `clang-cl`, and is a single static tool.
  msvc-wine's `vsdownload.py` mainly exists to support running MSVC under
  Wine, which [Q-017](#q-017-linux-compiler-toolchain) ruled out.
- **Evidence:**
  - User accepted the recommendation and Microsoft's license ("I accept").
  - Upstream presets use toolset `v143` (`CMakePresets.json`).
  - `xwin 0.10.0` was installed via `cargo install --locked xwin`. The splat
    is 631 MB, plus a 1.1 GB download cache in `~/.cache/xwin`.
  - Smoke test on this host: a C++20 DLL built with `clang-cl
    /winsysroot`, containing a `nasm -f win64` object and an `llvm-rc`
    resource and linked with `lld-link`, was loaded through `LoadLibraryA`
    by a `clang-cl` host EXE under `wine-11.20 (Staging)` and returned the
    expected result.
- **Consequences:** Every builder must accept Microsoft's license
  (`xwin --accept-license`). The splatted SDK is not redistributable and
  must never be committed or published in CI artifacts. The toolchain file
  passes `/winsysroot <splat>` to `clang-cl` and `/winsysroot:<splat>` to
  `lld-link`.
- **Revisit when:** Upstream moves to a newer toolset (v145 / VS 18), or
  `xwin` stops tracking Microsoft's manifests.

## Q-018: CMake entry point for Linux builds

- **Resolved:** 2026-11-25
- **Answer:**
  - **Small guard patches to upstream files, each suitable as a focused
    upstream PR:**
    - In `CMakeLists.txt`, allow non-Visual Studio generators when
      targeting Windows with an MSVC-compatible compiler.
    - Take the architecture from an explicit cache variable (for example
      `MQ_ARCH=x64`) when `CMAKE_GENERATOR_PLATFORM` is empty.
    - In `cmake/plugins.cmake`, call `pwsh` when `powershell.exe` isn't
      available.
  - **Fork-only new files for everything else:**
    - A `clang-cl` toolchain file (`CMAKE_SYSTEM_NAME=Windows`,
      LLVM tools, xwin include and lib paths).
    - A Linux preset (Ninja, x64, Release).
    - A CMake module that defines the missing `add_nasm_sources` with
      `nasm -f win64`, loaded through the toolchain or
      `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` so upstream files stay untouched.
    - Turn the loader on with `-DMQ_BUILD_LAUNCHER=ON`. Fixes for its
      unfinished CMake ("TODO: Fix the loader cmake") are treated as
      upstreamable patches.
- **Rationale:** User accepted the recommendation. The generator check at
  `CMakeLists.txt` line 35 runs before `project()`, so a toolchain file or
  injected include can't bypass it, and some edit to upstream is
  unavoidable. Keeping that edit to a few guarded lines fits the
  [upstream sync policy](#q-007-upstream-sync-policy). A fork-only top-level
  wrapper would avoid touching upstream files, but it would duplicate the
  root logic (vcpkg overlays, plugin lists) and drift from it.
- **Evidence:**
  - `CMakeLists.txt` lines 33-57 (generator and architecture checks before
    `project()`) and line 69 (`MQ_BUILD_LAUNCHER` defaults to OFF).
  - `cmake/plugins.cmake` lines 82-90 (`powershell.exe`).
  - `add_nasm_sources` is called in `src/main`, `src/plugins/map`, and
    `src/plugins/itemdisplay` CMake files but is defined nowhere.
  - `pwsh` 7.7.0, `nasm` 3.02, `ninja`, and LLVM 23.1.5 are now installed.
- **Consequences:**
  - The vcpkg triplet setup (**vcpkg dependencies on a Linux host**) must
    plug into the same toolchain file.
  - Whether the generated per-project CMake files then compile under
    `clang-cl` is **clang-cl source compatibility**.
  - It is unverified whether the converted loader CMake builds at all.
- **Revisit when:** Upstream rejects the guard patches and they become a
  recurring source of merge conflicts.

## Q-019: vcpkg dependencies on a Linux host

- **Answer:** Build the `x64-windows-static` ports with vcpkg on Linux,
  using a fork-only overlay triplet that chainloads the fork's `clang-cl`
  toolchain. This works for most ports. Ports whose build systems need a
  Windows host get fork-only overlay ports. Crashpad can't be built this way;
  how to handle it is a separate question (**Crashpad on Linux builds**).
- **Rationale:** The spike built 23 of the 26 Windows ports that the
  manifests need, with no Windows machine, which meets
  [Build host](#q-004-build-host). The failures came from port build
  systems, not from the toolchain.
- **Evidence:** The spike was run in the session workspace,
  with vcpkg 2026-03-04 from the `contrib/vcpkg` submodule. The repo was not
  modified.
  - **Triplet:** it is named `x64-windows-static`, so the root CMake
    triplet logic still matches. It sets static CRT and library linkage
    and `VCPKG_BUILD_TYPE release`, because xwin provides no debug CRT. It
    chainloads the toolchain and passes `XWIN_ROOT` through.
    `VCPKG_CMAKE_SYSTEM_NAME` must stay empty, or vcpkg stops treating the
    target as Windows.
  - **Toolchain fixes found during the spike:**
    - Set `CMAKE_TRY_COMPILE_CONFIGURATION Release`, because try-compile
      otherwise needs `libcmtd.lib`.
    - Don't quote paths in `/winsysroot`; gn's `--args` rejects them.
    - The xwin SDK directory is `10.0.26100`, without a trailing `.0`.
    - `cmake -E cmake_llvm_rc` mis-splits paths that contain the space in
      `Windows Kits`. Point the RC `/I` flags at a space-free symlink,
      `~/.local/share/xwin/winsdk`, which links to `Windows Kits/10`.
  - **Succeeded (23 ports):** abseil, argon2, asio, brotli, bzip2, cpr,
    curl, date, dxsdk-d3dx, fmt, freetype, glm, libpng, nlohmann-json,
    pe-parse, protobuf, sol2, spdlog, sqlite3, utf8-range, wil, yaml-cpp,
    and zlib.
  - **pe-parse:** `clang-cl` rejects bare `/analyze`. A one-line
    `vcpkg_replace_string` in an overlay copy of the port fixes it.
  - **detours and luajit:** the repo's overlays in
    `contrib/vcpkg-overlays/cmake/` call `vcpkg_build_nmake` and
    `vcpkg_install_nmake`, which fail with "only support windows".
  - **crashpad:** the gn build in mini_chromium runs `win_helper.py`, which
    imports `winreg` to detect Visual Studio and can't run on Linux.
  - `src/loader/vcpkg.json` asks for `curl[schannel]`, which is not a
    feature in this vcpkg; `curl[ssl,sspi]` selects Schannel on Windows.
    This is more evidence that the loader's CMake path is stale.
- **Consequences:**
  - Fork-only files to add:
    - the triplet;
    - overlay ports for pe-parse (strip `/analyze`);
    - detours and luajit, rebuilt with CMake or Makefiles instead of nmake.
  - These overlays live beside upstream's and take precedence only in Linux
    builds.
  - The loader's `curl[schannel]` dependency needs a small upstreamable fix,
    or a fork-only override.
  - Builds are Release only.
  - **Crashpad on Linux builds** is a new question, tied to
    **Feature parity bar**.
  - **clang-cl source compatibility** and **Linux CI and release pipeline**
    are unblocked.
- **Revisit when:** Upstream moves detours or luajit to CMake-based ports,
  or crashpad gains a non-gn build.

## Q-024: Filename case sensitivity

- **Answer:** Make every file reference match the real file name's case.
  - **Upstream-owned references:** fix them in place, as one small,
    upstreamable "fix filename case for case-sensitive build hosts" PR.
  - **Submodules:** the fork can't patch `src/eqlib` without forking it.
    Those fixes go to the submodule's upstream. Until they land, a
    fork-only build shim adds a correctly-cased symlink.
  - **Merge check:** a fork-only case-check script runs after each upstream
    merge, next to the CMake regeneration, and fails on any new mismatch.
  - **Runtime:** no work is needed, because Wine resolves file names
    case-insensitively inside the prefix.
- **Rationale:** Windows ignores case, but `clang-cl` and `lld-link` on
  Linux do not, so mismatches break the build. Fixing names at the source
  is the real fix and is harmless on Windows. The edits are one line each,
  which fits the [upstream sync policy](#q-007-upstream-sync-policy). The
  check script keeps upstream from reintroducing mismatches. A
  case-insensitive filesystem was rejected: Fedora's default btrfs has no
  casefold support, and `ciopfs` adds a FUSE dependency.
- **Evidence:** A scan of every `#include`, `#pragma comment(lib)`,
  `.vcxproj`, `.filters`, and `.rc` reference found the following.
  - Source includes:
    - `src/eqlib/src/graphics/GraphicsEngine.cpp:24`:
      `SceneGraphinterface.h` should be `SceneGraphInterface.h`
      (in the `eqlib` submodule).
    - `src/main/MQ2Main.h:20`: `blech/Blech.h` should be
      `Blech/Blech.h`.
  - SDK headers in `src/loader/MacroQuest.h` lines 33-41:
    - `Windowsx.h` should be `windowsx.h`;
    - `Wbemidl.h` should be `WbemIdl.h`;
    - `Tlhelp32.h` should be `TlHelp32.h`;
    - `Commctrl.h` should be `CommCtrl.h`.
    - xwin only adds symlinks for common casings, and a test showed
      `clang-cl` fails on `Windowsx.h`.
  - Library names, all of which should be lowercase:
    - `Crypt32.lib` in `src/loader/MacroQuest.cpp`, `src/login/Login.cpp`,
      and `src/plugins/autologin/MQ2AutoLogin.cpp`.
    - `Psapi.lib` in `src/loader/MacroQuest.cpp` and
      `src/main/MacroQuest.cpp`.
    - `Shcore.lib` and `User32.lib` in
      `src/loader/imgui_backend/imgui_impl_win32.cpp` and
      `src/main/ImGuiBackendWin32.cpp`.
    - `Secur32.lib`, `Setupapi.lib`, `Wldap32.lib`, and `Ws2_32.lib` in
      `src/loader/MacroQuest.vcxproj`.
    - A test showed `lld-link` cannot open `Crypt32.lib`, `Psapi.lib`, or
      `Ws2_32.lib`.
  - Project and resource files (not in the Live build, but cheap to fix):
    - `extras/plugins/MQ2Telnet/MQ2Telnet.vcxproj.filters`:
      `mq2telnet.cpp` should be `MQ2Telnet.cpp`.
    - `tools/mkplugin/mkplugin.rc`: `plugin_template\Resource.h` should
      be `resource.h`.
  - Found later by the checker script:
    - `src/routing/Network.cpp`: `Iphlpapi.lib` should be `iphlpapi.lib`.
    - `src/Plugin.props`: `mq2main.lib` should be `MQ2Main.lib`. This one
      is the project's own output name, so plugins couldn't link on Linux.
    - MQ2Telnet: `Ws2tcpip.h` should be `WS2tcpip.h`, and `wintelnet.h`
      should be `WinTelnet.h`.
  - No two tracked files differ only by case.
  - `src/loader/ImGui.h` versus `imgui.h` causes no ambiguity, because
    `ImGui.h` includes `imgui/imgui.h` explicitly.
- **Consequences:**
  - The case fixes are a prerequisite for **clang-cl source
    compatibility**.
  - The regenerated CMake files inherit the corrected `.vcxproj` names.
  - The case part of the "path, case, and INI" fog is resolved; paths and
    INI locations remain.
- **Implementation (applied):**
  - The source fixes above were made in place.
  - The `eqlib` shim is
    `tools/linux/case-shims/eqlib/graphics/SceneGraphinterface.h`.
  - Guard files:
    - `tools/linux/check_filename_case.py` checks includes against the repo
      and xwin, and library names (lower case for system libraries; exact
      project name for this repo's own). It also checks project and
      resource paths, and that each shim resolves and is still needed.
    - `tools/linux/test_check_filename_case.py` holds 11 tests, including a
      `KNOWN_FIXES` revert guard. A test confirmed that reverting
      `windowsx.h` or `iphlpapi.lib` fails it.
    - `.github/workflows/linux_case_check.yaml` runs on push and PR without
      xwin.
    - The `tools/linux/hooks/post-merge` hook runs after each local merge
      once `core.hooksPath` is set.
  - Documentation is in `tools/linux/README.md`.
- **Revisit when:** Upstream rejects the case PR, which would turn the
  fixes into fork-only symlink shims.

## Q-025: Steam and GE-Proton runtime

- **Resolved:** 2026-11-25
- **Answer:** The target runtime is EverQuest Live installed through Steam
  and run by Steam with GE-Proton.
  - The baseline is GE-Proton10-34, which bundles `wine-10.0 (Staging)` and
    DXVK 2.7.1.
  - `MacroQuest.exe` runs inside the game's own Proton prefix, so the
    existing injector sees `eqgame.exe` there.
  - This replaces [Target Wine runtime](#q-005-target-wine-runtime) (plain
    Wine) and the Wine 11.20 baseline in
    [Wine version and graphics layer](#q-015-wine-version-and-graphics-layer).
  - DXVK is still required; GE-Proton already provides it.
- **Rationale:** The user's working EverQuest setup is the Steam release
  under GE-Proton, and it is the only Live install on the machine.
  - Targeting it means testing against a setup known to run the game.
  - Steam-linked accounts may need the Steam client to log in, which a
    separate plain-Wine prefix might not provide.
  - DXVK is already in the prefix.
  - The user chose option A, "switch the target to GE-Proton", over keeping
    plain Wine 11.20.
- **Evidence:**
  - The game is at `~/.steam/steam/steamapps/common/Everquest F2P/` (Steam
    app 205710, build 22687336). `eqgame.exe` is PE32+ x86-64;
    `LaunchPad.exe` is PE32.
  - The prefix is `~/.steam/steam/steamapps/compatdata/205710/pfx`. Its
    `version` file reads GE-Proton10-34, and its `d3d9`, `d3d11`, and
    `dxgi` DLLs are DXVK.
  - GE-Proton10-34 is at
    `~/.local/share/Steam/compatibilitytools.d/GE-Proton10-34`.
    `files/bin/wine --version` reports `wine-10.0 (Staging)`, and its DXVK
    is `v2.7.1`.
  - EverQuest has no Steam launch options set.
- **Consequences:**
  - Proton moves from out of scope to in scope. Lutris, Bottles, and plain
    Wine stay untested.
  - **Linux launch wrapper scope** now covers starting `MacroQuest.exe` in
    the Proton prefix: Steam launch options, `proton run`, or
    `protontricks-launch`. It must use the same Proton build and
    wineserver as the game.
  - **Multibox IPC across instances** now asks whether extra clients start
    in the same Proton prefix and wineserver. Steam normally starts one
    instance per app.
  - Build machines still don't need Wine. Smoke tests may use either the
    Proton prefix or `~/.wine`.
  - Upgrading GE-Proton changes the Wine base. Record the version used in
    each verification run.
- **Revisit when:** GE-Proton breaks injection, EverQuest becomes
  installable outside Steam for this account, or the user moves to another
  Proton build.
