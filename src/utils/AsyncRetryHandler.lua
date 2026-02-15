-- =========================================================
-- FS25 Realistic Soil & Fertilizer
-- =========================================================
-- Async Retry Handler - Exponential Backoff Pattern
-- =========================================================
-- Author: TisonK
-- =========================================================
---@class AsyncRetryHandler
-- Generic retry handler for async operations in FS25
-- Works in Lua 5.1, no coroutines needed

AsyncRetryHandler = {}
local AsyncRetryHandler_mt = Class(AsyncRetryHandler)

--- Create new retry handler for async operations
---@param config table Configuration with maxAttempts, delays, onAttempt, onSuccess, onFailure, condition, name
---@return AsyncRetryHandler
function AsyncRetryHandler.new(config)
    local self = setmetatable({}, AsyncRetryHandler_mt)

    -- Configuration
    self.maxAttempts = config.maxAttempts or 3
    self.delays = config.delays or {2000, 4000, 8000}  -- ms - exponential backoff
    self.onAttempt = config.onAttempt or function() end
    self.onSuccess = config.onSuccess or function() end
    self.onFailure = config.onFailure or function() end
    self.condition = config.condition or function() return false end
    self.name = config.name or "AsyncOperation"

    -- State
    self.state = "idle"  -- idle, pending, success, failed
    self.attempts = 0
    self.lastAttemptTime = 0
    self.started = false

    return self
end

--- Start retry sequence
--- Begins attempting the operation with exponential backoff
---@return boolean True if started, false if already running
function AsyncRetryHandler:start()
    if self.state == "pending" then
        SoilLogger.debug("[%s] Already running", self.name)
        return false
    end

    self.state = "pending"
    self.attempts = 0
    self.started = true
    self:attempt()
    return true
end

-- Perform single attempt
function AsyncRetryHandler:attempt()
    if self.state ~= "pending" then return end

    self.attempts = self.attempts + 1
    self.lastAttemptTime = g_currentMission and g_currentMission.time or 0

    SoilLogger.debug("[%s] Attempt %d/%d", self.name, self.attempts, self.maxAttempts)

    -- Execute attempt callback
    local success, result = pcall(self.onAttempt)
    if not success then
        SoilLogger.warning("[%s] Attempt %d failed: %s",
            self.name, self.attempts, tostring(result))
    end
end

-- Check if condition met (call from update loop)
function AsyncRetryHandler:checkCondition()
    if self.state ~= "pending" then return end

    local conditionMet = self.condition()
    if conditionMet then
        self:markSuccess()
    end
end

--- Mark operation as successful
--- Stops retry attempts and calls onSuccess callback
function AsyncRetryHandler:markSuccess()
    if self.state ~= "pending" then return end

    self.state = "success"
    self.started = false

    SoilLogger.info("[%s] Operation succeeded after %d attempts", self.name, self.attempts)

    local success, result = pcall(self.onSuccess)
    if not success then
        SoilLogger.warning("[%s] Success callback failed: %s",
            self.name, tostring(result))
    end
end

--- Update loop - call from main update loop
---@param dt number Delta time in milliseconds
function AsyncRetryHandler:update(dt)
    if self.state ~= "pending" then return end

    -- Check if condition already met
    self:checkCondition()
    if self.state ~= "pending" then return end

    -- Calculate elapsed time
    local currentTime = g_currentMission and g_currentMission.time or 0
    local elapsed = currentTime - self.lastAttemptTime

    -- Get delay for current attempt
    local delayIndex = math.min(self.attempts, #self.delays)
    local retryDelay = self.delays[delayIndex]

    -- Check for timeout
    if elapsed >= retryDelay then
        if self.attempts < self.maxAttempts then
            SoilLogger.debug("[%s] Retry timeout, attempting again (%d/%d)",
                self.name, self.attempts + 1, self.maxAttempts)
            self:attempt()
        else
            -- Max attempts reached
            self.state = "failed"
            self.started = false

            SoilLogger.warning("[%s] Operation failed after %d attempts",
                self.name, self.maxAttempts)

            local success, result = pcall(self.onFailure)
            if not success then
                SoilLogger.warning("[%s] Failure callback error: %s",
                    self.name, tostring(result))
            end
        end
    end
end

-- Reset handler
function AsyncRetryHandler:reset()
    self.state = "idle"
    self.attempts = 0
    self.lastAttemptTime = 0
    self.started = false
    SoilLogger.debug("[%s] Reset", self.name)
end

-- Check if running
function AsyncRetryHandler:isPending()
    return self.state == "pending"
end

function AsyncRetryHandler:isComplete()
    return self.state == "success" or self.state == "failed"
end

function AsyncRetryHandler:getState()
    return self.state
end

function AsyncRetryHandler:getAttempts()
    return self.attempts
end
