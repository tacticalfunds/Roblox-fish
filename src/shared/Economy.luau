--!strict
-- Pure upgrade/stat math. No Roblox APIs so it can be tested offline.

local Economy = {}

export type StatDef = {
	Upgrade: string,
	Kind: string,
	Base: number,
	PerLevel: number?,
	Multiplier: number?,
	Min: number?,
}

export type UpgradeDef = {
	DisplayName: string,
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
}

-- Value of a stat curve at a given upgrade level (level 1 = base).
function Economy.statAt(def: StatDef, level: number): number
	local steps = math.max(0, level - 1)
	if def.Kind == "Linear" then
		return def.Base + (def.PerLevel or 0) * steps
	elseif def.Kind == "Geometric" then
		local value = def.Base * (def.Multiplier or 1) ^ steps
		if def.Min then
			value = math.max(def.Min, value)
		end
		return value
	end
	error("Unknown stat kind: " .. tostring(def.Kind))
end

-- Cost to buy the next level, or nil when already at MaxLevel.
function Economy.upgradeCost(def: UpgradeDef, currentLevel: number): number?
	if currentLevel >= def.MaxLevel then
		return nil
	end
	return math.floor(def.BaseCost * def.CostGrowth ^ (currentLevel - 1))
end

-- Resolves a stat by name from the config for a player's upgrade levels.
function Economy.stat(config: any, statName: string, levels: { [string]: number }): number
	local def = config.Stats[statName]
	assert(def, "Unknown stat " .. statName)
	return Economy.statAt(def, levels[def.Upgrade] or 1)
end

-- Integer-valued stats (capacities) are floored so curves may use fractions.
function Economy.intStat(config: any, statName: string, levels: { [string]: number }): number
	return math.floor(Economy.stat(config, statName, levels))
end

-- Result codes: "ok", "max", "funds".
function Economy.tryPurchase(def: UpgradeDef, currentLevel: number, money: number): (string, number?)
	local cost = Economy.upgradeCost(def, currentLevel)
	if cost == nil then
		return "max", nil
	end
	if money < cost then
		return "funds", cost
	end
	return "ok", cost
end

return Economy
