-- AgForward Financial Cooperative
-- Registry for active/released secured claims against economic assets.

AGFLienRegistry = {}
AGFLienRegistry_mt = Class(AGFLienRegistry)

function AGFLienRegistry.new(idService, runtimeState, assetRegistry, liabilityRegistry)
    local self = setmetatable({}, AGFLienRegistry_mt)
    self.idService = idService
    self.runtimeState = runtimeState
    self.assetRegistry = assetRegistry
    self.liabilityRegistry = liabilityRegistry
    self.liens = {}
    self.order = {}
    self.byAsset = {}
    self.byLiability = {}
    return self
end

function AGFLienRegistry:checkMutationAllowed(internal)
    if internal then return true, nil end
    if self.runtimeState == nil then return true, nil end
    return self.runtimeState:canMutate()
end

function AGFLienRegistry:create(assetId, liabilityId, priority)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return nil, errorCode end
    if assetId == nil or liabilityId == nil then return nil, "INVALID_LIEN_ARGUMENTS" end
    if self.assetRegistry ~= nil and self.assetRegistry:get(assetId) == nil then return nil, "UNKNOWN_ASSET" end
    if self.liabilityRegistry ~= nil and self.liabilityRegistry:get(liabilityId) == nil then return nil, "UNKNOWN_LIABILITY" end
    if self:getActiveLienForPair(assetId, liabilityId) ~= nil then return nil, "ACTIVE_LIEN_ALREADY_EXISTS" end

    local lien = AGFLien.new(self.idService:next("LIEN"), assetId, liabilityId)
    lien.priority = math.max(1, math.floor(tonumber(priority) or 1))
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        lien.startYear = g_currentMission.environment.currentYear
        lien.startPeriod = g_currentMission.environment.currentPeriod
    end
    return lien, nil
end

function AGFLienRegistry:register(lien, internal)
    local allowed, errorCode = self:checkMutationAllowed(internal)
    if not allowed then return false, errorCode end
    if lien == nil or lien.id == nil or lien.assetId == nil or lien.liabilityId == nil then
        return false, "INVALID_LIEN"
    end
    if self.liens[lien.id] ~= nil then return false, "DUPLICATE_LIEN_ID" end
    if lien:isActive() and self:getActiveLienForPair(lien.assetId, lien.liabilityId) ~= nil then
        return false, "ACTIVE_LIEN_ALREADY_EXISTS"
    end

    local stored = lien:clone()
    self.liens[stored.id] = stored
    table.insert(self.order, stored.id)
    self.byAsset[stored.assetId] = self.byAsset[stored.assetId] or {}
    table.insert(self.byAsset[stored.assetId], stored.id)
    self.byLiability[stored.liabilityId] = self.byLiability[stored.liabilityId] or {}
    table.insert(self.byLiability[stored.liabilityId], stored.id)
    if self.idService ~= nil then self.idService:observeId(stored.id) end
    return true, nil
end

function AGFLienRegistry:get(id)
    local lien = self.liens[id]
    return lien ~= nil and lien:clone() or nil
end

function AGFLienRegistry:getActiveLienForPair(assetId, liabilityId)
    for _, id in ipairs(self.byAsset[assetId] or {}) do
        local lien = self.liens[id]
        if lien ~= nil and lien.liabilityId == liabilityId and lien:isActive() then
            return lien:clone()
        end
    end
    return nil
end

function AGFLienRegistry:getAssetLiens(assetId, includeInactive)
    local result = {}
    for _, id in ipairs(self.byAsset[assetId] or {}) do
        local lien = self.liens[id]
        if lien ~= nil and (includeInactive or lien:isActive()) then
            table.insert(result, lien:clone())
        end
    end
    table.sort(result, function(left, right)
        if left.priority == right.priority then return tostring(left.id) < tostring(right.id) end
        return left.priority < right.priority
    end)
    return result
end

function AGFLienRegistry:getLiabilityLiens(liabilityId, includeInactive)
    local result = {}
    for _, id in ipairs(self.byLiability[liabilityId] or {}) do
        local lien = self.liens[id]
        if lien ~= nil and (includeInactive or lien:isActive()) then
            table.insert(result, lien:clone())
        end
    end
    return result
end

function AGFLienRegistry:release(lienId, status)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local lien = self.liens[lienId]
    if lien == nil then return false, "UNKNOWN_LIEN" end
    if not lien:isActive() then return false, "LIEN_NOT_ACTIVE" end

    lien.status = status or AGFLienStatus.RELEASED
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        lien.releaseYear = g_currentMission.environment.currentYear
        lien.releasePeriod = g_currentMission.environment.currentPeriod
    end
    return true, lien:clone()
end

function AGFLienRegistry:hasActiveLien(assetId)
    return #self:getAssetLiens(assetId, false) > 0
end
