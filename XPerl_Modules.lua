-- X-Perl UnitFrames - All-in-One module manager
-- ---------------------------------------------------------------------------
-- The classic X-Perl suite ships as ~17 separate AddOn folders and the Options
-- panel toggles them with EnableAddOn()/DisableAddOn()/IsAddOnLoaded().
--
-- This all-in-one build merges every module into the single "XPerl" folder, so
-- those real AddOns no longer exist. This file re-implements the enable/disable
-- system *inside* the merged addon:
--
--   * A per-character SavedVariable (XPerlModuleState) stores the DESIRED state
--     of each module. This is what EnableAddOn/DisableAddOn write.
--   * A session table (active) stores what is actually running THIS session,
--     decided once at load from the desired state. This is what IsAddOnLoaded
--     reports, so the "Reload UI" button in the Options panel lights up exactly
--     as before whenever a pending change differs from the running state.
--   * On load, any module whose desired state is "off" is torn down (frames
--     hidden, events unregistered, updates stopped) so it is inert.
--
-- Net effect: the existing Options panel keeps working unchanged - tick a box,
-- the Reload UI button enables, reload, and the module turns on/off. Exactly the
-- original workflow, just backed by one folder instead of many.
-- ---------------------------------------------------------------------------

-- Ordered list is not important here; keys are the old AddOn names.
-- frames = top-level frames to hide/deactivate when the module is disabled.
-- blizz  = Blizzard frames this module suppresses (used by the load-time guard
--          so the default UI frame can survive when the module is turned off).
-- always = helper modules that are always present and never torn down.
-- augment= modules that decorate other frames rather than owning their own;
--          disabled via a best-effort function guard instead of frame teardown.
local MODULES = {
	XPerl_Player        = {frames = {"XPerl_Player"}, blizz = {"PlayerFrame"}},
	XPerl_PlayerBuffs   = {augment = true},
	XPerl_PlayerPet     = {frames = {"XPerl_Player_Pet"}, blizz = {"PetFrame"}},
	XPerl_Target        = {frames = {"XPerl_Target", "XPerl_Focus"}, blizz = {"TargetFrame", "TargetofTargetFrame", "FocusFrame"}},
	XPerl_TargetTarget  = {frames = {"XPerl_TargetTarget"}},
	XPerl_Party         = {frames = {"XPerl_Party_Anchor", "XPerl_Party_SecureHeader"}, blizz = {"PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4"}},
	XPerl_PartyPet      = {frames = {"XPerl_Party_Pet_EventFrame"}},
	XPerl_ArcaneBar     = {augment = true},
	XPerl_RaidFrames    = {frames = {"XPerl_Raid_Frame"}},
	XPerl_RaidPets      = {frames = {"XPerl_RaidPets_Frame"}},
	XPerl_RaidHelper    = {frames = {"XPerl_Frame", "XPerl_Assists_Frame", "XPerl_Aggro"}},
	XPerl_RaidAdmin     = {frames = {"XPerl_AdminFrame", "XPerl_Check"}},
	XPerl_RaidMonitor   = {frames = {"XPerl_RaidMonitor_Frame"}},
	XPerl_Options       = {always = true},
	XPerl_CustomHighlight = {always = true},
	XPerl_Tutorial      = {always = true},
}

-- Which module owns a given Blizzard frame (reverse of the .blizz lists above).
local blizzOwner = {}
for name, info in pairs(MODULES) do
	if (info.blizz) then
		for _, bf in pairs(info.blizz) do
			blizzOwner[bf] = name
		end
	end
end

local active					-- session state: nil until computed at load
local computed = false

-- Read the desired (pending) on/off state of a module. Defaults to enabled.
local function IsDesired(name)
	local info = MODULES[name]
	if (not info) then return nil end			-- not one of ours
	if (info.always) then return true end
	local state = XPerlModuleState				-- may still be nil very early
	if (state and state[name] ~= nil) then
		return state[name] and true or false
	end
	return true									-- default: enabled
end

-- XPerl_ModuleIsActive(name)
-- True if the module is running this session. Before the session state is
-- computed (very early load) it falls back to the desired state so the
-- Blizzard-frame guard below can make the right call at frame-load time.
function XPerl_ModuleIsActive(name)
	if (not MODULES[name]) then return nil end
	if (computed and active) then
		return active[name] and true or false
	end
	return IsDesired(name)
end

-- XPerl_ModuleBlizzKeep(frame)
-- Called from XPerl_BlizzFrameDisable(). Returns true if the Blizzard frame
-- should be LEFT ALONE because the X-Perl module that would replace it is
-- currently disabled. Best-effort: only helps when the saved state is already
-- available at load; otherwise the original behaviour (suppress it) is kept.
function XPerl_ModuleBlizzKeep(frame)
	if (not frame) then return false end
	local fname = frame.GetName and frame:GetName()
	if (not fname) then return false end
	local owner = blizzOwner[fname]
	if (not owner) then return false end
	return XPerl_ModuleIsActive(owner) == false
end

----------------------------------------------------------------------
-- Teardown of a disabled module
----------------------------------------------------------------------
local function KillFrame(f)
	if (not f) then return end
	pcall(function()
		if (UnregisterUnitWatch) then UnregisterUnitWatch(f) end
		if (f.UnregisterAllEvents) then f:UnregisterAllEvents() end
		if (f.SetScript) then
			f:SetScript("OnUpdate", nil)
			f:SetScript("OnEvent", nil)
		end
		if (XPerl_UnregisterPerlFrames) then XPerl_UnregisterPerlFrames(f) end
		if (f.Hide) then f:Hide() end
		f.xperlModuleDisabled = true
	end)
end

-- Best-effort suppression for the two "augment" modules that don't own a
-- top-level frame. Wrapped so a missing function never errors.
local function SuppressAugment(name)
	if (name == "XPerl_PlayerBuffs") then
		pcall(function()
			local p = _G.XPerl_Player
			if (p) then
				if (p.buffFrame and p.buffFrame.Hide) then p.buffFrame:Hide() end
				if (p.debuffFrame and p.debuffFrame.Hide) then p.debuffFrame:Hide() end
			end
			local noop = function() end
			XPerl_Player_BuffSetup = noop
			XPerl_PlayerBuffs_OnUpdate = noop
			XPerl_Player_TempEnchantUpdate = noop
		end)
	elseif (name == "XPerl_ArcaneBar") then
		pcall(function()
			local noop = function() end
			XPerl_ArcaneBar_RegisterFrame = noop
			XPerl_ArcaneBar_SetUnit = noop
			XPerl_ArcaneBar_Set = noop
		end)
	end
end

local function TeardownModule(name)
	local info = MODULES[name]
	if (not info or info.always) then return end
	if (info.augment) then
		SuppressAugment(name)
		return
	end
	if (info.frames) then
		for _, fname in pairs(info.frames) do
			KillFrame(_G[fname])
		end
	end
end

-- Compute the session state once and tear down whatever is turned off.
local function ApplyModuleStates()
	if (computed) then return end
	XPerlModuleState = XPerlModuleState or {}
	active = {}
	for name, info in pairs(MODULES) do
		local on = IsDesired(name)
		active[name] = on
		if (not on) then
			TeardownModule(name)
		end
	end
	computed = true
end

----------------------------------------------------------------------
-- Shims for the AddOn API, scoped to X-Perl module names only.
-- Anything that is not one of our modules is passed straight through to
-- the real Blizzard function, so other addons are unaffected.
----------------------------------------------------------------------
local _EnableAddOn   = EnableAddOn
local _DisableAddOn  = DisableAddOn
local _IsAddOnLoaded = IsAddOnLoaded
local _LoadAddOn     = LoadAddOn
local _GetAddOnInfo  = GetAddOnInfo

local function SetDesired(name, on)
	XPerlModuleState = XPerlModuleState or {}
	XPerlModuleState[name] = on and true or false
end

function EnableAddOn(name, ...)
	if (name and MODULES[name]) then
		SetDesired(name, true)
		return
	end
	return _EnableAddOn(name, ...)
end

function DisableAddOn(name, ...)
	if (name and MODULES[name]) then
		local info = MODULES[name]
		if (info and info.always) then return end	-- never disable helpers
		SetDesired(name, false)
		return
	end
	return _DisableAddOn(name, ...)
end

function IsAddOnLoaded(name, ...)
	if (name and MODULES[name]) then
		-- Return 1/nil to match Blizzard's IsAddOnLoaded and CheckButton:GetChecked()
		-- in 3.3.5a. The Options "Reload UI" button compares the two directly, so
		-- the value types must line up or it would always appear enabled.
		return XPerl_ModuleIsActive(name) and 1 or nil
	end
	return _IsAddOnLoaded(name, ...)
end

function LoadAddOn(name, ...)
	if (name and MODULES[name]) then
		-- Everything is already in memory in the merged build.
		return true, nil
	end
	return _LoadAddOn(name, ...)
end

function GetAddOnInfo(name, ...)
	if (name and MODULES[name]) then
		-- name, title, notes, enabled, loadable, reason, security
		-- reason = nil means "present and loadable" (the Options panel checks
		-- for "MISSING" to hide sections for modules that aren't installed).
		-- enabled mirrors the desired (pending) on/off state.
		local enabled = IsDesired(name) and 1 or nil
		return name, name, "", enabled, 1, nil, "INSECURE"
	end
	return _GetAddOnInfo(name, ...)
end

-- Compute (once) and re-assert teardown of every disabled module.
local function DoApply()
	ApplyModuleStates()
	if (active) then
		for name, on in pairs(active) do
			if (not on) then TeardownModule(name) end
		end
	end
end

----------------------------------------------------------------------
-- Event driver
--
-- The manager loads before the rest of X-Perl so its API shims are in place
-- for all module code. That also means this frame's event handlers would run
-- *before* the core's setup handlers for the same event. To make sure teardown
-- always happens AFTER the core has finished showing/positioning frames for a
-- given login or zone-in, the actual work is deferred by one frame via a
-- one-shot OnUpdate (there is no C_Timer in 3.3.5a).
----------------------------------------------------------------------
local f = CreateFrame("Frame")

local function ScheduleApply()
	f:SetScript("OnUpdate", function(self)
		self:SetScript("OnUpdate", nil)
		DoApply()
	end)
end

f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self)
	ScheduleApply()
end)
