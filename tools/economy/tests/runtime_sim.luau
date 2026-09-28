-- Runtime simulation of the rod-stand buy prompt: the REAL EconomyService
-- (+ core modules) and the REAL EconomyClient (one copy per player) running
-- against a small fake engine: instances with signals/attributes, a virtual
-- clock scheduler, remotes that know which player's thread is calling, and a
-- ProximityPrompt model (nearest-per-key within MaxActivationDistance,
-- PromptShown/PromptHidden/Triggered, InputHoldBegin for touch/mouse).
--
-- run_runtime_sim.py prepends SOURCES = { name = source } and runs this with
-- the Luau CLI. Fake-engine simulation only; not a Roblox runtime test.

local SOURCES = SOURCES :: { [string]: string }
local realEnv = getfenv(1)

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

------------------------------------------------------------ values

local Vector3 = {}
local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	end
	return nil
end
V3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
local CFrame = {}
function CFrame.new(p)
	return { Position = p or Vector3.new(), __cframe = true }
end
local function dummy(kind)
	return setmetatable({}, {
		__index = function(_, k)
			return function(...)
				return { kind = kind, ctor = k, args = { ... } }
			end
		end,
	})
end
local Color3, UDim2, UDim = dummy("Color3"), dummy("UDim2"), dummy("UDim")
local Vector2 = {
	new = function(x, y)
		return { X = x, Y = y }
	end,
}
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

------------------------------------------------------------ scheduler

local now = 0
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
	local co = newThread(fn, current)
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
	schedule(now + math.max(t or 0, 1 / 60), co, {})
	coroutine.yield()
	return t
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
	return setmetatable({ conns = {} }, Signal)
end
function Signal:Connect(fn)
	local conn = { fn = fn, owner = current, connected = true }
	function conn.Disconnect()
		conn.connected = false
	end
	table.insert(self.conns, conn)
	return conn
end
function Signal:Fire(...)
	for _, c in ipairs(table.clone(self.conns)) do
		if c.connected then
			resume(newThread(c.fn, c.owner), ...)
		end
	end
end

------------------------------------------------------------ instances

local EVENTS = {
	ChildAdded = true,
	ChildRemoved = true,
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
}
local ISA = {
	Part = { BasePart = true, PVInstance = true },
	Model = { PVInstance = true },
	TextButton = { GuiObject = true, GuiButton = true },
	TextLabel = { GuiObject = true },
	Frame = { GuiObject = true },
	ImageLabel = { GuiObject = true },
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
	Humanoid = { Health = 100 },
	Part = {},
}
local Inst = {}
local created = {} -- every instance, with the owner that created it
local function isInst(x)
	return type(x) == "table" and getmetatable(x) == Inst
end
Inst.__index = function(self, k)
	local m = rawget(Inst, k)
	if m ~= nil then
		return m
	end
	if k == "Parent" then
		return rawget(self, "_parent")
	end
	if k == "Position" and rawget(self, "_props").CFrame then
		return rawget(self, "_props").CFrame.Position
	end
	if k == "LocalPlayer" and rawget(self, "_props").ClassName == "Players" then
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
	local v = rawget(self, "_props")[k]
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
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old == v then
			return
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
		end
		fireAncestry(self)
		return
	end
	if k == "Position" then
		k, v = "CFrame", CFrame.new(v)
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
	table.insert(created, o)
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
function Inst:SetAttribute(k, v)
	self._attrs[k] = v
	local s = self._attrSignals[k]
	if s then
		s:Fire()
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
	rawset(self, "_destroyed", true)
	self.Destroying:Fire()
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
	self.Parent = nil
end
function Inst:GetPivot()
	local pp = self._props.PrimaryPart
	return if pp then pp._props.CFrame else (self._props.CFrame or CFrame.new())
end

-- remotes
function Inst:FireClient(player, ...)
	local s = self._client[player]
	if s then
		s:Fire(...)
	end
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
local triggers = 0
local function shownFor(player, prompt)
	local st = promptState[player]
	return st ~= nil and st.shown[prompt] == true
end
function Inst:InputHoldBegin()
	local owner = self._owner
	if self._props.Enabled and shownFor(owner, self) then
		triggers += 1
		self.Triggered:Fire(owner)
	end
end
function Inst:InputHoldEnd() end

local function rootPart(player)
	local c = player._props.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local workspaceInst -- set below
local function promptTick(player)
	local st = promptState[player]
	if not st then
		return
	end
	local hrp = rootPart(player)
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

local function advance(seconds)
	local target = now + seconds
	while true do
		local stepEnd = math.min(target, now + 0.05)
		while true do
			local pick, idx = nil, nil
			for i, e in ipairs(queue) do
				if e.t <= stepEnd and (not pick or e.t < pick.t or (e.t == pick.t and e.seq < pick.seq)) then
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
		now = stepEnd
		for player in pairs(promptState) do
			promptTick(player)
		end
		if now >= target then
			break
		end
	end
end

------------------------------------------------------------ the game

local game = new("DataModel", "game")
game._props.JobId = ""
local services = {}
for _, n in ipairs({ "ReplicatedStorage", "ServerScriptService", "Workspace", "Players", "StarterPlayer" }) do
	local s = new(n, n)
	s.Parent = game
	services[n] = s
end
workspaceInst = services.Workspace
workspaceInst._props.CurrentCamera = { ViewportSize = Vector2.new(1280, 720) }
function workspaceInst:GetServerTimeNow()
	return now
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
	IsStudio = function()
		return true
	end,
}
services.UserInputService = {
	GetStringForKeyCode = function(_, key)
		return if key == Enum.KeyCode.E then "E" else ""
	end,
	GetImageForKeyCode = function(_, key)
		return if key == Enum.KeyCode.ButtonX then "rbxasset://textures/ui/Controls/xboxX.png" else ""
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
	end
	return typeof(x)
end

local loaded = {}
local function envFor(scriptInst)
	local env = setmetatable({
		script = scriptInst,
		game = game,
		workspace = workspaceInst,
		Instance = Instance,
		task = task,
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
		Enum = Enum,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			table.insert(warnings, table.concat(parts, " "))
		end,
		print = function() end,
	}, { __index = realEnv })
	env.require = function(mod)
		if loaded[mod] == nil then
			local fn = assert(loadstring(mod._props.Source, "=" .. mod.Name))
			setfenv(fn, envFor(mod))
			loaded[mod] = fn()
		end
		return loaded[mod]
	end
	return env
end
local function runScript(scriptInst)
	local fn = assert(loadstring(scriptInst._props.Source, "=" .. scriptInst.Name))
	setfenv(fn, envFor(scriptInst))
	fn()
end

-- installed objects (as InstallRodOffers creates them)
current = "server"
local root = new("Folder", "Economy")
root:SetAttribute("RodOffersEnabled", true)
new("RemoteEvent", "Notice").Parent = root
new("RemoteFunction", "OfferAction").Parent = root
new("Folder", "Offers").Parent = root
root.Parent = services.ReplicatedStorage
local service = new("ModuleScript", "EconomyService")
service._props.Source = SOURCES.EconomyService
for _, name in ipairs({ "Config", "Pricing", "Ledger", "MoneyStore", "Offers", "PieceTags", "Sales" }) do
	local m = new("ModuleScript", name)
	m._props.Source = SOURCES[name]
	m.Parent = service
end
service.Parent = services.ServerScriptService

local Economy
runAs("server", function()
	Economy = envFor(service).require(service)
	check("EconomyService starts", Economy.start() == true)
end)
advance(0.1)
local standsFolder = workspaceInst:FindFirstChild("EconomyBuyStands")
check("runtime stands folder created, not archivable", standsFolder ~= nil and standsFolder.Archivable == false)

-- players
local notices = {} -- player -> { text }
local function join(userId, name, pos)
	current = "server"
	local p = new("Player", name)
	p._props.UserId = userId
	p._props.DisplayName = name
	new("PlayerGui", "PlayerGui").Parent = p
	local char = new("Model", name)
	local hrp = new("Part", "HumanoidRootPart")
	hrp.Position = pos
	hrp.Parent = char
	new("Humanoid", "Humanoid").Parent = char
	char.Parent = workspaceInst
	p._props.Character = char
	p.Parent = Players
	Players.PlayerAdded:Fire(p)
	notices[p] = {}
	-- the player's client: EconomyClient + a notice spy, running as that player
	promptState[p] = { shown = {}, inputType = Enum.ProximityPromptInputType.Keyboard }
	runAs(p, function()
		root.Notice.OnClientEvent:Connect(function(text)
			table.insert(notices[p], text)
		end)
		local client = new("LocalScript", "EconomyClient")
		client._props.Source = SOURCES.EconomyClient
		runScript(client)
	end)
	current = nil
	return p
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
local function promptsOf(p)
	local out = {}
	for _, d in ipairs(workspaceInst:GetDescendants()) do
		if d.ClassName == "ProximityPrompt" and d._owner == p then
			table.insert(out, d)
		end
	end
	return out
end
local function panelOf(p)
	return p.PlayerGui:FindFirstChild("BuyPromptPanel")
end
local function pressKey(p)
	local st = promptState[p]
	for prompt in pairs(st.shown) do
		if prompt._props.Enabled and not rawget(prompt, "_destroyed") then
			triggers += 1
			runAs(p, function()
				prompt.Triggered:Fire(p)
			end)
		end
	end
end
local function tapPanel(p)
	local panel = panelOf(p)
	local button = panel and panel:FindFirstChild("Panel")
	if button then
		runAs(p, function()
			button.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch })
			button.InputEnded:Fire({ UserInputType = Enum.UserInputType.Touch })
		end)
	end
end

local STAND = Vector3.new(0, 0, 0)
local STAND_TOP = Vector3.new(0, 2.5, 0) -- + Config.Offer.StandHeight
local rodCount = 0
-- one rod offer, run the way the patched RodFishingSystem runs it
local function offer(caster, opts)
	opts = opts or {}
	rodCount += 1
	local rec = { result = nil, delivered = 0, done = false }
	current = "server"
	local fish = new("Model", "Salmon")
	local body = new("Part", "Body")
	body.Position = Vector3.new(12, 6, 0)
	body.Parent = fish
	fish._props.PrimaryPart = body
	fish.Parent = workspaceInst
	rec.fish = fish
	runAs("server", function()
		rec.result = Economy.runRodOffer({
			rodKey = opts.rodKey or rodCount,
			caster = caster,
			fishName = opts.fishName or "Salmon",
			tier = opts.tier or 10,
			variant = nil,
			chance = opts.chance,
			fish = fish,
			stand = opts.stand or STAND,
			stillValid = function()
				return true
			end,
			reservationOk = function()
				return true
			end,
			deliver = function()
				rec.delivered += 1
				return true
			end,
		})
		rec.done = true
	end)
	current = nil
	advance(0.1) -- replicate + the client adds its prompt
	return rec
end
local function standCount()
	return #standsFolder:GetChildren()
end

local A = join(1, "Alice", Vector3.new(30, 0, 0))
local B = join(2, "Bob", Vector3.new(3, 0, 0))
advance(0.5)
check("both players loaded with the grant", balance(A) == 100 and balance(B) == 100)

-- 1) the offer: stand anchor, billboard, caster-only prompt
do
	local rec = offer(A, { chance = 0.034 })
	local stand = standsFolder:GetChildren()[1]
	check("stand part at the rod stand (+StandHeight)", stand and stand.Position == STAND_TOP)
	check(
		"stand carries the offer",
		stand
			and stand:GetAttribute("CasterUserId") == 1
			and stand:GetAttribute("FishName") == "Salmon"
			and stand:GetAttribute("Price") == 17
			and stand:GetAttribute("PromptDistance") == 10
	)
	check(
		"stand invisible, no collisions",
		stand and stand.Transparency == 1 and stand.CanCollide == false and stand.Anchored
	)
	local gui = rec.fish.Body:FindFirstChild("OfferGui")
	check("billboard above the catch", gui ~= nil and gui.AlwaysOnTop == true)
	check("billboard: species", gui and gui:FindFirstChild("FishName") and gui.FishName.Text == "Salmon")
	check("billboard: $price from the server", gui and gui:FindFirstChild("Price") and gui.Price.Text == "$17")
	check(
		"billboard: real roll chance with clover",
		gui and gui:FindFirstChild("Chance") and gui.Chance.Text == "\u{1F340} 3.4%"
	)
	check("billboard labels outlined", gui and gui.Price:FindFirstChildOfClass("UIStroke") ~= nil)
	local pa, pb = promptsOf(A), promptsOf(B)
	check("caster gets exactly one prompt", #pa == 1)
	check("other player gets no prompt", #pb == 0)
	local pr = pa[1]
	check("prompt is on the stand", pr and pr.Parent == stand)
	check("custom style", pr and pr.Style == Enum.ProximityPromptStyle.Custom)
	check("E / ButtonX", pr and pr.KeyboardKeyCode == Enum.KeyCode.E and pr.GamepadKeyCode == Enum.KeyCode.ButtonX)
	check("ObjectText species, ActionText Buy", pr and pr.ObjectText == "Salmon" and pr.ActionText == "Buy")
	check("short range from the stand", pr and pr.MaxActivationDistance == 10 and pr.RequiresLineOfSight == false)
	check("one per key (nearest only)", pr and pr.Exclusivity == Enum.ProximityPromptExclusivity.OnePerButton)
	check("instant press", pr and pr.HoldDuration == 0)

	-- far away (Alice at 30 studs): nothing shown, E does nothing
	check("out of range: no panel", panelOf(A) == nil)
	pressKey(A)
	check("out of range: E does nothing", balance(A) == 100 and rec.delivered == 0)
	-- Bob stands right at the stand: no prompt for him, remote refused
	check("Bob sees no panel", panelOf(B) == nil)
	local okB
	runAs(B, function()
		okB = root.OfferAction:InvokeServer(stand:GetAttribute("OfferId"), "buy")
	end)
	check("Bob's direct buy refused, nobody charged", okB == false and balance(B) == 100 and balance(A) == 100)
	check("Bob told why", lastNotice(B) == "Only the player who cast can buy this fish")

	-- walk up: the reference panel appears
	moveTo(A, Vector3.new(8, 0, 0))
	advance(0.1)
	local panel = panelOf(A)
	check("in range: panel shown", panel ~= nil)
	check("panel anchored to the stand, on top", panel and panel.Adornee == stand and panel.AlwaysOnTop == true)
	local frame = panel and panel:FindFirstChild("Panel")
	check("panel: E keycap", frame and frame.Key:FindFirstChild("Glyph") and frame.Key.Glyph.Text == "E")
	check("panel: fish name + Buy", frame and frame.FishName.Text == "Salmon" and frame.Action.Text == "Buy")
	check(
		"panel: bordered keycap + outlined text",
		frame and frame.Key:FindFirstChildOfClass("UIStroke") and frame.FishName:FindFirstChildOfClass("UIStroke")
	)
	check(
		"panel is small (not a screen panel)",
		panel and panel.Size.ctor == "fromOffset" and panel.Size.args[1] <= 200
	)
	-- walk away: hidden promptly
	moveTo(A, Vector3.new(20, 0, 0))
	advance(0.06)
	check("walk away: panel hidden", panelOf(A) == nil)
	moveTo(A, Vector3.new(8, 0, 0))
	advance(0.06)

	-- buy with E, then spam E, tap and direct requests: charged once. The
	-- per-player cooldown is off here so the once-only guard itself is tested.
	local cooldown = Economy.Config.Offer.ActionCooldown
	Economy.Config.Offer.ActionCooldown = 0
	local id = stand:GetAttribute("OfferId")
	pressKey(A)
	pressKey(A)
	tapPanel(A)
	for _ = 1, 3 do
		runAs(A, function()
			root.OfferAction:InvokeServer(id, "buy")
		end)
	end
	check("after the buy the prompt stays off", promptsOf(A)[1] == nil or promptsOf(A)[1].Enabled == false)
	advance(0.3)
	pressKey(A)
	tapPanel(A)
	advance(0.3)
	Economy.Config.Offer.ActionCooldown = cooldown
	check("bought: charged the shown price once", balance(A) == 100 - 17)
	check("delivered once", rec.delivered == 1)
	check("runRodOffer returned bought", rec.done and rec.result == true)
	check("stand removed", standCount() == 0)
	check("prompt removed", #promptsOf(A) == 0)
	check("panel removed", panelOf(A) == nil)
	check("billboard removed", rec.fish.Body:FindFirstChild("OfferGui") == nil)
	check("buyer told", table.find(notices[A], "Bought! It's going to the aquarium") ~= nil)
end

-- 2) timeout: no charge, everything cleaned up
do
	local before = balance(A)
	moveTo(A, Vector3.new(5, 0, 0))
	local rec = offer(A)
	advance(0.1)
	check("timeout case: panel up", panelOf(A) ~= nil)
	advance(20.5)
	check("timeout: not bought", rec.done and rec.result == false and rec.delivered == 0)
	check("timeout: not charged", balance(A) == before)
	check("timeout: stand/prompt/panel gone", standCount() == 0 and #promptsOf(A) == 0 and panelOf(A) == nil)
	check("timeout: told", lastNotice(A) == "Salmon slipped off the hook (not bought)")
	pressKey(A)
	check("timeout: E afterwards does nothing", balance(A) == before)
end

-- 3) pass (server action kept): cleanup, no charge
do
	local before = balance(A)
	local rec = offer(A)
	local id = standsFolder:GetChildren()[1]:GetAttribute("OfferId")
	local ok
	runAs(A, function()
		ok = root.OfferAction:InvokeServer(id, "pass")
	end)
	advance(0.3)
	check("pass: accepted", ok == true)
	check("pass: not bought, not charged", rec.done and rec.result == false and balance(A) == before)
	check("pass: stand/prompt/panel gone", standCount() == 0 and #promptsOf(A) == 0 and panelOf(A) == nil)
end

-- 4) death: offer cancelled, no charge, cleanup
do
	local before = balance(A)
	local rec = offer(A)
	check("death case: panel up", panelOf(A) ~= nil)
	A.Character.Humanoid.Health = 0
	advance(0.3)
	check("death: not bought", rec.done and rec.result == false and rec.delivered == 0)
	check("death: not charged", balance(A) == before)
	check("death: stand/prompt/panel gone", standCount() == 0 and #promptsOf(A) == 0 and panelOf(A) == nil)
	A.Character.Humanoid.Health = 100 -- respawned
	advance(0.1)
end

-- 5) server reach from the stand (exploit-style direct requests)
do
	local before = balance(A)
	local rec = offer(A)
	local id = standsFolder:GetChildren()[1]:GetAttribute("OfferId")
	local function tryBuyAt(x)
		moveTo(A, Vector3.new(x, 2.5, 0))
		advance(0.3) -- past the action cooldown
		local ok
		runAs(A, function()
			ok = root.OfferAction:InvokeServer(id, "buy")
		end)
		return ok
	end
	check("reach: 40 studs refused", tryBuyAt(40) == false and balance(A) == before)
	check("reach: told to walk up", lastNotice(A) == "Walk up to the rod to buy")
	check("reach: 15 studs (beyond slack) refused", tryBuyAt(15) == false)
	check("reach: offer still open", standCount() == 1)
	check("reach: 13 studs (inside slack) accepted", tryBuyAt(13) == true and balance(A) == before - 17)
	advance(0.3)
	check("reach: cleaned up", rec.done and rec.result == true and standCount() == 0)
end

-- 6) not enough Money: offer stays, prompt comes back, buy later
do
	current = "server"
	Economy.tryDebit(A, balance(A) - 5, "test")
	current = nil
	moveTo(A, Vector3.new(4, 0, 0))
	local rec = offer(A)
	advance(0.1)
	pressKey(A)
	advance(0.3)
	check("funds: refused, told", lastNotice(A) == "Not enough Money" and balance(A) == 5)
	check(
		"funds: offer kept, prompt back",
		standCount() == 1 and #promptsOf(A) == 1 and promptsOf(A)[1].Enabled == true
	)
	check("funds: panel back", panelOf(A) ~= nil)
	advance(21)
	check("funds: then times out, not charged", rec.done and rec.result == false and balance(A) == 5)
	current = "server"
	Economy.credit(A, 95, "test")
	current = nil
end

-- 7) two of your catches next to each other: one panel, the nearest
do
	local r1 = offer(A, { stand = Vector3.new(0, 0, 0) })
	local r2 = offer(A, { stand = Vector3.new(0, 0, 6) })
	moveTo(A, Vector3.new(2, 0, 5))
	advance(0.1)
	local panels = 0
	for _, c in ipairs(A.PlayerGui:GetChildren()) do
		if c.Name == "BuyPromptPanel" then
			panels += 1
		end
	end
	check("two catches: one panel", panels == 1)
	check("two catches: the nearer stand", panelOf(A) and panelOf(A).Adornee.Position == Vector3.new(0, 2.5, 6))
	pressKey(A)
	advance(0.3)
	check("two catches: bought the nearer one only", r2.result == true and not r1.done and balance(A) == 100 - 17)
	advance(0.1)
	check(
		"two catches: the other one's panel shows next",
		panelOf(A) and panelOf(A).Adornee.Position == Vector3.new(0, 2.5, 0)
	)
	advance(21)
	check("two catches: the other one timed out uncharged", r1.done and r1.result == false and balance(A) == 83)
	current = "server"
	Economy.credit(A, 17, "test")
	current = nil
end

-- 8) gamepad and touch
do
	promptState[A].inputType = Enum.ProximityPromptInputType.Gamepad
	moveTo(A, Vector3.new(4, 0, 0))
	local r1 = offer(A)
	advance(0.1)
	local frame = panelOf(A) and panelOf(A).Panel
	check(
		"gamepad: button icon on the keycap",
		frame and frame.Key:FindFirstChild("Icon") and frame.Key.Icon.Image:find("xboxX", 1, true) ~= nil
	)
	pressKey(A) -- ButtonX goes through the same prompt activation
	advance(0.3)
	check("gamepad: bought", r1.result == true and balance(A) == 100 - 17)
	promptState[A].inputType = Enum.ProximityPromptInputType.Touch
	local r2 = offer(A)
	advance(0.1)
	frame = panelOf(A) and panelOf(A).Panel
	check("touch: TAP keycap", frame and frame.Key:FindFirstChild("Glyph") and frame.Key.Glyph.Text == "TAP")
	tapPanel(A)
	advance(0.3)
	check("touch: tapping the panel buys", r2.result == true and balance(A) == 100 - 34)
	promptState[A].inputType = Enum.ProximityPromptInputType.Keyboard
	current = "server"
	Economy.credit(A, 34, "test")
	current = nil
end

-- 9) feature switched off mid-offer
do
	local rec = offer(A)
	current = "server"
	root:SetAttribute("RodOffersEnabled", false)
	current = nil
	advance(0.3)
	check("disabled: cancelled, not charged", rec.done and rec.result == false and balance(A) == 100)
	check("disabled: stand/prompt/panel gone", standCount() == 0 and #promptsOf(A) == 0 and panelOf(A) == nil)
	current = "server"
	root:SetAttribute("RodOffersEnabled", true)
	current = nil
end

-- 10) the caster leaves mid-offer
do
	local rec = offer(A)
	check("leave case: prompt up", #promptsOf(A) == 1)
	current = "server"
	Players.PlayerRemoving:Fire(A)
	A.Parent = nil
	current = nil
	advance(0.3)
	check("leave: not bought, nothing delivered", rec.done and rec.result == false and rec.delivered == 0)
	check("leave: stand removed (Bob sees nothing left)", standCount() == 0 and #promptsOf(A) == 0)
	check("leave: saved balance unchanged", dsData["player_1"] and dsData["player_1"].money == 100)
end

check("no thread errors", #errors == 0)
for _, e in ipairs(errors) do
	print("  error: " .. e)
end
print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 or #errors > 0 then
	error("runtime simulation failed")
end
