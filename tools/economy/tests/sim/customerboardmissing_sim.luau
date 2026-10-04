-- The customer board when the place isn't as expected (REAL server + client):
--   * two Workspace children named Board: the server warns and makes no
--     remote; the client draws nothing and hides neither
--   * a card missing, or two cards with the same title: the client draws
--     nothing (warns), the board stays visible; with the server's remote
--     missing nothing can be bought either

local Economy, root = installEconomy()
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local MAIN = Vector3.new(-72.8355, 21.075, 136.483)

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
local b1, _, s1 = oldBoard(MAIN, { "Axe Speed", "Buy Miner" })
local b2, _, s2 = oldBoard(MAIN + Vector3.new(40, 0, 0), { "Axe Speed" })
dsData[KEY .. "1"] = { v = 2, money = 1000 }
local A = join(1, "Buyer", MAIN + Vector3.new(0, -9, 8))
warnings = {}
runScript(script("Script", "CustomerBoardServer", SOURCES.Cust_Server, SSS))
runAs(A, function()
	runScript(script("LocalScript", "CustomerBoardClient", SOURCES.Cust_Client), A)
end)
advance(1.5)
local function warnedWith(text)
	for _, w in ipairs(warnings) do
		if w:find(text, 1, true) then
			return true
		end
	end
	return false
end
local function seen(p, inst, prop)
	local v
	runAs(p, function()
		v = inst[prop]
	end)
	return v
end
check("two Boards: the server warns and makes no remote", warnedWith("expected exactly one Workspace.Board, found 2")
	and root:FindFirstChild("CustomerUpgradeAction") == nil)
check("two Boards: the client draws nothing and hides neither", A.PlayerGui:FindFirstChild("CustomerBoard") == nil
	and seen(A, s1, "Enabled") == true and seen(A, s2, "Enabled") == true)
current = "server"
b1.Parent = nil
current = nil
advance(1.5)
check("the Board left has no \"Buy Miner\" card: nothing drawn, it stays visible, a warning names the card",
	A.PlayerGui:FindFirstChild("CustomerBoard") == nil and seen(A, s2, "Enabled") == true
	and warnedWith("no single card titled \"Buy Miner\""))
check("nothing charged", Economy.balance(A) == 1000)

-- a Board with both cards, but "Axe Speed" twice: which one is meant can't be told
current = "server"
b2.Parent = nil
current = nil
local b3, _, s3, bord3 = oldBoard(MAIN, { "Axe Speed", "Buy Miner" })
current = "server"
local first
for _, c in ipairs(bord3:GetChildren()) do
	if c.ClassName == "Frame" and not first then
		first = c
	end
end
first:Clone().Parent = bord3
current = nil
warnings = {}
advance(1.5)
check("two cards titled \"Axe Speed\": nothing drawn (nothing guessed), the board stays visible",
	A.PlayerGui:FindFirstChild("CustomerBoard") == nil and seen(A, s3, "Enabled") == true and #bord3:GetChildren() == 4)

finish("customer board missing sim")
