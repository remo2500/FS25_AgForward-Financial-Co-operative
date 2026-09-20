-- AgForward Financial Cooperative
-- Pure cure-payment planner for a delinquent native liability. It derives the
-- liability component payment and a copied delinquency-state result without
-- mutating either source object.

AGFCurePaymentPlanService = {}

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function cloneAccount(account)
    local copy = {
        state = account.state,
        missedPayments = math.max(0, math.floor(tonumber(account.missedPayments) or 0)),
        pastDueAmount = AGFCurrency.round(account.pastDueAmount or 0),
        lastTransitionYear = account.lastTransitionYear,
        lastTransitionPeriod = account.lastTransitionPeriod,
        history = {}
    }
    for _, row in ipairs(account.history or {}) do
        local historyRow = {}
        for key, value in pairs(row) do historyRow[key] = value end
        table.insert(copy.history, historyRow)
    end
    return copy
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

function AGFCurePaymentPlanService.build(liability, delinquencyAccount, requestedPayment, year, period, context)
    context = context or {}
    if liability == nil or liability.id == nil then return false, "LIABILITY_REQUIRED" end
    if liability.isOpen ~= nil and not liability:isOpen() then return false, "LIABILITY_NOT_OPEN" end
    if delinquencyAccount == nil then return false, "DELINQUENCY_ACCOUNT_REQUIRED" end

    local pastDue = money(delinquencyAccount.pastDueAmount)
    if pastDue == nil then return false, "INVALID_PAST_DUE_AMOUNT" end
    if pastDue <= 0 then return false, "NO_PAST_DUE_BALANCE" end

    local payment = money(requestedPayment)
    if payment == nil or payment <= 0 then return false, "INVALID_CURE_PAYMENT" end

    local paymentOk, paymentPlan = AGFLiabilityPaymentPlanService.plan(
        liability,
        payment,
        context.paymentAllocationOrder or AGFPaymentAllocationOrder.FEES_INTEREST_PRINCIPAL,
        AGFFundingSource.CASH
    )
    if not paymentOk then return false, paymentPlan end
    if paymentPlan.unappliedAmount > 0 then
        return false, "CURE_PAYMENT_EXCEEDS_OUTSTANDING"
    end

    local accountAfter = cloneAccount(delinquencyAccount)
    local cureOk, cureResult = AGFDelinquencyStateMachine.applyCurePayment(
        accountAfter,
        paymentPlan.acceptedPayment,
        year,
        period
    )
    if not cureOk then return false, cureResult end

    local cureApplied = AGFCurrency.round(cureResult.applied or 0)
    local regularPaymentPortion = AGFCurrency.round(cureResult.unappliedAmount or 0)
    local groupId = context.groupId or "PENDING_CURE_GROUP"
    local journalIntents = {}

    for _, intent in ipairs(paymentPlan.journalIntents) do
        local copied = copyIntent(intent)
        copied.farmId = liability.farmId
        copied.groupId = groupId
        copied.economicRole = "curePayment"
        table.insert(journalIntents, copied)
    end

    local ledgerNet = 0
    for _, intent in ipairs(journalIntents) do
        ledgerNet = AGFCurrency.round(ledgerNet + (intent.amount or 0))
    end
    if not AGFCurrency.equals(ledgerNet, -paymentPlan.acceptedPayment) then
        return false, "CURE_LEDGER_RECONCILIATION_FAILED"
    end

    return true, {
        planType = "curePayment",
        groupId = groupId,
        farmId = liability.farmId,
        liabilityId = liability.id,
        requestedPayment = payment,
        acceptedPayment = paymentPlan.acceptedPayment,
        fsCashDelta = -paymentPlan.acceptedPayment,
        ledgerNet = ledgerNet,
        paymentPlan = paymentPlan,
        journalIntents = journalIntents,
        delinquencyBefore = cloneAccount(delinquencyAccount),
        delinquencyAfter = accountAfter,
        cureApplied = cureApplied,
        regularPaymentPortion = regularPaymentPortion,
        fullyCured = AGFCurrency.equals(accountAfter.pastDueAmount, 0),
        recommendedLiabilityStatus = AGFCurrency.equals(accountAfter.pastDueAmount, 0)
            and AGFLiabilityStatus.ACTIVE
            or liability.status
    }
end
