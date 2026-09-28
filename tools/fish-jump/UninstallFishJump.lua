--[[
	UninstallFishJump.lua - reverses InstallFishJump.lua.
	HOW TO RUN: stop Play, paste into the Studio Command Bar (Edit mode).

	In one undo step ("Uninstall FishJump"): restores FishSwimClient's original
	source from ServerStorage.FishJumpBackup and removes ReplicatedStorage.FishJump
	and the backup (only objects tagged FishJumpOwned). Stops instead if
	FishSwimClient was edited after install, unless FORCE_RESTORE is true.
]]

local FORCE_RESTORE = false

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TAG = "FishJumpOwned"

local function fail(msg)
	warn("[UninstallFishJump] " .. msg .. " - nothing changed.")
end

local function normalize(s)
	s = s:gsub("\r", "")
	s = s:gsub("[ \t]+\n", "\n")
	s = s:gsub("%s+$", "")
	return s
end

if game:GetService("RunService"):IsRunning() then
	return fail("stop Play first (run this in Edit mode)")
end
local backup = ServerStorage:FindFirstChild("FishJumpBackup")
if not backup or backup:GetAttribute(TAG) ~= true then
	return fail("ServerStorage.FishJumpBackup not found (not installed?)")
end
local targetValue = backup:FindFirstChild("Target")
local target = targetValue and targetValue:IsA("ObjectValue") and targetValue.Value
local original = backup:FindFirstChild("FishSwimClient_original")
local patched = backup:FindFirstChild("FishSwimClient_patched")
if not (target and target:IsA("LocalScript") and target:IsDescendantOf(game)) then
	return fail("the patched FishSwimClient was moved or deleted; restore it by hand from " .. backup:GetFullName())
end
if not (original and original:IsA("LocalScript") and patched and patched:IsA("LocalScript")) then
	return fail("backup copies are missing from " .. backup:GetFullName())
end
if normalize(target.Source) ~= normalize(patched.Source) and not FORCE_RESTORE then
	return fail(target:GetFullName() .. " was edited after install; set FORCE_RESTORE = true to restore anyway")
end
local module = ReplicatedStorage:FindFirstChild("FishJump")
if module and module:GetAttribute(TAG) ~= true then
	module = nil -- not ours; leave it
end

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Uninstall FishJump")
end)
if not ok or not recording then
	recording = nil
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before Uninstall FishJump")
	end)
end

local done, err = pcall(function()
	target.Source = original.Source
	if module then
		module:Destroy()
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
		ChangeHistoryService:SetWaypoint("Uninstall FishJump")
	end)
end

if not done then
	return warn("[UninstallFishJump] Failed: " .. tostring(err))
end
print("[UninstallFishJump] Restored " .. target:GetFullName() .. " and removed FishJump.")
