--[[
	UninstallRodCast.lua - reverses InstallRodCast.lua.
	HOW TO RUN: stop Play, paste into the Studio Command Bar (Edit mode).

	In one undo step ("Uninstall RodCast"): RodFishingSystem and
	RodFishingClient get their Before sources back from
	ServerStorage.RodCastBackup, then the backup is removed. Nothing else is
	touched. Refuses if either script was edited after install, unless
	FORCE_RESTORE. Uninstall this before uninstalling variants or the aquarium.
]]

local FORCE_RESTORE = false

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ServerStorage = game:GetService("ServerStorage")

local TAG = "RodCastOwned"

local function fail(msg)
	warn("[UninstallRodCast] " .. msg .. " - nothing changed.")
end

local function normalize(s)
	s = s:gsub("\r", "")
	s = s:gsub("[ \t]+\n", "\n")
	s = s:gsub("%s+$", "")
	return s
end

local backup = ServerStorage:FindFirstChild("RodCastBackup")
if not backup or backup:GetAttribute(TAG) ~= true then
	return fail("ServerStorage.RodCastBackup not found (not installed?)")
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

local toRemove = {} -- RodCast adds no modules

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Uninstall RodCast")
end)
if not ok or not recording then
	recording = nil
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before Uninstall RodCast")
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
		ChangeHistoryService:SetWaypoint("Uninstall RodCast")
	end)
end

if not done then
	return warn("[UninstallRodCast] Failed: " .. tostring(err))
end
print(string.format("[UninstallRodCast] Restored %d script(s)/module(s) and removed %d module(s).", #restores, #toRemove))
