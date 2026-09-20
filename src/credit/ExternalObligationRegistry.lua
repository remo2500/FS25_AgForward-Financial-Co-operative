-- AgForward Financial Cooperative
-- Registry for represented obligations managed outside AgForward.

AGFExternalObligationRegistry = {}
AGFExternalObligationRegistry_mt = Class(AGFExternalObligationRegistry)

function AGFExternalObligationRegistry.new(idService)
    local self = setmetatable({}, AGFExternalObligationRegistry_mt)
    self.idService = idService
    self.obligations = {}
    self.order = {}
    self.byFarm = {}
    return self
end

function AGFExternalObligationRegistry:create(farmId, obligationType, source, displayName)
    if farmId == nil or obligationType == nil then return nil, "INVALID_EXTERNAL_OBLIGATION_ARGUMENTS" end
    local obligation = AGFExternalObligation.new(self.idService:next("EXT"), farmId, obligationType, source)
    obligation.displayName = displayName
    return obligation, nil
end

function AGFExternalObligationRegistry:register(obligation)
    if obligation == nil or obligation.id == nil or obligation.farmId == nil or obligation.obligationType == nil then
        return false, "INVALID_EXTERNAL_OBLIGATION"
    end
    if self.obligations[obligation.id] ~= nil then return false, "DUPLICATE_EXTERNAL_OBLIGATION_ID" end

    local stored = obligation:clone()
    stored.principalBalance = math.max(0, AGFCurrency.round(stored.principalBalance or 0))
    stored.annualDebtService = math.max(0, AGFCurrency.round(stored.annualDebtService or 0))
    stored.annualFixedCharge = math.max(0, AGFCurrency.round(stored.annualFixedCharge or 0))

    self.obligations[stored.id] = stored
    table.insert(self.order, stored.id)
    self.byFarm[stored.farmId] = self.byFarm[stored.farmId] or {}
    table.insert(self.byFarm[stored.farmId], stored.id)
    if self.idService ~= nil then self.idService:observeId(stored.id) end
    return true, nil
end

function AGFExternalObligationRegistry:get(id)
    local obligation = self.obligations[id]
    return obligation ~= nil and obligation:clone() or nil
end

function AGFExternalObligationRegistry:getFarmObligations(farmId, includeInactive)
    local result = {}
    for _, id in ipairs(self.byFarm[farmId] or {}) do
        local obligation = self.obligations[id]
        if obligation ~= nil and (includeInactive or obligation.active) then
            table.insert(result, obligation:clone())
        end
    end
    return result
end

function AGFExternalObligationRegistry:replaceSourceSnapshot(farmId, source, obligations)
    for _, id in ipairs(self.byFarm[farmId] or {}) do
        local existing = self.obligations[id]
        if existing ~= nil and existing.source == source then
            existing.active = false
        end
    end

    local registered = {}
    for _, obligation in ipairs(obligations or {}) do
        obligation.farmId = farmId
        obligation.source = source
        local ok, errorCode = self:register(obligation)
        if not ok then return false, errorCode end
        table.insert(registered, obligation.id)
    end
    return true, registered
end

function AGFExternalObligationRegistry:getFarmTotals(farmId)
    local totals = {
        principalBalance = 0,
        annualDebtService = 0,
        annualFixedCharge = 0,
        verifiedCount = 0,
        partialCount = 0,
        estimatedCount = 0,
        unknownCount = 0
    }

    for _, obligation in ipairs(self:getFarmObligations(farmId, false)) do
        totals.principalBalance = AGFCurrency.round(totals.principalBalance + (obligation.principalBalance or 0))
        totals.annualDebtService = AGFCurrency.round(totals.annualDebtService + (obligation.annualDebtService or 0))
        totals.annualFixedCharge = AGFCurrency.round(totals.annualFixedCharge + (obligation.annualFixedCharge or 0))

        if obligation.dataQuality == AGFExternalObligationQuality.VERIFIED then
            totals.verifiedCount = totals.verifiedCount + 1
        elseif obligation.dataQuality == AGFExternalObligationQuality.PARTIAL then
            totals.partialCount = totals.partialCount + 1
        elseif obligation.dataQuality == AGFExternalObligationQuality.ESTIMATED then
            totals.estimatedCount = totals.estimatedCount + 1
        else
            totals.unknownCount = totals.unknownCount + 1
        end
    end

    return totals
end
