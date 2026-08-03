# fperl

A fork of **X-Perl UnitFrames** (by Zek) for **WoW 3.3.5a / WotLK**, patched for a 5-man-scaled
AzerothCore server with cross-faction groups enabled.

Base addon © Zek, GPL v3 — see `LICENSE.txt`. This fork keeps that license.

## Installing

> **The folder must be named `XPerl`, not `fperl`.**

13 texture paths across 8 XML files are hardcoded as `Interface\AddOns\XPerl\...`, and WoW
requires `XPerl.toc` to match its parent folder name. Renaming the folder gives you missing
textures and an addon that won't load.

```
git clone https://github.com/JerrodTanner/fperl.git "Interface/AddOns/XPerl"
```

Then `/reload` or restart the client. Existing XPerl settings are preserved — no config
variables were renamed or removed.

---

## What's different

### 1. Party and raid frames scale 50% larger

The Party Scale, Party Pet Scale, and Raid Scale sliders were capped at the global
**Maximum Frame Scale** setting (150% by default). Those three now get 1.5× that ceiling, so
they reach **225%** out of the box.

**Where:** Party tab → *Party Scale* / *Party Pet Scale*; Raid tab → *Raid Scale*.

The headroom is a multiplier, not a fixed number, so it still composes with the global setting
(Miscellaneous → *Maximum Frame Scale*, up to 400%). Set that to 300% and party/raid reach 450%.
Every other frame keeps the normal ceiling.

Raid frame *width* is hardcoded at 80px in the layout code, so scale is the only size lever for
raid frames.

**Also fixed:** the scaling sliders are built before `XPerlDB` exists, so they were falling back
to a hardcoded 150% and ignoring a saved *Maximum Frame Scale* until you happened to touch that
slider. Slider ranges now refresh when the options window opens.

> **Note:** because ranges now refresh on open, if you have *Maximum Frame Scale* set **below**
> 150% and a frame scaled above it, opening the options window will clamp that frame's saved
> scale down to your stated maximum. Only affects people who deliberately lowered the global max.

---

### 2. Cross-faction range checking

On AzerothCore, `AllowTwoSide.Interaction.Group` lets Horde and Alliance group together, but
unless the server also spoofs `UNIT_FIELD_FACTIONTEMPLATE`, your **client** still computes those
group members as hostile. The range finder was gated behind `UnitCanAssist`, so for those units it
silently did nothing — frames never faded, and no error was raised.

Range for a cross-faction group member is now measured off the **group roster** (`UnitInRange`),
which is the only 40-yard signal in 3.3.5 with no faction test in it.

What changed:

- The `UnitCanAssist` gate now also admits cross-faction group members.
- Helpful-spell and bandage-item probes return `nil` for these units ("not a legal target" rather
  than "out of range"), and only *that* case falls back to the roster check. A same-faction unit you
  genuinely can't cast on — a corpse, for instance — still reports out of range exactly as before.
- The out-of-range **icon** on the party and target frames was hardcoded to `CheckInteractDistance`
  with Inspect, which is faction-restricted and so showed "out of range" permanently for a
  cross-faction ally at any distance. It now falls back to the roster check too.

Inspect-gated features (the gear/talent check in Raid Admin, `NotifyInspect` hooks) were left
alone — inspect genuinely doesn't work across factions, and a range fallback there would just
produce failed inspects.

#### Testing it in game

Group up cross-faction, stand next to them, and run:

```
/run print(UnitInRange("party1"), UnitCanAssist("player","party1"))
```

| Result | Meaning |
| --- | --- |
| 1st value truthy | Working as intended. |
| 1st value `false`/`nil` | **`UnitInRange` isn't usable for these units on your server.** Cross-faction frames will now be permanently *faded* instead of permanently un-faded — worse than before. Open an issue; the fix is to leave them at full alpha instead. |
| 2nd value already truthy | Your server spoofs the faction template. Nothing was broken for you and these changes are harmless no-ops. |

Then walk out past 40 yards and confirm the frame fades and the range icon appears.

**Limits:** the roster fallback is fixed at 40 yards, so for cross-faction members it ignores your
configured spell/item range and the 28-yard Inspect distance behind the range icon. Same-faction
members keep exact spell range. Cross-faction **pets** are not covered.

---

### 3. "One-Group Raid Show" now works at any raid size

**Party tab → *One-Group Raid Show***, previously arena-only.

**Before:** party frames stayed up and *all* raid frames hid, but only when the raid had ≤5
members who were all in group 1. Any bigger and it did nothing.

**Now:** party frames stay up in a raid of any size, and exactly **one** raid group frame is
hidden — the one the party frames are covering. Groups 2, 3, 4 … show as normal raid frames.

So in a 25-man you get party frames for your own group plus raid frames for the other six.

Details:

- The hidden group is read off `party1`'s subgroup rather than assumed to be group 1, so it stays
  correct if you're moved between groups.
- If `party1` doesn't exist — a 1-person raid, or if the party header isn't populated — **nothing**
  is hidden. Better a redundant raid frame than a group with nothing standing in for it.
- **Sort By Class is deliberately excluded.** In that mode raid frames are class columns, so your
  subgroup is spread across all of them and there's no single frame to hide. Raid frames behave as
  they always did there, which means your group appears in both the party and class frames.
- **Raid pet frames** use one header for all pets with no group filter, so they can't exclude a
  subgroup. They hide only when nobody is outside the covered group (the old behaviour), and show
  normally once a second group exists.
- Toggling the setting used to leave the raid frames stale until the next roster change, because
  its handler only refreshed the party side. It now refreshes both.
- The option's tooltip was describing the old arena-only behaviour and has been rewritten. The
  label is unchanged so it's still where you expect it.

`XPerl_Party_SingleGroup()` was replaced by `XPerl_Party_ReplacesMyRaidGroup()`. If you have other
addons or edits calling the old function, they'll need updating.

---

## Unverified assumptions

Honest disclosure — these were not confirmed in game, and there's no Lua interpreter on the
machine these edits were made on, so the first `/reload` is the first real compile:

1. **`UnitInRange` works for cross-faction group members.** The whole of change 2 rests on it. Use
   the test command above.
2. **The party header populates from your own subgroup while in a raid.** WoW's FrameXML wasn't
   extracted locally, so `SecurePartyHeaderTemplate`'s raid behaviour couldn't be read from source.
   Change 3 is fail-safe either way, but this determines whether it does anything when you're not
   in group 1. First time you're in a multi-group raid outside group 1, confirm the party frames
   and the hidden raid group are the same five people.
3. **Return types of `UnitInRange` / `IsItemInRange`** (boolean vs `1`/`nil`) are normalised
   defensively, so this one is safe either way rather than merely untested.

## Known pre-existing bug (not introduced here, not fixed)

`rconf = conf.raid`, so `conf.sortByClass` and `rconf.sortByClass` are different keys. Header
filtering reads `rconf.sortByClass`, but `XPerl_ToggleRaidSort` *writes* `conf.sortByClass` — so
the keybind/slash toggle for class sorting writes a key nothing acts on. Left alone as out of
scope. Relevant if class sorting ever seems not to toggle.
