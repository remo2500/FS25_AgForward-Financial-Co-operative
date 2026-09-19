-- AgForward Financial Cooperative
-- Read-only whole-farm credit profile builder. It derives a borrower view from
-- common registries and explicitly reports missing/partial information.

AGFCreditProfileBuilder = {}
AGFCreditProfileBuilder_mt = Class(AGFCreditProfileBuilder)

function AGFCreditProfileBuilder.new(liabilityRegistry, externalRegistry, assetRegistry, rightRegistry, lienRegistry, leaseRegistry)
    local self = setmetatable({}, AGFCreditProfileBuilder_mt)
    self.liabilityRegistry = liabilityRegistry
    self.externalRegistry = externalRegistry
    self.assetRegistry = assetRegistry
    self.rightRegistry = rightRegistry
    self.lienRegistry = lienRegistry
    self.leaseRegistry = leaseRegistry
    return self
end

local QUALITY_RANK = {
    [AGFCreditDataQuality.COMPLETE] = 0,
    [AGFCreditDataQuality.INSUFFICIENT_HISTORY] = 1,
    [AGFCreditDataQuality.ASSET_LINK_UNRESOLVED] = 2,
    [AGFCreditDataQuality.PARTIAL_EXTERNAL_DEBT] = 3,
    [AGFCreditDataQuality.UNKNOWN_EXTERNAL_DEBT] = 4
}

local function addIssue(profile, quality, code, detail)
    profile:addQualityIssue(code, detail)
    local currentRank = QUALITY_RANK[profile.dataQuality] or 0
    local proposedRank = QUALITY_RANK[quality] or 0
    if proposedRank > currentRank then
        profile.dataQuality = quality
    end
end

local function positiveWhole(value)
    local number = tonumber(value)
    if number == nil or number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

local function getPaymentFrequency(liability)
    -- Schema-v3 liabilities are monthly by default. Offline/future contract
    -- models may expose frequency directly or through persisted metadata until
    -- the post-runtime schema promotion is deliberately implemented.
    local frequency = positiveWhole(liability.paymentFrequency)
        or positiveWhole(liability.paymentsPerYear)
        or positiveWhole(liability.metadata ~= nil and liability.metadata.paymentsPerYear or nil)
        or 12
    if frequency ~= 1 and frequency ~= 2 and frequency ~= 4 and frequency ~= 12 then
        return nil
    end
    return frequency
end

local function getRemainingPaymentPeriods(liability, paymentFrequency)
    local explicit = positiveWhole(liability.remainingPaymentPeriods)
        or positiveWhole(liability.metadata ~= nil and liability.metadata.remainingPaymentPeriods or nil)
    if explicit ~= nil then return explicit end

    -- Legacy schema-v3 term is stored in months. Convert remaining months to the
    -- number of scheduled payments for non-monthly offline contract models.
    local remainingMonths = math.max(0, math.floor(tonumber(liability.remainingTermMonths) or 0))
    if remainingMonths <= 0 then return nil end
    if paymentFrequency == 12 then return remainingMonths end
    return math.max(1, math.ceil((remainingMonths / 12) * paymentFrequency))
end

local function estimateNativeDebtService(liabilities, profile)
    local annualDebtService = 0
    local currentLiabilityPortion = 0

    for _, liability in ipairs(liabilities or {}) do
        local outstanding = AGFCurrency.round(liability:getOutstandingBalance())
        if outstanding > 0 then
            local payment = AGFCurrency.round(liability.scheduledPayment or 0)
            local paymentFrequency = getPaymentFrequency(liability)
            if paymentFrequency == nil then
                addIssue(
                    profile,
                    AGFCreditDataQuality.INSUFFICIENT_HISTORY,
                    "INVALID_PAYMENT_FREQUENCY",
                    tostring(liability.id)
                )
                paymentFrequency = 12
            end
            local remainingPayments = getRemainingPaymentPeriods(liability, paymentFrequency)

            if payment > 0 then
                local paymentCount = remainingPayments ~= nil and math.min(paymentFrequency, remainingPayments) or paymentFrequency
                local scheduled = AGFCurrency.round(payment * paymentCount)
                annualDebtService = AGFCurrency.round(annualDebtService + scheduled)
                currentLiabilityPortion = AGFCurrency.round(currentLiabilityPortion + math.min(outstanding, scheduled))

                -- A maturity balloon is a next-12-month burden only when the
                -- remaining scheduled-payment count reaches maturity inside one
                -- annual payment cycle for that contract frequency.
                if remainingPayments ~= nil and remainingPayments <= paymentFrequency and (liability.balloonAmount or 0) > 0 then
                    local balloon = math.min(AGFCurrency.round(liability.balloonAmount), math.max(0, outstanding - scheduled))
                    annualDebtService = AGFCurrency.round(annualDebtService + balloon)
                    currentLiabilityPortion = AGFCurrency.round(currentLiabilityPortion + balloon)
                end
            elseif not liability:isRevolving() then
                addIssue(
                    profile,
                    AGFCreditDataQuality.INSUFFICIENT_HISTORY,
                    "NATIVE_DEBT_SERVICE_UNMODELED",
                    tostring(liability.id)
                )
            end

            -- Accrued interest and fees are known obligations and are included
            -- in the 12-period burden unless a future product explicitly defers them.
            local accrued = AGFCurrency.round((liability.accruedInterest or 0) + (liability.accruedFees or 0))
            annualDebtService = AGFCurrency.round(annualDebtService + accrued)
            currentLiabilityPortion = AGFCurrency.round(currentLiabilityPortion + accrued)
        end
    end

    return annualDebtService, currentLiabilityPortion
end

function AGFCreditProfileBuilder:build(farmId, context)
    context = context or {}
    local profile = AGFFarmCreditProfile.new(farmId)

    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        profile.asOfYear = g_currentMission.environment.currentYear
        profile.asOfPeriod = g_currentMission.environment.currentPeriod
    else
        profile.asOfYear = context.asOfYear
        profile.asOfPeriod = context.asOfPeriod
    end

    local nativeLiabilities = self.liabilityRegistry ~= nil and self.liabilityRegistry:getFarmLiabilities(farmId, false) or {}
    profile.nativeLiabilityCount = #nativeLiabilities

    local nativeDebt = 0
    local revolverPrincipal = 0
    local revolverLimit = 0
    local undrawnCommittedCredit = 0
    for _, liability in ipairs(nativeLiabilities) do
        nativeDebt = AGFCurrency.round(nativeDebt + liability:getOutstandingBalance())
        if liability:isRevolving() then
            revolverPrincipal = AGFCurrency.round(revolverPrincipal + (liability.principalBalance or 0))
            revolverLimit = AGFCurrency.round(revolverLimit + (liability.creditLimit or 0))
            if liability.status == AGFLiabilityStatus.ACTIVE then
                undrawnCommittedCredit = AGFCurrency.round(undrawnCommittedCredit + liability:getAvailableCredit())
            end
        end
    end

    local nativeAnnualDebtService, nativeCurrentLiability = estimateNativeDebtService(nativeLiabilities, profile)

    local externalTotals = {
        principalBalance = 0,
        annualDebtService = 0,
        annualFixedCharge = 0,
        verifiedCount = 0,
        partialCount = 0,
        estimatedCount = 0,
        unknownCount = 0
    }
    if self.externalRegistry ~= nil then
        externalTotals = self.externalRegistry:getFarmTotals(farmId)
        profile.externalObligationCount = externalTotals.verifiedCount + externalTotals.partialCount + externalTotals.estimatedCount + externalTotals.unknownCount
        if externalTotals.unknownCount > 0 then
            addIssue(profile, AGFCreditDataQuality.UNKNOWN_EXTERNAL_DEBT, "UNKNOWN_EXTERNAL_OBLIGATION", tostring(externalTotals.unknownCount))
        elseif externalTotals.partialCount > 0 or externalTotals.estimatedCount > 0 then
            addIssue(profile, AGFCreditDataQuality.PARTIAL_EXTERNAL_DEBT, "PARTIAL_EXTERNAL_OBLIGATION", tostring(externalTotals.partialCount + externalTotals.estimatedCount))
        end
    end

    local ownedRegisteredAssetValue = 0
    local securedDebtIds = {}
    local securedDebt = 0
    local collateralValue = 0
    local activeLienCount = 0
    local unresolvedAssetCount = 0

    if self.assetRegistry ~= nil and self.rightRegistry ~= nil then
        for _, asset in ipairs(self.assetRegistry:getAll()) do
            if asset:isActive() and self.rightRegistry:isOwnedByFarm(asset.id, farmId) then
                local value = math.max(0, AGFCurrency.round(asset.currentValue or 0))
                ownedRegisteredAssetValue = AGFCurrency.round(ownedRegisteredAssetValue + value)

                if asset.linkState == AGFAssetLinkState.UNRESOLVED or asset.linkState == AGFAssetLinkState.QUARANTINED then
                    unresolvedAssetCount = unresolvedAssetCount + 1
                end

                local assetLiens = self.lienRegistry ~= nil and self.lienRegistry:getAssetLiens(asset.id, false) or {}
                if #assetLiens > 0 then
                    collateralValue = AGFCurrency.round(collateralValue + value)
                    activeLienCount = activeLienCount + #assetLiens
                    for _, lien in ipairs(assetLiens) do
                        if not securedDebtIds[lien.liabilityId] then
                            local liability = self.liabilityRegistry ~= nil and self.liabilityRegistry:get(lien.liabilityId) or nil
                            if liability ~= nil then
                                securedDebt = AGFCurrency.round(securedDebt + liability:getOutstandingBalance())
                                securedDebtIds[lien.liabilityId] = true
                            else
                                addIssue(profile, AGFCreditDataQuality.ASSET_LINK_UNRESOLVED, "LIEN_LIABILITY_UNRESOLVED", tostring(lien.liabilityId))
                            end
                        end
                    end
                end
            end
        end
    end

    profile.activeLienCount = activeLienCount
    profile.unresolvedAssetCount = unresolvedAssetCount
    if unresolvedAssetCount > 0 then
        addIssue(profile, AGFCreditDataQuality.ASSET_LINK_UNRESOLVED, "UNRESOLVED_OWNED_ASSETS", tostring(unresolvedAssetCount))
    end

    local annualLeaseCharges = self.leaseRegistry ~= nil and self.leaseRegistry:getAnnualFixedCharges(farmId) or 0

    local cashAndLiquidAssets = AGFCurrency.round(context.cashAndLiquidAssets or context.cashBalance or 0)
    local otherOwnedAssets = AGFCurrency.round(context.otherOwnedAssetValue or 0)
    local totalAssets = AGFCurrency.round(cashAndLiquidAssets + ownedRegisteredAssetValue + otherOwnedAssets)
    local totalLiabilities = AGFCurrency.round(nativeDebt + (externalTotals.principalBalance or 0) + (context.otherLiabilities or 0))

    local currentAssets = AGFCurrency.round(context.currentAssets or cashAndLiquidAssets)
    local currentLiabilities = AGFCurrency.round(
        (context.otherCurrentLiabilities or 0)
        + nativeCurrentLiability
        + (context.externalCurrentLiabilities or 0)
    )

    local annualDebtService = AGFCurrency.round(nativeAnnualDebtService + (externalTotals.annualDebtService or 0) + (context.otherAnnualDebtService or 0))
    local annualFixedCharges = AGFCurrency.round(annualLeaseCharges + (externalTotals.annualFixedCharge or 0) + (context.otherAnnualFixedCharges or 0))

    local cashAvailableForDebtService = context.cashAvailableForDebtService
    local cashAvailableForFixedCharges = context.cashAvailableForFixedCharges or cashAvailableForDebtService
    if cashAvailableForDebtService == nil then
        addIssue(profile, AGFCreditDataQuality.INSUFFICIENT_HISTORY, "CASH_AVAILABLE_FOR_DEBT_SERVICE_MISSING", nil)
        cashAvailableForDebtService = 0
        cashAvailableForFixedCharges = 0
    end

    local next12MonthObligations = AGFCurrency.round(annualDebtService + annualFixedCharges + (context.otherNext12MonthObligations or 0))

    profile:setMetrics(AGFCreditMetrics.buildSnapshot({
        totalAssets = totalAssets,
        totalLiabilities = totalLiabilities,
        currentAssets = currentAssets,
        currentLiabilities = currentLiabilities,
        annualDebtService = annualDebtService,
        annualLeaseAndFixedCharges = annualFixedCharges,
        cashAvailableForDebtService = cashAvailableForDebtService,
        cashAvailableForFixedCharges = cashAvailableForFixedCharges,
        securedDebt = securedDebt,
        collateralValue = collateralValue,
        revolverPrincipal = revolverPrincipal,
        revolverLimit = revolverLimit,
        cashAndLiquidAssets = cashAndLiquidAssets,
        undrawnCommittedCredit = undrawnCommittedCredit,
        next12MonthObligations = next12MonthObligations
    }))

    profile:setMetadata("nativeDebt", nativeDebt)
    profile:setMetadata("externalDebt", externalTotals.principalBalance or 0)
    profile:setMetadata("ownedRegisteredAssetValue", ownedRegisteredAssetValue)
    profile:setMetadata("annualLeaseCharges", annualLeaseCharges)
    profile:setMetadata("undrawnCommittedCredit", undrawnCommittedCredit)

    return profile
end
