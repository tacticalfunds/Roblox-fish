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
--   * tells a piece's owner when it sells (Economy.Earned: the "+$" popup;
--     display only - the payment itself is the ledger settlement)
--   * rods (child module Rods): owned / equipped rods saved in the same
--     record as the money; buying saves money + rod in one write before it
--     counts; RodFishingSystem reads the presser's rod per cast (rodStats)
--   * net capacity (child module NetKg): the +5 KG signs, saved the same way;
--     it is PER PLAYER: NetLiftScript's gate reads the pad player's
--     NetMaxWeight (published = netKg); NetLift.MaxWeight stays the base
--   * the GrinderUpgrades KG signs' purchases (their own DataStore, a count of
--     +5 kg buys) are ADOPTED into netKg once GrinderUpgradesServer reports a
--     player's count (adoptLegacyNetKg); net purchases wait for that
--   * purchases another script delivers into its own store (GrinderUpgrades:
--     conveyor, blades) are JOURNALED: beginPurchase saves the debit and an
--     open entry in the Money record in one write, finishPurchase settles it;
--     an entry left open by a shutdown, a slow write or a crash is settled at
--     the player's next load by asking that store (its registered reader)
--     whether the purchase token arrived: delivered -> kept, else refunded
--   * the GrinderUpgrades blade multiplier (live enhancement) still applies
--     at each sale, on top of the piece's value (Meat Price is in that value)
--   * board upgrades (child module BoardUpgrades): levels saved the same way,
--     bought at the upgrade board (UpgradeBoardServer -> upgradeAction);
--     gameplay reads the committed value (upgradeValue; Meat Price in
--     issueFish: the owner's multiplier on the whole fish, once)
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
local HttpService = game:GetService("HttpService")
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
local Rods = require(script.Rods)
local NetKg = require(script.NetKg)
local BoardUpgrades = require(script.BoardUpgrades)

local M = {}
M.Config = Config
M.Pricing = Pricing
M.BoardUpgrades = BoardUpgrades

local started = false
local starting = false -- start() yields (Studio DataStore probe); other callers wait
local startOk = false

local money: MoneyStore.MoneyStore
local ledger: Ledger.Ledger
local root: Folder -- ReplicatedStorage.Economy (installed)
local notice: RemoteEvent
local earned: RemoteEvent? -- ReplicatedStorage.Economy.Earned: sale popups for the owner
local storeKind = "DataStore"
local offers: Offers.Offers
local offersFolder: Folder -- ReplicatedStorage.Economy.Offers (kept empty; offers live on buy stands)
local standsFolder: Folder -- Workspace.EconomyBuyStands: one invisible buy-stand part per open offer
local offerAction: RemoteFunction
local offerRecs = {} -- offer id -> { stand, reservationOk, deliver }
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
	M._publishRods(player) -- rods load with the money
	M._adoptLegacy(player) -- earlier KG-sign buys reported before the money loaded
	M._settleOpen(player) -- purchases a shutdown / slow write / crash left open
	M._publishNet(player)
	M._publishUpgrades(player)
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

local inFlight: { [number]: number } = {} -- userId -> journaled purchases still being delivered (beginPurchase)

local function unloadPlayer(player: Player)
	local userId = player.UserId
	-- let a purchase still being delivered settle first (a normal refund /
	-- keep); if it takes longer, the final save keeps its open entry and the
	-- next load settles it - nothing is lost either way
	local t0 = os.clock()
	while (inFlight[userId] or 0) > 0 and os.clock() - t0 < Config.SaveHoldSeconds do
		task.wait(0.1)
	end
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
	local e = root:FindFirstChild("Earned")
	if not (e and e:IsA("RemoteEvent")) then
		e = Instance.new("RemoteEvent")
		e.Name = "Earned"
		e.Parent = root
	end
	earned = e :: RemoteEvent
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
	-- runtime folder (Play only, never saved): the caster's client puts its
	-- buy prompt on these parts
	if workspace:FindFirstChild("EconomyBuyStands") then
		-- ours is created here and never saved: an existing one is someone else's
		warn("[Economy] Workspace.EconomyBuyStands already exists and isn't ours; economy off")
		return false
	end
	local sf = Instance.new("Folder")
	sf.Name = "EconomyBuyStands"
	sf.Archivable = false
	sf.Parent = workspace
	standsFolder = sf :: Folder
	local oa = root:FindFirstChild("OfferAction")
	if not (oa and oa:IsA("RemoteFunction")) then
		oa = Instance.new("RemoteFunction")
		oa.Name = "OfferAction"
		oa.Parent = root
	end
	offerAction = oa :: RemoteFunction
	offers = Offers.new(Config.Offer.TimeoutSeconds, RunService:IsStudio())
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

	-- Studio test clients (negative UserIds) always use a memory store, so
	-- local multi-client tests never write keys to the real DataStore.
	local real = pickStore()
	local testStore = memoryStore()
	local store: MoneyStore.Store = {
		update = function(key: string, transform: (any) -> any): any
			if string.sub(key, #Config.KeyPrefix + 1, #Config.KeyPrefix + 1) == "-" then
				return testStore.update(key, transform)
			end
			return real.update(key, transform)
		end,
	}
	local sessionId = MoneyStore.sessionId(game.JobId, function()
		return HttpService:GenerateGUID(false)
	end)
	money = MoneyStore.new(store, sessionId, os.time)
	ledger = Ledger.new("P", RunService:IsStudio())

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
		-- purchases still being delivered get a moment to settle; any left
		-- open are saved as open entries and settled at the next load
		local t0 = os.clock()
		while next(inFlight) and os.clock() - t0 < Config.SaveHoldSeconds do
			task.wait(0.1)
		end
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
	-- display only: whether rods can be bought right now (the shop UI's "SOON")
	root:SetAttribute("RodShopPaidOpen", M.rodShopOpen())
	root:GetAttributeChangedSignal("RodShopOpen"):Connect(function()
		root:SetAttribute("RodShopPaidOpen", M.rodShopOpen())
	end)
	root:SetAttribute("NetKgPaidOpen", M.netKgOpen())
	root:GetAttributeChangedSignal("NetKgOpen"):Connect(function()
		root:SetAttribute("NetKgPaidOpen", M.netKgOpen())
	end)
	root:SetAttribute("UpgradesPaidOpen", M.upgradesOpen())
	root:GetAttributeChangedSignal("UpgradesOpen"):Connect(function()
		root:SetAttribute("UpgradesPaidOpen", M.upgradesOpen())
	end)
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

------------------------------------------------------------ journaled purchases (delivered by another store)

-- source name -> reader(userId): the set of purchase tokens that source's
-- own store holds ({ [token] = true }), or nil if it can't be read now; a
-- second value (the record it read) goes to the source's refresh. YIELDS.
local purchaseSources: { [string]: (number) -> ({ [string]: boolean }?, any) } = {}
-- source name -> refresh(player, record): brings the source's own copy of the
-- player's state up to the record just read, BEFORE an open purchase is
-- closed (closing unblocks buying); false / an error = try again later.
local purchaseRefresh: { [string]: (Player, any) -> boolean } = {}
local liveTokens: { [string]: boolean } = {} -- begun in this server (settled by finishPurchase)
local settlingTokens: { [string]: boolean } = {} -- being settled from their source's store

-- Open entries loaded with the player's Money (a shutdown, a slow write or a
-- crash left them): once old enough that no write from another server can
-- still be on its way (Config.PurchaseSettleSeconds), ask the source's store
-- whether the token arrived: delivered -> the debit stays, else refunded.
-- Retries while the store can't be read; new purchases wait meanwhile.
function M._settleOpen(player: Player)
	local open = money:openPurchases(player.UserId)
	if not open then
		return
	end
	local pending = {}
	for token, entry in pairs(open) do
		if not liveTokens[token] and not settlingTokens[token] then
			settlingTokens[token] = true
			table.insert(pending, { token = token, entry = entry })
		end
	end
	if #pending == 0 then
		return
	end
	task.spawn(function()
		while player.Parent == Players and #pending > 0 do
			local rest = {}
			local wait = nil
			for _, p in ipairs(pending) do
				local reader = purchaseSources[p.entry.source]
				local age = os.time() - p.entry.t
				if not reader then
					table.insert(rest, p)
					wait = 5 -- its source hasn't registered yet
				elseif age < Config.PurchaseSettleSeconds then
					table.insert(rest, p)
					wait = math.min(wait or math.huge, Config.PurchaseSettleSeconds - age + 1)
				else
					local ok, applied, record = pcall(reader, player.UserId)
					local refresh = purchaseRefresh[p.entry.source]
					local refreshed = true
					if ok and type(applied) == "table" and refresh then
						-- the source's copy first: a purchase delivered later is owned there
						-- before buying is unblocked (never sold twice from a stale copy)
						local rok, rres = pcall(refresh, player, record)
						refreshed = rok and rres ~= false
						if not rok then
							warn("[Economy] refreshing " .. p.entry.source .. " for " .. player.Name .. " failed: " .. tostring(rres))
						end
					end
					if ok and type(applied) == "table" and refreshed then
						settlingTokens[p.token] = nil
						local delivered = applied[p.token] == true
						if money:settlePurchase(player.UserId, p.token, delivered) == "settled" then
							sync(player)
							local what = p.entry.what or p.entry.source
							log(string.format("%s: open purchase %s settled (%s)", player.Name, p.token, if delivered then "delivered" else "refunded"))
							M.notify(player, if delivered
								then "Your last purchase (" .. what .. ") went through"
								else "Your last purchase (" .. what .. ") didn't go through - refunded " .. p.entry.amount, "info")
							task.spawn(saveWithRetry, player.UserId, false)
						end
					else
						table.insert(rest, p)
						wait = math.min(wait or math.huge, 30)
					end
				end
			end
			pending = rest
			if #pending > 0 then
				task.wait(wait or 5)
			end
		end
		for _, p in ipairs(pending) do
			settlingTokens[p.token] = nil -- left: settled at their next load
		end
	end)
end

-- A script that delivers purchases into its own store registers how to read
-- the tokens that store holds (authoritatively: not a cached read), and
-- optionally how to refresh its own copy of a player's state from the record
-- read, before an open purchase is closed. Settles open entries of players
-- already here.
function M.registerPurchaseSource(
	name: string,
	reader: (number) -> ({ [string]: boolean }?, any),
	refresh: ((Player, any) -> boolean)?
)
	purchaseSources[name] = reader
	purchaseRefresh[name] = refresh
	if startOk then
		for _, p in ipairs(Players:GetPlayers()) do
			M._settleOpen(p)
		end
	end
end

-- Opens a purchase `source` will deliver: debit + open entry saved in ONE
-- write before this returns the token (checks: a real player here, loaded,
-- one at a time, no older entry unsettled). The caller writes the token
-- into its own store WITH the upgrade, then calls finishPurchase. YIELDS.
-- Returns (token, nil) or (nil, reason): "funds" | "notLoaded" | "busy" |
-- "unsettled" | "unavailable" | "notSaved".
function M.beginPurchase(player: Player, source: string, amount: number, what: string?): (string?, string?)
	if not startOk or typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return nil, "unavailable"
	end
	if not purchaseSources[source] then
		return nil, "unavailable"
	end
	if not (type(amount) == "number" and amount == math.floor(amount) and amount > 0) then
		return nil, "unavailable"
	end
	local t0 = os.clock()
	while money:isSaving(player.UserId) and os.clock() - t0 < 10 do
		task.wait(0.05)
	end
	if player.Parent ~= Players then
		return nil, "unavailable"
	end
	local token = source .. ":" .. HttpService:GenerateGUID(false)
	liveTokens[token] = true
	inFlight[player.UserId] = (inFlight[player.UserId] or 0) + 1
	local ok, why = money:beginPurchase(player.UserId, token, source, amount, what)
	if not ok then
		liveTokens[token] = nil
		inFlight[player.UserId] -= 1
		if inFlight[player.UserId] <= 0 then
			inFlight[player.UserId] = nil
		end
		local reason = if type(why) == "string" and string.sub(why, 1, 8) == "notSaved" then "notSaved"
			elseif why == "purchasesUnavailable" then "unavailable"
			else why
		return nil, reason
	end
	sync(player)
	return token, nil
end

-- Settles a purchase begun with beginPurchase: delivered = the token is in
-- the source's own store with the upgrade. false -> refunded. nil = the
-- source can't tell (its write errored and it couldn't read back): the entry
-- stays open and is settled from that store once it can be read. If the
-- player's Money is already saved and closed (they left, the server is
-- shutting down), the entry stays in their record and is settled at their
-- next load. Returns "settled" | "later" | "atNextLoad".
function M.finishPurchase(player: Player, token: string, delivered: boolean?): string
	local userId = player.UserId
	if inFlight[userId] then
		inFlight[userId] -= 1
		if inFlight[userId] <= 0 then
			inFlight[userId] = nil
		end
	end
	liveTokens[token] = nil
	if delivered == nil then
		if player.Parent == Players then
			M._settleOpen(player)
		end
		return "later"
	end
	if money:settlePurchase(userId, token, delivered == true) == "settled" then
		if moneyValues[player] then
			sync(player)
		end
		if player.Parent == Players then
			task.spawn(saveWithRetry, userId, false)
		end
		return "settled"
	end
	warn(string.format("[Economy] purchase %s for %s left open (%s): settled at their next load", token, player.Name,
		if delivered then "delivered" else "not delivered"))
	return "atNextLoad"
end

function M.refund(player: Player, amount: number, reason: string)
	local r = M.credit(player, amount, "refund:" .. reason)
	if r ~= "paid" and r ~= "pending" then
		warn(string.format("[Economy] refund of %d to %s not applied (%s)", amount, player.Name, r))
	end
end

-- Paid rod purchases: Config.RodShopOpen, or (for a Studio validation) the
-- RodShopOpen attribute on ReplicatedStorage.Economy. Equipping never needs it.
function M.rodShopOpen(): boolean
	return startOk and (Config.RodShopOpen == true or root:GetAttribute("RodShopOpen") == true)
end

------------------------------------------------------------ rods (saved ownership)

M.Rods = Rods
local lastRodAction: { [Player]: number } = {}
local rodBusy: { [Player]: boolean } = {}
M.onPlayerLeaving(function(player: Player)
	lastRodAction[player] = nil
	rodBusy[player] = nil
end)

-- Display only (the shop UI reads these; the server never reads them back):
-- RodOwned_<id> = 1 for owned rods, EquippedRod = the rod casts use.
function M._publishRods(player: Player)
	local profile = money:rods(player.UserId)
	if not profile or not player.Parent then
		return
	end
	for _, rod in ipairs(Rods.list()) do
		player:SetAttribute("RodOwned_" .. rod.Id, if profile.owned[rod.Id] then 1 else nil)
	end
	player:SetAttribute("EquippedRod", Rods.stats(profile).Id)
end

-- The rod a cast by this player uses right now (a copy): the equipped one,
-- else Basic (also while money isn't loaded, or without the economy).
function M.rodStats(player: Player): Rods.Rod
	local rod = if startOk and typeof(player) == "Instance" and player:IsA("Player")
		then money:rodStats(player.UserId)
		else Rods.get(Config.BaseRod) :: Rods.Rod
	return table.clone(rod)
end

local ROD_REASONS = {
	funds = "Not enough money",
	notLoaded = "Your money is still loading - try again in a moment",
	rodsUnavailable = "Your saved rods couldn't be read, so buying rods is off this session",
	busy = "One moment - still saving",
	owned = "You already own that rod",
	unknown = "Unknown rod",
	notOwned = "You don't own that rod",
}
local function rodReason(why: string?): string
	if type(why) == "string" and string.sub(why, 1, 8) == "notSaved" then
		return "Couldn't save the purchase - you were not charged. Try again."
	end
	return ROD_REASONS[why or ""] or "Couldn't do that right now"
end

-- The shop's buy / equip for one rod. An owned rod is EQUIPPED (never
-- charged again); an unowned one is bought (and equipped) only while the
-- paid shop is open and `canBuy(rod)` agrees (RodShopServer: in range, in
-- stock). The purchase is saved (money + rod, one write) before this
-- returns true; if the save fails nothing is charged. Checks: a real player
-- in this server, alive, money loaded, one action at a time, a short
-- cooldown. Returns (ok, message for the player).
function M.rodAction(player: Player, rodId: any, canBuy: ((Rods.Rod) -> (boolean, string?))?): (boolean, string)
	if not startOk then
		return false, "The rod shop is unavailable right now"
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "The rod shop is unavailable right now"
	end
	if rodBusy[player] then
		return false, ROD_REASONS.busy
	end
	local now = os.clock()
	if lastRodAction[player] and now - lastRodAction[player] < Config.RodActionCooldown then
		return false, "Slow down a little"
	end
	lastRodAction[player] = now
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return false, "You can't do that right now"
	end
	local profile = money:rods(player.UserId)
	if not profile then
		return false, ROD_REASONS.notLoaded
	end
	local rod = Rods.get(rodId)
	if not rod then
		return false, ROD_REASONS.unknown
	end
	local decision = Rods.decide(profile, rod.Id)
	if decision == "equipped" then
		return true, rod.Name .. " is equipped"
	elseif decision == "equip" then
		local ok, why = money:equipRod(player.UserId, rod.Id)
		if not ok then
			return false, rodReason(why)
		end
		M._publishRods(player)
		return true, "Equipped " .. rod.Name
	end
	-- every purchase condition; checked now AND again right before the debit
	-- (after any wait for a save already running), with no yield in between
	local function buyable(): (boolean, string?)
		if player.Parent ~= Players then
			return false, "The rod shop is unavailable right now"
		end
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if not (hum and hum.Health > 0) then
			return false, "You can't do that right now"
		end
		if not M.rodShopOpen() then
			return false, "The rod shop opens soon"
		end
		local now = money:rods(player.UserId)
		if not now then
			return false, ROD_REASONS.notLoaded
		end
		if Rods.decide(now, rod.Id) ~= "buy" then
			return false, ROD_REASONS.owned
		end
		if canBuy then
			local allowed, why = canBuy(rod)
			if not allowed then
				return false, why or "You can't buy that here"
			end
		end
		return true, nil
	end
	local allowed, refusal = buyable()
	if not allowed then
		return false, refusal :: string
	end
	rodBusy[player] = true
	local ran, ok, why = pcall(function()
		local t0 = os.clock()
		while money:isSaving(player.UserId) and os.clock() - t0 < 10 do
			task.wait(0.05)
		end
		local still, changed = buyable() -- things may have changed while waiting
		if not still then
			return false, "refused:" .. tostring(changed)
		end
		return money:buyRod(player.UserId, rod.Id) -- saves money + rod in one write
	end)
	rodBusy[player] = nil
	if not ran then
		warn("[Economy] rod purchase failed: " .. tostring(ok))
		return false, rodReason("notSaved")
	end
	if not ok then
		if why and string.sub(why, 1, 8) == "refused:" then
			return false, string.sub(why, 9)
		end
		if why and string.sub(why, 1, 8) == "notSaved" then
			warn(string.format("[Economy] %s's %s purchase not saved (%s); not charged", player.Name, rod.Id, why))
		end
		return false, rodReason(why)
	end
	sync(player)
	M._publishRods(player)
	log(string.format("%s bought %s for %d", player.Name, rod.Id, rod.Price))
	return true, "Bought and equipped " .. rod.Name
end

------------------------------------------------------------ meat ledger

-- The owner's Meat Price right now (1 if they aren't in this server or
-- their money hasn't loaded): the committed level only.
local function meatMultiplier(ownerId: number): number
	local level = money:upgradeLevel(ownerId, "MeatPrice")
	return if level then BoardUpgrades.value("MeatPrice", level) else 1
end

-- GrinderProcessor: cut one fish into ledger pieces. Returns their ids
-- (count = meat yield for the tier). `player` is the net-pad player (nil
-- for the harpoon); `meta` is the catch payload ({ OwnerId, Variant, Source }).
-- The owner's Meat Price multiplies the whole fish's value once, here; the
-- pieces' values are fixed from now on (each still pays once).
-- An AMBIENT catch (the harpoon shoots on its own) with no buyer and no
-- bound gun owner belongs to nobody - except in a SOLO server: with exactly
-- one player present, the scene is running for them, so it is theirs, fixed
-- now, at catch time. Never over an explicit owner (the fish's buyer, the
-- gun's OwnerUserId), never with two or more players (nobody is picked),
-- never for meat caught earlier (pieces keep the owner they were issued with).
local SOLO_AMBIENT_OWNER = true
local function soloAmbientOwner(player: Player?, meta: any): number?
	if not SOLO_AMBIENT_OWNER or player ~= nil or type(meta) ~= "table" or meta.Source ~= "Harpoon" then
		return nil
	end
	if PieceTags.ownerFor(nil, meta) ~= nil then
		return nil -- an explicit owner stays the owner
	end
	local present = Players:GetPlayers()
	if #present ~= 1 then
		return nil
	end
	return Ledger.validOwner(present[1].UserId, RunService:IsStudio())
end

function M.issueFish(player: Player?, fishName: any, tier: any, meta: any): { string }
	if not startOk then
		return {}
	end
	local playerId = if player then player.UserId else soloAmbientOwner(player, meta)
	return Sales.issue(ledger, playerId, fishName, tier, meta, meatMultiplier)
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

-- Credits waiting for this player's Money to load (not spendable yet).
local function queued(userId: number): number
	local s = money.sessions[userId]
	return if s then s.pending else 0
end

-- The one sale of a piece: pays its owner (if in the server). Returns
-- (paid, amount). An unknown / already-settled id pays nothing.
function M.settle(pieceId: any, route: string): (boolean, number)
	if not startOk then
		return false, 0
	end
	-- what the credit really added (no yields between the reads and the
	-- credit): the balance can be clamped at MaxBalance, the pending queue
	-- at MaxPendingCredit
	local kind, added = nil, 0
	local paid, amount, piece = Sales.settle(ledger, pieceId, function(ownerId, value)
		-- GrinderUpgrades: the owner's blade tier multiplies what their meat pays
		do
			local owner = Players:GetPlayerByUserId(ownerId)
			local cfgMod = game:GetService("ReplicatedStorage"):FindFirstChild("GrinderUpgradesConfig")
			if owner and cfgMod then
				local okCfg, cfg = pcall(require, cfgMod)
				if okCfg then
					local mult = cfg.mult(owner:GetAttribute("BladeTier") or 1)
					value = math.max(1, math.floor(value * mult + 0.5))
				end
			end
		end
		local balanceBefore, queuedBefore = money:balance(ownerId), queued(ownerId)
		local r = M.credit(ownerId, value, "sale:" .. route)
		if r == "paid" then
			kind, added = "paid", (money:balance(ownerId) or 0) - (balanceBefore or 0)
		elseif r == "pending" then
			kind, added = "pending", queued(ownerId) - queuedBefore
		end
		return r
	end)
	if kind and piece then
		M._tellEarned(piece, kind, added, route)
	end
	return paid, amount
end

-- The owner's popup (display only; the ledger settlement is the payment).
-- Sends (added, route, fishName, variant, kind, value): `added` is what the
-- credit really added, `value` the piece's price; kind "paid" = spendable
-- now, "pending" = waits for their Money to load. Off while
-- ReplicatedStorage.Economy's EarningsPopup attribute is false. Never
-- yields and never errors into the sale.
function M._tellEarned(piece: Ledger.Piece, kind: string, added: number, route: string)
	if not earned or root:GetAttribute("EarningsPopup") == false then
		return
	end
	local player = piece.ownerId and Players:GetPlayerByUserId(piece.ownerId)
	if not player then
		return
	end
	pcall(function()
		(earned :: RemoteEvent):FireClient(player, added, route, piece.fishName, piece.variant, kind, piece.value)
	end)
end

------------------------------------------------------------ net capacity (+5 KG signs)

local lastNetAction: { [Player]: number } = {}
M.onPlayerLeaving(function(player: Player)
	lastNetAction[player] = nil
end)

-- Paid +5 KG: Config.NetKgOpen, or (for a Studio validation) the NetKgOpen
-- attribute on ReplicatedStorage.Economy.
function M.netKgOpen(): boolean
	return startOk and (Config.NetKgOpen == true or root:GetAttribute("NetKgOpen") == true)
end

-- Legacy KG signs (GrinderUpgradesServer, before this): it kept a COUNT of
-- +5 kg buys in its own store. With Config.NetKgLegacy on, a player's net
-- counts - and can be bought - only once GrinderUpgradesServer has reported
-- that count this session (adoptLegacyNetKg); the count is adopted as
-- netKg = max(netKg, Base + Step x buys): idempotent, never added twice, and
-- never based on the live NetLift.MaxWeight (which this service's own
-- NetCapacityServer raises).
local legacyNet: { [Player]: number } = {}
M.onPlayerLeaving(function(player: Player)
	legacyNet[player] = nil
end)
local function legacyReady(player: Player): boolean
	return Config.NetKgLegacy ~= true or legacyNet[player] ~= nil
end
function M._adoptLegacy(player: Player)
	local buys = legacyNet[player]
	if buys and money:netKg(player.UserId) then
		local r = money:adoptNetKg(player.UserId, Config.NetKg.Base + Config.NetKg.Step * buys)
		if r == "raised" then
			log(string.format("%s: adopted %d earlier +%d kg buys (net %d kg)", player.Name, buys, Config.NetKg.Step, money:netKg(player.UserId) :: number))
		elseif r ~= "kept" then
			warn(string.format("[Economy] %s's earlier kg buys (%d) not adopted: %s", player.Name, buys, tostring(r)))
		end
	end
end

-- GrinderUpgradesServer: this player's earlier KG-sign buys (its `kg`
-- count, loaded from its own store). Returns true when accepted.
function M.adoptLegacyNetKg(player: Player, buys: any): boolean
	if not startOk or typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false
	end
	if not (type(buys) == "number" and buys == buys and buys == math.floor(buys) and buys >= 0 and buys <= 100000) then
		warn("[Economy] " .. player.Name .. "'s earlier kg buys are not a count; net purchases stay off this session")
		return false
	end
	legacyNet[player] = buys
	M._adoptLegacy(player) -- or when their money loads
	M._publishNet(player)
	return true
end

-- The player's owned (committed) net capacity, or nil while not loaded
-- (or while their earlier KG-sign buys haven't been reported yet).
function M.netKg(player: Player): number?
	if not startOk or typeof(player) ~= "Instance" or not player:IsA("Player") or not legacyReady(player) then
		return nil
	end
	return money:netKg(player.UserId)
end

-- Display only (the sign plates / board read these): NetKg, NetKgNext,
-- NetKgCost; and, as the GrinderUpgrades scripts published them, NetMaxWeight
-- (= NetKg, the player's own capacity - never the shared MaxWeight plus
-- anything) and NetKgBuys (steps above Base).
function M._publishNet(player: Player)
	local kg = M.netKg(player)
	if not kg or not player.Parent then
		return
	end
	local nextKg, cost = NetKg.nextStep(kg)
	player:SetAttribute("NetKg", kg)
	player:SetAttribute("NetKgNext", nextKg)
	player:SetAttribute("NetKgCost", cost)
	player:SetAttribute("NetMaxWeight", kg)
	player:SetAttribute("NetKgBuys", math.max(0, (kg - Config.NetKg.Base) // Config.NetKg.Step))
end

local NET_REASONS = {
	funds = "Not enough money",
	notLoaded = "Your money is still loading - try again in a moment",
	netUnavailable = "Your saved net couldn't be read, so net upgrades are off this session",
	busy = "One moment - still saving",
}

-- One press of a +5 KG sign: buys the next step for this player, saved
-- (money + capacity, one write) before it counts; nothing is charged if the
-- write fails. `canBuy()` is the sign's own check (in reach). Everything is
-- checked before any wait for a running save AND again right before the
-- debit, with no yield in between. Returns (ok, message, newKg?).
function M.netKgAction(player: Player, canBuy: (() -> (boolean, string?))?): (boolean, string, number?)
	if not startOk or typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "Net upgrades are unavailable right now", nil
	end
	if rodBusy[player] then -- one purchase at a time per player (rods or net)
		return false, NET_REASONS.busy, nil
	end
	local now = os.clock()
	if lastNetAction[player] and now - lastNetAction[player] < Config.NetKgCooldown then
		return false, "Slow down a little", nil
	end
	lastNetAction[player] = now
	local function buyable(): (boolean, string?)
		if player.Parent ~= Players then
			return false, "Net upgrades are unavailable right now"
		end
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if not (hum and hum.Health > 0) then
			return false, "You can't do that right now"
		end
		if not M.netKgOpen() then
			return false, "Net upgrades open soon"
		end
		if not legacyReady(player) then
			return false, "Your net upgrades are still loading - try again in a moment"
		end
		local kg = money:netKg(player.UserId)
		if not kg then
			return false, NET_REASONS.notLoaded
		end
		if not NetKg.nextStep(kg) then
			return false, string.format("Your net is at the maximum (%d kg)", kg)
		end
		if canBuy then
			local allowed, why = canBuy()
			if not allowed then
				return false, why or "You can't buy that here"
			end
		end
		return true, nil
	end
	local allowed, refusal = buyable()
	if not allowed then
		return false, refusal :: string, nil
	end
	local before = money:netKg(player.UserId) :: number
	rodBusy[player] = true
	local ran, ok, why, newKg, cost = pcall(function()
		local t0 = os.clock()
		while money:isSaving(player.UserId) and os.clock() - t0 < 10 do
			task.wait(0.05)
		end
		local still, changed = buyable()
		if not still then
			return false, "refused:" .. tostring(changed), nil, nil
		end
		before = money:netKg(player.UserId) :: number
		return money:buyNetKg(player.UserId) -- saves money + capacity in one write
	end)
	rodBusy[player] = nil
	if not ran then
		warn("[Economy] net upgrade failed: " .. tostring(ok))
		return false, "Couldn't save the upgrade - you were not charged. Try again.", nil
	end
	if not ok then
		if type(why) == "string" and string.sub(why, 1, 8) == "refused:" then
			return false, string.sub(why, 9), nil
		end
		if type(why) == "string" and string.sub(why, 1, 8) == "notSaved" then
			warn(string.format("[Economy] %s's net upgrade not saved (%s); not charged", player.Name, why))
			return false, "Couldn't save the upgrade - you were not charged. Try again.", nil
		end
		return false, NET_REASONS[why or ""] or "Couldn't do that right now", nil
	end
	sync(player)
	M._publishNet(player)
	log(string.format("%s net %d -> %d kg for %d", player.Name, before, newKg, cost))
	return true, string.format("Net capacity %d → %d kg (-$%d)", before, newKg, cost), newKg
end

------------------------------------------------------------ board upgrades (Rod Luck, ...)

local lastUpgradeAction: { [Player]: number } = {}
M.onPlayerLeaving(function(player: Player)
	lastUpgradeAction[player] = nil
end)

-- Paid board upgrades: Config.BoardUpgradesOpen, or (for a Studio
-- validation) the UpgradesOpen attribute on ReplicatedStorage.Economy.
function M.upgradesOpen(): boolean
	return startOk and (Config.BoardUpgradesOpen == true or root:GetAttribute("UpgradesOpen") == true)
end

-- The effect a player's COMMITTED level gives (1 = none): what gameplay
-- reads, e.g. RodFishingSystem once per accepted press. Not loaded, not
-- running, or an unknown id -> 1.
function M.upgradeValue(player: Player, id: string): number
	if not startOk or typeof(player) ~= "Instance" or not player:IsA("Player") or not BoardUpgrades.known(id) then
		return 1
	end
	local level = money:upgradeLevel(player.UserId, id)
	return if level then BoardUpgrades.value(id, level) else 1
end

-- Display only (the board reads these): Upg<Id> = current value,
-- Upg<Id>Next / Upg<Id>Cost = the next level's value and price (nil at max).
function M._publishUpgrades(player: Player)
	if not player.Parent then
		return
	end
	for _, id in ipairs(BoardUpgrades.ids()) do
		local level = money:upgradeLevel(player.UserId, id)
		if level then
			local _, cost, nextValue = BoardUpgrades.nextStep(id, level)
			player:SetAttribute("Upg" .. id, BoardUpgrades.value(id, level))
			player:SetAttribute("Upg" .. id .. "Next", nextValue)
			player:SetAttribute("Upg" .. id .. "Cost", cost)
		end
	end
end

local UPGRADE_REASONS = {
	funds = "Not enough money",
	notLoaded = "Your money is still loading - try again in a moment",
	upgradesUnavailable = "Your saved upgrades couldn't be read, so board upgrades are off this session",
	busy = "One moment - still saving",
}
-- "1.25x" for a multiplier; "9/min", "7 in line" for an upgrade with a Unit
local function formatValue(v: number, id: string?): string
	local unit = id and Config.BoardUpgrades[id] and Config.BoardUpgrades[id].Unit
	return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")) .. (if type(unit) == "string" then unit else "x")
end
M.formatUpgradeValue = formatValue

-- One press of a board upgrade card: buys the next level for this player,
-- saved (money + levels, one write) before it counts; nothing is charged if
-- the write fails. `canBuy()` is the board's own check (in reach). Checked
-- before any wait for a running save AND again right before the debit, with
-- no yield in between. Returns (ok, message, newValue?).
function M.upgradeAction(player: Player, id: any, canBuy: (() -> (boolean, string?))?): (boolean, string, number?)
	if not startOk or typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "Upgrades are unavailable right now", nil
	end
	if not BoardUpgrades.known(id) then
		return false, "Unknown upgrade", nil
	end
	local name = Config.BoardUpgrades[id].Name or id
	if rodBusy[player] then -- one purchase at a time per player (rods, net or board)
		return false, UPGRADE_REASONS.busy, nil
	end
	local now = os.clock()
	if lastUpgradeAction[player] and now - lastUpgradeAction[player] < Config.BoardUpgradeCooldown then
		return false, "Slow down a little", nil
	end
	lastUpgradeAction[player] = now
	local function buyable(): (boolean, string?)
		if player.Parent ~= Players then
			return false, "Upgrades are unavailable right now"
		end
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if not (hum and hum.Health > 0) then
			return false, "You can't do that right now"
		end
		if not M.upgradesOpen() then
			return false, name .. " upgrades open soon"
		end
		local level = money:upgradeLevel(player.UserId, id)
		if not level then
			return false, UPGRADE_REASONS.notLoaded
		end
		if not BoardUpgrades.nextStep(id, level) then
			return false, string.format("%s is at the maximum (%s)", name, formatValue(BoardUpgrades.value(id, level), id))
		end
		if canBuy then
			local allowed, why = canBuy()
			if not allowed then
				return false, why or "You can't buy that here"
			end
		end
		return true, nil
	end
	local allowed, refusal = buyable()
	if not allowed then
		return false, refusal :: string, nil
	end
	local before = money:upgradeLevel(player.UserId, id) :: number
	rodBusy[player] = true
	local ran, ok, why, newLevel, cost = pcall(function()
		local t0 = os.clock()
		while money:isSaving(player.UserId) and os.clock() - t0 < 10 do
			task.wait(0.05)
		end
		local still, changed = buyable()
		if not still then
			return false, "refused:" .. tostring(changed), nil, nil
		end
		before = money:upgradeLevel(player.UserId, id) :: number
		return money:buyUpgrade(player.UserId, id) -- saves money + levels in one write
	end)
	rodBusy[player] = nil
	if not ran then
		warn("[Economy] upgrade failed: " .. tostring(ok))
		return false, "Couldn't save the upgrade - you were not charged. Try again.", nil
	end
	if not ok then
		if type(why) == "string" and string.sub(why, 1, 8) == "refused:" then
			return false, string.sub(why, 9), nil
		end
		if type(why) == "string" and string.sub(why, 1, 8) == "notSaved" then
			warn(string.format("[Economy] %s's %s upgrade not saved (%s); not charged", player.Name, id, why))
			return false, "Couldn't save the upgrade - you were not charged. Try again.", nil
		end
		return false, UPGRADE_REASONS[why or ""] or "Couldn't do that right now", nil
	end
	sync(player)
	M._publishUpgrades(player)
	local fromValue, toValue = BoardUpgrades.value(id, before), BoardUpgrades.value(id, newLevel)
	log(string.format("%s %s %s -> %s for %d", player.Name, id, formatValue(fromValue, id), formatValue(toValue, id), cost))
	return true, string.format("%s %s → %s (-$%d)", name, formatValue(fromValue, id), formatValue(toValue, id), cost), toValue
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

-- Customers (CustomerSystem): each present player brings their own saved
-- Customer Speed (customers a minute) and Customer Line (places); the server's
-- rate is the sum (up to Config.Customers.Max), its line the largest (up to
-- Config.Customers.LineMax). A player whose money hasn't loaded counts at the
-- base. Never below what the Car Sales upgrades publish.
-- Returns (customers a minute, line size).
local function savedValue(player: Player, id: string): number?
	if not (startOk and BoardUpgrades.known(id)) then
		return nil
	end
	local level = money:upgradeLevel(player.UserId, id)
	return if level then BoardUpgrades.value(id, level) else nil
end
function M.customers(): (number, number)
	local speeds, lines = {}, {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(speeds, savedValue(p, "CustomerSpeed") or Config.Customers.PerPlayer)
		table.insert(lines, savedValue(p, "CustomerLine") or Config.Customers.LineCap)
	end
	return Sales.customers(
		speeds,
		workspace:GetAttribute("CustomersPerMin"),
		workspace:GetAttribute("CustomersLineCap"),
		Config.Customers,
		lines
	)
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
local LIME = Color3.fromRGB(120, 255, 40)
local OUTLINE = Color3.fromRGB(10, 10, 12)

local function outlinedLabel(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	y: number,
	h: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, y)
	label.Size = UDim2.fromScale(1, h)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = parent
	return label
end

-- Everyone sees the catch's label above the fish: the real roll chance (only
-- when the rod supplied it), the species and the server price. It follows the
-- fish as clients animate it (adorned to the fish's part).
local function offerBillboard(
	fish: Model,
	fishName: string,
	variant: string?,
	price: number,
	chance: any
): BillboardGui?
	local adornee = fish.PrimaryPart or fish:FindFirstChildWhichIsA("BasePart", true)
	if not adornee then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "OfferGui"
	gui.Size = UDim2.fromScale(6.25, 3) -- locked world size
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local chanceText = Offers.chanceText(chance)
	if chanceText then
		outlinedLabel(gui, "Chance", "\u{1F340} " .. chanceText, LIME, 0, 0.24)
	end
	local nameColor = if variant == "Gold"
		then Color3.fromRGB(255, 205, 60)
		elseif variant == "Silver" then Color3.fromRGB(215, 230, 245)
		else Color3.new(1, 1, 1)
	outlinedLabel(gui, "FishName", (VARIANT_TEXT[variant or ""] or "") .. fishName, nameColor, 0.24, 0.32)
	outlinedLabel(gui, "Price", "$" .. tostring(price), LIME, 0.56, 0.44)
	gui.Parent = adornee
	return gui
end

-- The caster's buy point: an invisible anchored part at the rod stand. The
-- caster's EconomyClient puts a ProximityPrompt on it (only the caster's);
-- its attributes carry the offer for that client. Destroyed with the offer.
local function standAnchor(offer: Offers.Offer, stand: Vector3, expiresAt: number): Part
	local part = Instance.new("Part")
	part.Name = "BuyStand" .. offer.id
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Archivable = false
	part.CFrame = CFrame.new(stand)
	part:SetAttribute("OfferId", offer.id)
	part:SetAttribute("CasterUserId", offer.casterId)
	part:SetAttribute("FishName", offer.fishName)
	part:SetAttribute("Variant", offer.variant)
	part:SetAttribute("Price", offer.price)
	part:SetAttribute("ExpiresAt", expiresAt)
	part:SetAttribute("PromptDistance", Config.Offer.PromptDistance)
	part.Parent = standsFolder
	return part
end

local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local RESULT_TEXT = {
	bought = "Bought! It's going to the aquarium",
	alreadyBought = "Already bought",
	closed = "That fish is gone",
	unknown = "That fish is gone",
	notYours = "Only the player who cast can buy this fish",
	expired = "Too late - it slipped off the hook",
	tooFar = "Walk up to the rod to buy",
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
			-- measured from the rod stand (where the prompt is), not the fish
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not (hrp and hrp:IsA("BasePart") and alive(player)) then
				return false
			end
			return Offers.inReach(
				(hrp.Position - rec.stand).Magnitude,
				Config.Offer.PromptDistance,
				Config.Offer.ReachSlack
			)
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
	chance: number?, -- the fish's real roll chance on the rods (display only)
	fish: Model, -- the revealed fish on the line (price label)
	stand: Vector3, -- the rod stand's lowest point (buy prompt + range check)
	stillValid: () -> boolean, -- false = the aquarium can no longer take it
	reservationOk: () -> boolean, -- checked right before charging
	deliver: () -> boolean, -- puts the fish in the aquarium; false = failed (refund)
}

-- RodFishingSystem: offer a revealed fish to its caster and WAIT (yields)
-- until they buy it at the rod stand, it times out, they die or leave, or
-- the offer can't continue. Returns true only if it was paid for AND
-- delivered to the aquarium.
function M.runRodOffer(p: RodOfferParams): boolean
	if not M.rodOffersEnabled() then
		return false
	end
	local caster = p.caster
	if not (typeof(caster) == "Instance" and caster:IsA("Player") and caster.Parent == Players) then
		return false
	end
	if typeof(p.stand) ~= "Vector3" then
		warn("[Economy] rod offer not opened: no rod stand position")
		return false
	end
	if not alive(caster) then
		return false -- knocked out while reeling: it slips off, nothing charged
	end
	local variant = Pricing.variant(p.variant)
	local tier = if type(p.tier) == "number" then p.tier else 1
	local price = Pricing.offerPrice(tier, variant)
	local offer, why = offers:open(p.rodKey, caster.UserId, p.fishName, tier, variant, price, os.clock())
	if not offer then
		warn("[Economy] rod offer not opened: " .. tostring(why))
		return false
	end
	local standPos = p.stand + Vector3.new(0, Config.Offer.StandHeight, 0)
	local okGui, gui = pcall(offerBillboard, p.fish, p.fishName, variant, price, p.chance)
	local okStand, stand =
		pcall(standAnchor, offer, standPos, workspace:GetServerTimeNow() + Config.Offer.TimeoutSeconds)
	if not okStand then
		offers:cancel(offer.id, "error")
		warn("[Economy] buy stand failed: " .. tostring(stand))
	end
	offerRecs[offer.id] = { stand = standPos, reservationOk = p.reservationOk, deliver = p.deliver }

	while offer.status == "Open" or offer.status == "Delivering" do
		task.wait(0.1)
		if offer.status == "Open" then
			if os.clock() >= offer.expiresAt then
				offers:expire(os.clock())
			elseif caster.Parent ~= Players then
				offers:cancel(offer.id, "left")
			elseif not alive(caster) then
				offers:cancel(offer.id, "died")
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
	elseif offer.status == "Cancelled" and offer.reason == "died" then
		M.notify(caster, p.fishName .. " slipped off the hook - not charged", "info")
	elseif offer.status == "Cancelled" and offer.reason == "tankUnavailable" then
		M.notify(caster, "The aquarium closed - " .. p.fishName .. " was not charged", "warn")
	end
	offerRecs[offer.id] = nil
	offers:forget(offer.id)
	if okStand and stand then
		stand:Destroy()
	end
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
