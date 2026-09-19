-- AgForward Financial Cooperative
-- Read-model record for debt/fixed charges managed outside AgForward.

AGFExternalObligationType = {
    BASE_GAME_LOAN = "baseGameLoan",
    VEHICLE_LEASE = "vehicleLease",
    LAND_RENT = "landRent",
    THIRD_PARTY_DEBT = "thirdPartyDebt",
    OTHER = "other"
}

AGFExternalObligationQuality = {
    VERIFIED = "verified",
    PARTIAL = "partial",
    ESTIMATED = "estimated",
    UNKNOWN = "unknown"
}

AGFExternalObligation = {}
AGFExternalObligation_mt = Class(AGFExternalObligation)

function AGFExternalObligation.new(id, farmId, obligationType, source)
    local self = setmetatable({}, AGFExternalObligation_mt)
    self.id = id
    self.farmId = farmId
    self.obligationType = obligationType
    self.source = source or "external"
    self.displayName = nil
    self.principalBalance = 0
    self.annualDebtService = 0
    self.annualFixedCharge = 0
    self.dataQuality = AGFExternalObligationQuality.UNKNOWN
    self.modifiableByAgForward = false
    self.active = true
    self.metadata = {}
    return self
end

function AGFExternalObligation:setMetadata(key, value)
    if key ~= nil then
        if value == nil then
            self.metadata[tostring(key)] = nil
        else
            self.metadata[tostring(key)] = tostring(value)
        end
    end
    return self
end

function AGFExternalObligation:clone()
    local copy = AGFExternalObligation.new(self.id, self.farmId, self.obligationType, self.source)
    copy.displayName = self.displayName
    copy.principalBalance = self.principalBalance
    copy.annualDebtService = self.annualDebtService
    copy.annualFixedCharge = self.annualFixedCharge
    copy.dataQuality = self.dataQuality
    copy.modifiableByAgForward = self.modifiableByAgForward
    copy.active = self.active
    copy.metadata = {}
    for key, value in pairs(self.metadata or {}) do copy.metadata[key] = value end
    return copy
end
