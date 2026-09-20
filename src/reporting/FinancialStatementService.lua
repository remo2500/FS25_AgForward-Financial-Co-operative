-- AgForward Financial Cooperative
-- Read-only financial statement assembled from common registries. Economic
-- ownership, not FS25 operator access, determines which registered assets belong
-- on the farm balance sheet.

AGFFinancialStatementService = {}
AGFFinancialStatementService_mt = Class(AGFFinancialStatementService)

local function addMoney(map, key, amount)
    local normalizedKey = key or "other"
    map[normalizedKey] = AGFCurrency.round((map[normalizedKey] or 0) + (amount or 0))
end

function AGFFinancialStatementService.new(assetRegistry, rightRegistry, liabilityRegistry, externalObligationRegistry, leaseRegistry, financialHistoryService)
    local self = setmetatable({}, AGFFinancialStatementService_mt)
    self.assetRegistry = assetRegistry
    self.rightRegistry = rightRegistry
    self.liabilityRegistry = liabilityRegistry
    self.externalObligationRegistry = externalObligationRegistry
    self.leaseRegistry = leaseRegistry
    self.financialHistoryService = financialHistoryService
    return self
end

function AGFFinancialStatementService:build(farmId, context)
    context = context or {}

    local cashBalance = AGFCurrency.round(tonumber(context.cashBalance) or 0)
    local otherOwnedAssetValue = math.max(0, AGFCurrency.round(tonumber(context.otherOwnedAssetValue) or 0))
    local otherLiabilityValue = math.max(0, AGFCurrency.round(tonumber(context.otherLiabilityValue) or 0))

    local assets = {
        cash = cashBalance,
        registered = 0,
        otherOwned = otherOwnedAssetValue,
        total = 0,
        byType = {},
        acquisitionCostByType = {},
        ownedAssetCount = 0,
        unresolvedOwnedAssetCount = 0
    }

    if self.assetRegistry ~= nil and self.rightRegistry ~= nil then
        for _, asset in ipairs(self.assetRegistry:getAll()) do
            if asset:isActive() and self.rightRegistry:isOwnedByFarm(asset.id, farmId) then
                local value = math.max(0, AGFCurrency.round(asset.currentValue or 0))
                local acquisitionCost = math.max(0, AGFCurrency.round(asset.acquisitionCost or 0))
                assets.registered = AGFCurrency.round(assets.registered + value)
                assets.ownedAssetCount = assets.ownedAssetCount + 1
                addMoney(assets.byType, asset.assetType, value)
                addMoney(assets.acquisitionCostByType, asset.assetType, acquisitionCost)
                if asset.linkState == AGFAssetLinkState.UNRESOLVED or asset.linkState == AGFAssetLinkState.QUARANTINED then
                    assets.unresolvedOwnedAssetCount = assets.unresolvedOwnedAssetCount + 1
                end
            end
        end
    end
    assets.total = AGFCurrency.round(assets.cash + assets.registered + assets.otherOwned)

    local liabilities = {
        nativePrincipal = 0,
        nativeAccruedInterest = 0,
        nativeAccruedFees = 0,
        nativeOutstanding = 0,
        externalPrincipal = 0,
        other = otherLiabilityValue,
        total = 0,
        byProduct = {},
        nativeCount = 0,
        externalCount = 0
    }

    if self.liabilityRegistry ~= nil then
        for _, liability in ipairs(self.liabilityRegistry:getFarmLiabilities(farmId, false)) do
            local principal = math.max(0, AGFCurrency.round(liability.principalBalance or 0))
            local interest = math.max(0, AGFCurrency.round(liability.accruedInterest or 0))
            local fees = math.max(0, AGFCurrency.round(liability.accruedFees or 0))
            local outstanding = AGFCurrency.round(principal + interest + fees)

            liabilities.nativeCount = liabilities.nativeCount + 1
            liabilities.nativePrincipal = AGFCurrency.round(liabilities.nativePrincipal + principal)
            liabilities.nativeAccruedInterest = AGFCurrency.round(liabilities.nativeAccruedInterest + interest)
            liabilities.nativeAccruedFees = AGFCurrency.round(liabilities.nativeAccruedFees + fees)
            liabilities.nativeOutstanding = AGFCurrency.round(liabilities.nativeOutstanding + outstanding)
            addMoney(liabilities.byProduct, liability.productType, outstanding)
        end
    end

    local externalTotals = {
        principalBalance = 0,
        annualDebtService = 0,
        annualFixedCharge = 0,
        verifiedCount = 0,
        partialCount = 0,
        estimatedCount = 0,
        unknownCount = 0
    }
    if self.externalObligationRegistry ~= nil then
        externalTotals = self.externalObligationRegistry:getFarmTotals(farmId)
        liabilities.externalCount = externalTotals.verifiedCount + externalTotals.partialCount
            + externalTotals.estimatedCount + externalTotals.unknownCount
        liabilities.externalPrincipal = AGFCurrency.round(externalTotals.principalBalance or 0)
    end

    liabilities.total = AGFCurrency.round(
        liabilities.nativeOutstanding + liabilities.externalPrincipal + liabilities.other
    )

    local leaseFixedCharges = 0
    if self.leaseRegistry ~= nil then
        leaseFixedCharges = AGFCurrency.round(self.leaseRegistry:getAnnualFixedCharges(farmId))
    end
    local annualFixedCharges = AGFCurrency.round(
        leaseFixedCharges + (externalTotals.annualFixedCharge or 0)
    )

    local equity = AGFCurrency.round(assets.total - liabilities.total)
    local debtToAssets = nil
    if assets.total > 0 then debtToAssets = liabilities.total / assets.total end

    local currentYearHistory = nil
    if self.financialHistoryService ~= nil and context.currentYear ~= nil then
        local historyOk, historyOrError = self.financialHistoryService:buildAnnual(farmId, context.currentYear)
        if historyOk then currentYearHistory = historyOrError end
    end

    local dataQualityIssues = {}
    if context.cashBalance == nil then table.insert(dataQualityIssues, "CASH_BALANCE_NOT_SUPPLIED") end
    if self.rightRegistry == nil then table.insert(dataQualityIssues, "OWNERSHIP_RIGHTS_UNAVAILABLE") end
    if assets.unresolvedOwnedAssetCount > 0 then table.insert(dataQualityIssues, "UNRESOLVED_OWNED_ASSET_LINKS") end
    if externalTotals.unknownCount > 0 then table.insert(dataQualityIssues, "UNKNOWN_EXTERNAL_OBLIGATIONS") end
    if externalTotals.partialCount > 0 or externalTotals.estimatedCount > 0 then
        table.insert(dataQualityIssues, "PARTIAL_OR_ESTIMATED_EXTERNAL_OBLIGATIONS")
    end
    if context.otherOwnedAssetValue == nil then table.insert(dataQualityIssues, "OTHER_OWNED_ASSETS_NOT_SUPPLIED") end

    return {
        farmId = farmId,
        asOfYear = context.currentYear,
        asOfPeriod = context.currentPeriod,
        assets = assets,
        liabilities = liabilities,
        equity = equity,
        debtToAssets = debtToAssets,
        annualFixedCharges = annualFixedCharges,
        leaseAnnualFixedCharges = leaseFixedCharges,
        externalAnnualDebtService = AGFCurrency.round(externalTotals.annualDebtService or 0),
        externalAnnualFixedCharges = AGFCurrency.round(externalTotals.annualFixedCharge or 0),
        currentYearHistory = currentYearHistory,
        dataQuality = {
            complete = #dataQualityIssues == 0,
            issues = dataQualityIssues,
            external = externalTotals
        }
    }
end
