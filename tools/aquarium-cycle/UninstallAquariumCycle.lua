--[[
	UninstallAquariumCycle.lua - reverses InstallAquariumCycle.lua.
	HOW TO RUN: stop Play, then paste into the Studio Command Bar (Edit mode).

	In one undo step ("Uninstall AquariumCycle"):
	  * restores RodFishingSystem's original source from
	    ServerStorage.AquariumCycleBackup
	  * removes ReplicatedStorage.AquariumCycle,
	    ServerScriptService.AquariumCycleServer / AquariumEconomy,
	    StarterPlayer.StarterPlayerScripts.AquariumTankClient and the backup
	Only objects carrying the AquariumCycleOwned attribute are removed; nothing
	else in the place is touched.

	Safety: if RodFishingSystem was edited after the install, restoring would
	throw those edits away, so it stops instead unless FORCE_RESTORE is true.
]]

local FORCE_RESTORE = false

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local TAG = "AquariumCycleOwned"

local function fail(msg)
	warn("[UninstallAquariumCycle] " .. msg .. " - nothing changed.")
end

local function normalize(s)
	s = s:gsub("\r", "")
	s = s:gsub("[ \t]+\n", "\n")
	s = s:gsub("%s+$", "")
	return s
end

local backup = ServerStorage:FindFirstChild("AquariumCycleBackup")
if not backup or backup:GetAttribute(TAG) ~= true then
	return fail("ServerStorage.AquariumCycleBackup not found (not installed?)")
end
local targetValue = backup:FindFirstChild("Target")
local target = targetValue and targetValue:IsA("ObjectValue") and targetValue.Value
local original = backup:FindFirstChild("RodFishingSystem_original")
local patched = backup:FindFirstChild("RodFishingSystem_patched")
if not (target and target:IsA("Script") and target:IsDescendantOf(game)) then
	return fail("the patched RodFishingSystem was moved or deleted; restore it by hand from " .. backup:GetFullName())
end
if not (original and original:IsA("Script") and patched and patched:IsA("Script")) then
	return fail("backup copies are missing from " .. backup:GetFullName())
end
if normalize(target.Source) ~= normalize(patched.Source) and not FORCE_RESTORE then
	return fail(
		target:GetFullName()
			.. " was edited after install; restoring would discard those edits. Set FORCE_RESTORE = true to restore anyway"
	)
end

local starterScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
local toRemove = {}
for _, inst in ipairs({
	ReplicatedStorage:FindFirstChild("AquariumCycle"),
	ServerScriptService:FindFirstChild("AquariumCycleServer"),
	ServerScriptService:FindFirstChild("AquariumEconomy"),
	starterScripts and starterScripts:FindFirstChild("AquariumTankClient"),
}) do
	if inst and inst:GetAttribute(TAG) == true then
		table.insert(toRemove, inst)
	end
end

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Uninstall AquariumCycle")
end)
if not ok or not recording then
	recording = nil
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before Uninstall AquariumCycle")
	end)
end

local restoredSource = original.Source
local done, err = pcall(function()
	target.Source = restoredSource
	for _, inst in ipairs(toRemove) do
		inst:Destroy()
	end
	backup:Destroy()
end)

if recording then
	ChangeHistoryService:FinishRecording(
		recording,
		if done then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)
elseif done then
	pcall(function()
		ChangeHistoryService:SetWaypoint("Uninstall AquariumCycle")
	end)
end

if not done then
	return warn("[UninstallAquariumCycle] Failed: " .. tostring(err))
end
print("[UninstallAquariumCycle] Restored " .. target:GetFullName() .. " and removed " .. #toRemove .. " installed object(s) plus the backup.")
