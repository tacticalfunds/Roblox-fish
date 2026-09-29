--!strict
-- Rods: the rod catalog and the saved rod profile. Pure (no Roblox APIs), so
-- the offline tests run the exact logic MoneyStore and EconomyService use.
--
-- Saved in the player's Money record as the optional field
--   rods = { owned = { [rodId] = true, ... }, equipped = rodId }
-- Safety rules:
--   * The free BaseRod is always owned and never needs saving.
--   * A missing field (a v1 record) is a fresh profile: Basic, equipped.
--   * A field that isn't valid rod data is NOT overwritten (corrupt): the
--     player plays with Basic this session and can't buy rods.
--   * Ids this build doesn't know (a newer build's rods) and unknown
--     sub-fields are kept exactly as they were on every save.

local Config = require(script.Parent.Config)

local Rods = {}

export type Rod = { Id: string, Key: string, Name: string, Price: number, BiteWait: number }
export type Profile = {
	owned: { [string]: boolean },
	equipped: string,
	raw: { [any]: any }?, -- the loaded `rods` table (kept for unknown sub-fields)
	keepEquipped: string?, -- a newer build's equipped id, kept until the player equips here
}

local byId: { [string]: Rod } = {}
for _, rod in ipairs(Config.Rods) do
	byId[rod.Id] = rod
end

function Rods.get(id: any): Rod?
	return if type(id) == "string" then byId[id] else nil
end

function Rods.list(): { Rod }
	return Config.Rods
end

function Rods.alwaysStocked(id: string): boolean
	return table.find(Config.AlwaysStockedRods, id) ~= nil
end

function Rods.fresh(): Profile
	return { owned = { [Config.BaseRod] = true }, equipped = Config.BaseRod, raw = nil }
end

-- Reads a record's `rods` field. Returns (profile, writable): writable is
-- false when the field exists but isn't valid rod data (leave it untouched).
function Rods.load(field: any): (Profile, boolean)
	if field == nil then
		return Rods.fresh(), true
	end
	if type(field) ~= "table" or (field.owned ~= nil and type(field.owned) ~= "table") then
		return Rods.fresh(), false
	end
	local profile = Rods.fresh()
	profile.raw = field
	for id, v in pairs(field.owned or {}) do
		if type(id) ~= "string" or v ~= true then
			return Rods.fresh(), false
		end
		profile.owned[id] = true -- unknown ids kept too
	end
	local eq = field.equipped
	if eq ~= nil and type(eq) ~= "string" then
		return Rods.fresh(), false
	end
	-- equip falls back to Basic unless it names a rod this build knows and owns
	profile.equipped = if eq and byId[eq] and profile.owned[eq] then eq else Config.BaseRod
	if eq and not byId[eq] and profile.owned[eq] then
		profile.keepEquipped = eq -- a newer build's rod: written back as is
	end
	return profile, true
end

-- The `rods` field to write: the loaded table with owned / equipped
-- replaced (every other sub-field kept). The BaseRod isn't stored.
function Rods.save(profile: Profile, previousField: any): { [any]: any }
	local out = {}
	local keep = if type(previousField) == "table" then previousField else profile.raw
	for k, v in pairs(keep or {}) do
		out[k] = v
	end
	-- This session's owned set is authoritative (the session lock means no
	-- other server writes the record meanwhile), so a refunded purchase whose
	-- save failed ambiguously is undone on the next save, never resurrected.
	local owned = {}
	for id in pairs(profile.owned) do
		if id ~= Config.BaseRod then
			owned[id] = true
		end
	end
	out.owned = owned
	-- a newer build's equipped rod stays equipped unless the player changed it
	out.equipped = if profile.keepEquipped then profile.keepEquipped else profile.equipped
	return out
end

function Rods.copy(profile: Profile): Profile
	local owned = {}
	for id in pairs(profile.owned) do
		owned[id] = true
	end
	return { owned = owned, equipped = profile.equipped, raw = profile.raw, keepEquipped = profile.keepEquipped }
end

-- The stats a cast uses: the equipped rod if known and owned, else Basic.
function Rods.stats(profile: Profile?): Rod
	local id = profile and profile.equipped
	local rod = id and byId[id]
	if rod and profile and profile.owned[rod.Id] then
		return rod
	end
	return byId[Config.BaseRod]
end

-- What a shop press on `id` should do: "equip" (owned: never charges),
-- "buy", or a refusal ("unknown" | "equipped").
function Rods.decide(profile: Profile, id: any): string
	local rod = Rods.get(id)
	if not rod then
		return "unknown"
	end
	if profile.owned[rod.Id] then
		return if profile.equipped == rod.Id then "equipped" else "equip"
	end
	return "buy"
end

return Rods
