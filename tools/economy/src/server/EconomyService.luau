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
	local store = dataStoreStore()
	if RunService:IsStudio() and Config.StudioMemoryStoreFallback then
		local ok, err = pcall(function()
			DataStoreService:GetDataStore(Config.DataStoreName):GetAsync("__probe")
		end)
		if not ok then
			storeKind = "Memory"
			warn(
				"[Economy] DataStore unavailable in Studio ("
					.. tostring(err)
					.. "); using a TEMPORARY in-memory store - Money will not persist"
			)
			return memoryStore()
		end
	end
	return store
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
