-- AgForward Financial Cooperative
-- Economic/operating rights are separate from FS25 engine ownership flags.

AGFAssetRightType = {
    ECONOMIC_OWNER = "economicOwner",
    OPERATOR = "operator",
    TENANT = "tenant"
}

AGFRightHolderType = {
    FARM = "farm",
    EXTERNAL = "external",
    SYSTEM = "system"
}

AGFAssetRightStatus = {
    ACTIVE = "active",
    RELEASED = "released",
    EXPIRED = "expired"
}

AGFAssetRight = {}
AGFAssetRight_mt = Class(AGFAssetRight)

function AGFAssetRight.new(id, assetId, rightType, holderType, holderId)
    local self = setmetatable({}, AGFAssetRight_mt)
    self.id = id
    self.assetId = assetId
    self.rightType = rightType
    self.holderType = holderType
    self.holderId = holderId
    self.status = AGFAssetRightStatus.ACTIVE
    self.startYear = nil
    self.startPeriod = nil
    self.endYear = nil
    self.endPeriod = nil
    self.metadata = {}
    return self
end

function AGFAssetRight:isActive()
    return self.status == AGFAssetRightStatus.ACTIVE
end

function AGFAssetRight:setMetadata(key, value)
    if key ~= nil then
        if value == nil then
            self.metadata[tostring(key)] = nil
        else
            self.metadata[tostring(key)] = tostring(value)
        end
    end
    return self
end

function AGFAssetRight:clone()
    local copy = AGFAssetRight.new(self.id, self.assetId, self.rightType, self.holderType, self.holderId)
    copy.status = self.status
    copy.startYear = self.startYear
    copy.startPeriod = self.startPeriod
    copy.endYear = self.endYear
    copy.endPeriod = self.endPeriod
    copy.metadata = {}
    for key, value in pairs(self.metadata or {}) do
        copy.metadata[key] = value
    end
    return copy
end
