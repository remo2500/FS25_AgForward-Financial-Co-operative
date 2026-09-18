-- AgForward Financial Cooperative
-- Pure atomic sale/disposition planner for an asset with native AgForward liens.
-- It requires explicit payoff-policy inputs and performs no FS sale, cash, lien,
-- liability, right, or ledger mutation.

AGFSecuredDispositionExecutionPlanService = {}

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    return AGFCurrency.round(number)
end

local function copyIntent(intent)
    local copy = {}
    for key, value in pairs(intent or {}) do
        if type(value) == "table" then
            local child = {}
            for childKey, childValue in pairs(value) do child[childKey] = childValue end
            copy[key] = child
        else
            copy[key] = value
        end
    end
    return copy
end

function AGFSecuredDispositionExecutionPlanService.build(preflight, liabilitiesById, prepaymentPoliciesByLiabilityId, context)
    context = context or {}
    if preflight == nil or preflight.assetId == nil then return false, "DISPOSITION_PREFLIGHT_REQUIRED" end
    if preflight.allowed ~= true then return false, preflight.denialReason or "DISPOSITION_NOT_ALLOWED" end

    local grossProceeds = money(preflight.grossProceeds)
    local availableCash = money(preflight.availableCash)
    if grossProceeds == nil or grossProceeds < 0 or availableCash == nil or availableCash < 0 then
        return false, "INVALID_DISPOSITION_AMOUNTS"
    end

    local groupId = context.groupId or "PENDING_DISPOSITION_GROUP"
    local journalIntents = {
        {
            transactionType = AGFTransactionType.ASSET_SALE,
            amount = grossProceeds,
            farmId = context.farmId,
            assetId = preflight.assetId,
            groupId = groupId,
            economicRole = "assetDisposition"
        }
    }

    local liabilityPayoffPlans = {}
    local lienReleaseIntents = {}
    local totalPayoffCash = 0

    for _, lienRow in ipairs(preflight.lienBreakdown or {}) do
        local liability = liabilitiesById ~= nil and liabilitiesById[tostring(lienRow.liabilityId)] or nil
        if liability == nil then
            return false, "DISPOSITION_LIABILITY_REQUIRED:" .. tostring(lienRow.liabilityId)
        end

        local fullOutstanding = money(liability.getOutstandingBalance ~= nil
            and liability:getOutstandingBalance()
            or ((liability.principalBalance or 0) + (liability.accruedInterest or 0) + (liability.accruedFees or 0)))
        local preflightPayoff = money(lienRow.payoff)
        if fullOutstanding == nil or preflightPayoff == nil then return false, "INVALID_LIEN_PAYOFF" end

        -- A capped secured claim that is smaller than the full obligation can
        -- leave unsecured/residual debt. Release mechanics and partial-prepay
        -- charges are contract-specific, so do not guess.
        if AGFCurrency.toMinorUnits(preflightPayoff) < AGFCurrency.toMinorUnits(fullOutstanding) then
            return false, "CAPPED_LIEN_DISPOSITION_POLICY_REQUIRED:" .. tostring(lienRow.lienId)
        end

        local policy = prepaymentPoliciesByLiabilityId ~= nil
            and prepaymentPoliciesByLiabilityId[tostring(liability.id)]
            or nil
        if policy == nil and context.assumeOpenPrepayment ~= true then
            return false, "PREPAYMENT_POLICY_REQUIRED:" .. tostring(liability.id)
        end
        if policy == nil then policy = {type = AGFPrepaymentPolicyType.OPEN} end

        local quoteContext = {}
        for key, value in pairs(context.payoffContext or {}) do quoteContext[key] = value end
        local payoffOk, payoffQuote = AGFLiabilityPayoffQuoteService.quote(liability, policy, quoteContext)
        if not payoffOk then return false, payoffQuote end

        local paymentOk, paymentPlan = AGFLiabilityPaymentPlanService.plan(
            liability,
            payoffQuote.baseOutstanding,
            AGFPaymentAllocationOrder.FEES_INTEREST_PRINCIPAL,
            AGFFundingSource.CASH
        )
        if not paymentOk then return false, paymentPlan end
        if not paymentPlan.fullyPaid or paymentPlan.unappliedAmount > 0 then
            return false, "DISPOSITION_BASE_PAYOFF_DID_NOT_CLEAR_LIABILITY:" .. tostring(liability.id)
        end

        for _, intent in ipairs(paymentPlan.journalIntents) do
            local copied = copyIntent(intent)
            copied.farmId = liability.farmId
            copied.assetId = preflight.assetId
            copied.groupId = groupId
            copied.lienId = lienRow.lienId
            table.insert(journalIntents, copied)
        end

        if payoffQuote.prepaymentCharge > 0 then
            table.insert(journalIntents, {
                transactionType = AGFTransactionType.FINANCE_FEE,
                amount = -payoffQuote.prepaymentCharge,
                farmId = liability.farmId,
                liabilityId = liability.id,
                assetId = preflight.assetId,
                fundingSource = AGFFundingSource.CASH,
                expenseCategory = AGFExpenseCategory.FINANCE_FEE,
                groupId = groupId,
                lienId = lienRow.lienId,
                economicRole = "prepaymentCharge"
            })
        end

        totalPayoffCash = AGFCurrency.round(totalPayoffCash + payoffQuote.totalCashRequired)
        table.insert(liabilityPayoffPlans, {
            lienId = lienRow.lienId,
            liabilityId = liability.id,
            priority = lienRow.priority,
            payoffQuote = payoffQuote,
            paymentPlan = paymentPlan
        })
        table.insert(lienReleaseIntents, {
            lienId = lienRow.lienId,
            liabilityId = liability.id,
            assetId = preflight.assetId,
            releaseAfterFullPayoff = true
        })
    end

    local netCashDelta = AGFCurrency.round(grossProceeds - totalPayoffCash)
    local requiredCashContribution = netCashDelta < 0 and AGFCurrency.round(-netCashDelta) or 0
    local netCashToOwner = netCashDelta > 0 and netCashDelta or 0
    if AGFCurrency.toMinorUnits(requiredCashContribution) > AGFCurrency.toMinorUnits(availableCash) then
        return false, "INSUFFICIENT_CASH_TO_CLEAR_PAYOFF_AND_CHARGES"
    end

    local ledgerNet = 0
    for _, intent in ipairs(journalIntents) do
        ledgerNet = AGFCurrency.round(ledgerNet + (intent.amount or 0))
    end
    if not AGFCurrency.equals(ledgerNet, netCashDelta) then
        return false, "DISPOSITION_LEDGER_RECONCILIATION_FAILED"
    end

    return true, {
        planType = "securedAssetDisposition",
        groupId = groupId,
        farmId = context.farmId,
        assetId = preflight.assetId,
        grossProceeds = grossProceeds,
        totalPayoffCash = totalPayoffCash,
        requiredCashContribution = requiredCashContribution,
        netCashToOwner = netCashToOwner,
        fsCashDelta = netCashDelta,
        ledgerNet = ledgerNet,
        journalIntents = journalIntents,
        liabilityPayoffPlans = liabilityPayoffPlans,
        lienReleaseIntents = lienReleaseIntents,
        assetDispositionIntent = {
            assetId = preflight.assetId,
            markDisposed = true,
            releaseEconomicOwnerRight = true
        },
        atomicEffects = {
            "sellAsset",
            "moveFSCash",
            "applyLiabilityPayoffs",
            "postPrepaymentCharges",
            "releaseLiens",
            "updateAssetAndRights",
            "postLedgerGroup"
        }
    }
end
