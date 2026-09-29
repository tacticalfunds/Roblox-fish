-- The Blender Bot waddles between the meat stack (end of the conveyor) and the sale table,
-- carrying one piece of meat at a time and laying it on the table for customers.
--
-- [Economy patch v1] Changes vs. the live script are marked "Economy".
-- The carried/table clone keeps the picked piece's identity (PieceId, owner,
-- variant, tier, value), so the customer sale pays the right owner once.
--
-- [Bot recovery patch] Each trip runs under pcall. If anything errors while
-- the bot holds a piece (between the stack and the table), the loose clone is
-- removed and the piece is held in the ledger: the grinder brings it back out
-- of the pipe, so it is never lost unpaid. The bot then carries on (it used to
-- stop for good). Changes are marked "Recovery".
local RunService = game:GetService("RunService")
local SS = game:GetService("ServerStorage")

local bot = workspace:WaitForChild("Blender Bot")
local meatStack = workspace:WaitForChild("MeatStack")
local saleMeat = workspace:WaitForChild("SaleMeat")
local saleTable = workspace:WaitForChild("SaleTable")
local meatTemplate = SS:WaitForChild("MeatTemplate")

-- Economy: optional money service (missing or not running -> original behaviour)
local Economy = nil
do
	local mod = game:GetService("ServerScriptService"):FindFirstChild("EconomyService")
	if mod and mod:IsA("ModuleScript") then
		local ok, api = pcall(require, mod)
		if ok and type(api) == "table" then
			local ran, running = pcall(api.start)
			if ran and running then
				Economy = api
			else
				warn("[BotSystem] economy not running, original behaviour: " .. tostring(running))
			end
		else
			warn("[BotSystem] could not load EconomyService, original behaviour: " .. tostring(api))
		end
	end
end

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

-- Recovery: the piece in the bot's hands, from leaving the stack until it lies
-- on the table ({ pieceId = id?, part = clone? })
local inHand = nil

local function trip()
	local slot = freeSlot()
	local meat = slot and topOfStack()
	if not meat then
		if (pos - HOME).Magnitude > 0.5 then walkTo(HOME) end
		faceTo(Vector3.new(-78, GROUND, 160))
		idle(0.6)
		return
	end
	-- 1) go to the meat box and grab the top piece
	walkTo(PICK)
	faceTo(Vector3.new(-78, GROUND, PICK.Z))
	idle(0.2)
	meat = topOfStack()
	if not meat then return end
	local from = meat.Position
	local tags = Economy and Economy.readPiece(meat) -- Economy: keep the piece's identity
	inHand = { pieceId = tags and tags.PieceId } -- Recovery
	meat:Destroy()
	local c = meatTemplate:Clone()
	inHand.part = c -- Recovery
	c.Name = "CarriedMeat"
	if tags then Economy.writePiece(c, tags) end
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
	inHand = nil -- Recovery: on the table, the customer sale takes it from here
	idle(0.25)
end

-- Recovery: whatever the bot was holding goes back to the ledger (held: the
-- grinder re-emits it), never lost unpaid. (Once it lies on the table inHand
-- is already nil: the customer sale takes it from there.)
local function recover()
	carried = nil
	local h = inHand
	inHand = nil
	if not h then return end
	if Economy and h.pieceId then
		pcall(Economy.hold, h.pieceId)
	end
	if h.part then pcall(function() h.part:Destroy() end) end
end

pose(0, 0)
local fails = 0
while true do
	local ok, err = pcall(trip)
	if ok then
		fails = 0
	else
		fails += 1
		recover()
		if fails == 1 or fails % 20 == 0 then
			warn("[BotSystem] trip failed (" .. fails .. "x), piece kept, retrying: " .. tostring(err))
		end
		task.wait(math.min(5, fails)) -- back off while something stays broken
	end
end
