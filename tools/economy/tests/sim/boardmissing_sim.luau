-- The board art's edge cases, with the REAL UpgradeBoardServer +
-- UpgradeBoardClient:
--   * TWO Workspace children named "Upgrade board": the server refuses to
--     guess (no UpgradeAction, nothing sold, a warning); the client still
--     binds the player's art, but with no remote every card says OFF and
--     pressing sends nothing
--   * a card without the exact shape (Btn without Price, Price nested deeper,
--     two Frames with the card's name): left alone, the client names it in a
--     warning; the other cards work
--   * two UpgradeBoardGui copies in PlayerGui: none is bound (nothing guessed)
--   * the old Workspace.Board is never used or changed

local Economy, root = installEconomy()
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local MAIN = Vector3.new(-72.84, 21.08, 136.48)

local _, screen1 = upgradeBoard(MAIN)
upgradeBoard(MAIN + Vector3.new(40, 0, 0))
-- the old board, as the place has it (must stay untouched)
current = "server"
local oldBoard = new("Model", "Board")
local oldMain = part("Main", MAIN + Vector3.new(0, 30, 0), oldBoard, Vector3.new(19.53, 9.34, 0.85))
local oldSurface = new("SurfaceGui", "SurfaceGui")
oldSurface._props.Enabled = true
local bord = new("Frame", "bord3")
local oldPrice = new("TextLabel", "Price")
oldPrice._props.Text = "$ 120"
oldPrice.Parent = bord
bord.Parent = oldSurface
oldSurface.Parent = oldMain
oldBoard.Parent = ws
current = nil

dsData[KEY .. "1"] = { v = 2, money = 2000 }
local A = join(1, "Buyer", MAIN + Vector3.new(0, -7, 6))
warnings = {}
runScript(script("Script", "UpgradeBoardServer", SOURCES.Board_Server, SSS))
local artGui = boardArt(A, screen1, function(name, frame)
	if name == "Faster Reels" then
		frame.Btn.Price:Destroy() -- not the exact shape
	elseif name == "Rod Luck" then
		local holder = new("Frame", "Holder") -- Price one level deeper: not Btn.Price
		holder.Parent = frame.Btn
		frame.Btn.Price.Parent = holder
	end
end)
current = "server"
local dupe = new("Frame", "Meat Price") -- a second Frame with that card's name
local dupeDesc = new("TextLabel", "Desc")
dupeDesc._props.Text = "dupe"
dupeDesc.Parent = dupe
dupe.Parent = artGui
current = nil
runAs(A, function()
	runScript(script("LocalScript", "UpgradeBoardClient", SOURCES.Board_Client), A)
end)
advance(1.5)
root:SetAttribute("NetKgOpen", true)
advance(0.1)

local function warnedWith(text)
	for _, w in ipairs(warnings) do
		if w:find(text, 1, true) then
			return true
		end
	end
	return false
end
check("two Upgrade boards: the server warns and makes no remote", warnedWith("expected exactly one Workspace.Upgrade board, found 2")
	and root:FindFirstChild("UpgradeAction") == nil)
local net = artCard(A, "Net Strength")
check("the client binds the art anyway: without the server's remote the bound card says OFF", net.Buy.Price.Text == "OFF")
-- what a bound card would show for these values
runAs("server", function()
	A:SetAttribute("NetKg", 33)
	A:SetAttribute("NetKgNext", 38)
	A:SetAttribute("NetKgCost", 5)
	for _, id in ipairs({ "RodLuck", "MeatPrice", "FasterReels" }) do
		A:SetAttribute("Upg" .. id, 1)
		A:SetAttribute("Upg" .. id .. "Next", 4)
		A:SetAttribute("Upg" .. id .. "Cost", 7)
	end
end)
advance(0.2)
check("the bound card follows the values (Desc 33 > 38kg)", net.Value.Text == "33 > 38kg")
check("a card without Btn.Price: left alone and named in a warning", warnedWith("\"Faster Reels\" needs one TextLabel Desc and one Btn with one TextLabel Price")
	and artCard(A, "Faster Reels").Value.Text == "1x >1.2x")
local rodLuck = artGui:FindFirstChild("Rod Luck")
check("a card whose Price is nested deeper: left alone (not Btn.Price)", warnedWith("\"Rod Luck\" needs one TextLabel Desc")
	and rodLuck.Desc.Text == "1x >2x" and rodLuck.Btn.Holder.Price.Text == "$10")
local meatDescs = {}
for _, c in ipairs(artGui:GetChildren()) do
	if c.Name == "Meat Price" then
		table.insert(meatDescs, c.Desc.Text)
	end
end
check("two Frames named Meat Price: neither is written to", warnedWith("no single Frame \"Meat Price\"") and #meatDescs == 2
	and table.find(meatDescs, "1x >2x") ~= nil and table.find(meatDescs, "dupe") ~= nil)
click(A, net.Buy)
advance(0.5)
check("pressing sends nothing, charges nothing", net.Buy.Price.Text == "OFF" and Economy.balance(A) == 2000 and lastNotice(A) == nil)
check("no generated board gui; the old Workspace.Board untouched", A.PlayerGui:FindFirstChild("UpgradeBoard") == nil
	and oldSurface.Enabled == true and oldPrice.Text == "$ 120" and #bord:GetChildren() == 1)

-- a second copy of the gui in PlayerGui: nothing guessed
boardArt(A, screen1)
advance(0.5)
local copies = {}
for _, c in ipairs(A.PlayerGui:GetChildren()) do
	if c.Name == "UpgradeBoardGui" then
		table.insert(copies, c)
	end
end
runAs("server", function()
	A:SetAttribute("NetKg", 44)
	A:SetAttribute("NetKgNext", 49)
end)
advance(0.2)
check("two UpgradeBoardGui copies: neither is written to any more", #copies == 2
	and copies[1]:FindFirstChild("Net Strength").Desc.Text == "33 > 38kg" and copies[2]:FindFirstChild("Net Strength").Desc.Text == "15 >20kg")


finish("board missing sim")
