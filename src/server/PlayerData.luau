-- In-memory per-player state. Nothing is saved: state is created when a player
-- joins and discarded when they leave (see README "Reset behaviour").
-- commit() mirrors the public parts of the state onto Player attributes (read
-- by the client HUD) and redraws the carried stack.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.FishTycoonShared
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local CarryVisual = require(script.Parent.CarryVisual)

local PlayerData = {}

-- See src/server/Net.luau for the full state machine. ax/az/tx/tz/startAngle/
-- currentAngle are in the plot's FishZone local space; anchorWorld is used for
-- leash-distance checks against the character.
export type NetState = {
	phase: string, -- "Idle" | "Deploying" | "Sweeping" | "Hauling"
	timer: number, -- seconds remaining in Deploying/Hauling
	ax: number,
	az: number,
	anchorWorld: Vector3,
	radius: number, -- locked from the NetRadius stat at cast time
	tx: number,
	tz: number,
	startAngle: number,
	currentAngle: number,
	sweepDir: number, -- 0 = undetermined, else 1 or -1
	startedAngle: boolean,
	lastMove: number,
	netted: { any }, -- fish records currently held in the net; persists across cycles until unloaded
}

export type State = {
	player: Player,
	plot: any, -- Plots.Plot or nil when every plot is taken
	money: number,
	levels: { [string]: number },
	carry: { fish: number, food: number },
	net: NetState,
	pads: { [string]: boolean }, -- which pads the character was standing on last poll
	nextTransfer: number,
	connections: { RBXScriptConnection },
	characterConnections: { RBXScriptConnection },
	leaderMoney: IntValue?,
}

local states: { [Player]: State } = {}
local changedCallbacks: { (State) -> () } = {}

function PlayerData.create(player: Player): State
	local levels = {}
	for id in pairs(Config.Upgrades) do
		levels[id] = 1
	end
	local state: State = {
		player = player,
		plot = nil,
		money = Config.StartingMoney,
		levels = levels,
		carry = { fish = 0, food = 0 },
		net = {
			phase = "Idle",
			timer = 0,
			ax = 0,
			az = 0,
			anchorWorld = Vector3.zero,
			radius = 0,
			tx = 0,
			tz = 0,
			startAngle = 0,
			currentAngle = 0,
			sweepDir = 0,
			startedAngle = false,
			lastMove = 0,
			netted = {},
		},
		pads = {},
		nextTransfer = 0,
		connections = {},
		characterConnections = {},
		leaderMoney = nil,
	}

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Parent = leaderstats
	leaderstats.Parent = player
	state.leaderMoney = money

	states[player] = state
	return state
end

function PlayerData.get(player: Player): State?
	return states[player]
end

function PlayerData.all(): { [Player]: State }
	return states
end

function PlayerData.stat(state: State, statName: string): number
	return Economy.stat(Config, statName, state.levels)
end

function PlayerData.intStat(state: State, statName: string): number
	return Economy.intStat(Config, statName, state.levels)
end

-- Registers a callback run after every commit (used to refresh plot labels).
function PlayerData.onChanged(callback: (State) -> ())
	table.insert(changedCallbacks, callback)
end

-- Publishes state to attributes/leaderstats and redraws the carried stack.
function PlayerData.commit(state: State)
	local player = state.player
	player:SetAttribute("Money", state.money)
	player:SetAttribute("CarryFish", state.carry.fish)
	player:SetAttribute("CarryFood", state.carry.food)
	player:SetAttribute("CarryCapacity", PlayerData.intStat(state, "CarryCapacity"))
	player:SetAttribute("NetRadius", PlayerData.stat(state, "NetRadius"))
	player:SetAttribute("NetCapacity", PlayerData.intStat(state, "NetCapacity"))
	player:SetAttribute("NetPhase", state.net.phase)
	player:SetAttribute("NetCount", #state.net.netted)
	player:SetAttribute("PlotIndex", state.plot and state.plot.index or 0)
	for id, level in pairs(state.levels) do
		player:SetAttribute(id .. "Level", level)
	end
	if state.leaderMoney then
		state.leaderMoney.Value = state.money
	end
	CarryVisual.render(player.Character, state.carry)
	for _, callback in ipairs(changedCallbacks) do
		callback(state)
	end
end

-- The character's root part if the character exists and is alive.
function PlayerData.aliveRoot(state: State): BasePart?
	local character = state.player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

function PlayerData.clearCharacterConnections(state: State)
	disconnectAll(state.characterConnections)
end

function PlayerData.remove(player: Player)
	local state = states[player]
	if not state then
		return
	end
	disconnectAll(state.characterConnections)
	disconnectAll(state.connections)
	states[player] = nil
end

return PlayerData
