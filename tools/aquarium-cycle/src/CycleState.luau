--!strict
-- Pure, server-authoritative state for the dock-rod -> aquarium -> river cycle.
-- No Roblox APIs: time is passed in, and every operation returns a result code
-- instead of touching Instances. A Roblox-side controller (written only after
-- the existing Studio fish/rod/tank source has been inspected) is expected to
-- translate these results into its existing visuals.
--
-- Every fish the system tracks is in exactly ONE location at all times:
--   River                    swimming, catchable
--   Hooked(rodId)            on a rod's line, being lifted
--   Tank(owner)              in that owner's aquarium
--   Releasing(owner, readyAt) swimming from the tank back to the river
-- Moves between locations are the only way fish change state, so fish are
-- never duplicated or lost. A full tank blocks new casts (slots are reserved
-- at cast time) rather than dropping fish.
--
-- Owners are opaque keys (e.g. a UserId). Rods are registered to exactly one
-- owner; every call checks that the caller owns the rod/tank it names.

local Upgrades = require("./Upgrades")

local CycleState = {}
CycleState.__index = CycleState

export type Location = "River" | "Hooked" | "Tank" | "Releasing"

export type Fish = {
	id: number,
	location: Location,
	owner: any?, -- Tank/Releasing owner
	rodId: any?, -- Hooked rod
	readyAt: number?, -- Releasing: when it reaches the river
}

export type Rod = {
	id: any,
	owner: any,
	phase: "Idle" | "Waiting" | "Hooked",
	castAt: number,
	hookedAt: number,
	fishId: number?,
}

export type Tank = {
	owner: any,
	levels: { [string]: number },
	count: number, -- fish in location Tank for this owner
	reserved: number, -- active casts holding a slot
	lastReleaseAt: number,
}

export type Event = { kind: string, fishId: number?, rodId: any?, owner: any?, reason: string? }

function CycleState.new(config: any)
	local ok, problem = Upgrades.validateConfig(config)
	assert(ok, problem)
	local self = setmetatable({
		config = config,
		fish = {} :: { [number]: Fish },
		rods = {} :: { [any]: Rod },
		tanks = {} :: { [any]: Tank },
		nextFishId = 0,
	}, CycleState)
	return self
end

export type CycleState = typeof(CycleState.new({ Upgrades = {} }))

local function isKey(v: any): boolean
	return v ~= nil and (type(v) == "number" or type(v) == "string") and v == v
end

local function isId(v: any): boolean
	return type(v) == "number" and v == v and v >= 1 and v % 1 == 0 and v < 2 ^ 53
end

local function isTime(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- ---------------------------------------------------------------- queries

function CycleState.capacity(self: CycleState, owner: any): number
	local tank = self.tanks[owner]
	if not tank then
		return 0
	end
	return Upgrades.value(self.config, "Capacity", tank.levels.Capacity)
end

function CycleState.freeSlots(self: CycleState, owner: any): number
	local tank = self.tanks[owner]
	if not tank then
		return 0
	end
	return math.max(0, self:capacity(owner) - tank.count - tank.reserved)
end

export type TankInfo = { count: number, reserved: number, capacity: number, levels: { [string]: number } }

function CycleState.tankInfo(self: CycleState, owner: any): TankInfo?
	local tank = self.tanks[owner]
	if not tank then
		return nil
	end
	return {
		count = tank.count,
		reserved = tank.reserved,
		capacity = self:capacity(owner),
		levels = table.clone(tank.levels),
	}
end

function CycleState.getFish(self: CycleState, id: number): Fish?
	local f = self.fish[id]
	return f and table.clone(f) or nil
end

-- ---------------------------------------------------------------- setup

-- Adds a fish to the river and returns its unique id.
function CycleState.spawnRiverFish(self: CycleState): number
	self.nextFishId += 1
	local id = self.nextFishId
	self.fish[id] = { id = id, location = "River" }
	return id
end

function CycleState.addTank(self: CycleState, owner: any, levels: { [string]: any }?): (boolean, string?)
	if not isKey(owner) then
		return false, "badOwner"
	end
	if self.tanks[owner] then
		return false, "exists"
	end
	local clamped = {}
	for id in pairs(self.config.Upgrades) do
		clamped[id] = Upgrades.clampLevel(self.config, id, levels and levels[id])
	end
	self.tanks[owner] = { owner = owner, levels = clamped, count = 0, reserved = 0, lastReleaseAt = -math.huge }
	return true, nil
end

function CycleState.registerRod(self: CycleState, rodId: any, owner: any): (boolean, string?)
	if not isKey(rodId) then
		return false, "badRod"
	end
	if not self.tanks[owner] then
		return false, "noTank"
	end
	if self.rods[rodId] then
		return false, "exists"
	end
	self.rods[rodId] = { id = rodId, owner = owner, phase = "Idle", castAt = 0, hookedAt = 0, fishId = nil }
	return true, nil
end

-- ---------------------------------------------------------------- casting

local function ownedRod(self: CycleState, owner: any, rodId: any): (Rod?, string?)
	local rod = self.rods[rodId]
	if not rod then
		return nil, "noRod"
	end
	if rod.owner ~= owner then
		return nil, "notOwner"
	end
	return rod, nil
end

-- Starts a cast and reserves one tank slot for its eventual catch.
function CycleState.beginCast(self: CycleState, owner: any, rodId: any, now: number): (boolean, string?)
	if not isTime(now) then
		return false, "badTime"
	end
	local rod, err = ownedRod(self, owner, rodId)
	if not rod then
		return false, err
	end
	if rod.phase ~= "Idle" then
		return false, "busy"
	end
	if self:freeSlots(owner) < 1 then
		return false, "tankFull"
	end
	local tank = self.tanks[owner]
	tank.reserved += 1
	rod.phase = "Waiting"
	rod.castAt = now
	return true, nil
end

-- Hooks a specific river fish on a waiting rod. The server picks the fish;
-- clients never name fish ids.
function CycleState.hookFish(self: CycleState, owner: any, rodId: any, fishId: any, now: number): (boolean, string?)
	if not isTime(now) or not isId(fishId) then
		return false, "badArgs"
	end
	local rod, err = ownedRod(self, owner, rodId)
	if not rod then
		return false, err
	end
	if rod.phase ~= "Waiting" then
		return false, "notWaiting"
	end
	if now < rod.castAt + self.config.BiteSeconds then
		return false, "tooSoon"
	end
	local fish = self.fish[fishId]
	if not fish or fish.location ~= "River" then
		return false, "fishUnavailable"
	end
	fish.location = "Hooked"
	fish.rodId = rodId
	rod.phase = "Hooked"
	rod.hookedAt = now
	rod.fishId = fishId
	return true, nil
end

-- Lands a hooked fish in the owner's tank, consuming the reserved slot.
function CycleState.landCatch(self: CycleState, owner: any, rodId: any, now: number): (boolean, string?, number?)
	if not isTime(now) then
		return false, "badTime", nil
	end
	local rod, err = ownedRod(self, owner, rodId)
	if not rod then
		return false, err, nil
	end
	if rod.phase ~= "Hooked" or not rod.fishId then
		return false, "notHooked", nil
	end
	if now < rod.hookedAt + self.config.LiftSeconds then
		return false, "tooSoon", nil
	end
	local fish = self.fish[rod.fishId]
	local tank = self.tanks[owner]
	fish.location = "Tank"
	fish.rodId = nil
	fish.owner = owner
	tank.reserved -= 1
	tank.count += 1
	local id = rod.fishId
	rod.phase = "Idle"
	rod.fishId = nil
	return true, nil, id
end

-- Cancels a cast: a hooked fish goes back to the river and the slot is freed.
-- Returns the fish id that was put back, if any.
function CycleState.cancelCast(self: CycleState, rodId: any): number?
	local rod = self.rods[rodId]
	if not rod or rod.phase == "Idle" then
		return nil
	end
	local returned = nil
	if rod.fishId then
		local fish = self.fish[rod.fishId]
		fish.location = "River"
		fish.rodId = nil
		returned = rod.fishId
	end
	local tank = self.tanks[rod.owner]
	if tank then
		tank.reserved -= 1
	end
	rod.phase = "Idle"
	rod.fishId = nil
	return returned
end

-- ---------------------------------------------------------------- release

-- Sends up to ReleaseRate fish from the owner's tank back toward the river.
-- Returns the ids that started releasing.
function CycleState.release(self: CycleState, owner: any, now: number): (boolean, string?, { number })
	if not isTime(now) then
		return false, "badTime", {}
	end
	local tank = self.tanks[owner]
	if not tank then
		return false, "noTank", {}
	end
	if tank.count == 0 then
		return false, "empty", {}
	end
	if now < tank.lastReleaseAt + self.config.ReleaseCooldownSeconds then
		return false, "cooldown", {}
	end
	local batch = Upgrades.value(self.config, "ReleaseRate", tank.levels.ReleaseRate)
	local ids = {}
	-- Oldest fish first (lowest id), so order is deterministic.
	local inTank = {}
	for id, fish in pairs(self.fish) do
		if fish.location == "Tank" and fish.owner == owner then
			table.insert(inTank, id)
		end
	end
	table.sort(inTank)
	for i = 1, math.min(batch, #inTank) do
		local fish = self.fish[inTank[i]]
		fish.location = "Releasing"
		fish.readyAt = now + self.config.ReleaseSwimSeconds
		table.insert(ids, fish.id)
	end
	tank.count -= #ids
	tank.lastReleaseAt = now
	return true, nil, ids
end

-- ---------------------------------------------------------------- upgrades

-- Applies one level of an upgrade. Payment is NOT handled here: the caller
-- must have charged `cost` through its economy adapter first. Returns
-- (ok, reason, newLevel).
function CycleState.applyUpgrade(self: CycleState, owner: any, upgradeId: any): (boolean, string?, number?)
	local tank = self.tanks[owner]
	if not tank then
		return false, "noTank", nil
	end
	if type(upgradeId) ~= "string" or not self.config.Upgrades[upgradeId] then
		return false, "badUpgrade", nil
	end
	local level = tank.levels[upgradeId]
	if Upgrades.nextCost(self.config, upgradeId, level) == nil then
		return false, "max", level
	end
	tank.levels[upgradeId] = Upgrades.clampLevel(self.config, upgradeId, level + 1)
	return true, nil, tank.levels[upgradeId]
end

-- ---------------------------------------------------------------- time

-- Advances timers: expired casts are cancelled, released fish reach the
-- river. Returns events for the controller to render.
function CycleState.step(self: CycleState, now: number): { Event }
	local events: { Event } = {}
	if not isTime(now) then
		return events
	end
	for rodId, rod in pairs(self.rods) do
		if rod.phase == "Waiting" and now >= rod.castAt + self.config.CastTimeoutSeconds then
			self:cancelCast(rodId)
			table.insert(events, { kind = "CastExpired", rodId = rodId, owner = rod.owner })
		end
	end
	for id, fish in pairs(self.fish) do
		if fish.location == "Releasing" and fish.readyAt and now >= fish.readyAt then
			local owner = fish.owner
			fish.location = "River"
			fish.owner = nil
			fish.readyAt = nil
			table.insert(events, { kind = "ReturnedToRiver", fishId = id, owner = owner })
		end
	end
	return events
end

-- ---------------------------------------------------------------- cleanup

-- Owner left: cancel their casts, return every fish they hold to the river,
-- then forget their rods and tank. Returns the ids put back in the river.
function CycleState.removeOwner(self: CycleState, owner: any): { number }
	local returned = {}
	for rodId, rod in pairs(self.rods) do
		if rod.owner == owner then
			local id = self:cancelCast(rodId)
			if id then
				table.insert(returned, id)
			end
			self.rods[rodId] = nil
		end
	end
	for id, fish in pairs(self.fish) do
		if (fish.location == "Tank" or fish.location == "Releasing") and fish.owner == owner then
			fish.location = "River"
			fish.owner = nil
			fish.readyAt = nil
			table.insert(returned, id)
		end
	end
	self.tanks[owner] = nil
	table.sort(returned)
	return returned
end

-- System disabled/stopped: everyone's fish go back to the river.
function CycleState.shutdown(self: CycleState): { number }
	local owners = {}
	for owner in pairs(self.tanks) do
		table.insert(owners, owner)
	end
	local returned = {}
	for _, owner in ipairs(owners) do
		for _, id in ipairs(self:removeOwner(owner)) do
			table.insert(returned, id)
		end
	end
	table.sort(returned)
	return returned
end

-- ---------------------------------------------------------------- checks

-- Verifies internal consistency. Returns (ok, problem). Used by tests and
-- can be run in Studio debug builds.
function CycleState.checkInvariants(self: CycleState): (boolean, string?)
	local tankCounts, hookedByRod = {}, {}
	for id, fish in pairs(self.fish) do
		if fish.id ~= id then
			return false, "fish id mismatch " .. id
		end
		if fish.location == "Tank" then
			if not self.tanks[fish.owner] then
				return false, "tank fish without tank " .. id
			end
			tankCounts[fish.owner] = (tankCounts[fish.owner] or 0) + 1
		elseif fish.location == "Hooked" then
			local rod = self.rods[fish.rodId]
			if not rod or rod.fishId ~= id then
				return false, "hooked fish not on its rod " .. id
			end
			hookedByRod[fish.rodId] = id
		elseif fish.location == "Releasing" then
			if fish.readyAt == nil then
				return false, "releasing fish without readyAt " .. id
			end
		elseif fish.location ~= "River" then
			return false, "unknown location " .. tostring(fish.location)
		end
	end
	local reservedCounts = {}
	for rodId, rod in pairs(self.rods) do
		if rod.phase ~= "Idle" then
			reservedCounts[rod.owner] = (reservedCounts[rod.owner] or 0) + 1
		end
		if rod.phase == "Hooked" and hookedByRod[rodId] ~= rod.fishId then
			return false, "rod hooked fish mismatch " .. tostring(rodId)
		end
		if rod.phase ~= "Hooked" and rod.fishId ~= nil then
			return false, "idle/waiting rod holds a fish " .. tostring(rodId)
		end
	end
	for owner, tank in pairs(self.tanks) do
		if tank.count ~= (tankCounts[owner] or 0) then
			return false, "tank count drift for " .. tostring(owner)
		end
		if tank.reserved ~= (reservedCounts[owner] or 0) then
			return false, "reservation drift for " .. tostring(owner)
		end
		if tank.count + tank.reserved > self:capacity(owner) then
			return false, "over capacity for " .. tostring(owner)
		end
		for id, level in pairs(tank.levels) do
			if level ~= Upgrades.clampLevel(self.config, id, level) then
				return false, "unclamped level " .. id
			end
		end
	end
	return true, nil
end

return CycleState
