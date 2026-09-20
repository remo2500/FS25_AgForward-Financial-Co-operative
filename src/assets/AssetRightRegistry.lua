-- AgForward Financial Cooperative
-- Registry separating economic ownership, operating rights, and tenancy.

AGFAssetRightRegistry = {}
AGFAssetRightRegistry_mt = Class(AGFAssetRightRegistry)

function AGFAssetRightRegistry.new(idService, runtimeState, assetRegistry)
    local self = setmetatable({}, AGFAssetRightRegistry_mt)
    self.idService = idService
    self.runtimeState = runtimeState
    self.assetRegistry = assetRegistry
    self.rights = {}
    self.order = {}
    self.byAsset = {}
    return self
end

function AGFAssetRightRegistry:checkMutationAllowed(internal)
    if internal then return true, nil end
    if self.runtimeState == nil then return true, nil end
    return self.runtimeState:canMutate()
end

function AGFAssetRightRegistry:create(assetId, rightType, holderType, holderId)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return nil, errorCode end
    if assetId == nil or rightType == nil or holderType == nil or holderId == nil then
        return nil, "INVALID_RIGHT_ARGUMENTS"
    end
    if self.assetRegistry ~= nil and self.assetRegistry:get(assetId) == nil then
        return nil, "UNKNOWN_ASSET"
    end
    if self:getActiveRight(assetId, rightType) ~= nil then
        return nil, "ACTIVE_RIGHT_ALREADY_EXISTS"
    end

    local right = AGFAssetRight.new(self.idService:next("RIGHT"), assetId, rightType, holderType, tostring(holderId))
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        right.startYear = g_currentMission.environment.currentYear
        right.startPeriod = g_currentMission.environment.currentPeriod
    end
    return right, nil
end

function AGFAssetRightRegistry:register(right, internal)
    local allowed, errorCode = self:checkMutationAllowed(internal)
    if not allowed then return false, errorCode end
    if right == nil or right.id == nil or right.assetId == nil or right.rightType == nil or right.holderType == nil or right.holderId == nil then
        return false, "INVALID_RIGHT"
    end
    if self.rights[right.id] ~= nil then return false, "DUPLICATE_RIGHT_ID" end
    if right:isActive() and self:getActiveRight(right.assetId, right.rightType) ~= nil then
        return false, "ACTIVE_RIGHT_ALREADY_EXISTS"
    end

    local stored = right:clone()
    self.rights[stored.id] = stored
    table.insert(self.order, stored.id)
    self.byAsset[stored.assetId] = self.byAsset[stored.assetId] or {}
    table.insert(self.byAsset[stored.assetId], stored.id)
    if self.idService ~= nil then self.idService:observeId(stored.id) end
    return true, nil
end

function AGFAssetRightRegistry:get(id)
    local right = self.rights[id]
    return right ~= nil and right:clone() or nil
end

function AGFAssetRightRegistry:getAssetRights(assetId, includeInactive)
    local result = {}
    for _, id in ipairs(self.byAsset[assetId] or {}) do
        local right = self.rights[id]
        if right ~= nil and (includeInactive or right:isActive()) then
            table.insert(result, right:clone())
        end
    end
    return result
end

function AGFAssetRightRegistry:getActiveRight(assetId, rightType)
    for _, id in ipairs(self.byAsset[assetId] or {}) do
        local right = self.rights[id]
        if right ~= nil and right.rightType == rightType and right:isActive() then
            return right:clone()
        end
    end
    return nil
end

function AGFAssetRightRegistry:release(rightId, status)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local right = self.rights[rightId]
    if right == nil then return false, "UNKNOWN_RIGHT" end
    if not right:isActive() then return false, "RIGHT_NOT_ACTIVE" end

    right.status = status or AGFAssetRightStatus.RELEASED
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        right.endYear = g_currentMission.environment.currentYear
        right.endPeriod = g_currentMission.environment.currentPeriod
    end
    return true, right:clone()
end

function AGFAssetRightRegistry:replaceActiveRight(assetId, rightType, holderType, holderId)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end

    local current = self:getActiveRight(assetId, rightType)
    if current ~= nil then
        local released, releaseError = self:release(current.id)
        if not released then return false, releaseError end
    end

    local right, createError = self:create(assetId, rightType, holderType, holderId)
    if right == nil then return false, createError end
    local registered, registerError = self:register(right)
    if not registered then return false, registerError end
    return true, self:get(right.id)
end

function AGFAssetRightRegistry:isOwnedByFarm(assetId, farmId)
    local right = self:getActiveRight(assetId, AGFAssetRightType.ECONOMIC_OWNER)
    return right ~= nil and right.holderType == AGFRightHolderType.FARM and tostring(right.holderId) == tostring(farmId)
end

function AGFAssetRightRegistry:isOperatedByFarm(assetId, farmId)
    local operator = self:getActiveRight(assetId, AGFAssetRightType.OPERATOR)
    if operator ~= nil and operator.holderType == AGFRightHolderType.FARM and tostring(operator.holderId) == tostring(farmId) then
        return true
    end
    local tenant = self:getActiveRight(assetId, AGFAssetRightType.TENANT)
    return tenant ~= nil and tenant.holderType == AGFRightHolderType.FARM and tostring(tenant.holderId) == tostring(farmId)
end
