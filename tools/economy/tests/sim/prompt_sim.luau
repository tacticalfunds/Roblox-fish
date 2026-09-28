-- Rod-stand buy prompt: the REAL EconomyService (+ core) and the REAL
-- EconomyClient (one copy per player) on the fake engine (engine.luau).
-- Covers: caster-only prompt, its settings, the custom panel and input
-- types, show/hide with range, nearest-only, buy once under spam, server
-- reach from the stand, not enough Money, and cleanup on buy / timeout /
-- pass / death / leave / switch-off.

installEconomy()
local standsFolder = workspaceInst:FindFirstChild("EconomyBuyStands")
check("runtime stands folder created, not archivable", standsFolder ~= nil and standsFolder.Archivable == false)

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

finish("prompt sim")
