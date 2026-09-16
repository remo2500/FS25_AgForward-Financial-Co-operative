-- AgForward Financial Cooperative
-- Pure prepayment policy model. Policy values are contract inputs; this service
-- does not embed production penalty rates or move money.

AGFPrepaymentPolicyType = {
    OPEN = "open",
    ANNUAL_ALLOWANCE = "annualAllowance",
    CLOSED = "closed",
    NONE = "none"
}

AGFPrepaymentPolicyService = {}

local function normalizeMoney(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function normalizeRate(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    if number < 0 then return nil end
    return number
end

local function calculateAllowance(policy)
    if policy.annualAllowanceAmount ~= nil then
        local amount = normalizeMoney(policy.annualAllowanceAmount)
        if amount == nil then return nil, "INVALID_ANNUAL_ALLOWANCE_AMOUNT" end
        return amount, nil
    end

    if policy.annualAllowancePercent ~= nil then
        local percent = normalizeRate(policy.annualAllowancePercent)
        if percent == nil or percent > 1 then return nil, "INVALID_ANNUAL_ALLOWANCE_PERCENT" end
        local base = normalizeMoney(policy.allowanceBase)
        if base == nil or base <= 0 then return nil, "INVALID_ALLOWANCE_BASE" end
        return AGFCurrency.round(base * percent), nil
    end

    return nil, "ANNUAL_ALLOWANCE_NOT_DEFINED"
end

function AGFPrepaymentPolicyService.quote(principalBalance, requestedPrincipal, policy, context)
    policy = policy or {}
    context = context or {}

    local principal = normalizeMoney(principalBalance)
    if principal == nil then return false, "INVALID_PRINCIPAL_BALANCE" end
    if principal <= 0 then return false, "NO_OUTSTANDING_PRINCIPAL" end

    local requested = normalizeMoney(requestedPrincipal)
    if requested == nil or requested <= 0 then return false, "INVALID_PREPAYMENT_AMOUNT" end

    local policyType = policy.type or AGFPrepaymentPolicyType.OPEN
    local accepted = AGFCurrency.round(math.min(requested, principal))
    local unapplied = AGFCurrency.round(requested - accepted)

    -- Once contractual maturity is reached this is a normal payoff, not an
    -- early-prepayment restriction. Any separate maturity/payoff fee belongs in
    -- the payoff contract, not the early-prepayment allowance.
    if context.atMaturity == true then
        return true, {
            policyType = policyType,
            principalBalance = principal,
            requestedPrincipal = requested,
            acceptedPrincipal = accepted,
            unappliedPrincipal = unapplied,
            freePrincipal = accepted,
            chargeablePrincipal = 0,
            remainingAnnualAllowanceBefore = nil,
            remainingAnnualAllowanceAfter = nil,
            prepaymentCharge = 0,
            totalCashRequired = accepted,
            atMaturity = true
        }
    end

    local freePrincipal = 0
    local chargeablePrincipal = 0
    local allowanceBefore = nil
    local allowanceAfter = nil

    if policyType == AGFPrepaymentPolicyType.OPEN then
        freePrincipal = accepted
    elseif policyType == AGFPrepaymentPolicyType.ANNUAL_ALLOWANCE then
        local allowance, allowanceError = calculateAllowance(policy)
        if allowance == nil then return false, allowanceError end
        local alreadyPrepaid = normalizeMoney(context.alreadyPrepaidThisYear or 0)
        if alreadyPrepaid == nil then return false, "INVALID_ALREADY_PREPAID_AMOUNT" end

        allowanceBefore = math.max(0, AGFCurrency.round(allowance - alreadyPrepaid))
        freePrincipal = AGFCurrency.round(math.min(accepted, allowanceBefore))
        chargeablePrincipal = AGFCurrency.round(accepted - freePrincipal)
        allowanceAfter = math.max(0, AGFCurrency.round(allowanceBefore - freePrincipal))
    elseif policyType == AGFPrepaymentPolicyType.CLOSED then
        chargeablePrincipal = accepted
    elseif policyType == AGFPrepaymentPolicyType.NONE then
        return false, "PREPAYMENT_NOT_ALLOWED"
    else
        return false, "UNKNOWN_PREPAYMENT_POLICY"
    end

    local chargeRate = normalizeRate(policy.excessChargeRate or policy.chargeRate or 0)
    if chargeRate == nil then return false, "INVALID_PREPAYMENT_CHARGE_RATE" end
    local fixedCharge = normalizeMoney(policy.fixedCharge or 0)
    if fixedCharge == nil then return false, "INVALID_PREPAYMENT_FIXED_CHARGE" end

    local prepaymentCharge = 0
    if chargeablePrincipal > 0 then
        prepaymentCharge = AGFCurrency.round(chargeablePrincipal * chargeRate + fixedCharge)
    end

    return true, {
        policyType = policyType,
        principalBalance = principal,
        requestedPrincipal = requested,
        acceptedPrincipal = accepted,
        unappliedPrincipal = unapplied,
        freePrincipal = freePrincipal,
        chargeablePrincipal = chargeablePrincipal,
        remainingAnnualAllowanceBefore = allowanceBefore,
        remainingAnnualAllowanceAfter = allowanceAfter,
        prepaymentCharge = prepaymentCharge,
        totalCashRequired = AGFCurrency.round(accepted + prepaymentCharge),
        atMaturity = false
    }
end
