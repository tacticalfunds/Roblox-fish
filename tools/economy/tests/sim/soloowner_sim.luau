-- Ambient catches in a solo server (EconomyService.issueFish), the REAL
-- EconomyService. A harpoon catch with no buyer and no bound gun owner:
--   * solo (exactly one player): owned by that player, fixed at catch time
--   * two or more players: nobody (unchanged - nobody is picked)
-- and never over an explicit owner (the fish's buyer, the gun's
-- OwnerUserId), never for a net catch (the pad player, unchanged), never for
-- other sources, never retroactively (a piece keeps the owner it was issued
-- with, even if the server becomes solo before it sells).

local Economy = installEconomy()
local KEY = Economy.Config.KeyPrefix
dsData[KEY .. "1"] = { v = 2, money = 100 }
dsData[KEY .. "2"] = { v = 2, money = 100 }
local A = join(1, "Solo", Vector3.new(0, 10, 0))
advance(2)

local function issue(player, meta, tier)
	local ids
	runAs("server", function()
		ids = Economy.issueFish(player, "Cod", tier or 1, meta)
	end)
	return ids
end
local function sell(ids)
	runAs("server", function()
		for _, id in ipairs(ids) do
			Economy.settle(id, "Customer")
		end
	end)
	advance(0.5)
end
local function ownerOf(id)
	local tags = {}
	local fake = {
		SetAttribute = function(_, k, v)
			tags[k] = v
		end,
		GetAttribute = function(_, k)
			return tags[k]
		end,
	}
	runAs("server", function()
		Economy.stamp(fake, id)
	end)
	return tags.OwnerId
end
local VALUE = 4 -- a tier-1 fish

------------------------------------------------------------ solo

local p1 = issue(nil, { Source = "Harpoon" })
check("solo: an ambient harpoon catch with no owner is the player's, at catch time", #p1 == 1 and ownerOf(p1[1]) == 1)
sell(p1)
check("... and its sale pays them", Economy.balance(A) == 100 + VALUE)

local bought = issue(nil, { Source = "Harpoon", OwnerId = 4242 }) -- a fish someone else bought
check("solo: a harpooned fish someone bought stays the buyer's", ownerOf(bought[1]) == 4242)
sell(bought)
check("... the solo player isn't paid for it", Economy.balance(A) == 100 + VALUE)

local gun = issue(nil, { Source = "Harpoon", OwnerId = 777 }) -- what HarpoonSystem sends for a bound gun owner
check("solo: a bound gun owner (OwnerUserId) stays the owner", ownerOf(gun[1]) == 777)

local net = issue(A, { Source = "Net" })
check("solo: a net catch is the pad player's, as before", ownerOf(net[1]) == 1)

local other = issue(nil, { Source = "Unknown" })
local bare = issue(nil, nil)
check("solo: other ownerless sources are NOT attributed (only the ambient harpoon)", ownerOf(other[1]) == nil and ownerOf(bare[1]) == nil)

------------------------------------------------------------ two players

local B = join(2, "Second", Vector3.new(5, 10, 0))
advance(2)
local shared = issue(nil, { Source = "Harpoon" })
check("two players: an ownerless harpoon catch stays ownerless (nobody is picked)", ownerOf(shared[1]) == nil)
local beforeA, beforeB = Economy.balance(A), Economy.balance(B)
sell(shared)
check("... its sale pays nobody", Economy.balance(A) == beforeA and Economy.balance(B) == beforeB)
local stillBought = issue(nil, { Source = "Harpoon", OwnerId = 2 })
check("two players: a fish B bought is B's, as before", ownerOf(stillBought[1]) == 2)

------------------------------------------------------------ never retroactive

local early = issue(nil, { Source = "Harpoon" }) -- caught while two players were here
leave(B)
advance(2)
check("solo again: meat caught while two were here keeps no owner", ownerOf(early[1]) == nil)
beforeA = Economy.balance(A)
sell(early)
check("... and still pays nobody when it sells", Economy.balance(A) == beforeA)
local after = issue(nil, { Source = "Harpoon" })
check("a new ambient catch now that the server is solo again: the player's", ownerOf(after[1]) == 1)

finish("solo owner sim")
