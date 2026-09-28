--!strict
-- PieceTags: the attributes a meat object carries, and who owns a new fish.
-- Pure over anything with GetAttribute/SetAttribute, so the offline tests
-- drive it with fake parts along the real routes.
--
-- Identity attributes copied onto every object that stands for a piece
-- (pit/belt/stack part, the Blender Bot's carried clone, the sale-table
-- part). The value paid always comes from the LEDGER by PieceId; the other
-- attributes are for display and for scripts that already read them (Tier).

local Ledger = require(script.Parent.Ledger)

local PieceTags = {}

PieceTags.Names = { "PieceId", "OwnerId", "Variant", "Tier", "FromFish", "Value" }

-- An Instance, or a test fake with GetAttribute/SetAttribute.
type Taggable = any

-- Writes a ledger piece's identity onto an object (clears OwnerId/Variant
-- when the piece has none, so a template's stray values can't leak in).
function PieceTags.stamp(obj: Taggable, piece: Ledger.Piece)
	obj:SetAttribute("PieceId", piece.id)
	obj:SetAttribute("OwnerId", piece.ownerId)
	obj:SetAttribute("Variant", piece.variant)
	obj:SetAttribute("Tier", piece.tier)
	obj:SetAttribute("FromFish", piece.fishName)
	obj:SetAttribute("Value", piece.value)
end

-- Snapshot of an object's identity attributes (nil if it has no PieceId).
function PieceTags.read(obj: Taggable): { [string]: any }?
	if type(obj:GetAttribute("PieceId")) ~= "string" then
		return nil
	end
	local out = {}
	for _, name in ipairs(PieceTags.Names) do
		out[name] = obj:GetAttribute(name)
	end
	return out
end

function PieceTags.write(obj: Taggable, tags: { [string]: any }?)
	if not tags then
		return
	end
	for _, name in ipairs(PieceTags.Names) do
		obj:SetAttribute(name, tags[name])
	end
end

-- Who owns a fish entering the grinder (see Config ownership notes):
--   meta.OwnerId (a bought rod fish, carried through tank/river/net/harpoon)
--   else the triggering player (manual net pad)
--   else nobody (harpoon with no bound owner) - it sells but pays nobody.
-- (Test ids are let through here; the ledger drops them outside Studio.)
function PieceTags.ownerFor(playerUserId: number?, meta: any): number?
	if type(meta) == "table" then
		local owner = Ledger.validOwner(meta.OwnerId, true)
		if owner then
			return owner
		end
	end
	return Ledger.validOwner(playerUserId, true)
end

-- Variant from a catch payload (validated by the ledger/pricing later).
function PieceTags.variantFrom(meta: any): string?
	if type(meta) == "table" and type(meta.Variant) == "string" then
		return meta.Variant
	end
	return nil
end

function PieceTags.sourceFrom(meta: any, hasPlayer: boolean): string
	if type(meta) == "table" and type(meta.Source) == "string" then
		return meta.Source
	end
	return if hasPlayer then "Net" else "Unknown"
end

return PieceTags
