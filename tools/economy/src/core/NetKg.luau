--!strict
-- NetKg: each player's owned net capacity (the +5 KG signs). Pure (no Roblox
-- APIs), so the offline tests run the exact logic MoneyStore and
-- EconomyService use.
--
-- Saved in the player's Money record as the optional field `netKg` (whole
-- kg). A missing field is Base. A field that isn't valid is NOT overwritten:
-- the player has Base this session and can't buy. A value above this build's
-- Max (a newer build's) is kept as it is; nothing more is sold past Max.

local Config = require(script.Parent.Config)

local NetKg = {}
local C = Config.NetKg

function NetKg.base(): number
	return C.Base
end

-- Returns (kg, writable).
function NetKg.load(field: any): (number, boolean)
	if field == nil then
		return C.Base, true
	end
	if type(field) == "number" and field == field and field == math.floor(field) and field >= C.Base and field <= 1e6 then
		return field, true
	end
	return C.Base, false
end

-- Price of purchase number `level` + 1 (level 0 = the first purchase).
function NetKg.cost(level: number): number
	if level < #C.Costs then
		return C.Costs[level + 1]
	end
	local c = C.Costs[#C.Costs]
	for _ = #C.Costs, level do
		c = math.floor(c * C.Growth / 5 + 0.5) * 5
	end
	return c
end

-- The next purchase from `kg`: (next kg, its cost), or nil at Max.
function NetKg.nextStep(kg: number): (number?, number?)
	if kg >= C.Max then
		return nil, nil
	end
	local level = math.max(0, math.floor((kg - C.Base) / C.Step))
	return math.min(kg + C.Step, C.Max), NetKg.cost(level)
end

-- The shared net: the highest owned capacity, never below `floor`.
function NetKg.shared(capacities: { number }, floor: number): number
	local best = floor
	for _, kg in ipairs(capacities) do
		if kg > best then
			best = kg
		end
	end
	return best
end

return NetKg
