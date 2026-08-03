# fperl

A fork of **X-Perl UnitFrames** (by Zek) for **WoW 3.3.5a**, patched for a 5-man-scaled server
with cross-faction groups.

Base addon © Zek, GPL v3 — see `LICENSE.txt`. This fork keeps that license.

## Installing

> **The folder must be named `XPerl`, not `fperl`.** Textures are loaded from a path with that
> name in it, so renaming the folder gives you a broken addon.

```
git clone https://github.com/JerrodTanner/fperl.git "Interface/AddOns/XPerl"
```

Then `/reload`. Your existing XPerl settings carry over.

---

## 1. Party and raid frames go 50% bigger

The **Party Scale**, **Party Pet Scale** and **Raid Scale** sliders now reach **225%** instead of
150%.

They're still tied to **Maximum Frame Scale** (Miscellaneous options) and just get half again on
top of it — so raising that to 300% takes party and raid frames to 450%. Other frames are
unaffected.

Raid frame *width* is fixed by the addon's layout, so scale is the only way to make them bigger.

Two side effects worth knowing:

- Slider limits now update when you open the options window. They previously ignored a changed
  Maximum Frame Scale until you nudged that slider.
- Because of that, if you've set Maximum Frame Scale *below* 150% and have a frame scaled above
  it, opening the options window will pull that frame's saved scale down to your limit.

## 2. Range fading works on cross-faction group members

Horde and Alliance can group on this server, but your client still treats them as enemies. XPerl's
range fading checked "can I help this person?" first, so for them it silently did nothing —
frames never faded, and the out-of-range icon was stuck on permanently no matter how close they
stood.

Range for those group members now comes from group membership instead, which ignores faction.
Everyone else is unchanged.

**Test it:** group cross-faction, stand next to them, and run

```
/run print(UnitInRange("party1"), UnitCanAssist("player","party1"))
```

- **First value true** — working. Walk out past 40 yards and the frame should fade.
- **First value false or nil** — this approach doesn't work on your server, and cross-faction
  frames will now be stuck *faded* instead of stuck un-faded. Tell me and I'll change it back to
  leaving them alone.
- **Second value already true** — the server handles this itself, nothing was broken for you, and
  these changes do nothing.

Limits: for cross-faction members the check is a flat 40 yards, so it ignores your configured
spell range and the 30-yard range icon distance. Same-faction members keep exact spell range.
Cross-faction pets aren't covered.

## 3. "One-Group Raid Show" works in any raid

**Party tab → One-Group Raid Show.** Previously it only did anything in an arena-sized raid —
five or fewer people, all in group 1.

Now party frames stay up in a raid of any size, and the raid frame for **your own group** is
hidden while every other group shows as normal. In a 25-man you get party frames for your group
plus raid frames for the other six.

- It follows you if you're moved between groups.
- If the party frames aren't showing anyone, nothing gets hidden — better a duplicate frame than
  a missing group.
- **Sort By Class is excluded.** In that mode raid frames are class columns, so there's no single
  group frame to hide. Raid frames behave as they always did, which means your group shows twice.
- Raid pet frames hide only when your group is the only one in the raid.
- Toggling the setting now updates the raid frames straight away instead of waiting for someone
  to join or leave.

## 4. Raid markers on party frames

Party frames never showed the skull/X/square on the member — only on that member's target. Now
they show it, which matters once change 3 has party frames covering your group.

You can also **set** markers now: right-click a party frame → *Set Raid Target*. Right-clicking in
a raid also gives you the raid options (promote, assist) instead of the party ones. Normal rules
apply — you need to be leader or assist.

The marker sits in the top-right corner of the name. If it overlaps something at your frame
width, it's a one-line change to move it.

## 5. Healers see every dispel type highlighted

The coloured frame/border highlight for dispellable debuffs was limited to the types your class
can normally remove — a priest saw Magic and Disease but went blind to Curse and Poison. Since
healers here can dispel everything, that hid debuffs you can actually cure.

Healers now get all four types highlighted, with their own class's types still coloured first.
**Non-healers are unchanged.**

"Healer" means healing *spec*, not class — Discipline or Holy priest, Holy paladin, Restoration
druid, Restoration shaman. A shadow priest or ret paladin keeps the normal rules. It updates on
respec and dual-spec swap without a reload.

Turning off **Only Curable** still highlights every type for anyone, as before.

Note this highlight only ever responds to debuffs that have a dispel type. Untyped boss mechanics
don't trigger it, and never did — on party or raid frames.

---

## Not tested in game yet

Everything above is written and reviewed but unplayed, so treat the first session as the real
test. Specifically:

1. Whether the cross-faction range check actually works on this server — use the test above.
2. Whether party frames show your own group in a raid, or someone else's. Change 3 fails safe
   either way, but first time you're in a multi-group raid outside group 1, check that the party
   frames and the hidden raid group are the same five people.
3. Whether the new raid marker overlaps the combat icon at your frame width.
4. That healers here really do dispel all four types — that's taken on report.
