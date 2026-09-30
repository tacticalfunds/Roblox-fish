--!strict
-- BoardUpgrades: each player's levels of the upgrade board's upgrades
-- (Config.BoardUpgrades; Net Strength is NetKg). Pure (no Roblox APIs), so
-- the offline tests run the exact logic MoneyStore, EconomyService and
-- RodFishingSystem use.
--
-- Saved in the player's Money record as the optional table `upgrades`
-- ({ [id] = level }, whole numbers, 0 = not bought). A missing table is all
-- 0. A table this build can't read (not a table, or one of ITS upgrades
-- holds something that isn't a whole number >= 0) is NOT overwritten: the
-- player has level 0 of everything this session and can't buy. Entries this
-- build doesn't know (a newer build's upgrades) are kept as they are. A level
-- above this build's last one is kept too; its effect is this build's last
-- value and nothing more is sold.

local Config = require(script.Parent.Config)

local BoardUpgrades = {}

export type Levels = { [string]: any }

function BoardUpgrades.ids(): { string }
	return table.clone(Config.BoardUpgradeIds)
end

function BoardUpgrades.known(id: any): boolean
	return type(id) == "string" and Config.BoardUpgrades[id] ~= nil and table.find(Config.BoardUpgradeIds, id) ~= nil
end

local function wholeLevel(v: any): boolean
	return type(v) == "number" and v == v and v == math.floor(v) and v >= 0 and v <= 1e6
end

-- Returns (levels, writable). `levels` is a copy that keeps unknown entries.
function BoardUpgrades.load(field: any): (Levels, boolean)
	if field == nil then
		return {}, true
	end
	if type(field) ~= "table" then
		return {}, false
	end
	local out = {}
	for k, v in pairs(field) do
		if BoardUpgrades.known(k) and not wholeLevel(v) then
			return {}, false
		end
		out[k] = v
	end
	return out, true
end

function BoardUpgrades.copy(levels: Levels): Levels
	return table.clone(levels)
end

function BoardUpgrades.level(levels: Levels?, id: string): number
	local v = levels and levels[id]
	return if wholeLevel(v) then v :: number else 0
end

-- The effect at `level` (this build's last value above its last level).
function BoardUpgrades.value(id: string, level: number): number
	local values = Config.BoardUpgrades[id].Values
	return values[math.clamp(level, 0, #values - 1) + 1]
end

-- The next purchase from `level`: (next level, its cost, its value), or nil at the last level.
function BoardUpgrades.nextStep(id: string, level: number): (number?, number?, number?)
	local u = Config.BoardUpgrades[id]
	if level >= #u.Values - 1 then
		return nil, nil, nil
	end
	return level + 1, u.Costs[level + 1], u.Values[level + 2]
end

-- Rod Luck: the factor on a fish's roll weight for a caster with luck `luck`.
-- The commonest tier (lo) keeps x1, the rarest (hi) gets x luck, tiers between
-- scale geometrically; the caller renormalises over the whole pool, so this
-- shifts the odds toward rarer fish without ever making one certain.
function BoardUpgrades.luckFactor(tier: number, lo: number, hi: number, luck: number): number
	if not (type(luck) == "number" and luck > 1) or hi <= lo then
		return 1
	end
	local u = math.clamp((tier - lo) / (hi - lo), 0, 1)
	return luck ^ u
end

return BoardUpgrades
