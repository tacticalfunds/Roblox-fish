--[[
	UninstallGrinderDwell.lua - reverses InstallGrinderDwell.lua.
	HOW TO RUN: stop Play, paste into the Studio Command Bar (Edit mode).

	In one undo step ("Uninstall GrinderDwell"): FishSwimClient, NetLiftScript
	and RodFishingSystem get their Before sources back from
	ServerStorage.GrinderDwellBackup; ReplicatedStorage.GrinderDwell and the
	backup are removed (only objects tagged GrinderDwellOwned). Refuses if any
	script was edited after install, unless FORCE_RESTORE. Uninstall this
	FIRST, before any of the other features.
]]

local FORCE_RESTORE = false

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TAG = "GrinderDwellOwned"

local function fail(msg)
	warn("[UninstallGrinderDwell] " .. msg .. " - nothing changed.")
end

local function normalize(s)
	s = s:gsub("\r", "")
	s = s:gsub("[ \t]+\n", "\n")
	s = s:gsub("%s+$", "")
	return s
end

local backup = ServerStorage:FindFirstChild("GrinderDwellBackup")
if not backup or backup:GetAttribute(TAG) ~= true then
	return fail("ServerStorage.GrinderDwellBackup not found (not installed?)")
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

local toRemove = {}
for _, inst in ipairs({
	ReplicatedStorage:FindFirstChild("GrinderDwell"),
}) do
	if inst and inst:GetAttribute(TAG) == true then
		table.insert(toRemove, inst)
	end
end

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Uninstall GrinderDwell")
end)
if not ok or not recording then
	recording = nil
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before Uninstall GrinderDwell")
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
		ChangeHistoryService:SetWaypoint("Uninstall GrinderDwell")
	end)
end

if not done then
	return warn("[UninstallGrinderDwell] Failed: " .. tostring(err))
end
print(string.format("[UninstallGrinderDwell] Restored %d script(s)/module(s) and removed %d module(s).", #restores, #toRemove))
