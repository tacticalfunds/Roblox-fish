--!strict
-- Pure wrapper of CycleState for the live shared scene: ONE physical tank, a
-- fixed set of shared rods, anyone may press the button. There is a single
-- tank owner (Config.Scene.OwnerKey), so capacity is never multiplied per
-- player.
--
-- Rod catches are not taken out of the place's river: the rod script picks a
-- fish name from the weighted pool at bite time. hook() therefore creates a
-- fresh tracked fish and hooks it in one step. When a fish finishes its
-- release swim it is handed to the place's own river (the controller spawns a
-- SwimmingFish model) and forgotten here, so tracking never grows unbounded.

local CycleState = require(script.Parent.CycleState)
local Adapters = require(script.Parent.Adapters)

local SharedTank = {}
SharedTank.__index = SharedTank

export type Handoff = { id: number, name: string? }

export type Info = {
	count: number,
	reserved: number,
	capacity: number,
	free: number,
	full: boolean,
	levels: { [string]: number },
}

function SharedTank.new(config: any)
	local state = CycleState.new(config)
	local owner = config.Scene.OwnerKey
	local ok, err = state:addTank(owner)
	assert(ok, err)
	return setmetatable({
		config = config,
		state = state,
		owner = owner,
		names = {} :: { [number]: string },
		rodKeys = {} :: { any },
		stopped = false,
	}, SharedTank)
end

export type SharedTank = typeof(SharedTank.new({ Upgrades = {}, Scene = { OwnerKey = "x" } }))

function SharedTank.registerRods(self: SharedTank, keys: { any }): number
	local count = 0
	for _, key in ipairs(keys) do
		if self.state:registerRod(key, self.owner) then
			table.insert(self.rodKeys, key)
			count += 1
		end
	end
	return count
end

function SharedTank.info(self: SharedTank): Info?
	local info = self.state:tankInfo(self.owner)
	if not info then
		return nil
	end
	local free = math.max(0, info.capacity - info.count - info.reserved)
	return {
		count = info.count,
		reserved = info.reserved,
		capacity = info.capacity,
		free = free,
		full = free == 0,
		levels = info.levels,
	}
end

-- Reserves one tank slot per rod, in the order given, BEFORE any rod task is
-- started. Stops at the first refusal for a full tank. Returns the rod keys
-- that may cast and, when none could, the reason.
function SharedTank.reserve(self: SharedTank, keys: { any }, now: number): ({ any }, string?)
	if self.stopped then
		return {}, "stopped"
	end
	local reserved: { any }, reason: string? = {}, nil
	for _, key in ipairs(keys) do
		local ok, err = self.state:beginCast(self.owner, key, now)
		if ok then
			table.insert(reserved, key)
		elseif err == "tankFull" then
			reason = "tankFull"
			break
		else
			reason = reason or err
		end
	end
	if #reserved > 0 then
		return reserved, nil
	end
	return reserved, reason
end

-- Hooks a newly picked fish on a rod that holds a reservation.
function SharedTank.hook(self: SharedTank, key: any, fishName: any, now: number): (boolean, string?, number?)
	if self.stopped then
		return false, "stopped", nil
	end
	if type(fishName) ~= "string" or fishName == "" then
		return false, "badName", nil
	end
	local id = self.state:spawnRiverFish()
	local ok, err = self.state:hookFish(self.owner, key, id, now)
	if not ok then
		self.state:forgetRiverFish(id)
		return false, err, nil
	end
	self.names[id] = fishName
	return true, nil, id
end

-- Moves the rod's hooked fish into the tank. Returns (ok, reason, id, name).
function SharedTank.land(self: SharedTank, key: any, now: number): (boolean, string?, number?, string?)
	if self.stopped then
		return false, "stopped", nil, nil
	end
	local ok, err, id = self.state:landCatch(self.owner, key, now)
	if not ok or not id then
		return false, err, nil, nil
	end
	return true, nil, id, self.names[id]
end

-- Releases a rod's reservation and any fish on its line. That fish was made
-- for this rod and never swam in the place's river, so it is forgotten; the
-- rod script decides what to do with its visual (grinder fallback). Safe to
-- call on an idle rod. Returns true if something was released.
function SharedTank.abort(self: SharedTank, key: any): boolean
	local rod = self.state.rods[key]
	local wasBusy = rod ~= nil and rod.phase ~= "Idle"
	local id = self.state:cancelCast(key)
	if id then
		self.state:forgetRiverFish(id)
		self.names[id] = nil
	end
	return wasBusy
end

-- Starts releasing a batch from the tank. Returns (ok, reason, fish).
function SharedTank.release(self: SharedTank, now: number): (boolean, string?, { Handoff })
	if self.stopped then
		return false, "stopped", {}
	end
	local ok, err, ids = self.state:release(self.owner, now)
	local out: { Handoff } = {}
	for _, id in ipairs(ids) do
		table.insert(out, { id = id, name = self.names[id] })
	end
	return ok, err, out
end

-- Advances timers. Returns the fish that finished their release swim; they
-- are no longer tracked and must be put into the place's river by the caller.
function SharedTank.step(self: SharedTank, now: number): { Handoff }
	local out: { Handoff } = {}
	if self.stopped then
		return out
	end
	for _, event in ipairs(self.state:step(now)) do
		if event.kind == "ReturnedToRiver" and event.fishId then
			local id = event.fishId
			local name = self.names[id]
			self.state:forgetRiverFish(id)
			self.names[id] = nil
			table.insert(out, { id = id, name = name })
		end
	end
	return out
end

function SharedTank.buyUpgrade(self: SharedTank, adapters: any, upgradeId: any): (boolean, string?, number?)
	if self.stopped then
		return false, "stopped", nil
	end
	return Adapters.buyUpgrade(adapters, self.state, self.owner, upgradeId)
end

-- Disable/stop. Rod casts are cancelled and their fish forgotten (the rod
-- script sends those to the grinder instead). Every fish in the tank or
-- mid-release is returned for the caller to put into the river, so nothing
-- is lost. Idempotent.
function SharedTank.shutdown(self: SharedTank): { Handoff }
	local out: { Handoff } = {}
	if self.stopped then
		return out
	end
	for _, key in ipairs(self.rodKeys) do
		self:abort(key)
	end
	for _, id in ipairs(self.state:removeOwner(self.owner)) do
		table.insert(out, { id = id, name = self.names[id] })
		self.state:forgetRiverFish(id)
		self.names[id] = nil
	end
	self.stopped = true
	return out
end

-- Core invariants plus name bookkeeping: every tracked fish has a name, no
-- name outlives its fish, and no fish lingers in River (handed off at once).
function SharedTank.check(self: SharedTank): (boolean, string?)
	local ok, problem = self.state:checkInvariants()
	if not ok then
		return false, problem
	end
	for id, fish in pairs(self.state.fish) do
		if fish.location == "River" then
			return false, "river fish not handed off " .. id
		end
		if self.names[id] == nil then
			return false, "tracked fish without name " .. id
		end
	end
	for id in pairs(self.names) do
		if self.state.fish[id] == nil then
			return false, "name without fish " .. id
		end
	end
	return true, nil
end

return SharedTank
