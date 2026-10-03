-- A small fake Roblox engine for offline simulations of the REAL economy
-- scripts: Vector3/CFrame maths, instances with signals/attributes/Clone,
-- a virtual-clock scheduler with Heartbeat frames, remotes that know which
-- player's thread is calling, BindableEvents, and a ProximityPrompt model
-- (nearest-per-key within MaxActivationDistance, PromptShown/Hidden,
-- Triggered, InputHoldBegin). Scripts are loaded with loadstring + setfenv.
--
-- run_runtime_sim.py prepends SOURCES = { name = source } and this file to
-- each scenario file in tests/sim/. Fake engine only; not a Roblox runtime.

local SOURCES = SOURCES :: { [string]: string }
local realEnv = getfenv(1)
local realTypeof = typeof

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end
local errors = {}
local warnings = {}

------------------------------------------------------------ Vector3

local Vector3 = {}
local V3 = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return if m > 0 then v3(v.X / m, v.Y / m, v.Z / m) else v3(0 / 0, 0 / 0, 0 / 0)
	end
	return rawget(Vector3, k)
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("%g, %g, %g", v.X, v.Y, v.Z)
end
function Vector3.new(x, y, z)
	return v3(x, y, z)
end
function Vector3.Lerp(a, b, u)
	return a + (b - a) * u
end
function Vector3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

------------------------------------------------------------ CFrame
-- position p + rotation matrix rows r = { {r00,r01,r02}, {r10,...}, {r20,...} }

local CFrame = {}
local CF = {}
local function cf(p, r)
	return setmetatable({ p = p, r = r }, CF)
end
local I3 = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
local function matmul(a, b)
	local out = {}
	for i = 1, 3 do
		out[i] = {}
		for j = 1, 3 do
			out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return out
end
local function rotate(r, v)
	return v3(
		r[1][1] * v.X + r[1][2] * v.Y + r[1][3] * v.Z,
		r[2][1] * v.X + r[2][2] * v.Y + r[2][3] * v.Z,
		r[3][1] * v.X + r[3][2] * v.Y + r[3][3] * v.Z
	)
end
local function transpose(r)
	return {
		{ r[1][1], r[2][1], r[3][1] },
		{ r[1][2], r[2][2], r[3][2] },
		{ r[1][3], r[2][3], r[3][3] },
	}
end
CF.__index = function(c, k)
	if k == "Position" then
		return c.p
	elseif k == "Rotation" then
		return cf(v3(0, 0, 0), c.r)
	elseif k == "X" then
		return c.p.X
	elseif k == "Y" then
		return c.p.Y
	elseif k == "Z" then
		return c.p.Z
	elseif k == "LookVector" then
		return v3(-c.r[1][3], -c.r[2][3], -c.r[3][3])
	elseif k == "RightVector" then
		return v3(c.r[1][1], c.r[2][1], c.r[3][1])
	elseif k == "UpVector" then
		return v3(c.r[1][2], c.r[2][2], c.r[3][2])
	end
	return rawget(CFrame, k)
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		return a.p + rotate(a.r, b)
	end
	return cf(a.p + rotate(a.r, b.p), matmul(a.r, b.r))
end
CF.__add = function(a, v)
	return cf(a.p + v, a.r)
end
CF.__sub = function(a, v)
	return cf(a.p - v, a.r)
end
function CFrame.new(x, y, z)
	if getmetatable(x) == V3 then
		return cf(x, I3)
	end
	return cf(v3(x or 0, y or 0, z or 0), I3)
end
local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } }
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } }
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } }
end
function CFrame.Angles(x, y, z)
	return cf(v3(0, 0, 0), matmul(matmul(rx(x or 0), ry(y or 0)), rz(z or 0)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(x, y, z)
	return cf(v3(0, 0, 0), matmul(matmul(ry(y or 0), rx(x or 0)), rz(z or 0)))
end
function CFrame.lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at).Unit
	if look.X ~= look.X then
		return cf(at, I3)
	end
	local right = Vector3.Cross(look, up)
	if right.Magnitude < 1e-6 then
		right = Vector3.Cross(look, v3(0, 0, 1))
	end
	right = right.Unit
	local upv = Vector3.Cross(right, look)
	return cf(at, {
		{ right.X, upv.X, -look.X },
		{ right.Y, upv.Y, -look.Y },
		{ right.Z, upv.Z, -look.Z },
	})
end
function CFrame.Inverse(c)
	local t = transpose(c.r)
	return cf(-rotate(t, c.p), t)
end
function CFrame.ToEulerAnglesYXZ(c)
	local r = c.r
	local x = math.asin(math.clamp(-r[2][3], -1, 1))
	local y = math.atan2(r[1][3], r[3][3])
	local z = math.atan2(r[2][1], r[2][2])
	return x, y, z
end
function CFrame.Lerp(a, b, u)
	return cf(a.p + (b.p - a.p) * u, if u < 0.5 then a.r else b.r)
end
function CFrame.ToObjectSpace(a, b)
	return CFrame.Inverse(a) * b
end
function CFrame.ToWorldSpace(a, b)
	return a * b
end
function CFrame.fromAxisAngle(axis, angle)
	local u = axis.Unit
	local c, s, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
	local x, y, z = u.X, u.Y, u.Z
	return cf(v3(0, 0, 0), {
		{ t * x * x + c, t * x * y - s * z, t * x * z + s * y },
		{ t * x * y + s * z, t * y * y + c, t * y * z - s * x },
		{ t * x * z - s * y, t * y * z + s * x, t * z * z + c },
	})
end
function CFrame.PointToWorldSpace(c, v)
	return c * v
end
function CFrame.PointToObjectSpace(c, v)
	return CFrame.Inverse(c) * v
end
CFrame.identity = cf(v3(0, 0, 0), I3)

------------------------------------------------------------ other values

local function dummy(kind)
	return setmetatable({}, {
		__index = function(_, k)
			return function(...)
				return { kind = kind, ctor = k, args = { ... } }
			end
		end,
	})
end
-- UDim2 with the arithmetic GUI code uses (scale / offset per axis)
local U2 = {}
U2.__index = U2
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }, U2)
end
U2.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
U2.__eq = function(a, b)
	return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end
local UDim2 = {
	new = udim2,
	fromScale = function(x, y)
		return udim2(x, 0, y, 0)
	end,
	fromOffset = function(x, y)
		return udim2(0, x, 0, y)
	end,
}
local UDim = {
	new = function(scale, offset)
		return { Scale = scale or 0, Offset = offset or 0 }
	end,
}
local C3 = {}
C3.__index = C3
function C3:Lerp(other, u)
	return setmetatable({
		R = self.R + (other.R - self.R) * u,
		G = self.G + (other.G - self.G) * u,
		B = self.B + (other.B - self.B) * u,
	}, C3)
end
local Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
	end,
	fromRGB = function(r, g, b)
		return setmetatable({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }, C3)
	end,
}
local RaycastParams = {
	new = function()
		return {}
	end,
}
local ColorSequence, NumberSequence, NumberRange = dummy("ColorSequence"), dummy("NumberSequence"), dummy("NumberRange")
local NumberSequenceKeypoint, ColorSequenceKeypoint = dummy("NumberSequenceKeypoint"), dummy("ColorSequenceKeypoint")
local TweenInfo = dummy("TweenInfo")
local Vector2 = {
	new = function(x, y)
		return { X = x, Y = y }
	end,
}
Vector2.zero = Vector2.new(0, 0)
local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, t)
		enumCache[t] = enumCache[t]
			or setmetatable({}, {
				__index = function(tbl, n)
					local item = { EnumType = t, Name = n }
					rawset(tbl, n, item)
					return item
				end,
			})
		return enumCache[t]
	end,
})
-- seeded Random (the Luau CLI has none)
local Random = {}
Random.__index = Random
local seedCounter = 0
function Random.new(seed)
	seedCounter += 1
	return setmetatable({ s = (seed or seedCounter * 7919) % 2147483647 + 1 }, Random)
end
function Random:NextNumber(a, b)
	self.s = (self.s * 48271) % 2147483647
	local u = self.s / 2147483647
	if a == nil then
		return u
	end
	return a + (b - a) * u
end
function Random:NextInteger(a, b)
	return math.floor(self:NextNumber(a, b + 1 - 1e-9))
end

------------------------------------------------------------ scheduler

local now = 0
local FRAME = 1 / 30
local queue = {}
local seq = 0
local owners = setmetatable({}, { __mode = "k" })
local current: any = nil -- owner of the running thread: "server" or a Player

local function resume(co, ...)
	local prev = current
	current = owners[co]
	local ok, err = coroutine.resume(co, ...)
	current = prev
	if not ok then
		table.insert(errors, tostring(err))
		print("THREAD ERROR: " .. tostring(err))
	end
end
local function schedule(t, co, args)
	seq += 1
	table.insert(queue, { t = t, seq = seq, co = co, args = args or {} })
end
local function newThread(fn, owner)
	local co = coroutine.create(fn)
	owners[co] = owner
	return co
end
local task = {}
function task.spawn(fn, ...)
	local co = if type(fn) == "thread" then fn else newThread(fn, current)
	resume(co, ...)
	return co
end
function task.defer(fn, ...)
	schedule(now, newThread(fn, current), { ... })
end
function task.delay(t, fn, ...)
	schedule(now + (t or 0), newThread(fn, current), { ... })
end
function task.wait(t)
	local co = coroutine.running()
	local start = now
	schedule(now + math.max(t or 0, FRAME), co, {})
	coroutine.yield()
	return now - start
end
local function runAs(owner, fn, ...)
	local co = newThread(fn, owner)
	resume(co, ...)
	return co
end

------------------------------------------------------------ signals

local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ conns = {}, waiting = {} }, Signal)
end
function Signal:Connect(fn)
	local conn = { fn = fn, owner = current, connected = true, Connected = true }
	function conn.Disconnect()
		conn.connected = false
		conn.Connected = false
	end
	table.insert(self.conns, conn)
	return conn
end
Signal.connect = Signal.Connect
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		fn(...)
	end)
	return conn
end
function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end
-- only the handlers connected by `owner` (a prompt shown on one client)
function Signal:FireFor(owner, ...)
	for _, c in ipairs(table.clone(self.conns)) do
		if c.connected and c.owner == owner then
			resume(newThread(c.fn, c.owner), ...)
		end
	end
end
function Signal:Fire(...)
	for _, c in ipairs(table.clone(self.conns)) do
		if c.connected then
			resume(newThread(c.fn, c.owner), ...)
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, co in ipairs(waiting) do
		resume(co, ...)
	end
end

local Heartbeat = Signal.new()
local RenderStepped = Signal.new()

------------------------------------------------------------ instances

local EVENTS = {
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	AncestryChanged = true,
	Destroying = true,
	Activated = true,
	MouseButton1Click = true,
	MouseClick = true,
	Changed = true,
	PromptShown = true,
	PromptHidden = true,
	Triggered = true,
	InputBegan = true,
	InputEnded = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	CharacterAdded = true,
	Event = true,
	OnServerEvent = true,
	Touched = true,
	Died = true,
	AttributeChanged = true,
}
local ISA = {
	Part = { BasePart = true, PVInstance = true },
	MeshPart = { BasePart = true, PVInstance = true },
	UnionOperation = { BasePart = true, PVInstance = true },
	Model = { PVInstance = true },
	Workspace = { Model = true, PVInstance = true },
	TextButton = { GuiObject = true, GuiButton = true },
	ImageButton = { GuiObject = true, GuiButton = true },
	IntValue = { ValueBase = true },
	NumberValue = { ValueBase = true },
	TextLabel = { GuiObject = true },
	Frame = { GuiObject = true },
	ImageLabel = { GuiObject = true },
	Script = { BaseScript = true, LuaSourceContainer = true },
	LocalScript = { Script = true, BaseScript = true, LuaSourceContainer = true },
	ModuleScript = { LuaSourceContainer = true },
}
local DEFAULTS = {
	DataStoreGetOptions = { UseCache = true },
	ProximityPrompt = {
		Enabled = true,
		HoldDuration = 0,
		MaxActivationDistance = 10,
		RequiresLineOfSight = true,
		ObjectText = "",
		ActionText = "",
		KeyboardKeyCode = Enum.KeyCode.E, -- Roblox's defaults
		GamepadKeyCode = Enum.KeyCode.ButtonX,
	},
	Humanoid = { Health = 100, MaxHealth = 100 },
	Part = {
		Size = v3(1, 1, 1),
		Anchored = false,
		Transparency = 0,
		Color = setmetatable({ R = 0.6, G = 0.6, B = 0.6 }, C3),
	},
}
-- display properties a client can change locally on a server object
local LOCAL_PROPS = {
	SurfaceGui = { Enabled = true },
	BillboardGui = { Enabled = true },
	TextLabel = { Text = true, TextColor3 = true, Visible = true },
	TextButton = { Text = true, TextColor3 = true, Visible = true },
	UIStroke = { Color = true },
}
-- (only for objects in the Workspace: GUIs the sims build in a PlayerGui stand
-- for the client's own copies)
local function inWorkspace(o)
	local p = rawget(o, "_parent")
	while p do
		if rawget(p, "_props").ClassName == "Workspace" then
			return true
		end
		p = rawget(p, "_parent")
	end
	return false
end
local Inst = {}
local function isInst(x)
	return type(x) == "table" and getmetatable(x) == Inst
end
local function partCFrame(self)
	return rawget(self, "_props").CFrame or CFrame.identity
end
Inst.__index = function(self, k)
	local m = rawget(Inst, k)
	if m ~= nil then
		return m
	end
	if k == "Parent" then
		return rawget(self, "_parent")
	end
	local props = rawget(self, "_props")
	if k == "Position" and (props.CFrame or ISA[props.ClassName] and ISA[props.ClassName].BasePart) then
		return partCFrame(self).Position
	end
	if k == "Enabled" and props.ClassName == "ProximityPrompt" and isInst(current) then
		local localEnabled = rawget(self, "_localEnabled")
		if localEnabled and localEnabled[current] ~= nil then
			return localEnabled[current]
		end
	end
	-- a client's own change to a server object's display (see __newindex)
	local shown = rawget(self, "_localProps")
	if shown and isInst(current) and shown[current] and shown[current][k] ~= nil then
		return shown[current][k]
	end
	if k == "LocalPlayer" and props.ClassName == "Players" then
		return if isInst(current) then current else nil
	end
	if k == "OnClientEvent" then
		local per = rawget(self, "_client")
		per[current] = per[current] or Signal.new()
		return per[current]
	end
	if EVENTS[k] then
		local sigs = rawget(self, "_signals")
		sigs[k] = sigs[k] or Signal.new()
		return sigs[k]
	end
	local v = props[k]
	if v ~= nil then
		return v
	end
	return self:FindFirstChild(k)
end
local function fireAncestry(o)
	o.AncestryChanged:Fire(o, o.Parent)
	for _, c in ipairs(o._children) do
		fireAncestry(c)
	end
end
local function fireDescendantAdded(parent, child)
	local p = parent
	while p do
		local sig = rawget(p, "_signals").DescendantAdded
		if sig then
			sig:Fire(child)
		end
		p = rawget(p, "_parent")
	end
end
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old == v then
			return
		end
		if rawget(self, "_destroyed") and v ~= nil then
			error("The Parent property of " .. self.Name .. " is locked")
		end
		if old then
			for i, c in ipairs(old._children) do
				if c == self then
					table.remove(old._children, i)
					break
				end
			end
			old.ChildRemoved:Fire(self)
		end
		rawset(self, "_parent", v)
		if v then
			table.insert(v._children, self)
			v.ChildAdded:Fire(self)
			fireDescendantAdded(v, self)
		end
		fireAncestry(self)
		return
	end
	if k == "Enabled" and rawget(self, "_props").ClassName == "ProximityPrompt" and isInst(current) and rawget(self, "_owner") ~= current then
		-- like Roblox: a client-side change to a server prompt stays on that client
		local localEnabled = rawget(self, "_localEnabled") or {}
		rawset(self, "_localEnabled", localEnabled)
		localEnabled[current] = v
		return
	end
	local localKind = LOCAL_PROPS[rawget(self, "_props").ClassName]
	if localKind and localKind[k] and isInst(current) and rawget(self, "_owner") ~= current and inWorkspace(self) then
		-- like Roblox: a client changing what a server GUI shows changes it only for itself
		local shown = rawget(self, "_localProps") or {}
		rawset(self, "_localProps", shown)
		shown[current] = shown[current] or {}
		shown[current][k] = v
		return
	end
	if k == "Position" then
		local old = partCFrame(self)
		k, v = "CFrame", cf(v, old.r)
	end
	rawget(self, "_props")[k] = v
	self.Changed:Fire(k)
end
local function new(className, name)
	local o = setmetatable({
		_props = { ClassName = className, Name = name or className },
		_children = {},
		_attrs = {},
		_signals = {},
		_client = {},
		_attrSignals = {},
		_owner = current,
	}, Inst)
	for k, v in pairs(DEFAULTS[className] or {}) do
		o._props[k] = v
	end
	return o
end
function Inst:IsA(c)
	return c == "Instance" or self.ClassName == c or (ISA[self.ClassName] or {})[c] == true
end
function Inst:GetChildren()
	return table.clone(self._children)
end
function Inst:GetDescendants()
	local out = {}
	local function walk(o)
		for _, c in ipairs(o._children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Inst:FindFirstChild(n, recursive)
	for _, c in ipairs(self._children) do
		if c.Name == n then
			return c
		end
	end
	if recursive then
		for _, d in ipairs(self:GetDescendants()) do
			if d.Name == n then
				return d
			end
		end
	end
	return nil
end
function Inst:FindFirstChildOfClass(cl)
	for _, c in ipairs(self._children) do
		if c.ClassName == cl then
			return c
		end
	end
	return nil
end
function Inst:FindFirstChildWhichIsA(cl, recursive)
	for _, c in ipairs(if recursive then self:GetDescendants() else self._children) do
		if c:IsA(cl) then
			return c
		end
	end
	return nil
end
function Inst:FindFirstAncestorOfClass(cl)
	local p = self.Parent
	while p do
		if p.ClassName == cl then
			return p
		end
		p = p.Parent
	end
	return nil
end
function Inst:WaitForChild(n, timeout)
	local waited = 0
	while true do
		local c = self:FindFirstChild(n)
		if c then
			return c
		end
		if timeout and waited >= timeout then
			return nil
		end
		waited += task.wait(0.05)
	end
end
function Inst:GetAttribute(k)
	return self._attrs[k]
end
function Inst:GetAttributes()
	return table.clone(self._attrs)
end
function Inst:SetAttribute(k, v)
	self._attrs[k] = v
	local s = self._attrSignals[k]
	if s then
		s:Fire()
	end
	local any = rawget(self, "_signals").AttributeChanged
	if any then
		any:Fire(k)
	end
end
function Inst:GetAttributeChangedSignal(k)
	self._attrSignals[k] = self._attrSignals[k] or Signal.new()
	return self._attrSignals[k]
end
function Inst:GetPropertyChangedSignal(_k)
	return Signal.new()
end
function Inst:IsDescendantOf(a)
	local p = self.Parent
	while p do
		if p == a then
			return true
		end
		p = p.Parent
	end
	return false
end
function Inst:GetFullName()
	local p = self.Parent
	if p and p.ClassName ~= "DataModel" then
		return p:GetFullName() .. "." .. self.Name
	end
	return self.Name
end
function Inst:Destroy()
	if rawget(self, "_destroyed") then
		return
	end
	self.Destroying:Fire()
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
	self.Parent = nil
	rawset(self, "_destroyed", true)
end
function Inst:ClearAllChildren()
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
end
function Inst:Clone()
	local c = new(self.ClassName, self.Name)
	for k, v in pairs(self._props) do
		c._props[k] = v
	end
	for k, v in pairs(self._attrs) do
		c._attrs[k] = v
	end
	local map = { [self] = c }
	for _, ch in ipairs(self._children) do
		local cc = ch:Clone()
		map[ch] = cc
		cc.Parent = c
	end
	if self._props.PrimaryPart and map[self._props.PrimaryPart] then
		c._props.PrimaryPart = map[self._props.PrimaryPart]
	end
	return c
end
-- models: pivot = PrimaryPart's CFrame (or the stored WorldPivot)
function Inst:GetPivot()
	if self:IsA("BasePart") then
		return partCFrame(self)
	end
	local pp = self._props.PrimaryPart
	if pp then
		return partCFrame(pp)
	end
	return self._props.WorldPivot or CFrame.identity
end
function Inst:PivotTo(target)
	if self:IsA("BasePart") then
		self.CFrame = target
		return
	end
	local old = self:GetPivot()
	local delta = target * CFrame.Inverse(old)
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = delta * partCFrame(d)
		end
	end
	if not self._props.PrimaryPart then
		self._props.WorldPivot = target
	end
end
function Inst:GetBoundingBox()
	return self:GetPivot(), v3(2, 2, 2)
end
function Inst:GetScale()
	return self._props.Scale or 1
end
function Inst:ScaleTo(s)
	self._props.Scale = s
end
-- BindableEvent
function Inst:Fire(...)
	self.Event:Fire(...)
end
-- remotes
function Inst:FireClient(player, ...)
	local s = self._client[player]
	if s then
		s:Fire(...)
	end
end
function Inst:FireAllClients(...)
	for _, s in pairs(self._client) do
		s:Fire(...)
	end
end
function Inst:FireServer(...)
	local caller = current
	assert(isInst(caller) and caller.ClassName == "Player", "FireServer from a non-client thread")
	local prev = current
	current = "server"
	self.OnServerEvent:Fire(caller, ...)
	current = prev
end
function Inst:InvokeServer(...)
	local caller = current
	assert(isInst(caller) and caller.ClassName == "Player", "InvokeServer from a non-client thread")
	local handler = self._props.OnServerInvoke
	if not handler then
		error("no OnServerInvoke")
	end
	local prev = current
	current = "server"
	local results = table.pack(pcall(handler, caller, ...))
	current = prev
	if not results[1] then
		error(results[2])
	end
	return table.unpack(results, 2, results.n)
end

------------------------------------------------------------ prompt engine

local promptState = {} -- player -> { shown = { [prompt] = true }, inputType }
local function shownFor(player, prompt)
	local st = promptState[player]
	return st ~= nil and st.shown[prompt] == true
end
-- Called on the client: the local player triggers (server prompts too).
function Inst:InputHoldBegin()
	local who = if isInst(current) then current else self._owner
	if self.Enabled and shownFor(who, self) then
		self.Triggered:Fire(who)
	end
end
function Inst:InputHoldEnd() end

local workspaceInst -- set below
local function promptTick(player)
	local st = promptState[player]
	if not st then
		return
	end
	local c = player._props.Character
	local hrp = c and c:FindFirstChild("HumanoidRootPart")
	local best = {} -- key -> { prompt, dist }
	if hrp then
		for _, d in ipairs(workspaceInst:GetDescendants()) do
			local localEnabled = rawget(d, "_localEnabled")
			local enabled = d._props.Enabled
			if localEnabled and localEnabled[player] ~= nil then
				enabled = localEnabled[player]
			end
			if
				d.ClassName == "ProximityPrompt"
				and (d._owner == player or d._owner == "server")
				and enabled
				and d.Parent
				and (d.Parent:IsA("BasePart") or d.Parent.ClassName == "Attachment")
			then
				local at = if d.Parent.ClassName == "Attachment" then d.Parent._props.WorldPosition else d.Parent.Position
				local dist = (hrp.Position - at).Magnitude
				if dist <= d._props.MaxActivationDistance then
					local key = d._props.KeyboardKeyCode
					if not best[key] or dist < best[key].dist then
						best[key] = { prompt = d, dist = dist }
					end
				end
			end
		end
	end
	local nowShown = {}
	for _, b in pairs(best) do
		nowShown[b.prompt] = true
	end
	for p in pairs(st.shown) do
		if not nowShown[p] and not rawget(p, "_destroyed") then
			p.PromptHidden:FireFor(player)
		end
	end
	for p in pairs(nowShown) do
		if not st.shown[p] then
			p.PromptShown:FireFor(player, st.inputType)
		end
	end
	st.shown = nowShown
end

-- Runs the world for `seconds`: scheduled threads in time order, then one
-- Heartbeat (and RenderStepped) per frame, then the prompt model.
local function advance(seconds)
	local target = now + seconds - 1e-9
	while now < target do
		local frameEnd = now + FRAME
		while true do
			local pick, idx = nil, nil
			for i, e in ipairs(queue) do
				if e.t <= frameEnd and (not pick or e.t < pick.t or (e.t == pick.t and e.seq < pick.seq)) then
					pick, idx = e, i
				end
			end
			if not pick then
				break
			end
			table.remove(queue, idx)
			now = math.max(now, pick.t)
			resume(pick.co, table.unpack(pick.args))
		end
		now = frameEnd
		Heartbeat:Fire(FRAME)
		RenderStepped:Fire(FRAME)
		for player in pairs(promptState) do
			promptTick(player)
		end
	end
end

------------------------------------------------------------ the game

local game = new("DataModel", "game")
game._props.JobId = ""
local services = {}
for _, n in ipairs({
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"Workspace",
	"Players",
	"StarterPlayer",
}) do
	local s = new(n, n)
	s.Parent = game
	services[n] = s
end
workspaceInst = services.Workspace
workspaceInst._props.CurrentCamera = { ViewportSize = Vector2.new(1280, 720) }
function workspaceInst:GetServerTimeNow()
	return now
end
function workspaceInst:BulkMoveTo(parts, cframes)
	for i, p in ipairs(parts) do
		p._props.CFrame = cframes[i]
	end
end
local Players = services.Players
function Players:GetPlayers()
	local out = {}
	for _, c in ipairs(self._children) do
		if c.ClassName == "Player" then
			table.insert(out, c)
		end
	end
	return out
end
function Players:GetPlayerFromCharacter(char)
	for _, p in ipairs(self:GetPlayers()) do
		if p._props.Character == char then
			return p
		end
	end
	return nil
end
function Players:GetPlayerByUserId(id)
	for _, p in ipairs(self:GetPlayers()) do
		if p._props.UserId == id then
			return p
		end
	end
	return nil
end
local dsData = {}
local studioMode = { on = true } -- a sim sets .on = false to act as a live server
-- stores a sim keeps apart (dsOther[name] = {}): every other store is dsData
local dsOther = {}
-- dsHooks.before(key): runs at the start of every UpdateAsync (a sim can
-- task.wait() in it for latency, or error() for a failed request)
local dsHooks = {}
-- dsHooks.store(name): runs in GetDataStore (error() = DataStore unavailable);
-- dsHooks.get(key): runs at the start of every GetAsync
-- GetAsync is CACHED like Roblox's (per server, DS_CACHE_SECONDS): a read
-- within that time of the last read or successful write of the key returns
-- that copy, even if the stored value changed since (another server, or a
-- write that landed but errored). A DataStoreGetOptions with UseCache = false
-- reads the stored value (and leaves the cache as it is).
local DS_CACHE_SECONDS = 4
local dsCache = {} -- [store][key] = { value = copy, t = time }
local function dsCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = dsCopy(x)
	end
	return out
end
services.DataStoreService = {
	GetDataStore = function(_, name)
		if dsHooks.store then
			dsHooks.store(name)
		end
		local data = dsOther[name] or dsData
		dsCache[name] = dsCache[name] or {}
		local cache = dsCache[name]
		return {
			UpdateAsync = function(_, key, fn)
				if dsHooks.before then
					dsHooks.before(key, name)
				end
				local r = fn(dsCopy(data[key]))
				if r ~= nil then
					data[key] = r
				end
				if dsHooks.after then
					dsHooks.after(key, name) -- may error: a write that landed, then failed to answer (cache NOT refreshed)
				end
				cache[key] = { value = dsCopy(data[key]), t = now }
				return data[key]
			end,
			GetAsync = function(_, key, options)
				if dsHooks.get then
					dsHooks.get(key, name)
				end
				local fresh = options ~= nil and isInst(options) and options.ClassName == "DataStoreGetOptions"
					and options.UseCache == false
				if fresh then
					return data[key] -- the stored value; the cache is left as it is (worst case for plain reads)
				end
				local c = cache[key]
				if c and now - c.t < DS_CACHE_SECONDS then
					return dsCopy(c.value)
				end
				cache[key] = { value = dsCopy(data[key]), t = now }
				return data[key]
			end,
		}
	end,
}
local guid = 0
services.HttpService = {
	GenerateGUID = function()
		guid += 1
		return "guid-" .. guid
	end,
}
services.RunService = {
	Heartbeat = Heartbeat,
	RenderStepped = RenderStepped,
	Stepped = Heartbeat,
	IsStudio = function()
		return studioMode.on
	end,
	IsRunning = function()
		return true
	end,
	IsServer = function()
		return current == "server"
	end,
}
services.GuiService = {
	GetGuiInset = function()
		return Vector2.new(0, 0)
	end,
}
services.UserInputService = {
	InputBegan = Signal.new(),
	InputEnded = Signal.new(),
	GetMouseLocation = function()
		return Vector2.new(0, 0)
	end,
	GetStringForKeyCode = function(_, key)
		return if key == Enum.KeyCode.E then "E" else ""
	end,
	GetImageForKeyCode = function(_, key)
		return if key == Enum.KeyCode.ButtonX then "rbxasset://textures/ui/Controls/xboxX.png" else ""
	end,
}
-- tweens jump to their goal when played (the sims check end states)
tweensPlayed = {}
services.TweenService = {
	Create = function(_, inst, info, goal)
		local tw = { Instance = inst, TweenInfo = info, Goal = goal, Completed = Signal.new() }
		function tw:Play()
			table.insert(tweensPlayed, self)
			for k, v in pairs(goal) do
				inst[k] = v
			end
			self.Completed:Fire(Enum.PlaybackState.Completed)
		end
		function tw:Cancel() end
		return tw
	end,
}
local boundActions = {} -- player -> name -> { fn, keys }
services.ContextActionService = {
	BindAction = function(_, name, fn, _createTouchButton, ...)
		boundActions[current] = boundActions[current] or {}
		boundActions[current][name] = { fn = fn, keys = { ... } }
	end,
	UnbindAction = function(_, name)
		if boundActions[current] then
			boundActions[current][name] = nil
		end
	end,
}
local function pressKey(p, key)
	for name, b in pairs(boundActions[p] or {}) do
		if table.find(b.keys, key) then
			runAs(p, b.fn, name, Enum.UserInputState.Begin, { KeyCode = key, UserInputType = Enum.UserInputType.Keyboard })
		end
	end
end
-- a client presses a key a shown prompt listens to (as Roblox does natively)
local function pressPromptKey(p, key)
	local st = promptState[p]
	for prompt in pairs(st and st.shown or {}) do
		if prompt._props.KeyboardKeyCode == key then
			runAs(p, function()
				prompt:InputHoldBegin()
				prompt:InputHoldEnd()
			end)
		end
	end
end
-- a client clicks / taps a GUI button
local function click(p, b)
	runAs(p, function()
		b.Activated:Fire()
	end)
end
services.ProximityPromptService = { PromptTriggered = Signal.new() }
services.SoundService = new("SoundService", "SoundService")
services.PhysicsService = {
	RegisterCollisionGroup = function() end,
	CollisionGroupSetCollidable = function() end,
}
-- CollectionService: tags on instances (a sim tags with addTag)
local tagged, tagSignals = {}, {}
local function addTag(inst, tag)
	tagged[tag] = tagged[tag] or {}
	table.insert(tagged[tag], inst)
	if tagSignals[tag] then
		tagSignals[tag]:Fire(inst)
	end
end
services.CollectionService = {
	GetTagged = function(_, tag)
		local out = {}
		for _, inst in ipairs(tagged[tag] or {}) do
			if inst:IsDescendantOf(game) then
				table.insert(out, inst)
			end
		end
		return out
	end,
	HasTag = function(_, inst, tag)
		return table.find(tagged[tag] or {}, inst) ~= nil
	end,
	AddTag = function(_, inst, tag)
		addTag(inst, tag)
	end,
	GetInstanceAddedSignal = function(_, tag)
		tagSignals[tag] = tagSignals[tag] or Signal.new()
		return tagSignals[tag]
	end,
}
local closers = {}
function game:GetService(n)
	return services[n] or error("no service " .. n)
end
function game:BindToClose(fn)
	table.insert(closers, fn)
end

local Instance = {
	new = function(className, parent)
		local o = new(className)
		if parent then
			o.Parent = parent
		end
		return o
	end,
}

local function typeofFake(x)
	if isInst(x) then
		return "Instance"
	elseif type(x) == "table" and getmetatable(x) == V3 then
		return "Vector3"
	elseif type(x) == "table" and getmetatable(x) == CF then
		return "CFrame"
	end
	return realTypeof(x)
end

local loaded = {}
local envFor
local function requireModule(mod)
	if loaded[mod] == nil then
		local fn = assert(loadstring(mod._props.Source, "=" .. mod.Name))
		setfenv(fn, envFor(mod))
		loaded[mod] = fn()
	end
	return loaded[mod]
end
function envFor(scriptInst)
	return setmetatable({
		script = scriptInst,
		game = game,
		workspace = workspaceInst,
		Instance = Instance,
		task = task,
		wait = task.wait,
		os = {
			clock = function()
				return now
			end,
			time = function()
				return 1700000000 + math.floor(now)
			end,
		},
		typeof = typeofFake,
		Vector3 = Vector3,
		CFrame = CFrame,
		Color3 = Color3,
		UDim2 = UDim2,
		UDim = UDim,
		Vector2 = Vector2,
		ColorSequence = ColorSequence,
		NumberSequence = NumberSequence,
		NumberRange = NumberRange,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		TweenInfo = TweenInfo,
		Random = Random,
		RaycastParams = RaycastParams,
		Enum = Enum,
		require = requireModule,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			table.insert(warnings, table.concat(parts, " "))
		end,
		print = function() end,
	}, { __index = realEnv })
end
-- Runs a Script's source as its own thread (it may yield forever, like a
-- real server script).
local function runScript(scriptInst, owner)
	local fn = assert(loadstring(scriptInst._props.Source, "=" .. scriptInst.Name))
	setfenv(fn, envFor(scriptInst))
	return runAs(owner or "server", fn)
end
local function script(className, name, source, parent)
	local s = new(className, name)
	s._props.Source = source
	if parent then
		s.Parent = parent
	end
	return s
end
local function part(name, pos, parent, size)
	local p = new("Part", name)
	p._props.CFrame = CFrame.new(pos)
	p._props.Size = size or v3(1, 1, 1)
	p._props.Anchored = true
	if parent then
		p.Parent = parent
	end
	return p
end
-- The place's four-card upgrade board art, as Astra found it: the part
-- Workspace["Upgrade board"].Screen, and per player PlayerGui.UpgradeBoardGui
-- (Roblox's copy of StarterGui.UpgradeBoardGui: a SurfaceGui adorned to the
-- screen, no scripts). Each card is a Frame named for its upgrade with a
-- TextLabel Desc ("15 >20kg"), a TextLabel Title, an ImageButton Btn (the art
-- image) holding a TextLabel Price ("$10"), and icon art that must never be
-- touched (two ViewportFrames named IconOutline with models, a gradient).
local BOARD_ART_CARDS = {
	{ "Net Strength", "15 >20kg" },
	{ "Rod Luck", "1x >2x" },
	{ "Meat Price", "1x >2x" },
	{ "Faster Reels", "1x >1.2x" },
}
local BOARD_ART_BUTTON = "rbxassetid://77162011310420"
local function upgradeBoard(pos, size)
	current = "server"
	local model = new("Model", "Upgrade board")
	local screen = part("Screen", pos, model, size or Vector3.new(19.53, 9.34, 0.85))
	model.Parent = workspaceInst
	current = nil
	return model, screen
end
-- p's PlayerGui copy; `shape(cardName, frame)` may alter a card (malformed-art tests)
local function boardArt(p, screen, shape)
	current = "server"
	local gui = new("SurfaceGui", "UpgradeBoardGui")
	gui._props.Enabled = true
	gui._props.Adornee = screen
	gui._props.ResetOnSpawn = true
	for _, c in ipairs(BOARD_ART_CARDS) do
		local frame = new("Frame", c[1])
		frame._props.Size = UDim2.fromScale(0.49, 0.48)
		local title = new("TextLabel", "Title")
		title._props.Text = c[1]
		title.Parent = frame
		local desc = new("TextLabel", "Desc")
		desc._props.Text = c[2]
		desc.Parent = frame
		local btn = new("ImageButton", "Btn")
		btn._props.Image = BOARD_ART_BUTTON
		local price = new("TextLabel", "Price")
		price._props.Text = "$10"
		price.Parent = btn
		new("UIGradient", "UIGradient").Parent = btn
		btn.Parent = frame
		for _ = 1, 2 do
			local vp = new("ViewportFrame", "IconOutline")
			new("Model", "IconModel").Parent = vp
			vp.Parent = frame
		end
		new("UIGradient", "UIGradient").Parent = frame
		if shape then
			shape(c[1], frame)
		end
		frame.Parent = gui
	end
	gui.Parent = p.PlayerGui
	current = nil
	return gui
end
-- a card of p's board art as { Value = Desc, Buy = Btn, Frame = frame } (nil if missing)
local function artCard(p, cardName)
	local gui = p.PlayerGui:FindFirstChild("UpgradeBoardGui")
	local frame = gui and gui:FindFirstChild(cardName)
	if not frame then
		return nil
	end
	return { Value = frame:FindFirstChild("Desc"), Buy = frame:FindFirstChild("Btn"), Frame = frame }
end
local ART_CARD_NAMES = { NetStrength = "Net Strength", RodLuck = "Rod Luck", MeatPrice = "Meat Price", FasterReels = "Faster Reels" }
local function model(name, parent, pos)
	local m = new("Model", name)
	local body = part("Body", pos or v3(0, 0, 0), m)
	m._props.PrimaryPart = body
	if parent then
		m.Parent = parent
	end
	return m
end

------------------------------------------------------------ economy (as InstallRodOffers creates it)

local root, Economy
local CORE = { "Config", "Pricing", "Ledger", "MoneyStore", "Offers", "PieceTags", "Sales", "Rods", "NetKg", "BoardUpgrades" }
-- The sims were written for the ORIGINAL prices (net 10, 25, 50, 100 then
-- x1.5; board 3 levels; rods 150 / 600 / 2000 / 7500): they test the logic, so
-- they run with those, pinned into the same Config tables the modules read.
-- customers_sim sets fastStartTuning.on to run the current (fast-start) one.
local fastStartTuning = { on = false }
local function pinOriginalTuning(Config)
	Config.NetKg.Costs = { 10, 25, 50, 100 }
	Config.NetKg.Growth = 1.5
	local U = Config.BoardUpgrades
	U.RodLuck.Values, U.RodLuck.Costs, U.RodLuck.FirstValue = { 1, 2, 2.5, 3 }, { 10, 75, 300 }, 2
	U.MeatPrice.Values, U.MeatPrice.Costs, U.MeatPrice.FirstValue = { 1, 2, 2.5, 3 }, { 10, 150, 600 }, 2
	U.FasterReels.Values, U.FasterReels.Costs, U.FasterReels.FirstValue = { 1, 1.2, 1.35, 1.5 }, { 10, 100, 400 }, 1.2
	local ORIGINAL = { FishingRod4 = 150, FishingRod3 = 600, FishingRod2 = 2000, FishingRod5 = 7500 }
	for _, rod in ipairs(Config.Rods) do
		rod.Price = ORIGINAL[rod.Id] or rod.Price
	end
	assert(Config.check() == true, "pinned tuning fails Config.check")
end

local function installEconomy()
	current = "server"
	root = new("Folder", "Economy")
	root:SetAttribute("RodOffersEnabled", true)
	new("RemoteEvent", "Notice").Parent = root
	new("RemoteFunction", "OfferAction").Parent = root
	new("Folder", "Offers").Parent = root
	root.Parent = services.ReplicatedStorage
	local service = script("ModuleScript", "EconomyService", SOURCES.EconomyService)
	for _, name in ipairs(CORE) do
		script("ModuleScript", name, SOURCES[name], service)
	end
	service.Parent = services.ServerScriptService
	runAs("server", function()
		Economy = requireModule(service)
		if not fastStartTuning.on then
			pinOriginalTuning(Economy.Config)
		end
		check("EconomyService starts", Economy.start() == true)
	end)
	current = nil
	advance(0.1)
	return Economy, root
end

-- players (each gets the real EconomyClient and a notice spy)
local notices = {} -- player -> { text }
local function join(userId, name, pos)
	current = "server"
	local p = new("Player", name)
	p._props.UserId = userId
	p._props.DisplayName = name
	new("PlayerGui", "PlayerGui").Parent = p
	local char = new("Model", name)
	local hrp = part("HumanoidRootPart", pos, char)
	char._props.PrimaryPart = hrp
	new("Humanoid", "Humanoid").Parent = char
	char.Parent = workspaceInst
	p._props.Character = char
	p.Parent = Players
	Players.PlayerAdded:Fire(p)
	p.CharacterAdded:Fire(char)
	notices[p] = {}
	promptState[p] = { shown = {}, inputType = Enum.ProximityPromptInputType.Keyboard }
	if root then -- economy installed: the player's EconomyClient + a notice spy
		runAs(p, function()
			root.Notice.OnClientEvent:Connect(function(text)
				table.insert(notices[p], text)
			end)
			runScript(script("LocalScript", "EconomyClient", SOURCES.EconomyClient), p)
		end)
	end
	current = nil
	return p
end
local function respawn(p, pos)
	current = "server"
	local old = p._props.Character
	if old then
		old:Destroy()
	end
	local char = new("Model", p.Name)
	local hrp = part("HumanoidRootPart", pos, char)
	char._props.PrimaryPart = hrp
	new("Humanoid", "Humanoid").Parent = char
	char.Parent = workspaceInst
	p._props.Character = char
	p.CharacterAdded:Fire(char)
	current = nil
end
local function leave(p)
	current = "server"
	Players.PlayerRemoving:Fire(p)
	p.Parent = nil
	promptState[p] = nil
	current = nil
end
local function moveTo(p, pos)
	p._props.Character.HumanoidRootPart.Position = pos
end
local function lastNotice(p)
	local n = notices[p]
	return n[#n]
end
local function balance(p)
	return Economy.balance(p)
end
local function asServer(fn, ...)
	current = "server"
	local r = table.pack(fn(...))
	current = nil
	return table.unpack(r, 1, r.n)
end

local function finish(label)
	check(label .. ": no thread errors", #errors == 0)
	for _, e in ipairs(errors) do
		print("  error: " .. e)
	end
	print(string.format("%s: %d passed, %d failed", label, passes, failures))
	if failures > 0 or #errors > 0 then
		error(label .. " failed")
	end
end
