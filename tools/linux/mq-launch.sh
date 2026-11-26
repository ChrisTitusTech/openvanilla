#!/usr/bin/env bash
# Start MacroQuest and N EverQuest clients under Proton, each on its own
# tag/workspace: switch to the tag, launch, wait for the window, repeat (tools/linux/README.md, "Running (multibox)").
# Usage: tools/linux/mq-launch.sh
#   TAGS            1-based tags, one client per entry (default: "3 4 5 6")
#   CHARS           optional AutoLogin characters paired with TAGS, as server:character
#                   ("-" = no auto-login), e.g. "erollisi:Tums erollisi:Dantea"
#   PROTON          proton script (default: GE-Proton10-34 in compatibilitytools.d)
#   EQ_DIR          EverQuest install (default: Steam's "Everquest F2P")
#   EQ_INSTANCES    per-tag client directories, one tag<N> each: symlinks to EQ_DIR plus
#                   the client's own eqclient.ini and Logs/ (default:
#                   ~/.local/share/openvanilla/eq-instances)
#   MQ_DIR          directory holding MacroQuest.exe (default: build/linux-x64/bin/release)
#   LAUNCH_DELAY    seconds between a client's window appearing and the next launch (default: 2)
#   WINDOW_TIMEOUT  seconds to wait for each client window (default: 180)
#   GS_RES          EverQuest (and gamescope) resolution per client: one value for all
#                   or one per TAGS entry, each WxH or "auto" = the tag's monitor minus
#                   dock/panel bars along its edges (default: auto)
#   GAMESCOPE       1 = run each client in its own nested gamescope (client always sees
#                   itself focused); 0 = plain Proton (default: 1)
#   GS_ARGS         extra gamescope arguments (default: "--force-grab-cursor"; "" = none)
#   MQ_LAUNCH_CONF  shell file setting any of the above, e.g. CHARS="..."; variables set
#                   in the environment win (default: ~/.config/openvanilla/mq-launch.conf)
set -euo pipefail

conf="${MQ_LAUNCH_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/openvanilla/mq-launch.conf}"
if [[ -f "$conf" ]]; then
    # shellcheck disable=SC2153
    env_vars="$(declare -p TAGS CHARS PROTON EQ_DIR EQ_INSTANCES MQ_DIR LAUNCH_DELAY WINDOW_TIMEOUT \
        GS_RES GAMESCOPE GS_ARGS 2>/dev/null || true)"
    # shellcheck source=/dev/null
    source "$conf"
    eval "$env_vars"
fi

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
steam="${STEAM_ROOT:-$HOME/.steam/steam}"
read -r -a tags <<<"${TAGS:-3 4 5 6}"
read -r -a chars <<<"${CHARS:-}"
proton="${PROTON:-$steam/compatibilitytools.d/GE-Proton10-34/proton}"
eq_dir="${EQ_DIR:-$steam/steamapps/common/Everquest F2P}"
instances="${EQ_INSTANCES:-${XDG_DATA_HOME:-$HOME/.local/share}/openvanilla/eq-instances}"
mq_dir="${MQ_DIR:-$repo/build/linux-x64/bin/release}"
launch_delay="${LAUNCH_DELAY:-2}"
window_timeout="${WINDOW_TIMEOUT:-180}"
use_gamescope="${GAMESCOPE:-1}"
read -r -a gs_res <<<"${GS_RES:-auto}"
read -r -a gs_args <<<"${GS_ARGS---force-grab-cursor}"

export STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH:-$steam/steamapps/compatdata/205710}"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$steam}"
export SteamAppId=205710 SteamGameId=205710

die() { printf 'mq-launch: %s\n' "$*" >&2; exit 1; }

for tool in wmctrl pgrep; do
    command -v "$tool" >/dev/null || die "missing required tool: $tool"
done
[[ -n "${DISPLAY:-}" ]] || die "DISPLAY is not set (run from the X session)"
[[ -x "$proton" ]] || die "proton not found: $proton"
[[ -f "$eq_dir/eqgame.exe" ]] || die "eqgame.exe not found in: $eq_dir"
[[ -f "$mq_dir/MacroQuest.exe" ]] || die "MacroQuest.exe not found in: $mq_dir (run tools/linux/build.sh)"
(( ${#tags[@]} > 0 )) || die "TAGS is empty"
for tag in "${tags[@]}"; do
    [[ "$tag" =~ ^[1-9]$ ]] || die "invalid tag '$tag' (expected 1-9)"
done
if (( ${#chars[@]} > 0 && ${#chars[@]} != ${#tags[@]} )); then
    die "CHARS has ${#chars[@]} entries but TAGS has ${#tags[@]}"
fi
# Geometry "W H X Y" of the monitor showing 0-based desktop $1. dwm-titus gives
# each monitor its own tags and publishes x,y,w,h,current-tag per monitor in
# _DWM_MONITOR_DESKTOPS; other WMs fall back to the primary monitor.
tag_monitor() {
    local geom
    geom="$(xprop -root _DWM_MONITOR_DESKTOPS 2>/dev/null | awk -F' = ' -v d="$1" 'NF == 2 {
        n = split($2, v, ", ")
        for (i = 1; i + 4 <= n; i += 5) if (v[i + 4] == d) { print v[i + 2], v[i + 3], v[i], v[i + 1]; exit }
    }')"
    if [[ -z "$geom" ]]; then
        geom="$(xrandr --listactivemonitors | awk '$2 ~ /^\+\*/ { print $3; exit }')"
        [[ "$geom" =~ ^([0-9]+)/[0-9]+x([0-9]+)/[0-9]+\+([0-9]+)\+([0-9]+)$ ]] || return 1
        geom="${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
    fi
    printf '%s\n' "$geom"
}

# Monitor size (W H X Y) minus dock windows (panels/bars) docked to its edges.
playable_area() {
    local mw="$1" mh="$2" mx="$3" my="$4" w h x y id
    local top=0 bottom=0 left=0 right=0
    while read -r id w h x y; do
        (( x >= mx && y >= my && x + w <= mx + mw && y + h <= my + mh )) || continue
        xprop -id "$id" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q _NET_WM_WINDOW_TYPE_DOCK || continue
        if (( w == mw && y == my )); then (( h > top )) && top=$h
        elif (( w == mw && y + h == my + mh )); then (( h > bottom )) && bottom=$h
        elif (( h == mh && x == mx )); then (( w > left )) && left=$w
        elif (( h == mh && x + w == mx + mw )); then (( w > right )) && right=$w
        fi
    done < <(xwininfo -root -children | sed -nE 's/^ +(0x[0-9a-f]+) .*: \(.*\) +([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+) .*/\1 \2 \3 \4 \5/p')
    printf '%dx%d\n' "$((mw - left - right))" "$((mh - top - bottom))"
}

# Per-tag client directory: EverQuest reads and writes eqclient.ini and Logs/ in
# its working directory, so each client gets its own copies. Everything else is
# a symlink to the shared install, refreshed on every launch (new patch files,
# removed ones). The first run seeds eqclient.ini from the shared one.
prepare_instance() {
    local dir="$1"
    mkdir -p "$dir/Logs" || return 1
    find "$dir" -mindepth 1 -maxdepth 1 -xtype l -delete
    find "$eq_dir" -mindepth 1 -maxdepth 1 ! -name eqclient.ini ! -name Logs -print0 \
        | while IFS= read -r -d '' src; do
            [[ -e "$dir/${src##*/}" || -L "$dir/${src##*/}" ]] || printf '%s\0' "$src"
        done | xargs -0 -r ln -s -t "$dir" || return 1
    [[ -f "$dir/eqclient.ini" ]] || cp -p "$eq_dir/eqclient.ini" "$dir/eqclient.ini" 2>/dev/null || true
}

# Size EverQuest's window to the tile/nested screen: windowed, no offset (the WM
# or gamescope places it). Only the video keys change; other settings stay.
set_eq_video() {
    local ini="$1/eqclient.ini" tmp
    [[ -f "$ini" ]] || return 0
    tmp="$(mktemp)"
    awk -v w="$2" -v h="$3" '
        function want(sec, key) {
            if (sec == "defaults") return key == "windowedmodexoffset" ? "0" : key == "windowedmodeyoffset" ? "0" : key == "maximized" ? "0" : ""
            if (sec == "videomode") return key == "windowedwidth" ? w : key == "windowedheight" ? h : key == "fullscreen" ? "0" : ""
            return ""
        }
        function flush(   k) { for (k in pending) if (pending[k] != "") printf "%s=%s\r\n", k, pending[k]; delete pending }
        BEGIN {
            names["defaults"] = "WindowedModeXOffset WindowedModeYOffset Maximized"
            names["videomode"] = "WindowedWidth WindowedHeight Fullscreen"
        }
        { line = $0; sub(/\r$/, "", line) }
        line ~ /^\[/ {
            flush()
            sec = tolower(substr(line, 2, index(line, "]") - 2))
            if (sec in names) { n = split(names[sec], ks, " "); for (i = 1; i <= n; i++) pending[ks[i]] = want(sec, tolower(ks[i])) }
            print; next
        }
        {
            key = line; sub(/=.*/, "", key)
            v = want(sec, tolower(key))
            if (v != "" && index(line, "=")) { printf "%s=%s\r\n", key, v; delete pending[key]; next }
            print
        }
        END { flush() }
    ' "$ini" >"$tmp" && cat "$tmp" >"$ini"
    rm -f "$tmp"
}

if [[ "$use_gamescope" == 1 ]]; then
    for tool in gamescope setpriv; do
        command -v "$tool" >/dev/null || die "missing $tool (set GAMESCOPE=0 to run without gamescope)"
    done
fi
(( ${#gs_res[@]} == 1 || ${#gs_res[@]} == ${#tags[@]} )) \
    || die "GS_RES has ${#gs_res[@]} entries but TAGS has ${#tags[@]} (use one value or one per tag)"
for res in "${gs_res[@]}"; do
    [[ "$res" == auto || "$res" =~ ^[0-9]+x[0-9]+$ ]] || die "invalid GS_RES entry '$res' (expected WxH or auto)"
    [[ "$res" == auto ]] || continue
    for tool in xrandr xprop xwininfo; do
        command -v "$tool" >/dev/null || die "GS_RES=auto needs $tool (or set GS_RES=WxH)"
    done
done
for char in "${chars[@]}"; do
    [[ "$char" == - || "$char" =~ ^[^:]+:[^:]+$ ]] || die "invalid CHARS entry '$char' (expected server:character or -)"
done

# Top-level window owned by a PID (gamescope's nested output window).
pid_window() {
    wmctrl -lp | awk -v pid="$1" '$3 == pid { print $1; exit }'
}

# Managed EverQuest windows. Proton sets WM_CLASS to steam_app_<id> for every
# process in the prefix (MacroQuest too), so also match the "EverQuest" title.
eq_windows() {
    wmctrl -lx | awk '(tolower($3) ~ /^(steam_app_205710|eqgame\.exe)\./) && $5 ~ /^EverQuest/ { print $1 }'
}

declare -A seen=()
while read -r win; do
    [[ -n "$win" ]] && seen["$win"]=1
done < <(eq_windows)

# MacroQuest's App Compatibility check errors out (popup) when the AppCompatFlags
# keys are missing, which they are in a fresh Wine prefix. Create them empty once.
pfx="$STEAM_COMPAT_DATA_PATH/pfx"
for entry in HKLM:system.reg HKCU:user.reg; do
    hive="${entry%%:*}"
    # .reg files store the key with doubled backslashes.
    grep -qi 'AppCompatFlags\\\\Layers\]' "$pfx/${entry#*:}" 2>/dev/null && continue
    printf 'creating %s AppCompatFlags key in the prefix\n' "$hive"
    # proton's steam.exe wrapper won't start builtins like reg; use its wine directly.
    WINEPREFIX="$pfx" "$(dirname "$proton")/files/bin/wine" reg add "$hive\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\AppCompatFlags\\Layers" /f >/dev/null 2>&1 \
        || die "failed to create $hive AppCompatFlags key"
done

# MacroQuest.exe relaunches as a randomly named copy with /spawnedprocess; match
# that Wine process, not a leftover proton/steam.exe wrapper.
if pgrep -f '^[A-Za-z]:\\.*\.exe /spawnedprocess' >/dev/null; then
    printf 'MacroQuest.exe already running\n'
else
    printf 'starting MacroQuest.exe\n'
    (cd "$mq_dir" && exec "$proton" run "$mq_dir/MacroQuest.exe") >/dev/null 2>&1 &
    sleep 15
fi

client=0
for tag in "${tags[@]}"; do
    client=$((client + 1))
    # The WM's _NET_CURRENT_DESKTOP/_NET_WM_DESKTOP handlers take 0-based indexes.
    wmctrl -s "$((tag - 1))"
    # MQ2AutoLogin reads /login: and looks the character up in MacroQuest's login.db.
    args=(patchme)
    char="${chars[client - 1]:--}"
    [[ "$char" == - ]] || args+=("/login:$char")
    printf 'client %d: launching eqgame.exe %s (tag %d)\n' "$client" "${args[*]}" "$tag"
    res="${gs_res[0]}"
    (( ${#gs_res[@]} == 1 )) || res="${gs_res[client - 1]}"
    if [[ "$res" == auto ]]; then
        sleep 0.3 # let the WM publish the switched tag
        read -r mon_w mon_h mon_x mon_y < <(tag_monitor "$((tag - 1))") \
            || die "client $client: could not detect the monitor for tag $tag (set GS_RES=WxH)"
        res="$(playable_area "$mon_w" "$mon_h" "$mon_x" "$mon_y")"
    fi
    gs_w="${res%x*}" gs_h="${res#*x}"
    printf 'client %d: resolution %s\n' "$client" "$res"
    inst="$instances/tag$tag"
    prepare_instance "$inst" || die "client $client: could not prepare $inst"
    set_eq_video "$inst" "$gs_w" "$gs_h"
    if [[ "$use_gamescope" == 1 ]]; then
        # Fixed inner (-w/-h) and outer (-W/-H) size; dwm may resize the outer window,
        # gamescope scales, and EQ never sees a mode change or focus loss.
        # no_new_privs drops gamescope's file CAP_SYS_NICE: two gamescopes with
        # realtime Vulkan queues fault NVIDIA GPUs (Xid 51 BAD_TSG; ublue-os/bazzite#6089).
        (cd "$inst" && exec setpriv --no-new-privs gamescope -w "$gs_w" -h "$gs_h" -W "$gs_w" -H "$gs_h" "${gs_args[@]}" \
            -- "$proton" run "$inst/eqgame.exe" "${args[@]}") >/dev/null 2>&1 &
    else
        (cd "$inst" && exec "$proton" run "$inst/eqgame.exe" "${args[@]}") >/dev/null 2>&1 &
    fi
    launcher_pid=$!

    win=""
    deadline=$((SECONDS + window_timeout))
    while [[ -z "$win" ]]; do
        (( SECONDS < deadline )) || die "client $client: no window after ${window_timeout}s"
        sleep 1
        if [[ "$use_gamescope" == 1 ]]; then
            kill -0 "$launcher_pid" 2>/dev/null || die "client $client: gamescope exited (check: gamescope -- glxgears)"
            win="$(pid_window "$launcher_pid")"
            continue
        fi
        while read -r candidate; do
            if [[ -n "$candidate" && -z "${seen[$candidate]:-}" ]]; then
                win="$candidate"
                break
            fi
        done < <(eq_windows)
    done
    seen["$win"]=1

    # Pin it in case the tag changed before the window mapped.
    wmctrl -i -r "$win" -t "$((tag - 1))"
    printf 'client %d: window %s -> tag %d\n' "$client" "$win" "$tag"

    if (( client < ${#tags[@]} )); then sleep "$launch_delay"; fi
done
wmctrl -s "$((tags[0] - 1))"
printf 'launched %d clients\n' "$client"
