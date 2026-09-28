-- EconomyService (ModuleScript in ServerScriptService; its children are the
-- pure core modules Config, Pricing, Ledger, MoneyStore, Offers, PieceTags).
--
-- The ONE money service. Binds the pure core to Roblox:
--   * loads/saves each player's Money (DataStore, session-locked) and shows
--     it as leaderstats.Money once - and only once - it has loaded
--   * the meat ledger: GrinderProcessor issues pieces, BotSystem copies
--     their identity, CustomerSystem / TruckSystem settle them (one payment
--     per piece, to its owner), full pipelines hold pieces as data
--   * charging (aquarium upgrades, rod shop, rod-fish offers)
--
-- Every patched live script loads this with FindFirstChild + pcall(require)
-- and calls start(); if it is missing or fails, those scripts behave
-- exactly as before. ServerScriptService.EconomyBoot also calls start() so
-- money loads even before anything is sold.
--
-- It never creates Cash or a Money attribute, never grants anything except
-- the one-time starting grant for a player with no saved record, and never
-- saves a player whose money failed to load.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Config)
local Pricing = require(script.Pricing)
local Ledger = require(script.Ledger)
local MoneyStore = require(script.MoneyStore)
local PieceTags = require(script.PieceTags)
local Sales = require(script.Sales)
local Offers = require(script.Offers)

local M = {}
M.Config = Config
M.Pricing = Pricing

local started = false
local starting = false -- start() yields (Studio DataStore probe); other callers wait
local startOk = false

local money: MoneyStore.MoneyStore
local ledger: Ledger.Ledger
local root: Folder -- ReplicatedStorage.Economy (installed)
local notice: RemoteEvent
local storeKind = "DataStore"
local offers: Offers.Offers
local offersFolder: Folder -- ReplicatedStorage.Economy.Offers: one Configuration per open offer
local offerAction: RemoteFunction
local offerRecs = {} -- offer id -> { fish, deps, cfg, gui }
local lastOfferAction: { [Player]: number } = {}
local lastLockWarn = {}

------------------------------------------------------------ helpers

local function log(msg: string)
	print("[Economy] " .. msg)
end

local function userIdOf(who: any): number?
	if typeof(who) == "Instance" and who:IsA("Player") then
		return who.UserId
	end
	return Ledger.validOwner(who)
end

function M.notify(player: Player?, text: string, kind: string?)
	if player and notice and player.Parent == Players then
		notice:FireClient(player, text, kind or "info")
	end
end

------------------------------------------------------------ stores

local function dataStoreStore(): MoneyStore.Store
	local ds = DataStoreService:GetDataStore(Config.DataStoreName)
	return {
		update = function(key: string, transform: (any) -> any): any
			return ds:UpdateAsync(key, transform)
		end,
	}
end

-- Studio-only, non-persistent. Never used in a live server.
local function memoryStore(): MoneyStore.Store
	local data = {}
	return {
		update = function(key: string, transform: (any) -> any): any
			local result = transform(data[key])
			if result ~= nil then
				data[key] = result
			end
			return data[key]
		end,
	}
end

local function pickStore(): MoneyStore.Store
	local ok, result = pcall(dataStoreStore)
	local err: any = if ok then nil else result
	if ok and RunService:IsStudio() then
		-- Studio: is DataStore access actually on for this place?
		local probed, probeErr = pcall(function()
			DataStoreService:GetDataStore(Config.DataStoreName):GetAsync("__probe")
		end)
		if not probed then
			ok, err = false, probeErr
		end
	end
	if ok then
		return result
	end
	if RunService:IsStudio() and Config.StudioMemoryStoreFallback then
		storeKind = "Memory"
		warn(
			"[Economy] DataStore unavailable in Studio ("
				.. tostring(err)
				.. "); using a TEMPORARY in-memory store - Money will not persist"
		)
		return memoryStore()
	end
	error("DataStore unavailable: " .. tostring(err))
end

------------------------------------------------------------ leaderstats

local moneyValues: { [Player]: IntValue } = {}

local function sync(player: Player)
	local v = moneyValues[player]
	local bal = money:balance(player.UserId)
	if v and bal then
		v.Value = bal
	end
end

local function showMoney(player: Player)
	if moneyValues[player] or not player.Parent then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local v = Instance.new("IntValue")
	v.Name = Config.CurrencyName
	v.Value = money:balance(player.UserId) or 0
	-- Display only: the balance lives in this service. Revert outside writes.
	v.Changed:Connect(function()
		local bal = money:balance(player.UserId)
		if bal and v.Value ~= bal then
			warn("[Economy] leaderstats.Money was changed outside EconomyService; reverted")
			v.Value = bal
		end
	end)
	moneyValues[player] = v
	v.Parent = stats
end

------------------------------------------------------------ load / save

local function loadPlayer(player: Player)
	local userId = player.UserId
	money:begin(userId)
	local attempt = 0
	while true do
		attempt += 1
		local result, detail = money:attemptLoad(userId)
		if result == "ready" then
			if not player.Parent then
				money:save(userId, true)
				money:forget(userId)
				return
			end
			showMoney(player)
			if detail == "new" then
				M.notify(player, string.format("Welcome! %d Money to start", Config.StartingGrant), "success")
			end
			log(string.format("%s money loaded (%s store)", player.Name, storeKind))
			return
		elseif result == "corrupt" then
			warn("[Economy] " .. player.Name .. "'s saved money is not valid; left untouched, money unavailable")
			M.notify(player, "Your money couldn't be loaded. Buying is off this session.", "warn")
			return
		elseif result == "notLoading" then
			return
		end
		-- "locked" or "error": retry, then keep retrying slowly in the background
		if attempt >= Config.LoadAttempts then
			money:markFailed(userId, result)
			warn(string.format("[Economy] %s money not loaded (%s): %s", player.Name, result, tostring(detail)))
			M.notify(player, "Money is still loading. Buying is paused; retrying...", "warn")
			while player.Parent do
				task.wait(Config.LoadRetryEverySeconds)
				if not player.Parent or not money:reopen(userId) then
					return
				end
				local r2, d2 = money:attemptLoad(userId)
				if r2 == "ready" then
					if not player.Parent then
						money:save(userId, true)
						money:forget(userId)
						return
					end
					showMoney(player)
					if d2 == "new" then
						M.notify(player, string.format("Welcome! %d Money to start", Config.StartingGrant), "success")
					end
					M.notify(player, "Money loaded", "success")
					return
				elseif r2 == "corrupt" or r2 == "notLoading" then
					return
				end
				money:markFailed(userId, r2)
			end
			return
		end
		task.wait(Config.LoadRetryDelays[attempt] or 4)
	end
end

local function saveWithRetry(userId: number, release: boolean): boolean
	for i = 1, 3 do
		while money:isSaving(userId) do
			task.wait(0.1)
		end
		local ok, why = money:save(userId, release)
		if ok then
			return true
		end
		if why == "notLoaded" or why == "lockLost" then
			if why == "lockLost" and not lastLockWarn[userId] then
				lastLockWarn[userId] = true
				warn("[Economy] session lock lost for " .. userId .. "; not saving over the other server")
			end
			return false
		end
		warn(string.format("[Economy] save %d failed (try %d): %s", userId, i, tostring(why)))
		task.wait(i)
	end
	return false
end

local function unloadPlayer(player: Player)
	local userId = player.UserId
	moneyValues[player] = nil
	local state = money:state(userId)
	if state == "Ready" then
		if not saveWithRetry(userId, true) then
			warn("[Economy] final save for " .. player.Name .. " did not complete")
		end
	end
	money:forget(userId)
	lastLockWarn[userId] = nil
end

------------------------------------------------------------ start

function M.start(): boolean
	if started then
		while starting do
			task.wait()
		end
		return startOk
	end
	started = true
	starting = true
	local ok, result = pcall(M._start)
	starting = false
	if not ok then
		warn("[Economy] failed to start: " .. tostring(result))
		startOk = false
		return false
	end
	return startOk
end

function M._start(): boolean
	local folder = ReplicatedStorage:FindFirstChild("Economy")
	if not (folder and folder:IsA("Folder")) then
		warn("[Economy] ReplicatedStorage.Economy not installed; economy off")
		return false
	end
	root = folder
	local okConfig, why = Config.check()
	if not okConfig then
		warn("[Economy] config check failed: " .. tostring(why) .. "; economy off")
		return false
	end
	local n = root:FindFirstChild("Notice")
	if not (n and n:IsA("RemoteEvent")) then
		n = Instance.new("RemoteEvent")
		n.Name = "Notice"
		n.Parent = root
	end
	notice = n :: RemoteEvent
	local of = root:FindFirstChild("Offers")
	if not (of and of:IsA("Folder")) then
		of = Instance.new("Folder")
		of.Name = "Offers"
		of.Parent = root
	end
	offersFolder = of :: Folder
	for _, old in ipairs(offersFolder:GetChildren()) do
		old:Destroy() -- nothing from a previous run survives
	end
	local oa = root:FindFirstChild("OfferAction")
	if not (oa and oa:IsA("RemoteFunction")) then
		oa = Instance.new("RemoteFunction")
		oa.Name = "OfferAction"
		oa.Parent = root
	end
	offerAction = oa :: RemoteFunction
	offers = Offers.new(Config.Offer.TimeoutSeconds)
	offerAction.OnServerInvoke = function(player, offerId, action)
		return M._offerAction(player, offerId, action)
	end
	root:GetAttributeChangedSignal(Config.RodOffersAttribute):Connect(function()
		if root:GetAttribute(Config.RodOffersAttribute) == false then
			offers:cancelAll("disabled") -- nothing charged, nothing delivered
		end
	end)
	table.insert(M._onLeave, function(player: Player)
		offers:cancelForUser(player.UserId, "left") -- nothing charged, nothing delivered
		lastOfferAction[player] = nil
	end)

	money = MoneyStore.new(pickStore(), game.JobId, os.time)
	ledger = Ledger.new("P")

	Players.PlayerAdded:Connect(function(p)
		task.spawn(loadPlayer, p)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		for _, fn in ipairs(M._onLeave) do
			pcall(fn, p)
		end
		unloadPlayer(p)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for _, userId in ipairs(money:users()) do
				if money:state(userId) == "Ready" then
					task.spawn(saveWithRetry, userId, false)
				end
			end
		end
	end)
	game:BindToClose(function()
		local waiting = 0
		for _, userId in ipairs(money:users()) do
			if money:state(userId) == "Ready" then
				waiting += 1
				task.spawn(function()
					saveWithRetry(userId, true)
					waiting -= 1
				end)
			end
		end
		local t0 = os.clock()
		while waiting > 0 and os.clock() - t0 < 25 do
			task.wait(0.1)
		end
	end)

	startOk = true
	root:SetAttribute("Running", true)
	root:SetAttribute("Store", storeKind)
	log("running (" .. storeKind .. " store)")
	return true
end

function M.running(): boolean
	return startOk
end

M._onLeave = {} :: { (Player) -> () }
function M.onPlayerLeaving(fn: (Player) -> ())
	table.insert(M._onLeave, fn)
end

------------------------------------------------------------ money API

function M.balance(player: Player): number?
	if not startOk then
		return nil
	end
	return money:balance(player.UserId)
end

-- Takes exactly `amount` from the player or nothing. Synchronous (no
-- yields). Returns (ok, reason) with reason "funds" | "notLoaded" | ...
function M.tryDebit(player: Player, amount: number, reason: string): (boolean, string?)
	if not startOk then
		return false, "notLoaded"
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "notLoaded"
	end
	local ok, why = money:tryDebit(player.UserId, amount)
	if ok then
		sync(player)
	end
	return ok, why
end

-- Pays `amount` to a player (Player or UserId). Returns "paid" | "pending"
-- | "dropped" | "absent" (not in this server: not paid).
function M.credit(who: any, amount: number, reason: string): string
	if not startOk then
		return "dropped"
	end
	local userId = userIdOf(who)
	local player = userId and Players:GetPlayerByUserId(userId)
	if not player then
		return "absent"
	end
	local result = money:credit(userId :: number, amount)
	if result == "paid" then
		sync(player)
	end
	return result
end

function M.refund(player: Player, amount: number, reason: string)
	local r = M.credit(player, amount, "refund:" .. reason)
	if r ~= "paid" and r ~= "pending" then
		warn(string.format("[Economy] refund of %d to %s not applied (%s)", amount, player.Name, r))
	end
end

function M.rodShopOpen(): boolean
	return startOk and Config.RodShopOpen == true
end

------------------------------------------------------------ meat ledger

-- GrinderProcessor: cut one fish into ledger pieces. Returns their ids
-- (count = meat yield for the tier). `player` is the net-pad player (nil
-- for the harpoon); `meta` is the catch payload ({ OwnerId, Variant, Source }).
function M.issueFish(player: Player?, fishName: any, tier: any, meta: any): { string }
	if not startOk then
		return {}
	end
	local playerId = if player then player.UserId else nil
	return Sales.issue(ledger, playerId, fishName, tier, meta)
end

-- Stamps a piece's identity on the object that stands for it.
function M.stamp(obj: Instance, pieceId: string)
	local piece = startOk and ledger:get(pieceId)
	if piece then
		PieceTags.stamp(obj, piece)
	end
end

-- BotSystem: copy identity from the picked meat to its carried clone.
function M.readPiece(obj: Instance): { [string]: any }?
	return PieceTags.read(obj)
end
function M.writePiece(obj: Instance, tags: { [string]: any }?)
	PieceTags.write(obj, tags)
end

-- TruckSystem: a player picked a piece up to carry to a truck.
function M.carry(pieceId: any): boolean
	return startOk and ledger:carry(pieceId)
end

-- The one sale of a piece: pays its owner (if in the server). Returns
-- (paid, amount). An unknown / already-settled id pays nothing.
function M.settle(pieceId: any, route: string): (boolean, number)
	if not startOk then
		return false, 0
	end
	local paid, amount = Sales.settle(ledger, pieceId, function(ownerId, value)
		return M.credit(ownerId, value, "sale:" .. route)
	end)
	return paid, amount
end

-- The object for a piece is gone without a sale: keep the piece as data.
function M.hold(pieceId: any): boolean
	return startOk and ledger:hold(pieceId)
end

-- Oldest held piece back to Live; the grinder makes its object.
function M.takeHeld(): Ledger.Piece?
	if not startOk then
		return nil
	end
	return ledger:takeHeld()
end

function M.heldCount(): number
	return if startOk then ledger.heldCount else 0
end

-- Too much meat waiting: the harpoon skips shots and the net pad refuses.
function M.saturated(): boolean
	return startOk and ledger.heldCount >= Config.Pipeline.MaxHeld
end

function M.pipeline()
	return Config.Pipeline
end

------------------------------------------------------------ rod-fish offers

-- Offers are on while the service runs, unless ReplicatedStorage.Economy's
-- RodOffersEnabled attribute is false.
function M.rodOffersEnabled(): boolean
	return startOk and root:GetAttribute(Config.RodOffersAttribute) ~= false
end

local VARIANT_TEXT = { Silver = "SILVER ", Gold = "GOLD " }

local function offerBillboard(
	fish: Model,
	caster: Player,
	fishName: string,
	variant: string?,
	price: number
): BillboardGui?
	local adornee = fish.PrimaryPart or fish:FindFirstChildWhichIsA("BasePart", true)
	if not adornee then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "OfferGui"
	gui.Size = UDim2.fromOffset(240, 58)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local top = Instance.new("TextLabel")
	top.Name = "Price"
	top.Size = UDim2.fromScale(1, 0.6)
	top.BackgroundTransparency = 1
	top.Font = Enum.Font.FredokaOne
	top.TextScaled = true
	top.TextColor3 = if variant == "Gold"
		then Color3.fromRGB(255, 205, 60)
		elseif variant == "Silver" then Color3.fromRGB(215, 230, 245)
		else Color3.new(1, 1, 1)
	top.TextStrokeTransparency = 0.2
	top.Text = string.format("%s%s - %d %s", VARIANT_TEXT[variant or ""] or "", fishName, price, Config.CurrencyName)
	top.Parent = gui
	local sub = top:Clone()
	sub.Name = "Who"
	sub.Position = UDim2.fromScale(0, 0.6)
	sub.Size = UDim2.fromScale(1, 0.4)
	sub.TextColor3 = Color3.fromRGB(220, 230, 240)
	sub.Text = caster.DisplayName .. "'s catch: Buy or Pass"
	sub.Parent = gui
	gui.Parent = adornee
	return gui
end

local RESULT_TEXT = {
	bought = "Bought! It's going to the aquarium",
	alreadyBought = "Already bought",
	closed = "That fish is gone",
	unknown = "That fish is gone",
	notYours = "Only the player who cast can buy this fish",
	expired = "Too late - it slipped off the hook",
	tooFar = "Get closer to the rods to buy",
	tankUnavailable = "The aquarium can't take it - not charged",
	funds = "Not enough Money",
	notLoaded = "Money is still loading - try again",
	deliveryFailed = "Couldn't reach the aquarium - refunded",
	passed = "Passed - it swims off",
}

function M._offerAction(player: Player, offerId: any, action: any): (boolean, string)
	if not startOk or typeof(player) ~= "Instance" or player.Parent ~= Players then
		return false, "Not available"
	end
	if type(offerId) ~= "number" or (action ~= "buy" and action ~= "pass") then
		return false, "Bad request"
	end
	local now = os.clock()
	local last = lastOfferAction[player]
	if last and now - last < Config.Offer.ActionCooldown then
		return false, "Slow down"
	end
	lastOfferAction[player] = now
	local rec = offerRecs[offerId]
	if action == "pass" then
		local r = offers:pass(offerId, player.UserId)
		return r == "passed", RESULT_TEXT[r] or r
	end
	if not rec then
		return false, RESULT_TEXT.unknown
	end
	-- One synchronous sequence (Offers.buy): no yields between the checks,
	-- the debit and the delivery.
	local r = offers:buy(offerId, player.UserId, now, {
		inRange = function(): boolean
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (hrp and hrp:IsA("BasePart") and humanoid and humanoid.Health > 0 and rec.fish.Parent) then
				return false
			end
			return (hrp.Position - rec.fish:GetPivot().Position).Magnitude <= Config.Offer.MaxBuyDistance
		end,
		reservationOk = function(): boolean
			return rec.reservationOk() == true
		end,
		debit = function(amount: number): (boolean, string?)
			return M.tryDebit(player, amount, "RodFish")
		end,
		deliver = function(): boolean
			return rec.deliver() == true
		end,
		refund = function(amount: number)
			M.refund(player, amount, "RodFish")
		end,
	})
	local text = RESULT_TEXT[r] or r
	M.notify(player, text, if r == "bought" then "success" elseif r == "alreadyBought" then "info" else "warn")
	return r == "bought" or r == "alreadyBought", text
end

export type RodOfferParams = {
	rodKey: any,
	caster: Player,
	fishName: string,
	tier: number,
	variant: string?,
	fish: Model, -- the revealed fish on the line (price label + range check)
	stillValid: () -> boolean, -- false = the aquarium can no longer take it
	reservationOk: () -> boolean, -- checked right before charging
	deliver: () -> boolean, -- puts the fish in the aquarium; false = failed (refund)
}

-- RodFishingSystem: offer a revealed fish to its caster and WAIT (yields)
-- until they buy it, pass, time out, leave, or the offer can't continue.
-- Returns true only if it was paid for AND delivered to the aquarium.
function M.runRodOffer(p: RodOfferParams): boolean
	if not M.rodOffersEnabled() then
		return false
	end
	local caster = p.caster
	if not (typeof(caster) == "Instance" and caster:IsA("Player") and caster.Parent == Players) then
		return false
	end
	local variant = Pricing.variant(p.variant)
	local tier = if type(p.tier) == "number" then p.tier else 1
	local price = Pricing.offerPrice(tier, variant)
	local offer, why = offers:open(p.rodKey, caster.UserId, p.fishName, tier, variant, price, os.clock())
	if not offer then
		warn("[Economy] rod offer not opened: " .. tostring(why))
		return false
	end
	local cfg = Instance.new("Configuration")
	cfg.Name = "Offer" .. offer.id
	cfg:SetAttribute("OfferId", offer.id)
	cfg:SetAttribute("CasterUserId", caster.UserId)
	cfg:SetAttribute("FishName", p.fishName)
	cfg:SetAttribute("Tier", tier)
	cfg:SetAttribute("Variant", variant)
	cfg:SetAttribute("Price", price)
	cfg:SetAttribute("ExpiresAt", workspace:GetServerTimeNow() + Config.Offer.TimeoutSeconds)
	cfg.Parent = offersFolder
	local okGui, gui = pcall(offerBillboard, p.fish, caster, p.fishName, variant, price)
	offerRecs[offer.id] = { fish = p.fish, reservationOk = p.reservationOk, deliver = p.deliver }

	while offer.status == "Open" or offer.status == "Delivering" do
		task.wait(0.1)
		if offer.status == "Open" then
			if os.clock() >= offer.expiresAt then
				offers:expire(os.clock())
			elseif caster.Parent ~= Players then
				offers:cancel(offer.id, "left")
			elseif not M.rodOffersEnabled() then
				offers:cancel(offer.id, "disabled")
			elseif not p.stillValid() or not p.fish.Parent then
				offers:cancel(offer.id, "tankUnavailable")
			end
		end
	end

	local bought = offer.status == "Bought"
	if offer.status == "Expired" then
		M.notify(caster, p.fishName .. " slipped off the hook (not bought)", "info")
	elseif offer.status == "Cancelled" and offer.reason == "tankUnavailable" then
		M.notify(caster, "The aquarium closed - " .. p.fishName .. " was not charged", "warn")
	end
	offerRecs[offer.id] = nil
	offers:forget(offer.id)
	cfg:Destroy()
	if okGui and gui then
		gui:Destroy()
	end
	return bought
end

-- Rod task failed: cancel its open offer (no charge). Safe to call any time.
function M.cancelRodOffer(rodKey: any)
	if startOk then
		local id = offers.byRod[rodKey]
		if id then
			offers:cancel(id, "error")
		end
	end
end

-- Diagnostics (Command Bar during Play): require(...).stats()
function M.stats()
	if not startOk then
		return nil
	end
	local c = ledger:counts()
	return {
		store = storeKind,
		live = c.live,
		carried = c.carried,
		held = c.held,
		totals = table.clone(ledger.totals),
	}
end

return M
