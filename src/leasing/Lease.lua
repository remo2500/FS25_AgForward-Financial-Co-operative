-- AgForward Financial Cooperative
-- Common economic lease record. Engine access/ownership mechanics are adapters,
-- not the source of economic truth.

AGFLeaseStatus = {
    PENDING = "pending",
    ACTIVE = "active",
    PAST_DUE = "pastDue",
    DEFAULTED = "defaulted",
    EXPIRED = "expired",
    TERMINATED = "terminated",
    COMPLETED = "completed"
}

AGFLeaseType = {
    FARMLAND = "farmland",
    EQUIPMENT = "equipment",
    FACILITY = "facility",
    OTHER = "other"
}

AGFLease = {}
AGFLease_mt = Class(AGFLease)

function AGFLease.new(id, assetId, leaseType, lesseeFarmId)
    local self = setmetatable({}, AGFLease_mt)
    self.id = id
    self.assetId = assetId
    self.leaseType = leaseType
    self.lesseeFarmId = lesseeFarmId
    self.status = AGFLeaseStatus.PENDING
    self.displayName = nil
    self.lessorType = "external"
    self.lessorId = nil
    self.periodicRent = 0
    self.paymentsPerYear = 12
    self.termPeriods = 0
    self.remainingPeriods = 0
    self.startYear = nil
    self.startPeriod = nil
    self.nextPaymentYear = nil
    self.nextPaymentPeriod = nil
    self.endYear = nil
    self.endPeriod = nil
    self.accruedRent = 0
    self.accruedFees = 0
    self.autoRenew = false
    self.metadata = {}
    return self
end

function AGFLease:isOpen()
    return self.status == AGFLeaseStatus.PENDING
        or self.status == AGFLeaseStatus.ACTIVE
        or self.status == AGFLeaseStatus.PAST_DUE
        or self.status == AGFLeaseStatus.DEFAULTED
end

function AGFLease:getOutstandingDue()
    return AGFCurrency.round((self.accruedRent or 0) + (self.accruedFees or 0))
end

function AGFLease:getAnnualizedFixedCharge()
    if not self:isOpen() then return 0 end
    local frequency = tonumber(self.paymentsPerYear) or 12
    if frequency <= 0 then frequency = 12 end
    return AGFCurrency.round((self.periodicRent or 0) * frequency)
end

function AGFLease:setMetadata(key, value)
    if key ~= nil then
        if value == nil then self.metadata[tostring(key)] = nil
        else self.metadata[tostring(key)] = tostring(value) end
    end
    return self
end

function AGFLease:clone()
    local copy = AGFLease.new(self.id, self.assetId, self.leaseType, self.lesseeFarmId)
    copy.status = self.status
    copy.displayName = self.displayName
    copy.lessorType = self.lessorType
    copy.lessorId = self.lessorId
    copy.periodicRent = self.periodicRent
    copy.paymentsPerYear = self.paymentsPerYear
    copy.termPeriods = self.termPeriods
    copy.remainingPeriods = self.remainingPeriods
    copy.startYear = self.startYear
    copy.startPeriod = self.startPeriod
    copy.nextPaymentYear = self.nextPaymentYear
    copy.nextPaymentPeriod = self.nextPaymentPeriod
    copy.endYear = self.endYear
    copy.endPeriod = self.endPeriod
    copy.accruedRent = self.accruedRent
    copy.accruedFees = self.accruedFees
    copy.autoRenew = self.autoRenew
    copy.metadata = {}
    for key, value in pairs(self.metadata or {}) do copy.metadata[key] = value end
    return copy
end
