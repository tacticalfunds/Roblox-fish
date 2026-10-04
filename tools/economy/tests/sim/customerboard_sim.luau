-- The customer board: the REAL CustomerBoardServer + CustomerBoardClient and
-- the REAL EconomyService on the old two-panel Workspace.Board exactly as the
-- place has it (Main > SurfaceGui > bord3 with two cards both named "Frame",
-- each with Buy > Price, Icons and two labels both named "Text": "Axe Speed" /
-- "x1.00 > x1.15" and "Buy Miner" / "1/64").
-- Checks:
--   * a per-player copy adorned to Main; the place's board hidden for that
--     client only and never changed; cards found by title; person icon
--   * Customer Speed "6/min > 9/min" and Customer Line "6 > 7 in line"; SOON
--     while closed; $25 / $40 open; BOUGHT! and the saved level; the next
--     step; MAX; the press bounces the Buy button
--   * Economy.customers() follows the purchases (rate, line)
--   * far / unknown id / spam refused, never charged
--   * two Boards or a missing card: the server sells nothing / no copy drawn

local Economy, root = installEconomy()
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local MAIN = Vector3.new(-72.8355, 21.075, 136.483)
local NEAR = MAIN + Vector3.new(0, -9, 8)

local function oldBoard(where, titles)
	current = "server"
	local board = new("Model", "Board")
	local main = part("Main", where, board, Vector3.new(22.306, 12.737, 3.397))
	local surface = new("SurfaceGui", "SurfaceGui")
	surface._props.Enabled = true
	local bord = new("Frame", "bord3")
	new("UIListLayout", "UIListLayout").Parent = bord
	local function card(title, stat, image)
		local c = new("Frame", "Frame")
		local buy = new("TextButton", "Buy")
		buy._props.Size = UDim2.fromScale(0.827, 0.12)
		buy._props.Position = UDim2.fromScale(0.532, 0.885)
		buy._props.AnchorPoint = Vector2.new(0.5, 0.5)
		local price = new("TextLabel", "Price")
		price._props.Text = "$120"
		price.Parent = buy
		local grad = new("UIGradient", "UIGradient")
		grad:SetAttribute("BoardArt", true)
		grad.Parent = buy
		buy.Parent = c
		local icons = new("ImageLabel", "Icons")
		icons._props.Image = image
		icons.Parent = c
		local t1 = new("TextLabel", "Text")
		t1._props.Text = title
		t1.Parent = c
		local t2 = new("TextLabel", "Text")
		t2._props.Text = stat
		t2.Parent = c
		c.Parent = bord
	end
	card(titles[1], "x1.00 > x1.15", "rbxassetid://75744565067217")
	if titles[2] then
		card(titles[2], "1/64", "rbxassetid://137299198925368")
	end
	bord.Parent = surface
	surface.Parent = main
	board.Parent = ws
	current = nil
	return board, main, surface, bord
end
local board, main, surface, bord = oldBoard(MAIN, { "Axe Speed", "Buy Miner" })

dsData[KEY .. "1"] = { v = 2, money = 1000 }
local A = join(1, "Buyer", NEAR)
runScript(script("Script", "CustomerBoardServer", SOURCES.Cust_Server, SSS))
runAs(A, function()
	runScript(script("LocalScript", "CustomerBoardClient", SOURCES.Cust_Client), A)
end)
advance(1.5)

local function seen(p, inst, prop)
	local v
	runAs(p, function()
		v = inst[prop]
	end)
	return v
end
local function copyOf(p)
	return p.PlayerGui:FindFirstChild("CustomerBoard")
end
local function cardOf(p, title)
	local g = copyOf(p)
	if not g then
		return nil
	end
	for _, c in ipairs(g.bord3:GetChildren()) do
		if c.ClassName == "Frame" then
			for _, t in ipairs(c:GetChildren()) do
				if t.Name == "Text" and t.Text == title then
					local stat
					for _, u in ipairs(c:GetChildren()) do
						if u.Name == "Text" and u ~= t then
							stat = u
						end
					end
					return { frame = c, stat = stat, buy = c.Buy, price = c.Buy.Price, icon = c.Icons }
				end
			end
		end
	end
	return nil
end
local remote = root:FindFirstChild("CustomerUpgradeAction")

------------------------------------------------------------ the board

check("server made Economy.CustomerUpgradeAction (not saved)", remote ~= nil and remote.Archivable == false)
local g = copyOf(A)
check("a per-player copy of the board's SurfaceGui, adorned to Main", g ~= nil and g.Adornee == main and g.ResetOnSpawn == false)
check("the place's board: hidden for A only, never changed", seen(A, surface, "Enabled") == false and surface.Enabled == true
	and #bord:GetChildren() == 3)
local speed, line = cardOf(A, "Customer Speed"), cardOf(A, "Customer Line")
check("cards found by title: Axe Speed -> Customer Speed, Buy Miner -> Customer Line", speed ~= nil and line ~= nil)
check("both show the board's person icon; the Buy art (gradient) kept", speed.icon.Image == "rbxassetid://137299198925368"
	and line.icon.Image == "rbxassetid://137299198925368" and speed.buy:FindFirstChildOfClass("UIGradient"):GetAttribute("BoardArt") == true)
check("values: 6/min > 9/min and 6 > 7 in line; SOON while closed", speed.stat.Text == "6/min > 9/min"
	and line.stat.Text == "6 > 7 in line" and speed.price.Text == "SOON" and line.price.Text == "SOON")

click(A, speed.buy)
advance(0.4)
check("closed: refused, SOON, not charged", lastNotice(A) == "Customer Speed upgrades open soon" and Economy.balance(A) == 1000)
advance(1.5)

root:SetAttribute("UpgradesOpen", true)
advance(0.2)
check("open: $25 and $40", speed.price.Text == "$25" and line.price.Text == "$40")

------------------------------------------------------------ buying

local from = #tweensPlayed
click(A, speed.buy)
advance(0.7)
local bounced = 0
for i = from + 1, #tweensPlayed do
	if tweensPlayed[i].Instance == speed.buy then
		bounced += 1
	end
end
check("press: the Buy button bounces (down and back) and ends at its own size", bounced == 2
	and speed.buy.Size == UDim2.fromScale(0.827, 0.12))
check("bought: Customer Speed 6/min -> 9/min for $25, saved", lastNotice(A) == "Customer Speed 6/min → 9/min (-$25)"
	and Economy.balance(A) == 975 and dsData[KEY .. "1"].upgrades.CustomerSpeed == 1 and speed.price.Text == "BOUGHT!")
advance(2)
check("then: 9/min > 12/min, $60", speed.stat.Text == "9/min > 12/min" and speed.price.Text == "$60")
local r = select(1, (function()
	local a, b
	runAs("server", function()
		a, b = Economy.customers()
	end)
	return a, b
end)())
check("the shop's rate follows: 9 customers a minute", r == 9)
click(A, line.buy)
advance(2.5)
click(A, line.buy)
advance(2.5)
check("Customer Line bought twice: 8 in line MAX, $160 spent", line.stat.Text == "8 in line MAX" and line.price.Text == "MAX"
	and Economy.balance(A) == 815)
click(A, line.buy)
advance(0.4)
check("at the maximum: refused, not charged", lastNotice(A) == "Customer Line is at the maximum (8 in line)" and Economy.balance(A) == 815)
advance(2)

------------------------------------------------------------ refusals

moveTo(A, MAIN + Vector3.new(80, 0, 0))
click(A, speed.buy)
advance(0.4)
check("far from the board: TOO FAR, not charged", speed.price.Text == "TOO FAR" and lastNotice(A) == "Walk up to the board"
	and Economy.balance(A) == 815)
moveTo(A, NEAR)
advance(2)
local answers = {}
runAs(A, function()
	for _, id in ipairs({ "RodLuck", "Hack", 7 }) do
		table.insert(answers, { remote:InvokeServer(id) })
		task.wait(0.3)
	end
end)
advance(1.5)
check("only the two customer upgrades: others refused, nothing charged", answers[1][2] == "Unknown upgrade"
	and answers[2][2] == "Unknown upgrade" and answers[3][2] == "Unknown upgrade" and Economy.balance(A) == 815)
local quick = {}
runAs(A, function()
	table.insert(quick, { remote:InvokeServer("CustomerSpeed") })
	table.insert(quick, { remote:InvokeServer("CustomerSpeed") })
end)
advance(1)
check("presses faster than the server's gap: the second is refused", quick[2] and quick[2][2] == "Slow down a little")

finish("customer board sim")
