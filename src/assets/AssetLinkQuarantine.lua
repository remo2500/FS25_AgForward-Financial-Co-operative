-- AgForward Financial Cooperative
-- Tracks unresolved runtime asset links without treating collateral as disposed.

AGFAssetLinkQuarantine = {}
AGFAssetLinkQuarantine_mt = Class(AGFAssetLinkQuarantine)

function AGFAssetLinkQuarantine.new()
    local self = setmetatable({}, AGFAssetLinkQuarantine_mt)
    self.entries = {}
    return self
end

function AGFAssetLinkQuarantine:add(assetId, stableKey, reason)
    if assetId == nil then return false, "INVALID_ASSET_ID" end
    local key = tostring(assetId)
    local entry = self.entries[key]
    if entry == nil then
        entry = {
            assetId = assetId,
            stableKey = stableKey,
            reason = reason or "unresolved",
            attempts = 0,
            firstYear = nil,
            firstPeriod = nil,
            lastYear = nil,
            lastPeriod = nil
        }
        if g_currentMission ~= nil and g_currentMission.environment ~= nil then
            entry.firstYear = g_currentMission.environment.currentYear
            entry.firstPeriod = g_currentMission.environment.currentPeriod
        end
        self.entries[key] = entry
    else
        entry.stableKey = stableKey or entry.stableKey
        entry.reason = reason or entry.reason
    end
    return true, self:get(assetId)
end

function AGFAssetLinkQuarantine:recordAttempt(assetId, reason)
    local entry = self.entries[tostring(assetId)]
    if entry == nil then return false, "UNKNOWN_QUARANTINE_ENTRY" end
    entry.attempts = (entry.attempts or 0) + 1
    if reason ~= nil then entry.reason = reason end
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        entry.lastYear = g_currentMission.environment.currentYear
        entry.lastPeriod = g_currentMission.environment.currentPeriod
    end
    return true, self:get(assetId)
end

function AGFAssetLinkQuarantine:resolve(assetId)
    local key = tostring(assetId)
    if self.entries[key] == nil then return false, "UNKNOWN_QUARANTINE_ENTRY" end
    self.entries[key] = nil
    return true, nil
end

function AGFAssetLinkQuarantine:get(assetId)
    local entry = self.entries[tostring(assetId)]
    if entry == nil then return nil end
    local copy = {}
    for key, value in pairs(entry) do copy[key] = value end
    return copy
end

function AGFAssetLinkQuarantine:getAll()
    local result = {}
    for _, entry in pairs(self.entries) do
        local copy = {}
        for key, value in pairs(entry) do copy[key] = value end
        table.insert(result, copy)
    end
    table.sort(result, function(left, right) return tostring(left.assetId) < tostring(right.assetId) end)
    return result
end

function AGFAssetLinkQuarantine:count()
    local count = 0
    for _ in pairs(self.entries) do count = count + 1 end
    return count
end
