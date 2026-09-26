-- Draws the carried stack as a column of blocks welded in front of the
-- character: fish (orange) at the bottom, food portions (cream boxes) on top.
-- Purely cosmetic; the authoritative counts live in PlayerData.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.FishTycoonShared.Config)

local CarryVisual = {}

local STACK_NAME = "CarryStack"
local FISH_COLOR = Color3.fromRGB(255, 140, 60)
local FOOD_COLOR = Color3.fromRGB(250, 226, 170)

local function makeBlock(kind: string): Part
	local part = Instance.new("Part")
	part.Name = kind
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "Fish" then
		part.Size = Vector3.new(1.4, Config.Visual.StackItemHeight, 0.7)
		part.Color = FISH_COLOR
		part.Material = Enum.Material.SmoothPlastic
	else
		part.Size = Vector3.new(1.2, Config.Visual.StackItemHeight, 1.2)
		part.Color = FOOD_COLOR
		part.Material = Enum.Material.SmoothPlastic
	end
	return part
end

-- Rebuilds the stack for the given counts. Safe to call with a nil character.
function CarryVisual.render(character: Model?, carry: { fish: number, food: number })
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end

	local stack = character:FindFirstChild(STACK_NAME)
	local total = carry.fish + carry.food
	if total <= 0 then
		if stack then
			stack:Destroy()
		end
		return
	end
	if not stack then
		stack = Instance.new("Folder")
		stack.Name = STACK_NAME
		stack.Parent = character
	end
	assert(stack)

	-- Scale the number of fish/food blocks down proportionally if over the cap.
	local shown = math.min(total, Config.Visual.MaxStackParts)
	local fishShown = math.floor(carry.fish / total * shown + 0.5)

	local existing = stack:GetChildren()
	table.sort(existing, function(a, b)
		return (a:GetAttribute("Slot") or 0) < (b:GetAttribute("Slot") or 0)
	end)

	for slot = 1, shown do
		local kind = if slot <= fishShown then "Fish" else "Food"
		local block = existing[slot]
		if block and block.Name ~= kind then
			block:Destroy()
			block = nil
		end
		if not block then
			local part = makeBlock(kind)
			part:SetAttribute("Slot", slot)
			local height = root.Size.Y / 2 + Config.Visual.StackItemHeight * (slot - 0.5) - 1
			part.CFrame = root.CFrame * CFrame.new(0, height, -1.5)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
			part.Parent = stack
		end
	end
	for slot = shown + 1, #existing do
		existing[slot]:Destroy()
	end
end

return CarryVisual
