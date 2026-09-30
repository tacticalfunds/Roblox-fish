-- Upgrade board with an ambiguous place: TWO Workspace children named Board.
-- The server refuses to guess (no UpgradeAction, nothing sold, a warning);
-- the client draws nothing and leaves both boards as they are. When one is
-- removed the client draws the remaining one, but with no server remote every
-- card says OFF and pressing sends nothing.

local Economy, root = installEconomy()
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local MAIN = Vector3.new(-72.84, 21.08, 136.48)

current = "server"
local surfaces, boards = {}, {}
for i = 1, 2 do
	local board = new("Model", "Board")
	local main = part("Main", MAIN + Vector3.new((i - 1) * 40, 0, 0), board, Vector3.new(19.53, 9.34, 0.85))
	local surface = new("SurfaceGui", "SurfaceGui")
	surface._props.Enabled = true
	local bord = new("Frame", "bord3")
	new("UIListLayout", "UIListLayout").Parent = bord
	new("Frame", "Frame").Parent = bord
	bord.Parent = surface
	surface.Parent = main
	board.Parent = ws
	surfaces[i], boards[i] = surface, board
end
current = nil

dsData[KEY .. "1"] = { v = 2, money = 2000 }
local A = join(1, "Buyer", MAIN + Vector3.new(0, -7, 6))
warnings = {}
runScript(script("Script", "UpgradeBoardServer", SOURCES.Board_Server, SSS))
runAs(A, function()
	runScript(script("LocalScript", "UpgradeBoardClient", SOURCES.Board_Client), A)
end)
advance(1.5)
root:SetAttribute("NetKgOpen", true)
advance(0.1)

local warned = false
for _, w in ipairs(warnings) do
	warned = warned or (w:find("expected exactly one Workspace.Board, found 2", 1, true) ~= nil)
end
check("two Boards: the server warns and makes no remote", warned and root:FindFirstChild("UpgradeAction") == nil)
local function seen(p, inst, prop)
	local v
	runAs(p, function()
		v = inst[prop]
	end)
	return v
end
check("two Boards: the client draws nothing and hides neither", A.PlayerGui:FindFirstChild("UpgradeBoard") == nil
	and seen(A, surfaces[1], "Enabled") == true and seen(A, surfaces[2], "Enabled") == true)

current = "server"
boards[2].Parent = nil
current = nil
advance(1.5)
local g = A.PlayerGui:FindFirstChild("UpgradeBoard")
local price = g and g.bord3.NetStrength.Buy.Price
check("one Board left: drawn, but without the server's remote every card says OFF / SOON", price ~= nil and price.Text == "OFF"
	and g.bord3.RodLuck.Buy.Price.Text == "OFF" and g.bord3.MeatPrice.Buy.Price.Text == "OFF" and g.bord3.FasterReels.Buy.Price.Text == "SOON")
click(A, g.bord3.NetStrength.Buy)
advance(0.5)
check("pressing sends nothing, charges nothing", price.Text == "OFF" and Economy.balance(A) == 2000 and lastNotice(A) == nil)

finish("board missing sim")
