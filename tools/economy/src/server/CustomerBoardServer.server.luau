-- CustomerBoardServer (Script in ServerScriptService). [Economy customer board v1]
--
-- The old two-panel board (Workspace.Board: Main > SurfaceGui > bord3) sells
-- the two CUSTOMER upgrades. CustomerBoardClient draws each player's copy of
-- it and asks here through ReplicatedStorage.Economy.CustomerUpgradeAction (a
-- RemoteFunction made at run time, never saved): InvokeServer(id) -> (ok, message).
--   * CustomerSpeed: customers a minute this player brings (the server's rate
--     is the sum of the present players', capped - EconomyService.customers)
--   * CustomerLine: places in the line (the server's line is the largest)
--   * anything else: refused
-- Both are saved board upgrades (EconomyService.upgradeAction: alive, money
-- loaded, one purchase at a time, cooldown, money + level in ONE write before
-- it counts, re-checked right before the debit; open with UpgradesOpen). Here
-- "in reach" means near the board (Config.UpgradeBoardReach + half its size).
-- The result is also a toast. No truck unlock is needed.
--
-- The board is found by its exact path: exactly one Workspace child named
-- Board, exactly one BasePart Main in it. Without a running EconomyService or
-- that board, no remote is made and nothing is sold (fail closed).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local IDS = { CustomerSpeed = true, CustomerLine = true }
local PRESS_GAP = 0.25 -- seconds between presses per player (each upgrade has its own cooldown too)

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

local Economy = nil
do
	local mod = ServerScriptService:FindFirstChild("EconomyService")
	if mod and mod:IsA("ModuleScript") then
		local ok, api = pcall(require, mod)
		if ok and type(api) == "table" then
			local ran, running = pcall(api.start)
			if ran and running and type(api.upgradeAction) == "function" then
				Economy = api
			else
				warn("[CustomerBoard] economy not running: the customer board sells nothing (" .. tostring(running) .. ")")
			end
		else
			warn("[CustomerBoard] could not load EconomyService: the customer board sells nothing (" .. tostring(api) .. ")")
		end
	else
		warn("[CustomerBoard] no EconomyService: the customer board sells nothing")
	end
end
if not Economy then
	return
end

local board, missing = only(workspace, "Board", "Model")
local main = nil
if board then
	main, missing = only(board :: Instance, "Main", "BasePart")
end
if not main then
	warn("[CustomerBoard] " .. tostring(missing) .. ": the customer board sells nothing")
	return
end

local root = ReplicatedStorage:FindFirstChild("Economy")
if not (root and root:IsA("Folder")) then
	warn("[CustomerBoard] ReplicatedStorage.Economy missing: the customer board sells nothing")
	return
end
if root:FindFirstChild("CustomerUpgradeAction") then
	warn("[CustomerBoard] ReplicatedStorage.Economy.CustomerUpgradeAction already exists and isn't ours: the customer board sells nothing")
	return
end

local Config = Economy.Config
for id in pairs(IDS) do
	if not (Config.BoardUpgrades and Config.BoardUpgrades[id] and table.find(Config.BoardUpgradeIds, id)) then
		warn("[CustomerBoard] EconomyService doesn't know " .. id .. " (older version?): the customer board sells nothing")
		return
	end
end
local mainPart = main :: BasePart

-- the press's own place check: near the board (re-run right before the debit)
local function nearBoard(player: Player): () -> (boolean, string?)
	return function()
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		local reach = Config.UpgradeBoardReach + mainPart.Size.Magnitude / 2
		if not (hrp and hrp:IsA("BasePart")) or not mainPart:IsDescendantOf(workspace) or (hrp.Position - mainPart.Position).Magnitude > reach then
			return false, "Walk up to the board"
		end
		return true, nil
	end
end

local lastPress: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player)
	lastPress[player] = nil
end)

local remote = Instance.new("RemoteFunction")
remote.Name = "CustomerUpgradeAction"
remote.Archivable = false
remote.OnServerInvoke = function(player: Player, id: any): (boolean, string)
	if type(id) ~= "string" or not IDS[id] then
		return false, "Unknown upgrade"
	end
	local now = os.clock()
	if lastPress[player] and now - lastPress[player] < PRESS_GAP then
		return false, "Slow down a little"
	end
	lastPress[player] = now
	local ran, ok, message = pcall(Economy.upgradeAction, player, id, nearBoard(player))
	if not ran then
		warn("[CustomerBoard] " .. id .. " failed: " .. tostring(ok))
		ok, message = false, "Couldn't do that right now"
	end
	Economy.notify(player, message, if ok then "success" else "warn")
	return ok == true, message
end
remote.Parent = root
