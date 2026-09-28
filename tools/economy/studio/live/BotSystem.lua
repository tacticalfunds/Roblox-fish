-- The Blender Bot waddles between the meat stack (end of the conveyor) and the sale table,
-- carrying one piece of meat at a time and laying it on the table for customers.
local RunService = game:GetService("RunService")
local SS = game:GetService("ServerStorage")

local bot = workspace:WaitForChild("Blender Bot")
local meatStack = workspace:WaitForChild("MeatStack")
local saleMeat = workspace:WaitForChild("SaleMeat")
local saleTable = workspace:WaitForChild("SaleTable")
local meatTemplate = SS:WaitForChild("MeatTemplate")

local SPEED = 7
local GROUND = 8.75
local groundOff = bot:GetAttribute("GroundOffset") or 1.5
local PICK = Vector3.new(-84.3, GROUND, 160.2)   -- next to the meat box
local HOME = Vector3.new(-84.5, GROUND, 156)
local DROP_X = -85.6                               -- beside the sale table

local slots = {}
for i = 1, saleTable:GetAttribute("SlotCount") do slots[i] = saleTable:GetAttribute("Slot" .. i) end

local _, bsize = bot:GetBoundingBox()
local carryHeight = bsize.Y - groundOff + 0.6

local pos = Vector3.new(bot:GetPivot().X, GROUND, bot:GetPivot().Z)
local look = bot:GetPivot().LookVector
local carried = nil
local t = 0

local function pose(bob, roll)
	local p = pos + Vector3.new(0, groundOff + bob, 0)
	local cf = CFrame.lookAt(p, p + Vector3.new(look.X, 0, look.Z)) * CFrame.Angles(0, 0, math.rad(roll))
	bot:PivotTo(cf)
	if carried then
		carried.CFrame = CFrame.new(p + Vector3.new(0, carryHeight, 0)) * CFrame.lookAt(Vector3.zero, look).Rotation
	end
end

local function faceTo(target)
	local d = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
	if d.Magnitude > 0.01 then look = d.Unit end
end

local function walkTo(target)
	target = Vector3.new(target.X, GROUND, target.Z)
	faceTo(target)
	while (target - pos).Magnitude > 0.05 do
		local dt = RunService.Heartbeat:Wait()
		t += dt
		local d = target - pos
		pos += d.Unit * math.min(d.Magnitude, SPEED * dt)
		pose(math.abs(math.sin(t * 12)) * 0.35, math.sin(t * 12) * 7) -- little waddle
	end
end

local function idle(sec)
	local e = 0
	while e < sec do
		local dt = RunService.Heartbeat:Wait()
		e += dt t += dt
		pose(math.sin(t * 3) * 0.08, 0)
	end
end

local function arc(part, from, to, dur, height)
	local e = 0
	while e < dur do
		e += RunService.Heartbeat:Wait()
		local u = math.min(e / dur, 1)
		part.CFrame = CFrame.new(from:Lerp(to, u) + Vector3.new(0, height * 4 * u * (1 - u), 0)) * part.CFrame.Rotation
	end
end

local function topOfStack()
	local best, bi = nil, -1
	for _, m in ipairs(meatStack:GetChildren()) do
		local i = m:GetAttribute("StackIndex") or 0
		if i > bi then best, bi = m, i end
	end
	return best
end

local function freeSlot()
	local used = {}
	for _, m in ipairs(saleMeat:GetChildren()) do used[m:GetAttribute("Slot") or 0] = true end
	for i = 1, #slots do if not used[i] then return i end end
end

pose(0, 0)
while true do
	local slot = freeSlot()
	local meat = slot and topOfStack()
	if not meat then
		if (pos - HOME).Magnitude > 0.5 then walkTo(HOME) end
		faceTo(Vector3.new(-78, GROUND, 160))
		idle(0.6)
		continue
	end
	-- 1) go to the meat box and grab the top piece
	walkTo(PICK)
	faceTo(Vector3.new(-78, GROUND, PICK.Z))
	idle(0.2)
	meat = topOfStack()
	if not meat then continue end
	local from = meat.Position
	meat:Destroy()
	local c = meatTemplate:Clone()
	c.Name = "CarriedMeat"
	c.CFrame = CFrame.new(from)
	c.Parent = workspace
	arc(c, from, pos + Vector3.new(0, groundOff + carryHeight, 0), 0.25, 1.5)
	carried = c
	-- 2) waddle over to the table
	local target = slots[slot]
	walkTo(Vector3.new(DROP_X, GROUND, target.Z))
	faceTo(Vector3.new(target.X, GROUND, target.Z))
	idle(0.15)
	-- 3) put it on the table
	carried = nil
	c.Name = "Meat"
	c:SetAttribute("Slot", slot)
	arc(c, c.Position, target, 0.3, 1.2)
	c.CFrame = CFrame.new(target) * CFrame.Angles(0, math.rad(math.random(-10, 10)), 0)
	c.Parent = saleMeat
	idle(0.25)
end
