-- AgForward Financial Cooperative
-- Authoritative economic asset registry. Runtime object links are secondary.

AGFAssetRegistry = {}
AGFAssetRegistry_mt = Class(AGFAssetRegistry)

function AGFAssetRegistry.new(idService, runtimeState)
    local self = setmetatable({}, AGFAssetRegistry_mt)
    self.idService = idService
    self.runtimeState = runtimeState
    self.assets = {}
    self.order = {}
    self.byStableKey = {}
    self.byType = {}
    return self
end

function AGFAssetRegistry:checkMutationAllowed(internal)
    if internal then return true, nil end
    if self.runtimeState == nil then return true, nil end
    return self.runtimeState:canMutate()
end

function AGFAssetRegistry:create(assetType, stableKey, displayName)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return nil, errorCode end
    if assetType == nil or stableKey == nil or stableKey == "" then
        return nil, "INVALID_ASSET_ARGUMENTS"
    end
    stableKey = tostring(stableKey)
    if self.byStableKey[stableKey] ~= nil then
        return nil, "DUPLICATE_STABLE_KEY"
    end

    local asset = AGFAssetRecord.new(self.idService:next("ASSET"), assetType, stableKey)
    asset.displayName = displayName
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        asset.acquisitionYear = g_currentMission.environment.currentYear
        asset.acquisitionPeriod = g_currentMission.environment.currentPeriod
    end
    return asset, nil
end

function AGFAssetRegistry:register(asset, internal)
    local allowed, errorCode = self:checkMutationAllowed(internal)
    if not allowed then return false, errorCode end
    if asset == nil or asset.id == nil or asset.assetType == nil or asset.stableKey == nil or asset.stableKey == "" then
        return false, "INVALID_ASSET"
    end
    if self.assets[asset.id] ~= nil then
        return false, "DUPLICATE_ASSET_ID"
    end
    if self.byStableKey[asset.stableKey] ~= nil then
        return false, "DUPLICATE_STABLE_KEY"
    end

    local stored = asset:clone()
    self.assets[stored.id] = stored
    table.insert(self.order, stored.id)
    self.byStableKey[stored.stableKey] = stored.id
    self.byType[stored.assetType] = self.byType[stored.assetType] or {}
    table.insert(self.byType[stored.assetType], stored.id)
    if self.idService ~= nil then self.idService:observeId(stored.id) end
    return true, nil
end

function AGFAssetRegistry:getInternal(id)
    return self.assets[id]
end

function AGFAssetRegistry:get(id)
    local asset = self.assets[id]
    return asset ~= nil and asset:clone() or nil
end

function AGFAssetRegistry:getByStableKey(stableKey)
    local id = self.byStableKey[tostring(stableKey)]
    return id ~= nil and self:get(id) or nil
end

function AGFAssetRegistry:getAll()
    local result = {}
    for _, id in ipairs(self.order) do
        local asset = self.assets[id]
        if asset ~= nil then table.insert(result, asset:clone()) end
    end
    return result
end

function AGFAssetRegistry:getByType(assetType, includeDisposed)
    local result = {}
    for _, id in ipairs(self.byType[assetType] or {}) do
        local asset = self.assets[id]
        if asset ~= nil and (includeDisposed or asset.status == AGFAssetStatus.ACTIVE) then
            table.insert(result, asset:clone())
        end
    end
    return result
end

function AGFAssetRegistry:setValue(assetId, currentValue)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local asset = self.assets[assetId]
    if asset == nil then return false, "UNKNOWN_ASSET" end
    local value = tonumber(currentValue)
    if value == nil or value < 0 then return false, "INVALID_ASSET_VALUE" end
    asset.currentValue = AGFCurrency.round(value)
    return true, asset:clone()
end

function AGFAssetRegistry:setRuntimeLink(assetId, runtimeObjectId)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local asset = self.assets[assetId]
    if asset == nil then return false, "UNKNOWN_ASSET" end
    asset.runtimeObjectId = runtimeObjectId
    asset.linkState = runtimeObjectId ~= nil and AGFAssetLinkState.RESOLVED or AGFAssetLinkState.UNRESOLVED
    return true, asset:clone()
end

function AGFAssetRegistry:markQuarantined(assetId, reason)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local asset = self.assets[assetId]
    if asset == nil then return false, "UNKNOWN_ASSET" end
    asset.runtimeObjectId = nil
    asset.linkState = AGFAssetLinkState.QUARANTINED
    asset:setMetadata("quarantineReason", reason or "unresolved")
    return true, asset:clone()
end

function AGFAssetRegistry:markDisposed(assetId)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local asset = self.assets[assetId]
    if asset == nil then return false, "UNKNOWN_ASSET" end
    asset.status = AGFAssetStatus.DISPOSED
    asset.runtimeObjectId = nil
    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        asset.disposalYear = g_currentMission.environment.currentYear
        asset.disposalPeriod = g_currentMission.environment.currentPeriod
    end
    return true, asset:clone()
end
