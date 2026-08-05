# fperl

A fork of **X-Perl UnitFrames** (by Zek) for **WoW 3.3.5a**, patched for a 5-man-scaled server
with cross-faction groups.

Base addon © Zek, GPL v3 — see `LICENSE.txt`. This fork keeps that license.

## Installing

> **The folder must be named `XPerl`, not `fperl`.** Textures load from a path with that name in
> it, so renaming the folder gives you a broken addon.

```
git clone https://github.com/JerrodTanner/fperl.git "Interface/AddOns/XPerl"
```

Then `/reload`. Your existing XPerl settings carry over.

---

## Raid frames in a party

**Raid tab → Show In Party** (on by default). Raid frames now cover a 5-man party as well as a
raid, **including your own frame** — so you can untick everything on the Party tab and only ever
look at raid frames.

**Show When Solo** underneath keeps your frame up when you're not grouped.

**Party Uses Group 1 Only** (on by default) keeps the other group blocks hidden while you're in a
party, whatever their own settings say. Ignored when sorting by class, where the blocks are
classes rather than groups.

In a party everyone lands in the group 1 block, so it uses your group 1 position. Sort By Class
works in a party too. Raid *pet* frames stay raid-only.

Replaces the old **One-Group Raid Show** on the Party tab, which is gone.

## Raid buffs and debuffs at the same time

They used to switch each other off. Now independent, both on the **Raid tab**:

| Option | What it does |
| --- | --- |
| **Raid Buffs** / **Raid Debuffs** | Turn each row on. Both can be on at once. |
| **Castable Only** / **Curable Only** | Filter buffs to what you can cast, debuffs to what you can cure. |
| **Buff Position** / **Debuff Position** | Above, below, left or right of the frame. Defaults: buffs below, debuffs above. |
| **Buff Size** / **Debuff Size** | Icon size. Icons wrap to a new row once they no longer fit across the frame. |

**Buffs to Right** and **Buffs Inside** are gone — Position replaces them. **Buffs Until Debuffed**
now only applies if you have debuffs turned off.

## Buff order on raid frames

Buffs used to show in whatever order the game happened to keep them, which reshuffles as they
drop and get reapplied. Now it's **HoTs first, then whatever expires soonest**.

HoTs hold a fixed order however much time is left on them, so the row doesn't jump around as
ticks land: Rejuvenation, Regrowth, Wild Growth, Lifebloom, Renew, Riptide.

**Raid tab → Hide Group Buffs** leaves the long group buffs out of the row — Mark of the Wild,
Fortitude, Spirit, Shadow Protection, Arcane Intellect and the Blessings, single and group version
of each. Worth ticking: only 8 icons fit per frame, and on a fully buffed target those alone can
push your own HoTs off the row entirely.

## Timers on raid buff and debuff icons

Raid icons now get the sweep and the countdown number that the party and player frames have always
had. Set on the **Buffs tab**, separately for your own auras and everyone else's:

| Option | What it does |
| --- | --- |
| **My Cooldown** / **Their Cooldown** | The sweep around the icon. |
| **My Countdown** / **Their Countdown** | Seconds remaining, as a number. Works with the sweep turned off. |
| **Countdown Start** | How many seconds remaining before the number appears. 1 to 99, now defaults to 99. |

Those four replace the old single on/off plus **All** pair, so "number but no sweep" is possible
for the first time. Your existing settings carry over.

## Test mode — `/xperl test`

Gives you **two sample raid groups** with sample buffs and debuffs so you can set the above up
without being in a raid. Run it again to turn it off.

Leave the options window open while it's on — Position, Size, scale, spacing, anchor, mana bar and
percentages all update the samples live. Sample aura counts run 1 to 8 across the ten frames, so
whichever icon size you pick, something on screen shows you where the row wraps.

- Sample frames can't be clicked or targeted, and don't simulate aggro, range fading or incoming
  heals. Layout, sizes, colours and wrapping are accurate.
- A group with real people in it is left alone, so this never draws over your actual raid.
- Out of combat only, and off again after a reload.

## Raid markers on party frames

Party frames now show the skull/X/square on the member, not just on their target. Right-click a
party frame → **Set Raid Target** to set one; right-clicking in a raid also gives the raid options.
Marker sits top-right of the name.

## Healers see every dispel type highlighted

The dispellable-debuff highlight was limited to what your class can normally remove. Healers now
get all four types, since healers here can dispel everything. **Non-healers are unchanged**, and
"healer" means healing *spec* — it updates on respec and dual-spec swap without a reload.

## Bigger party and raid frames

**Party Scale**, **Party Pet Scale** and **Raid Scale** now reach **225%** instead of 150%. Still
tied to **Maximum Frame Scale** on the Miscellaneous tab, at 1.5x whatever that's set to.

## Range fading on cross-faction group members

Frames for cross-faction group members never faded and their out-of-range icon was stuck on. Range
for them now comes from group membership, which ignores faction. Everyone else is unchanged.

Flat 40 yards for those members, so it ignores your configured spell range. Cross-faction pets
aren't covered.

To confirm it works on your server, group cross-faction, stand next to them and run
`/run print(UnitInRange("party1"))` — **true** means it's working.

## Fixes

- Debuffs set to sit above a raid frame no longer overlap the name.
- The options window is taller, so the Raid tab's settings all fit. Enable/disable per raid group
  was already there under **Groups** — it was only ever hidden off the bottom of the panel.
- The three "No sibling found called..." errors when leaving a group. Two options were replaced by
  the Position dropdowns, but something still went looking for them.
- Buff and debuff **Position**, **Size**, **Castable Only** and **Curable Only** now grey out when
  their own row is switched off.
- Test mode no longer draws a sample frame on top of your own when you're solo with Show When Solo
  on, and every Raid tab option redraws the samples now — the raid pet ones didn't.
- Frame scale and position no longer reset after a relog. Opening the options window could
  overwrite a saved scale with 50%, which moved the frame too.
- Spells that wouldn't cast and action buttons that went blank. The addon was replacing some
  Blizzard functions, which tainted Blizzard code paths and got protected actions refused.
  **Unconfirmed** — if it persists, check for "Interface action failed because of an AddOn"; if
  instead spells are greyed in your spellbook with no error, that isn't something this addon can
  cause and it's worth testing with X-Perl disabled.

---

**None of this has been played yet.** Treat the first session as the test, and say if anything
looks wrong — especially the new Raid tab controls, which were laid out without being able to see
the tab.
