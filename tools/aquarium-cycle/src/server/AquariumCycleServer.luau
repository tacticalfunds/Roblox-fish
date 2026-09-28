-- AquariumCycleServer (ModuleScript in ServerScriptService).
--
-- Server side of the dock rod -> aquarium -> river cycle for the live shared
-- scene (one FishTank, five shared FishingRod1 rods, one BigButton). The
-- patched RodFishingSystem is the only caller; this module never starts on
-- its own. All game rules live in the pure ReplicatedStorage.AquariumCycle
-- modules; this file only binds them to the scene.
--
-- API used by RodFishingSystem:
--   start(rodKeys)          -> (ok, reason)  reason "disabled" when switched off
--   active()                -> bool
--   reserve(rods, player)   -> rods allowed to cast (a tank spot is reserved for each)
--   hasFreeSpot(player)     -> bool (tells the player when the tank is full)
--   hook(rodKey, fishName, meta?) -> bool  (meta: e.g. { Variant = "Gold", OwnerId = 123 }, carried unchanged)
--   land(rodKey)            -> bool
--   abort(rodKey)           -- frees the rod's spot; safe to call any time
--   entryPoint()            -> Vector3 above the tank water
--   toTankSeconds, toTankHeight
--
-- Everything this module creates or changes at runtime is undone by stop(),
-- which runs when the "Enabled" attribute on ReplicatedStorage.AquariumCycle
-- is switched off during play. Nothing it does at runtime is saved to the
-- place. It never grants currency.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local FOLDER_NAME = "AquariumCycle"

local M = {}
M.toTankSeconds = 1.3
M.toTankHeight = 12

local startedOnce = false
local running = false

local root: Folder
local Config, Upgrades, SharedTank, RiverRelease, Messages
local scene
local tank

local water: BasePart
local river: Instance
local riverBounds
local swimTemplates: Instance
local economy = nil -- { tryCharge = function(player, amount, reason) -> bool } or nil

local runtimeFolder: Folder
local tankFishFolder: Folder
local notice: RemoteEvent
local countUi = nil -- { amount = TextLabel, color = Color3 }
local prompts = {} -- id -> ProximityPrompt
local markers = {} -- fish id -> Configuration

local owned = {} -- runtime instances to destroy on stop()
local restore = {} -- functions undoing runtime changes to existing objects
local connections = {}
local lastAction = {}
local seedCounter = 0
local rng = Random.new()

local function clock(): number
	return os.clock()
end

local function own<T>(inst: T): T
	table.insert(owned, inst)
	return inst
end

local function notify(player: Player?, text: string, kind: string?)
	if player and notice and player.Parent then
		notice:FireClient(player, text, kind or "info")
	end
end

------------------------------------------------------------ bindings

local function binding(bindings: Instance, name: string, required: boolean): (Instance?, string?)
	local value = bindings:FindFirstChild(name)
	if not value or not value:IsA("ObjectValue") then
		return nil, if required then "missing binding " .. name else nil
	end
	if not value.Value then
		return nil, if required then "binding " .. name .. " is empty" else nil
	end
	return value.Value, nil
end

-- The placeholder count UI: Workspace.Model.Road.ProximityPrompt.BillboardGui
-- with TextLabel "Fish available" and TextLabel Amount. Bound only if that
-- exact structure and text are present; otherwise left untouched.
local function bindCountUi(prompt: Instance?)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return nil
	end
	local gui = prompt:FindFirstChild("BillboardGui")
	local title = gui and gui:FindFirstChild("TextLabel")
	local amount = gui and gui:FindFirstChild("Amount")
	if
		not (
			gui
			and gui:IsA("BillboardGui")
			and title
			and title:IsA("TextLabel")
			and amount
			and amount:IsA("TextLabel")
		)
	then
		warn("[AquariumCycle] count UI structure not as expected; leaving it untouched")
		return nil
	end
	if title.Text ~= "Fish available" then
		warn("[AquariumCycle] count UI title is '" .. title.Text .. "', not 'Fish available'; leaving it untouched")
		return nil
	end
	local original = {
		title = title.Text,
		amount = amount.Text,
		color = amount.TextColor3,
		enabled = prompt.Enabled,
	}
	table.insert(restore, function()
		title.Text = original.title
		amount.Text = original.amount
		amount.TextColor3 = original.color
		prompt.Enabled = original.enabled
	end)
	title.Text = scene.TitleText
	if scene.HidePlaceholderPrompt then
		-- The "E / NEW CAR / PLACE CAR" prompt is a placeholder; hide it while
		-- the aquarium runs so it can't be confused with Release Fish.
		prompt.Enabled = false
	end
	return { amount = amount, color = original.color }
end

-- Own billboard when the placeholder UI isn't bound.
local function makeCountUi()
	local gui = own(Instance.new("BillboardGui"))
	gui.Name = "AquariumCount"
	gui.Size = UDim2.fromOffset(160, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, water.Size.Y / 2 + 3, 0)
	gui.MaxDistance = 120
	gui.Adornee = water
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.45)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.3
	title.Text = scene.TitleText
	title.Parent = gui
	local amount = title:Clone()
	amount.Name = "Amount"
	amount.Position = UDim2.fromScale(0, 0.45)
	amount.Size = UDim2.fromScale(1, 0.55)
	amount.Parent = gui
	gui.Parent = runtimeFolder
	return { amount = amount, color = amount.TextColor3 }
end

------------------------------------------------------------ display

local function upgradeText(id: string, level: number): (string, string)
	local def = Config.Upgrades[id]
	local current = Upgrades.value(Config, id, level)
	local cost = Upgrades.nextCost(Config, id, level)
	if cost == nil then
		return "Maxed", string.format("%s %d", def.DisplayName, current)
	end
	local nextValue = Upgrades.value(Config, id, level + 1)
	local price = if economy then tostring(cost) else "unavailable"
	return string.format("Upgrade %s", def.DisplayName), string.format("%d → %d (%s)", current, nextValue, price)
end

local function refresh()
	if not tank then
		return
	end
	local info = tank:info()
	if not info then
		return
	end
	if countUi then
		countUi.amount.Text = string.format("%d/%d", info.count, info.capacity)
		countUi.amount.TextColor3 = if info.full then Color3.fromRGB(table.unpack(scene.FullColor)) else countUi.color
	end
	for id, prompt in pairs(prompts) do
		if id ~= "Release" then
			prompt.ActionText, prompt.ObjectText = upgradeText(id, info.levels[id])
		end
	end
	root:SetAttribute("TankCount", info.count)
	root:SetAttribute("TankCapacity", info.capacity)
	root:SetAttribute("TankFull", info.full)
end

------------------------------------------------------------ fish

-- Optional ReplicatedStorage.FishVariantVisuals (installed by the variants
-- feature); without it, fish are released without extra effects.
local function variantVisuals()
	local mod = ReplicatedStorage:FindFirstChild("FishVariantVisuals")
	if not (mod and mod:IsA("ModuleScript")) then
		return nil
	end
	local ok, v = pcall(require, mod)
	return if ok and type(v) == "table" then v else nil
end

local function setMeta(inst: Instance, meta)
	if type(meta) ~= "table" then
		return
	end
	for _, key in ipairs(scene.PassthroughAttributes or {}) do
		if meta[key] ~= nil then
			inst:SetAttribute(key, meta[key])
		end
	end
end

local function addMarker(id: number, name: string, meta)
	local marker = Instance.new("Configuration")
	marker.Name = "Fish" .. id
	marker:SetAttribute("FishId", id)
	marker:SetAttribute("FishName", name)
	marker:SetAttribute("Seed", id)
	marker:SetAttribute("EnterT", workspace:GetServerTimeNow())
	marker:SetAttribute("State", "Tank")
	setMeta(marker, meta)
	marker.Parent = tankFishFolder
	markers[id] = marker
end

local function removeMarker(id: number)
	local marker = markers[id]
	markers[id] = nil
	if marker then
		marker:Destroy()
	end
end

-- Puts a fish back into Workspace.SwimmingFish exactly like FishSpawner does,
-- so FishSwimClient animates it and the net can catch it. Attributes are set
-- before parenting because FishSwimClient reads them on ChildAdded.
local function spawnIntoRiver(name: string?, meta)
	local template = name and swimTemplates:FindFirstChild(name)
	if not template then
		warn("[AquariumCycle] no SwimTemplate for released fish " .. tostring(name))
		return
	end
	local model = template:Clone()
	seedCounter += 1
	local s = RiverRelease.attributes(
		riverBounds,
		model:GetAttribute("SwimLen"),
		workspace:GetServerTimeNow(),
		scene.RiverSeedBase + seedCounter,
		rng:NextNumber(),
		rng:NextNumber(),
		scene.RiverSpeed
	)
	model:SetAttribute("SpawnT", s.SpawnT)
	model:SetAttribute("StartZ", s.StartZ)
	model:SetAttribute("Speed", s.Speed)
	model:SetAttribute("LaneX", s.LaneX)
	model:SetAttribute("Seed", s.Seed)
	model:SetAttribute("FromAquarium", true)
	setMeta(model, meta) -- e.g. Variant: kept from the original catch, never rerolled
	local visuals = variantVisuals()
	if visuals and model:GetAttribute("Variant") then
		pcall(visuals.applyToFish, model, model:GetAttribute("Variant"))
	end
	local at = Vector3.new(s.LaneX, s.y, s.StartZ)
	model:PivotTo(CFrame.lookAt(at, at + Vector3.new(0, 0, 1)))
	model.Parent = river
	task.delay(s.lifetime, function()
		-- v1.2: a fish the harpoon has already hit is the harpoon's to remove
		if model.Parent and not model:GetAttribute("CaughtT") and not model:GetAttribute("HarpoonT") then
			model:Destroy()
		end
	end)
end

local function handOff(list)
	for _, fish in ipairs(list) do
		removeMarker(fish.id)
		spawnIntoRiver(fish.name, fish.meta)
	end
end

------------------------------------------------------------ player actions

local function promptPosition(prompt: ProximityPrompt): Vector3
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return water.Position
end

-- Server-side check of the prompt trigger: live character, near the prompt,
-- and not spamming.
local function validPlayer(player: Player, prompt: ProximityPrompt): boolean
	local now = clock()
	if lastAction[player] and now - lastAction[player] < scene.PlayerActionCooldown then
		return false
	end
	lastAction[player] = now
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (hrp and hrp:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return false
	end
	if (hrp.Position - promptPosition(prompt)).Magnitude > prompt.MaxActivationDistance + scene.PromptSlack then
		notify(player, Messages.forReason("tooFar"))
		return false
	end
	return true
end

local function onRelease(player: Player)
	if not running or not validPlayer(player, prompts.Release) then
		return
	end
	local ok, reason, fish = tank:release(clock())
	if not ok then
		notify(player, Messages.forReason(reason))
		return
	end
	local releaseT = workspace:GetServerTimeNow()
	for _, f in ipairs(fish) do
		local marker = markers[f.id]
		if marker then
			marker:SetAttribute("State", "Releasing")
			marker:SetAttribute("ReleaseT", releaseT)
			marker:SetAttribute("ReleaseDur", Config.ReleaseSwimSeconds)
		end
	end
	-- No payout: releasing never grants currency.
	notify(player, Messages.released(#fish), "success")
	refresh()
end

local function onUpgrade(player: Player, upgradeId: string)
	if not running or not validPlayer(player, prompts[upgradeId]) then
		return
	end
	-- The shared tank has no owner to bill, so the player who triggers the
	-- prompt pays through the economy binding (when one exists).
	local adapters = {}
	if economy then
		adapters.Economy = {
			tryCharge = function(_owner, amount, why)
				return economy.tryCharge(player, amount, why) == true
			end,
		}
	end
	local ok, reason, level = tank:buyUpgrade(adapters, upgradeId)
	if ok and level then
		local def = Config.Upgrades[upgradeId]
		notify(player, Messages.upgraded(def.DisplayName, Upgrades.value(Config, upgradeId, level)), "success")
	else
		notify(player, Messages.forReason(reason))
	end
	refresh()
end

local function makePrompt(parent: Instance, id: string, key: Enum.KeyCode, pad: Enum.KeyCode, offsetY: number)
	local prompt = own(Instance.new("ProximityPrompt"))
	prompt.Name = "Aquarium" .. id
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = pad
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = scene.PromptDistance
	prompt.UIOffset = Vector2.new(0, offsetY)
	prompt.ObjectText = "Aquarium"
	prompt.ActionText = if id == "Release" then "Release Fish" else ""
	prompt.Parent = parent
	prompts[id] = prompt
	table.insert(
		connections,
		prompt.Triggered:Connect(function(player)
			if id == "Release" then
				onRelease(player)
			else
				onUpgrade(player, id)
			end
		end)
	)
	return prompt
end

------------------------------------------------------------ lifecycle

local function loadEconomy()
	local mod = ServerScriptService:FindFirstChild("AquariumEconomy")
	if not (mod and mod:IsA("ModuleScript")) then
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[AquariumCycle] AquariumEconomy failed to load; upgrades unavailable: " .. tostring(result))
		return nil
	end
	if type(result) == "table" and type(result.tryCharge) == "function" then
		return result
	end
	return nil
end

function M.start(rodKeys: { any }): (boolean, string?)
	if startedOnce then
		return running, if running then nil else "already stopped"
	end
	startedOnce = true

	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not (folder and folder:IsA("Folder")) then
		return false, "ReplicatedStorage." .. FOLDER_NAME .. " not installed"
	end
	root = folder
	Config = require(root:WaitForChild("Config"))
	if not (Config.Enabled or root:GetAttribute("Enabled") == true) then
		return false, "disabled"
	end
	Upgrades = require(root:WaitForChild("Upgrades"))
	SharedTank = require(root:WaitForChild("SharedTank"))
	RiverRelease = require(root:WaitForChild("RiverRelease"))
	Messages = require(root:WaitForChild("Messages"))
	scene = Config.Scene
	M.toTankSeconds = scene.ToTankSeconds
	M.toTankHeight = scene.ToTankArcHeight

	-- Explicit bindings only (ObjectValues written by the installer).
	local bindings = root:FindFirstChild("Bindings")
	if not bindings then
		return false, "missing Bindings folder"
	end
	local problem
	local w, riv, templates
	w, problem = binding(bindings, "TankWater", true)
	if problem then
		return false, problem
	end
	riv, problem = binding(bindings, "River", true)
	if problem then
		return false, problem
	end
	templates, problem = binding(bindings, "SwimTemplates", true)
	if problem then
		return false, problem
	end
	if not (w and w:IsA("BasePart")) then
		return false, "TankWater binding is not a BasePart"
	end
	water = w
	river = riv :: Instance
	swimTemplates = templates :: Instance
	local b, why = RiverRelease.readBounds(function(name)
		return river:GetAttribute(name)
	end)
	if not b then
		return false, why
	end
	riverBounds = b

	tank = SharedTank.new(Config)
	if tank:registerRods(rodKeys) ~= #rodKeys or #rodKeys == 0 then
		return false, "could not register rods"
	end
	economy = loadEconomy()

	runtimeFolder = own(Instance.new("Folder"))
	runtimeFolder.Name = scene.RuntimeFolderName
	tankFishFolder = Instance.new("Folder")
	tankFishFolder.Name = "TankFish"
	tankFishFolder.Parent = runtimeFolder
	runtimeFolder.Parent = workspace

	notice = own(Instance.new("RemoteEvent"))
	notice.Name = "Notice"
	notice.Parent = root

	local countPrompt = binding(bindings, "CountPrompt", false)
	countUi = bindCountUi(countPrompt)
	if not countUi then
		countUi = makeCountUi()
	end

	-- Prompts sit where the placeholder prompt is (the spot players already
	-- walk to); otherwise at the bottom of the tank water.
	local promptParent: Instance
	local placeholderParent = countPrompt and countPrompt.Parent
	if placeholderParent and (placeholderParent:IsA("BasePart") or placeholderParent:IsA("Attachment")) then
		promptParent = placeholderParent
	else
		local att = own(Instance.new("Attachment"))
		att.Name = "AquariumPrompts"
		att.Position = Vector3.new(0, -water.Size.Y / 2 + 1, 0)
		att.Parent = water
		promptParent = att
	end
	makePrompt(promptParent, "Release", Enum.KeyCode.E, Enum.KeyCode.ButtonX, 0)
	makePrompt(promptParent, "Capacity", Enum.KeyCode.F, Enum.KeyCode.ButtonY, 80)
	makePrompt(promptParent, "ReleaseRate", Enum.KeyCode.G, Enum.KeyCode.ButtonB, 160)

	local acc = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < scene.StepInterval then
				return
			end
			acc = 0
			local list = tank:step(clock())
			if #list > 0 then
				handOff(list)
				refresh()
			end
		end)
	)
	table.insert(
		connections,
		root:GetAttributeChangedSignal("Enabled"):Connect(function()
			if not Config.Enabled and root:GetAttribute("Enabled") ~= true then
				M.stop()
			end
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player)
			lastAction[player] = nil
		end)
	)

	running = true
	root:SetAttribute("Running", true)
	refresh()
	if not economy then
		print("[AquariumCycle] running; upgrades unavailable (no currency binding in AquariumEconomy)")
	else
		print("[AquariumCycle] running")
	end
	return true, nil
end

function M.active(): boolean
	return running
end

function M.reserve(rods: { any }, player: Player?): { any }
	if not running then
		return rods
	end
	local keys, byKey = {}, {}
	for _, rod in ipairs(rods) do
		table.insert(keys, rod.key)
		byKey[rod.key] = rod
	end
	local reserved, reason = tank:reserve(keys, clock())
	local out = {}
	for _, key in ipairs(reserved) do
		table.insert(out, byKey[key])
	end
	if #out == 0 then
		notify(player, Messages.forReason(reason), "warn")
	end
	refresh()
	return out
end

function M.hasFreeSpot(player: Player?): boolean
	if not running then
		return true
	end
	local info = tank:info()
	if info and info.free > 0 then
		return true
	end
	notify(player, Messages.forReason("tankFull"), "warn")
	return false
end

function M.hook(rodKey: any, fishName: string, meta: any?): boolean
	if not running then
		return false
	end
	local ok, reason = tank:hook(rodKey, fishName, clock(), meta)
	if not ok and reason ~= "notWaiting" then
		warn("[AquariumCycle] hook refused for rod " .. tostring(rodKey) .. ": " .. tostring(reason))
	end
	return ok
end

function M.land(rodKey: any): boolean
	if not running then
		return false
	end
	local ok, reason, id, name, meta = tank:land(rodKey, clock())
	if not ok or not id then
		warn("[AquariumCycle] land refused for rod " .. tostring(rodKey) .. ": " .. tostring(reason))
		return false
	end
	addMarker(id, name or "", meta)
	refresh()
	return true
end

function M.abort(rodKey: any)
	if tank and running and tank:abort(rodKey) then
		refresh()
	end
end

function M.entryPoint(): Vector3
	return water.CFrame:PointToWorldSpace(Vector3.new(0, water.Size.Y / 2 + 1, 0))
end

-- Switch-off during play: every fish in the tank (or mid-release) is put back
-- into the river, rods in flight fall back to the grinder, and every runtime
-- change is undone.
function M.stop()
	if not running then
		return
	end
	running = false
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	handOff(tank:shutdown())
	for id in pairs(markers) do
		removeMarker(id)
	end
	for i = #restore, 1, -1 do
		pcall(restore[i])
	end
	table.clear(restore)
	for i = #owned, 1, -1 do
		local inst = owned[i]
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(owned)
	table.clear(prompts)
	countUi = nil
	root:SetAttribute("Running", false)
	root:SetAttribute("TankCount", nil)
	root:SetAttribute("TankCapacity", nil)
	root:SetAttribute("TankFull", nil)
	print("[AquariumCycle] stopped; catches go to the grinder")
end

return M
