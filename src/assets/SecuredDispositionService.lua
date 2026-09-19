-- AgForward Financial Cooperative
-- Read-only secured-sale/trade preflight shared by future equipment, project,
-- land, and trade-in workflows. Execution/money movement is intentionally absent.

AGFSecuredDispositionService = {}
AGFSecuredDispositionService_mt = Class(AGFSecuredDispositionService)

function AGFSecuredDispositionService.new(assetRegistry, lienRegistry, liabilityRegistry, rightRegistry)
    local self = setmetatable({}, AGFSecuredDispositionService_mt)
    self.assetRegistry = assetRegistry
    self.lienRegistry = lienRegistry
    self.liabilityRegistry = liabilityRegistry
    self.rightRegistry = rightRegistry
    return self
end

function AGFSecuredDispositionService:preflight(assetId, grossProceeds, availableCash, actingFarmId)
    local asset = self.assetRegistry ~= nil and self.assetRegistry:get(assetId) or nil
    if asset == nil then return false, "UNKNOWN_ASSET" end
    if not asset:isActive() then return false, "ASSET_NOT_ACTIVE" end
    if asset.linkState == AGFAssetLinkState.QUARANTINED then return false, "ASSET_LINK_QUARANTINED" end

    if actingFarmId ~= nil and self.rightRegistry ~= nil and not self.rightRegistry:isOwnedByFarm(assetId, actingFarmId) then
        return false, "ACTING_FARM_NOT_ECONOMIC_OWNER"
    end

    local gross = tonumber(grossProceeds)
    local cash = tonumber(availableCash) or 0
    if gross == nil or gross < 0 then return false, "INVALID_GROSS_PROCEEDS" end
    if cash < 0 then return false, "INVALID_AVAILABLE_CASH" end
    gross = AGFCurrency.round(gross)
    cash = AGFCurrency.round(cash)

    local lienBreakdown = {}
    local totalPayoff = 0
    local activeLiens = self.lienRegistry ~= nil and self.lienRegistry:getAssetLiens(assetId, false) or {}

    for _, lien in ipairs(activeLiens) do
        local liability = self.liabilityRegistry ~= nil and self.liabilityRegistry:get(lien.liabilityId) or nil
        if liability == nil then
            return false, "LIEN_LIABILITY_UNRESOLVED"
        end

        local payoff = AGFCurrency.round(liability:getOutstandingBalance())
        if lien.securedAmountCap ~= nil and lien.securedAmountCap > 0 then
            payoff = math.min(payoff, AGFCurrency.round(lien.securedAmountCap))
        end
        payoff = AGFCurrency.round(math.max(0, payoff))

        table.insert(lienBreakdown, {
            lienId = lien.id,
            liabilityId = lien.liabilityId,
            priority = lien.priority,
            payoff = payoff
        })
        totalPayoff = AGFCurrency.round(totalPayoff + payoff)
    end

    local grossEquity = AGFCurrency.round(gross - totalPayoff)
    local requiredCashContribution = grossEquity < 0 and AGFCurrency.round(-grossEquity) or 0
    local netCashToOwner = grossEquity > 0 and grossEquity or 0
    local allowed = AGFCurrency.toMinorUnits(cash) >= AGFCurrency.toMinorUnits(requiredCashContribution)

    return true, {
        allowed = allowed,
        assetId = assetId,
        grossProceeds = gross,
        lienPayoff = totalPayoff,
        grossEquity = grossEquity,
        requiredCashContribution = requiredCashContribution,
        availableCash = cash,
        netCashToOwner = netCashToOwner,
        lienBreakdown = lienBreakdown,
        denialReason = allowed and nil or "INSUFFICIENT_CASH_TO_CLEAR_LIENS"
    }
end
