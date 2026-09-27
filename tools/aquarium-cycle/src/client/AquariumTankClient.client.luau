-- AquariumTankClient (LocalScript in StarterPlayer.StarterPlayerScripts).
--
-- Visual only. For each fish marker the server keeps in
-- Workspace.AquariumCycleRuntime.TankFish, this draws a local clone of the
-- matching ReplicatedStorage.FishModels model swimming a smooth, bounded path
-- inside the bound tank water (FishTank.Base5.BaseWater). Released fish swim over to
-- the fish loader (or the tank rim) and fade out; the server then puts them
-- back into the river. Also shows the server's short feedback notices.
-- Nothing here affects game state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local root = ReplicatedStorage:WaitForChild("AquariumCycle")
local Config = require(root:WaitForChild("Config"))
local TankPath = require(root:WaitForChild("TankPath"))
local scene = Config.Scene
local fishModels = ReplicatedStorage:WaitForChild("FishModels")
local bindings = root:WaitForChild("Bindings")

local ENTER_SECONDS = 1
local TURN_RATE = 6 -- orientation smoothing
local FADE_FROM = 0.75 -- fraction of the release swim after which the fish fades

------------------------------------------------------------ notices

local player = Players.LocalPlayer
local noticeGui = Instance.new("ScreenGui")
noticeGui.Name = "AquariumNotices"
noticeGui.ResetOnSpawn = false
noticeGui.Parent = player:WaitForChild("PlayerGui")

local noticeLabel = Instance.new("TextLabel")
noticeLabel.AnchorPoint = Vector2.new(0.5, 0)
noticeLabel.Position = UDim2.new(0.5, 0, 0, 70)
noticeLabel.Size = UDim2.fromOffset(460, 44)
noticeLabel.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
noticeLabel.BackgroundTransparency = 0.2
noticeLabel.Font = Enum.Font.FredokaOne
noticeLabel.TextScaled = true
noticeLabel.TextColor3 = Color3.new(1, 1, 1)
noticeLabel.Visible = false
noticeLabel.Parent = noticeGui
Instance.new("UICorner", noticeLabel).CornerRadius = UDim.new(0, 10)
local padding = Instance.new("UIPadding", noticeLabel)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)

local KIND_COLORS = {
	info = Color3.fromRGB(20, 30, 45),
	success = Color3.fromRGB(30, 110, 60),
	warn = Color3.fromRGB(140, 60, 30),
}
local noticeToken = 0
local function showNotice(text: any, kind: any)
	if type(text) ~= "string" then
		return
	end
	noticeToken += 1
	local token = noticeToken
	noticeLabel.Text = text
	noticeLabel.BackgroundColor3 = KIND_COLORS[kind] or KIND_COLORS.info
	noticeLabel.Visible = true
	task.delay(2.8, function()
		if token == noticeToken then
			noticeLabel.Visible = false
		end
	end)
end

local function hookNotice(child: Instance)
	if child.Name == "Notice" and child:IsA("RemoteEvent") then
		child.OnClientEvent:Connect(showNotice)
	end
end
for _, child in ipairs(root:GetChildren()) do
	hookNotice(child)
end
root.ChildAdded:Connect(hookNotice)

------------------------------------------------------------ tank fish

local visuals = Instance.new("Folder")
visuals.Name = "AquariumTankVisuals"
visuals.Parent = workspace

local fish = {} -- marker -> record

local function boundPart(name: string): Instance?
	local value = bindings:FindFirstChild(name)
	return if value and value:IsA("ObjectValue") then value.Value else nil
end

local function removeFish(marker: Instance)
	local record = fish[marker]
	fish[marker] = nil
	if record and record.model then
		record.model:Destroy()
	end
end

local function addFish(marker: Instance)
	if fish[marker] then
		return
	end
	local name = marker:GetAttribute("FishName")
	local template = type(name) == "string" and fishModels:FindFirstChild(name)
	if not (template and template:IsA("Model")) then
		return
	end
	local model = template:Clone()
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		model:ScaleTo(model:GetScale() * scene.TankFishSize / longest)
	end
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			table.insert(parts, d)
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	-- Rare-fish effects when the variants feature is installed.
	local variant = marker:GetAttribute("Variant")
	local fx = variant and ReplicatedStorage:FindFirstChild("FishVariantVisuals")
	if fx and fx:IsA("ModuleScript") then
		local ok, v = pcall(require, fx)
		if ok and type(v) == "table" then
			pcall(v.applyToFish, model, variant)
		end
	end
	model.Parent = visuals
	fish[marker] = {
		model = model,
		parts = parts,
		seed = marker:GetAttribute("Seed") or 1,
		enterT = marker:GetAttribute("EnterT") or workspace:GetServerTimeNow(),
		cf = nil,
		releaseFrom = nil,
	}
end

local function watchFolder(folder: Instance)
	for _, marker in ipairs(folder:GetChildren()) do
		addFish(marker)
	end
	folder.ChildAdded:Connect(addFish)
	folder.ChildRemoved:Connect(removeFish)
end

local function watchRuntime(runtime: Instance)
	local tankFish = runtime:WaitForChild("TankFish", 10)
	if tankFish then
		watchFolder(tankFish)
	end
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == scene.RuntimeFolderName then
		watchRuntime(child)
	end
end)
workspace.ChildRemoved:Connect(function(child)
	if child.Name == scene.RuntimeFolderName then
		for marker in pairs(fish) do
			removeFish(marker)
		end
	end
end)
local existing = workspace:FindFirstChild(scene.RuntimeFolderName)
if existing then
	task.spawn(watchRuntime, existing)
end

local function smoothstep(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function setFade(record, alpha: number)
	for _, p in ipairs(record.parts) do
		p.LocalTransparencyModifier = alpha
	end
end

RunService.RenderStepped:Connect(function(dt)
	if next(fish) == nil then
		return
	end
	local water = boundPart("TankWater")
	if not (water and water:IsA("BasePart")) then
		return -- not streamed in yet
	end
	local now = workspace:GetServerTimeNow()
	local wcf, wsize = water.CFrame, water.Size
	local hx, hy, hz = TankPath.halfExtents(wsize.X, wsize.Y, wsize.Z, scene.TankMargin, scene.TankFishSize)
	local entry = wcf:PointToWorldSpace(Vector3.new(0, wsize.Y / 2 - 0.5, 0))
	local loader = boundPart("Loader")
	local exit = if loader and loader:IsA("PVInstance")
		then (loader :: PVInstance):GetPivot().Position
		else wcf:PointToWorldSpace(Vector3.new(-wsize.X / 2, wsize.Y / 2, 0))

	for marker, record in pairs(fish) do
		if not marker.Parent then
			removeFish(marker)
			continue
		end
		local x, y, z, dx, dy, dz = TankPath.at(hx, hy, hz, record.seed, now)
		local pos = wcf:PointToWorldSpace(Vector3.new(x, y, z))
		local dir = wcf:VectorToWorldSpace(Vector3.new(dx, dy * 0.5, dz))

		local age = now - record.enterT
		if age < ENTER_SECONDS then
			pos = entry:Lerp(pos, smoothstep(age / ENTER_SECONDS))
		end

		if marker:GetAttribute("State") == "Releasing" then
			local releaseT = marker:GetAttribute("ReleaseT") or now
			local dur = math.max(0.1, marker:GetAttribute("ReleaseDur") or Config.ReleaseSwimSeconds)
			local u = math.clamp((now - releaseT) / dur, 0, 1)
			record.releaseFrom = record.releaseFrom or (record.cf and record.cf.Position) or pos
			local from = record.releaseFrom
			pos = from:Lerp(exit, smoothstep(u)) + Vector3.new(0, 3 * 4 * u * (1 - u), 0)
			dir = exit - from
			setFade(record, math.clamp((u - FADE_FROM) / (1 - FADE_FROM), 0, 1))
		end

		if dir.Magnitude < 1e-3 then
			dir = wcf.LookVector
		end
		local wiggle = CFrame.Angles(0, math.sin(now * 6 + record.seed) * 0.12, 0)
		local target = CFrame.lookAt(pos, pos + dir) * wiggle
		record.cf = if record.cf then record.cf:Lerp(target, math.min(1, dt * TURN_RATE)) else target
		record.model:PivotTo(record.cf)
	end
end)
