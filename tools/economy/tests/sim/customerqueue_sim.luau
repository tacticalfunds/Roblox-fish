-- The customer queue: the REAL tuning + customer-behaviour code of the
-- CustomerSystem (the board release's, and the queue fix), run on its own
-- with small fake customers (a root part, a humanoid whose MoveTo arrives
-- after 0.5 s unless the target is unreachable). A customer's root part
-- stands where Astra measured it live: 3.0017 above the slot's ground point
-- and 0.873 beside it - 3.126 studs away in 3-D, 0.873 horizontally.
-- Checks:
--   * the board release jams there (never buys) - the live bug
--   * the fix: that customer buys; six in a row all buy, the line drains
--   * an unreachable counter: the front customer gives up within a bounded
--     time and the next one buys
--   * a customer far above the slot (vertical sanity) doesn't count as there
--   * a customer that dies / is removed while queued leaves the line
--   * a customer whose script errors leaves the line (the fix's pcall)

local ARRIVE_OFFSET = Vector3.new(-0.0084, 3.0017, 0.8732) -- live: front customer vs SLOTS[1]
local SLOT1 = Vector3.new(-94.8, 9.3, 152.5)

-- the queue code of one CustomerSystem version, with test stubs around it
local function queueCode(src, label)
	local a = src:find("-- tuning\n", 1, true)
	local b = src:find("-- R15 default animations", 1, true)
	local c = src:find("------------------------------------------------ customer behaviour\n", 1, true)
	local d = src:find("local function spawnCustomer()", 1, true)
	assert(a and b and c and d, label .. ": sections not found")
	local behaviour = src:sub(c, d - 1)
	-- the hand-over animation isn't what this tests: hand the piece over plainly
	local g1 = behaviour:find("local function giveMeat(c, meat)", 1, true)
	local g2 = behaviour:find("\nend\n", g1, true)
	behaviour = behaviour:sub(1, g1 - 1) .. "local function giveMeat(c, meat)\n\tmeat:Destroy()\n\ttable.insert(GIVEN, c)\nend\n" .. behaviour:sub(g2 + 5)
	local chunk = "local Economy, saleMeat, bought, GIVEN = ...\n" .. src:sub(a, b - 1) .. behaviour
		.. "\nlocal function add(c)\n\ttable.insert(line, c)\n\ttask.spawn(function()\n"
		.. (if src:find("pcall(runCustomer, c)", 1, true)
			then "\t\tlocal ok = pcall(runCustomer, c)\n\t\tif not ok then drop(c) end\n"
			else "\t\trunCustomer(c)\n")
		.. "\tend)\nend\nreturn add, line\n"
	local fn = assert(loadstring(chunk, "=" .. label))
	setfenv(fn, envFor(script("Script", "CustomerSystem", "")))
	return fn
end

local function folder()
	local f = { kids = {} }
	function f:GetChildren()
		return table.clone(self.kids)
	end
	return f
end
local function meatOn(f, id)
	local m = { Position = SLOT1 + Vector3.new(6, 3, 0), attrs = { PieceId = id, Tier = 1 } }
	function m:GetAttribute(k)
		return self.attrs[k]
	end
	function m:SetAttribute(k, v)
		self.attrs[k] = v
	end
	function m:Destroy()
		local i = table.find(f.kids, self)
		if i then
			table.remove(f.kids, i)
		end
	end
	table.insert(f.kids, m)
	return m
end

-- a fake customer; opts.blocked(target) -> true: MoveTo never gets there;
-- opts.offset: where its root part comes to rest relative to a target
local function customer(name, opts)
	opts = opts or {}
	local hrp = { Position = Vector3.new(-126.1, 12.3, 184), Parent = true }
	hrp.CFrame = CFrame.new(hrp.Position)
	local hum = { Parent = true, Health = 100, MoveToFinished = Signal.new(), moves = 0, toCounter = 0 }
	function hum:MoveTo(target)
		self.moves += 1
		if (target - SLOT1).Magnitude < 0.01 then
			self.toCounter += 1
		end
		local id = self.moves
		if opts.blocked and opts.blocked(target) then
			return
		end
		task.delay(0.5, function()
			if hum.moves == id and hum.Health > 0 then
				hrp.Position = target + (opts.offset or ARRIVE_OFFSET)
				hum.MoveToFinished:Fire(true)
			end
		end)
	end
	local model = { Parent = true, Name = name }
	function model:Destroy()
		self.Parent = nil
	end
	function model:FindFirstChild()
		return nil
	end
	local route = { door = Vector3.new(-125.6, 9.3, 185), out = Vector3.new(-126.1, 9.3, 184) }
	return { model = model, hum = hum, hrp = hrp, route = route, state = "walking", name = name }
end

-- one scene: a version's queue code, a sale table, a settle log
local function scene(src, label)
	local sale, given, settled = folder(), {}, {}
	local econ = {
		settle = function(pieceId, route)
			table.insert(settled, { pieceId, route })
			return true, 1
		end,
	}
	local boughtEvent = { Fire = function() end }
	local add, line
	runAs("server", function()
		add, line = queueCode(src, label)(econ, sale, boughtEvent, given)
	end)
	return {
		sale = sale,
		given = given,
		settled = settled,
		line = line,
		add = function(c)
			runAs("server", function()
				add(c)
			end)
		end,
	}
end
local function bought(s, c)
	return table.find(s.given, c) ~= nil
end

------------------------------------------------------------ the live bug (the board release)

local old = scene(SOURCES.Board_Customer, "board CustomerSystem")
meatOn(old.sale, "P13")
local oc = customer("Front")
old.add(oc)
advance(90)
check("board release: at the counter 3.126 studs away (3-D) the customer never buys - the live jam", not bought(old, oc)
	and #old.line == 1 and #old.settled == 0)

------------------------------------------------------------ the fix

local s = scene(SOURCES.Queue_Customer, "queue fix")
meatOn(s.sale, "P13")
local first = customer("Front")
s.add(first)
advance(20)
check("fix: the same customer buys (horizontal 0.87 <= 3, vertical 3.0 <= 6): settled once, meat handed over",
	bought(s, first) and #s.settled == 1 and s.settled[1][1] == "P13" and s.settled[1][2] == "Customer")
advance(30)
check("... and leaves: the line is empty", #s.line == 0)

-- six in a row, six pieces
local six = {}
for i = 1, 6 do
	meatOn(s.sale, "Q" .. i)
	six[i] = customer("C" .. i)
	s.add(six[i])
end
advance(240)
local all = true
for _, c in ipairs(six) do
	all = all and bought(s, c)
end
check("six queued customers: all six buy, the line drains", all and #s.line == 0 and #s.settled == 7)

------------------------------------------------------------ bounded recovery

-- the counter can't be reached by the front customer: it gives up, the next one buys
meatOn(s.sale, "R1")
local stuck = customer("Stuck", { blocked = function(t)
	return (t - SLOT1).Magnitude < 0.01
end })
local nextUp = customer("Next")
s.add(stuck)
s.add(nextUp)
advance(10)
check("unreachable counter: at 10 s the front customer is still trying, the next one waits behind", table.find(s.line, stuck) ~= nil
	and not bought(s, nextUp))
advance(75)
check("... gives up and leaves the line; the next customer buys the piece", table.find(s.line, stuck) == nil
	and not bought(s, stuck) and bought(s, nextUp))
check("... it walked to the counter again once before giving up (two tries, no more)", stuck.hum.toCounter == 2)
advance(60)

-- vertical sanity: right above the slot, 10 studs up, isn't "at the counter"
meatOn(s.sale, "V1")
local high = customer("Roof", { offset = Vector3.new(0, 10, 0) })
s.add(high)
advance(15)
check("10 studs above the slot (horizontal 0): not at the counter, doesn't buy", not bought(s, high))
advance(60)
check("... gives up within the bound, the line is free again", #s.line == 0 and not bought(s, high))

-- dies while queued (behind someone at the counter who waits for meat)
for _, m in ipairs(s.sale:GetChildren()) do
	m:Destroy()
end
local waiting = customer("Waiting")
local doomed = customer("Doomed")
local removed = customer("Removed")
s.add(waiting)
s.add(doomed)
s.add(removed)
advance(6)
doomed.hum.Health = 0
removed.model.Parent = nil
advance(2)
check("a customer that dies, and one that is removed, while queued: both leave the line", table.find(s.line, doomed) == nil
	and table.find(s.line, removed) == nil and table.find(s.line, waiting) ~= nil)
check("... the dead one's model is cleaned up", doomed.model.Parent == nil)
advance(40)
check("the waiting customer gives up when no meat comes (as before), the line is empty", #s.line == 0)

-- a customer whose script errors
local broken = customer("Broken")
broken.hum.MoveTo = function()
	error("MoveTo exploded (fake)")
end
s.add(broken)
advance(2)
check("a customer whose script errors: removed from the line, model removed", table.find(s.line, broken) == nil
	and broken.model.Parent == nil)

finish("customer queue sim")
