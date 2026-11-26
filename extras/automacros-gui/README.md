# AutoLua configuration window

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
cp "$overlay/gui.lua" gui.lua
cp "$overlay/test_gui.lua" tests/test_gui.lua
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
