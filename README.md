# Open Vanilla for Linux

Open Vanilla is an EverQuest multiboxing distribution based on
[MacroQuest](https://github.com/macroquest/macroquest) and the
[RedGuides community](https://www.redguides.com). This fork adds a native Linux
build environment and a launcher for EverQuest running through GE-Proton.

**No Windows machine, VM, Visual Studio, or Wine-based compiler is required.**
Build on Linux with LLVM, CMake and Ninja, then run the resulting Windows x64
binaries inside the same Proton prefix as EverQuest. EverQuest itself remains
a Windows game; this is not a native Linux port of the game or MacroQuest.

- [Supported setup](#supported-setup)
- [Install prerequisites](#1-install-the-linux-prerequisites)
- [Clone and build](#2-clone-and-build-open-vanilla)
- [Set up Steam and GE-Proton](#3-install-everquest-and-ge-proton)
- [Launch and multibox](#4-run-macroquest-and-everquest)
- [Updates and backups](#5-keep-the-build-and-settings-up-to-date)
- [Troubleshooting](#troubleshooting)

## Supported setup

| Component | Baseline |
| --- | --- |
| Build host | x86-64 Linux (tested on Fedora 45) |
| Game | [EverQuest Live](https://store.steampowered.com/app/205710/EverQuest/), 64-bit, Steam app 205710 |
| Runtime | [GE-Proton10-34](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton10-34), with DXVK |
| Desktop | X11 with an EWMH window manager (tested with dwm-titus) |
| Compiler | Native `clang-cl` and `lld-link`, tested with LLVM 23.1.5 |
| Build system | CMake 3.30 or newer, Ninja, NASM, PowerShell 7 |
| Windows SDK | xwin 0.10.0, MSVC CRT 14.44.17.14, Windows SDK 10.0.26100 |
| Plugins | 14 built-in and 18 pinned external plugins |

Two clients have been verified in-game concurrently at different resolutions,
with all 25 enabled plugins loaded and DanNet peer connectivity confirmed.
The launcher defaults to four workspaces, but four-client stability and runtime
behavior of every external plugin have not been fully validated. Windows builds,
EverQuest Test, emulator clients, Wayland-only window management, and alternate
Wine runners are not supported by this Linux setup. For upstream's distribution
and other platforms, see [RedGuides Open Vanilla](https://github.com/RedGuides/openvanilla).

## 1. Install the Linux prerequisites

Use a recent 64-bit Linux distribution with working Vulkan graphics drivers.
Install the native Steam client using your distribution's package manager or
[Valve's official installer](https://store.steampowered.com/about/). A native
Steam installation is the tested configuration; Flatpak Steam paths and sandbox
permissions are not covered here.

On Fedora, enable the appropriate RPM Fusion nonfree repository and install
the native package with `sudo dnf install steam`.

On Fedora, the build and X11 launcher dependencies are:

```bash
sudo dnf install git clang lld llvm nasm ninja-build cmake \
  gcc gcc-c++ make pkgconf-pkg-config curl tar unzip zip patch diffutils \
  python3 file glibc-common libicu libunwind openssl-libs zlib-ng-compat \
  wmctrl xrandr xprop xwininfo procps-ng util-linux
```

On other distributions, install the equivalent packages. Ensure `clang-cl`,
`lld-link`, `llvm-rc`, `llvm-lib`, `llvm-mt`, `nasm`, `ninja`, `cmake`, `iconv`
and a native C/C++ compiler are available. Older distribution releases may
need a newer LLVM or CMake package. The first build also downloads and builds
vcpkg dependencies, so allow several gigabytes of disk space and an internet
connection.

### Install PowerShell 7

PowerShell is used only to convert upstream Visual Studio project files and run
build scripts, not to compile on Windows. Install it from the
[official Linux instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux)
or use the tested [7.7.0 release](https://github.com/PowerShell/PowerShell/releases/tag/v7.7.0)
without root privileges:

```bash
(
  set -e
  download_dir=$(mktemp -d)
  trap 'rm -rf -- "$download_dir"' EXIT
  cd "$download_dir"
  base=https://github.com/PowerShell/PowerShell/releases/download/v7.7.0
  asset=powershell-7.7.0-linux-x64.tar.gz
  curl -fLO "$base/$asset"
  curl -fLO "$base/hashes.sha256"
  iconv -f UTF-16 -t UTF-8 hashes.sha256 |
    grep -F "$asset" | tr -d '\r' | sha256sum -c -
  mkdir -p "$HOME/.local/opt/powershell-7.7.0" "$HOME/.local/bin"
  tar -xzf "$asset" -C "$HOME/.local/opt/powershell-7.7.0"
  chmod +x "$HOME/.local/opt/powershell-7.7.0/pwsh"
  ln -s "$HOME/.local/opt/powershell-7.7.0/pwsh" "$HOME/.local/bin/pwsh"
)
export PATH="$HOME/.local/bin:$PATH"
pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
```

Add `$HOME/.local/bin` to your shell's `PATH` permanently if it is not already
there. If `pwsh` is installed through your package manager, skip the manual
installation.

### Install xwin and download the Windows SDK

[xwin](https://github.com/Jake-Shadle/xwin) supplies the MSVC-compatible headers
and libraries without installing Visual Studio. You can install the pinned
[0.10.0 release](https://github.com/Jake-Shadle/xwin/releases/tag/0.10.0) directly:

```bash
(
  set -e
  download_dir=$(mktemp -d)
  trap 'rm -rf -- "$download_dir"' EXIT
  cd "$download_dir"
  base=https://github.com/Jake-Shadle/xwin/releases/download/0.10.0
  asset=xwin-0.10.0-x86_64-unknown-linux-musl.tar.gz
  curl -fLO "$base/$asset"
  curl -fLO "$base/$asset.sha256"
  printf '%s  %s\n' "$(cat "$asset.sha256")" "$asset" | sha256sum -c -
  tar -xzf "$asset"
  mkdir -p "$HOME/.local/bin"
  install -m 755 xwin-0.10.0-x86_64-unknown-linux-musl/xwin "$HOME/.local/bin/xwin"
)
xwin --version
```

Alternatively, with Rust and Cargo installed:

```bash
cargo install --locked --version 0.10.0 xwin
export PATH="$HOME/.cargo/bin:$PATH"
```

After reviewing and accepting Microsoft's SDK license, download the exact SDK
and CRT versions used by this fork:

```bash
xwin --accept-license --cache-dir ~/.cache/xwin --manifest-version 17 \
  --arch x86_64 --crt-version 14.44.17.14 --sdk-version 10.0.26100 \
  --http-retry 3 splat --use-winsysroot-style --preserve-ms-arch-notation \
  --output ~/.local/share/xwin
```

**Required:** LLVM's resource compiler needs a space-free path to the SDK.
Create this symlink after the splat:

```bash
if [ ! -e "$HOME/.local/share/xwin/winsdk" ]; then
  ln -s 'Windows Kits/10' "$HOME/.local/share/xwin/winsdk"
fi
test -d "$HOME/.local/share/xwin/winsdk/Include/10.0.26100"
```

Keep the SDK outside the repository. `XWIN_ROOT` can override its location;
use a path without spaces for both the build checkout and SDK root. The SDK
and CRT files must not be committed or redistributed with the project.

## 2. Clone and build Open Vanilla

Clone **this Linux fork**, not the upstream Windows repository:

```bash
git clone https://github.com/ChrisTitusTech/openvanilla.git
cd openvanilla
git submodule update --init src/eqlib contrib/vcpkg
git submodule update --init --recursive -- plugins
```

Build the loader, core libraries and built-in plugins, then build all 18
additional plugins:

```bash
./tools/linux/build.sh
./tools/linux/build-plugins.sh
```

The scripts bootstrap vcpkg, apply the pinned Linux compatibility patches,
configure a Release x64 cross-build with Ninja, and compile the binaries.
The second command regenerates the external projects from their `.vcxproj`
files and installs bundled plugin resources without overwriting existing files.
No manual CMake conversion is necessary for a fresh checkout.

If memory is limited, reduce concurrent compilation jobs:

```bash
CMAKE_BUILD_PARALLEL_LEVEL=4 ./tools/linux/build.sh
CMAKE_BUILD_PARALLEL_LEVEL=4 ./tools/linux/build-plugins.sh
```

All runtime files appear under:

```text
build/linux-x64/bin/release/
├── MacroQuest.exe
├── MQ2Main.dll
├── eqlib.dll
├── config/
├── plugins/
├── macros/
├── lua/
├── resources/
└── Logs/                 # Created at runtime
```

Check the results:

```bash
release="$PWD/build/linux-x64/bin/release"
file "$release/MacroQuest.exe" "$release/MQ2Main.dll" "$release"/plugins/*.dll
find "$release/plugins" -maxdepth 1 -name '*.dll' | wc -l
python3 tools/linux/check_filename_case.py --require-xwin
python3 -m unittest discover -s tools/linux -p 'test_*.py'
```

Expect 64-bit Windows PE binaries and 32 plugin DLLs after both builds.
The source submodules may appear modified in `git status` after building:
this is expected because the build applies compatibility patches and generates
CMake files locally. The upstream revisions remain pinned in the parent repo.

### Included plugins

<!-- markdownlint-disable MD013 -->
| Built-in (14) | External (18) |
| --- | --- |
| MQ2AutoBank, MQ2AutoLogin, MQ2Bzsrch, MQ2Chat, MQ2ChatWnd, MQ2CustomBinds, MQ2EQBugFix | MQ2AASpend, MQ2AdvPath, MQ2AutoAccept, MQ2Camera, MQ2Cast, MQ2DanNet, MQ2EasyFind, MQ2EQBC, MQ2Exchange |
| MQ2HUD, MQ2ItemDisplay, MQ2Labels, MQ2Lua, MQ2Map, MQ2TargetInfo, MQ2XTarInfo | MQ2GroupInfo, MQ2Melee, MQ2MoveUtils, MQ2Nav, MQ2PortalSetter, MQ2Relocate, MQ2Rez, MQ2Status, MQItemColor |
<!-- markdownlint-enable MD013 -->

External sources come from [RedGuides](https://github.com/orgs/RedGuides/repositories?q=props.Type%3Aplugin),
[brainiac](https://github.com/brainiac) and [dannuic](https://github.com/dannuic).
All 18 compile as x64 DLLs. Installed does not mean loaded: MacroQuest's
`[Plugins]` configuration determines which plugins load at startup. Optional
helper executables (EQBCS, Nav's console tool and MeshGenerator) are not built
by `build-plugins.sh`. Nav also needs appropriate navigation mesh data, which
is not included in the source checkout.

## 3. Install EverQuest and GE-Proton

Install EverQuest in Steam (app ID `205710`). The launcher assumes the usual
native Steam root, `~/.steam/steam`, which normally points to
`~/.local/share/Steam`.

Install the tested GE-Proton release into Steam's `compatibilitytools.d`
directory. On a new native Steam installation:

```bash
(
  set -e
  download_dir=$(mktemp -d)
  trap 'rm -rf -- "$download_dir"' EXIT
  cd "$download_dir"
  base=https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-34
  curl -fLO "$base/GE-Proton10-34.tar.gz"
  curl -fLO "$base/GE-Proton10-34.sha512sum"
  sha512sum -c GE-Proton10-34.sha512sum
  mkdir -p "$HOME/.steam/steam/compatibilitytools.d"
  tar -xzf GE-Proton10-34.tar.gz -C "$HOME/.steam/steam/compatibilitytools.d"
)
```

Restart Steam, open EverQuest's Properties > Compatibility, enable the
option to force a compatibility tool, and select GE-Proton10-34. Launch the
game from Steam at least once, let the game finish patching, confirm it runs,
and close it. This initializes the Proton prefix and installs game files.

Verify the expected paths:

```bash
steam_root="$HOME/.steam/steam"
test -x "$steam_root/compatibilitytools.d/GE-Proton10-34/proton"
test -f "$steam_root/steamapps/common/Everquest F2P/eqgame.exe"
test -d "$steam_root/steamapps/compatdata/205710/pfx"
```

MacroQuest and every EverQuest client must use this **same Proton version and
prefix**. The launcher starts the Windows executable directly, using `patchme`
after the Steam installation is up to date. Do not use a separate Wine prefix
for each character; they need the shared Wine session.

## 4. Run MacroQuest and EverQuest

Run these commands from a terminal in your X11 graphical session, not an SSH
shell or a managed process scope that kills child applications on exit.

First, test one client on a workspace your window manager supports:

```bash
TAGS="1" CHARS="-" ./tools/linux/mq-launch.sh
```

The script starts MacroQuest if necessary, starts EverQuest in the game's
prefix, waits for the game window, and assigns it to the selected workspace.
Log in manually the first time. In-game, use `/plugin list` to see which
plugins are loaded. The MacroQuest tray menu provides access to AutoLogin
profiles.

<!-- markdownlint-disable MD033 -->
<details>
<summary>Manual single-client launch for troubleshooting</summary>

From the repository root, with no other MacroQuest or EverQuest process
running, you can launch both executables without the workspace script:

```bash
export STEAM_COMPAT_DATA_PATH="$HOME/.steam/steam/steamapps/compatdata/205710"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam/steam"
export SteamAppId=205710 SteamGameId=205710
proton="$HOME/.steam/steam/compatibilitytools.d/GE-Proton10-34/proton"
mq_dir="$PWD/build/linux-x64/bin/release"
eq_dir="$HOME/.steam/steam/steamapps/common/Everquest F2P"
(cd "$mq_dir" && "$proton" run "$mq_dir/MacroQuest.exe") &
sleep 15
(cd "$eq_dir" && "$proton" run "$eq_dir/eqgame.exe" patchme) &
```

This uses the shared game directory rather than per-tag game settings.
The launcher script is preferred for multiboxing and also handles first-run
Wine application compatibility registry keys.

</details>
<!-- markdownlint-enable MD033 -->

### Multiboxing

Create an AutoLogin profile for each character using the MacroQuest tray menu,
or log in each character manually once. Profiles are stored in
`build/linux-x64/bin/release/config/login.db`. Keep that database private;
account passwords do not belong in the launcher configuration.

Close the existing test client before launching the same character again.
For four accounts, replace the example names with your own:

```bash
TAGS="3 4 5 6" CHARS="erollisi:Main erollisi:Alt1 erollisi:Alt2 erollisi:Alt3" \
  ./tools/linux/mq-launch.sh
```

The `TAGS` values are 1-based workspace numbers. `CHARS` entries must match
`TAGS` one for one, in the same order; use `-` for a manual login. The window
manager must have the requested workspaces available (`wmctrl -d`).

Rerun the same launcher command to fill missing slots after a client closes.
It skips running characters, including ones moved to another workspace, and
leaves their settings and windows alone. A slot occupied by a different
character is reported as a conflict instead of launching a second client there.

The default launcher uses plain Proton (no Gamescope) and waits for each
AutoLogin character to finish entering the game before focusing and launching
the next. This resolves the login stalls caused by switching focus too early.
Allow roughly a minute per client for startup; do not change focus during
AutoLogin. If a profile is missing or the server is slow, the launcher times
out and continues so you can finish that login manually.

### DanNet communication

MQ2DanNet is included in the external plugin build and enabled in the shipped
configuration. It discovers peers directly; no EQBC server is needed. Start
the clients normally, then use `/echo ${DanNet.Peers}` in the game to see
connected characters. `/dnet interface` shows the discovered interfaces.
The current GroupInfo plugin's default group buttons use DanNet.

DanNet's Zyre/CZMQ transport uses UDP port `5670` for discovery and dynamic
TCP ports `49152-65535` for peer connections. If discovery is blocked by a
host firewall, allow these ports in the zone used by your game machines.
For firewalld, the following example applies both permanent and runtime
rules in one elevation. Substitute the appropriate active zone if different:

```bash
sudo bash -c 'zone=public
firewall-cmd --permanent --zone="$zone" \
  --add-port=5670/udp --add-port=49152-65535/tcp &&
firewall-cmd --zone="$zone" \
  --add-port=5670/udp --add-port=49152-65535/tcp'
```

On the tested Linux host, allowing these ports resolved failed discovery
between two clients on the same machine. Other firewall rules were unchanged.
See the [DanNet documentation](https://github.com/dannuic/MQ2Dan) for commands
and configuration options.

### Save your launch configuration

```bash
mkdir -p "$HOME/.config/openvanilla"
```

Create `~/.config/openvanilla/mq-launch.conf` with shell variable assignments,
for example:

```bash
TAGS="3 4 5 6"
CHARS="erollisi:Main erollisi:Alt1 erollisi:Alt2 erollisi:Alt3"
GS_RES="auto"
GAMESCOPE=0
LOGIN_TIMEOUT=120
```

Then launch without repeating the settings:

```bash
./tools/linux/mq-launch.sh
```

The config is sourced as a shell file, so use a trusted local file. Values
passed in the calling environment override the saved configuration.

| Variable | Default / purpose |
| --- | --- |
| `TAGS` | `3 4 5 6`; one client per workspace |
| `CHARS` | No AutoLogin unless supplied; `server:character` or `-` |
| `GS_RES` | `auto`; fixed `WxH`, or one resolution per tag |
| `GAMESCOPE` | `0`; optional nested compositor when set to `1` |
| `GS_ARGS` | `--force-grab-cursor` for Gamescope; empty disables it |
| `LOGIN_TIMEOUT` | 120 seconds per AutoLogin client; `0` skips waiting |
| `LAUNCH_DELAY` | 2 seconds between clients after the current startup wait |
| `WINDOW_TIMEOUT` | 180 seconds waiting for each window |
| `PROTON` | `~/.steam/steam/compatibilitytools.d/GE-Proton10-34/proton` |
| `EQ_DIR` | `~/.steam/steam/steamapps/common/Everquest F2P` |
| `MQ_DIR` | `<checkout>/build/linux-x64/bin/release` |
| `EQ_INSTANCES` | `~/.local/share/openvanilla/eq-instances` (XDG data) |
| `MQ_LAUNCH_CONF` | `~/.config/openvanilla/mq-launch.conf` (XDG config) |

For a nonstandard Steam library, set `STEAM_ROOT`, `STEAM_COMPAT_DATA_PATH`
and `EQ_DIR` in the calling environment as appropriate, and point `PROTON`
at the actual Proton executable. `STEAM_COMPAT_DATA_PATH` must point to the
app's compatdata directory, not its `pfx` subdirectory. Use absolute paths.

Example, when only the game library is on a second drive:

```bash
STEAM_COMPAT_DATA_PATH="/mnt/games/SteamLibrary/steamapps/compatdata/205710" \
EQ_DIR="/mnt/games/SteamLibrary/steamapps/common/Everquest F2P" \
  ./tools/linux/mq-launch.sh
```

### Independent client resolutions

Every tag has its own `eqclient.ini` and `Logs/` directory under
`~/.local/share/openvanilla/eq-instances/tag<N>/`. Other game files are symlinked
to the shared install, so separate resolution settings do not require multiple
copies of EverQuest. On the first launch the game configuration is seeded from
the install. The launcher sets windowed mode, size and zero offsets without
changing other video settings.

With `GS_RES=auto`, dwm-titus detects the monitor displaying each tag and
subtracts docked panels. On other EWMH window managers, the primary monitor
is used as a fallback. You can override the detected resolution explicitly:

```bash
GS_RES="2560x1410 1920x1050 1920x1050 1920x1050" ./tools/linux/mq-launch.sh
```

### Optional Gamescope

[Gamescope](https://github.com/ValveSoftware/gamescope) can isolate each client
in a nested compositor, but it is **not the recommended default** for this
setup. Standalone concurrent Gamescope instances worked at mixed resolutions;
EverQuest clients exhibited X11 `BadWindow` failures and Vulkan swapchain
recreation loops. On NVIDIA, concurrent realtime Vulkan queues have also
caused GPU faults ([upstream report](https://github.com/ublue-os/bazzite/issues/6089)).

If you want to experiment, install Gamescope and override the default:

```bash
GAMESCOPE=1 ./tools/linux/mq-launch.sh
```

The launcher removes Gamescope's realtime capability with
`setpriv --no-new-privs`, but that does not resolve every compatibility issue.
Return to `GAMESCOPE=0` if clients freeze or exit.

### Optional tray bridge for Quickshell or Waybar

MacroQuest uses Wine's X11 XEmbed tray icons. If your panel only supports
StatusNotifierItem (SNI), install [wine-sni-bridge](https://github.com/waliori/wine-sni-bridge)
following its instructions. On Fedora its Python dependencies are
`python3-xlib`, `python3-dbus`, and `python3-gobject`. Start the bridge before
MacroQuest. On X11 tiling WMs such as dwm, set `override_redirect=True` on the
bridge's tray window so the WM does not tile or close it. If the bridge
restarts, restart MacroQuest to restore the icon. See
[Linux implementation notes](tools/linux/README.md#running-multibox) for details.

When the bridge script is installed at `~/.local/bin/wine-sni-bridge.py`,
the following user service is the configuration tested on Fedora. Save it as
`~/.config/systemd/user/wine-sni-bridge.service`:

```ini
[Unit]
Description=Wine SNI Bridge - X11 tray to StatusNotifierItem
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/bin/python3 %h/.local/bin/wine-sni-bridge.py --byte-order native
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now wine-sni-bridge.service
```

## 5. Keep the build and settings up to date

When EverQuest patches, update the game through Steam and make sure the
pinned Live eqlib version matches the current client before launching.
Close game clients and MacroQuest before replacing the binaries.
Update this fork and its pinned dependencies, not arbitrary branches of
individual plugins:

```bash
git status --short
git pull --ff-only
git submodule update --init src/eqlib contrib/vcpkg
git submodule update --init --recursive -- plugins
./tools/linux/build.sh
./tools/linux/build-plugins.sh
python3 tools/linux/check_filename_case.py --require-xwin
python3 -m unittest discover -s tools/linux -p 'test_*.py'
```

If a submodule update is blocked by local patches or your own changes, do not
force-reset it.
A clean checkout of the updated fork is the simplest reliable upgrade path;
keep the old build until the new one is tested and migrate settings selectively.

Back up these directories before moving to a new checkout or machine:

- `build/linux-x64/bin/release/config/` (MacroQuest and plugin settings, and
  private AutoLogin profiles).
- `build/linux-x64/bin/release/macros/`, `lua/`, and user-created files in
  `resources/` (including Nav meshes).
- `~/.config/openvanilla/` (launcher settings).
- `~/.local/share/openvanilla/eq-instances/tag<N>/eqclient.ini` (per-client
  video and game options; the other entries are generated links).

Restore ordinary settings and macros selectively, and recreate AutoLogin
profiles for the new Proton prefix if needed. Do not copy old plugin DLLs or
overwrite current version-specific defaults wholesale. Macros and plugin
configuration formats can change between releases.

## Troubleshooting

<!-- markdownlint-disable MD013 -->
| Symptom | What to check |
| --- | --- |
| `xwin splat not found` | Confirm the SDK is downloaded and the `winsdk` symlink exists; set `XWIN_ROOT` if using another location. |
| Compiler, CMake, or PowerShell missing | Check the tool versions and `PATH`. Linux builds use native tools, not Visual Studio or Wine's compiler. |
| `proton not found` / `eqgame.exe not found` | Check the Steam library paths, selected Proton version and `PROTON` / `EQ_DIR` overrides. |
| MacroQuest doesn't load | Confirm the game is patched, eqlib matches Live, and both executables share the same Proton prefix. |
| Window or AutoLogin stalls | Use `GAMESCOPE=0`, keep the active client focused during startup, verify the profile, or increase `LOGIN_TIMEOUT`. |
| Plugin installed but not loaded | Check `/plugin list`, the current `[Plugins]` section in `config/MacroQuest.ini`, and the MacroQuest logs. |
| No tray icon | Check XEmbed/SNI support and start the optional tray bridge before MacroQuest. |
| Crashpad database errors | The Linux build uses a Crashpad stub; these errors are expected. Normal crash-reporting integration is not implemented. |
| Gamescope swapchain loop / X11 `BadWindow` | Disable Gamescope. Check kernel logs for NVIDIA Xid errors and reboot if the GPU entered a reset-required state. |
<!-- markdownlint-enable MD013 -->

Useful diagnostics (adjust the tag number):

```bash
tail -n 50 "$HOME/.local/share/openvanilla/eq-instances/tag3/Logs/launch.log"
tail -n 50 "$HOME/.local/share/openvanilla/eq-instances/tag3/Logs/dbg.txt"
ls -lt build/linux-x64/bin/release/Logs/
pgrep -x eqgame.exe
journalctl -k --since '-10 min'
```

## Development and fork maintenance

The build still uses the upstream Windows ABI and existing MacroQuest runtime.
The Linux additions are intentionally small: native clang-cl cross-compilation,
vcpkg overlay triplets and ports, resource compiler fixes, case-sensitive path
fixes, external plugin compatibility patches, and per-client launch handling.

- [Linux development guide](tools/linux/README.md): toolchain internals,
  filename-case checks, CMake regeneration, patches and upstream synchronization.
- [Project specification](SPEC.md) and [architecture decisions](ANSWERS.md).
- [MacroQuest documentation](https://docs.macroquest.org/).

Keep `.vcxproj` files as the source of truth when changing build metadata.
After merging upstream source changes, regenerate root CMake projects with
`pwsh ./batch-convert.ps1` and run the checks in the Linux development guide.
External projects are regenerated by `build-plugins.sh`. A local check hook is
available:

```bash
git config core.hooksPath tools/linux/hooks
```

Custom plugin source directories belong under `plugins/`, not `src/plugins/`.
Use the Linux external build path with `MQ_BUILD_CUSTOM_PLUGINS=ON` and select
compatible target names through `TARGETS`. The pinned plugins provide working
examples; a new plugin may need further Linux compatibility fixes.

### Directory structure

| Directory | Purpose |
| --- | --- |
| `build/` | Generated build files and runtime binaries |
| `contrib/` | Third-party dependencies and vcpkg |
| `data/` | Default configuration and runtime assets |
| `extras/` | Optional upstream projects |
| `include/` | Public MacroQuest headers |
| `plugins/` | Pinned external and personal plugins |
| `src/` | MacroQuest core, eqlib, loader and built-in plugins |
| `tools/linux/` | Linux build, launcher, patches and validation tools |
| `tools/conversions/` | Visual Studio to CMake converter |

<!-- markdownlint-disable MD012 MD013 MD022 MD028 MD031 MD033 MD040 -->
<details>
<summary>Historical upstream Test / Emulator reference (not supported by this Linux fork)</summary>

The original upstream notes are retained below for reference. The build steps
mentioned here refer to the upstream Windows guide, not the Linux workflow
above. Do not change the pinned Live eqlib revision for this Linux build.

### Building for Test or Emulator
The only difference between builds is the `eqlib` submodule. The `master` branch pins `eqlib` to **Live**. To build a different client, point `eqlib` at the matching branch before building:


For **EverQuest Test**:
```
git -C src/eqlib checkout test
```

For **EverQuest RoF2 (Emulator)**:
```
git -C src/eqlib checkout emu-rof2
```

To go back to **Live**:
```
git -C src/eqlib checkout live
```

> [!IMPORTANT]
> `git submodule update` will reset `eqlib` back to Live. Re-run your client's command above to fix.

> [!NOTE]
> RoF2 (Emulator) builds use the `Win32` platform instead of `x64` in the Build Steps below.

</details>
<!-- markdownlint-enable MD012 MD013 MD022 MD028 MD031 MD033 MD040 -->

[License](LICENSE.md). This fork is built on work from the MacroQuest and
RedGuides contributors; it is not an official EverQuest Linux client.
