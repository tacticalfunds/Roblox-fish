-- +5 KG signs without EconomyService: the REAL NetCapacityServer fails
-- closed. Clicks do nothing, nothing is written anywhere, MaxWeight stays the
-- place's, and it says so once in the output.

local SSS = services.ServerScriptService
local ws = workspaceInst
current = "server"
local netLift = new("Model", "NetLift")
netLift:SetAttribute("MaxWeight", 15)
netLift.Parent = ws
local sign = new("Model", "KGsign")
local board = part("Board Part", Vector3.new(0, 10, 0), sign, Vector3.new(8, 4, 0.5))
local cd = new("ClickDetector", "ClickDetector")
cd._props.MaxActivationDistance = 20
cd.Parent = board
sign.Parent = ws
current = nil
local P = join(1, "Player", Vector3.new(0, 5, 5))
runScript(script("Script", "NetCapacityServer", SOURCES.Kg_Server, SSS))
advance(0.5)
asServer(function()
	cd.MouseClick:Fire(P)
end)
advance(0.5)
check("no economy: MaxWeight stays 15", netLift:GetAttribute("MaxWeight") == 15)
check("no economy: no money, no attributes written", P:FindFirstChild("leaderstats") == nil and P:GetAttribute("NetKg") == nil and next(dsData) == nil)
local said = false
for _, w in ipairs(warnings) do
	if w:find("[NetCapacity] no EconomyService", 1, true) then
		said = true
	end
end
check("it says so in the output", said)
finish("kg no-economy sim")
