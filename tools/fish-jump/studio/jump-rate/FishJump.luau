--!strict
-- FishJump (ModuleScript in ReplicatedStorage). Pure, visual-only jump
-- schedule for river fish, used by the patched FishSwimClient.
--
-- Each fish gets its own period and time offset from its Seed; in every
-- period it jumps with probability Chance, decided by an integer hash of
-- (Seed, cycle number). Everything is a pure function of server time and
-- Seed, so every client sees the same fish jump at the same moment, jumps are
-- sparse and staggered, and a player joining mid-jump computes the same arc.
-- The hash uses exact 32-bit integer ops (not sin()) because server time is
-- ~1.7e9 and large-argument sin() can differ between devices.
--
-- Nothing here touches the server: net catch eligibility (NetLiftScript's
-- fishPos uses only x/z from the spawn attributes) and rewards are unchanged,
-- and the jump never moves the fish's x/z, so it stays in its lane.

-- [JumpRate v1] Periods halved (16-28 s -> 8-14 s): about twice the jumps,
-- still one period and offset per fish, so they stay staggered.
local FishJump = {}

export type Config = {
	Enabled: boolean,
	Chance: number, -- probability a fish jumps in one of its periods
	PeriodMin: number, -- seconds; each fish's period is in [PeriodMin, PeriodMin + PeriodSpread)
	PeriodSpread: number,
	Duration: number, -- seconds in the air
	HeightPerStud: number, -- jump height per stud of SwimLen
	MinHeight: number,
	MaxHeight: number,
	PitchScale: number, -- 1 = nose follows the arc exactly; lower = gentler pitch
	EdgeMargin: number, -- no jumps this close to the river's MinZ/MaxZ
	SkipSnakes: boolean, -- CrystalSerpent-style long fish don't jump
	Splash: boolean,
	SplashPool: number, -- max simultaneous splash rings
}

FishJump.Defaults = {
	Enabled = true,
	Chance = 0.35,
	PeriodMin = 8, -- JumpRate: was 16 (jumps about twice as often)
	PeriodSpread = 6, -- JumpRate: was 12 (jumps about twice as often)
	Duration = 0.9,
	HeightPerStud = 0.45,
	MinHeight = 1.2,
	MaxHeight = 3.2,
	PitchScale = 0.6,
	EdgeMargin = 6,
	SkipSnakes = true,
	Splash = true,
	SplashPool = 10,
} :: Config

local TWO32 = 4294967296

local function u32(v: number): number
	return math.floor(v) % TWO32
end

local function xorshift(h: number): number
	h = bit32.bxor(h, bit32.lshift(h, 13))
	h = bit32.bxor(h, bit32.rshift(h, 17))
	h = bit32.bxor(h, bit32.lshift(h, 5))
	return h
end

-- Deterministic hash of two integers to [0, 1).
function FishJump.hash01(a: number, b: number): number
	local h = bit32.bxor(u32(a), bit32.lrotate(u32(b), 16), 0x9E3779B9)
	if h == 0 then
		h = 0x6D2B79F5
	end
	h = xorshift(xorshift(xorshift(h)))
	return h / TWO32
end

-- Reads optional overrides from attributes on the river folder:
-- JumpEnabled (bool), JumpChance (0..1), JumpHeightScale (multiplier).
function FishJump.config(get: (string) -> any): Config
	local cfg = table.clone(FishJump.Defaults)
	local enabled = get("JumpEnabled")
	if type(enabled) == "boolean" then
		cfg.Enabled = enabled
	end
	local chance = get("JumpChance")
	if type(chance) == "number" and chance == chance then
		cfg.Chance = math.clamp(chance, 0, 1)
	end
	local scale = get("JumpHeightScale")
	if type(scale) == "number" and scale == scale and scale > 0 then
		cfg.HeightPerStud *= scale
		cfg.MinHeight *= scale
		cfg.MaxHeight *= scale
	end
	return cfg
end

function FishJump.period(seed: number, cfg: Config): number
	return cfg.PeriodMin + cfg.PeriodSpread * FishJump.hash01(seed, 1)
end

-- Returns (u, cycle): u in [0, 1) while this fish is in the air at time t,
-- otherwise nil. `cycle` identifies the current period (for splash bookkeeping).
function FishJump.phase(seed: number, t: number, cfg: Config): (number?, number)
	local period = FishJump.period(seed, cfg)
	local offset = FishJump.hash01(seed, 2) * period
	local x = (t - offset) / period
	local cycle = math.floor(x)
	local into = (x - cycle) * period
	if not cfg.Enabled or into >= cfg.Duration then
		return nil, cycle
	end
	if FishJump.hash01(seed, cycle + 3) >= cfg.Chance then
		return nil, cycle
	end
	return into / cfg.Duration, cycle
end

-- Size-aware, modest jump height.
function FishJump.height(swimLen: any, cfg: Config): number
	local L = if type(swimLen) == "number" and swimLen > 0 then swimLen else 4
	return math.clamp(L * cfg.HeightPerStud, cfg.MinHeight, cfg.MaxHeight)
end

-- Vertical offset and (pitch-scaled) vertical velocity along the arc.
function FishJump.offset(u: number, height: number, cfg: Config): (number, number)
	u = math.clamp(u, 0, 1)
	local dy = height * 4 * u * (1 - u)
	local vy = height * 4 * (1 - 2 * u) / cfg.Duration * cfg.PitchScale
	return dy, vy
end

-- Jumps only away from the ends of the river, so the arc stays in bounds.
function FishJump.allowed(z: number, minZ: any, maxZ: any, cfg: Config): boolean
	if type(minZ) ~= "number" or type(maxZ) ~= "number" then
		return false
	end
	return z >= minZ + cfg.EdgeMargin and z <= maxZ - cfg.EdgeMargin
end

return FishJump
