-- Server side of the net sweep mechanic.
--
-- The client only sends intent: "cast", "steer toward this point", "these fish
-- ids look like they are in my net", "haul". The server:
--   * requires the character to be alive and standing in its own plot's FishingArea,
--   * moves the net toward the steering target at no more than Net.MaxSpeed,
--     clamped to Net.Reach from the character and to the plot's FishZone,
--   * records each swept segment with its speed,
--   * accepts a claimed fish only if it is a swimming fish of the owner's plot
--     whose server position lies within the net radius (+ latency tolerance)
--     of a recent segment swept faster than Net.MinSweepSpeed, and only while
--     the net has capacity left,
--   * on haul, moves netted fish onto the carried stack up to carry capacity;
--     anything that does not fit stays in the net.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.FishTycoonShared
local Config = require(Shared.Config)
local Scene = require(Shared.Scene)
local Geometry = require(Shared.Geometry)
local GameRules = require(Shared.GameRules)
local Validate = require(Shared.Validate)
local RateLimiter = require(Shared.RateLimiter)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local Fish = require(script.Parent.Fish)
local Plots = require(script.Parent.Plots)
local Notifier = require(script.Parent.Notifier)

local Net = {}

local MAX_SEGMENTS = 64
local ROPE_ATTACHMENT = "FishTycoonNetRope"

local limiters = {}
for name, limit in pairs(Config.RateLimits) do
	limiters[name] = RateLimiter.new(limit.Rate, limit.Burst)
end

local function zoneOf(plot): BasePart
	return plot.parts[Scene.Parts.FishZone]
end

local function waterPoint(plot, x: number, z: number): Vector3
	local zone = zoneOf(plot)
	local lp = zone.CFrame:PointToObjectSpace(Vector3.new(x, zone.Position.Y, z))
	return zone.CFrame:PointToWorldSpace(Vector3.new(lp.X, zone.Size.Y / 2 + 0.1, lp.Z))
end

-- Clamps a desired net centre to the character's reach and the fishing bounds.
-- The fishing bounds are applied last, so the net can never leave the water zone.
local function clampNet(plot, root: BasePart, x: number, z: number): (number, number)
	x, z = Geometry.clampToCircle(x, z, root.Position.X, root.Position.Z, Config.Net.Reach)
	local zone = zoneOf(plot)
	local lp = zone.CFrame:PointToObjectSpace(Vector3.new(x, zone.Position.Y, z))
	local lx, lz = Geometry.clampToRect(lp.X, lp.Z, zone.Size.X / 2, zone.Size.Z / 2)
	local world = zone.CFrame:PointToWorldSpace(Vector3.new(lx, 0, lz))
	return world.X, world.Z
end

local function inFishingArea(plot, root: BasePart): boolean
	return Plots.isOnPad(plot.parts[Scene.Parts.FishingArea], root.Position, Config.Net.FishingAreaMargin)
end

local function ropeAttachment(root: BasePart): Attachment
	local existing = root:FindFirstChild(ROPE_ATTACHMENT)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = ROPE_ATTACHMENT
	attachment.Position = Vector3.new(0.8, 0.5, -0.6)
	attachment.Parent = root
	return attachment
end

-- Places the net disc and arranges the fish it holds.
local function drawNet(plot, state)
	local net = state.net
	local visual = plot.net
	local radius = PlayerData.stat(state, "NetRadius")
	local centre = waterPoint(plot, net.x, net.z)
	visual.part.Size = Vector3.new(0.2, radius * 2, radius * 2)
	visual.part.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.pi / 2)

	local parts, cframes = {}, {}
	local count = #net.netted
	for i, record in ipairs(net.netted) do
		local angle = i * 2.39996 -- golden angle spreads fish evenly
		local r = radius * 0.65 * math.sqrt(i / math.max(count, 1))
		local position = centre + Vector3.new(math.cos(angle) * r, 0.35, math.sin(angle) * r)
		table.insert(parts, record.part)
		table.insert(cframes, CFrame.new(position) * CFrame.Angles(0, angle, 0))
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function setVisible(plot, state, visible: boolean)
	local visual = plot.net
	visual.part.Transparency = if visible then 0.45 else 1
	visual.beam.Enabled = false
	if visible then
		local root = PlayerData.aliveRoot(state)
		if root then
			visual.beam.Attachment0 = ropeAttachment(root)
			visual.beam.Enabled = true
		end
	else
		visual.beam.Attachment0 = nil
	end
end

local function deactivate(state)
	local net = state.net
	net.active = false
	table.clear(net.segments)
	if state.plot then
		setVisible(state.plot, state, false)
	end
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

local function releaseNetted(state): number
	local net = state.net
	local released = #net.netted
	for _, record in ipairs(net.netted) do
		Fish.release(state.plot, record)
	end
	table.clear(net.netted)
	return released
end

function Net.initPlot(plot)
	local part = Instance.new("Part")
	part.Name = "Net"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(235, 240, 250)
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 6, 6)
	part.CFrame = CFrame.new(waterPoint(plot, zoneOf(plot).Position.X, zoneOf(plot).Position.Z))

	local attachment = Instance.new("Attachment")
	attachment.Name = "RopeEnd"
	attachment.Parent = part

	local beam = Instance.new("Beam")
	beam.Name = "Rope"
	beam.Attachment1 = attachment
	beam.Width0 = 0.15
	beam.Width1 = 0.15
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(Color3.fromRGB(120, 85, 50))
	beam.Enabled = false
	beam.Parent = part

	part.Parent = plot.runtime
	plot.net = { part = part, beam = beam }
end

-- Ends the sweep and puts any netted fish back in the water. Used on death,
-- leaving the game and when a plot is released.
function Net.cancel(state)
	if not state.net.active and #state.net.netted == 0 then
		return
	end
	if state.plot then
		releaseNetted(state)
	end
	deactivate(state)
	PlayerData.commit(state)
end

-- Hauls what fits; fish that do not fit are returned to the water with a
-- message (used when the owner walks off the fishing strip).
local function finish(state, reason: string)
	local moved, left = haulIntoCarry(state)
	if left > 0 then
		releaseNetted(state)
		Notifier.send(state.player, "warn", string.format("%s: carry full, %d fish swam back into the water.", reason, left))
	elseif moved > 0 then
		Notifier.send(state.player, "success", string.format("Hauled in %d fish!", moved))
	end
	deactivate(state)
	PlayerData.commit(state)
end

local function onStart(player: Player)
	if not limiters.NetStart:allow(player, os.clock()) then
		return
	end
	local state = PlayerData.get(player)
	if not (state and state.plot) or state.net.active then
		return
	end
	local root = PlayerData.aliveRoot(state)
	if not root then
		return
	end
	local plot = state.plot
	if not inFishingArea(plot, root) then
		Notifier.send(player, "warn", "Stand on the blue fishing strip at the dock edge to cast.", "cast")
		return
	end
	local net = state.net
	net.x, net.z = clampNet(plot, root, root.Position.X, root.Position.Z)
	net.lastMove = os.clock()
	net.active = true
	table.clear(net.segments)
	setVisible(plot, state, true)
	drawNet(plot, state)
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
	if not (state and state.plot and state.net.active) then
		return
	end
	local root = PlayerData.aliveRoot(state)
	if not root then
		return
	end
	local plot = state.plot
	local net = state.net

	-- Speed constraint: the net may only travel MaxSpeed * elapsed time.
	local dt = math.clamp(now - net.lastMove, 0, 0.25)
	net.lastMove = now
	local tx, tz = clampNet(plot, root, target.X, target.Z)
	local nx, nz = Geometry.stepToward(net.x, net.z, tx, tz, Config.Net.MaxSpeed * dt)
	nx, nz = clampNet(plot, root, nx, nz)

	local dx, dz = nx - net.x, nz - net.z
	local speed = if dt > 1e-3 then math.sqrt(dx * dx + dz * dz) / dt else 0
	if speed >= Config.Net.MinSweepSpeed then
		table.insert(net.segments, { ax = net.x, az = net.z, bx = nx, bz = nz, t = now, speed = speed })
		if #net.segments > MAX_SEGMENTS then
			table.remove(net.segments, 1)
		end
	end
	net.x, net.z = nx, nz
	drawNet(plot, state)
end

local function recentlySwept(state, position: Vector3, now: number): boolean
	local radius = PlayerData.stat(state, "NetRadius") + Config.Net.CatchTolerance
	local radiusSq = radius * radius
	for i = #state.net.segments, 1, -1 do
		local seg = state.net.segments[i]
		if now - seg.t > Config.Net.HistorySeconds then
			break
		end
		if Geometry.pointSegmentDistSq(position.X, position.Z, seg.ax, seg.az, seg.bx, seg.bz) <= radiusSq then
			return true
		end
	end
	return false
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
	if not (state and state.plot and state.net.active) then
		return
	end
	local plot = state.plot
	local net = state.net
	local capacity = PlayerData.intStat(state, "NetCapacity")
	local caught = 0
	for _, id in ipairs(list) do
		if #net.netted >= capacity then
			Notifier.send(player, "warn", "Net is full! Haul it in (E / HAUL).", "netfull")
			break
		end
		local record = Fish.getSwimming(plot, id)
		if record and recentlySwept(state, record.position, now) then
			Fish.take(plot, record)
			table.insert(net.netted, record)
			caught += 1
		end
	end
	if caught > 0 then
		drawNet(plot, state)
		PlayerData.commit(state)
	end
end

local function onHaul(player: Player)
	if not limiters.NetHaul:allow(player, os.clock()) then
		return
	end
	local state = PlayerData.get(player)
	if not (state and state.plot and state.net.active) then
		return
	end
	local moved, left = haulIntoCarry(state)
	if left > 0 then
		-- Keep the net out with the remaining fish rather than discarding them.
		Notifier.send(
			player,
			"warn",
			string.format("Carry full! %d fish still in the net. Drop fish at the grinder hopper first.", left)
		)
		drawNet(state.plot, state)
	else
		if moved > 0 then
			Notifier.send(player, "success", string.format("Hauled in %d fish!", moved))
		else
			Notifier.send(player, "info", "Empty net. Sweep it through a school of fish.")
		end
		deactivate(state)
	end
	PlayerData.commit(state)
end

-- Periodic check: a net whose owner died, despawned or left the fishing strip
-- is hauled in (or cancelled when there is no character).
function Net.step(now: number)
	for _, state in pairs(PlayerData.all()) do
		if state.net.active and state.plot then
			local root = PlayerData.aliveRoot(state)
			if not root then
				Net.cancel(state)
			elseif not inFishingArea(state.plot, root) then
				finish(state, "Left the fishing strip")
			else
				-- Drop expired history so memory stays bounded while idle.
				local segments = state.net.segments
				while segments[1] and now - segments[1].t > Config.Net.HistorySeconds do
					table.remove(segments, 1)
				end
			end
		end
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
