-- AgForward Financial Cooperative
-- Economic asset identity independent from transient FS25 runtime object IDs.

AGFAssetType = {
    VEHICLE = "vehicle",
    PLACEABLE = "placeable",
    FARMLAND = "farmland",
    OTHER = "other"
}

AGFAssetStatus = {
    ACTIVE = "active",
    DISPOSED = "disposed",
    RETIRED = "retired"
}

AGFAssetLinkState = {
    UNRESOLVED = "unresolved",
    RESOLVED = "resolved",
    QUARANTINED = "quarantined",
    NOT_REQUIRED = "notRequired"
}

AGFAssetRecord = {}
AGFAssetRecord_mt = Class(AGFAssetRecord)

function AGFAssetRecord.new(id, assetType, stableKey)
    local self = setmetatable({}, AGFAssetRecord_mt)
    self.id = id
    self.assetType = assetType
    self.stableKey = stableKey
    self.displayName = nil
    self.status = AGFAssetStatus.ACTIVE
    self.linkState = AGFAssetLinkState.UNRESOLVED
    self.runtimeObjectId = nil
    self.acquisitionCost = 0
    self.currentValue = 0
    self.acquisitionYear = nil
    self.acquisitionPeriod = nil
    self.disposalYear = nil
    self.disposalPeriod = nil
    self.metadata = {}
    return self
end

function AGFAssetRecord:isActive()
    return self.status == AGFAssetStatus.ACTIVE
end

function AGFAssetRecord:setMetadata(key, value)
    if key ~= nil then
        if value == nil then
            self.metadata[tostring(key)] = nil
        else
            self.metadata[tostring(key)] = tostring(value)
        end
    end
    return self
end

function AGFAssetRecord:clone()
    local copy = AGFAssetRecord.new(self.id, self.assetType, self.stableKey)
    copy.displayName = self.displayName
    copy.status = self.status
    copy.linkState = self.linkState
    copy.runtimeObjectId = self.runtimeObjectId
    copy.acquisitionCost = self.acquisitionCost
    copy.currentValue = self.currentValue
    copy.acquisitionYear = self.acquisitionYear
    copy.acquisitionPeriod = self.acquisitionPeriod
    copy.disposalYear = self.disposalYear
    copy.disposalPeriod = self.disposalPeriod
    copy.metadata = {}
    for key, value in pairs(self.metadata or {}) do
        copy.metadata[key] = value
    end
    return copy
end
