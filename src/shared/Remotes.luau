--!strict
-- RemoteEvent registry. The server creates the events at startup; clients wait
-- for them. Client -> server events carry input intent only; the server owns
-- every reward and state change.
--
--   NetStart  ()                     ask to cast the net (must stand in the FishingArea)
--   NetMove   (target: Vector3)      where the player is steering the net
--   NetClaim  (fishIds: {number})    fish the client saw inside the net; the server re-checks each one
--   NetHaul   ()                     haul the net in onto the carried stack
--   Notify    (kind: string, text: string)   server -> client feedback toast

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local Remotes = {}

Remotes.Names = { "NetStart", "NetMove", "NetClaim", "NetHaul", "Notify" }

local function folder(): Folder?
	return ReplicatedStorage:FindFirstChild(Config.RemotesFolderName) :: Folder?
end

-- Server only. Idempotent.
function Remotes.createAll()
	local root = folder()
	if not root then
		local created = Instance.new("Folder")
		created.Name = Config.RemotesFolderName
		created.Parent = ReplicatedStorage
		root = created
	end
	assert(root)
	for _, name in ipairs(Remotes.Names) do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = root
		end
	end
end

function Remotes.get(name: string): RemoteEvent
	local root = folder()
	assert(root, "Remotes not created yet")
	local remote = root:FindFirstChild(name)
	assert(remote and remote:IsA("RemoteEvent"), "Missing remote " .. name)
	return remote
end

-- Client side: yields until the server has created the remote.
function Remotes.waitFor(name: string): RemoteEvent
	local root = ReplicatedStorage:WaitForChild(Config.RemotesFolderName)
	return root:WaitForChild(name) :: RemoteEvent
end

return Remotes
