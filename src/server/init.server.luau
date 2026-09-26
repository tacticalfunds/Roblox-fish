-- Fish Tycoon prototype - server entry point.
--
-- Requires Workspace.<Config.SceneFolderName> to already exist (built by the
-- opt-in tools/BuildPrototypeScene.lua command-bar script - never run
-- automatically). If it's missing, the game stays inert and says so in the
-- output rather than erroring, so an empty Studio place doesn't spam errors.
--
-- Reset behaviour: nothing is saved. All fish, catches, grinder contents,
-- customer queues, cash, upgrade levels and carried stock are held only in
-- this script's memory and PlayerData; a server restart or place reset starts
-- everyone over from Config.StartingMoney and level 1 upgrades. A player who
-- leaves and rejoins gets a fresh plot assignment and fresh state (their old
-- plot is released and reset for the next owner).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.FishTycoonShared
local Config = require(Shared.Config)
local Scene = require(Shared.Scene)
local Remotes = require(Shared.Remotes)

local Plots = require(script.Plots)
local PlayerData = require(script.PlayerData)
local Fish = require(script.Fish)
local Net = require(script.Net)
local Grinder = require(script.Grinder)
local Customers = require(script.Customers)
local Stations = require(script.Stations)
local Notifier = require(script.Notifier)

Remotes.createAll()

local sceneReady = Plots.load()
if not sceneReady then
	warn(
		"[FishTycoon] No prototype scene found. This is expected in an empty/unmodified place file. "
			.. "Run tools/BuildPrototypeScene.lua from the Studio command bar to create one, then re-run this script."
	)
	return
end

for _, plot in ipairs(Plots.all()) do
	Fish.initPlot(plot)
	Net.initPlot(plot)
	Grinder.initPlot(plot)
	Customers.initPlot(plot)
end

local function releasePlayerPlot(state)
	if not state.plot then
		return
	end
	Net.cancel(state) -- release any netted fish back to the water; excess is not kept across owners
	Grinder.reset(state.plot)
	Customers.reset(state.plot)
	state.plot.cash = 0
	Plots.refreshCashLabel(state.plot)
	Plots.release(state.plot)
	state.plot = nil
end

local function attachCharacter(state: PlayerData.State, character: Model)
	PlayerData.clearCharacterConnections(state)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		table.insert(
			state.characterConnections,
			humanoid.Died:Connect(function()
				Net.cancel(state)
			end)
		)
	end
	if state.plot and Config.TeleportToPlotOnSpawn then
		local spawnPart = state.plot.parts[Scene.Parts.SpawnPoint]
		local root = character:WaitForChild("HumanoidRootPart", 5)
		if root and root:IsA("BasePart") and spawnPart then
			character:PivotTo(spawnPart.CFrame + Vector3.new(0, 3, 0))
		end
	end
	PlayerData.commit(state)
end

local function onPlayerAdded(player: Player)
	local state = PlayerData.create(player)
	state.plot = Plots.assign(player)
	if not state.plot then
		Notifier.send(player, "warn", "All docks are taken right now - try again later.")
	end
	PlayerData.commit(state)

	table.insert(
		state.connections,
		player.CharacterAdded:Connect(function(character)
			attachCharacter(state, character)
		end)
	)
	if player.Character then
		attachCharacter(state, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local state = PlayerData.get(player)
	if not state then
		return
	end
	releasePlayerPlot(state)
	Net.forget(player)
	Notifier.forget(player)
	PlayerData.remove(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Net.connectRemotes()

-- Fixed-rate simulation loop, decoupled from render framerate.
local fishAccumulator = 0
local fishStep = 1 / Config.Fish.TickRate

RunService.Heartbeat:Connect(function(dt)
	Net.step(dt)
	Stations.step(dt)
	for _, plot in ipairs(Plots.all()) do
		if plot.owner then
			Grinder.step(plot, dt)
			Customers.step(plot, dt)
		end
	end

	fishAccumulator += dt
	while fishAccumulator >= fishStep do
		fishAccumulator -= fishStep
		for _, plot in ipairs(Plots.all()) do
			Fish.step(plot, fishStep)
		end
	end
end)

print(string.format("[FishTycoon] Ready with %d plot(s).", #Plots.all()))
