-- FishVariantVisuals (ModuleScript in ReplicatedStorage).
-- Tasteful effects for Silver/Gold fish and their meat. Species colors and
-- details are never changed; the effects are ADDED as non-BasePart children
-- (a Highlight outline with a faint tint, a few sparkles, a small light, a
-- label), so FishSwimClient's part list and BulkMoveTo animation are
-- unaffected. Uses only built-in particle textures; no external assets.
--
-- Cost per variant object: 1 ParticleEmitter (3-4 particles/s), 1 PointLight
-- without shadows, and for fish 1 Highlight + 1 BillboardGui. Variants are
-- rare (~2.5% of fish), so this stays cheap with 60 river fish. Roblox renders
-- at most 31 Highlights per client; beyond that the outline alone is skipped.

local FishVariants = require(script.Parent.FishVariants)

local V = {}

local FX = "VariantFx"

local function colorOf(name: string): Color3
	local c = FishVariants.Defs[name].Color
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function rootPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function sparkles(parent: Instance, color: Color3, rate: number, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = FX .. "Sparkles"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(0.4, 1)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
end

local function light(parent: Instance, color: Color3, range: number)
	local l = Instance.new("PointLight")
	l.Name = FX .. "Light"
	l.Color = color
	l.Brightness = 1.2
	l.Range = range
	l.Shadows = false
	l.Parent = parent
end

-- Fish models (river, rod reveal, aquarium). `label` defaults to true.
function V.applyToFish(model: Instance, variant: any, label: boolean?)
	local name = FishVariants.sanitize(variant)
	if not name or model:FindFirstChild(FX) then
		return
	end
	local color = colorOf(name)
	local folder = Instance.new("Folder")
	folder.Name = FX

	local hl = Instance.new("Highlight")
	hl.Adornee = model
	hl.FillColor = color
	hl.FillTransparency = 0.82 -- faint tint: species colors stay readable
	hl.OutlineColor = color
	hl.OutlineTransparency = 0.15
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = folder

	local root = rootPart(model)
	if root then
		local att = Instance.new("Attachment")
		att.Name = FX .. "Att"
		att.Parent = root
		sparkles(att, color, if name == "Gold" then 4 else 3, 0.3)
		light(root, color, 6)
		if label ~= false then
			local gui = Instance.new("BillboardGui")
			gui.Name = FX .. "Label"
			gui.Adornee = root
			gui.Size = UDim2.fromOffset(84, 22)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
			gui.MaxDistance = 80
			gui.LightInfluence = 0
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.FredokaOne
			text.TextScaled = true
			text.Text = FishVariants.Defs[name].Label
			text.TextColor3 = color
			text.TextStrokeColor3 = Color3.fromRGB(30, 30, 40)
			text.TextStrokeTransparency = 0.2
			text.Parent = gui
			gui.Parent = folder
		end
	end
	folder.Parent = model
end

-- Meat pieces (blender, belt, stack, carried, loaded, held by a customer):
-- a small glow and sparkles only, so a full stack doesn't get cluttered.
function V.applyToPart(part: Instance, variant: any)
	local name = FishVariants.sanitize(variant)
	if not name or not part:IsA("BasePart") or part:FindFirstChild(FX .. "Att") then
		return
	end
	local color = colorOf(name)
	local att = Instance.new("Attachment")
	att.Name = FX .. "Att"
	att.Parent = part
	sparkles(att, color, 2, 0.2)
	light(part, color, 4)
end

return V
