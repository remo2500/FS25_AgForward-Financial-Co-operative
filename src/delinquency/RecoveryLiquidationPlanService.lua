-- AgForward Financial Cooperative
-- Pure collateral-recovery liquidation plan. Recovery is intentionally distinct
-- from a voluntary secured sale: insufficient proceeds may leave a deficiency
-- rather than requiring the borrower to contribute cash before disposition.

AGFRecoveryLiquidationPlanService = {}

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
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

function AGFRecoveryLiquidationPlanService.build(liability, delinquencyAccount, assetId, lienId, grossProceeds, recoveryCosts, context)
    context = context or {}
    if context.recoveryAuthorized ~= true then return false, "RECOVERY_AUTHORIZATION_REQUIRED" end
    if liability == nil or liability.id == nil then return false, "LIABILITY_REQUIRED" end
    if liability.isOpen ~= nil and not liability:isOpen() then return false, "LIABILITY_NOT_OPEN" end
    if delinquencyAccount == nil then return false, "DELINQUENCY_ACCOUNT_REQUIRED" end
    if delinquencyAccount.state ~= AGFDelinquencyState.RECOVERY then
        return false, "DELINQUENCY_NOT_IN_RECOVERY"
    end
    if assetId == nil or assetId == "" then return false, "RECOVERY_ASSET_REQUIRED" end
    if lienId == nil or lienId == "" then return false, "RECOVERY_LIEN_REQUIRED" end

    local gross = money(grossProceeds)
    local costs = money(recoveryCosts)
    if gross == nil then return false, "INVALID_RECOVERY_PROCEEDS" end
    if costs == nil then return false, "INVALID_RECOVERY_COSTS" end
    if AGFCurrency.toMinorUnits(costs) > AGFCurrency.toMinorUnits(gross) then
        return false, "RECOVERY_COSTS_EXCEED_PROCEEDS"
    end

    local principal = money(liability.principalBalance)
    local interest = money(liability.accruedInterest)
    local fees = money(liability.accruedFees)
    if principal == nil or interest == nil or fees == nil then return false, "INVALID_LIABILITY_BALANCE" end

    local outstanding = AGFCurrency.round(principal + interest + fees)
    if outstanding <= 0 then return false, "NO_OUTSTANDING_BALANCE" end

    local netLiquidationProceeds = AGFCurrency.round(gross - costs)
    local amountAppliedToDebt = AGFCurrency.round(math.min(netLiquidationProceeds, outstanding))
    local deficiency = AGFCurrency.round(outstanding - amountAppliedToDebt)
    local surplus = AGFCurrency.round(netLiquidationProceeds - amountAppliedToDebt)
    local groupId = context.groupId or "PENDING_RECOVERY_GROUP"

    local journalIntents = {
        {
            transactionType = AGFTransactionType.ASSET_SALE,
            amount = gross,
            farmId = liability.farmId,
            assetId = tostring(assetId),
            liabilityId = liability.id,
            groupId = groupId,
            economicRole = "recoveryDisposition"
        }
    }

    if costs > 0 then
        table.insert(journalIntents, {
            transactionType = AGFTransactionType.FINANCE_FEE,
            amount = -costs,
            farmId = liability.farmId,
            assetId = tostring(assetId),
            liabilityId = liability.id,
            fundingSource = AGFFundingSource.CASH,
            expenseCategory = AGFExpenseCategory.FINANCE_FEE,
            groupId = groupId,
            economicRole = "recoveryCost",
            metadata = {
                recoveryCost = true,
                taxTreatmentRequiresRuntimeProof = true
            }
        })
    end

    local paymentPlan = nil
    if amountAppliedToDebt > 0 then
        local paymentOk, paymentOrError = AGFLiabilityPaymentPlanService.plan(
            liability,
            amountAppliedToDebt,
            AGFPaymentAllocationOrder.FEES_INTEREST_PRINCIPAL,
            AGFFundingSource.CASH
        )
        if not paymentOk then return false, paymentOrError end
        paymentPlan = paymentOrError
        if not AGFCurrency.equals(paymentPlan.acceptedPayment, amountAppliedToDebt)
            or paymentPlan.unappliedAmount > 0 then
            return false, "RECOVERY_PAYMENT_DID_NOT_RECONCILE"
        end

        for _, intent in ipairs(paymentPlan.journalIntents) do
            local copied = copyIntent(intent)
            copied.farmId = liability.farmId
            copied.assetId = tostring(assetId)
            copied.groupId = groupId
            copied.lienId = tostring(lienId)
            copied.economicRole = "recoveryDebtApplication"
            table.insert(journalIntents, copied)
        end
    end

    local ledgerNet = 0
    for _, intent in ipairs(journalIntents) do
        ledgerNet = AGFCurrency.round(ledgerNet + (intent.amount or 0))
    end

    -- Sale proceeds are routed first through recovery costs and the debt. Only
    -- residual surplus reaches ordinary farm cash.
    if not AGFCurrency.equals(ledgerNet, surplus) then
        return false, "RECOVERY_LEDGER_RECONCILIATION_FAILED"
    end

    local recommendedLiabilityStatus = deficiency > 0
        and AGFLiabilityStatus.COLLECTIONS
        or AGFLiabilityStatus.CLOSED
    local recommendedDelinquencyState = deficiency > 0
        and AGFDelinquencyState.RECOVERY
        or AGFDelinquencyState.RESOLVED

    return true, {
        planType = "recoveryLiquidation",
        groupId = groupId,
        farmId = liability.farmId,
        liabilityId = liability.id,
        assetId = tostring(assetId),
        lienId = tostring(lienId),
        grossProceeds = gross,
        recoveryCosts = costs,
        netLiquidationProceeds = netLiquidationProceeds,
        outstandingBefore = outstanding,
        amountAppliedToDebt = amountAppliedToDebt,
        deficiency = deficiency,
        surplus = surplus,
        fsCashDelta = surplus,
        ledgerNet = ledgerNet,
        paymentPlan = paymentPlan,
        journalIntents = journalIntents,
        lienReleaseIntent = {
            lienId = tostring(lienId),
            assetId = tostring(assetId),
            liabilityId = liability.id,
            releaseBecauseCollateralDisposed = true
        },
        assetDispositionIntent = {
            assetId = tostring(assetId),
            markDisposed = true,
            releaseEconomicOwnerRight = true
        },
        liabilityOutcome = {
            outstandingAfter = deficiency,
            recommendedStatus = recommendedLiabilityStatus,
            fullySatisfied = AGFCurrency.equals(deficiency, 0)
        },
        delinquencyOutcome = {
            recommendedState = recommendedDelinquencyState,
            deficiencyRemaining = deficiency
        },
        prepaymentTreatment = "notAppliedToForcedRecovery",
        atomicEffects = {
            "authorizeRecovery",
            "disposeCollateral",
            "payRecoveryCosts",
            "applyNetProceedsToDebt",
            "releaseDisposedCollateralLien",
            "updateAssetAndRights",
            "updateLiabilityAndDelinquency",
            "postLedgerGroup",
            surplus > 0 and "creditBorrowerSurplusCash" or nil
        }
    }
end
