-- Server-simulated fish schools. Each plot keeps Config.Fish.PerPlot fish
-- swimming inside its FishZone. Fish are anchored parts moved in bulk at
-- Config.Fish.TickRate; their server positions are the ones used to verify
-- catch claims.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.FishTycoonShared
local Config = require(Shared.Config)
local Scene = require(Shared.Scene)

local Fish = {}

export type School = { x: number, z: number, tx: number, tz: number, members: number }

export type FishRecord = {
	id: number,
	part: BasePart,
	school: School,
	ox: number,
	oz: number,
	phase: number,
	state: string, -- "Swimming" | "Netted"
	position: Vector3, -- current world position
}

local COLORS = {
	Color3.fromRGB(255, 150, 70),
	Color3.fromRGB(250, 200, 80),
	Color3.fromRGB(120, 190, 255),
	Color3.fromRGB(240, 110, 110),
}

local nextId = 0
local rng = Random.new()

local function zoneInfo(plot)
	local zone: BasePart = plot.parts[Scene.Parts.FishZone]
	local margin = Config.Fish.SchoolSpread + 1
	local hx = math.max(1, zone.Size.X / 2 - margin)
	local hz = math.max(1, zone.Size.Z / 2 - margin)
	return zone, hx, hz
end

local function pickTarget(plot, school: School)
	local _, hx, hz = zoneInfo(plot)
	school.tx = rng:NextNumber(-hx, hx)
	school.tz = rng:NextNumber(-hz, hz)
end

-- Local (zone space) x/z -> world position on the water surface.
local function toWorld(zone: BasePart, lx: number, lz: number): Vector3
	local top = zone.Size.Y / 2 - Config.Fish.Depth
	return zone.CFrame:PointToWorldSpace(Vector3.new(lx, top, lz))
end

local function spawnFish(plot, school: School)
	local state = plot.fish
	nextId += 1
	local zone = zoneInfo(plot)

	local part = Instance.new("Part")
	part.Name = "Fish"
	part.Size = Vector3.new(0.8, 0.45, 1.8)
	part.Color = COLORS[rng:NextInteger(1, #COLORS)]
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part:SetAttribute("FishId", nextId)

	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(0.5, Config.Fish.SchoolSpread)
	local record: FishRecord = {
		id = nextId,
		part = part,
		school = school,
		ox = math.cos(angle) * radius,
		oz = math.sin(angle) * radius,
		phase = rng:NextNumber(0, math.pi * 2),
		state = "Swimming",
		position = toWorld(zone, school.x, school.z),
	}
	part.CFrame = CFrame.new(record.position)
	part.Parent = state.folder

	school.members += 1
	state.byId[record.id] = record
	state.count += 1
end

function Fish.initPlot(plot)
	local folder = Instance.new("Folder")
	folder.Name = "Fish"
	folder.Parent = plot.runtime

	plot.fish = { byId = {}, count = 0, schools = {}, folder = folder, respawnTimer = 0, clock = 0 }

	local _, hx, hz = zoneInfo(plot)
	local schoolCount = math.max(1, math.ceil(Config.Fish.PerPlot / Config.Fish.SchoolSize))
	for _ = 1, schoolCount do
		local school: School = { x = rng:NextNumber(-hx, hx), z = rng:NextNumber(-hz, hz), tx = 0, tz = 0, members = 0 }
		pickTarget(plot, school)
		table.insert(plot.fish.schools, school)
	end
	for i = 1, Config.Fish.PerPlot do
		spawnFish(plot, plot.fish.schools[(i - 1) % schoolCount + 1])
	end
end

local function emptiestSchool(plot): School
	local best = plot.fish.schools[1]
	for _, school in ipairs(plot.fish.schools) do
		if school.members < best.members then
			best = school
		end
	end
	return best
end

function Fish.step(plot, dt: number)
	local state = plot.fish
	state.clock += dt
	local zone = zoneInfo(plot)

	-- Respawn missing fish one at a time.
	if state.count < Config.Fish.PerPlot then
		state.respawnTimer += dt
		if state.respawnTimer >= Config.Fish.RespawnSeconds then
			state.respawnTimer = 0
			spawnFish(plot, emptiestSchool(plot))
		end
	else
		state.respawnTimer = 0
	end

	-- Move school centres toward their wander targets.
	for _, school in ipairs(state.schools) do
		local dx, dz = school.tx - school.x, school.tz - school.z
		local dist = math.sqrt(dx * dx + dz * dz)
		local step = Config.Fish.SchoolSpeed * dt
		if dist <= step then
			school.x, school.z = school.tx, school.tz
			pickTarget(plot, school)
		else
			school.x += dx / dist * step
			school.z += dz / dist * step
		end
	end

	local parts, cframes = {}, {}
	for _, record in pairs(state.byId) do
		if record.state == "Swimming" then
			local school = record.school
			local wobble = math.sin(state.clock * 2 + record.phase) * 0.6
			local lx = school.x + record.ox + wobble
			local lz = school.z + record.oz + math.cos(state.clock * 1.7 + record.phase) * 0.6
			local position = toWorld(zone, lx, lz)
			local heading = Vector3.new(school.tx - school.x, 0, school.tz - school.z)
			local worldHeading = zone.CFrame:VectorToWorldSpace(heading)
			local look = if worldHeading.Magnitude > 0.01 then position + worldHeading.Unit else position + zone.CFrame.LookVector
			record.position = position
			table.insert(parts, record.part)
			table.insert(cframes, CFrame.lookAt(position, look))
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Returns a swimming fish of this plot, or nil. Fish of other plots are never
-- found here, which is what enforces catch ownership.
function Fish.getSwimming(plot, id: number): FishRecord?
	local record = plot.fish.byId[id]
	if record and record.state == "Swimming" then
		return record
	end
	return nil
end

-- Moves a fish from the water into a net.
function Fish.take(plot, record: FishRecord)
	assert(record.state == "Swimming")
	record.state = "Netted"
	record.school.members -= 1
end

-- Puts a netted fish back into the water (e.g. net cancelled on death).
function Fish.release(plot, record: FishRecord)
	if plot.fish.byId[record.id] ~= record or record.state ~= "Netted" then
		return
	end
	record.state = "Swimming"
	record.school = emptiestSchool(plot)
	record.school.members += 1
end

-- Removes a netted fish for good (it was hauled onto the dock).
function Fish.remove(plot, record: FishRecord)
	if plot.fish.byId[record.id] ~= record then
		return
	end
	plot.fish.byId[record.id] = nil
	plot.fish.count -= 1
	record.part:Destroy()
end

return Fish
