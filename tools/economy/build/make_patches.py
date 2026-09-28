#!/usr/bin/env python3
"""Generates the Milestone 2 (money + sale settlement) patches.

Bases are the live sources Astra supplied (tools/economy/studio/live/).
Every edit is asserted to match exactly once; the output goes to
tools/economy/studio/patched/. Each patched script loads EconomyService
optionally: if it is missing or not running, the script behaves exactly
like its live base.

Usage:  python3 tools/economy/build/make_patches.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIVE = ROOT / "studio" / "live"
OUT = ROOT / "studio" / "patched"

SCRIPTS = ["GrinderProcessor", "BotSystem", "CustomerSystem", "TruckSystem", "NetLiftScript", "HarpoonSystem", "RodShopServer"]


def loader(tag: str) -> str:
    return f"""
-- Economy: optional money service (missing or not running -> original behaviour)
local Economy = nil
do
	local mod = game:GetService("ServerScriptService"):FindFirstChild("EconomyService")
	if mod and mod:IsA("ModuleScript") then
		local ok, api = pcall(require, mod)
		if ok and type(api) == "table" then
			local ran, running = pcall(api.start)
			if ran and running then
				Economy = api
			else
				warn("[{tag}] economy not running, original behaviour: " .. tostring(running))
			end
		else
			warn("[{tag}] could not load EconomyService, original behaviour: " .. tostring(api))
		end
	end
end
"""


def header(lines: list[str]) -> str:
    body = "".join(f"-- {line}\n" if line else "--\n" for line in lines)
    return "--\n-- [Economy patch v1] Changes vs. the live script are marked \"Economy\".\n" + body


class Patch:
    def __init__(self, src: str):
        self.src = src

    def rep(self, old: str, new: str) -> None:
        count = self.src.count(old)
        assert count == 1, f"expected 1 match, got {count}: {old[:80]!r}"
        self.src = self.src.replace(old, new)


def grinder(src: str) -> str:
    p = Patch(src)
    p.rep(
        "--    and stacks up neatly in the box at the end.\n",
        "--    and stacks up neatly in the box at the end.\n"
        + header(
            [
                "With ServerScriptService.EconomyService running, every meat piece gets a ledger",
                "record (PieceId; owner and value fixed here) that is paid once when it sells.",
                "Nothing is destroyed unpaid any more: when the pit or the stack is full, pieces",
                "wait (in the blender queue, or as held ledger data) and come back out of the",
                "pipe when there is room. Without EconomyService this runs exactly as before.",
            ]
        ),
    )
    p.rep(
        'local pit = workspace:WaitForChild("Pit")\n',
        'local pit = workspace:WaitForChild("Pit")\n' + loader("GrinderProcessor"),
    )
    # backpressure helpers, right after the stack slot function
    p.rep(
        "------------------------------------------------------------------ BELT (one at a time)\n",
        """-- Economy: backpressure. A piece goes onto the belt only if the stack will
-- have room for it, and new pieces are shot into the pit only while the pit
-- has room; otherwise they wait (blender queue / held ledger data).
local onBelt = 0
local function stackHasRoom()
	if not Economy then return true end
	local stackFolder = workspace:FindFirstChild("MeatStack") or pitMeat
	return #stackFolder:GetChildren() + onBelt < MAX_STACK
end
local function pitHasRoom()
	local n = 0
	for _, m in ipairs(pitMeat:GetChildren()) do
		if m:GetAttribute("StackIndex") == nil then n += 1 end
	end
	return n < Economy.pipeline().MaxPitObjects
end

------------------------------------------------------------------ BELT (one at a time)
""",
    )
    p.rep(
        """	if count >= MAX_STACK then
		meat:Destroy() -- stack is full
		return
	end
""",
        """	if count >= MAX_STACK then
		-- Economy: never lose unpaid meat - keep the piece as held ledger data
		if Economy then Economy.hold(meat:GetAttribute("PieceId")) end
		meat:Destroy() -- stack is full
		return
	end
""",
    )
    p.rep(
        """			if clear then
				table.remove(beltQueue, 1)
				lastOnBelt = { part = first, t0 = os.clock() + 0.5 } -- reserve while it hops on
				task.spawn(runBelt, first)
			end
""",
        """			if clear and stackHasRoom() then -- Economy: wait while the stack is full
				table.remove(beltQueue, 1)
				lastOnBelt = { part = first, t0 = os.clock() + 0.5 } -- reserve while it hops on
				onBelt += 1
				task.spawn(function()
					local ok, err = pcall(runBelt, first)
					onBelt -= 1
					if not ok then warn("[GrinderProcessor] belt: " .. tostring(err)) end
				end)
			end
""",
    )
    p.rep(
        """local function shootMeat(info)
	local meat = meatTemplate:Clone()
	meat.Name = "Meat"
	meat:SetAttribute("FromFish", info.fishName)
	meat:SetAttribute("Tier", info.tier)
	if info.player then meat:SetAttribute("OwnerId", info.player.UserId) end
""",
        """local function shootMeat(info, pieceId)
	local meat = meatTemplate:Clone()
	meat.Name = "Meat"
	meat:SetAttribute("FromFish", info.fishName)
	meat:SetAttribute("Tier", info.tier)
	if info.player then meat:SetAttribute("OwnerId", info.player.UserId) end
	if Economy and pieceId then Economy.stamp(meat, pieceId) end -- Economy: PieceId, owner, value, variant
""",
    )
    p.rep(
        """	for _, info in ipairs(batch) do
		for i = 1, meatFor(info.tier) do
			task.spawn(shootMeat, info)
			task.wait(0.22)
		end
	end
""",
        """	for _, info in ipairs(batch) do
		if Economy then
			-- Economy: one ledger piece per meat piece (same count as meatFor);
			-- pieces the pit has no room for are held as data, not dropped
			for _, pieceId in ipairs(Economy.issueFish(info.player, info.fishName, info.tier, info.meta)) do
				if pitHasRoom() then
					task.spawn(shootMeat, info, pieceId)
					task.wait(0.22)
				else
					Economy.hold(pieceId)
				end
			end
		else
			for i = 1, meatFor(info.tier) do
				task.spawn(shootMeat, info)
				task.wait(0.22)
			end
		end
	end
""",
    )
    p.rep(
        """caught.Event:Connect(function(player, fishName, tier)
	table.insert(pending, { player = player, fishName = fishName, tier = tier })
""",
        """caught.Event:Connect(function(player, fishName, tier, meta) -- Economy: meta = { OwnerId, Variant, Source }
	table.insert(pending, { player = player, fishName = fishName, tier = tier, meta = meta })
""",
    )
    p.src = p.src.rstrip("\n") + "\n" + """
-- Economy: held pieces (pit/stack was full, or a carrier left) come back out
-- of the pipe, oldest first, whenever the pit has room again.
if Economy then
	task.spawn(function()
		while true do
			task.wait(0.5)
			while pitHasRoom() do
				local piece = Economy.takeHeld()
				if not piece then break end
				task.spawn(shootMeat, { fishName = piece.fishName, tier = piece.tier }, piece.id)
				task.wait(0.22)
			end
		end
	end)
end
"""
    return p.src


def bot(src: str) -> str:
    p = Patch(src)
    p.rep(
        "-- carrying one piece of meat at a time and laying it on the table for customers.\n",
        "-- carrying one piece of meat at a time and laying it on the table for customers.\n"
        + header(
            [
                "The carried/table clone keeps the picked piece's identity (PieceId, owner,",
                "variant, tier, value), so the customer sale pays the right owner once.",
            ]
        ),
    )
    p.rep(
        'local meatTemplate = SS:WaitForChild("MeatTemplate")\n',
        'local meatTemplate = SS:WaitForChild("MeatTemplate")\n' + loader("BotSystem"),
    )
    p.rep(
        """	local from = meat.Position
	meat:Destroy()
	local c = meatTemplate:Clone()
	c.Name = "CarriedMeat"
""",
        """	local from = meat.Position
	local tags = Economy and Economy.readPiece(meat) -- Economy: keep the piece's identity
	meat:Destroy()
	local c = meatTemplate:Clone()
	c.Name = "CarriedMeat"
	if tags then Economy.writePiece(c, tags) end
""",
    )
    return p.src


def customer(src: str) -> str:
    p = Patch(src)
    p.rep(
        "-- (if there is any), and walk back into the city.\n",
        "-- (if there is any), and walk back into the city.\n"
        + header(
            [
                "A customer's purchase is the piece's one sale: EconomyService pays the piece's",
                "owner its ledger value. The tier is read before the piece is destroyed.",
            ]
        ),
    )
    p.rep(
        'local bought = SS:WaitForChild("CustomerEvents"):WaitForChild("CustomerBought")\n',
        'local bought = SS:WaitForChild("CustomerEvents"):WaitForChild("CustomerBought")\n' + loader("CustomerSystem"),
    )
    p.rep(
        """		if meat then
			giveMeat(c, meat)
			bought:Fire(c.model.Name, meat:GetAttribute("Tier"))
""",
        """		if meat then
			local tier = meat:GetAttribute("Tier") -- Economy: read before giveMeat destroys it
			if Economy then Economy.settle(meat:GetAttribute("PieceId"), "Customer") end -- Economy: the one sale
			giveMeat(c, meat)
			bought:Fire(c.model.Name, tier)
""",
    )
    return p.src


def truck(src: str) -> str:
    p = Patch(src)
    p.rep(
        "-- (Trucks are drawn/moved on each client by TruckClient using the \"S\" attribute; server keeps the logic.)\n",
        "-- (Trucks are drawn/moved on each client by TruckClient using the \"S\" attribute; server keeps the logic.)\n"
        + header(
            [
                "Players carry the ledger ids of the meat they pick up. Dropping a piece in a",
                "truck is that piece's one sale (paid to the piece's owner, not the carrier).",
                "If a carrier leaves or respawns, their pieces are held and come back out of",
                "the grinder pipe instead of vanishing unpaid. Truck UI is unchanged.",
            ]
        ),
    )
    p.rep(
        'local events = SS:WaitForChild("TruckEvents")\n',
        'local events = SS:WaitForChild("TruckEvents")\n' + loader("TruckSystem"),
    )
    p.rep(
        "local carry = {} -- player -> {count, parts}\n",
        """local carry = {} -- player -> {count, parts, ids}

-- Economy: ledger ids of the meat a player carries (false = untracked piece).
-- A carrier who leaves or respawns gives them back as held pieces.
local function dropCarried(c)
	if Economy and c and c.ids then
		for _, id in ipairs(c.ids) do
			if id then Economy.hold(id) end
		end
		table.clear(c.ids)
	end
end
""",
    )
    p.rep(
        "			carry[player] = carry[player] or { count = 0, parts = {} }\n",
        "			carry[player] = carry[player] or { count = 0, parts = {}, ids = {} }\n",
    )
    p.rep(
        """				if meat then
					local from = meat.Position
					meat:Destroy()
""",
        """				if meat then
					local from = meat.Position
					local pieceId = meat:GetAttribute("PieceId") -- Economy
					meat:Destroy()
					if Economy then
						table.insert(c.ids, if pieceId and Economy.carry(pieceId) then pieceId else false)
					end
""",
    )
    p.rep(
        """				if d <= DELIVER_RANGE then
					c.count -= 1
""",
        """				if d <= DELIVER_RANGE then
					c.count -= 1
					if Economy then Economy.settle(table.remove(c.ids), "Truck") end -- Economy: the one sale
""",
    )
    p.rep(
        "Players.PlayerRemoving:Connect(function(p) carry[p] = nil end)\n",
        "Players.PlayerRemoving:Connect(function(p) dropCarried(carry[p]) carry[p] = nil end)\n",
    )
    p.rep(
        """	p.CharacterAdded:Connect(function()
		carry[p] = { count = 0, parts = {} }
""",
        """	p.CharacterAdded:Connect(function()
		dropCarried(carry[p]) -- Economy
		carry[p] = { count = 0, parts = {}, ids = {} }
""",
    )
    return p.src


def netlift(src: str) -> str:
    p = Patch(src)
    p.rep(
        "-- Server: handles the step pad. The net animation + splash runs on each client (NetLiftClient).\n",
        "-- Server: handles the step pad. The net animation + splash runs on each client (NetLiftClient).\n"
        + header(
            [
                "Each catch also sends { OwnerId, Variant, Source = \"Net\" } as a 4th value, so a",
                "bought fish keeps its buyer (the grinder falls back to the pad player). While",
                "EconomyService reports the meat pipeline saturated, the pad refuses to lift",
                "(fish stay in the river). The MaxWeight rule is unchanged.",
            ]
        ),
    )
    p.rep("caughtEvent.Parent = model\n", "caughtEvent.Parent = model\n" + loader("NetLiftScript"))
    p.rep(
        """				task.delay(1.65, function()
					caughtEvent:Fire(player, m.Name, m:GetAttribute("Tier"))
""",
        """				task.delay(1.65, function()
					caughtEvent:Fire(player, m.Name, m:GetAttribute("Tier"), {
						OwnerId = m:GetAttribute("OwnerId"), -- Economy: a bought fish keeps its buyer
						Variant = m:GetAttribute("Variant"),
						Source = "Net",
					})
""",
    )
    p.rep(
        """	busy = true
	pressPad(true)
""",
        """	busy = true
	pressPad(true)
	-- Economy: grinder backed up -> no lift; the fish stay in the river
	if Economy and Economy.saturated() then
		Economy.notify(player, "The grinder is backed up - let the meat clear first", "warn")
		task.wait(0.6)
		pressPad(false)
		task.wait(0.4)
		busy = false
		return
	end
""",
    )
    return p.src


def harpoon(src: str) -> str:
    p = Patch(src)
    p.rep(
        "-- (Later this can be a Robux upgrade: just gate the loop below.)\n",
        "-- (Later this can be a Robux upgrade: just gate the loop below.)\n"
        + header(
            [
                "Targeting is effectively random (random score, slightly prefers closer fish);",
                "it is NOT rarity-biased despite the note above. Each catch sends",
                "{ OwnerId, Variant, Source = \"Harpoon\" }: the owner is the fish's buyer if it",
                "has one, else the player explicitly bound in HarpoonGun's OwnerUserId attribute,",
                "else nobody (the meat sells but pays no one - never an arbitrary player).",
                "Shots are skipped while EconomyService reports the meat pipeline saturated.",
            ]
        ),
    )
    p.rep(
        'local fishCaught = workspace:WaitForChild("NetLift"):WaitForChild("FishCaught")\n',
        'local fishCaught = workspace:WaitForChild("NetLift"):WaitForChild("FishCaught")\n'
        + loader("HarpoonSystem")
        + """
-- Economy: who is paid for a harpooned fish (see header)
local function harpoonMeta(fish)
	local owner = fish:GetAttribute("OwnerId")
	if type(owner) ~= "number" then
		local bound = gunModel:GetAttribute("OwnerUserId")
		owner = if type(bound) == "number" then bound else nil
	end
	return { OwnerId = owner, Variant = fish:GetAttribute("Variant"), Source = "Harpoon" }
end
""",
    )
    p.rep(
        '			fishCaught:Fire(nil, fish.Name, fish:GetAttribute("Tier") or 1)\n',
        '			fishCaught:Fire(nil, fish.Name, fish:GetAttribute("Tier") or 1, harpoonMeta(fish)) -- Economy: owner payload\n',
    )
    p.rep(
        """	task.wait(math.random(FIRE_EVERY[1] * 10, FIRE_EVERY[2] * 10) / 10)
	local ok, err = pcall(fire)
""",
        """	task.wait(math.random(FIRE_EVERY[1] * 10, FIRE_EVERY[2] * 10) / 10)
	if Economy and Economy.saturated() then continue end -- Economy: grinder backed up, skip this shot
	local ok, err = pcall(fire)
""",
    )
    return p.src


def rodshop(src: str) -> str:
    p = Patch(src)
    p.rep(
        '-- Stock lives on the player as attributes "RodStock_<RodName>", owned rods as "RodOwned_<RodName>".\n',
        '-- Stock lives on the player as attributes "RodStock_<RodName>", owned rods as "RodOwned_<RodName>".\n'
        + header(
            [
                "With EconomyService running, rods are charged through it (never by writing",
                "leaderstats.Money directly, which EconomyService reverts). The shop stays",
                "closed (Config.RodShopOpen = false) until owning a rod does something and is",
                "saved; stock/restock and the RodOwned attributes are unchanged.",
            ]
        ),
    )
    p.rep(
        'local EVERY = shop:GetAttribute("RestockEvery") or 300\n',
        'local EVERY = shop:GetAttribute("RestockEvery") or 300\n' + loader("RodShopServer"),
    )
    p.rep(
        """	local price = rod:GetAttribute("Price") or 0
	local money, setMoney = getMoney(player)
	if money == nil then return false, "No money system yet" end
	if money < price then return false, "Not enough money" end
	setMoney(money - price)
""",
        """	local price = rod:GetAttribute("Price") or 0
	if Economy then
		-- Economy: charged through EconomyService; closed until rods are linked to stats
		if not Economy.rodShopOpen() then return false, "Rod shop opens soon" end
		if type(price) ~= "number" or price < 0 or price ~= math.floor(price) then return false, "Unknown rod" end
		if price > 0 then
			local paid, why = Economy.tryDebit(player, price, "Rod:" .. rod.Name)
			if not paid then return false, if why == "funds" then "Not enough money" else "Money not loaded yet" end
		end
	else
		local money, setMoney = getMoney(player)
		if money == nil then return false, "No money system yet" end
		if money < price then return false, "Not enough money" end
		setMoney(money - price)
	end
""",
    )
    return p.src


BUILDERS = {
    "GrinderProcessor": grinder,
    "BotSystem": bot,
    "CustomerSystem": customer,
    "TruckSystem": truck,
    "NetLiftScript": netlift,
    "HarpoonSystem": harpoon,
    "RodShopServer": rodshop,
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in SCRIPTS:
        base = (LIVE / f"{name}.lua").read_text()
        out = BUILDERS[name](base)
        assert out != base
        (OUT / f"{name}.lua").write_text(out)
        print(f"wrote studio/patched/{name}.lua")


if __name__ == "__main__":
    main()
