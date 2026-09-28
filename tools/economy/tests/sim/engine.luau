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
local UDim2, UDim = dummy("UDim2"), dummy("UDim")
local C3 = {}
C3.__index = C3
function C3:Lerp(other, u)
	return setmetatable(
		{
			R = self.R + (other.R - self.R) * u,
			G = self.G + (other.G - self.G) * u,
			B = self.B + (other.B - self.B) * u,
		},
		C3
	)
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
	TextLabel = { GuiObject = true },
	Frame = { GuiObject = true },
	ImageLabel = { GuiObject = true },
	Script = { BaseScript = true, LuaSourceContainer = true },
	LocalScript = { Script = true, BaseScript = true, LuaSourceContainer = true },
	ModuleScript = { LuaSourceContainer = true },
}
local DEFAULTS = {
	ProximityPrompt = {
		Enabled = true,
		HoldDuration = 0,
		MaxActivationDistance = 10,
		RequiresLineOfSight = true,
		ObjectText = "",
		ActionText = "",
	},
	Humanoid = { Health = 100, MaxHealth = 100 },
	Part = {
		Size = v3(1, 1, 1),
		Anchored = false,
		Transparency = 0,
		Color = setmetatable({ R = 0.6, G = 0.6, B = 0.6 }, C3),
	},
}
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
function Inst:WaitForChild(n)
	while true do
		local c = self:FindFirstChild(n)
		if c then
			return c
		end
		task.wait(0.05)
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
function Inst:InputHoldBegin()
	local owner = self._owner
	if self._props.Enabled and shownFor(owner, self) then
		self.Triggered:Fire(owner)
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
			if
				d.ClassName == "ProximityPrompt"
				and d._owner == player
				and d._props.Enabled
				and d.Parent
				and d.Parent:IsA("BasePart")
			then
				local dist = (hrp.Position - d.Parent.Position).Magnitude
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
			p.PromptHidden:Fire()
		end
	end
	for p in pairs(nowShown) do
		if not st.shown[p] then
			p.PromptShown:Fire(st.inputType)
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
function Players:GetPlayerByUserId(id)
	for _, p in ipairs(self:GetPlayers()) do
		if p._props.UserId == id then
			return p
		end
	end
	return nil
end
local dsData = {}
services.DataStoreService = {
	GetDataStore = function()
		return {
			UpdateAsync = function(_, key, fn)
				local r = fn(dsData[key])
				if r ~= nil then
					dsData[key] = r
				end
				return dsData[key]
			end,
			GetAsync = function(_, key)
				return dsData[key]
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
		return true
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
services.PhysicsService = {
	RegisterCollisionGroup = function() end,
	CollisionGroupSetCollidable = function() end,
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
local CORE = { "Config", "Pricing", "Ledger", "MoneyStore", "Offers", "PieceTags", "Sales" }
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
