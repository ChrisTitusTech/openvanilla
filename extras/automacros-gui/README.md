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

- All classes: auto melee, return to camp, camp
  radius, assist HP, follow, fellowship, instant release, verbose
  notifications and backoff.
- Bard: slow, mez and bring your own spells.
- Monk: auto pull, pull radius, vertical radius, NPC name filter,
  readiness thresholds, combat abilities and burn policy. See the monk section below.
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
   the pull radius (default 350 units) and camp radius (default 30 units).
3. Enable **Auto pull**, or run `/autolua pullon`.

Auto pull is off on the first run and requires a freshly anchored camp
each script session or zone change. A loaded MQ2Nav zone mesh is required.
The monk enumerates loaded NPCs through the native MQ Lua spawn API.
Horizontal camp radius and vertical radius (default 90) are independent.
Living, targetable non-pet NPCs are filtered for special service classes,
encounter locks, trap NPCs and the optional literal name substring. Unknown or
partial NPC HP does not disqualify a living pull candidate. Valid targets
are ranked by actual MQ2Nav path length, subject to a maximum path
distance (default 1000). The GUI and log report candidate counts and
rejection reasons. While navigating out, the monk rescans every five
seconds and switches if a materially shorter path becomes available.
If MQ2Nav reports arrival before the actual NPC is in tag range and line
of sight, the monk halves the navigation approach range down to 10
units, rather than repeating an identical path. If that still fails,
the target is temporarily skipped.

The monk uses **Distant Strike** when ready, falling back to **Throw Stone**.
It resolves the actual AA ID, confirms its target and ability activation
using casting/cooldown state, and retries or moves closer until aggro is
confirmed (default timeout 15 seconds). Confirmed activation gets a
three-second aggro grace period before a fallback approach. AutoLua
disables MQ2Melee throughout the entire monk session, including in camp,
during combat, when pulling is off, and when zoning. On a graceful
AutoLua stop, it restores the plugin's original enabled state without
saving changes to MQ2Melee's configuration. A manual feign or invisibility
pauses navigation and retains the return state until the monk is standing
and visible again.

**Feign death to dump aggro** is enabled by default. Once camp combat is
underway and a nearby group tank can take over, the monk dumps actual
top hate, including hate on other extended targets. It prefers learned
Imitate Death and falls back to the Feign Death skill. Attack and stick
stop before the request; AutoLua confirms the actual feigned state and
waits for hate and health to recover before standing, removing the AA's
temporary invisibility if needed. The monk holds attack when initial
pull hate has not yet transferred to the tank. Healthy pull aggro does
not trigger a feign while traveling.

On pulls and returns, instant Mend, Purify Body and usable self-only
defensives may protect the monk without stopping navigation. Critical
health (default 50%, configurable) triggers an emergency feign; a
stalled return under attack can trigger one earlier at 65% HP. After
recovery, the monk abandons that pull, temporarily skips the target and
returns to the saved camp. Stalled navigation is replanned when the
monk is not rooted or stunned.

At camp, the monk scans all occupied extended-target slots for living
NPCs. It prioritizes an eligible group assist target, otherwise the
lowest-health eligible NPC, confirms the target, and controls basic attack
and stick directly. Other mobs already in camp can be fought immediately,
even while the pulled mob is still on its way. After a target dies, AutoLua
releases its attack and stick before engaging the next NPC.

With **Monk combat and recovery abilities** enabled (default), AutoLua
enumerates learned combat abilities at startup and chooses the highest
learned line and rank. It refreshes its ability list during downtime
after a level change or every five minutes. It uses trained melee
skills (Flying Kick, Tiger Claw and applicable alternatives), the
Synergy, Fists, Phantom, Fang, Curse and Shuriken discipline lines,
combat buff AAs and disciplines, Mend, Purify Body when needed,
endurance recovery and the monk aura. Defensive discs are prioritized
when health is low. Major damage discs and burn AAs are used against
named targets or when at least three live encounter NPCs are inside
the configured camp radius. Ordinary fights, elapsed fight time and
extended targets outside camp do not trigger burns.
Long-duration active discs are not overwritten. Offensive abilities require a
valid target and range; readiness, health and endurance reserves are checked. Requests are
confirmed from cooldown or cast state and failed requests back off.
The log records the resolved ability list, unclassified learned
disciplines, requests and activation results; the GUI displays the last
confirmed ability. Automatic FD is limited to aggro dumps and emergency
survival. No forced target movement, area damage, veteran AA or
equipment clicky rotation is enabled.

The next pull waits for combat to finish and for monk/group health
(default 80%), endurance (50%) and healer mana (50%). During safe
downtime the monk uses available endurance recovery, respects the
learned recovery discipline's activation cap (Breather Rk. III: 29%),
and sits until its configured health/endurance requirements are met.
The GUI status displays recovery progress; the monk stands for incoming
combat or when ready to resume pulling.
If the group starts fighting or falls below readiness during approach,
the monk returns to camp. Failed/unreachable targets are skipped for
30 seconds. This is single-pull automation; it does not implement
automatic feign-death splitting or coordinated raid burn rotations.

Commands:

- `/autolua pullon` and `/autolua pulloff` enable/disable new pulls.
- `/autolua pullradius 200` sets a radius from 50 to 10000 units.
- `/autolua pullstatus` displays the current state.
- `/autolua camphere` re-anchors camp and `/autolua campoff` clears it.
- `/autolua meleeoff` disables basic auto melee without enabling MQ2Melee.
- `/autolua backoff` stops pulling and auto melee; MQ2Melee remains off.
- `/autolua stop` stops the script, releases its owned attack, stick
  and navigation, and restores MQ2Melee's previous enabled state.
  The GUI Stop AutoLua button does the same. Use graceful stop rather
  than forcibly terminating the Lua process to ensure cleanup.

For an already-installed GUI/Selo overlay, apply only
`monk-integration.patch`, copy the updated `gui.lua`, new `mnk.lua`, and
`test_monk.lua` as shown above. No rebuild or relog is required. The
offline suite exercises the pull cycle, 3D camp coordinates, group
readiness, native spawn enumeration, path ranking, AA activation and
retry, rescan, trap rejection, early navigation arrival, aggro dump and emergency feign recovery, plugin suspension/restoration, multi-target
camp combat, learned-rank selection, capped endurance recovery, sit/resume, burn coordination, mob-arrival wait, GUI persistence, timeout, cancellation,
and zone invalidation. Existing character INI settings are preserved
when upgrading; the new path limit and timeout are initialized on first
run. Live pathing and ability activation still need verification in the
current zone.

The scan/path-ranking and action-confirmation design is informed by the
open-source [RG Mercs pull module](https://github.com/DerpleDude/rgmercs/blob/a4b1ffc3f97a9c13a97510e4693b4d6ca6501b40/modules/pull.lua)
and [casting utilities](https://github.com/DerpleDude/rgmercs/blob/a4b1ffc3f97a9c13a97510e4693b4d6ca6501b40/utils/casting.lua);
AutoLua implements its own camp-specific state machine.
