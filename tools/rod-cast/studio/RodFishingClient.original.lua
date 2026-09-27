-- Smooth visuals for the button fishing:
--  * fish rise slowly out of the water on the line while spinning (silhouettes swap on the server)
--  * rods bend back and tug while reeling
--  * bobbers bob / dip on a bite
--  * the big red button squishes down and wobbles back up when pressed
local RunService = game:GetService("RunService")
local folder = workspace:WaitForChild("RodCatches")
local button = workspace:WaitForChild("BigButton")
local btnModel = button:WaitForChild("Button")

------------------------------------------------ button: squishy press
local UIS = game:GetService("UserInputService")
local body = btnModel:WaitForChild("Body")
local top = btnModel:FindFirstChild("TopEdge")
local bodyRest = { cf = body.CFrame, size = body.Size }        -- cylinder: height is Size.X
local topRest = top and { cf = top.CFrame, size = top.Size }
local H = body.Size.X
local bottomY = body.Position.Y - H / 2

local held, hovering = false, false
local downT, relT = -100, -100
local relSq = 1

local function pressDown() if not held then held = true downT = os.clock() end end
local function release()
	if held then
		held = false
		relT = os.clock()
		relSq = 1 - 0.75 * math.min(1, (os.clock() - downT) / 0.09)
	end
end
local function tap() pressDown() task.delay(0.1, release) end

local pressRemote = game:GetService("ReplicatedStorage"):WaitForChild("PressFishButton")
local camera = workspace.CurrentCamera
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { button }
local function pointingAtButton(screenPos)
	local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	return workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams) ~= nil
end
local lastFire = 0
local function fire()
	if os.clock() - lastFire < 0.6 then return end
	lastFire = os.clock()
	pressRemote:FireServer()
end
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		local pos = t == Enum.UserInputType.Touch and input.Position or UIS:GetMouseLocation() - game:GetService("GuiService"):GetGuiInset()
		if pointingAtButton(Vector2.new(pos.X, pos.Y)) then
			pressDown()
			fire()
		end
	end
end)
UIS.InputEnded:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then release() end
end)
local lastSeen = button:GetAttribute("PressedAt")
button:GetAttributeChangedSignal("PressedAt"):Connect(function()
	-- someone else pressed it (or stepped on it): play a quick tap
	if not held and os.clock() - relT > 0.3 then tap() end
end)

local function squish(t)
	if held then
		local u = math.min(1, (t - downT) / 0.09)
		u = 1 - (1 - u) ^ 2
		return 1 - 0.75 * u
	end
	local s = t - relT
	if s > 1.5 then return 1 end
	return 1 - (1 - relSq) * math.exp(-6 * s) * math.cos(16 * s)
end

local function drawButton(t)
	local sq = squish(t)
	local wide = 1 + (1 - sq) * 0.35
	local h = H * sq
	body.Size = Vector3.new(h, bodyRest.size.Y * wide, bodyRest.size.Z * wide)
	body.CFrame = bodyRest.cf.Rotation + Vector3.new(bodyRest.cf.X, bottomY + h / 2, bodyRest.cf.Z)
	if top then
		top.Size = Vector3.new(topRest.size.X * wide, topRest.size.Y * (0.6 + 0.4 * sq), topRest.size.Z * wide)
		top.CFrame = topRest.cf.Rotation + Vector3.new(topRest.cf.X, topRest.cf.Y - (H - h), topRest.cf.Z)
	end
end

------------------------------------------------ rods
local rods = {}
for _, m in ipairs(workspace:GetChildren()) do
	if m.Name == "FishingRod1" and m:IsA("Model") then table.insert(rods, m) end
end

local rodAng = {}
local spinBase = {}
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local now = workspace:GetServerTimeNow()

	drawButton(t)

	-- rods tugging while reeling
	for _, m in ipairs(rods) do
		local rest = m:GetAttribute("RestPivot")
		if rest and m.Parent then
			local ang = 0
			if m:GetAttribute("Pulling") then
				local e = now - (m:GetAttribute("PullT0") or now)
				ang = math.rad(9) * math.min(1, e * 3) + math.rad(4) * math.sin(e * 11) + math.rad(2) * math.sin(e * 23)
			end
			rodAng[m] = (rodAng[m] or 0) + (ang - (rodAng[m] or 0)) * 0.25
			local p = rest.Position
			m:PivotTo(CFrame.new(p) * CFrame.Angles(0, 0, rodAng[m]) * CFrame.new(-p) * rest)
		end
	end

	-- fish rising + spinning, bobbers bobbing
	for _, m in ipairs(folder:GetChildren()) do
		if m:GetAttribute("Spin") and m.PrimaryPart then
			local base = spinBase[m]
			if not base then base = m:GetPivot().Rotation spinBase[m] = base end
			local from, to, t0, dur = m:GetAttribute("From"), m:GetAttribute("To"), m:GetAttribute("T0"), m:GetAttribute("Dur")
			local pos = m:GetPivot().Position
			if from and to and t0 and dur then
				local u = math.clamp((now - t0) / dur, 0, 1)
				u = 1 - (1 - u) ^ 2
				pos = from:Lerp(to, u) + Vector3.new(0, math.sin(t * 9) * 0.15 * (1 - u), 0)
			end
			m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, t * 5, 0) * CFrame.Angles(math.sin(t * 2) * 0.12, 0, 0) * base)
		elseif spinBase[m] then
			spinBase[m] = nil
		end
		if m.Name == "Bobber" and m:GetAttribute("Bob") then
			local b = m:GetAttribute("BobBase")
			if b then
				local dip = m:GetAttribute("Bite") and (math.sin(t * 22) * 0.25 - 0.25) or 0
				local yy = b.Y + math.sin(t * 3 + b.Z) * 0.08 + dip
				m.Red.CFrame = CFrame.new(b.X, yy, b.Z)
				m.White.CFrame = CFrame.new(b.X, yy + 0.3, b.Z)
			end
		end
	end
end)
folder.ChildRemoved:Connect(function(m) spinBase[m] = nil end)
