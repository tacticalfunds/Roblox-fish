--!strict
-- Token-bucket rate limiter keyed by an arbitrary key (e.g. player). Time is
-- passed in explicitly so the logic is deterministic and testable.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = { tokens: number, last: number }

export type RateLimiter = typeof(setmetatable(
	{} :: { rate: number, burst: number, buckets: { [any]: Bucket } },
	RateLimiter
))

function RateLimiter.new(rate: number, burst: number): RateLimiter
	return setmetatable({ rate = rate, burst = burst, buckets = {} }, RateLimiter)
end

-- Returns true and consumes a token when the key is under its limit.
function RateLimiter.allow(self: RateLimiter, key: any, now: number): boolean
	local bucket = self.buckets[key]
	if not bucket then
		bucket = { tokens = self.burst, last = now }
		self.buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.last)
	bucket.tokens = math.min(self.burst, bucket.tokens + elapsed * self.rate)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.forget(self: RateLimiter, key: any)
	self.buckets[key] = nil
end

return RateLimiter
