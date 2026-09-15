-- AgForward Financial Cooperative
-- Secured claim linking an asset to an AgForward liability.

AGFLienStatus = {
    ACTIVE = "active",
    RELEASED = "released",
    SATISFIED = "satisfied"
}

AGFLien = {}
AGFLien_mt = Class(AGFLien)

function AGFLien.new(id, assetId, liabilityId)
    local self = setmetatable({}, AGFLien_mt)
    self.id = id
    self.assetId = assetId
    self.liabilityId = liabilityId
    self.status = AGFLienStatus.ACTIVE
    self.priority = 1
    self.securedAmountCap = 0
    self.startYear = nil
    self.startPeriod = nil
    self.releaseYear = nil
    self.releasePeriod = nil
    self.metadata = {}
    return self
end

function AGFLien:isActive()
    return self.status == AGFLienStatus.ACTIVE
end

function AGFLien:setMetadata(key, value)
    if key ~= nil then
        if value == nil then
            self.metadata[tostring(key)] = nil
        else
            self.metadata[tostring(key)] = tostring(value)
        end
    end
    return self
end

function AGFLien:clone()
    local copy = AGFLien.new(self.id, self.assetId, self.liabilityId)
    copy.status = self.status
    copy.priority = self.priority
    copy.securedAmountCap = self.securedAmountCap
    copy.startYear = self.startYear
    copy.startPeriod = self.startPeriod
    copy.releaseYear = self.releaseYear
    copy.releasePeriod = self.releasePeriod
    copy.metadata = {}
    for key, value in pairs(self.metadata or {}) do
        copy.metadata[key] = value
    end
    return copy
end
