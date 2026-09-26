-- Server side of the net sweep mechanic.
--
-- The net is anchored to a fixed dock marker (Scene.Parts.NetAnchor). The
-- client only sends intent: "cast", "steer the outer tip toward this point",
-- "these fish ids look like they are inside my net", "haul it in". The server
-- owns the whole state machine:
--
--   Idle      -> nothing cast. May still hold leftover fish from a previous
--                cycle that didn't fit anywhere on unload (never discarded).
--   Deploying -> timed (Config.Net.DeploySeconds); the rope drops into the
--                water. No sweeping or claims are accepted yet.
--   Sweeping  -> the player steers the tip. The enclosure is the circular
--                sector ("bag") between the anchor and the swept arc: fixed
--                radius (locked at cast time from the NetRadius stat), and an
--                angular span that may only grow in ONE direction once
--                established, so the bag can never fold over itself. This is
--                a deliberate simplification of the reference's free-form net
--                shape -- documented here per the project's "a simple
--                constrained sweep mechanic is fine if documented" allowance.
--   Hauling   -> timed (Config.Net.HaulSeconds); the sector visually shrinks
--                to the anchor. No new captures.
--   (auto)    -> on Hauling completion the server tries to unload: fish go
--                into the plot's grinder hopper first if the owner is near
--                NetReturn (the marker beside the grinder) and the hopper has
--                room, then any remainder onto the carry stack. Whatever still
--                doesn't fit stays IN THE NET (not lost) for the next cycle.
--
-- Fish ownership/ physics is entirely delegated to Fish.luau (take/release/
-- remove); this module only decides which fish ids are eligible.
--
-- Clamp-order proof (fixes the previous circle-then-rect bug): the tip must
-- stay within both the plot's water rectangle (fixed, convex) and a circle of
-- fixed radius centred on the anchor (convex). The anchor itself is clamped
-- into the rectangle once, at Deploy. Clamping RECT then CIRCLE (this file's
-- `clampTip`) is then provably exact in one pass: clampToRect(p) stays in the
-- rectangle; clampToCircle either leaves that point unchanged (already inside
-- the circle) or moves it along the straight line toward the anchor -- and
-- since both the rect-clamped point and the anchor are themselves inside the
-- (convex) rectangle, every point on that line, including the result, is too.
-- Because both the current tip and any freshly clamped target are therefore
-- always inside the convex intersection of the two shapes, and MaxSpeed-based
-- stepping (`Geometry.stepToward`) only ever moves along the straight segment
-- between them, the stepped position is provably inside that intersection as
-- well -- so a target clamp followed by a bounded step can never need a
-- further correction to satisfy either bound, and the applied displacement is
-- bounded by construction rather than checked after the fact.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.FishTycoonShared
local Config = require(Shared.Config)
local Scene = require(Shared.Scene)
local Geometry = require(Shared.Geometry)
local GeometryAngle = require(Shared.GeometryAngle)
local GameRules = require(Shared.GameRules)
local Validate = require(Shared.Validate)
local RateLimiter = require(Shared.RateLimiter)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local Fish = require(script.Parent.Fish)
local Plots = require(script.Parent.Plots)
local Grinder = require(script.Parent.Grinder)
local Notifier = require(script.Parent.Notifier)
local NetVisual = require(script.Parent.NetVisual)

local Net = {}

local limiters = {}
for name, limit in pairs(Config.RateLimits) do
	limiters[name] = RateLimiter.new(limit.Rate, limit.Burst)
end

local function zoneOf(plot): BasePart
	return plot.parts[Scene.Parts.FishZone]
end

local function toLocal(zone: BasePart, worldPos: Vector3): (number, number)
	local lp = zone.CFrame:PointToObjectSpace(worldPos)
	return lp.X, lp.Z
end

-- Local (zone space) x/z -> world position just above the water surface.
local function toWorld(zone: BasePart, lx: number, lz: number): Vector3
	local top = zone.Size.Y / 2 + 0.12
	return zone.CFrame:PointToWorldSpace(Vector3.new(lx, top, lz))
end

local function planarDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- See the file header for why one rect-then-circle pass is exact here.
local function clampTip(zone: BasePart, ax: number, az: number, x: number, z: number, radius: number): (number, number)
	x, z = Geometry.clampToRect(x, z, zone.Size.X / 2, zone.Size.Z / 2)
	x, z = Geometry.clampToCircle(x, z, ax, az, radius)
	return x, z
end

function Net.initPlot(plot)
	plot.net = NetVisual.create(plot.runtime)
end

-- Moves netted fish onto the carry stack. Returns (moved, leftInNet).
local function haulIntoCarry(state): (number, number)
	local net = state.net
	local capacity = PlayerData.intStat(state, "CarryCapacity")
	local moved, left = GameRules.haul(#net.netted, state.carry, capacity)
	for _ = 1, moved do
		local record = table.remove(net.netted)
		Fish.remove(state.plot, record)
	end
	return moved, left
end

-- Puts every currently-netted fish back into the water. Used for death,
-- leaving, and plot release -- the one case where excess fish are not kept.
local function releaseNetted(state)
	local net = state.net
	for _, record in ipairs(net.netted) do
		Fish.release(state.plot, record)
	end
	table.clear(net.netted)
end

local function resetToIdle(net)
	net.phase = "Idle"
	net.timer = 0
	net.sweepDir = 0
	net.startedAngle = false
end

-- Tries to unload netted fish: grinder hopper first (only if the owner is
-- standing near NetReturn and the hopper has room), then the carry stack.
-- Whatever still doesn't fit stays in net.netted -- nothing is discarded.
local function finishUnload(state)
	local plot = state.plot
	local net = state.net
	local player = state.player
	local depositedToGrinder = 0

	local root = PlayerData.aliveRoot(state)
	local nearGrinder = root and planarDist(root.Position, plot.parts[Scene.Parts.NetReturn].Position) <= Config.Net.ReturnReach
	if nearGrinder then
		local grinder = plot.grinder
		local storage = Grinder.storage(plot)
		while #net.netted > 0 and grinder.input < storage do
			local record = table.remove(net.netted)
			Fish.remove(plot, record)
			grinder.input += 1
			depositedToGrinder += 1
		end
		if depositedToGrinder > 0 then
			Grinder.refresh(plot)
		end
	end

	local movedToCarry = 0
	if #net.netted > 0 then
		movedToCarry = haulIntoCarry(state)
	end

	resetToIdle(net)

	local leftInNet = #net.netted
	if depositedToGrinder > 0 or movedToCarry > 0 then
		local parts = {}
		if depositedToGrinder > 0 then
			table.insert(parts, string.format("%d into the grinder", depositedToGrinder))
		end
		if movedToCarry > 0 then
			table.insert(parts, string.format("%d onto your back", movedToCarry))
		end
		Notifier.send(player, "success", "Unloaded " .. table.concat(parts, " and ") .. "!")
	elseif leftInNet == 0 then
		Notifier.send(player, "info", "Empty net.")
	end
	if leftInNet > 0 then
		Notifier.send(
			player,
			"warn",
			string.format("Net still holds %d fish - make room (hopper/carry) and haul again.", leftInNet),
			"netexcess"
		)
	end
	PlayerData.commit(state)
end

-- Ends whatever phase is active immediately and attempts to unload. Used when
-- a player wanders past the sweep leash instead of hauling normally.
local function forceFinish(state, reason: string)
	Notifier.send(state.player, "warn", reason, "netleash")
	finishUnload(state)
end

-- Cancel is the destructive path (death/leave/plot release): every netted
-- fish swims back into the water rather than being retained.
function Net.cancel(state)
	local net = state.net
	if net.phase == "Idle" and #net.netted == 0 then
		return
	end
	if state.plot then
		releaseNetted(state)
	end
	resetToIdle(net)
	PlayerData.commit(state)
end

local function onStart(player: Player)
	if not limiters.NetStart:allow(player, os.clock()) then
		return
	end
	local state = PlayerData.get(player)
	if not (state and state.plot) or state.net.phase ~= "Idle" then
		return
	end
	local root = PlayerData.aliveRoot(state)
	if not root then
		return
	end
	local plot = state.plot
	local anchorPart = plot.parts[Scene.Parts.NetAnchor]
	if planarDist(root.Position, anchorPart.Position) > Config.Net.AnchorReach then
		Notifier.send(player, "warn", "Stand next to the net spool at the dock to cast.", "cast")
		return
	end

	local zone = zoneOf(plot)
	local ax, az = toLocal(zone, anchorPart.Position)
	-- Defensive: the anchor should already sit inside the water footprint by
	-- construction, but the clamp proof above depends on it, so enforce it.
	ax, az = Geometry.clampToRect(ax, az, zone.Size.X / 2, zone.Size.Z / 2)

	local net = state.net
	net.ax, net.az = ax, az
	net.anchorWorld = anchorPart.Position
	net.radius = PlayerData.stat(state, "NetRadius") -- locked for this whole cast
	net.tx, net.tz = ax, az
	net.startAngle, net.currentAngle = 0, 0
	net.sweepDir = 0
	net.startedAngle = false
	net.lastMove = os.clock()
	net.phase = "Deploying"
	net.timer = Config.Net.DeploySeconds
	PlayerData.commit(state)
end

local function onMove(player: Player, target: any)
	local now = os.clock()
	if not limiters.NetMove:allow(player, now) then
		return
	end
	if not Validate.vector3(target) then
		return
	end
	local state = PlayerData.get(player)
	if not (state and state.plot and state.net.phase == "Sweeping") then
		return
	end
	local root = PlayerData.aliveRoot(state)
	if not root then
		return
	end
	local net = state.net
	if planarDist(root.Position, net.anchorWorld) > Config.Net.SweepLeash then
		return -- the periodic step check will finish the cast; ignore this move
	end

	local plot = state.plot
	local zone = zoneOf(plot)
	local dt = math.clamp(now - net.lastMove, 0, 0.25)
	net.lastMove = now

	local tx, tz = toLocal(zone, target)
	tx, tz = clampTip(zone, net.ax, net.az, tx, tz, net.radius)
	local nx, nz = Geometry.stepToward(net.tx, net.tz, tx, tz, Config.Net.MaxSpeed * dt)
	-- Defensive re-clamp: not required by the proof above, kept only to
	-- absorb floating-point drift across many frames.
	nx, nz = clampTip(zone, net.ax, net.az, nx, nz, net.radius)

	local dx, dz = nx - net.ax, nz - net.az
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist > 0.05 then
		local newAngle = math.atan2(dz, dx)
		local angleForTip = net.currentAngle
		if not net.startedAngle then
			net.startAngle, net.currentAngle = newAngle, newAngle
			net.startedAngle = true
			angleForTip = newAngle
		else
			local deadzone = math.rad(Config.Net.SweepDeadzoneDegrees)
			local rawDelta = GeometryAngle.delta(net.currentAngle, newAngle)
			if net.sweepDir == 0 then
				if math.abs(rawDelta) >= deadzone then
					net.sweepDir = if rawDelta > 0 then 1 else -1
					net.currentAngle = newAngle
				end
			else
				local sameDir = (rawDelta >= 0) == (net.sweepDir > 0)
				if sameDir or math.abs(rawDelta) < deadzone then
					local maxSpan = math.rad(Config.Net.MaxSweepDegrees)
					local proposedTotal = GeometryAngle.delta(net.startAngle, newAngle)
					if math.abs(proposedTotal) > maxSpan then
						net.currentAngle = net.startAngle + maxSpan * net.sweepDir
					else
						net.currentAngle = newAngle
					end
				end
				-- else: a reversal past the deadzone would fold the bag over
				-- itself, so the angle change is rejected outright.
			end
			angleForTip = net.currentAngle
		end
		nx = net.ax + math.cos(angleForTip) * dist
		nz = net.az + math.sin(angleForTip) * dist
		nx, nz = clampTip(zone, net.ax, net.az, nx, nz, net.radius)
	end
	net.tx, net.tz = nx, nz
end

local function onClaim(player: Player, ids: any)
	local now = os.clock()
	if not limiters.NetClaim:allow(player, now) then
		return
	end
	local list = Validate.idArray(ids, Config.MaxClaimIdsPerCall)
	if not list then
		return
	end
	local state = PlayerData.get(player)
	if not (state and state.plot and state.net.phase == "Sweeping") then
		return
	end
	local root = PlayerData.aliveRoot(state)
	if not root then
		return
	end
	local net = state.net
	if planarDist(root.Position, net.anchorWorld) > Config.Net.SweepLeash then
		return
	end
	local plot = state.plot
	local zone = zoneOf(plot)
	local capacity = PlayerData.intStat(state, "NetCapacity")
	local radiusSq = (net.radius + Config.Net.CatchTolerance) ^ 2
	local angleTolerance = math.rad(2)
	local caught = 0
	for _, id in ipairs(list) do
		if #net.netted >= capacity then
			Notifier.send(player, "warn", "Net is full! Haul it in.", "netfull")
			break
		end
		local record = Fish.getSwimming(plot, id)
		if record then
			local flx, flz = toLocal(zone, record.position)
			local dx, dz = flx - net.ax, flz - net.az
			local distSq = dx * dx + dz * dz
			if distSq <= radiusSq then
				local angle = math.atan2(dz, dx)
				if GeometryAngle.withinArc(angle, net.startAngle, net.currentAngle, angleTolerance) then
					Fish.take(plot, record)
					table.insert(net.netted, record)
					caught += 1
				end
			end
		end
	end
	if caught > 0 then
		PlayerData.commit(state)
	end
end

local function onHaul(player: Player)
	if not limiters.NetHaul:allow(player, os.clock()) then
		return
	end
	local state = PlayerData.get(player)
	if not (state and state.plot and state.net.phase == "Sweeping") then
		return
	end
	local root = PlayerData.aliveRoot(state)
	if not root then
		return
	end
	local net = state.net
	if planarDist(root.Position, net.anchorWorld) > Config.Net.SweepLeash then
		return
	end
	net.phase = "Hauling"
	net.timer = Config.Net.HaulSeconds
	PlayerData.commit(state)
end

-- Redraws the rope lattice and bunches any currently-netted fish. Called
-- every tick for every plot with an owner, regardless of phase, so leftover
-- fish retained from a previous cycle stay visible at the anchor.
local function updateVisual(plot, net)
	local zone = zoneOf(plot)
	local displayRadius = 0
	if net.phase == "Deploying" then
		displayRadius = net.radius * (1 - net.timer / Config.Net.DeploySeconds)
	elseif net.phase == "Sweeping" then
		displayRadius = net.radius
	elseif net.phase == "Hauling" then
		displayRadius = net.radius * (net.timer / Config.Net.HaulSeconds)
	end
	displayRadius = math.max(displayRadius, 0)

	if net.ax then
		NetVisual.update(plot.net, function(lx, lz)
			return toWorld(zone, lx, lz)
		end, net.ax, net.az, displayRadius, net.startAngle, net.currentAngle, net.phase ~= "Idle")
	end

	local count = #net.netted
	if count == 0 or not net.ax then
		return
	end
	local spread = math.max(displayRadius * 0.5, 1.2)
	local parts, cframes = {}, {}
	for i, record in ipairs(net.netted) do
		local angle = i * 2.399963 -- golden angle spreads fish evenly
		local r = spread * math.sqrt(i / count)
		local position = toWorld(zone, net.ax + math.cos(angle) * r, net.az + math.sin(angle) * r)
		table.insert(parts, record.part)
		table.insert(cframes, CFrame.new(position) * CFrame.Angles(0, angle, 0))
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Advances every player's timed net phases and leash checks. Call once per
-- server heartbeat with the frame's dt.
function Net.step(dt: number)
	for _, state in pairs(PlayerData.all()) do
		local plot = state.plot
		if not plot then
			continue
		end
		local net = state.net
		if net.phase ~= "Idle" then
			local root = PlayerData.aliveRoot(state)
			if not root then
				Net.cancel(state)
			elseif planarDist(root.Position, net.anchorWorld) > Config.Net.SweepLeash then
				forceFinish(state, "Wandered too far from the net - hauling it in.")
			elseif net.phase == "Deploying" then
				net.timer -= dt
				if net.timer <= 0 then
					net.phase = "Sweeping"
				end
			elseif net.phase == "Hauling" then
				net.timer -= dt
				if net.timer <= 0 then
					finishUnload(state)
				end
			end
		end
		updateVisual(plot, state.net)
	end
end

function Net.forget(player: Player)
	for _, limiter in pairs(limiters) do
		limiter:forget(player)
	end
end

function Net.connectRemotes()
	Remotes.get("NetStart").OnServerEvent:Connect(onStart)
	Remotes.get("NetMove").OnServerEvent:Connect(onMove)
	Remotes.get("NetClaim").OnServerEvent:Connect(onClaim)
	Remotes.get("NetHaul").OnServerEvent:Connect(onHaul)
end

return Net
