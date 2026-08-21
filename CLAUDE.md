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
  work via `tinsert(XPerl_OutOfCombatQueue, func)`. Only ever `tinsert` into it — the
  `PLAYER_REGEN_ENABLED` drain in `XPerl_Globals.lua` swaps in a fresh table and walks the detached
  one by index, which is defined behaviour only because every key is an integer. A queued call may
  queue more work; that lands in the new table and runs at the next combat end, not in the same
  pass. Each entry goes through `XPerl_pcall`, so one failing entry no longer loses the rest of the
  queue — keep that, and don't swap it for a bare `pcall`: it routes the error to
  `geterrorhandler()`, which is what keeps a failure visible instead of silently dropping a frame's
  configuration.

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
  Two things follow from the raid frames covering a party. `CheckRaid()` in `XPerl_Party.lua` hides
  the party header when the raid frames cover the group unless `pconf.inRaid` ("Show In Raid") — the
  party pet frames go with it, being children. It asks `XPerl_Raid_CoversParty()`, **not**
  `XPerl_Raid_ShouldShow()`: the latter only says the frames are up, while a group block turned off
  under Groups draws nobody, and hiding the party frames on that would leave members with no frame
  at all. Both of those, and the pet ones below, must first ask
  `XPerl_ModuleLoaded("XPerl_RaidFrames")`, because in this build the raid config stays readable
  after that module is torn down. Anything that changes whether the raid frames are up has to call
  `XPerl_Party_CheckRaid()`; `XPerl_Raid_OptionActions` does, and that wrapper checks
  `XPerl_ModuleLoaded("XPerl_Party")` itself — every other route into `CheckRaid` is a handler on
  frames teardown has already unregistered, but the options panel always runs, so without it a Raid
  tab click would put a disabled module's dead party frames back up. And `XPerl_RaidPets_HideShow`
  follows `RaidPetsShouldShow()` rather than `GetNumRaidMembers() > 0`, with `showParty`/`showPlayer`/
  `showSolo` set on `XPerl_Raid_GrpPets` from the **raid** config — the pet header walks group
  members and resolves each one's pet, so it fills from a party the same way. `XPerl_Raid_TitlePets`
  is the pet block's parent, so hiding it hides the pets; `XPerl_RaidPets_OptionActions` decides its
  visibility too and has to agree with `HideShow` (plus `XPerlLocked == 0`, so it can still be
  dragged while unlocked). `XPerl_RaidPet_UpdateGUIDs` walks `partypet1..4` and `pet` when there is
  no raid, or the GUID-keyed highlight lookups do nothing for party pets.
- **Instance zone-in refresh** (`ScheduleZoneRefresh` in `XPerl_Raid.lua`) — the roster the client
  reports while an instance is still loading can be missing the player, and the secure header then
  has nothing to draw for them and won't retry until the next roster event. So
  `PLAYER_ENTERING_WORLD` schedules a deferred `XPerl_Raid_ChangeAttributes()` (one second, via a
  self-stopping `OnUpdate` — no `C_Timer`), which re-fills every header. Deferred deliberately: the
  roster at event time is the thing that can't be trusted.
- **My Debuffs Above** (`target.debuffs.mineAbove`, `XPerl_Target.lua`) — `buffs.above` moves buffs
  and debuffs together because both rows are one chained stack, so this splits the debuff list by
  caster instead: `SplitMyDebuffs` reads `button.mine` (stamped in `XPerl_Unit_UpdateBuffs`) and
  `LayoutMyDebuffRow` anchors my icons above the frame, while the shared engine lays out the buffs
  and anyone else's debuffs as before. Two consequences elsewhere in `XPerl.lua`:
  `perlDebuffsMine` is now kept whenever this option is on (it feeds the `buffOptMix` that decides
  whether a re-layout is needed, and the total debuff count can stay put while the split changes),
  and `XPerl_Unit_BuffPositionsType` clears `hideFrom1`/`hideFrom2` on an empty list, since the
  lists handed to it are now rebuilt every update. That is also why the empty list is passed as
  `nil` and why the "nudge the bottom row up" branch tests `buffList2[1]`: the shared layout was
  written when the only lists it ever saw were the frame's own, whose first button always exists.
  `LayoutMyDebuffRow` has to follow `conf.flip` and, when `conf.buffs.above` is also on, start above
  the main stack's last row (`self.prevBuff`) rather than at the frame's top edge — otherwise both
  rows land on the same point.
- **Raid frame auras** — buffs and debuffs are independent rows with their own enable, anchor and
  icon size (`rconf.buffs` / `rconf.debuffs` in `XPerl_Raid.lua`). They used to share one row, so
  the options could only ever enable one. Icons wrap to fit the frame, so `perRow` is normally
  absent and derived from the frame width and icon size. `buffs.right`/`buffs.inside` are retired.
  Both rows are built by collecting first and drawing second (`CollectSortedBuffs`,
  `CollectDebuffs`), so a filtered aura closes the row up instead of leaving a hole — which is why
  the real aura index travels on the entry and goes onto the button with `SetID` for the tooltip.
  `AURA_SCAN_MAX` is **40, the whole aura list, and must not be lowered** as an optimisation. Both
  collectors break at the first missing aura, so the cap costs nothing for a unit carrying fewer
  auras than it — the only unit that ever reaches it is one that really has that many. And
  filtering runs *after* the scan, so hiding group buffs or consumables frees no scan slots: at 24
  a unit over the cap lost auras no option could bring back, and since a buff applied mid-fight
  takes a slot at the end of the list, the thing it lost was the freshest aura on the frame. That
  is what made the priority buffs below miss Eclipse on a well-buffed druid.
  The row's name/duration filters live in one place, `AuraFiltered()`: `buffs.hideGroupBuffs`,
  `buffs.hideAuraBuffs` (anything with no duration — paladin auras, totems, mounts),
  `buffs.hideConsumables` (flasks, elixirs, food, scrolls, buff-leaving potions, Flame Cap),
  `buffs.hideClassBuffs` (shields, armors, shouts, seals, Inner Fire, Thorns, Horn of Winter, plus
  the stances/forms/presences/aspects) and `debuffs.hideSated` (spell IDs 57724/57723). `Castable Only`/`Curable Only` are not in there:
  they are filter strings handed to the client and can only be judged against a real unit.
  The three spell-list filters are matched **by name**, resolved from real spell IDs through
  `AuraNameLists()` — which is the point, not an accident: every food in the game produces one buff
  called `Well Fed`, so one ID covers the whole category, and the scroll ranks collapse the same
  way. Several `consumableSpellIDs` entries therefore resolve to the same name deliberately. An ID
  the client doesn't know resolves to nothing and is skipped, so a missing consumable still draws
  rather than erroring — but do not pad the list with guessed IDs, because a wrong ID that *does*
  resolve hides an unrelated buff. Comment each entry with the **buff** name it resolves to, not the
  item's: the scroll block is the exception and is annotated as such, because a scroll's buff is a
  bare stat word (`Agility`, `Armor`) and so is the one group that can over-match even with correct
  IDs — a server-side buff by one of those names would go with it.
  `consumableNameParts` is the escape hatch for consumables whose spell ID can't be pinned down —
  server-added items, or a buff named differently from the item that applied it (`Scourgebane` covers
  both Scourgebane items and any variant). It is a **separate list on purpose**: a literal string
  always "resolves", so folding it into `consumableSpellIDs` would break the `resolved` counter that
  stops an empty set being cached before spell data is readable. Fragments are compared with
  `strfind(name, part, 1, true)` — plain, not a pattern — and only when the exact-name lookup misses.
  Keep the list short; it is walked per icon while the option is on.
  **Weapon enchants can never be filtered here.** Rogue poisons, sharpening stones and oils are temp
  enchants, not auras: `UnitBuff` never returns them, and `GetWeaponEnchantInfo` reports only your
  own weapons, so a raid frame cannot know another player has one. The player frame's two temp-enchant
  icons come from `XPerl_PlayerBuffs` and no raid option reaches them. Drums are deliberately absent for that reason: Drums of the Wild
  applies `Gift of the Wild`, which is already a `hideGroupBuffs` entry, so listing the drums would
  hide the druid's group buff whenever the consumables toggle was on and Hide Group Buffs was off.
  `classBuffSpellIDs` follows the same by-name rules — ranks collapse, unknown IDs are skipped, don't
  guess IDs. Two things are specific to it. **Nothing in `priorityBuffs` may be hidden by it**, and
  that is enforced in `AuraFiltered` (`not PriorityBuffNames()[name]`) rather than by keeping the
  tables apart by hand, so a self buff added to `priorityBuffs` later can't silently start vanishing
  — Slice and Dice is the live collision. And **racials stay out**: they aren't class buffs, and
  Berserking is test mode's Castable Only sample, which has to be one no other filter touches. The
  durationless entries (stances, forms, presences, aspects) duplicate what `hideAuraBuffs` catches on
  purpose, so the two options stand alone.
- **Spec priority buffs** (`priorityBuffs` / `PriorityBuffNames()` in `XPerl_Raid.lua`) — the procs a
  spec plays around sort ahead of even the HoTs on the raid buff row, so they are never the icon the
  8-cap pushed off. The table is keyed by class then talent tab (1-3), with an `all` key for a buff
  that matters in every spec; **both** the tab list and the `all` list apply. `AuraSortCompare` needs
  no knowledge of them: HoTs occupy 1..n and everything else 1000, so anything below 1 leads. Each
  priority buff gets its **own** rank, `PRIORITY_ORDER_BASE` counting up in listed order — not one
  shared rank, because equal ranks tie and fall through to the compare's aura-index tiebreak, which
  is the slot-reuse order the sort exists to hide, so two procs up at once would swap places as one
  refreshed into a different slot. A name already in the set keeps its first rank, so two ranks of
  one spell resolving to the same name don't reorder it.
  The gate is the **viewer's** class and spec, not the unit's — `XPerl_PlayerClass()` and
  `XPerl_PlayerTalentTab()`, both in `XPerl.lua` beside `PlayerIsHealer` and sharing its
  `BestTalentTab()` helper and its respec/dual-spec event frame. That frame registers
  **`PLAYER_REGEN_DISABLED`** on top of upstream's four talent events, and it is the one that
  matters here: spec changing on this server is a custom item, not the talent UI, so no talent event
  is guaranteed to fire for it — and with nothing clearing the cache, it holds the spec you had at
  login for the whole session (a balance druid who swapped to feral and back saw no Eclipse until a
  reload). Entering combat always fires and is when the answer starts to matter, so the tab is
  re-read at most once a fight. Reading talents isn't protected, so it's safe under lockdown. The
  consequence to know: a spec change reaches the rows by your next pull, not instantly. So a fire mage sees no change, and a
  frost mage sees Fingers of Frost lead on *any* frame that has it.
  `PriorityBuffNames()` keeps its own cache keyed on the talent tab rather than registering events:
  when `XPerl_PlayerTalentTab()` goes stale the tab differs and the set rebuilds. It follows the same
  rule as `AuraNameLists` — never cache a set when nothing resolved, since that means spell data
  isn't readable yet — but a spec with **no** entry does cache `emptyNames`, because that answer
  can't change. Entries may be a spell ID or a literal name string; prefer IDs, which resolve to
  whatever this server calls the spell.
  **Stack counts** are set in `UpdateAuraType` from the count `UnitBuff`/`UnitDebuff` returns, which
  the raid collectors used to discard — the `$parentcount` FontString has always been on
  `XPerl_BuffTemplate` and every other frame filled it. Shown only above 1, matching `XPerl.lua`.
  Test mode must clear it too: those buttons come from the same pool as the live ones, so a leftover
  count would sit on a sample icon. Its font is rescaled in `LayoutAuras` alongside the cooldown
  countdown's, and for the same reason — **any font on a raid aura button must be**. Other frames
  are spared because `XPerl_GetBuffButton` does `SetScale(size / 32)`, which takes the fonts with it;
  the raid rows set an explicit width and height, so a template font sized for a 32px icon would
  draw at full size on a 10px one.
- **Test mode** (`/xperl test`, `XPerl_Raid_TestMode` in `XPerl_Raid.lua`) — two sample groups for
  configuring aura layout outside a raid. Secure headers can only be filled by the game from the
  real roster, so this builds its own **non-secure** frames from `XPerl_Raid_FrameTemplate` and
  runs them through the same `Setup1RaidFrame` and `LayoutAuras` as live frames — keep it that way
  rather than reimplementing layout, or the preview stops matching reality. It skips any group with
  real members (`SubgroupCounts`), refuses to run in combat (the template inherits
  `SecureActionButtonTemplate`, so `CreateFrame`/`SetHeight` are unsafe under lockdown), and is
  re-driven from `XPerl_Raid_OptionActions` and `XPerl_Raid_Position`.
  There is **one sample per option that can filter the row** (`testBuffSamples` /
  `testDebuffSamples`), by **real spell ID**, so `AuraFiltered` judges them exactly as it judges live
  auras and the icon is the real icon; the preview is therefore how a user confirms a filter works.
  One each rather than two because `buffs.max` is a fixed 8 with no options widget and the trim in
  `PrepareTestAuras` runs after the sort, so the cap drops what a real row would drop: with pairs, a
  new filter's sample could only arrive by silently evicting another option's. **Adding a filter means
  adding one sample.** Each sample must also be one no *other* filter removes, or the options mask
  each other — that is why `Devotion Aura` is flagged castable though nothing can really cast it, and
  why `Inner Fire` exists purely as the not-castable case. Same rule as layout: run
  samples through the shared code (`AuraFiltered`, `AuraSortCompare`,
  `XPerl_CooldownFrame_SetTimer`), never a lookalike. `castable`/`curable` on a sample stand in for
  the client filter, which a made-up aura can't be judged by. `mine` drives which of the
  My/Their cooldown and countdown settings applies. `PrepareTestAuras` runs once per refresh (the
  filters are config, identical for every frame) with **one entry pool per row** — a shared pool
  lets the debuff pass overwrite the buff list. `testTicker` re-arms each icon as its own sample
  expires (`testTimers`, rebuilt per refresh); samples run from 5s to 25 minutes, so one shared
  interval would leave the short ones sitting expired — which is the state Countdown Start is judged
  against.
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
