-- Per-plot customer queue. Customers spawn on a timer, wait at a CustomerSpots
-- part with limited patience, and are served one food portion at a time by
-- the owner standing on CounterPad (see Stations.luau). An impatient customer
-- leaves without paying for what they didn't get; a fully served customer
-- pays a small completion bonus. Coins accumulate in plot.cash until the
-- owner collects them at CashPad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.FishTycoonShared
local Config = require(Shared.Config)
local GameRules = require(Shared.GameRules)

local Billboard = require(script.Parent.Billboard)
local Plots = require(script.Parent.Plots)
local Notifier = require(script.Parent.Notifier)

local Customers = {}

local rng = Random.new()

local COLORS = {
	Color3.fromRGB(235, 120, 120),
	Color3.fromRGB(120, 180, 235),
	Color3.fromRGB(230, 200, 110),
	Color3.fromRGB(150, 220, 150),
}

local function spawnDelay(): number
	return rng:NextNumber(Config.Customers.SpawnIntervalMin, Config.Customers.SpawnIntervalMax)
end

local function makeFigure(spot: BasePart): Model
	local model = Instance.new("Model")
	model.Name = "Customer"
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 3, 1)
	torso.Anchored = true
	torso.CanCollide = false
	torso.CanQuery = false
	torso.CastShadow = false
	torso.Material = Enum.Material.SmoothPlastic
	torso.Color = COLORS[rng:NextInteger(1, #COLORS)]
	torso.CFrame = spot.CFrame * CFrame.new(0, 2, 0)
	torso.Parent = model
	model.PrimaryPart = torso
	model.Parent = spot
	return model
end

function Customers.initPlot(plot)
	plot.customers = {
		queue = {},
		spawnTimer = spawnDelay(),
	}
end

local function removeCustomer(plot, index: number)
	local customer = table.remove(plot.customers.queue, index)
	if customer and customer.figure then
		customer.figure:Destroy()
	end
	-- Free spots shift down; refresh labels for everyone still waiting.
	Customers.refreshLabels(plot)
end

function Customers.refreshLabels(plot)
	for i, customer in ipairs(plot.customers.queue) do
		local remaining = customer.size - customer.delivered
		local patiencePct = math.clamp(customer.patience / Config.Customers.PatienceSeconds, 0, 1)
		customer.label.Text = string.format("Wants %d food  (%d%% patience)", remaining, math.floor(patiencePct * 100))
		local spot = plot.customerSpots[i]
		if customer.figure and spot then
			customer.figure:PivotTo(spot.CFrame * CFrame.new(0, 2, 0))
		end
	end
end

function Customers.step(plot, dt: number)
	local state = plot.customers
	local spots = plot.customerSpots

	-- Spawn new customers when there is room and a free spot.
	state.spawnTimer -= dt
	if state.spawnTimer <= 0 then
		state.spawnTimer = spawnDelay()
		if #state.queue < math.min(Config.Customers.MaxQueue, #spots) then
			local spot = spots[#state.queue + 1]
			local size = rng:NextInteger(Config.Customers.OrderSizeMin, Config.Customers.OrderSizeMax)
			local label = Billboard.create(spot, plot.runtime, 5, 190)
			table.insert(state.queue, {
				size = size,
				delivered = 0,
				patience = Config.Customers.PatienceSeconds,
				label = label,
				figure = makeFigure(spot),
			})
		end
	end

	-- Patience countdown; impatient customers leave without full payment.
	local i = 1
	while i <= #state.queue do
		local customer = state.queue[i]
		customer.patience -= dt
		if customer.patience <= 0 then
			local coins = GameRules.payout(customer.delivered, customer.size, Config.Customers.PricePerPortion, 0)
			plot.cash += coins
			customer.label:Destroy()
			removeCustomer(plot, i)
			Plots.refreshCashLabel(plot)
		else
			i += 1
		end
	end
	Customers.refreshLabels(plot)
end

-- Serves one food portion from the owner's carry stack to the first customer
-- still waiting. Returns true if a portion was delivered.
function Customers.serveOne(plot, state): boolean
	local queue = plot.customers.queue
	local index = GameRules.nextCustomerIndex(queue)
	if not index then
		return false
	end
	if state.carry.food <= 0 then
		Notifier.send(state.player, "info", "No food to serve - collect some from the grinder tray.", "noservefood")
		return false
	end
	local customer = queue[index]
	state.carry.food -= 1
	customer.delivered += 1
	if customer.delivered >= customer.size then
		local coins = GameRules.payout(customer.delivered, customer.size, Config.Customers.PricePerPortion, Config.Customers.CompletionBonus)
		plot.cash += coins
		Notifier.send(state.player, "success", string.format("Order complete! +%d coins waiting at the cash pad.", coins))
		customer.label:Destroy()
		local idx = table.find(queue, customer)
		if idx then
			removeCustomer(plot, idx)
		end
		Plots.refreshCashLabel(plot)
	end
	Customers.refreshLabels(plot)
	return true
end

-- Plot released: clear the queue without paying out (see README reset behaviour).
function Customers.reset(plot)
	for _, customer in ipairs(plot.customers.queue) do
		customer.label:Destroy()
		if customer.figure then
			customer.figure:Destroy()
		end
	end
	table.clear(plot.customers.queue)
	plot.customers.spawnTimer = spawnDelay()
end

return Customers
