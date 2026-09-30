-- UpgradeBoardServer (Script in ServerScriptService). [Economy upgrade board v4: Faster Reels]
--
-- The four-upgrade board (Workspace.Board: its Main part's SurfaceGui.bord3).
-- UpgradeBoardClient draws the four cards for each player and asks here
-- through ReplicatedStorage.Economy.UpgradeAction (a RemoteFunction made at
-- run time): InvokeServer(upgradeId) -> (ok, message). The server decides
-- everything; the client only shows the answer.
--   * NetStrength: the SAME saved net capacity the KGsign posts sell
--     (EconomyService.netKgAction: alive, money loaded, one purchase at a
--     time, cooldown, money + capacity saved in one write before it counts).
--     Here "in reach" means near the board. NetCapacityServer follows the
--     player's NetKg attribute, so the shared NetLift.MaxWeight updates the
--     same way as after a sign purchase.
--   * RodLuck: the player's saved Rod Luck level (EconomyService.upgradeAction:
--     the same checks, money + level saved in one write; paid board upgrades
--     open with UpgradesOpen). RodFishingSystem reads the committed value
--     once per accepted press.
--   * MeatPrice: the same, for the saved Meat Price level (EconomyService
--     multiplies each of the player's own fish's whole value once, when the
--     grinder cuts it).
--   * FasterReels: the same, for the saved reel speed (RodFishingSystem reads
--     the committed value once per accepted press).
--   * anything else: refused.
-- The result is also a toast (EconomyService.notify).
--
-- The board is found by its exact path, never by a name that could match
-- two things: exactly one Workspace child named Board, exactly one Main
-- part in it, exactly one SurfaceGui on Main with exactly one bord3.
-- Without a running EconomyService, or without that board, no remote is
-- made and nothing can be bought here (fail closed).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function only(parent: Instance, name: string, class: string): (Instance?, string?)
	local found = nil
	local count = 0
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			count += 1
			found = child
		end
	end
	if count ~= 1 then
		return nil, string.format("expected exactly one %s.%s, found %d", parent:GetFullName(), name, count)
	end
	if not (found :: Instance):IsA(class) then
		return nil, string.format("%s is a %s, not a %s", (found :: Instance):GetFullName(), (found :: Instance).ClassName, class)
	end
	return found, nil
end

-- Workspace.Board.Main (the part the board's SurfaceGui is on), or nil + why.
local function findBoard(): (BasePart?, string?)
	local board, why = only(workspace, "Board", "Model")
	if not board then
		return nil, why
	end
	local main, why2 = only(board :: Instance, "Main", "BasePart")
	if not main then
		return nil, why2
	end
	local gui, why3 = only(main :: Instance, "SurfaceGui", "SurfaceGui")
	if not gui then
		return nil, why3
	end
	local _, why4 = only(gui :: Instance, "bord3", "Frame")
	if why4 then
		return nil, why4
	end
	return main :: BasePart, nil
end

local Economy = nil
do
	local mod = ServerScriptService:FindFirstChild("EconomyService")
	if mod and mod:IsA("ModuleScript") then
		local ok, api = pcall(require, mod)
		if ok and type(api) == "table" then
			local ran, running = pcall(api.start)
			if ran and running and type(api.netKgAction) == "function" then
				Economy = api
			else
				warn("[UpgradeBoard] economy not running: the upgrade board sells nothing (" .. tostring(running) .. ")")
			end
		else
			warn("[UpgradeBoard] could not load EconomyService: the upgrade board sells nothing (" .. tostring(api) .. ")")
		end
	else
		warn("[UpgradeBoard] no EconomyService: the upgrade board sells nothing")
	end
end
if not Economy then
	return
end

local main, missing = findBoard()
if not main then
	warn("[UpgradeBoard] " .. tostring(missing) .. ": the upgrade board sells nothing")
	return
end

local root = ReplicatedStorage:FindFirstChild("Economy")
if not (root and root:IsA("Folder")) then
	warn("[UpgradeBoard] ReplicatedStorage.Economy missing: the upgrade board sells nothing")
	return
end
if root:FindFirstChild("UpgradeAction") then
	-- ours is made here, at run time, and never saved: an existing one isn't ours
	warn("[UpgradeBoard] ReplicatedStorage.Economy.UpgradeAction already exists and isn't ours: the upgrade board sells nothing")
	return
end

local Config = Economy.Config
local PRESS_GAP = 0.25 -- seconds between presses per player (each upgrade has its own cooldown too)

-- The press's own place check: near the board (re-run right before the debit).
local function nearBoard(player: Player): () -> (boolean, string?)
	return function()
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local reach = Config.UpgradeBoardReach + main.Size.Magnitude / 2
		if not (hrp and hrp:IsA("BasePart")) or not main:IsDescendantOf(workspace) or (hrp.Position - main.Position).Magnitude > reach then
			return false, "Walk up to the board"
		end
		return true, nil
	end
end

-- what each card sells; a card listed in SOON isn't sold yet
local SOLD: { [string]: (Player) -> (boolean, string) } = {
	NetStrength = function(player: Player): (boolean, string)
		local ok, message = Economy.netKgAction(player, nearBoard(player))
		return ok, message
	end,
}
local SOON: { [string]: string } = {}
for _, id in ipairs({ "RodLuck", "MeatPrice", "FasterReels" }) do
	if type(Economy.upgradeAction) == "function" and Economy.BoardUpgrades and Economy.BoardUpgrades.known(id) then
		SOLD[id] = function(player: Player): (boolean, string)
			local ok, message = Economy.upgradeAction(player, id, nearBoard(player))
			return ok, message
		end
	else
		warn("[UpgradeBoard] EconomyService can't sell " .. id .. " (older version?): it shows as coming soon")
		SOON[id] = id .. " upgrades are coming soon"
	end
end

local lastPress: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	lastPress[player] = nil
end)

local remote = Instance.new("RemoteFunction")
remote.Name = "UpgradeAction"
remote.Archivable = false
remote.OnServerInvoke = function(player: Player, id: any): (boolean, string)
	if type(id) ~= "string" or not (SOLD[id] or SOON[id]) then
		return false, "Unknown upgrade"
	end
	local now = os.clock()
	if lastPress[player] and now - lastPress[player] < PRESS_GAP then
		return false, "Slow down a little"
	end
	lastPress[player] = now
	local action = SOLD[id]
	local ok, message
	if not action then
		ok, message = false, SOON[id]
	else
		local ran, a, b = pcall(action, player)
		if ran then
			ok, message = a, b
		else
			warn("[UpgradeBoard] " .. id .. " failed: " .. tostring(a))
			ok, message = false, "Couldn't do that right now"
		end
	end
	Economy.notify(player, message, if ok then "success" else "warn")
	return ok, message
end
remote.Parent = root
