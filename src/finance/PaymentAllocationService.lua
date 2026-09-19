-- AgForward Financial Cooperative
-- Pure component allocation for liability payments. Ledger posting and balance
-- mutation remain the responsibility of coordinated financial operations.

AGFPaymentAllocationService = {}

AGFPaymentAllocationOrder = {
    FEES_INTEREST_PRINCIPAL = "feesInterestPrincipal",
    INTEREST_FEES_PRINCIPAL = "interestFeesPrincipal",
    PRINCIPAL_ONLY = "principalOnly"
}

local function normalizedAmount(value)
    return math.max(0, AGFCurrency.round(tonumber(value) or 0))
end

local function applyComponent(remaining, outstanding)
    local applied = math.min(remaining, outstanding)
    return AGFCurrency.round(applied), AGFCurrency.round(remaining - applied)
end

function AGFPaymentAllocationService.allocate(paymentAmount, balances, order)
    local payment = normalizedAmount(paymentAmount)
    if payment <= 0 then return false, "INVALID_PAYMENT_AMOUNT" end
    balances = balances or {}

    local principal = normalizedAmount(balances.principal)
    local interest = normalizedAmount(balances.interest)
    local fees = normalizedAmount(balances.fees)
    local totalOutstanding = AGFCurrency.round(principal + interest + fees)

    local selectedOrder = order or AGFPaymentAllocationOrder.FEES_INTEREST_PRINCIPAL
    local remaining = payment
    local appliedPrincipal = 0
    local appliedInterest = 0
    local appliedFees = 0

    if selectedOrder == AGFPaymentAllocationOrder.PRINCIPAL_ONLY then
        appliedPrincipal, remaining = applyComponent(remaining, principal)
    elseif selectedOrder == AGFPaymentAllocationOrder.INTEREST_FEES_PRINCIPAL then
        appliedInterest, remaining = applyComponent(remaining, interest)
        appliedFees, remaining = applyComponent(remaining, fees)
        appliedPrincipal, remaining = applyComponent(remaining, principal)
    elseif selectedOrder == AGFPaymentAllocationOrder.FEES_INTEREST_PRINCIPAL then
        appliedFees, remaining = applyComponent(remaining, fees)
        appliedInterest, remaining = applyComponent(remaining, interest)
        appliedPrincipal, remaining = applyComponent(remaining, principal)
    else
        return false, "UNKNOWN_PAYMENT_ALLOCATION_ORDER"
    end

    return true, {
        paymentAmount = payment,
        totalOutstandingBefore = totalOutstanding,
        appliedPrincipal = appliedPrincipal,
        appliedInterest = appliedInterest,
        appliedFees = appliedFees,
        unappliedAmount = remaining,
        principalAfter = AGFCurrency.round(principal - appliedPrincipal),
        interestAfter = AGFCurrency.round(interest - appliedInterest),
        feesAfter = AGFCurrency.round(fees - appliedFees),
        totalOutstandingAfter = AGFCurrency.round(totalOutstanding - appliedPrincipal - appliedInterest - appliedFees),
        order = selectedOrder
    }
end
