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
works in a party too.

**Raid pet frames follow.** They used to be raid-only, on the grounds that the party pet frames
covered a party — but those go away with the party frames now, which left party pets with no frame
at all. **Raid tab → Raid Pets** now fills from the party the same way group 1 does, your own pet
included, and **Align To Raid** still parks the block beside your last used group.

While the raid frames are covering a party, **the party frames take themselves off screen** — party
pet frames with them, since they hang off the party frames. Two sets of bars for the same five
people is exactly what turning this on is meant to replace. If you want both at once, tick
**Party tab → Show In Raid**, which is now what decides it.

They only stand down if the raid frames really are drawing everybody: untick group 1 under
**Groups** (or, sorting by class, a class somebody in the party is playing) and the party frames stay
up, rather than both being gone.

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

**Your spec's proc leads the row, ahead of even the HoTs**, so the 8-icon limit can never push it
off. It only applies to the spec that plays around it — a fire mage sees nothing different.

| Your spec | Leads the row |
| --- | --- |
| Balance druid | Eclipse (Lunar), Eclipse (Solar) |
| Feral druid | Clearcasting (Omen of Clarity) |
| Frost death knight | Rime, Killing Machine, Unbreakable Armor |
| Unholy death knight | Ghoul Frenzy, Gargoyle |
| Arcane mage | Missile Barrage, Clearcasting |
| Fire mage | Hot Streak |
| Frost mage | Fingers of Frost |
| Survival hunter | Lock and Load |
| Arms warrior | Sudden Death |
| Protection warrior | Sword and Board |
| Retribution paladin | The Art of War |
| Enhancement shaman | Maelstrom Weapon |
| Demonology warlock | Molten Core, Decimation |
| Rogue, any spec | Slice and Dice |

Respeccing switches it over on its own. **Castable Only has to be off** for these to show at all —
it limits the row to buffs you can cast on someone, and a proc isn't one.

## Stack counts on raid buff and debuff icons

Raid icons now show the stack number in the corner the way the player and target frames always
have, so a five stack Maelstrom Weapon or Sunder Armor no longer looks the same as one. Shown only
above one stack. Both rows have a stacking sample in `/xperl test`.

**Raid tab → Hide Group Buffs** leaves the long group buffs out of the row — Mark of the Wild,
Fortitude, Spirit, Shadow Protection, Arcane Intellect and the Blessings, single and group version
of each. Worth ticking: only 8 icons fit per frame, and on a fully buffed target those alone can
push your own HoTs off the row entirely.

**Hide Auras**, beside it, leaves out the proximity auras — the ones with no timer at all. Paladin
auras, totem buffs, Blood Pact, Fel Intelligence, Trueshot Aura, Leader of the Pack, and mounts.
They don't expire and there's nothing to react to, so they're only ever taking up icon slots.
Anything with no duration counts, so the server's own auras are covered without a spell list to
keep up to date.

**Hide Consumables**, under those two, leaves out what people drink and eat — flasks, elixirs, food
(**Well Fed**), scrolls, the potions that leave a buff behind (Speed, Wild Magic, Indestructible,
Insane Strength, Mighty Rage, Free Action) and **Flame Cap**. Usually two icons per frame back on a
raid where everyone is flasked and fed. Leave it off when you want to check who actually consumed.
Check it with `/xperl test` — the buff samples include a flask and a **Well Fed**, and both go when
you tick the box.

It works from a spell list, so a flask or elixir the list doesn't know still shows — say which and
it's a one-line fix. Anything with **Scourgebane** in the name is matched by name instead, so both
the Draught and the Infusion go whatever their buffs turn out to be called. Scroll buffs are named
after the stat, plain **Agility** or **Stamina**, so a server buff by one of those exact names would
be hidden too; say so and those six entries come out.

**Hide Sated** on the debuff row leaves out Bloodlust and Heroism's cooldown debuff — **Sated** and
**Exhaustion**, whichever version the shaman who cast it had. It sits there for ten minutes, can't
be removed, and with 8 icons to spend it can push a debuff you *do* need to see off the row. When
the debuff row hides it, the icons close up behind it rather than leaving a gap.

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
percentages all update the samples live.

**There's one sample per filter, and they're judged by your own settings.** So the preview answers
"is this option actually doing what I want?", not just "where does the row wrap?". Tick **Hide
Sated** and the Sated icon goes, because the option removed it. Every filter has a sample no other
filter touches, so each one visibly changes the row on its own.

| Buff sample | Removed by |
| --- | --- |
| Rejuvenation — *yours* | — (first in the row, being a HoT) |
| Mark of the Wild | **Hide Group Buffs** |
| Devotion Aura | **Hide Auras** (no duration) |
| Flask of Endless Rage — *someone else's* | **Hide Consumables** |
| Inner Fire — *someone else's* | **Castable Only** |
| Maelstrom Weapon *(5 stacks)* | — (previews the stack number) |

| Debuff sample | Removed by |
| --- | --- |
| Sated | **Hide Sated** |
| Shadow Word: Pain *(yours, Magic)* | — (this is what **Curable Only** keeps) |
| Deep Wounds | **Curable Only** (nothing removes it) |
| Sunder Armor *(5 stacks)* | — (previews the stack number) |

Sweeps and countdown numbers are real, run through the same timer the live rows use, and each
sample knows whether *you* cast it — so **My Cooldown / Their Cooldown**, **My Countdown / Their
Countdown** and **Countdown Start** all preview as configured. Remaining times deliberately
straddle the Countdown Start threshold, so some numbers show and some don't. Each icon re-arms on
its own sample's cycle as it runs out, so the row never goes dead while you're looking at it.

Buffs preview in the real display order too: HoTs first, then soonest to expire. The fixed order
*among* HoTs needs two of them on one frame, so that part only shows on a live row.

- Sample frames can't be clicked or targeted, and don't simulate aggro, range fading or incoming
  heals. Layout, sizes, colours, wrapping, order, filters and timers are accurate.
- A group with real people in it is left alone, so this never draws over your actual raid.
- Out of combat only, and off again after a reload.
- A sample spell this client doesn't know just leaves itself out.

## Your debuffs on top of the target frame

**Target tab → My Debuffs Above.** The debuffs *you* cast get their own row directly above the
target frame, so your DoTs are readable without looking away from the health bar. Buffs and anyone
else's debuffs stay exactly where they were, under the frame.

Not the same as **Above** further down the tab, which moves buffs and debuffs together. They work
together: with both on, your row sits above that stack rather than on top of it. **Flip** is followed
too. Tick **Only My Debuffs** as well if you don't want anyone else's under the frame either.

Icons wrap by frame width and stack upwards, honouring **Debuff Size** and **Max Rows**, so a long
row never lands on the frame itself.

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
