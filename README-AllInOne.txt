X-Perl UnitFrames - All-in-One (WotLK 3.3.5a)
=============================================

WHAT THIS IS
------------
The normal X-Perl download is ~17 separate AddOn folders (XPerl, XPerl_Player,
XPerl_Target, XPerl_Party, XPerl_RaidFrames, ...). This build merges every one
of them into this SINGLE "XPerl" folder, so there is only one thing to install.

INSTALL
-------
1. Copy the whole "XPerl" folder into:
       World of Warcraft\Interface\AddOns\
   You should end up with:
       World of Warcraft\Interface\AddOns\XPerl\XPerl.toc
2. Make sure any OLD X-Perl folders (XPerl_Player, XPerl_Target, etc.) are
   removed from Interface\AddOns\ so they don't conflict.
3. Start the game. On the character-select AddOns list you'll see one entry:
   "X-Perl UnitFrames (All-in-One)".

TURNING MODULES ON / OFF
------------------------
Everything is still toggled from the X-Perl options panel exactly like before:

   /xperl   ->   Frames tab   ->   the module check-boxes
   (Player, Player Buffs, Player Pet, Target, Target's Target, Party,
    Party Pet, Cast Bars, Raid Frames, Raid Pets, Raid Helper,
    Raid Monitor, Raid Admin)

Tick/untick a module, then click the "Reload UI" button that lights up (or type
/reload). The change is applied on reload - the same one-reload workflow the
original multi-folder version used.

Your choices are saved per character (SavedVariable: XPerlModuleState).

HOW IT WORKS (for the curious)
------------------------------
Because WoW only loads AddOns from top-level folders, a real "one folder"
version can't use EnableAddOn/DisableAddOn (there's only one addon now). So
XPerl_Modules.lua re-creates that system internally:
  * EnableAddOn/DisableAddOn now record each module's desired state.
  * IsAddOnLoaded/GetAddOnInfo report that state, so the existing options panel
    and its "Reload UI" button behave unchanged.
  * On load, any module you turned off is made inert: its frames are hidden and
    its events/updates are stopped.

NOTES / LIMITATIONS
-------------------
* "Cast Bars" (ArcaneBar) and "Player Buffs" decorate other frames instead of
  owning their own, so when turned off they are suppressed on a best-effort
  basis (applied on reload).
* Disabling a core unit module (e.g. Player or Target) hides X-Perl's frame.
  Whether Blizzard's default frame returns depends on load timing; if you want
  the stock Blizzard frames back, the cleanest option is to disable the whole
  X-Perl addon. In practice these core frames are meant to stay enabled.
* This does not change any of X-Perl's own features or settings - only how the
  modules are packaged and toggled.

Original addon by Zek. GNU GPL v3. This is a repackaging only.
