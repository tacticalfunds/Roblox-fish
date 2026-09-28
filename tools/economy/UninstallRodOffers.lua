--[[
	UninstallRodOffers.lua - reverses InstallRodOffers.lua.
	HOW TO RUN: stop Play, paste into the Studio Command Bar (Edit mode).

	In one undo step ("Uninstall RodOffers"): RodFishingSystem and
	RodShopServer get their recorded Before source back, then
	ReplicatedStorage.Economy, ServerScriptService.EconomyService /
	EconomyBoot, StarterPlayerScripts.EconomyClient and the backup are removed
	(only objects tagged EconomyOwned).

	Safety: if either script was edited after install (its source no longer
	matches the recorded After copy), nothing is changed unless FORCE_RESTORE.
	Uninstall later economy milestones FIRST (they build on EconomyService).
	Saved Money in the DataStore is NOT deleted.
]]

local FORCE_RESTORE = false

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local TAG = "EconomyOwned"
local BACKUP = "EconomyRodOffersBackup"
-- backups of later economy milestones; they must be uninstalled first
local LATER = { "EconomySalesBackup", "EconomyAquariumBackup" }

local function fail(msg)
	warn("[UninstallRodOffers] " .. msg .. " - nothing changed.")
end

local function normalize(s)
	s = s:gsub("\r", "")
	s = s:gsub("[ \t]+\n", "\n")
	s = s:gsub("%s+$", "")
	return s
end

for _, name in ipairs(LATER) do
	if ServerStorage:FindFirstChild(name) then
		return fail("ServerStorage." .. name .. " exists: uninstall that milestone first")
	end
end

local backup = ServerStorage:FindFirstChild(BACKUP)
if not backup or backup:GetAttribute(TAG) ~= true then
	return fail("ServerStorage." .. BACKUP .. " not found (not installed?)")
end

local restores = {}
for _, entry in ipairs(backup:GetChildren()) do
	local targetValue = entry:FindFirstChild("Target")
	local target = targetValue and targetValue:IsA("ObjectValue") and targetValue.Value
	local before = entry:FindFirstChild("Before")
	local after = entry:FindFirstChild("After")
	if not (target and target:IsA("LuaSourceContainer") and target:IsDescendantOf(game)) then
		return fail(entry.Name .. ": target was moved or deleted; restore it by hand from " .. entry:GetFullName())
	end
	if not (before and before:IsA("LuaSourceContainer") and after and after:IsA("LuaSourceContainer")) then
		return fail(entry.Name .. ": backup copies are missing")
	end
	if normalize(target.Source) ~= normalize(after.Source) and not FORCE_RESTORE then
		return fail(target:GetFullName() .. " was edited after install; set FORCE_RESTORE = true to restore anyway")
	end
	table.insert(restores, { target = target, source = before.Source })
end

-- Dense { parent, name } list, each slot checked explicitly; only objects
-- tagged EconomyOwned are removed (an untagged object with the same name is
-- someone else's and is left alone).
local starterScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
local OWN = {
	{ ReplicatedStorage, "Economy" },
	{ ServerScriptService, "EconomyService" },
	{ ServerScriptService, "EconomyBoot" },
	{ starterScripts, "EconomyClient" },
}
local toRemove, skipped = {}, {}
for _, slot in ipairs(OWN) do
	local parent, name = slot[1], slot[2]
	local inst = parent and parent:FindFirstChild(name)
	if inst then
		if inst:GetAttribute(TAG) == true then
			table.insert(toRemove, inst)
		else
			table.insert(skipped, inst:GetFullName())
		end
	end
end

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Uninstall RodOffers")
end)
if not ok or not recording then
	recording = nil
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before Uninstall RodOffers")
	end)
end

local done, err = pcall(function()
	for _, r in ipairs(restores) do
		r.target.Source = r.source
	end
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
		ChangeHistoryService:SetWaypoint("Uninstall RodOffers")
	end)
end

if not done then
	return warn("[UninstallRodOffers] Failed: " .. tostring(err))
end
print(string.format("[UninstallRodOffers] Restored %d script(s) and removed %d object(s). Saved Money is kept.", #restores, #toRemove))
for _, path in ipairs(skipped) do
	warn("[UninstallRodOffers] left " .. path .. " in place: not tagged EconomyOwned (not ours)")
end
