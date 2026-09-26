--!strict
-- Names of the instances in the prototype scene. The setup builder creates
-- exactly these and the runtime looks them up by these names, so this module
-- is the contract between src/setup and src/server / src/client.
--
-- Workspace.<Config.SceneFolderName>          Folder
--   Plots                                     Folder
--     Plot<N>                                 Model (attribute PlotIndex = N, pivot faces the water along -Z)
--       <Parts.*>                             see below
--       CustomerSpots                         Folder of Parts (Spot1..SpotN)
--       Grinder                               Model with RollerA / RollerB Models (spun by clients)
--       UpgradePads                           Folder of Parts with attribute UpgradeId
--       Runtime                               Folder created by the server at runtime

local Scene = {}

Scene.PlotsFolder = "Plots"
Scene.PlotPrefix = "Plot"
Scene.RuntimeFolder = "Runtime"
Scene.CustomerSpots = "CustomerSpots"
Scene.UpgradePads = "UpgradePads"
Scene.Grinder = "Grinder"
Scene.Rollers = { "RollerA", "RollerB" }

-- Required BaseParts directly under each plot model.
Scene.Parts = {
	FishZone = "FishZone", -- invisible box over the water; its top face is the water surface
	FishingArea = "FishingArea", -- dock-edge strip where the owner may cast the net
	DepositPad = "DepositPad", -- grinder hopper: drop carried fish here
	OutputPad = "OutputPad", -- grinder output tray: pick up food portions
	CounterPad = "CounterPad", -- stand here to serve waiting customers
	CashPad = "CashPad", -- stand here to collect earnings
	SpawnPoint = "SpawnPoint",
	Sign = "Sign",
}

Scene.UpgradeIds = { "Net", "Carry", "Processing" }

return Scene
