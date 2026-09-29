# Studio asset inventory — 2026-09-29

Read-only snapshot of Catch Fish game thing, place 134592289044923, Edit mode.

Includes every instance in the listed game-owned services. Excludes Studio/CoreGui/internal engine services and Players. ServerStorage includes rollback backups, not only active assets. StarterGui contains many preview models. This is an inventory, not an rbxm export or script source dump.

Each JSONL file starts with metadata, then one row per instance. `id` and `parent` reconstruct the exact tree and distinguish duplicate names. Instance-reference properties include paths and, where available, localId. Attributes, tags, common geometry/media/UI/interaction properties are included when exposed. Script SourceLength only; no source bodies. Terrain voxel data and mesh binaries are not included.

## Counts

- Workspace: 6908 descendants
- ReplicatedStorage: 3599 descendants
- ServerStorage: 1134 descendants
- ServerScriptService: 21 descendants
- StarterPlayer: 10 descendants
- StarterGui: 11832 descendants
- Lighting: 36 descendants
- SoundService: 0 descendants
- MaterialService: 2 descendants
- ReplicatedFirst: 0 descendants
- TextChatService: 8 descendants

## Gameplay landmarks

- Two top-level Workspace.KGsign models: enumerate by row IDs; both have Board Part.ClickDetector and +5 KG button. No current active handler found.
- Workspace.NetLift.MaxWeight = 15; existing weight gate, gauge and NetThemes consume it.
- ReplicatedStorage.Rods holds five rods: FishingRod1 Basic, FishingRod4 Tiger, FishingRod3 Coral, FishingRod2 Tide, FishingRod5 Magma. Asset Price/Tier/Title values are legacy; current design proposals are not installed.
- Shared dock rods are separate instances from stored rod templates and shop display models.
- Aquarium CountPrompt binding references the loader attachment; old car prompt is disabled. AquariumPanelClient installed; paid upgrades remain disabled.
- ServerStorage backup script copies are not live implementation; don't confuse Before/After or disabled backups with active code.
