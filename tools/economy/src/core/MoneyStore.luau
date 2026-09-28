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

local Config = require(script.Parent.Config)

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
}

local MoneyStore = {}
MoneyStore.__index = MoneyStore

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
	local ok, err = pcall(self.store.update, MoneyStore.key(userId), function(old: any): any
		if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.job ~= self.jobId then
			decision = "lost"
			return nil
		end
		local out = copy(old)
		out.v = Config.SchemaVersion
		out.money = s.balance
		out.lock = if release then nil else { job = self.jobId, t = self.now() }
		written = s.balance
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
	s.dirty = s.balance ~= written
	if release then
		s.state = "Closed"
	end
	return true, nil
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
