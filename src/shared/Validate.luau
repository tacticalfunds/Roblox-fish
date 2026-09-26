--!strict
-- Argument validation for values arriving over RemoteEvents. Every remote
-- handler must run its arguments through these before using them.

local Validate = {}

local HUGE = 1e6 -- no legitimate coordinate or id in this prototype is this large

function Validate.finiteNumber(v: any): boolean
	return type(v) == "number" and v == v and v > -HUGE and v < HUGE
end

function Validate.positiveInteger(v: any): boolean
	return Validate.finiteNumber(v) and v >= 1 and v % 1 == 0
end

-- Vector3 is a Roblox type; typeof() returns "Vector3" only in Roblox.
function Validate.vector3(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	return Validate.finiteNumber(v.X) and Validate.finiteNumber(v.Y) and Validate.finiteNumber(v.Z)
end

-- Returns a de-duplicated array of positive integers, or nil when the value is
-- not a plain array of at most maxLen positive integers.
function Validate.idArray(v: any, maxLen: number): { number }?
	if type(v) ~= "table" then
		return nil
	end
	local count = 0
	for key in pairs(v) do
		count += 1
		if count > maxLen or type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
			return nil
		end
	end
	if count ~= #v then
		return nil
	end
	local seen: { [number]: boolean } = {}
	local out: { number } = {}
	for _, id in ipairs(v) do
		if not Validate.positiveInteger(id) then
			return nil
		end
		if not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	return out
end

return Validate
