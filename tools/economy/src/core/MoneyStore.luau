--!strict
-- MoneyStore: per-player balances with safe loading and saving. Pure: the
-- DataStore is injected as `store.update(key, transform)` with UpdateAsync
-- semantics (transform may run several times; returning nil cancels the
-- write; the call ERRORS on failure). The service passes the real DataStore;
-- tests pass fakes that fail on purpose.
--
-- Safety rules this module enforces:
--   * The starting grant is given ONLY when the store positively reports no
--     record for the player (transform called with nil). A failed or errored
--     read never grants and never creates defaults.
--   * A record that is not valid money data is left untouched ("corrupt"):
--     the player's money is unavailable this session, nothing overwrites it.
--   * A player whose load has not succeeded is NEVER saved.
--   * Saves write only while this server holds the record's session lock;
--     losing it stops all further saves, debits and credits for that player.
--   * save() reports success only when the store call returned without error
--     AND the transform wrote this server's value.
--   * Debits/credits are synchronous (no yields), so a check-and-debit can't
--     interleave with another purchase.
--   * v2: the record may carry `rods` (see Rods). Loaded with the money, saved
--     with the money in the same write. Every other field (and a newer
--     schema version) is kept on every save. A rod purchase debits and saves
--     at once: if that write fails, the rod and the money are both undone.
--   * `netKg` (the +5 KG signs) works the same way: loaded and saved with the
--     money, bought with one staged write, invalid data never overwritten.
--   * `upgrades` (the upgrade board's levels, see BoardUpgrades): the same
--     again; entries this build doesn't know are kept.
--   * `pendingPurchases`: purchases another script delivers into ITS OWN
--     store (GrinderUpgrades). beginPurchase saves the debit AND an entry
--     { source, amount, t } under a fresh token in ONE write before the other
--     store is touched; finishPurchase settles it (delivered: the entry goes;
--     not: the money comes back and the entry goes - both in the same
--     session, saved together). An entry still there when the record is next
--     loaded (a shutdown, a timeout, a crash) is settled then by asking the
--     other store whether the token arrived (EconomyService). So a purchase
--     is never paid-for-and-lost nor delivered-and-free, whatever stops.

local Config = require(script.Parent.Config)
local Rods = require(script.Parent.Rods)
local NetKg = require(script.Parent.NetKg)
local BoardUpgrades = require(script.Parent.BoardUpgrades)

export type Store = {
	update: (key: string, transform: (old: any) -> any) -> any,
}

export type State = "Loading" | "Ready" | "Failed" | "Lost" | "Closed"

type Session = {
	userId: number,
	state: State,
	failReason: string?,
	balance: number,
	pending: number, -- credits waiting for a successful load
	dirty: boolean,
	saving: boolean,
	granted: boolean, -- this session created the record with the starting grant
	rods: Rods.Profile, -- Basic only until loaded
	rodsWritable: boolean, -- false: not loaded, or the saved field isn't valid (left untouched)
	rodsRev: number, -- bumped on every rod change (dirty tracking across saves)
	buying: boolean, -- a rod purchase is being saved
	pendingRods: Rods.Profile?, -- that purchase's profile: written by the save, not yet committed
	netKg: number, -- owned net capacity (Base until loaded)
	netWritable: boolean, -- false: not loaded, or the saved field isn't valid (left untouched)
	pendingNetKg: number?, -- a net purchase being written, not yet committed
	upgrades: BoardUpgrades.Levels, -- the board's levels (all 0 until loaded)
	upgradesWritable: boolean, -- false: not loaded, or the saved field isn't valid (left untouched)
	pendingUpgrades: BoardUpgrades.Levels?, -- an upgrade purchase being written, not yet committed
	purchases: { [string]: Purchase }, -- pendingPurchases: token -> the open purchase
	purchasesWritable: boolean, -- false: not loaded, or the saved field isn't valid (left untouched)
}

export type Purchase = { source: string, amount: number, t: number, what: string? }

local MoneyStore = {}
MoneyStore.__index = MoneyStore

-- pendingPurchases: nil = none; otherwise every entry must be readable, or the
-- whole field is left as it is (and no such purchases this session).
local function validPurchase(k: any, v: any): boolean
	return type(k) == "string" and #k > 0 and #k <= 80 and type(v) == "table" and type(v.source) == "string"
		and type(v.amount) == "number" and v.amount == math.floor(v.amount) and v.amount > 0 and v.amount <= Config.MaxBalance
		and type(v.t) == "number" and (v.what == nil or type(v.what) == "string")
end
local function loadPurchases(field: any): ({ [string]: Purchase }, boolean)
	if field == nil then
		return {}, true
	end
	if type(field) ~= "table" then
		return {}, false
	end
	local out = {}
	for k, v in pairs(field) do
		if not validPurchase(k, v) then
			return {}, false
		end
		out[k] = { source = v.source, amount = v.amount, t = v.t, what = v.what }
	end
	return out, true
end
local function copyPurchases(t: { [string]: Purchase }): { [string]: Purchase }
	local out = {}
	for k, v in pairs(t) do
		out[k] = { source = v.source, amount = v.amount, t = v.t, what = v.what }
	end
	return out
end

export type MoneyStore = typeof(setmetatable(
	{} :: {
		store: Store,
		jobId: string,
		now: () -> number,
		sessions: { [number]: Session },
	},
	MoneyStore
))

function MoneyStore.new(store: Store, jobId: string, now: () -> number): MoneyStore
	return setmetatable({ store = store, jobId = jobId, now = now, sessions = {} }, MoneyStore)
end

local function validMoney(v: any): boolean
	return type(v) == "number" and v == v and v >= 0 and v <= Config.MaxBalance and v == math.floor(v)
end
MoneyStore.validMoney = validMoney

local function validAmount(v: any): boolean
	return type(v) == "number" and v == v and v > 0 and v <= Config.MaxBalance and v == math.floor(v)
end

-- Session-lock owner id. game.JobId is empty in Studio, so parallel Studio
-- sessions would share one lock owner; use a fresh GUID instead.
function MoneyStore.sessionId(jobId: string?, makeGuid: () -> string): string
	if type(jobId) == "string" and jobId ~= "" then
		return jobId
	end
	return "studio-" .. makeGuid()
end

-- Studio test clients have negative UserIds; their money is never written
-- to the real DataStore (the service routes these keys to memory).
function MoneyStore.isTestUser(userId: number): boolean
	return userId < 0
end

function MoneyStore.key(userId: number): string
	return Config.KeyPrefix .. tostring(userId)
end

local function copy(t: { [any]: any }): { [any]: any }
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

-- Starts tracking a player (state Loading). Idempotent.
function MoneyStore.begin(self: MoneyStore, userId: number)
	if not self.sessions[userId] then
		self.sessions[userId] = {
			userId = userId,
			state = "Loading",
			failReason = nil,
			balance = 0,
			pending = 0,
			dirty = false,
			saving = false,
			granted = false,
			rods = Rods.fresh(),
			rodsWritable = false,
			rodsRev = 0,
			buying = false,
			netKg = NetKg.base(),
			netWritable = false,
			upgrades = {},
			upgradesWritable = false,
			purchases = {},
			purchasesWritable = false,
		}
	end
end

function MoneyStore.state(self: MoneyStore, userId: number): (State?, string?)
	local s = self.sessions[userId]
	if not s then
		return nil, nil
	end
	return s.state, s.failReason
end

-- One load attempt. Returns "ready" | "locked" | "corrupt" | "error" | "notLoading".
function MoneyStore.attemptLoad(self: MoneyStore, userId: number): (string, string?)
	local s = self.sessions[userId]
	if not s or s.state ~= "Loading" then
		return "notLoading", nil
	end
	local decision: string? = nil
	local loaded: any = nil
	local ok, err = pcall(self.store.update, MoneyStore.key(userId), function(old: any): any
		local now = self.now()
		if old == nil then
			decision = "new"
			loaded = {
				v = Config.SchemaVersion,
				money = Config.StartingGrant,
				granted = true,
				lock = { job = self.jobId, t = now },
				rods = Rods.save(Rods.fresh(), nil),
				netKg = NetKg.base(),
				upgrades = {},
			}
			return loaded
		end
		if type(old) ~= "table" or not validMoney(old.money) then
			decision = "corrupt"
			return nil
		end
		local lock = old.lock
		if
			type(lock) == "table"
			and lock.job ~= self.jobId
			and type(lock.t) == "number"
			and now - lock.t < Config.LockSeconds
		then
			decision = "locked"
			return nil
		end
		decision = "loaded"
		loaded = copy(old)
		loaded.lock = { job = self.jobId, t = now }
		return loaded
	end)
	if s.state ~= "Loading" then
		-- The player left while the call yielded. If it took the session
		-- lock, give it back (money unchanged) so their next server can load.
		if ok and (decision == "new" or decision == "loaded") then
			pcall(self.store.update, MoneyStore.key(userId), function(old: any): any
				if type(old) == "table" and type(old.lock) == "table" and old.lock.job == self.jobId then
					local out = copy(old)
					out.lock = nil
					return out
				end
				return nil
			end)
		end
		return "notLoading", nil
	end
	if not ok then
		return "error", tostring(err)
	end
	if decision == "corrupt" then
		s.state = "Failed"
		s.failReason = "corrupt"
		return "corrupt", nil
	end
	if decision == "locked" then
		return "locked", nil
	end
	if (decision == "new" or decision == "loaded") and loaded then
		s.balance = loaded.money
		s.granted = decision == "new"
		s.rods, s.rodsWritable = Rods.load(loaded.rods)
		s.netKg, s.netWritable = NetKg.load(loaded.netKg)
		s.upgrades, s.upgradesWritable = BoardUpgrades.load(loaded.upgrades)
		s.purchases, s.purchasesWritable = loadPurchases(loaded.pendingPurchases)
		s.state = "Ready"
		if s.pending > 0 then
			s.balance = math.min(Config.MaxBalance, s.balance + s.pending)
			s.pending = 0
			s.dirty = true
		end
		return "ready", decision
	end
	return "error", "store returned without running the transform"
end

-- All load attempts used up: money stays unavailable this session (retries
-- may still call attemptLoad after reopen()).
function MoneyStore.markFailed(self: MoneyStore, userId: number, reason: string)
	local s = self.sessions[userId]
	if s and s.state == "Loading" then
		s.state = "Failed"
		s.failReason = reason
	end
end

-- Background retry of a failed (not corrupt) load.
function MoneyStore.reopen(self: MoneyStore, userId: number): boolean
	local s = self.sessions[userId]
	if s and s.state == "Failed" and s.failReason ~= "corrupt" then
		s.state = "Loading"
		s.failReason = nil
		return true
	end
	return false
end

function MoneyStore.balance(self: MoneyStore, userId: number): number?
	local s = self.sessions[userId]
	if s and s.state == "Ready" then
		return s.balance
	end
	return nil
end

-- Takes exactly `amount` or nothing. Returns (ok, reason).
function MoneyStore.tryDebit(self: MoneyStore, userId: number, amount: any): (boolean, string?)
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return false, "notLoaded"
	end
	if not validAmount(amount) then
		return false, "badAmount"
	end
	if s.balance < amount then
		return false, "funds"
	end
	s.balance -= amount
	s.dirty = true
	return true, nil
end

-- Adds money. Returns "paid" (in the balance), "pending" (applied once the
-- player's load succeeds), or "dropped" (not tracked / lock lost / invalid).
function MoneyStore.credit(self: MoneyStore, userId: number, amount: any): string
	local s = self.sessions[userId]
	if not s or not validAmount(amount) then
		return "dropped"
	end
	if s.state == "Ready" then
		s.balance = math.min(Config.MaxBalance, s.balance + amount)
		s.dirty = true
		return "paid"
	elseif s.state == "Loading" or s.state == "Failed" then
		s.pending = math.min(Config.MaxPendingCredit, s.pending + amount)
		return "pending"
	end
	return "dropped"
end

-- Writes the balance (and refreshes or releases the lock). Returns
-- (ok, reason): true only if this server's value was really written.
function MoneyStore.save(self: MoneyStore, userId: number, release: boolean): (boolean, string?)
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return false, "notLoaded"
	end
	if s.saving then
		return false, "busy"
	end
	s.saving = true
	local decision: string? = nil
	local written: number? = nil
	local writtenRev: number? = nil
	local ok, err = pcall(self.store.update, MoneyStore.key(userId), function(old: any): any
		if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.job ~= self.jobId then
			decision = "lost"
			return nil
		end
		local out = copy(old) -- every field this build doesn't manage is kept
		-- never lower a newer build's schema number
		out.v = if type(old.v) == "number" and old.v > Config.SchemaVersion then old.v else Config.SchemaVersion
		out.money = s.balance
		if s.rodsWritable then
			-- a purchase in flight writes its staged profile (committed only on success)
			out.rods = Rods.save(s.pendingRods or s.rods, old.rods)
		end
		if s.netWritable then
			out.netKg = s.pendingNetKg or s.netKg -- a net purchase in flight writes its staged value
		end
		if s.upgradesWritable then
			-- an upgrade purchase in flight writes its staged levels
			out.upgrades = BoardUpgrades.copy(s.pendingUpgrades or s.upgrades)
		end
		if s.purchasesWritable then
			out.pendingPurchases = if next(s.purchases) then copyPurchases(s.purchases) else nil
		end
		out.lock = if release then nil else { job = self.jobId, t = self.now() }
		written = s.balance
		writtenRev = s.rodsRev
		decision = "saved"
		return out
	end)
	s.saving = false
	if not ok then
		return false, "error: " .. tostring(err)
	end
	if decision == "lost" then
		s.state = "Lost"
		return false, "lockLost"
	end
	if decision ~= "saved" or written == nil then
		return false, "notWritten"
	end
	-- anything changed while the write was in flight is saved next time
	s.dirty = s.balance ~= written or s.rodsRev ~= writtenRev
	if release then
		s.state = "Closed"
	end
	return true, nil
end

------------------------------------------------------------ rods (v2)

-- The player's rods, or nil while their money isn't loaded (a copy).
function MoneyStore.rods(self: MoneyStore, userId: number): Rods.Profile?
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return nil
	end
	return Rods.copy(s.rods)
end

-- The rod a cast uses right now: the equipped one, else Basic.
function MoneyStore.rodStats(self: MoneyStore, userId: number): Rods.Rod
	local s = self.sessions[userId]
	return Rods.stats(if s and s.state == "Ready" then s.rods else nil)
end

local function rodsChanged(s: Session)
	s.rodsRev += 1
	s.dirty = true
end

-- Equips an owned rod. Synchronous; never charges. Saved with the next save.
-- Returns (ok, reason): reason "notLoaded" | "busy" | "unknown" | "notOwned"
-- | "equipped" (already).
function MoneyStore.equipRod(self: MoneyStore, userId: number, id: any): (boolean, string?)
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return false, "notLoaded"
	end
	if s.buying then
		return false, "busy"
	end
	local d = Rods.decide(s.rods, id)
	if d == "buy" then
		return false, "notOwned"
	elseif d ~= "equip" then
		return false, d
	end
	s.rods.equipped = id
	s.rods.keepEquipped = nil
	rodsChanged(s)
	return true, nil
end

-- Buys (and equips) a rod: takes its price and WRITES the new balance and
-- the rod together in one store update before reporting success. If that
-- write fails, the money and the rod are both put back. YIELDS (one store
-- call). Refuses while a save is running: the caller waits for isSaving()
-- to clear, then calls (no yield in between). Returns (ok, reason): reason
-- "notLoaded" | "rodsUnavailable" | "busy" | "unknown" | "owned" | "funds"
-- | "badAmount" | "notSaved" (charged nothing).
function MoneyStore.buyRod(self: MoneyStore, userId: number, id: any): (boolean, string?)
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return false, "notLoaded"
	end
	if not s.rodsWritable then
		return false, "rodsUnavailable"
	end
	if s.buying or s.saving then
		return false, "busy"
	end
	local d = Rods.decide(s.rods, id)
	if d ~= "buy" then
		return false, if d == "equip" or d == "equipped" then "owned" else d
	end
	local rod = Rods.get(id) :: Rods.Rod
	if rod.Price > 0 then
		local paid, why = self:tryDebit(userId, rod.Price)
		if not paid then
			return false, why
		end
	end
	-- The new rod is STAGED: only the save writes it. Everything gameplay
	-- reads (rods(), rodStats()) stays the committed profile until the write
	-- succeeded, so a cast during the save never gets an unpaid rod.
	local pending = Rods.copy(s.rods)
	pending.owned[rod.Id] = true
	pending.equipped = rod.Id
	pending.keepEquipped = nil
	s.pendingRods = pending
	s.buying = true
	local saved, why = self:save(userId, false)
	s.buying = false
	s.pendingRods = nil
	if saved then
		s.rods = pending -- committed: exactly what was written
		return true, nil
	end
	-- not written: the rod was never committed; give the money back
	-- (credits that arrived meanwhile stay) and save the undone state next time
	if s.state == "Ready" then
		s.balance = math.min(Config.MaxBalance, s.balance + rod.Price)
		s.dirty = true
	end
	return false, "notSaved: " .. tostring(why)
end

------------------------------------------------------------ net capacity (+5 KG)

-- The player's owned net capacity (committed), or nil while not loaded.
function MoneyStore.netKg(self: MoneyStore, userId: number): number?
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return nil
	end
	return s.netKg
end

------------------------------------------------------------ purchases delivered by another store

-- Opens a purchase another script will deliver into its own store: takes
-- `amount` and WRITES the new balance and the entry { source, amount, t }
-- under `token` in ONE store update before returning true. If that write
-- fails, the money is back and there is no entry. One open purchase per
-- player at a time (and none while an older one is unsettled). YIELDS.
-- Returns (ok, reason): "notLoaded" | "purchasesUnavailable" | "busy" |
-- "unsettled" | "badAmount" | "funds" | "notSaved: ...".
function MoneyStore.beginPurchase(self: MoneyStore, userId: number, token: string, source: string, amount: number, what: string?): (boolean, string?)
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return false, "notLoaded"
	end
	if not s.purchasesWritable then
		return false, "purchasesUnavailable"
	end
	if s.buying or s.saving then
		return false, "busy"
	end
	if next(s.purchases) then
		return false, "unsettled"
	end
	if type(token) ~= "string" or #token == 0 or #token > 80 or type(source) ~= "string" then
		return false, "badAmount"
	end
	local paid, why = self:tryDebit(userId, amount)
	if not paid then
		return false, why
	end
	s.purchases[token] = { source = source, amount = amount, t = self.now(), what = what }
	rodsChanged(s)
	s.buying = true
	local saved, reason = self:save(userId, false)
	s.buying = false
	if saved then
		return true, nil
	end
	-- not written: no purchase (a write that did land is overwritten by the
	-- next save while this server holds the lock, or settled at the next load)
	s.purchases[token] = nil
	if s.state == "Ready" then
		s.balance = math.min(Config.MaxBalance, s.balance + amount)
		s.dirty = true
	end
	return false, "notSaved: " .. tostring(reason)
end

-- Settles an open purchase in this session: delivered -> the entry goes;
-- not delivered -> the money comes back and the entry goes. Saved together
-- with the next save. Returns "settled" | "notOpen" (not loaded here / no
-- such entry: it stays in the store and is settled at the next load).
function MoneyStore.settlePurchase(self: MoneyStore, userId: number, token: string, delivered: boolean): string
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return "notOpen"
	end
	local entry = s.purchases[token]
	if not entry then
		return "notOpen"
	end
	s.purchases[token] = nil
	if not delivered then
		s.balance = math.min(Config.MaxBalance, s.balance + entry.amount)
	end
	rodsChanged(s)
	return "settled"
end

-- The open purchases (a copy), or nil while not loaded.
function MoneyStore.openPurchases(self: MoneyStore, userId: number): { [string]: Purchase }?
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" or not s.purchasesWritable then
		return nil
	end
	return copyPurchases(s.purchases)
end

-- Adopts net capacity bought before (the legacy GrinderUpgrades KG signs):
-- raises the committed capacity to `kg` if that is higher, never lowers it,
-- never adds (so reporting the same purchases again changes nothing). Saved
-- with the next save. Returns "raised" | "kept" | "notLoaded" |
-- "netUnavailable" | "invalid".
function MoneyStore.adoptNetKg(self: MoneyStore, userId: number, kg: any): string
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return "notLoaded"
	end
	if not s.netWritable then
		return "netUnavailable"
	end
	if not (type(kg) == "number" and kg == kg and kg == math.floor(kg) and kg >= NetKg.base() and kg <= 1e6) then
		return "invalid"
	end
	if kg <= s.netKg then
		return "kept"
	end
	s.netKg = kg
	rodsChanged(s) -- saved with the next save
	return "raised"
end

-- Buys the next step: takes its cost and WRITES the new balance and the new
-- capacity together before it counts; the new capacity is staged (netKg()
-- keeps the committed one) until that write succeeded. Same rules as
-- buyRod. Returns (ok, reason, newKg, cost): reason "notLoaded" |
-- "netUnavailable" | "busy" | "max" | "funds" | "notSaved: ..." .
function MoneyStore.buyNetKg(self: MoneyStore, userId: number): (boolean, string?, number?, number?)
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return false, "notLoaded", nil, nil
	end
	if not s.netWritable then
		return false, "netUnavailable", nil, nil
	end
	if s.buying or s.saving then
		return false, "busy", nil, nil
	end
	local nextKg, cost = NetKg.nextStep(s.netKg)
	if not nextKg or not cost then
		return false, "max", nil, nil
	end
	local paid, why = self:tryDebit(userId, cost)
	if not paid then
		return false, why, nil, nil
	end
	s.pendingNetKg = nextKg
	s.buying = true
	local saved, reason = self:save(userId, false)
	s.buying = false
	s.pendingNetKg = nil
	if saved then
		s.netKg = nextKg -- committed: exactly what was written
		return true, nil, nextKg, cost
	end
	if s.state == "Ready" then
		s.balance = math.min(Config.MaxBalance, s.balance + cost)
		s.dirty = true
	end
	return false, "notSaved: " .. tostring(reason), nil, nil
end

------------------------------------------------------------ board upgrades

-- The player's (committed) level of a board upgrade, or nil while not loaded.
function MoneyStore.upgradeLevel(self: MoneyStore, userId: number, id: string): number?
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return nil
	end
	return BoardUpgrades.level(s.upgrades, id)
end

-- Buys the next level of a board upgrade: takes its cost and WRITES the new
-- balance and the new level together before it counts; the new level is
-- staged (upgradeLevel() keeps the committed one) until that write
-- succeeded. Same rules as buyNetKg. Returns (ok, reason, newLevel, cost):
-- reason "notLoaded" | "unknown" | "upgradesUnavailable" | "busy" | "max" |
-- "funds" | "notSaved: ..." .
function MoneyStore.buyUpgrade(self: MoneyStore, userId: number, id: any): (boolean, string?, number?, number?)
	local s = self.sessions[userId]
	if not s or s.state ~= "Ready" then
		return false, "notLoaded", nil, nil
	end
	if not BoardUpgrades.known(id) then
		return false, "unknown", nil, nil
	end
	if not s.upgradesWritable then
		return false, "upgradesUnavailable", nil, nil
	end
	if s.buying or s.saving then
		return false, "busy", nil, nil
	end
	local nextLevel, cost = BoardUpgrades.nextStep(id, BoardUpgrades.level(s.upgrades, id))
	if not nextLevel or not cost then
		return false, "max", nil, nil
	end
	local paid, why = self:tryDebit(userId, cost)
	if not paid then
		return false, why, nil, nil
	end
	local pending = BoardUpgrades.copy(s.upgrades)
	pending[id] = nextLevel
	s.pendingUpgrades = pending
	s.buying = true
	local saved, reason = self:save(userId, false)
	s.buying = false
	s.pendingUpgrades = nil
	if saved then
		s.upgrades = pending -- committed: exactly what was written
		return true, nil, nextLevel, cost
	end
	if s.state == "Ready" then
		s.balance = math.min(Config.MaxBalance, s.balance + cost)
		s.dirty = true
	end
	return false, "notSaved: " .. tostring(reason), nil, nil
end

function MoneyStore.isBuying(self: MoneyStore, userId: number): boolean
	local s = self.sessions[userId]
	return s ~= nil and s.buying
end

function MoneyStore.isSaving(self: MoneyStore, userId: number): boolean
	local s = self.sessions[userId]
	return s ~= nil and s.saving
end

function MoneyStore.isDirty(self: MoneyStore, userId: number): boolean
	local s = self.sessions[userId]
	return s ~= nil and s.dirty
end

-- Stops tracking. Unsaved pending credits of an unloaded player are dropped
-- (never written over their record). Call save(userId, true) first.
function MoneyStore.forget(self: MoneyStore, userId: number)
	local s = self.sessions[userId]
	if s then
		s.state = "Closed"
		self.sessions[userId] = nil
	end
end

function MoneyStore.users(self: MoneyStore): { number }
	local out = {}
	for id in pairs(self.sessions) do
		table.insert(out, id)
	end
	return out
end

return MoneyStore
