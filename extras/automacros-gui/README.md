# AutoLua configuration window and class extensions

In-game ImGui configuration for the locally installed AutoLua 1.5 port
of AutoMacros. This is an optional overlay, not a replacement for the
underlying AutoLua scripts.

## In-game use

Start AutoLua normally with `/lua run automacros`. The configuration
window opens automatically. Close or hide it without stopping the script;
`/autolua gui` opens it again. During startup, the window shows the
current startup phase and elapsed time. Settings become visible as soon as
they are loaded and unlock once the runtime can process changes.

- All classes: melee, return to camp, camp radius, assist HP, follow,
  fellowship, instant release, verbose notifications and backoff.
- Bard: slow, mez and bring your own spells.
- Monk: auto pull, pull radius, vertical radius, NPC name filter and
  readiness thresholds. See the monk section below.
- Cleric: resurrection, Promised heals, Divine buff, druid buffs, heal
  and mana thresholds, mount item, Quiet Miracle recipient and tank
  selection. The cure suppression setting applies only to this session.

Checkboxes apply immediately on the next runtime event pump. Sliders and
the mount item use their individual Apply buttons. The existing
`config/automacros/Auto_Player_<character>.ini` remains the single
persistent configuration per character. The existing aliases still work.
Bring your own spells affects spell setup when the script restarts.

After installing or updating this overlay, restart only AutoLua on the
character when safe to do so:

```text
/lua stop automacros
/lua run automacros
```

No client restart or MacroQuest rebuild is needed.

## Apply to an existing AutoLua 1.5 installation

The AutoLua sources are not tracked in this repository; the overlay is
kept here so it survives removal of the local build output. The integration
patch targets the existing AutoLua 1.5 runtime and offline test suite.
From the repository root:

```bash
overlay="$PWD/extras/automacros-gui"
lua_dir="$PWD/build/linux-x64/bin/release/lua"
cd "$lua_dir/automacros"
patch --dry-run -p1 < "$overlay/integration.patch"
patch -p1 < "$overlay/integration.patch"
patch --dry-run -p1 < "$overlay/selo-refresh.patch"
patch -p1 < "$overlay/selo-refresh.patch"
patch --dry-run -p1 < "$overlay/monk-integration.patch"
patch -p1 < "$overlay/monk-integration.patch"
cp "$overlay/gui.lua" gui.lua
cp "$overlay/mnk.lua" mnk.lua
cp "$overlay/test_gui.lua" tests/test_gui.lua
cp "$overlay/test_monk.lua" tests/test_monk.lua
cd "$lua_dir"
luajit automacros/tests/test.lua
```

Apply the integration patch to unmodified AutoLua 1.5 sources. For an
installation with the earlier GUI overlay, reverse the earlier integration
patch first (available at commit `5520e30c`), then apply the updated patch.
The updated patch also fixes the unnecessary zone-settle wait when the
configured follow target is the legacy placeholder. The tests use mocked
MQ data and do not operate on the game or real INIs. Actual startup timing
depends on the client and spell setup.


## Bard Selo refresh

The additional `selo-refresh.patch` applies to the AutoLua 1.5 Bard
runtime and its offline tests. It resolves the actual rank-I/II triggered
speed buffs (Selo's Accelerando/Accelerato), checks their remaining
duration at least every five seconds when idle between casts, and refreshes
the instant AA during combat as well as downtime. Attempts are paced at
15 seconds if the buff does not appear. Active casts, invisibility, and
feign death remain protected. The log records the observed buff name and
duration after a successful observation.

For an existing installation with the GUI overlay already applied, apply
only `selo-refresh.patch` once and restart AutoLua on the bard. The offline
suite covers early buff disappearance, rank lookup fallback, combat
refresh, and the inter-song casting boundary.


## Monk AutoLua

The new native Lua class module is selected automatically on a monk by
`/lua run automacros`. It does not require a legacy `auto_MNK.mac`.

1. Move the monk to the desired camp with the group and click
   **Set camp here** (or use `/autolua camphere`).
2. On the monk's GUI, optionally enter the NPC name substring and adjust
   the pull radius (default 200 units) and camp radius (default 30 units).
3. Enable **Auto pull**, or run `/autolua pullon`.

Auto pull is off on the first run and requires a freshly anchored camp
each script session or zone change. A loaded MQ2Nav zone mesh is required.
The monk chooses a living, targetable, uninjured non-pet NPC within the
configured radius and vertical limit, excluding special service classes.
An optional literal name substring restricts the NPC selection further.
If no idle target can be reached, the GUI reports the reason.

The monk uses **Distant Strike** when ready, falling back to **Throw Stone**.
It approaches via MQ2Nav when necessary, confirms its target, waits for
hostile aggro or combat state, returns to the camp's saved XYZ coordinates
and fights from camp. The next pull waits for combat to finish and for
monk/group health (default 80%), endurance (50%) and healer mana (50%).
If the group starts fighting or falls below readiness during approach,
the monk returns to camp. Failed/unreachable targets are skipped for
30 seconds. This is single-pull automation; it does not implement
automatic feign-death splitting or a full monk burn rotation.

Commands:

- `/autolua pullon` and `/autolua pulloff` enable/disable new pulls.
- `/autolua pullradius 200` sets a radius from 50 to 500 units.
- `/autolua pullstatus` displays the current state.
- `/autolua camphere` re-anchors camp and `/autolua campoff` clears it.
- `/autolua backoff` stops pulling and melee; `/autolua stop` stops the
  script and its owned movement. The GUI Stop AutoLua button does the same.

For an already-installed GUI/Selo overlay, apply only
`monk-integration.patch`, copy the updated `gui.lua`, new `mnk.lua`, and
`test_monk.lua` as shown above. No rebuild or relog is required. The
offline suite exercises the pull cycle, 3D camp coordinates, group
readiness, navigation, target selection, GUI persistence, timeout,
cancellation, and zone invalidation. Live pathing and ability activation
still need verification in the current zone.
