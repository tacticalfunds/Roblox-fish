-- Desktop + touch controls for the net. Both platforms aim the same way: the
-- mouse position (desktop) or a finger's position (touch) is projected onto
-- the water plane every frame while the net is Sweeping, and sent as the
-- steering target. Cast/Haul are bound through ContextActionService, which
-- gives desktop a keybind (F / E) and touch an on-screen button for free.
--
-- This module only sends intent. The server (src/server/Net.luau) validates
-- and clamps everything; nothing here is trusted for rewards.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.FishTycoonShared.Remotes)

local Input = {}

local ACTION_CAST = "FishTycoonCastNet"
local ACTION_HAUL = "FishTycoonHaulNet"
local MOVE_SEND_INTERVAL = 1 / 20 -- throttle below the server's NetMove rate limit

local netStart = Remotes.waitFor("NetStart")
local netMove = Remotes.waitFor("NetMove")
local netHaul = Remotes.waitFor("NetHaul")

local player = Players.LocalPlayer
local aimScreenPos: Vector2? = nil
local sendAccumulator = 0

local function onAimInput(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		aimScreenPos = Vector2.new(input.Position.X, input.Position.Y)
	end
end

-- Intersects the camera ray through `screenPos` with the horizontal plane at
-- worldY. Returns nil if the ray is parallel to the plane (looking level).
local function planeIntersect(screenPos: Vector2, worldY: number): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(screenPos.X, screenPos.Y)
	local direction = ray.Direction
	if math.abs(direction.Y) < 1e-4 then
		return nil
	end
	local t = (worldY - ray.Origin.Y) / direction.Y
	if t <= 0 then
		return nil
	end
	return ray.Origin + direction * t
end

local function handleCast(_actionName, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return
	end
	netStart:FireServer()
end

local function handleHaul(_actionName, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return
	end
	netHaul:FireServer()
end

function Input.start()
	UserInputService.InputChanged:Connect(onAimInput)

	ContextActionService:BindAction(ACTION_CAST, handleCast, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(ACTION_CAST, "Cast Net")
	ContextActionService:BindAction(ACTION_HAUL, handleHaul, true, Enum.KeyCode.E, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle(ACTION_HAUL, "Haul Net")

	RunService.RenderStepped:Connect(function(dt)
		sendAccumulator += dt
		if sendAccumulator < MOVE_SEND_INTERVAL then
			return
		end
		sendAccumulator = 0
		if not aimScreenPos then
			return
		end
		if player:GetAttribute("NetPhase") ~= "Sweeping" then
			return
		end
		-- Aim at the water surface height the server reports for this plot.
		local surfaceY = player:GetAttribute("PlotSurfaceY")
		if type(surfaceY) ~= "number" then
			return
		end
		local target = planeIntersect(aimScreenPos, surfaceY)
		if target then
			netMove:FireServer(target)
		end
	end)
end

return Input
