#!/usr/bin/env bash
# Start MacroQuest and N EverQuest clients under Proton, each on its own
# tag/workspace: switch to the tag, launch, wait for the window, repeat (tools/linux/README.md, "Running (multibox)").
# Usage: tools/linux/mq-launch.sh
#   TAGS            1-based tags, one client per entry (default: "3 7 8 9")
#   PROTON          proton script (default: GE-Proton10-34 in compatibilitytools.d)
#   EQ_DIR          EverQuest install (default: Steam's "Everquest F2P")
#   MQ_DIR          directory holding MacroQuest.exe (default: build/linux-x64/bin/release)
#   LAUNCH_DELAY    seconds between a client's window appearing and the next launch (default: 2)
#   WINDOW_TIMEOUT  seconds to wait for each client window (default: 180)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
steam="${STEAM_ROOT:-$HOME/.steam/steam}"
read -r -a tags <<<"${TAGS:-3 7 8 9}"
proton="${PROTON:-$steam/compatibilitytools.d/GE-Proton10-34/proton}"
eq_dir="${EQ_DIR:-$steam/steamapps/common/Everquest F2P}"
mq_dir="${MQ_DIR:-$repo/build/linux-x64/bin/release}"
launch_delay="${LAUNCH_DELAY:-2}"
window_timeout="${WINDOW_TIMEOUT:-180}"

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

# Managed EverQuest windows. Proton sets WM_CLASS to steam_app_<id> for every
# process in the prefix (MacroQuest too), so also match the "EverQuest" title.
eq_windows() {
    wmctrl -lx | awk '(tolower($3) ~ /^(steam_app_205710|eqgame\.exe)\./) && $5 ~ /^EverQuest/ { print $1 }'
}

declare -A seen=()
while read -r win; do
    [[ -n "$win" ]] && seen["$win"]=1
done < <(eq_windows)

if pgrep -f 'MacroQuest\.exe' >/dev/null; then
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
    printf 'client %d: launching eqgame.exe patchme (tag %d)\n' "$client" "$tag"
    (cd "$eq_dir" && exec "$proton" run "$eq_dir/eqgame.exe" patchme) >/dev/null 2>&1 &

    win=""
    deadline=$((SECONDS + window_timeout))
    while [[ -z "$win" ]]; do
        (( SECONDS < deadline )) || die "client $client: no window after ${window_timeout}s"
        sleep 1
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
