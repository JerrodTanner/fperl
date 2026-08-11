-- X-Perl UnitFrames
-- Author: Zek <Boodhoof-EU>
-- License: GNU GPL v3, 29 June 2007 (see LICENSE.txt)

local XPerl_Raid_Events = {}
local RaidGroupCounts = {0,0,0,0,0,0,0,0,0,0}
local SubgroupCounts = {0,0,0,0,0,0,0,0}	-- Always by subgroup, unlike RaidGroupCounts which is by class when sorting by class
local myGroup = 0
local FrameArray = {}		-- List of raid frames indexed by raid ID
local RaidPositions = {}	-- Back-matching of unit names to raid ID
local ResArray = {}		-- List of currently active resserections in progress
local buffUpdates = {}		-- Queue for buff updates after a roster change
local raidLoaded
local rosterUpdated
local percD = "%d"..PERCENT_SYMBOL
local lastNamesList, lastName, lastWith, lastNamesCount		-- Stores with/without buff list (OnUpdate optimization)
local fullyInitiallized

local new, del, copy = XPerl_GetReusableTable, XPerl_FreeTable, XPerl_CopyTable

local format = format
local strsub = strsub
local GetNumRaidMembers = GetNumRaidMembers
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGhost = UnitIsGhost
local UnitMana = UnitMana
local UnitManaMax = UnitManaMax
local UnitName = UnitName
local UnitPowerType = UnitPowerType
local XPerl_UnitBuff = XPerl_UnitBuff
local XPerl_UnitDebuff = XPerl_UnitDebuff
local XPerl_CheckDebuffs = XPerl_CheckDebuffs
local XPerl_ColourFriendlyUnit = XPerl_ColourFriendlyUnit
local XPerl_ColourHealthBar = XPerl_ColourHealthBar

-- TODO - Watch for:   ERR_FRIEND_OFFLINE_S = "%s has gone offline."

local conf, rconf
XPerl_RequestConfig(function(newConf) conf = newConf rconf = conf.raid end, "$Revision: 398 $")

XPERL_RAIDGRP_PREFIX	= "XPerl_Raid_Grp"

-- Hold some raid roster information (AFK, DND etc.)
-- Is also stored between sessions to maintain timers and flags
XPerl_Roster = {}

-- Uses some variables from FrameXML\RaidFrame.lua:
-- MAX_RAID_MEMBERS = 40
-- NUM_RAID_GROUPS = 8
-- MEMBERS_PER_RAID_GROUP = 5

local localGroups = LOCALIZED_CLASS_NAMES_MALE
local WoWclassCount = 0
for k,v in pairs(localGroups) do WoWclassCount = WoWclassCount + 1 end

local resSpells  = {
	[GetSpellInfo(2006)] = true,			-- Resurrection
	[GetSpellInfo(2008)] = true,			-- Ancestral Spirit
	[GetSpellInfo(20484)] = true,			-- Rebirth
	[GetSpellInfo(7328)] = true,			-- Redemption
	[GetSpellInfo(50769)] = true,			-- Revive
}

local hotSpells = XPERL_HIGHLIGHT_SPELLS.hotSpells

----------------------
-- Loading Function --
----------------------

local raidHeaders = {}

-- XPerl_Raid_OnLoad
function XPerl_Raid_OnLoad(self)
	-- Added UNIT_POWER/UNIT_MAXPOWER to events list for 4.0 (By PlayerLin)
	local events = {"CHAT_MSG_ADDON",	-- "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_PARTY",
			"PLAYER_ENTERING_WORLD", "VARIABLES_LOADED", "RAID_ROSTER_UPDATE", "UNIT_FACTION",
			"UNIT_DYNAMIC_FLAGS", "UNIT_FLAGS", "UNIT_AURA", "UNIT_POWER", "UNIT_MAXPOWER",
			"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "PLAYER_FLAGS_CHANGED",
			"UNIT_COMBAT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
			"UNIT_SPELLCAST_INTERRUPTED", "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
			"RAID_TARGET_UPDATE", "PLAYER_LOGIN",
			-- Needed now the raid frames can be fed by the party: without it, joining or
			-- leaving a party never re-ran the roster or the show/hide check.
			"PARTY_MEMBERS_CHANGED"
			}
	for i,event in pairs(events) do
		self:RegisterEvent(event)
	end

	for i = 1,WoWclassCount do			-- Fix for WoW 2.1 UNIT_NAME_UPDATE issue
		_G["XPerl_Raid_Grp"..i]:UnregisterEvent("UNIT_NAME_UPDATE")
		tinsert(raidHeaders, _G[XPERL_RAIDGRP_PREFIX..i])
	end

	self.time = 0
	self.Array = {}

	XPerl_RegisterOptionChanger(function()
		if (raidLoaded) then
			XPerl_RaidTitles()
		end

		XPerl_Raid_Set_Bits(XPerl_Raid_Frame)

		if (raidLoaded) then
			SkipHighlightUpdate = true
			XPerl_Raid_UpdateDisplayAll()
			SkipHighlightUpdate = nil
		end
	end, "Raid")

	XPerl_Raid_OnLoad = nil
end

-- XPerl_Raid_HeaderOnLoad
function XPerl_Raid_HeaderOnLoad(self)
	self:RegisterForDrag("LeftButton")
	self.text = _G[self:GetName().."TitleText"]
	self.virtual = _G[self:GetName().."Virtual"]
	XPerl_RegisterUnitText(self.text)
	--XPerl_SavePosition(self, true)
end

-- CreateManaBar
local function CreateManaBar(self)
	local sf = self.statsFrame
	sf.manaBar = CreateFrame("StatusBar", sf:GetName().."manaBar", sf, "XPerlRaidStatusBar")
	sf.manaBar:SetScale(0.7)
	sf.manaBar:SetWidth(70)
	sf.manaBar:SetPoint("TOPLEFT", sf.healthBar, "BOTTOMLEFT", 0, 0)
	sf.manaBar:SetPoint("BOTTOMRIGHT", sf.healthBar, "BOTTOMRIGHT", 0, -7)
	sf.manaBar:SetStatusBarColor(0, 0, 1)
end

-- Setup1RaidFrame
local function Setup1RaidFrame(self)
	if (rconf.mana) then
		if (not self.statsFrame.manaBar) then
			CreateManaBar(self)
		end

		if (not InCombatLockdown()) then
			self:SetHeight(43)
		end
		self.statsFrame:SetHeight(26)
		self.statsFrame.manaBar:Show()
	else
		if (not InCombatLockdown()) then
			self:SetHeight(38)
		end
		self.statsFrame:SetHeight(21)
		if (self.statsFrame.manaBar) then
			self.statsFrame.manaBar:Hide()
		end
	end

	if (rconf.percent) then
		self.statsFrame.healthBar.text:Show()
		if (self.statsFrame.manaBar) then
			self.statsFrame.manaBar.text:Show()
		end
	else
		self.statsFrame.healthBar.text:Hide()
		if (self.statsFrame.manaBar) then
			self.statsFrame.manaBar.text:Hide()
		end
	end

	if (XPerl_Voice) then
		XPerl_Voice:Register(self, true)
	end
end

-- XPerl_MainTankSet_OnClick
function XPerl_MainTankSet_OnClick(self, value)
	if (self.value[1] == "Main Tanks") then				-- Must be 'this'
		if (self.value[4]) then
			SendAddonMessage("CTRA", "R "..self.value[2], "RAID")
		else
			SendAddonMessage("CTRA", "SET "..self.value[3].." "..self.value[2], "RAID")
		end
	end
	CloseMenus()
end

-- XPerl_RaidFrameDropDown_Initialize
function XPerl_RaidFrameDropDown_Initialize(self, ct)
	if (type(ct) ~= "table") then
		ct = nil
	end

	local info
	if (XPerl_MainTanks and type(UIDROPDOWNMENU_MENU_VALUE) == "table" and UIDROPDOWNMENU_MENU_VALUE[1] == "Main Tanks") then
		info = UIDropDownMenu_CreateInfo()
		info.text = XPERL_RAID_DROPDOWN_MAINTANKS
		info.isTitle = 1
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
		for i = 1,10 do
			info = UIDropDownMenu_CreateInfo()
			info.notCheckable = 1
			if (XPerl_MainTanks[i] and XPerl_MainTanks[i][2] == UIDROPDOWNMENU_MENU_VALUE[2]) then
				info.text = format("|c00FFFF80"..XPERL_RAID_DROPDOWN_REMOVEMT.."|r", i)
				info.value = {UIDROPDOWNMENU_MENU_VALUE[1], UIDROPDOWNMENU_MENU_VALUE[2], i, 1}
			else
				info.text = format(XPERL_RAID_DROPDOWN_SETMT, i)
				info.value = {UIDROPDOWNMENU_MENU_VALUE[1], UIDROPDOWNMENU_MENU_VALUE[2], i}
			end
			info.func = XPerl_MainTankSet_OnClick
			UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL)
		end
		return
	end

	RaidFrameDropDown_Initialize(self)

	if (UIDROPDOWNMENU_MENU_LEVEL > 1) then
		return
	end

	local titleDone
	if (DropDownList1.numButtons == 0 and (IsRaidOfficer() or (ct and CT_RATab_AutoPromotions))) then
		titleDone = true
		info = UIDropDownMenu_CreateInfo()
		info.text = self.name
		if (self.server) then
			info.text = info.text.."-"..self.server
		end
		info.isTitle = 1
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info)
	end

	if (IsRaidOfficer() and XPerl_MainTanks) then
		if (not titleDone and DropDownList1.numButtons > 0) then
			-- We want our MT option above the Cancel option, so we trick the menu into thinking it's got 1 less button
			DropDownList1.numButtons = DropDownList1.numButtons - 1
		end

		info = UIDropDownMenu_CreateInfo()
		info.text = XPERL_RAID_DROPDOWN_MAINTANKS
		info.value = {"Main Tanks", self.name, self.id}			-- Must be 'this'
		info.hasArrow = 1
		info.dist = 0
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info)

		-- Re-add the cancel button after our MT option
		info = UIDropDownMenu_CreateInfo()
		info.text = XPERL_CANCEL
		info.value = "CANCEL"
		info.owner = "RAID"
		info.func = UnitPopup_OnClick
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info)
	end

	if (ct and CT_RATab_AutoPromotions) then
		info = UIDropDownMenu_CreateInfo()
		info.text = XPERL_RAID_AUTOPROMOTE
		info.checked = CT_RATab_AutoPromotions[self.name]	-- Must be 'this'
		info.value = self.id					-- Must be 'this'
		info.func = CT_RATab_AutoPromote_OnClick
		UIDropDownMenu_AddButton(info)
	end
end

-- ShowPopup
function XPerl_Raid_ShowPopup(self)
	local me = self
	if (not self.nameFrame and self:GetParent().nameFrame == self) then
		me = self:GetParent()
	end

	HideDropDownMenu(1)
	FriendsDropDown.initialize = XPerl_RaidFrameDropDown_Initialize
	FriendsDropDown.displayMode = "MENU"

	FriendsDropDown.unit = SecureButton_GetUnit(me)
	FriendsDropDown.name, FriendsDropDown.server = UnitName(FriendsDropDown.unit)
	FriendsDropDown.id = tonumber(strmatch(FriendsDropDown.unit, "(%d+)"))

	XPerl_ShouldHideSetFocus = true
	ToggleDropDownMenu(1, nil, FriendsDropDown, me.statsFrame:GetName(), 0, 0)
	XPerl_ShouldHideSetFocus = nil
end

-- SetFrameArray
local function SetFrameArray(self, value)
	for k,v in pairs(FrameArray) do
		if (v == self) then
			FrameArray[k] = nil
			break
		end
	end

	self.partyid = value

	if (value) then
		FrameArray[value] = self
	end
end

-- XPerl_Raid_UpdateName
local function XPerl_Raid_UpdateName(self)
	local partyid = self:GetAttribute("unit")
	if (not partyid) then
		partyid = SecureButton_GetUnit(self)
		if (not partyid) then
			self.lastName, self.lastID = nil, nil
			return
		end
	end



	local name = UnitName(partyid)
	self.lastName, self.lastID = name, partyid -- These stored, so we can at least make a small effort in reducing workload on attribute changes.

	if (name) then
		self.nameFrame.text:SetText(name)

		if (self.pet) then
			local color = conf.ColourReactionNone
			self.nameFrame.text:SetTextColor(color.r, color.g, color.b)
		else
			XPerl_ColourFriendlyUnit(self.nameFrame.text, partyid)
		end
	end
end

-- XPerl_Raid_CheckFlags
local function XPerl_Raid_CheckFlags(partyid)

	local unitName = UnitName(partyid)
	local resser

	for i,name in pairs(ResArray) do
		if (name == unitName) then
			resser = i
			break
		end
	end

	if (resser) then
		-- Verify they're dead..
		if (UnitIsDeadOrGhost(partyid)) then
			return {flag = resser..XPERL_RAID_RESSING, bgcolor = {r = 0, g = 0.5, b = 1}}
		end

		ResArray[resser] = nil
	end

	local unitInfo = XPerl_Roster[unitName]
	if (unitInfo) then
		if (unitInfo.ressed) then
			if (UnitIsDead(partyid)) then
				if (unitInfo.ressed == 2) then
					return {flag = XPERL_LOC_SS_AVAILABLE, bgcolor = {r = 0, g = 1, b = 0.5}}
				elseif (unitInfo.ressed == 3) then
					return {flag = XPERL_LOC_ACCEPTEDRES, bgcolor = {r = 0, g = 0.5, b = 1}}
				else
					return {flag = XPERL_LOC_RESURRECTED, bgcolor = {r = 0, g = 0.5, b = 1}}
				end
			else
				unitInfo.ressed = nil
				XPerl_Raid_UpdateManaType(FrameArray[partyid], true)
			end

		elseif (unitInfo.afk) then
			if (UnitIsAFK(partyid)) then
				if (conf.showAFK) then
					return {flag = XPERL_RAID_AFK}
				end
			else
				unitInfo.afk = nil
			end
		end
	end
end

-- XPerl_Raid_UpdateManaType
function XPerl_Raid_UpdateManaType(self, skipFlags)
	if (rconf.mana) then
		local partyid = self:GetAttribute("unit")
		if (not partyid) then
			partyid = SecureButton_GetUnit(self)
			if (not partyid) then
				return
			end
			return
		end

		local flags
		if (not skipFlags) then
			flags = XPerl_Raid_CheckFlags(partyid)
		end
		if (not flags) then
			XPerl_SetManaBarType(self)
		end
	end
end

-- XPerl_Raid_ShowFlags
local function XPerl_Raid_ShowFlags(self, flags)
	local r, g, b
	local flag
	if (type(flags) == "string") then
		flag = flags
		flags = nil
	else
		flag = flags.flag
	end

	if (flags and flags.bgcolor) then
		r, g, b = flags.bgcolor.r, flags.bgcolor.g, flags.bgcolor.b
	else
		r, g, b = 0.5, 0.5, 0.5
	end

	self.statsFrame:SetGrey(r, g, b)

	if (flags and flags.color) then
		r, g, b = flags.color.r, flags.color.g, flags.color.b
	else
		r, g, b = 1, 1, 1
	end

	self.statsFrame.healthBar.text:SetText(flag)
	self.statsFrame.healthBar.text:SetTextColor(r, g, b)
	self.statsFrame.healthBar.text:Show()
	del(flags)
end

local spiritOfRedemption = GetSpellInfo(27827)

-- XPerl_Raid_UpdateHealth
function XPerl_Raid_UpdateHealth(self)


	local partyid = self.partyid
	if (not partyid) then
		return
	end

	local health = XPerl_UnitHealth(partyid)
	local healthmax = UnitHealthMax(partyid)

	if (health > healthmax) then
		-- New glitch with 1.12.1
		if (UnitIsDeadOrGhost(partyid)) then
			health = 0
		else
			health = healthmax
		end
	end

	self.statsFrame.healthBar:SetMinMaxValues(0, healthmax)
	if (conf.bar.inverse) then
		self.statsFrame.healthBar:SetValue(healthmax - health)
	else
		self.statsFrame.healthBar:SetValue(health)
	end

	if (not rconf.percent) then
		if (self.statsFrame.healthBar.text:IsShown()) then
			self.statsFrame.healthBar.text:Hide()
		end
	end

	XPerl_SetExpectedHealth(self)

	local name = UnitName(partyid)
	local myRoster = XPerl_Roster[name]
	if (name and UnitIsConnected(partyid)) then
		self.disco = nil
		if (myRoster and myRoster.fd) then
			if (not UnitIsFeignDeath(partyid)) then
				myRoster.fd = nil
			end
		end

		local flags = XPerl_Raid_CheckFlags(partyid)
		if (flags) then
			XPerl_Raid_ShowFlags(self, flags)

			if (UnitIsDeadOrGhost(partyid)) then
				self.dead = true
				XPerl_Raid_UpdateName(self)
			end
			return

		elseif (UnitBuff(partyid, spiritOfRedemption)) then
			self.dead = true
			XPerl_Raid_ShowFlags(self, XPERL_LOC_DEAD)
			XPerl_Raid_UpdateName(self)

		elseif (UnitIsDead(partyid) or (myRoster and myRoster.fd and conf.showFD)) then
			if (myRoster and myRoster.fd) then
				XPerl_NoFadeBars(true)
				self.statsFrame.healthBar.text:SetText(XPERL_LOC_FEIGNDEATH)
				self.statsFrame:SetGrey()
				XPerl_NoFadeBars()
			else
				self.dead = true
				XPerl_Raid_ShowFlags(self, XPERL_LOC_DEAD)
				XPerl_Raid_UpdateName(self)
			end

		elseif (UnitIsGhost(partyid)) then
			self.dead = true
			XPerl_Raid_ShowFlags(self, XPERL_LOC_GHOST)
			XPerl_Raid_UpdateName(self)

		else
			if (self.dead or (myRoster and ((myRoster.fd and conf.showFD) or myRoster.ressed))) then
				XPerl_Raid_UpdateManaType(self, true)
			end
			self.dead = nil

			local percentHp = health / healthmax
			if (rconf.healerMode.enable) then
				self.statsFrame.healthBar.text:SetText(-(healthmax - health))
			else
				if (rconf.values) then
					self.statsFrame.healthBar.text:SetFormattedText("%d/%d", health, healthmax)
				else
					self.statsFrame.healthBar.text:SetFormattedText(percD, (percentHp + 0.005) * 100)
				end
			end

			-- XPerl_SetSmoothBarColor(self.statsFrame.healthBar, percentHp)
			XPerl_ColourHealthBar(self, percentHp, partyid)

			if (self.statsFrame.greyMana) then
				self.statsFrame.greyMana = nil
				if (myRoster) then
					myRoster.resCount = nil
					myRoster.ressed = nil
				end
				XPerl_Raid_UpdateManaType(self, true)
			end
		end
	else
		self.disco = true
		self.dead = nil
		XPerl_Raid_ShowFlags(self, XPERL_LOC_OFFLINE)

		if (name and myRoster and not myRoster.offline) then
			myRoster.offline = GetTime()
			myRoster.afk = nil
			myRoster.dnd = nil
		end
	end
end

-- XPerl_Raid_UpdateMana
local function XPerl_Raid_UpdateMana(self)
	if (rconf.mana) then
		if (not self.statsFrame.manaBar) then
			CreateManaBar(self)
		end

		local partyid = self.partyid
		if (not partyid) then
			return
		end

		local mana = UnitMana(partyid)
		local manamax = UnitManaMax(partyid)

		if (rconf.manaPercent and UnitPowerType(partyid) == 0 and not self.pet) then
			if (rconf.values) then			-- TODO rconf.manavalues
			 	self.statsFrame.manaBar.text:SetFormattedText("%d/%d", mana, manamax)
		 	else
		 		local pmanaPct = (mana * 100.0) / manamax
				self.statsFrame.manaBar.text:SetFormattedText(percD, pmanaPct)	-- XPerl_Percent[floor(pmanaPct)])
			end
		else
			self.statsFrame.manaBar.text:SetText("")
		end

		self.statsFrame.manaBar:SetMinMaxValues(0, manamax)
		self.statsFrame.manaBar:SetValue(mana)
	end
end

-- onAttrChanged
local function onAttrChanged(self, name, value)
	if (name == "unit") then
		if (value) then
			SetFrameArray(self, value)
			if (self.lastID ~= value or self.lastName ~= UnitName(value)) then
				XPerl_Raid_UpdateDisplay(self)
			end
		else
			buffUpdates[self] = nil
			SetFrameArray(self)
			self.lastID = nil
			self.lastName = nil
		end
	end
end

-- XPerl_Raid_Single_OnLoad
function XPerl_Raid_Single_OnLoad(self)
	XPerl_SetChildMembers(self)
	self:RegisterForClicks("AnyUp")

	self.edgeFile = "Interface\\Addons\\XPerl\\images\\XPerl_ThinEdge"
	self.edgeSize = 10
	self.edgeInsets = 2

	XPerl_RegisterHighlight(self.highlight, 2)

	XPerl_RegisterPerlFrames(self, {self.nameFrame, self.statsFrame})
	self.FlashFrames = {self.nameFrame, self.statsFrame}

	--self:SetScript("OnAttributeChanged", onAttrChanged)
	--XPerl_RegisterClickCastFrame(self)
	--XPerl_RegisterClickCastFrame(self.nameFrame)
end

-- XPerl_Raid_CombatFlash
local function XPerl_Raid_CombatFlash(self, elapsed, argNew, argGreen)
	if (XPerl_CombatFlashSet(self, elapsed, argNew, argGreen)) then
		XPerl_CombatFlashSetFrames(self)
	end
end

-- XPerl_GetRaidPosition
function XPerl_GetRaidPosition(findName)
	return RaidPositions[findName]
end

-- XPerl_Raid_GetUnitFrameByName
function XPerl_Raid_GetUnitFrameByName(findName)
	-- Used by teamspeak module
	local id = RaidPositions[findName]
	if (id) then
		return FrameArray[id]
	end
end

-- XPerl_Raid_GetUnitFrameByName
function XPerl_Raid_GetUnitFrameByUnit(unit)
	return FrameArray[unit]
end

-- XPerl_Raid_GetFrameArray
function XPerl_Raid_GetFrameArray()
	return FrameArray
end

-- UpdateUnitByName
local function UpdateUnitByName(name,flagsOnly)
	local id = RaidPositions[name]
	if (id) then
		local frame = FrameArray[id]
		if (frame and frame:IsShown()) then
			if (flagsOnly) then
				XPerl_Raid_UpdateHealth(frame)
			else
				XPerl_Raid_UpdateDisplay(frame)
			end
		end
	end
end

-- XPerl_Raid_HighlightCallback(updateName)
local function XPerl_Raid_HighlightCallback(self, updateGUID)
	local f = XPerl_Raid_GetUnitFrameByGUID(updateGUID)
	if (f) then
		XPerl_Highlight:SetHighlight(f, updateGUID)
	end
end

----------------------------------------------------------------------
-- Aura icons
--
-- Buffs and debuffs used to share one icon row, so the options could only ever turn on one
-- of them - the old GetShowCast() returned "b" or "d" and buffs always won. A healer needs
-- both at once, so each type now gets its own container, its own enable, anchor, icon size
-- and icons-per-row, and wraps onto further rows once that limit is reached.
--
-- The old buffs.right and buffs.inside options are retired by this. "inside" narrowed the
-- stats frame to fit icons within the frame width, which cannot work once two independent
-- rows can be anchored anywhere; anchor = "LEFT"/"RIGHT" replaces the outside part of it.
----------------------------------------------------------------------

-- GetAuraContainer(self, auraType)
-- buffFrame comes from the XML. debuffFrame is created on demand so an existing layout
-- doesn't pay for it, and so this needs no XML change. Both parent the raid frame itself,
-- which XPerl_Raid_SetBuffTooltip relies on to walk back up to the unit.
local function GetAuraContainer(self, auraType)
	if (auraType == "b") then
		return self.buffFrame
	end

	if (not self.debuffFrame) then
		local f = CreateFrame("Frame", nil, self)
		f:SetFrameStrata("MEDIUM")
		f:SetWidth(10)
		f:SetHeight(10)
		f:Hide()
		self.debuffFrame = f
	end

	return self.debuffFrame
end

-- GetAuraButton(container, index, createIfAbsent, auraType)
local buffIconCount = 0
local function GetAuraButton(container, index, createIfAbsent, auraType)

	local button = container.buff and container.buff[index]

	if (not button and createIfAbsent) then
		buffIconCount = buffIconCount + 1
		-- Cooldown variant of the template, so raid icons get the same timer sweep and
		-- countdown text the party and player frames have always had.
		button = CreateFrame("Button", "XPerlRBuff"..buffIconCount, container, "XPerl_Cooldown_BuffTemplate")
		button:SetID(index)

		if (not container.buff) then
			container.buff = {}
		end
		container.buff[index] = button

		button:SetHeight(10)
		button:SetWidth(10)

		button.icon:SetTexCoord(0.078125, 0.921875, 0.078125, 0.921875)

		button:SetScript("OnEnter", XPerl_Raid_SetBuffTooltip)
		button:SetScript("OnLeave", function()
						lastNamesList, lastName, lastWith = nil, nil, nil
						XPerl_PlayerTipHide()
					end)
	end

	if (button) then
		-- The tooltip needs to know which kind of aura this icon is showing, now that a
		-- frame can have both kinds on screen at the same time.
		button.auraType = auraType
	end

	return button
end

-- auraAnchors
-- Where the container sits against the stats frame, and which way the icons grow from it.
-- dx/dy move along a row, and rows stack away from the frame, so a second row never lands
-- on top of the health bar. wrapAcross means rows run vertically (LEFT/RIGHT anchors).
-- relTo names the sub-frame to hang off, defaulting to the stats frame. TOP has to use the name
-- row instead: the stats frame's top edge is under the name, so anchoring there put the icons on
-- top of the name text. The name row is the top of the whole frame, so icons clear it.
local auraAnchors = {
	BOTTOM	= {point = "TOPLEFT",		relPoint = "BOTTOMLEFT",	x = 0,	y = -1,	dx = 1,	dy = -1,	wrapAcross = false},
	TOP	= {point = "BOTTOMLEFT",	relPoint = "TOPLEFT",		x = 0,	y = 1,	dx = 1,	dy = 1,		wrapAcross = false,	relTo = "nameFrame"},
	RIGHT	= {point = "TOPLEFT",		relPoint = "TOPRIGHT",		x = 1,	y = 0,	dx = 1,	dy = -1,	wrapAcross = true},
	LEFT	= {point = "TOPRIGHT",		relPoint = "TOPLEFT",		x = -1,	y = 0,	dx = -1, dy = -1,	wrapAcross = true},
}

-- LayoutAuras(self, container, count, aconf)
local function LayoutAuras(self, container, count, aconf)
	local a = auraAnchors[aconf.anchor] or auraAnchors.BOTTOM
	local size = aconf.size or 10

	-- How many fit before wrapping. Derived from the frame rather than configured, so
	-- raising the icon size just means fewer per row instead of icons hanging off the
	-- side. perRow is still honoured if something sets it explicitly.
	local perRow = aconf.perRow
	if (not perRow) then
		local across = a.wrapAcross and self.statsFrame:GetHeight() or self.statsFrame:GetWidth()
		perRow = floor((across or 80) / size)
	end
	if (perRow < 1) then
		perRow = 1
	end

	container:ClearAllPoints()
	container:SetPoint(a.point, (a.relTo and self[a.relTo]) or self.statsFrame, a.relPoint, a.x, a.y)

	for i = 1, count do
		local button = container.buff[i]
		local row = floor((i - 1) / perRow)
		local col = (i - 1) % perRow

		button:SetWidth(size)
		button:SetHeight(size)
		button:ClearAllPoints()

		-- The template's countdown font is sized for a 32px icon, so scale it to whatever
		-- icon size is in use or the number spills off a small raid icon.
		local cd = button.cooldown
		if (cd and cd.countdown) then
			cd.countdown:SetFont(STANDARD_TEXT_FONT, max(8, floor(size * 0.55)), "OUTLINE")
		end

		local x, y
		if (a.wrapAcross) then
			x, y = row * size * a.dx, col * size * a.dy
		else
			x, y = col * size * a.dx, row * size * a.dy
		end

		button:SetPoint(a.point, container, a.point, x, y)
	end
end

-- HideAuras(self, auraType)
-- Only touches a container that already exists, so turning debuffs off never creates one.
local function HideAuras(self, auraType)
	local container = (auraType == "b") and self.buffFrame or self.debuffFrame
	if (container and container:IsShown()) then
		container:Hide()
	end
end

----------------------------------------------------------------------
-- Buff ordering
--
-- Buffs are not shown in the game's slot order. That order is really aura slot reuse: when
-- one drops, the next applied takes the hole, so icons shuffle for no visible reason. Worse,
-- with a cap of 8 icons the slot order decides what you see, and on a fully raid buffed unit
-- your own HoTs can sit past the cap and never be drawn at all.
--
-- Order is HoTs first, then whatever expires soonest. HoTs keep the fixed order in the list
-- below however much time is left on them, so the row stays put as ticks land.
--
-- Spell IDs rather than names, so this works on any client language.
----------------------------------------------------------------------

-- The order here IS the display order for HoTs. Rearrange to taste.
local hotSpellIDs = {
	774,		-- Rejuvenation
	8936,		-- Regrowth
	48438,		-- Wild Growth
	33763,		-- Lifebloom
	139,		-- Renew
	61295,		-- Riptide
}

-- The long duration group buffs, single and group version of each. Hidden as one set by the
-- Hide Group Buffs option, to stop them crowding out short term buffs you actually watch.
local groupBuffSpellIDs = {
	1126, 21849,		-- Mark of the Wild / Gift of the Wild
	1243, 21562,		-- Power Word: Fortitude / Prayer of Fortitude
	14752, 27681,		-- Divine Spirit / Prayer of Spirit
	976, 27683,		-- Shadow Protection / Prayer of Shadow Protection
	1459, 23028,		-- Arcane Intellect / Arcane Brilliance
	20217, 25898,		-- Blessing of Kings / Greater Blessing of Kings
	19740, 25782,		-- Blessing of Might / Greater Blessing of Might
	19742, 25894,		-- Blessing of Wisdom / Greater Blessing of Wisdom
	20911, 25899,		-- Blessing of Sanctuary / Greater Blessing of Sanctuary
	19977, 25890,		-- Blessing of Light / Greater Blessing of Light
}

-- Bloodlust and Heroism's cooldown debuff, both faction versions. Nothing can be done about it,
-- it sits there for ten minutes, and with a cap of 8 icons it can push a debuff you do need to
-- see off the row - so the Hide Sated option leaves it out. Both are listed because a
-- cross-faction group gets whichever version the shaman who cast it had.
local satedSpellIDs = {
	57724,		-- Sated (Bloodlust)
	57723,		-- Exhaustion (Heroism)
}

local hotOrder, groupBuffNames, satedNames
local emptyNames = {}
local function AuraNameLists()
	if (not hotOrder) then
		local hots, group, sated = {}, {}, {}
		local resolved = 0

		for i = 1, #hotSpellIDs do
			local name = GetSpellInfo(hotSpellIDs[i])
			if (name) then
				hots[name] = i
				resolved = resolved + 1
			end
		end
		for i = 1, #groupBuffSpellIDs do
			local name = GetSpellInfo(groupBuffSpellIDs[i])
			if (name) then
				group[name] = true
				resolved = resolved + 1
			end
		end
		for i = 1, #satedSpellIDs do
			local name = GetSpellInfo(satedSpellIDs[i])
			if (name) then
				sated[name] = true
				resolved = resolved + 1
			end
		end

		-- Don't keep the result until at least one name came back. Nothing resolving means the
		-- spell data isn't readable yet, and caching that would silently kill buff ordering and
		-- group buff hiding for the rest of the session.
		if (resolved == 0) then
			return emptyNames, emptyNames, emptyNames
		end

		hotOrder, groupBuffNames, satedNames = hots, group, sated
	end
	return hotOrder, groupBuffNames, satedNames
end

-- AuraFiltered(name, duration, aconf, auraType)
-- Whether the row's own name and duration filters leave this aura out. Shared with test mode, so a
-- sample vanishing from the preview means the option really is working rather than the preview
-- pretending it does. Castable Only and Curable Only are not here: those are handed to the client
-- as a filter string and can only be judged against a real unit.
local function AuraFiltered(name, duration, aconf, auraType)
	local _, group, sated = AuraNameLists()

	if (auraType == "d") then
		return (aconf.hideSated and sated[name]) and true or false
	end

	if (aconf.hideGroupBuffs and group[name]) then
		return true
	end

	-- Aura buffs are the permanent proximity ones - paladin auras, totem buffs, Blood Pact,
	-- Trueshot Aura. Nothing about them changes while you stand next to the caster, so they are
	-- pure noise on a raid frame. Keyed off having no duration rather than a spell list, which
	-- needs no maintenance and covers the server's own auras too.
	if (aconf.hideAuraBuffs and not (duration and duration > 0)) then
		return true
	end

	return false
end

-- Scan past the icon cap so the sort picks from everything present rather than the cap
-- deciding first. Kept modest because with Castable Only on, each lookup also walks the
-- unfiltered list to recover the real aura index.
local AURA_SCAN_MAX = 24
local NO_EXPIRY = 1e9

-- Reused between calls, entries included, so a busy raid isn't allocating 25 tables a tick
local auraPool, auraList = {}, {}

local function AuraSortCompare(x, y)
	local xh, yh = x.hot or 1000, y.hot or 1000
	if (xh ~= yh) then
		return xh < yh			-- HoTs first, in their fixed order
	end
	if (xh < 1000) then
		return x.index < y.index	-- same HoT on twice, keep it stable
	end
	if (x.left ~= y.left) then
		return x.left < y.left		-- then soonest to expire
	end
	return x.index < y.index		-- and a tiebreak, so the sort is never ambiguous
end

-- CollectSortedBuffs(partyid, aconf, filter)
-- Fills auraList with what should be shown, in display order. Returns how many.
local function CollectSortedBuffs(partyid, aconf, filter)
	local hots = AuraNameLists()
	local now = GetTime()

	for i = #auraList, 1, -1 do
		auraList[i] = nil
	end

	local n = 0
	for index = 1, AURA_SCAN_MAX do
		local name, _, tex, _, _, duration, endTime, caster = XPerl_UnitBuff(partyid, index, filter, true)
		if (not name) then
			break
		end

		if (tex and not AuraFiltered(name, duration, aconf, "b")) then
			n = n + 1
			local e = auraPool[n]
			if (not e) then
				e = {}
				auraPool[n] = e
			end
			auraList[n] = e

			e.index = index
			e.tex = tex
			e.duration = duration
			e.endTime = endTime
			e.caster = caster
			e.hot = hots[name]
			e.left = (duration and duration > 0 and endTime) and (endTime - now) or NO_EXPIRY
		end
	end

	if (n > 1) then
		table.sort(auraList, AuraSortCompare)
	end

	return n
end

-- CollectDebuffs(partyid, aconf, filter)
-- Fills auraList with the debuffs to show, in the game's own order. Debuffs are not sorted -
-- unlike buffs their order isn't shuffled by slot reuse, and a debuff row that rearranged itself
-- would be harder to read. This exists so a hidden debuff closes the row up behind it instead of
-- leaving a hole, which a straight index-to-icon loop cannot do. Returns how many.
local function CollectDebuffs(partyid, aconf, filter)
	for i = #auraList, 1, -1 do
		auraList[i] = nil
	end

	local n = 0
	for index = 1, AURA_SCAN_MAX do
		local name, _, tex, _, _, duration, endTime, caster = XPerl_UnitDebuff(partyid, index, filter, true)
		if (not name) then
			break
		end

		if (tex and not AuraFiltered(name, duration, aconf, "d")) then
			n = n + 1
			local e = auraPool[n]
			if (not e) then
				e = {}
				auraPool[n] = e
			end
			auraList[n] = e

			e.index = index
			e.tex = tex
			e.duration = duration
			e.endTime = endTime
			e.caster = caster
		end
	end

	return n
end

-- UpdateAuraType(self, auraType, aconf, filter)
-- Returns how many icons ended up shown.
local function UpdateAuraType(self, auraType, aconf, filter)
	local partyid = self.partyid
	local container = GetAuraContainer(self, auraType)
	local maxIcons = aconf.max or 8
	local count = 0

	-- Both types are collected first: buffs sorted, debuffs in the game's order with anything
	-- filtered out closed up. Either way an icon's position no longer matches its aura index, so
	-- the real index travels with the entry for the tooltip to look up.
	local collected = (auraType == "b") and CollectSortedBuffs(partyid, aconf, filter) or CollectDebuffs(partyid, aconf, filter)

	for slot = 1, maxIcons do
		local index, tex, duration, endTime, caster
		local e = (slot <= collected) and auraList[slot]
		if (e) then
			index, tex, duration, endTime, caster = e.index, e.tex, e.duration, e.endTime, e.caster
		end

		local button = GetAuraButton(container, slot, tex, auraType)	-- 'tex' flags whether to create icon
		if (button) then
			if (tex) then
				count = count + 1
				button.icon:SetTexture(tex)

				-- The tooltip looks the aura up by the button's ID, so this has to carry the
				-- real aura index rather than the position the icon happens to sit in.
				button:SetID(index)

				-- Same options as every other frame. SetTimer works out sweep and text from the
				-- per audience settings, so nothing is decided here beyond having a duration.
				if (button.cooldown) then
					if (duration and duration > 0 and endTime) then
						XPerl_CooldownFrame_SetTimer(button.cooldown, endTime - duration, duration, 1, (caster == "player" or caster == "vehicle"))
					else
						button.cooldown:Hide()
					end
				end

				if (not button:IsShown()) then
					button:Show()
				end
			elseif (button:IsShown()) then
				if (button.cooldown) then
					button.cooldown:Hide()
				end
				button:Hide()
			end
		end
	end

	-- Anything left over from a previously larger maximum
	if (container.buff) then
		for index = maxIcons + 1, #container.buff do
			local button = container.buff[index]
			if (button and button:IsShown()) then
				button:Hide()
			end
		end
	end

	if (count > 0) then
		LayoutAuras(self, container, count, aconf)
		if (not container:IsShown()) then
			container:Show()
		end
	elseif (container:IsShown()) then
		container:Hide()
	end

	return count
end

-- UpdateBuffs
local function UpdateBuffs(self)
	local partyid = self.partyid
	if (not partyid) then
		return
	end

	XPerl_CheckDebuffs(self, partyid)
	XPerl_ColourFriendlyUnit(self.nameFrame.text, partyid)

	-- Icons anchor outside the stats frame now, so its width is no longer negotiable. This has
	-- to happen BEFORE the aura layout: LayoutAuras measures this frame to work out how many
	-- icons fit per row, and a config upgrading from the old "Buffs Inside" mode arrives here
	-- with a 60 or 70 wide stats frame, which would wrap one update's worth of icons early.
	self.statsFrame:SetWidth(80)

	local showBuffs = rconf.buffs.enable
	local showDebuffs = rconf.debuffs.enable

	-- untilDebuffed only existed because one row had to serve both types. With both able to
	-- show at once it has nothing left to do, so it now only applies when debuffs are off.
	-- The old debuffsForced flag went with it - the tooltip reads the icon's own auraType.
	if (showBuffs and not showDebuffs and rconf.buffs.untilDebuffed) then
		-- Asked through the same collection the debuff row would use, so a debuff that row is set
		-- to hide (Sated) doesn't swap the buff row out for an empty debuff row.
		if (CollectDebuffs(partyid, rconf.debuffs, (rconf.debuffs.curable == 1) and "RAID") > 0) then
			showBuffs, showDebuffs = nil, true
		end
	end

	if (showBuffs) then
		UpdateAuraType(self, "b", rconf.buffs, (rconf.buffs.castable == 1) and "RAID")
	else
		HideAuras(self, "b")
	end

	if (showDebuffs) then
		UpdateAuraType(self, "d", rconf.debuffs, (rconf.debuffs.curable == 1) and "RAID")
	else
		HideAuras(self, "d")
	end

	local myRoster = XPerl_Roster[UnitName(partyid)]
	if (myRoster) then
		local _,class = UnitClass(partyid)
		if (class == "HUNTER") then
			if (UnitIsFeignDeath(partyid)) then
				if (not myRoster.fd) then
					myRoster.fd = GetTime()
					XPerl_Raid_UpdateHealth(self)
				end
			elseif (myRoster.fd) then
				myRoster.fd = nil
				XPerl_Raid_UpdateHealth(self)
			end
		end
	end
end

------------------
-- Buffs stuffs --
------------------

-- XPerl_Raid_UpdateCombat
local function XPerl_Raid_UpdateCombat(self)
	local partyid = self.partyid
	if (not partyid) then
		return
	end
	if (UnitExists(partyid) and UnitAffectingCombat(partyid)) then
		self.nameFrame.combatIcon:Show()
	else
		self.nameFrame.combatIcon:Hide()
	end
	if (UnitIsVisible(partyid) and UnitIsCharmed(partyid)) then
		self.nameFrame.warningIcon:Show()
	else
		self.nameFrame.warningIcon:Hide()
	end
end

----------------------------------------------------------------------
-- Configuration test mode -- /xperl test
--
-- Two sample raid groups with sample buffs and debuffs, so the aura position, icon size and
-- wrapping can be set up without waiting to be in a raid.
--
-- Secure group headers fill themselves from the real roster and cannot be handed made-up
-- units, so this deliberately does not drive the real headers. It builds its own frames from
-- the same XPerl_Raid_FrameTemplate and runs them through the same Setup1RaidFrame and the
-- same LayoutAuras used by live frames, so icon size, wrap points, spacing, scale, anchor
-- and the mana/percent options all preview exactly as they will look for real.
--
-- The frames are not secure: no unit attribute, so they can't be clicked, targeted or
-- click-cast on, and anything needing a live unit isn't simulated (aggro, range fading,
-- incoming heals, res and AFK flags). That's the trade for previewing without a raid.
--
-- The samples are two of each *kind* of aura, and they are judged by the row's own filters through
-- the same AuraFiltered the live rows use. So the preview is also the answer to "is Hide Sated
-- actually doing anything?" - tick it and the two Sated samples go, because the option removed
-- them, not because the preview was told to fake it.
----------------------------------------------------------------------

local testMode
local TestGroups = {}

----------------------------------------------------------------------
-- Sample auras
--
-- Real spell IDs, so the name-based filters (Hide Group Buffs, Hide Sated) and the duration-based
-- one (Hide Auras) judge them exactly as they judge the real thing, and the icon is the real icon.
-- A spell ID this client doesn't know is skipped rather than drawn as a question mark.
--
--   duration/left  what the sweep and the countdown number are driven from. left is chosen to
--                  straddle a typical Countdown Start, so some numbers are showing and some
--                  aren't - which is the thing that setting is hard to judge blind.
--   mine           picks My Cooldown/My Countdown over Their Cooldown/Their Countdown, the same
--                  way a real aura's caster does. Every row has some of each.
--   castable       whether Castable Only would keep it. curable, likewise, for Curable Only.
--                  Those two are handed to the client as a filter string, so they cannot be
--                  judged against a made-up aura and are applied from this flag instead.
--
-- No duration at all means an aura buff, which is what Hide Auras keys off.
----------------------------------------------------------------------

local testBuffSamples = {
	-- HoTs of mine. Also shows the HoT-first ordering, and My Cooldown/My Countdown.
	{id = 774,	duration = 15,	left = 11,	mine = true,	castable = true},	-- Rejuvenation
	{id = 139,	duration = 18,	left = 5,	mine = true,	castable = true},	-- Renew

	-- Class buffs: what Hide Group Buffs takes out. Long, so no countdown number at 99 or less.
	{id = 1126,	duration = 3600, left = 2400,			castable = true},	-- Mark of the Wild
	{id = 1243,	duration = 3600, left = 1500,			castable = true},	-- Power Word: Fortitude

	-- Auras: no duration, no sweep, no number. What Hide Auras takes out.
	{id = 465,							castable = true},	-- Devotion Aura
	{id = 19506,							castable = true},	-- Trueshot Aura

	-- Someone else's own buffs, which you can't cast: what Castable Only takes out. Their
	-- Cooldown and Their Countdown apply to these.
	{id = 22812,	duration = 12,	left = 8},							-- Barkskin
	{id = 588,	duration = 1800, left = 900},							-- Inner Fire
}

local testDebuffSamples = {
	-- Bloodlust and Heroism's cooldown debuff: what Hide Sated takes out.
	{id = 57724,	duration = 600,	left = 420},							-- Sated
	{id = 57723,	duration = 600,	left = 240},							-- Exhaustion

	-- Dispellable, one Magic and one Curse: what Curable Only keeps. The first is mine.
	{id = 589,	duration = 18,	left = 12,	mine = true,	curable = true},	-- Shadow Word: Pain
	{id = 980,	duration = 24,	left = 7,			curable = true},	-- Curse of Agony

	-- Nothing removes these: a bleed and a raid boss debuff. What Curable Only takes out.
	{id = 12162,	duration = 12,	left = 9},							-- Deep Wounds
	{id = 72293,	duration = 120,	left = 105},							-- Mark of the Fallen Champion
}

-- TestSampleInfo(sample)
-- Name and icon for a sample, resolved once. Returns nothing for a spell this client doesn't have,
-- which is how a sample removes itself rather than previewing a missing icon.
local function TestSampleInfo(sample)
	if (not sample.resolved) then
		local name, _, tex = GetSpellInfo(sample.id)
		if (not name or not tex) then
			sample.resolved = "missing"
		else
			sample.name, sample.tex, sample.resolved = name, tex, true
		end
	end

	if (sample.resolved == true) then
		return sample.name, sample.tex
	end
end

-- Ten sample members over two groups. hp/mp are fractions so the bars show a spread rather
-- than ten full bars, which is what you actually want when judging colours and text.
local testRoster = {
	{
		{name = "Firecracker",	class = "PRIEST",	hp = 1.00, mp = 0.74},
		{name = "Slimesham",	class = "WARRIOR",	hp = 0.61, mp = 0.30},
		{name = "Azula",	class = "MAGE",		hp = 0.88, mp = 0.55},
		{name = "Bindu",	class = "DRUID",	hp = 0.34, mp = 0.91},
		{name = "Greatspoon",	class = "PALADIN",	hp = 0.72, mp = 0.48},
	},
	{
		{name = "Thornwick",	class = "ROGUE",	hp = 0.95, mp = 0.60},
		{name = "Mossgrave",	class = "SHAMAN",	hp = 0.18, mp = 0.83},
		{name = "Ashling",	class = "WARLOCK",	hp = 0.66, mp = 0.22},
		{name = "Duskrend",	class = "DEATHKNIGHT",	hp = 1.00, mp = 0.40},
		{name = "Pellworth",	class = "HUNTER",	hp = 0.47, mp = 0.68},
	},
}

-- Where the sample group sits against its title frame, and which way the frames stack.
-- Mirrors SetMainHeaderAttributes so the preview lines up with the real thing.
local testAnchors = {
	TOP	= {point = "TOP",	rel = "BOTTOM",		child = "TOP",		next = "BOTTOM",	x = 0,	y = -1},
	BOTTOM	= {point = "BOTTOM",	rel = "TOP",		child = "BOTTOM",	next = "TOP",		x = 0,	y = 1},
	LEFT	= {point = "TOPLEFT",	rel = "BOTTOMLEFT",	child = "LEFT",		next = "RIGHT",		x = 1,	y = 0},
	RIGHT	= {point = "TOPRIGHT",	rel = "BOTTOMRIGHT",	child = "RIGHT",	next = "LEFT",		x = -1,	y = 0},
}

-- TestClassColour(class)
-- Same source and brightness scaling XPerl_ColourHealthBar uses, so a customised class
-- colour previews correctly rather than showing the stock Blizzard hue.
local function TestClassColour(class)
	local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
	if (not c) then
		return 0.5, 0.5, 0.5
	end
	local b = conf.colour.classbarBright or 1
	return max(0, min(1, c.r * b)), max(0, min(1, c.g * b)), max(0, min(1, c.b * b))
end

-- PrepareTestAuras(auraType, aconf, samples, out)
-- Which samples the row's options leave, in the order the live row would show them. Worked out once
-- per refresh and handed to every sample frame, because it cannot differ between them - the filters
-- are config, not per unit. Entry tables are reused, so dragging a slider isn't making garbage.
local testBuffList, testDebuffList = {}, {}
-- A pool per row. One shared pool would hand the buff list and the debuff list the same entry
-- tables, and preparing the second row would overwrite what the first one had just worked out.
local testPools = {b = {}, d = {}}

local function PrepareTestAuras(auraType, aconf, samples, out)
	for i = #out, 1, -1 do
		out[i] = nil
	end

	if (not aconf.enable) then
		return out
	end

	local hots = AuraNameLists()
	local maxIcons = aconf.max or 8
	local pool = testPools[auraType]

	-- The one filter that can't be asked of a made-up aura, so each sample declares the answer
	local clientFilter = (auraType == "b") and (aconf.castable == 1) or (auraType == "d") and (aconf.curable == 1)

	local n = 0
	for i = 1, #samples do
		local sample = samples[i]
		local name, tex = TestSampleInfo(sample)

		if (name) then
			local hidden = AuraFiltered(name, sample.duration, aconf, auraType)

			if (not hidden and clientFilter) then
				hidden = not ((auraType == "b") and sample.castable or (auraType == "d") and sample.curable)
			end

			if (not hidden) then
				n = n + 1
				local e = pool[n]
				if (not e) then
					e = {}
					pool[n] = e
				end
				out[n] = e

				e.sample = sample
				e.tex = tex
				e.index = i
				e.hot = hots[name]
				e.left = sample.left or NO_EXPIRY
			end
		end
	end

	-- The same sort the live buff row uses, so the preview shows the order you will really get:
	-- HoTs first in their fixed order, then whatever expires soonest. Debuffs aren't sorted there
	-- and aren't sorted here.
	if (auraType == "b" and n > 1) then
		table.sort(out, AuraSortCompare)
	end

	-- Trim after sorting, so the cap drops what the row would really drop
	for i = #out, maxIcons + 1, -1 do
		out[i] = nil
	end

	return out
end

-- Sample timers. One entry per drawn icon, holding the sample it came from and when its made up
-- aura runs out, so each one can be re-armed as it expires. Samples run from five seconds to
-- twenty five minutes, so a single refresh interval can't serve them: anything longer than the
-- shortest leaves those icons sitting expired, which is the state you're trying to judge Countdown
-- Start against. Entries are pooled and testTimerCount says how many are live.
local testTimers = {}
local testTimerCount = 0

-- TestTimerAdd(button, sample, expires)
local function TestTimerAdd(button, sample, expires)
	testTimerCount = testTimerCount + 1

	local e = testTimers[testTimerCount]
	if (not e) then
		e = {}
		testTimers[testTimerCount] = e
	end

	e.button, e.sample, e.expires = button, sample, expires
end

-- TestArmTimer(button, sample, now)
-- Through the same SetTimer the live rows use, with the sample's own idea of who cast it, so the
-- sweep and the countdown preview whatever My/Their settings are in force.
local function TestArmTimer(button, sample, now)
	XPerl_CooldownFrame_SetTimer(button.cooldown, now + sample.left - sample.duration, sample.duration, 1, sample.mine)
end

-- TestAuras(frame, auraType, list, aconf)
-- Draws a prepared list and hands off to the real LayoutAuras, so the wrapping and positioning here
-- is not a reimplementation of it.
local function TestAuras(frame, auraType, list, aconf)
	local count = #list

	if (not aconf.enable or count == 0) then
		HideAuras(frame, auraType)
		return
	end

	local container = GetAuraContainer(frame, auraType)
	local now = GetTime()

	for slot = 1, count do
		local e = list[slot]
		local sample = e.sample
		local button = GetAuraButton(container, slot, e.tex, auraType)

		if (button) then
			button.icon:SetTexture(e.tex)

			if (button.cooldown) then
				if (sample.duration and sample.left) then
					TestArmTimer(button, sample, now)
					TestTimerAdd(button, sample, now + sample.left)
				else
					button.cooldown:Hide()		-- an aura buff: no duration, so nothing to run
				end
			end

			if (not button:IsShown()) then
				button:Show()
			end
		end
	end

	-- Anything left from a longer list last time, or from a real aura before test mode came on
	if (container.buff) then
		for slot = count + 1, #container.buff do
			local button = container.buff[slot]
			if (button and button:IsShown()) then
				if (button.cooldown) then
					button.cooldown:Hide()
				end
				button:Hide()
			end
		end
	end

	LayoutAuras(frame, container, count, aconf)
	container:Show()
end

-- CreateTestGroup(group)
local function CreateTestGroup(group)
	local titleFrame = _G["XPerl_Raid_Title"..group]
	if (not titleFrame) then
		return
	end

	local holder = CreateFrame("Frame", nil, titleFrame)
	holder:SetWidth(80)
	holder:SetHeight(40)

	local frames = {}
	for i = 1, #testRoster[group] do
		-- Same template the real frames use, so it carries the same art, bars, name frame and
		-- buff container. No unit attribute is ever set on it.
		local f = CreateFrame("Button", "XPerl_Raid_TestFrame"..group.."_"..i, holder, "XPerl_Raid_FrameTemplate")
		f:SetID(i)
		frames[i] = f
	end

	TestGroups[group] = {holder = holder, frames = frames}
	return TestGroups[group]
end

-- XPerl_Raid_TestMode_Refresh
-- Re-applies every option to the sample frames. Called whenever a raid option changes, so
-- dragging the icon size slider updates the preview live.
function XPerl_Raid_TestMode_Refresh()
	if (not testMode) then
		return
	end

	-- Creating the sample frames and resizing them are both off limits while the secure
	-- environment is locked down, so leave the preview exactly as it is until combat ends.
	if (InCombatLockdown()) then
		return
	end

	local a = testAnchors[rconf.anchor] or testAnchors.TOP
	local spacing = rconf.spacing or 0

	-- Which samples the current options leave, once for all ten frames
	PrepareTestAuras("b", rconf.buffs, testBuffSamples, testBuffList)
	PrepareTestAuras("d", rconf.debuffs, testDebuffSamples, testDebuffList)

	-- The icons are about to be re-armed from scratch, so drop what the ticker was watching
	testTimerCount = 0

	for group = 1, #testRoster do
		local g = TestGroups[group] or CreateTestGroup(group)

		-- Never draw samples over a group that has real people in it. In a raid that means
		-- test mode quietly does nothing for the groups you can already see, and in a party
		-- group 1 stays real while group 2 shows you what a second group would look like.
		--
		-- Only when actually grouped. SetRaidRoster counts you alone as one member of group 1,
		-- so testing this on SubgroupCounts by itself hid the group 1 samples while solo -
		-- which is the main thing test mode is for.
		local grouped = (GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0)

		if (g and grouped and (SubgroupCounts[group] or 0) > 0) then
			g.holder:Hide()
			g = nil
		end

		if (g) then
			local titleFrame = _G["XPerl_Raid_Title"..group]

			g.holder:ClearAllPoints()
			g.holder:SetPoint(a.point, titleFrame, a.rel, 0, 0)
			g.holder:Show()

			-- Ungrouped with Show When Solo on, the header is already drawing your own frame in
			-- the first slot of group 1. Start the samples one slot along so they don't stack on
			-- top of it - your real frame plus four samples still makes a full group of five.
			local skip = 0
			if (group == 1 and not grouped and rconf.inParty and rconf.solo) then
				skip = 1
			end

			for i = 1, skip do
				if (g.frames[i] and g.frames[i]:IsShown()) then
					g.frames[i]:Hide()
				end
			end

			for i, member in ipairs(testRoster[group]) do
			  if (i > skip) then
				local f = g.frames[i]

				Setup1RaidFrame(f)

				f:ClearAllPoints()
				if (i == skip + 1) then
					local slot = 0
					if (skip > 0) then
						slot = ((a.x ~= 0) and f:GetWidth() or f:GetHeight()) + spacing
					end
					f:SetPoint(a.child, g.holder, a.child, slot * skip * a.x, slot * skip * a.y)
				else
					f:SetPoint(a.child, g.frames[i - 1], a.next, spacing * a.x, spacing * a.y)
				end

				local sf = f.statsFrame
				local r, gr, b = TestClassColour(member.class)

				sf.healthBar:SetMinMaxValues(0, 1)
				sf.healthBar:SetValue(conf.bar.inverse and (1 - member.hp) or member.hp)
				if (conf.colour.classbar) then
					sf.healthBar:SetStatusBarColor(r, gr, b)
					if (sf.healthBar.bg) then
						sf.healthBar.bg:SetVertexColor(r, gr, b, 0.25)
					end
				else
					XPerl_SetSmoothBarColor(sf.healthBar, member.hp)
				end
				sf.healthBar.text:SetFormattedText(percD, member.hp * 100)

				if (sf.manaBar) then
					sf.manaBar:SetMinMaxValues(0, 1)
					sf.manaBar:SetValue(member.mp)
					sf.manaBar.text:SetFormattedText(percD, member.mp * 100)
				end

				f.nameFrame.text:SetText(member.name)
				f.nameFrame.text:SetTextColor(r, gr, b)

				-- Every sample frame shows the same set. Which auras are in it is decided by the
				-- options, not by the frame, and that is the whole point of it - ten frames each
				-- showing a different count told you where the row wraps but nothing about
				-- whether your filters do what you wanted.
				TestAuras(f, "b", testBuffList, rconf.buffs)
				TestAuras(f, "d", testDebuffList, rconf.debuffs)

				f:Show()
			  end
			end
		end
	end
end

-- The sample sweeps and countdowns are real timers, so left alone they run out and the row goes
-- quiet - which reads as broken when you are sitting there judging Countdown Start. This re-arms
-- each icon as it expires, on its own sample's cycle, so a five second HoT restarts every five
-- seconds while a twenty five minute buff is left alone. Only the timers are touched: nothing here
-- re-lays anything out, so it is safe to leave running and does no work when nothing has expired.
local TEST_TICK = 0.5

local testTicker = CreateFrame("Frame")
testTicker:Hide()
testTicker:SetScript("OnUpdate", function(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if (self.elapsed < TEST_TICK) then
		return
	end
	self.elapsed = 0

	local now = GetTime()
	for i = 1, testTimerCount do
		local e = testTimers[i]
		if (e.expires and now >= e.expires and e.button.cooldown) then
			e.expires = now + e.sample.left
			TestArmTimer(e.button, e.sample, now)
		end
	end
end)

-- XPerl_Raid_TestMode
-- on = true/false to set it, nil to toggle. Returns the state it ended up in.
function XPerl_Raid_TestMode(on)
	if (on == nil) then
		on = not testMode
	end

	-- The sample frames inherit SecureActionButtonTemplate from the raid template, so they
	-- can't be created or resized while the secure environment is locked down.
	if (on and InCombatLockdown()) then
		XPerl_Notice(XPERL_TEST_MODE_COMBAT)
		return testMode and true or false
	end

	testMode = on and true or false

	if (testMode) then
		XPerl_Raid_TestMode_Refresh()
		testTicker.elapsed = 0
		testTicker:Show()
		XPerl_Notice(XPERL_TEST_MODE_ON)
	else
		testTicker:Hide()
		testTimerCount = 0
		for group, g in pairs(TestGroups) do
			g.holder:Hide()
		end
		XPerl_Notice(XPERL_TEST_MODE_OFF)
	end

	return testMode
end

-- XPerl_Raid_TestModeActive
function XPerl_Raid_TestModeActive()
	return testMode and true or false
end

-- XPerl_Raid_UpdatePlayerFlags(self)
local function XPerl_Raid_UpdatePlayerFlags(self, partyid,...)
	
	if (not partyid) then

		partyid = self:GetAttribute("unit")
	end



	local f = FrameArray[partyid]
	if (f) then

		self = f

		local unitName = UnitName(partyid)
		if (unitName) then
			local unitInfo = XPerl_Roster[unitName]
			if (unitInfo) then
				local change
				if (UnitIsAFK(partyid)) then
					if (not unitInfo.afk) then
						change = true
						unitInfo.afk = GetTime()
						unitInfo.dnd = nil
					end
				elseif (UnitIsDND(partyid)) then
					if (not unitInfo.dnd) then
						change = true
						unitInfo.dnd = GetTime()
						unitInfo.afk = nil
					end
				else
					if (unitInfo.afk or unitInfo.dnd) then
						unitInfo.afk, unitInfo.dnd = nil, nil
						change = true
					end
				end

				if (change) then
					local flags = XPerl_Raid_CheckFlags(partyid)
					if (flags) then
						XPerl_Raid_ShowFlags(self, flags)
					else
						XPerl_Raid_UpdateMana(self)
						XPerl_Raid_UpdateHealth(self)
					end
				end
			end
		end
	end
end

-- XPerl_Raid_ShowRaidGroup
--local function XPerl_Raid_ShowRaidGroup(show)
--	if (rconf.group[show] and rconf.enable and (show < 9 or rconf.sortByClass)) then
--		raidHeaders[show]:Show()
--	else
--		raidHeaders[show]:Hide()
--	end
--end

-- XPerl_Raid_OnUpdate
function XPerl_Raid_OnUpdate(self, elapsed)
	if (rosterUpdated) then
		rosterUpdated = nil
		if (not InCombatLockdown()) then
			XPerl_Raid_Position(self)
		end
		if (XPerl_Custom) then
			XPerl_Custom:UpdateUnits()
		end
		-- Was "no raid members", which now throws away the roster SetRaidRoster just built
		-- from the party and returns before the buff and range updates below ever run - so
		-- party-mode raid frames would have drawn no aura icons at all.
		if (not XPerl_Raid_ShouldShow()) then
			ResArray = {}
			XPerl_Roster = {}
			buffUpdates = {}
			return
		end
	end

	local updateHighlights, someUpdate
	local enemyUnitList

	self.time = self.time + elapsed
	if (self.time >= 0.2) then
		self.time = 0
		someUpdate = true
	end

	for i,frame in pairs(FrameArray) do
		if (frame:IsShown()) then
			if (frame.PlayerFlash) then
				XPerl_Raid_CombatFlash(frame, arg1, false)
			end

			if (someUpdate) then
				local unit = frame.partyid	-- frame:GetAttribute("unit")
				if (unit) then
					local name = UnitName(unit)
					if (name) then
						local myRoster = XPerl_Roster[name]
						if (myRoster) then
							if (frame.statsFrame.greyMana) then
								if (myRoster.offline and UnitIsConnected(unit)) then
									XPerl_Raid_UpdateHealth(frame)
								end
							else
								if (not myRoster.offline and not UnitIsConnected(unit)) then
									XPerl_Raid_UpdateHealth(frame)
								end
							end
						end
					end

					XPerl_UpdateSpellRange(frame, unit, true)
				end
			end
		end
	end

	local i = 1
	for k,v in pairs(buffUpdates) do
		UpdateBuffs(k)
		buffUpdates[k] = nil
		i = i + 1
		if (i > 5) then
			break
		end
	end

	fullyInitiallized = true
end

-- XPerl_Raid_RaidTargetUpdate
local function XPerl_Raid_RaidTargetUpdate(self)
	local icon = self.nameFrame.raidIcon
	local raidIcon = GetRaidTargetIndex(self.partyid)

	if (raidIcon) then
		if (not icon) then
			icon = self.nameFrame:CreateTexture(nil, "OVERLAY")
			self.nameFrame.raidIcon = icon
			icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
			icon:SetPoint("LEFT")
			icon:SetWidth(16)
			icon:SetHeight(16)
		else
			icon:Show()
		end
		SetRaidTargetIconTexture(icon, raidIcon)
	elseif (icon) then
		icon:Hide()
	end
end

-------------------------
-- The Update Function --
-------------------------
function XPerl_Raid_UpdateDisplayAll()
	for k,v in pairs(FrameArray) do
		if (v:IsShown()) then
			XPerl_Raid_UpdateDisplay(v)
		end
	end
end

-- XPerl_Raid_UpdateDisplay
function XPerl_Raid_UpdateDisplay(self)
	-- Health must be updated after mana, since ctra flag checks are done here.
	if (rconf.mana) then
		XPerl_Raid_UpdateManaType(self)
		XPerl_Raid_UpdateMana(self)
	end
	XPerl_Raid_UpdatePlayerFlags(self)
	XPerl_Raid_UpdateHealth(self)		-- <<< -- AFTER MANA -- <<< --
	XPerl_Raid_UpdateName(self)
	XPerl_Raid_UpdateCombat(self)
	XPerl_Unit_UpdateReadyState(self)
	XPerl_Raid_RaidTargetUpdate(self)

	buffUpdates[self] = true		-- UpdateBuffs(self)

	if (not SkipHighlightUpdate) then
		XPerl_Highlight:SetHighlight(self)
	end

	if (XPerl_Voice) then
		XPerl_Voice:UpdateVoice(self)
	end
end

-- XPerl_Raid_Enabled
-- Whether the raid frames are turned on for where we currently are.
local function XPerl_Raid_Enabled()
	local enable = rconf.enable
	if (enable and select(2, IsInInstance()) == "pvp") then
		enable = not rconf.notInBG
	end
	return enable
end

-- XPerl_Raid_ShouldShow
-- The raid frames used to be for raids only, and "One-Group Raid Show" approached the
-- problem from the other end by having the party frames stand in for your own subgroup.
-- That was backwards for anyone who only wants to look at raid frames, so the raid frames
-- now cover a party too and the party frames can simply be turned off.
--
-- In a raid this is unchanged. In a party it follows the Raid tab's "Show In Party", and
-- with nobody grouped at all it follows "Show When Solo".
function XPerl_Raid_ShouldShow()
	if (GetNumRaidMembers() > 0) then
		return true
	end

	if (not rconf or not rconf.inParty or not XPerl_Raid_Enabled()) then
		return false
	end

	if (GetNumPartyMembers() > 0) then
		return true
	end

	return rconf.solo and true or false
end

-- XPerl_Raid_CoversParty
-- Whether the raid frames are really drawing a frame for everybody in this party, which is a
-- different question from XPerl_Raid_ShouldShow. The party frames hide themselves on the answer, so
-- "the frames are up" is not good enough: XPerl_Raid_HideShowRaid only shows a block whose own
-- setting is on, and saying yes for a block that is turned off would hide the party frames too and
-- leave those members with no frame at all.
--
-- False in a raid. The party frames' own "Show In Raid" has always decided that case, and this is
-- only about the party one.
function XPerl_Raid_CoversParty()
	if (GetNumRaidMembers() > 0 or not XPerl_Raid_ShouldShow()) then
		return false
	end

	if (not rconf.sortByClass) then
		-- Every party member is reported as subgroup 1, so that one block is all of them
		return rconf.group[1] == 1 and true or false
	end

	-- Sorting by class the blocks are classes, so every class actually present needs its own on
	for i = 0, GetNumPartyMembers() do
		local unit = (i == 0) and "player" or ("party"..i)
		local _, class = UnitClass(unit)

		if (class) then
			local on
			for n = 1, WoWclassCount do
				local c = rconf.class[n]
				if (c and c.name == class) then
					on = c.enable and true or false
					break
				end
			end

			if (not on) then
				return false
			end
		end
	end

	return true
end

-- HideShowRaid
-- XPerl_Raid_PartyGroup1Only()
-- True when we're being shown for a party rather than a raid and only the group 1 block should
-- be used. Group 1's filter already matches the whole party, so the other group blocks have
-- nothing to show; this keeps them out of the way entirely rather than leaving them up empty.
--
-- Never while sorting by class. The blocks are classes then, not groups, so there is no "group
-- 1" to keep and applying this would hide every class block but the first.
function XPerl_Raid_PartyGroup1Only()
	if (rconf.sortByClass) then
		return false
	end
	return GetNumRaidMembers() == 0 and rconf.inParty and rconf.partyGroup1Only and true or false
end

function XPerl_Raid_HideShowRaid()
	local enable = XPerl_Raid_Enabled()
	local group1Only = XPerl_Raid_PartyGroup1Only()

	for i = 1,WoWclassCount do
		if (group1Only and i ~= 1) then
			if (raidHeaders[i]:IsShown()) then
				raidHeaders[i]:Hide()
			end
		elseif (rconf.group[i] == 1 and enable and (i < 9 or rconf.sortByClass)) then
			if (not raidHeaders[i]:IsShown()) then
				raidHeaders[i]:Show()
			end
		else
			if (raidHeaders[i]:IsShown()) then
				raidHeaders[i]:Hide()
			end
		end
	end
end

-------------------
-- Event Handler --
-------------------

-- XPerl_Raid_OnEvent
function XPerl_Raid_OnEvent(self, event, unit, ...)
	local func = XPerl_Raid_Events[event]
	if (func) then
		if (strfind(event, "^UNIT_")) then
			local f = FrameArray[unit]
			if (f) then
				func(f, unit, ...)
			end
		else
			func(self, unit, ...)
		end
	else
XPerl_ShowMessage("EXTRA EVENT")
	end
end

-- VARIABLES_LOADED
function XPerl_Raid_Events:VARIABLES_LOADED()
	self:UnregisterEvent("VARIABLES_LOADED")

	if (GetNumRaidMembers() == 0) then
		ResArray = {}
		XPerl_Roster = {}
	else
		local myRoster = XPerl_Roster[UnitName("player")]
		if (myRoster) then
			myRoster.afk, myRoster.dnd, myRoster.ressed, myRoster.resCount = nil, nil, nil, nil
		end
	end

	XPerl_Highlight:Register(XPerl_Raid_HighlightCallback, self)

	XPerl_Raid_Events.VARIABLES_LOADED = nil
end

----------------------------------------------------------------------
-- Instance zone-in refresh
--
-- Zoning into an instance would occasionally leave your own frame out of the group. The secure
-- headers fill themselves from the roster, and the roster the client reports while an instance is
-- still loading can be short of you - the header then has nothing to draw for you and does not try
-- again until the next roster event, which never comes if nobody joins or leaves.
--
-- Re-applying the header attributes makes them re-fill from the roster as it stands a moment
-- later, which is what the session's first PLAYER_ENTERING_WORLD already does. Deferred rather
-- than immediate because the roster at the point the event fires is the thing we can't trust.
-- There is no C_Timer on this client, so it's a one-shot OnUpdate that stops itself.
----------------------------------------------------------------------
local ZONE_REFRESH_DELAY = 1

local zoneRefresh = CreateFrame("Frame")
zoneRefresh:Hide()
zoneRefresh:SetScript("OnUpdate", function(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if (self.elapsed < ZONE_REFRESH_DELAY) then
		return
	end

	self.elapsed = nil
	self:Hide()

	rosterUpdated = true			-- so the update driver redoes XPerl_Roster along with it
	XPerl_Raid_ChangeAttributes()		-- queues itself until combat ends if it has to
	XPerl_Raid_UpdateDisplayAll()
end)

-- ScheduleZoneRefresh()
local function ScheduleZoneRefresh()
	zoneRefresh.elapsed = nil
	zoneRefresh:Show()			-- OnUpdate only runs on a shown frame
end

-- XPerl_Raid_Events:PLAYER_ENTERING_WORLDsmall()
function XPerl_Raid_Events:PLAYER_ENTERING_WORLDsmall()
	-- Force a re-draw. Events not processed for anything that happens during
	-- the small time you zone. Some display anomolies can occur from this
	XPerl_Raid_UpdateDisplayAll()

	if (IsInInstance()) then
		XPerl_ModuleLoad("XPerl_CustomHighlight")
		ScheduleZoneRefresh()
	end
end

-- PLAYER_ENTERING_WORLD
function XPerl_Raid_Events:PLAYER_ENTERING_WORLD()
	--self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	
	XPerl_Raid_ChangeAttributes()
	XPerl_RaidTitles()

	raidLoaded = true
	rosterUpdated = nil

	if (XPerl_Raid_ShouldShow()) then
		XPerl_Raid_Frame:Show()
	end

	if (IsInInstance()) then
		XPerl_ModuleLoad("XPerl_CustomHighlight")
		-- Logging in inside an instance races the roster the same way zoning into one does
		ScheduleZoneRefresh()
	end

	XPerl_Raid_Events.PLAYER_ENTERING_WORLD = XPerl_Raid_Events.PLAYER_ENTERING_WORLDsmall
	XPerl_Raid_Events.PLAYER_ENTERING_WORLDsmall = nil
end

do
	local rosterGuids
	-- XPerl_Raid_GetUnitFrameByGUID
	function XPerl_Raid_GetUnitFrameByGUID(guid)
		local unitid = rosterGuids and rosterGuids[guid]
		if (unitid) then
			return FrameArray[unitid]
		end
	end

	local function BuildGuidMap()
		if (GetNumRaidMembers() > 0) then
			rosterGuids = new()
			for i = 1,GetNumRaidMembers() do
				local guid = UnitGUID("raid"..i)
				if (guid) then
					rosterGuids[guid] = "raid"..i
				end
			end
		else
			rosterGuids = del(rosterGuids)
		end
	end

	-- RAID_ROSTER_UPDATE
	function XPerl_Raid_Events:RAID_ROSTER_UPDATE()
		rosterUpdated = true		-- Many roster updates can occur during 1 video frame, so we'll check everything at end of last one
		BuildGuidMap()
		if (XPerl_Raid_ShouldShow()) then
			XPerl_Raid_Frame:Show()
		end
	end

	-- PARTY_MEMBERS_CHANGED
	-- The secure headers re-fill themselves on this, but our own roster and the show/hide
	-- decision need it too now that a party can drive the raid frames.
	function XPerl_Raid_Events:PARTY_MEMBERS_CHANGED()
		rosterUpdated = true
		BuildGuidMap()
		if (XPerl_Raid_ShouldShow()) then
			XPerl_Raid_Frame:Show()
		else
			XPerl_Raid_Frame:Hide()
		end
	end
	
	function XPerl_Raid_Events:PLAYER_LOGIN()
		BuildGuidMap()
	end
end

-- UNIT_FLAGS
function XPerl_Raid_Events:UNIT_FLAGS()
	XPerl_Raid_UpdateCombat(self)
end

XPerl_Raid_Events.UNIT_DYNAMIC_FLAGS = XPerl_Raid_Events.UNIT_FLAGS

function XPerl_Raid_Events:PLAYER_FLAGS_CHANGED(unit,...)
	XPerl_Raid_UpdatePlayerFlags(self, unit,...)
end

-- UNIT_FACTION
function XPerl_Raid_Events:UNIT_FACTION()
	XPerl_Raid_UpdateCombat(self)
	XPerl_Raid_UpdateName(self)
end

-- UNIT_COMBAT
function XPerl_Raid_Events:UNIT_COMBAT()
	if (arg2 == "HEAL") then
		XPerl_Raid_CombatFlash(self, 0, true, true)
	elseif (arg4 and arg4 > 0) then
		XPerl_Raid_CombatFlash(self, 0, true)
	end
end

-- UNIT_HEALTH
function XPerl_Raid_Events:UNIT_HEALTH()
	XPerl_Raid_UpdateHealth(self)
	XPerl_Raid_UpdateCombat(self)
end
XPerl_Raid_Events.UNIT_MAXHEALTH = XPerl_Raid_Events.UNIT_HEALTH

function XPerl_Raid_Events:UNIT_DISPLAYPOWER()
	XPerl_Raid_UpdateManaType(self)
	XPerl_Raid_UpdateMana(self)
end

-- WoW 4.0 UNIT_POWER shit (Added by PlayerLin)

function XPerl_Raid_Events:UNIT_POWER()
	if (rconf.mana) then
		XPerl_Raid_UpdateMana(self)
	end
end

XPerl_Raid_Events.UNIT_MAXPOWER   = XPerl_Raid_Events.UNIT_POWER

-- WoW 3.3.5 and older.
-- UNIT_MANA
function XPerl_Raid_Events:UNIT_MANA()
	if (rconf.mana) then
		XPerl_Raid_UpdateMana(self)
	end
end
XPerl_Raid_Events.UNIT_MAXMANA   = XPerl_Raid_Events.UNIT_MANA
XPerl_Raid_Events.UNIT_RAGE      = XPerl_Raid_Events.UNIT_MANA
XPerl_Raid_Events.UNIT_MAXRAGE   = XPerl_Raid_Events.UNIT_MANA
XPerl_Raid_Events.UNIT_ENERGY    = XPerl_Raid_Events.UNIT_MANA
XPerl_Raid_Events.UNIT_MAXENERGY = XPerl_Raid_Events.UNIT_MANA
XPerl_Raid_Events.UNIT_RUNIC_POWER = XPerl_Raid_Events.UNIT_MANA
XPerl_Raid_Events.UNIT_MAXRUNIC_POWER = XPerl_Raid_Events.UNIT_MANA

-- UNIT_NAME_UPDATE
function XPerl_Raid_Events:UNIT_NAME_UPDATE()
	XPerl_Raid_UpdateName(self)
	XPerl_Raid_UpdateHealth(self)			-- Added 16th May 2007 - Seems they now fire name update to indicate some change in state.
end

-- UNIT_AURA
function XPerl_Raid_Events:UNIT_AURA()
	lastNamesList, lastName, lastWith = nil, nil, nil
	UpdateBuffs(self)
end

-- READY_CHECK
function XPerl_Raid_Events:READY_CHECK(a, b, c)
	for i,frame in pairs(FrameArray) do
		if (frame.partyid) then
			XPerl_Unit_UpdateReadyState(frame)
		end
	end
end

XPerl_Raid_Events.READY_CHECK_CONFIRM = XPerl_Raid_Events.READY_CHECK
XPerl_Raid_Events.READY_CHECK_FINISHED = XPerl_Raid_Events.READY_CHECK

-- RAID_TARGET_UPDATE
function XPerl_Raid_Events:RAID_TARGET_UPDATE()
	for i,frame in pairs(FrameArray) do
		if (frame.partyid) then
			XPerl_Raid_RaidTargetUpdate(frame)
		end
	end
end

-- SetRes
local function SetResStatus(resserName, resTargetName, ignoreCounter)

	--frame.beingRessed = true
	local resEnd

	if (resTargetName) then
		ResArray[resserName] = resTargetName
	else
		resEnd = true

		for i,name in pairs(ResArray) do
			if (i == resserName) then
				resTargetName = name
				break
			end
		end

		ResArray[resserName] = nil
	end

	if (resTargetName) then
		local myRoster = XPerl_Roster[resTargetName]
		if (myRoster) then
			if (resEnd and not ignoreCounter) then
				myRoster.ressed = 1
				myRoster.resCount = (myRoster.resCount or 0) + 1
			end
			UpdateUnitByName(resTargetName, true)
		end
	end
end

-- UNIT_SPELLCAST_START
function XPerl_Raid_Events:UNIT_SPELLCAST_START(unit, spell, rank)
	if (ResArray[UnitName(unit)]) then
		-- Flagged as ressing, finish their old cast
		SetResStatus(UnitName(unit))
	end

	local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill = UnitCastingInfo(unit)
	if (resSpells[name]) then
		local u = unit.."target"
		if (UnitExists(u) and UnitIsDead(u)) then
			SetResStatus(UnitName(unit), UnitName(u))
		end
	end
end

-- UNIT_SPELLCAST_STOP
function XPerl_Raid_Events:UNIT_SPELLCAST_STOP(unit)
	if (unit) then
		SetResStatus(UnitName(unit))
	end
end

-- UNIT_SPELLCAST_FAILED
function XPerl_Raid_Events:UNIT_SPELLCAST_FAILED(unit)
	if (unit) then
		SetResStatus(UnitName(unit), nil, true)
	end
end

XPerl_Raid_Events.UNIT_SPELLCAST_INTERRUPTED = XPerl_Raid_Events.UNIT_SPELLCAST_FAILED

-- Direct string matches can be done via table lookup
local QuickFuncs = {
	--AFK	= function(m)	m.afk = GetTime(); m.dnd = nil; end,
	--UNAFK	= function(m)	m.afk = nil; end,
	--DND	= function(m)	m.dnd = GetTime(); m.afk = nil; end,
	--UNDND	= function(m)	m.dnd = nil; end,
	RESNO	= function(m,n) SetResStatus(n) end,
	RESSED	= function(m)	m.ressed = 1; end,
	CANRES	= function(m)	m.ressed = 2; end,
	NORESSED= function(m)
		if (m.ressed) then
			m.ressed = 3
		else
			m.ressed = nil
		end
		m.resCount = nil
	end,
	SR	= XPerl_SendModules
}

-- DurabilityCheck(msg, author)
-- Quick DUR check for those people who don't have oRA2 and CTRA installed
-- No, I'm not going to replace either mod
local XPerl_DurabilityCheck
do
	local tip
	function XPerl_DurabilityCheck(author)
		local durPattern = gsub(DURABILITY_TEMPLATE, "(%%%d-$-d)", "(%%d+)")
		local cur, max, broken = 0, 0, 0
		if (not tip) then
			tip = CreateFrame("GameTooltip", "XPerlDurCheckTooltip")
		end

		tip:SetOwner(self, "ANCHOR_RIGHT")
		tip:ClearAllPoints()
		tip:SetPoint("TOP", UIParent, "BOTTOM", -200, 0)
		for i = 1, 18 do
			if (GetInventoryItemBroken("player", i)) then
				broken = broken + 1
			end

			tip:SetInventoryItem("player", i)

			for j = 1,tip:NumLines() do
				local line = _G[tip:GetName().."TextLeft"..j]
				if (line) then
					local text = line:GetText()
					if (text) then
						local imin, imax = strmatch(text, durPattern)
						if (imin and imax) then
							imin, imax = tonumber(imin), tonumber(imax)
							cur = cur + imin
							max = max + imax
							break
						end
					end
				end
			end
		end

		tip:Hide()

		SendAddonMessage("CTRA", format("DUR %s %s %s %s", cur, max, broken, author), "RAID")
	end
end

-- XPerl_ItemCheckCount
local function XPerl_ItemCheckCount(itemName, author)
	local count = GetItemCount(itemName)
	if (count and count > 0) then
		SendAddonMessage("CTRA", "ITM "..count.." "..itemName.." "..author, "RAID")
	end
end

-- XPerl_ResistsCheck
local function XPerl_ResistsCheck(unitName)
	local str = ""
	for i = 2, 6 do
		str = str.." "..select(2, UnitResistance("player", i))
	end
	SendAddonMessage("CTRA", format("RST%s %s", str, unitName), "RAID")
end

-- ProcessCTRAMessage
local function ProcessCTRAMessage(unitName, msg)
	local myRoster = XPerl_Roster[unitName]

	if (not myRoster) then
		return
	end

	local update = true

	local func = QuickFuncs[msg]
	if (func) then
--ChatFrame7:AddMessage("QuickFuncs["..msg.."]")
		func(myRoster, unitName)
	else
		if (strsub(msg, 1, 4) == "RES ") then
			SetResStatus(unitName, strsub(msg, 5))
			return

		elseif (strsub(msg, 1, 3) == "CD ") then
			local num, cooldown = strmatch(msg, "^CD (%d+) (%d+)$")
			if ( num == "1" ) then
				myRoster.Rebirth = GetTime() + tonumber(cooldown)*60
			elseif ( num == "2" ) then
				myRoster.Reincarnation = GetTime() + tonumber(cooldown)*60
			elseif ( num == "3" ) then
				myRoster.Soulstone = GetTime() + tonumber(cooldown)*60
			end
			update = nil

		elseif (strsub(msg, 1, 2) == "V ") then
			myRoster.version = strsub(msg, 3)
			update = nil

		elseif (msg == "DURC") then
			if (not CT_RA_VersionNumber and not oRA) then
				XPerl_DurabilityCheck(unitName)
			end

		elseif (msg == "RSTC") then
			if (not CT_RA_VersionNumber and not oRA) then
				XPerl_ResistsCheck(unitName)
			end

		elseif (strsub(msg, 1, 4) == "ITMC") then
			if (not CT_RA_VersionNumber and not oRA) then
				local itemName = strmatch(msg, "^ITMC (.+)$")
				if (itemName) then
					XPerl_ItemCheckCount(itemName, unitName)
				end
			end
		else
			update = nil
		end
	end

	if (update) then
		UpdateUnitByName(unitName, true)
	end
end

-- ProcessoRAMessage
local function ProcessoRAMessage(unitName, msg)
	local myRoster = XPerl_Roster[unitName]

	if (not myRoster) then
		return
	end

	if (strsub(msg, 1, 5) == "oRAV ") then
		myRoster.oRAversion = strsub(msg, 6)
	end
end

-- XPerl_Raid_Events:CHAT_MSG_RAID
-- Check for AFK/DND flags in chat
--function XPerl_Raid_Events:CHAT_MSG_RAID()
--	local myRoster = XPerl_Roster[arg4]
--	if (myRoster) then
--		if (arg6 == "AFK") then
--			if (not myRoster.afk) then
--				myRoster.afk = GetTime()
--				myRoster.dnd = nil
--			end
--		elseif (arg6 == "DND") then
--			if (not myRoster.dnd) then
--				myRoster.dnd = GetTime()
--				myRoster.afk = nil
--			end
--		else
--			myRoster.dnd, myRoster.afk = nil, nil
--		end
--	end
--end
--XPerl_Raid_Events.CHAT_MSG_RAID_LEADER = XPerl_Raid_Events.CHAT_MSG_RAID
--XPerl_Raid_Events.CHAT_MSG_PARTY = XPerl_Raid_Events.CHAT_MSG_RAID

-- XPerl_ParseCTRA
function XPerl_ParseCTRA(sender, msg, func)
	local arr = new(strsplit("#", msg))
	for i,subMsg in pairs(arr) do
		func(sender, subMsg)
	end
	del(arr)
end

-- CHAT_MSG_ADDON
function XPerl_Raid_Events:CHAT_MSG_ADDON(prefix, msg, channel, sender)
	if (channel == "RAID") then
		if (prefix == "CTRA") then
			XPerl_ParseCTRA(sender, msg, ProcessCTRAMessage)
		elseif (prefix == "oRA") then
			XPerl_ParseCTRA(sender, msg, ProcessoRAMessage)
		end
	end
end

-- SetRaidRoster
local function SetRaidRoster()
	local NewRoster = new()

	del(RaidPositions)
	RaidPositions = new()

	del(RaidGroupCounts)
	RaidGroupCounts = new(0,0,0,0,0,0,0,0,0,0)

	for i = 1,8 do
		SubgroupCounts[i] = 0
	end

	-- In a party the raid frames are fed by the party, and GetRaidRosterInfo has nothing to
	-- say about it. Walk the party instead so the roster still gets built - the AFK/DND,
	-- name colouring and res tracking all key off XPerl_Roster, and without this they would
	-- silently do nothing on party-mode raid frames.
	if (GetNumRaidMembers() == 0) then
		for i = 0,GetNumPartyMembers() do
			local unit = (i == 0) and "player" or ("party"..i)
			local name = UnitExists(unit) and UnitName(unit)

			if (name) then
				local fileName = select(2, UnitClass(unit))

				RaidPositions[name] = unit
				myGroup = 1
				SubgroupCounts[1] = (SubgroupCounts[1] or 0) + 1

				if (rconf.sortByClass) then
					for j = 1,WoWclassCount do
						if (rconf.class[j].name == fileName and rconf.class[j].enable) then
							RaidGroupCounts[j] = RaidGroupCounts[j] + 1
							break
						end
					end
				else
					RaidGroupCounts[1] = RaidGroupCounts[1] + 1
				end

				local r = XPerl_Roster[name]
				if (r) then
					NewRoster[name] = r
					XPerl_Roster[name] = nil
					r.afk = UnitIsAFK(unit) and GetTime() or nil
					r.dnd = UnitIsDND(unit) and GetTime() or nil
				else
					NewRoster[name] = new()
				end
			end
		end
	end

	for i = 1,GetNumRaidMembers() do
		local name, rank, group, level, class, fileName = GetRaidRosterInfo(i)

		if (name) then
			local unit = "raid"..i
			RaidPositions[name] = unit

			if (UnitIsUnit(unit, "player")) then
				myGroup = group
			end

			if (group) then
				SubgroupCounts[group] = (SubgroupCounts[group] or 0) + 1
			end

			if (rconf.sortByClass) then
				for j = 1,WoWclassCount do
					if (rconf.class[j].name == fileName and rconf.class[j].enable) then
						RaidGroupCounts[j] = RaidGroupCounts[j] + 1
						break
					end
				end
			else
				RaidGroupCounts[group] = RaidGroupCounts[group] + 1
			end

			local r = XPerl_Roster[name]
			if (r) then
				NewRoster[name] = r
				XPerl_Roster[name] = nil
				r.afk = UnitIsAFK(unit) and GetTime() or nil
				r.dnd = UnitIsDND(unit) and GetTime() or nil
			else
				NewRoster[name] = new()
			end
		end
	end

	if (XPerl_Raid_ShouldShow()) then
		XPerl_Raid_Frame:Show()
	else
		XPerl_Raid_Frame:Hide()
	end

	del(XPerl_Roster, true)
	XPerl_Roster = NewRoster
end

-- XPerl_RaidGroupCounts()
function XPerl_RaidGroupCounts()
	return RaidGroupCounts
end

-- XPerl_Raid_Position
function XPerl_Raid_Position(self)
	SetRaidRoster()
	XPerl_RaidTitles()

	-- Was gated on the old One-Group Raid Show option, since that was the only thing that
	-- could change which headers should be up. Party mode can too, so this now always runs.
	if (fullyInitiallized and not InCombatLockdown()) then
		XPerl_Raid_HideShowRaid()
	end

	-- Roster just changed, so which groups have real people in them may have too. Lets test
	-- mode stand down for a group that has filled up, without needing to be toggled off.
	XPerl_Raid_TestMode_Refresh()
end

--------------------
-- Click Handlers --
--------------------

-- XPerl_ScaleRaid
function XPerl_ScaleRaid()
	for frame = 1,WoWclassCount do
		local f = _G["XPerl_Raid_Title"..frame]
		if (f) then
			f:SetScale(rconf.scale)
		end
	end
end

-- XPerl_RaidTitles
function XPerl_RaidTitles()
	local c
	local group1Only = XPerl_Raid_PartyGroup1Only()
	for i = 1,WoWclassCount do
		local confClass = rconf.class[i].name
		local frame = _G["XPerl_Raid_Title"..i]
		local titleFrame = frame.text
		local virtualFrame = frame.virtual

		if (not rconf.sortByClass and myGroup == i) then
			c = HIGHLIGHT_FONT_COLOR
		else
			c = NORMAL_FONT_COLOR
		end
		titleFrame:SetTextColor(c.r, c.g, c.b)

		if (rconf.sortByClass) then
			if (LOCALIZED_CLASS_NAMES_MALE[confClass]) then
				titleFrame:SetText(LOCALIZED_CLASS_NAMES_MALE[confClass])
			else
				titleFrame:SetText(localGroups[confClass])
			end
		else
			titleFrame:SetFormattedText(XPERL_RAID_GROUP, i)
		end

		local enable = XPerl_Raid_Enabled()

		-- The group1Only check has to beat the unlocked case too, or the other group titles
		-- would still appear while positioning frames in a party.
		if (group1Only and i ~= 1) then
			if (virtualFrame:IsShown()) then
				virtualFrame:Hide()
			end
			if (titleFrame:IsShown()) then
				titleFrame:Hide()
			end
		elseif (XPerlLocked == 0 or (RaidGroupCounts[i] > 0 and enable and rconf.group[i])) then
			if (XPerlLocked == 0 or rconf.titles) then
				if (not titleFrame:IsShown()) then
					titleFrame:Show()
				end
			else
				if (titleFrame:IsShown()) then
					titleFrame:Hide()
				end
			end

			if (XPerlLocked == 0) then
				local rows = conf.sortByClass and RaidGroupCounts[i] or 5
				virtualFrame:ClearAllPoints()
				if (rconf.anchor == "TOP") then
					virtualFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
					virtualFrame:SetHeight(((rconf.mana or 0) * rows + 38) * rows + (rconf.spacing * (rows - 1)))
					virtualFrame:SetWidth(80)

				elseif (rconf.anchor == "LEFT") then
					virtualFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
					virtualFrame:SetHeight((rconf.mana or 0) * 5 + 38)
					virtualFrame:SetWidth(80 * rows + (rconf.spacing * (rows - 1)))

				elseif (rconf.anchor == "BOTTOM") then
					virtualFrame:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 0)
					virtualFrame:SetHeight(((rconf.mana or 0) * rows + 38) * rows + (rconf.spacing * (rows - 1)))
					virtualFrame:SetWidth(80)

				elseif (rconf.anchor == "RIGHT") then
					virtualFrame:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0)
					virtualFrame:SetHeight((rconf.mana or 0) * 5 + 38)
					virtualFrame:SetWidth(80 * rows + (rconf.spacing * (rows - 1)))
				end

				virtualFrame:SetBackdropColor(conf.colour.frame.r, conf.colour.frame.g, conf.colour.frame.b, conf.colour.frame.a)
				virtualFrame:SetBackdropBorderColor(conf.colour.border.r, conf.colour.border.g, conf.colour.border.b, 1)
				virtualFrame:Show()
			else
				virtualFrame:Hide()
			end
		else
			if (virtualFrame:IsShown()) then
				virtualFrame:Hide()
			end
			if (titleFrame:IsShown()) then
				titleFrame:Hide()
			end
		end
	end

	XPerl_ProtectedCall(XPerl_EnableRaidMouse)

	if (XPerl_RaidPets_Align) then
		XPerl_ProtectedCall(XPerl_RaidPets_Align)
	end
end

-- XPerl_EnableRaidMouse()
function XPerl_EnableRaidMouse()
	for i = 1,WoWclassCount do
		local frame = _G["XPerl_Raid_Title"..i]
		if (XPerlLocked == 0) then
			frame:EnableMouse(true)
		else
			frame:EnableMouse(false)
		end
	end
end

-- XPerl_Raid_SetBuffTooltip
function XPerl_Raid_SetBuffTooltip(self)
	if (conf.tooltip.enableBuffs and XPerl_TooltipModiferPressed(true)) then
		if (not conf.tooltip.hideInCombat or not InCombatLockdown()) then
			local parentUnit = self:GetParent():GetParent()
			local partyid = SecureButton_GetUnit(parentUnit)
			if (not partyid) then
				return
			end

			GameTooltip:SetOwner(self,"ANCHOR_BOTTOMRIGHT",30,0)

			-- Which kind of aura this icon is showing is now a property of the icon, since
			-- a frame can have a buff row and a debuff row up at the same time.
			if (self.auraType == "b") then
				XPerl_TooltipSetUnitBuff(GameTooltip, partyid, self:GetID(), (rconf.buffs.castable == 1) and "RAID", true)
			elseif (self.auraType == "d") then
				XPerl_TooltipSetUnitDebuff(GameTooltip, partyid, self:GetID(), (rconf.debuffs.curable == 1) and "RAID", true)
			end
		end
	end
end

------- XPerl_ToggleRaidBuffs -------
-- Raid Buff Key Binding function --
function XPerl_ToggleRaidBuffs(castable)

	if (castable) then
		if (rconf.buffs.castable == 1) then
			rconf.buffs.castable = 0
			XPerl_Notice(XPERL_KEY_NOTICE_RAID_BUFFANY)
		else
			rconf.buffs.castable = 1
			XPerl_Notice(XPERL_KEY_NOTICE_RAID_BUFFCURECAST)
		end
	else
		if (rconf.buffs.enable) then
			rconf.buffs.enable = nil
			rconf.debuffs.enable = 1
			XPerl_Notice(XPERL_KEY_NOTICE_RAID_DEBUFFS)

		elseif (rconf.debuffs.enable) then
			rconf.buffs.enable = nil
			rconf.debuffs.enable = nil
			XPerl_Notice(XPERL_KEY_NOTICE_RAID_NOBUFFS)

		else
			rconf.buffs.enable = 1
			rconf.debuffs.enable = nil
			XPerl_Notice(XPERL_KEY_NOTICE_RAID_BUFFS)
		end
	end

	for k,v in pairs(FrameArray) do
		if (v:IsShown()) then
			XPerl_Raid_UpdateDisplay(v)
		end
	end
end

-- XPerl_ToggleRaidSort
function XPerl_ToggleRaidSort(New)
	if (not XPerl_Options or not XPerl_Options:IsShown()) then
		if (not InCombatLockdown()) then
			if (New) then
				conf.sortByClass = New == 1
			else
				if (conf.sortByClass) then
					conf.sortByClass = nil
				else
					conf.sortByClass = 1
				end
			end
			XPerl_Raid_ChangeAttributes()
			XPerl_Raid_Position()
			XPerl_Raid_Set_Bits(XPerl_Raid_Frame)
		end
	end
end

-- GetCombatRezzerList()
local normalRezzers = {PRIEST = true, SHAMAN = true, PALADIN = true}
local function GetCombatRezzerList()

	local anyCombat = 0
	local anyAlive = 0
	for i = 1,GetNumRaidMembers() do
		local unit = "raid"..i
		if (normalRezzers[select(2, UnitClass(unit))]) then
			if (UnitAffectingCombat(unit)) then
				anyCombat = anyCombat + 1
			end
			if (not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit)) then
				anyAlive = anyAlive + 1
			end
		end
	end

	-- We only need to know about battle rezzers if any normal rezzers are in combat
	if (anyCombat > 0 or anyAlive < 3) then
		local ret = new()
		local t = GetTime()

		for i = 1,GetNumRaidMembers() do
			local raidid = "raid"..i
			if (not UnitIsDeadOrGhost(raidid) and UnitIsVisible(raidid)) then
				local name, rank, subgroup, level, _, fileName, zone, online, isDead = GetRaidRosterInfo(i)

				local good
				if (not UnitAffectingCombat(raidid)) then
					if (fileName == "PRIEST" or fileName == "SHAMAN" or fileName == "PALADIN") then
						tinsert(ret, {["name"] = name, class = fileName, cd = 0})
					end
				else
					if (fileName == "DRUID") then
						local myRoster = XPerl_Roster[name]

						if (myRoster) then
							if (myRoster.Rebirth and myRoster.Rebirth - t <= 0) then
								myRoster.Rebirth = nil		-- Check for expired cooldown
							end
							if (myRoster.Rebirth) then
								if (myRoster.Rebirth - t < 120) then
									tinsert(ret, {["name"] = name, class = fileName, cd = myRoster.Rebirth - t})
								end
							else
								tinsert(ret, {["name"] = name, class = fileName, cd = 0})
							end
						end
					end
				end
			end
		end

		if (#ret > 0) then
			sort(ret, function(a,b) return a.cd < b.cd end)

			local list = ""
			for k,v in ipairs(ret) do
				local name = XPerlColourTable[v.class]..v.name.."|r"

				if (v.cd > 0) then
					name = name.." (in "..SecondsToTime(v.cd)..")"
				end

				if (list == "") then
					list = name
				else
					list = list..", "..name
				end
			end
			del(ret)
			return list
		else
			del(ret)
			return "|c00FF0000"..NONE.."|r"
		end
	end

	if (anyAlive == 0) then
		return "|c00FF0000"..NONE.."|r"
	elseif (anyCombat == 0) then
		return "|c00FFFFFF"..ALL.."|r"
	end
end

-- XPerl_RaidTipExtra
function XPerl_RaidTipExtra(unitid)

	if (UnitInRaid(unitid)) then
		local unitName = UnitName(unitid)
		local zone
		local name, rank, subgroup, level, class, fileName, zone, online, isDead

		for i = 1,GetNumRaidMembers() do
			name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
			if (name == unitName) then
				break
			end
			zone = ""
		end

		local stats = XPerl_Roster[unitName]
		if (stats) then
			local t = GetTime()

			if (stats.version) then
				if (stats.oRAversion) then
					GameTooltip:AddLine("CTRA "..stats.version.." (oRA "..stats.oRAversion..")", 1, 1, 1)
				else
					GameTooltip:AddLine("CTRA "..stats.version, 1, 1, 1)
				end
			else
				GameTooltip:AddLine(XPERL_RAID_TOOLTIP_NOCTRA, 0.7, 0.7, 0.7)
			end

			if (stats.offline and UnitIsConnected(unitid)) then
				stats.offline = nil
			end
			if (stats.afk and not UnitIsAFK(unitid)) then
				stats.afk = nil
			end
			if (stats.dnd and not UnitIsDND(unitid)) then
				stats.dnd = nil
			end

			if (stats.offline) then
				GameTooltip:AddLine(format(XPERL_RAID_TOOLTIP_OFFLINE, SecondsToTime(t - stats.offline)))

			elseif (stats.afk) then
				GameTooltip:AddLine(format(XPERL_RAID_TOOLTIP_AFK, SecondsToTime(t - stats.afk)))

			elseif (stats.dnd) then
				GameTooltip:AddLine(format(XPERL_RAID_TOOLTIP_DND, SecondsToTime(t - stats.dnd)))

			elseif (stats.fd) then
				if (not UnitIsDead(unitid)) then
					stats.fd = nil
				else
					local x = stats.fd + 360 - t
					if (x > 0) then
						GameTooltip:AddLine(format(XPERL_RAID_TOOLTIP_DYING, SecondsToTime(x)))
					end
				end
			end

			if (stats.Rebirth) then
				if (stats.Rebirth - t > 0) then
					GameTooltip:AddLine(format(XPERL_RAID_TOOLTIP_REBIRTH, SecondsToTime(stats.Rebirth - t)))
				else
					stats.Rebirth = nil
				end

			elseif (stats.Reincarnation) then
				if (stats.Reincarnation - t > 0) then
					GameTooltip:AddLine(format(XPERL_RAID_TOOLTIP_ANKH, SecondsToTime(stats.Reincarnation - t)))
				else
					stats.Reincarnation = nil
				end

			elseif (stats.Soulstone) then
				if (stats.Soulstone - t > 0) then
					GameTooltip:AddLine(format(XPERL_RAID_TOOLTIP_SOULSTONE, SecondsToTime(stats.Soulstone - t)))
				else
					stats.Soulstone = nil
				end
			end

			if (UnitIsDeadOrGhost(unitid) and not UnitIsFeignDeath(unitid)) then
				if (stats.resCount) then
					GameTooltip:AddLine(XPERL_LOC_RESURRECTED.." x"..stats.resCount)
				end

				local Rezzers = GetCombatRezzerList()
				if (Rezzers) then
					GameTooltip:AddLine(XPERL_RAID_RESSER_AVAIL..Rezzers, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1)
				end
			end
		end

		GameTooltip:Show()
	end
end

-- initialConfigFunction
local function initialConfigFunction(self)
	-- This is the only place we're allowed to set attributes whilst in combat
	
	self:SetScript("OnAttributeChanged", onAttrChanged)
	XPerl_RegisterClickCastFrame(self)
	XPerl_RegisterClickCastFrame(self.nameFrame)

	Setup1RaidFrame(self)

	self:SetAttribute("*type1", "target")
	self:SetAttribute("type2", "menu")
	self.menu = XPerl_Raid_ShowPopup

	-- Does AllowAttributeChange work for children?
	self.nameFrame:SetAttribute("useparent-unit", true)
	self.nameFrame:SetAttribute("*type1", "target")
	self.nameFrame:SetAttribute("type2", "menu")
	self.nameFrame.menu = XPerl_Raid_ShowPopup

	if (rconf.mana) then
		self:SetAttribute("initial-height", 43)
	else
		self:SetAttribute("initial-height", 38)
	end
end

-- SetMainHeaderAttributes
local function SetMainHeaderAttributes(self)

	self:Hide()

	self.initialConfigFunction = initialConfigFunction

	if (rconf.sortAlpha) then
		self:SetAttribute("sortMethod", "NAME")
	else
		self:SetAttribute("sortMethod", nil)
	end

	-- Raid frames in a party.
	-- SecureRaidGroupHeaderTemplate is SecureGroupHeaderTemplate plus showRaid = true, and
	-- nothing else, so these headers ignored a party entirely. Adding showParty makes the
	-- same headers fill from the party when there is no raid; showRaid is still checked
	-- first, so a real raid behaves exactly as before.
	--
	-- showPlayer is what puts you in the list - in a raid you are already a raid member, so
	-- it only has an effect here. showSolo covers being in no group at all, where the party
	-- count is zero and the header would otherwise have nothing to show.
	self:SetAttribute("showParty", rconf.inParty and true or false)
	self:SetAttribute("showPlayer", rconf.inParty and true or false)
	self:SetAttribute("showSolo", (rconf.inParty and rconf.solo) and true or false)

	self:SetAttribute("point", rconf.anchor)
	self:SetAttribute("minWidth", 80)
	self:SetAttribute("minHeight", 10)
	local titleFrame = self:GetParent()
	self:ClearAllPoints()
	if (rconf.anchor == "TOP") then
		self:SetPoint("TOP", titleFrame, "BOTTOM", 0, 0)
		self:SetAttribute("xOffset", 0)
		self:SetAttribute("yOffset", -rconf.spacing)
	elseif (rconf.anchor == "LEFT") then
		self:SetPoint("TOPLEFT", titleFrame, "BOTTOMLEFT", 0, 0)
		self:SetAttribute("xOffset", rconf.spacing)
		self:SetAttribute("yOffset", 0)
	elseif (rconf.anchor == "BOTTOM") then
		self:SetPoint("BOTTOM", titleFrame, "TOP", 0, 0)
		self:SetAttribute("xOffset", 0)
		self:SetAttribute("yOffset", rconf.spacing)
	elseif (rconf.anchor == "RIGHT") then
		self:SetPoint("TOPRIGHT", titleFrame, "BOTTOMRIGHT", 0, 0)
		self:SetAttribute("xOffset", -rconf.spacing)
		self:SetAttribute("yOffset", 0)
	end
end

-- XPerl_Raid_SetAttributes
function XPerl_Raid_ChangeAttributes()

	if (InCombatLockdown()) then
		tinsert(XPerl_OutOfCombatQueue, XPerl_Raid_ChangeAttributes)
		return
	end

	rconf.anchor = (rconf and rconf.anchor) or "TOP"

	local function DefaultRaidClasses()
		return {
			{enable = true, name = "WARRIOR"},
			{enable = true, name = "DEATHKNIGHT"},
			{enable = true, name = "ROGUE"},
			{enable = true, name = "HUNTER"},
			{enable = true, name = "MAGE"},
			{enable = true, name = "WARLOCK"},
			{enable = true, name = "PRIEST"},
			{enable = true, name = "DRUID"},
			{enable = true, name = "SHAMAN"},
			{enable = true, name = "PALADIN"},
		}
	end

	local function GroupFilter(n)
		if (rconf.sortByClass) then
			if (not rconf.class[n]) then
				rconf.class = DefaultRaidClasses()
			end
			if (rconf.class[n].enable) then
				return rconf.class[n].name
			end
			return ""
		else
			local f
			if (rconf.group[n]) then
				f = tostring(n)
			end

			for i = 1,WoWclassCount do
				if (not rconf.class[i]) then
					invalid = true
				end
			end
			if (invalid) then
				rconf.class = DefaultRaidClasses()
			end

			for i = 1,WoWclassCount do
				if (rconf.class[i].enable) then
					if (not f) then
						f = rconf.class[i].name
					else
						f = f..","..rconf.class[i].name
					end
				end
			end
			return f
		end
	end

	for i = 1,rconf.sortByClass and WoWclassCount or 8 do
		local groupHeader = raidHeaders[i]

		-- Hide this when we change attributes, so the whole re-calc is only done once, instead of for every attribute change
		groupHeader:Hide()

		groupHeader:SetAttribute("strictFiltering", not rconf.sortByClass)
		groupHeader:SetAttribute("groupFilter", GroupFilter(i))
		SetMainHeaderAttributes(groupHeader)
	end

	XPerl_Raid_HideShowRaid()
end

-- XPerl_Raid_Set_Bits
function XPerl_Raid_Set_Bits(self)
	if (raidLoaded) then
		XPerl_ProtectedCall(XPerl_Raid_HideShowRaid)
	end
	SkipHighlightUpdate = nil

	XPerl_ScaleRaid()

	for i = 1,WoWclassCount do
		XPerl_SavePosition(_G["XPerl_Raid_Title"..i], true)
	end

	for i,frame in pairs(FrameArray) do
		Setup1RaidFrame(frame)
	end

	local manaEvents = {"UNIT_DISPLAYPOWER", "UNIT_RAGE", "UNIT_MAXRAGE", "UNIT_ENERGY", "UNIT_MAXENERGY", "UNIT_MANA", "UNIT_MAXMANA", "UNIT_RUNIC_POWER", "UNIT_MAXRUNIC_POWER"}
	for i,event in pairs(manaEvents) do
		if (rconf.mana) then
			self:RegisterEvent(event)
		else
			self:UnregisterEvent(event)
		end
	end
	SkipHighlightUpdate = nil

	if (XPerl_Raid_ShouldShow()) then
		XPerl_Raid_Frame:Show()
	end
end
