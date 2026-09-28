--[[
	RollbackRodPrompt.lua - reverses UpdateRodPrompt.lua: back to the 8cb2554
	rod-offers install (bottom-screen Buy/Pass panel).
	HOW TO RUN: stop Play, paste into the Studio Command Bar (Edit mode).

	In one undo step ("Rollback RodPrompt"): every script the update changed
	gets its recorded Before (8cb2554) source back, then
	ServerStorage.EconomyRodPromptBackup is removed. Nothing else is touched:
	ServerStorage.EconomyRodOffersBackup (the original uninstall chain) stays,
	so UninstallRodOffers.lua still works afterwards.

	Safety: if a script was edited after the update (its source no longer
	matches the recorded After copy), nothing is changed unless FORCE_RESTORE.
	Roll back later economy milestones FIRST. Saved Money is NOT touched.
]]

local FORCE_RESTORE = false

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local TAG = "EconomyOwned"
local BACKUP = "EconomyRodPromptBackup"
local LATER = { "EconomySalesBackup", "EconomyAquariumBackup" }

local function fail(msg)
	warn("[RollbackRodPrompt] " .. msg .. " - nothing changed.")
end

local function normalize(s)
	s = s:gsub("\r", "")
	s = s:gsub("[ \t]+\n", "\n")
	s = s:gsub("%s+$", "")
	return s
end

if RunService:IsRunning() then
	return fail("stop Play first (run this in Edit mode)")
end
for _, name in ipairs(LATER) do
	if ServerStorage:FindFirstChild(name) then
		return fail("ServerStorage." .. name .. " exists: roll that milestone back first")
	end
end

local backup = ServerStorage:FindFirstChild(BACKUP)
if not backup or backup:GetAttribute(TAG) ~= true then
	return fail("ServerStorage." .. BACKUP .. " not found (update not installed?)")
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
		return fail(target:GetFullName() .. " was edited after the update; set FORCE_RESTORE = true to restore anyway")
	end
	table.insert(restores, { target = target, source = before.Source })
end
if #restores == 0 then
	return fail("ServerStorage." .. BACKUP .. " is empty")
end

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Rollback RodPrompt")
end)
if not ok or not recording then
	recording = nil
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before Rollback RodPrompt")
	end)
end

local done, err = pcall(function()
	for _, r in ipairs(restores) do
		r.target.Source = r.source
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
		ChangeHistoryService:SetWaypoint("Rollback RodPrompt")
	end)
end

if not done then
	return warn("[RollbackRodPrompt] Failed: " .. tostring(err))
end
print(string.format("[RollbackRodPrompt] Restored %d script(s) to 8cb2554. Saved Money is kept.", #restores))
