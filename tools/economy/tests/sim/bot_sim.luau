-- Blender Bot recovery: the REAL recovery-patched BotSystem (studio/bot/)
-- with the real EconomyService. An error mid-trip (injected into the bot
-- model) must not lose the piece in its hands: the clone goes, the piece is
-- HELD (the grinder re-emits it with the same identity), and the bot keeps
-- working. The sales-patched original is run the same way to show the bug.

local Economy = installEconomy()
local SS = services.ServerStorage
local SSS = services.ServerScriptService
local ws = workspaceInst

local owner = join(1, "Owner", Vector3.new(200, 5, 200))

local function scene()
	current = "server"
	for _, n in ipairs({ "Blender Bot", "MeatStack", "SaleMeat", "SaleTable" }) do
		local old = ws:FindFirstChild(n)
		if old then old:Destroy() end
	end
	local old = SS:FindFirstChild("MeatTemplate")
	if old then old:Destroy() end
	local bot = model("Blender Bot", ws, Vector3.new(-84.5, 10, 156))
	local stack = new("Folder", "MeatStack")
	stack.Parent = ws
	new("Folder", "SaleMeat").Parent = ws
	local tbl = part("SaleTable", Vector3.new(-80, 8, 152), ws)
	tbl:SetAttribute("SlotCount", 2)
	tbl:SetAttribute("Slot1", Vector3.new(-82, 9, 152))
	tbl:SetAttribute("Slot2", Vector3.new(-82, 9, 150))
	part("MeatTemplate", Vector3.new(0, -50, 0), SS, Vector3.new(1.5, 0.3, 1))
	current = nil
	return bot, stack
end

-- one piece of the owner's meat on the stack (as the grinder leaves it)
local function stackPiece(stack, index)
	return asServer(function()
		local id = Economy.issueFish(owner, "Cod", 1, { Source = "Net" })[1]
		local m = part("Meat", Vector3.new(-80, 9, 161 + index), nil, Vector3.new(1.5, 0.3, 1))
		Economy.stamp(m, id)
		m:SetAttribute("StackIndex", index)
		m.Parent = stack
		return id
	end)
end

local function carriedMeat()
	for _, c in ipairs(ws:GetChildren()) do
		if c.Name == "CarriedMeat" then return c end
	end
	return nil
end

local function runBot(src)
	local s = script("Script", "BotSystem", src, SSS)
	runScript(s)
	return s
end

------------------------------------------------------------ 1) normal trip

local bot, stack = scene()
local sc = runBot(SOURCES.Bot_Recovery)
local id1 = stackPiece(stack, 0)
local t = 0
repeat advance(0.2) t += 0.2 until #ws.SaleMeat:GetChildren() == 1 or t > 30
local onTable = ws.SaleMeat:GetChildren()[1]
check("normal: the piece reaches the table with its identity", onTable and onTable:GetAttribute("PieceId") == id1)
local before = balance(owner)
local paid = asServer(function() return (Economy.settle(id1, "Customer")) end)
check("normal: it sells once to its owner", paid == true and balance(owner) > before)
onTable:Destroy()

------------------------------------------------------------ 2) error while carrying: piece held, bot carries on

local id2 = stackPiece(stack, 0)
t = 0
repeat advance(0.05) t += 0.05 until carriedMeat() or t > 30
check("fault: the bot picked it up", carriedMeat() ~= nil and carriedMeat():GetAttribute("PieceId") == id2)
local warned = #warnings
rawset(bot, "PivotTo", function() error("bot model broken") end)
advance(0.5)
check("fault: the loose clone is removed", carriedMeat() == nil)
check("fault: the piece is held in the ledger, not lost", Economy.heldCount() == 1)
check("fault: warned once", #warnings == warned + 1 and warnings[#warnings]:find("piece kept", 1, true) ~= nil)
advance(12) -- still broken: backs off, no warning spam
check("fault: no warning spam while broken", #warnings == warned + 1)
check("fault: still nothing on the table", #ws.SaleMeat:GetChildren() == 0 and Economy.heldCount() == 1)
rawset(bot, "PivotTo", nil) -- fixed
local held = asServer(function() return Economy.takeHeld() end)
check("fault: the grinder gets the SAME piece back", held and held.id == id2 and held.state == "Live")
local id3 = stackPiece(stack, 0)
t = 0
repeat advance(0.2) t += 0.2 until #ws.SaleMeat:GetChildren() == 1 or t > 30
check("fault: the bot works again afterwards", #ws.SaleMeat:GetChildren() == 1 and ws.SaleMeat:GetChildren()[1]:GetAttribute("PieceId") == id3)
ws.SaleMeat:GetChildren()[1]:Destroy()

------------------------------------------------------------ 3) error with nothing in hand: nothing held

sc:Destroy()
bot, stack = scene()
sc = runBot(SOURCES.Bot_Recovery)
advance(0.5)
rawset(bot, "PivotTo", function() error("broken while idle") end)
advance(2)
check("idle fault: nothing held", Economy.heldCount() == 0)
rawset(bot, "PivotTo", nil)
sc:Destroy()

------------------------------------------------------------ 4) the unpatched sales BotSystem: the bug this fixes

bot, stack = scene()
local errs = #errors
runBot(SOURCES.Sales_BotSystem)
stackPiece(stack, 0)
t = 0
repeat advance(0.05) t += 0.05 until carriedMeat() or t > 30
rawset(bot, "PivotTo", function() error("bot model broken") end)
advance(1)
rawset(bot, "PivotTo", nil)
local stranded = carriedMeat() ~= nil and Economy.heldCount() == 0
local died = #errors > errs
for i = #errors, errs + 1, -1 do table.remove(errors, i) end -- expected: the old script dies
stackPiece(stack, 1)
advance(20)
check("unpatched: the piece is stranded and the bot stops for good (the bug)", stranded and died and #ws.SaleMeat:GetChildren() == 0)

finish("bot sim")
