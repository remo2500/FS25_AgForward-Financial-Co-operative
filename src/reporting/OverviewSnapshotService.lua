-- AgForward Financial Cooperative
-- Read-only overview projection for future UI/reporting. It derives values from
-- common registries and never becomes an independent financial balance store.

AGFOverviewSnapshotService = {}
AGFOverviewSnapshotService_mt = Class(AGFOverviewSnapshotService)

function AGFOverviewSnapshotService.new(liabilityRegistry, externalObligations, assetRegistry, rightRegistry, lienRegistry, ledger)
    local self = setmetatable({}, AGFOverviewSnapshotService_mt)
    self.liabilityRegistry = liabilityRegistry
    self.externalObligations = externalObligations
    self.assetRegistry = assetRegistry
    self.rightRegistry = rightRegistry
    self.lienRegistry = lienRegistry
    self.ledger = ledger
    return self
end

function AGFOverviewSnapshotService:build(farmId, context)
    context = context or {}

    local nativeDebt = 0
    local operatingLineBalance = 0
    local operatingLineAvailable = 0
    local cropInputLineBalance = 0
    local cropInputLineAvailable = 0
    local nativeLiabilityCount = 0

    if self.liabilityRegistry ~= nil then
        for _, liability in ipairs(self.liabilityRegistry:getFarmLiabilities(farmId, false)) do
            nativeLiabilityCount = nativeLiabilityCount + 1
            nativeDebt = AGFCurrency.round(nativeDebt + liability:getOutstandingBalance())
            if liability.productType == AGFProductType.OPERATING_LINE then
                operatingLineBalance = AGFCurrency.round(operatingLineBalance + (liability.principalBalance or 0))
                operatingLineAvailable = AGFCurrency.round(operatingLineAvailable + liability:getAvailableCredit())
            elseif liability.productType == AGFProductType.CROP_INPUT_LINE then
                cropInputLineBalance = AGFCurrency.round(cropInputLineBalance + (liability.principalBalance or 0))
                cropInputLineAvailable = AGFCurrency.round(cropInputLineAvailable + liability:getAvailableCredit())
            end
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
    if self.externalObligations ~= nil then
        externalTotals = self.externalObligations:getFarmTotals(farmId)
    end

    local registeredOwnedAssetValue = 0
    local registeredOwnedAssetCount = 0
    local unresolvedOwnedAssetCount = 0
    local activeLienCount = 0

    if self.assetRegistry ~= nil and self.rightRegistry ~= nil then
        for _, asset in ipairs(self.assetRegistry:getAll()) do
            if asset:isActive() and self.rightRegistry:isOwnedByFarm(asset.id, farmId) then
                registeredOwnedAssetCount = registeredOwnedAssetCount + 1
                registeredOwnedAssetValue = AGFCurrency.round(registeredOwnedAssetValue + (asset.currentValue or 0))
                if asset.linkState == AGFAssetLinkState.UNRESOLVED or asset.linkState == AGFAssetLinkState.QUARANTINED then
                    unresolvedOwnedAssetCount = unresolvedOwnedAssetCount + 1
                end
                if self.lienRegistry ~= nil then
                    activeLienCount = activeLienCount + #self.lienRegistry:getAssetLiens(asset.id, false)
                end
            end
        end
    end

    local cashBalance = AGFCurrency.round(context.cashBalance or 0)
    local otherOwnedAssetValue = AGFCurrency.round(context.otherOwnedAssetValue or 0)
    local representedAssets = AGFCurrency.round(cashBalance + otherOwnedAssetValue + registeredOwnedAssetValue)
    local representedLiabilities = AGFCurrency.round(nativeDebt + (externalTotals.principalBalance or 0))
    local representedEquity = AGFCurrency.round(representedAssets - representedLiabilities)

    local recentTransactions = {}
    local recentLimit = math.max(0, math.floor(tonumber(context.recentTransactionLimit) or 10))
    if self.ledger ~= nil and recentLimit > 0 then
        local farmTransactions = self.ledger:getFarmTransactions(farmId)
        local startIndex = math.max(1, #farmTransactions - recentLimit + 1)
        for index = #farmTransactions, startIndex, -1 do
            table.insert(recentTransactions, farmTransactions[index])
        end
    end

    local dataQuality = "COMPLETE_NATIVE_VIEW"
    if externalTotals.unknownCount > 0 then
        dataQuality = "UNKNOWN_EXTERNAL_OBLIGATIONS"
    elseif externalTotals.partialCount > 0 or externalTotals.estimatedCount > 0 then
        dataQuality = "PARTIAL_EXTERNAL_OBLIGATIONS"
    elseif unresolvedOwnedAssetCount > 0 then
        dataQuality = "UNRESOLVED_ASSET_LINKS"
    elseif context.otherOwnedAssetValue == nil then
        dataQuality = "REGISTERED_ASSETS_ONLY"
    end

    return {
        farmId = farmId,
        cashBalance = cashBalance,
        nativeDebt = nativeDebt,
        externalDebt = AGFCurrency.round(externalTotals.principalBalance or 0),
        representedLiabilities = representedLiabilities,
        registeredOwnedAssetValue = registeredOwnedAssetValue,
        otherOwnedAssetValue = otherOwnedAssetValue,
        representedAssets = representedAssets,
        representedEquity = representedEquity,
        nativeLiabilityCount = nativeLiabilityCount,
        registeredOwnedAssetCount = registeredOwnedAssetCount,
        unresolvedOwnedAssetCount = unresolvedOwnedAssetCount,
        activeLienCount = activeLienCount,
        operatingLineBalance = operatingLineBalance,
        operatingLineAvailable = operatingLineAvailable,
        cropInputLineBalance = cropInputLineBalance,
        cropInputLineAvailable = cropInputLineAvailable,
        externalAnnualDebtService = AGFCurrency.round(externalTotals.annualDebtService or 0),
        externalAnnualFixedCharge = AGFCurrency.round(externalTotals.annualFixedCharge or 0),
        externalDataQuality = externalTotals,
        recentTransactions = recentTransactions,
        dataQuality = dataQuality
    }
end
