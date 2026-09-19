-- AgForward Financial Cooperative
-- Pure payoff quote for one native liability. Separates principal, accrued
-- interest/fees, and any contractual prepayment charge.

AGFLiabilityPayoffQuoteService = {}

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

function AGFLiabilityPayoffQuoteService.quote(liability, prepaymentPolicy, context)
    context = context or {}
    if liability == nil or liability.id == nil then return false, "LIABILITY_REQUIRED" end

    local principal = money(liability.principalBalance)
    local interest = money(liability.accruedInterest)
    local fees = money(liability.accruedFees)
    if principal == nil or interest == nil or fees == nil then return false, "INVALID_LIABILITY_BALANCE" end

    local baseOutstanding = AGFCurrency.round(principal + interest + fees)
    if baseOutstanding <= 0 then return false, "NO_OUTSTANDING_BALANCE" end

    local prepayment = nil
    local prepaymentCharge = 0
    if principal > 0 then
        local policy = prepaymentPolicy or {type = AGFPrepaymentPolicyType.OPEN}
        local prepaymentOk, prepaymentOrError = AGFPrepaymentPolicyService.quote(
            principal,
            principal,
            policy,
            context
        )
        if not prepaymentOk then return false, prepaymentOrError end
        prepayment = prepaymentOrError
        if not AGFCurrency.equals(prepayment.acceptedPrincipal, principal)
            or not AGFCurrency.equals(prepayment.unappliedPrincipal, 0) then
            return false, "FULL_PRINCIPAL_PAYOFF_NOT_ACCEPTED"
        end
        prepaymentCharge = money(prepayment.prepaymentCharge)
        if prepaymentCharge == nil then return false, "INVALID_PREPAYMENT_CHARGE" end
    end

    local totalCashRequired = AGFCurrency.round(baseOutstanding + prepaymentCharge)
    return true, {
        liabilityId = liability.id,
        farmId = liability.farmId,
        productType = liability.productType,
        principal = principal,
        accruedInterest = interest,
        accruedFees = fees,
        baseOutstanding = baseOutstanding,
        prepayment = prepayment,
        prepaymentCharge = prepaymentCharge,
        totalCashRequired = totalCashRequired,
        atMaturity = context.atMaturity == true
    }
end
