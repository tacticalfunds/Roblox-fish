--!strict
-- Pure upgrade math over the explicit level tables in Config.Upgrades.
-- Levels are always clamped to [1, #Values]; a missing or malformed level is
-- treated as level 1.

local Upgrades = {}

export type UpgradeDef = {
	DisplayName: string,
	Values: { number },
	Costs: { number },
}

local function def(config: any, id: string): UpgradeDef
	local d = config.Upgrades[id]
	assert(d, "Unknown upgrade " .. tostring(id))
	return d
end

function Upgrades.maxLevel(config: any, id: string): number
	return #def(config, id).Values
end

function Upgrades.clampLevel(config: any, id: string, level: any): number
	if type(level) ~= "number" or level ~= level then
		return 1
	end
	return math.clamp(math.floor(level), 1, Upgrades.maxLevel(config, id))
end

function Upgrades.value(config: any, id: string, level: any): number
	return def(config, id).Values[Upgrades.clampLevel(config, id, level)]
end

-- Price of the next level, or nil when already at max.
function Upgrades.nextCost(config: any, id: string, level: any): number?
	local current = Upgrades.clampLevel(config, id, level)
	if current >= Upgrades.maxLevel(config, id) then
		return nil
	end
	return def(config, id).Costs[current]
end

-- Checks a config's upgrade tables are well-formed. Returns (ok, problem).
function Upgrades.validateConfig(config: any): (boolean, string?)
	for id, d in pairs(config.Upgrades) do
		if type(d.Values) ~= "table" or #d.Values < 1 then
			return false, id .. ": Values must be a non-empty list"
		end
		if type(d.Costs) ~= "table" or #d.Costs ~= #d.Values - 1 then
			return false, id .. ": Costs must have exactly #Values - 1 entries"
		end
		for i, v in ipairs(d.Values) do
			if type(v) ~= "number" or v < 1 or v % 1 ~= 0 then
				return false, string.format("%s: Values[%d] must be a positive integer", id, i)
			end
			if i > 1 and v < d.Values[i - 1] then
				return false, string.format("%s: Values must not decrease", id)
			end
		end
		for i, c in ipairs(d.Costs) do
			if type(c) ~= "number" or c < 0 then
				return false, string.format("%s: Costs[%d] must be a non-negative number", id, i)
			end
		end
	end
	return true, nil
end

return Upgrades
