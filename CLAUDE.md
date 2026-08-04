# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A fork of **X-Perl UnitFrames** (Zek, GPL v3) for **World of Warcraft 3.3.5a**, patched for a
private 5-man-scaled AzerothCore server with cross-faction groups. Lua + Blizzard XML, loaded by
the game client — there is no build step, no package manager, no test suite.

The base addon normally ships as ~17 separate AddOn folders; this is an **all-in-one build** where
every module lives in one folder. See "Module system" below — that difference drives real code.

## Working on it

There is nothing to run outside the game. Verification means installing and reloading:

- The addon folder **must be named `XPerl`**. Textures are loaded from hardcoded
  `Interface\Addons\XPerl\images\...` paths, so a folder named `fperl` produces a broken addon.
  Clone or symlink to `Interface/AddOns/XPerl`.
- `/reload` in game to pick up Lua/XML changes. `/xperl` opens the options panel.
- Load order is declared in `XPerl.toc` and, per group, in the `<Script>` lists of `XPerl.xml`,
  `XPerl_Globals.xml`, and each module's XML. A new file needs adding to one of those or it never
  loads. Cast bars load before the frames that attach to them.
- Lua errors surface only in game — use an error display addon (BugSack/!BugGrabber) or
  `/console scriptErrors 1`. `XPerl_Notice(...)` and `XPerl_ShowMessage(...)` print to chat.

### 3.3.5a API constraints

Target `## Interface: 30300`. Retail/Classic-era APIs do not exist here:

- **No `C_Timer`** — defer work with a one-shot `OnUpdate` script that clears itself (see the
  `ScheduleApply` pattern at the bottom of `XPerl_Modules.lua`).
- No `C_*` namespaces generally; use `GetNumRaidMembers`/`GetNumPartyMembers` (not
  `GetNumGroupMembers`), `GetTalentTabInfo`, `getglobal`, `UnitDebuff` with filter strings.
- `UnitPopupFrames`, `UIDropDownMenu_Initialize`, secure-frame attributes behave as in WotLK.
- Register events defensively with `pcall(f.RegisterEvent, f, event)` when an event may not exist
  on this client build.
- Anything that touches secure frames must respect `InCombatLockdown()`; the codebase queues such
  work via `tinsert(XPerl_OutOfCombatQueue, func)`.

## Architecture

### Module system (`XPerl_Modules.lua`)

Because the modules are no longer real AddOns, this file reimplements the enable/disable system.
A per-character SavedVariable `XPerlModuleState` holds the *desired* state; a session table holds
what is actually *running*. That split is what makes the options panel's "Reload UI" button light
up correctly. Disabled modules are torn down at load (frames hidden, events unregistered) rather
than not loaded.

It exposes `XPerl_ModuleEnable`, `XPerl_ModuleDisable`, `XPerl_ModuleLoaded`, `XPerl_ModuleLoad`
and `XPerl_ModuleGetInfo`, which stand in for `EnableAddOn`, `DisableAddOn`, `IsAddOnLoaded`,
`LoadAddOn` and `GetAddOnInfo`. **Call those, not the Blizzard originals**, anywhere in X-Perl —
they fall through to the real function for any name that isn't one of our modules, so they are
safe everywhere.

**Never assign to those Blizzard globals.** An earlier version of this file did, so that
untouched module code kept working. Blizzard's own code calls them (`UIParentLoadAddOn` for the
talent/glyph/trainer/inspect panels, the AddOn list), which tainted those execution paths — and a
tainted path is refused protected actions, showing up in game as spells that won't cast, action
buttons that go blank, and "Interface action failed because of an AddOn", intermittently. There
are currently no Blizzard global function overrides anywhere in the addon; keep it that way.

Consequence: **the `MODULES` table in this file must be updated** if a module gains or loses a
top-level frame, or suppresses a different Blizzard frame. `blizz` entries feed
`XPerl_ModuleBlizzKeep()`, which lets the default Blizzard frame survive when its X-Perl
replacement is off.

### Config

`XPerlDB` is the live config table. Modules do not read it directly at load — they call

```lua
XPerl_RequestConfig(function(new) conf = new end, "$Revision: 396 $")
```

and get handed the table once it exists (and again whenever the config mode changes). Anything
that reads config at file scope will see `nil`, which is the cause of several bugs this fork
fixed — the options sliders were computing their maximums before `XPerlDB` existed.

Persistence is split across `XPerlConfigNew` (global vs per-character, keyed by realm and name)
plus the per-character variables listed in `XPerl.toc`. Defaults live in `XPerl_Defaults()` in
`XPerl_Options/XPerl_FrameOptions.lua`; `UpgradeSettings()` in the same file patches configs saved
by older versions, and is where a retired option gets migrated.

**Saved frame positions are scale-coupled.** `XPerl_SavePosition` stores `GetTop() * GetScale()`
and `XPerl_RestorePosition` divides by the current scale, so anything that corrupts a frame's
saved scale also moves the frame. A bug that looks like "my frame position reset" is usually a
scale bug. Options widgets must never write config from a widget value they haven't first read
from config — `XPerl_Options_MaxScaleRefresh` and the `refreshingSliders` guard exist because
`SetMinMaxValues`/`SetValue` fire `OnValueChanged`, and a slider on an unopened tab is still
sitting at its floor.

### Frames and events

Each module is an XML file defining frame templates plus a Lua file of **globally named**
functions (`XPerl_Party_OnLoad`, `XPerl_Party_UpdateDisplay`, …) referenced from the XML. Nothing
is namespaced in a table; new helpers follow the same `XPerl_<Module>_<Thing>` naming.

Events use a dispatch table per module: `XPerl_Party_Events` keyed by event name, with an
`XPerl_<Module>_Events_OnLoad` that registers a hardcoded list and an `XPerl_<Module>_OnEvent`
that looks the handler up. `UNIT_*` events are re-dispatched to the frame owning that unit. To
handle a new event you must add it to **both** the registration list and the table.

Shared per-unit rendering lives in `XPerl.lua` as `XPerl_Unit_*` functions used by every module
(portrait, level, buffs, ready state), with the debuff-highlight logic built per class in
`XPerl_DebufHighlightInit()`.

### Localization

Localization files assign **global string constants** (`XPERL_MINIMAP_HELP1`, `XPERL_CMD_LOCK`, …);
`localization.lua` is enUS and the per-locale files overwrite selectively. Options panel strings
live separately under `XPerl_Options/localization.*.lua`, likewise `XPerl_RaidAdmin/` and
`XPerl_RaidFrames/`. Adding a user-visible string means adding it to the enUS file at minimum.

## Fork-specific behaviour

Read `README.md` first — it is written for the server's players and describes each change plus what
is still unverified in game. The code touchpoints:

- **Cross-faction range** (`XPerl.lua` ~lines 219-320). The client computes a cross-faction group
  member as hostile, so helpful-spell probes return `nil` and `CheckInteractDistance` always
  fails. `XPerl_IsCrossFactionAlly()` detects the case, `XPerl_InGroupRange()` measures off the
  roster's 40-yard flag, and `NormaliseRange()` only falls back for that case so same-faction
  units report exactly as before. Prefer `XPerl_CheckInteractDistance()` over raw
  `CheckInteractDistance()` in frame code.
- **Raid frames in a party** — the Raid tab's `inParty`/`solo` options. `SetMainHeaderAttributes`
  in `XPerl_RaidFrames/XPerl_Raid.lua` sets `showParty`/`showPlayer`/`showSolo` on the group
  headers; `XPerl_Raid_ShouldShow()` gates the driver frame. This works because 3.3.5a's
  `SecureGroupHeader_Update` reports every party member as **subgroup 1** with their real class,
  so group 1's existing filter matches a whole party and groups 2-8 match nobody —
  `SecureRaidGroupHeaderTemplate` is just `SecureGroupHeaderTemplate` plus `showRaid = true`.
  `SetRaidRoster` also walks the party when there is no raid, or everything keyed off
  `XPerl_Roster` (AFK/DND, res tracking, name colouring) silently does nothing.
  This replaced "One-Group Raid Show", which had the party frames stand in for your own raid
  subgroup — the inverse approach. If you find a reference to `XPerl_Party_ReplacesMyRaidGroup`
  or `party.smallRaid`, it is a leftover.
- **Raid frame auras** — buffs and debuffs are independent rows with their own enable, anchor and
  icon size (`rconf.buffs` / `rconf.debuffs` in `XPerl_Raid.lua`). They used to share one row, so
  the options could only ever enable one. Icons wrap to fit the frame, so `perRow` is normally
  absent and derived from the frame width and icon size. `buffs.right`/`buffs.inside` are retired.
- **Test mode** (`/xperl test`, `XPerl_Raid_TestMode` in `XPerl_Raid.lua`) — two sample groups for
  configuring aura layout outside a raid. Secure headers can only be filled by the game from the
  real roster, so this builds its own **non-secure** frames from `XPerl_Raid_FrameTemplate` and
  runs them through the same `Setup1RaidFrame` and `LayoutAuras` as live frames — keep it that way
  rather than reimplementing layout, or the preview stops matching reality. It skips any group with
  real members (`SubgroupCounts`), refuses to run in combat (the template inherits
  `SecureActionButtonTemplate`, so `CreateFrame`/`SetHeight` are unsafe under lockdown), and is
  re-driven from `XPerl_Raid_OptionActions` and `XPerl_Raid_Position`.
- **Scale ceiling** — sliders carry a `maxFactor` (1.5 for party/party pet/raid) multiplied into
  `XPerlDB.maximumScale` in `XPerl_Options/XPerl_FrameOptions.lua`.
- **Healer dispel highlight** — `PlayerIsHealer()` in `XPerl.lua` decides by talent tab, not class,
  caches the answer, and clears the cache on respec/dual-spec events. It deliberately does not
  cache a negative answer when talents aren't readable yet.
- **Raid markers on party frames** — `XPerl_Party_RaidIcon()` creates its texture on demand rather
  than in XML, and party frames use `XPerl_ShowGenericMenu` instead of Blizzard's
  `PartyMemberFrameNDropDown` so the raid menu is available in a raid.

## Conventions

- Match the surrounding style: tabs, `if (cond) then` with parenthesised conditions, `local`
  upvalue caching of Blizzard functions at the top of a file, `-- FunctionName` comment above each
  function.
- Every fork change carries a comment saying what the original behaviour was and why it changed —
  future readers are diffing against upstream X-Perl. Keep doing this.
- Commit messages: a one-line summary, then a bullet per behaviour change stating what now happens
  and why the old behaviour was wrong. See `git log` — both existing commits follow it.
- Keep GPL v3 headers on files that have them; upstream files are Zek's.
