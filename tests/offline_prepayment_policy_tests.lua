-- Offline validation for contract-driven early-prepayment policy.

dofile("src/core/Currency.lua")
dofile("src/finance/PrepaymentPolicyService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local function assertFalse(value, message)
    if value ~= false then error(message or "expected false") end
end

-- Open loans permit early principal reduction without a charge.
local openOk, openQuote = AGFPrepaymentPolicyService.quote(100000, 25000, {
    type = AGFPrepaymentPolicyType.OPEN
})
assertTrue(openOk, "open prepayment quote succeeds")
assertEqual(openQuote.acceptedPrincipal, 25000, "open accepted principal")
assertEqual(openQuote.freePrincipal, 25000, "open free principal")
assertEqual(openQuote.chargeablePrincipal, 0, "open chargeable principal")
assertEqual(openQuote.prepaymentCharge, 0, "open prepayment charge")
assertEqual(openQuote.totalCashRequired, 25000, "open cash required")

-- Overpayment clips to the outstanding principal and exposes the excess rather than consuming it.
local clipOk, clipped = AGFPrepaymentPolicyService.quote(10000, 15000, {
    type = AGFPrepaymentPolicyType.OPEN
})
assertTrue(clipOk, "over-request quote succeeds")
assertEqual(clipped.acceptedPrincipal, 10000, "over-request clips to principal")
assertEqual(clipped.unappliedPrincipal, 5000, "over-request excess returned")
assertEqual(clipped.totalCashRequired, 10000, "over-request cash excludes excess")

-- Annual allowance: 10% of a $100k allowance base, with $3k already used.
-- A $12k prepayment has $7k free and $5k chargeable. 2% of $5k + $50 = $150.
local allowanceOk, allowance = AGFPrepaymentPolicyService.quote(80000, 12000, {
    type = AGFPrepaymentPolicyType.ANNUAL_ALLOWANCE,
    annualAllowancePercent = 0.10,
    allowanceBase = 100000,
    excessChargeRate = 0.02,
    fixedCharge = 50
}, {
    alreadyPrepaidThisYear = 3000
})
assertTrue(allowanceOk, "annual allowance quote succeeds")
assertEqual(allowance.remainingAnnualAllowanceBefore, 7000, "remaining allowance before")
assertEqual(allowance.freePrincipal, 7000, "allowance free principal")
assertEqual(allowance.chargeablePrincipal, 5000, "allowance chargeable principal")
assertEqual(allowance.remainingAnnualAllowanceAfter, 0, "allowance exhausted")
assertEqual(allowance.prepaymentCharge, 150, "allowance excess charge")
assertEqual(allowance.totalCashRequired, 12150, "allowance total cash")

-- A fixed-dollar annual allowance is also supported and unused allowance carries only within the caller's annual context.
local fixedAllowanceOk, fixedAllowance = AGFPrepaymentPolicyService.quote(50000, 4000, {
    type = AGFPrepaymentPolicyType.ANNUAL_ALLOWANCE,
    annualAllowanceAmount = 5000,
    excessChargeRate = 0.03
}, {
    alreadyPrepaidThisYear = 1500
})
assertTrue(fixedAllowanceOk, "fixed annual allowance quote succeeds")
assertEqual(fixedAllowance.remainingAnnualAllowanceBefore, 3500, "fixed allowance remaining")
assertEqual(fixedAllowance.freePrincipal, 3500, "fixed allowance free amount")
assertEqual(fixedAllowance.chargeablePrincipal, 500, "fixed allowance excess")
assertEqual(fixedAllowance.prepaymentCharge, 15, "fixed allowance excess charge")

-- Closed structures can charge the entire early principal amount, using contract-supplied parameters.
local closedOk, closed = AGFPrepaymentPolicyService.quote(50000, 5000, {
    type = AGFPrepaymentPolicyType.CLOSED,
    chargeRate = 0.01
})
assertTrue(closedOk, "closed prepayment quote succeeds")
assertEqual(closed.freePrincipal, 0, "closed no free principal")
assertEqual(closed.chargeablePrincipal, 5000, "closed chargeable principal")
assertEqual(closed.prepaymentCharge, 50, "closed charge")
assertEqual(closed.totalCashRequired, 5050, "closed total cash")

-- A contract that prohibits early prepayment fails closed.
local noneOk, noneError = AGFPrepaymentPolicyService.quote(50000, 1000, {
    type = AGFPrepaymentPolicyType.NONE
})
assertFalse(noneOk, "no-prepayment contract rejects early principal")
assertEqual(noneError, "PREPAYMENT_NOT_ALLOWED", "no-prepayment error")

-- Maturity is not early prepayment; it bypasses the early-prepayment restriction/charge.
local maturityOk, maturity = AGFPrepaymentPolicyService.quote(50000, 60000, {
    type = AGFPrepaymentPolicyType.NONE,
    chargeRate = 0.10,
    fixedCharge = 1000
}, {
    atMaturity = true
})
assertTrue(maturityOk, "maturity payoff permitted")
assertEqual(maturity.acceptedPrincipal, 50000, "maturity accepts outstanding principal")
assertEqual(maturity.unappliedPrincipal, 10000, "maturity excess unapplied")
assertEqual(maturity.prepaymentCharge, 0, "early-prepayment charge absent at maturity")
assertEqual(maturity.totalCashRequired, 50000, "maturity principal cash")
assertTrue(maturity.atMaturity, "maturity flag")

-- Missing/invalid policy inputs are explicit errors rather than silent defaults.
local missingAllowanceOk, missingAllowanceError = AGFPrepaymentPolicyService.quote(50000, 1000, {
    type = AGFPrepaymentPolicyType.ANNUAL_ALLOWANCE
})
assertFalse(missingAllowanceOk, "missing annual allowance rejected")
assertEqual(missingAllowanceError, "ANNUAL_ALLOWANCE_NOT_DEFINED", "missing allowance error")

local badPercentOk, badPercentError = AGFPrepaymentPolicyService.quote(50000, 1000, {
    type = AGFPrepaymentPolicyType.ANNUAL_ALLOWANCE,
    annualAllowancePercent = 1.1,
    allowanceBase = 50000
})
assertFalse(badPercentOk, "allowance percent above 100% rejected")
assertEqual(badPercentError, "INVALID_ANNUAL_ALLOWANCE_PERCENT", "bad allowance percent error")

local noBaseOk, noBaseError = AGFPrepaymentPolicyService.quote(50000, 1000, {
    type = AGFPrepaymentPolicyType.ANNUAL_ALLOWANCE,
    annualAllowancePercent = 0.10
})
assertFalse(noBaseOk, "percentage allowance requires base")
assertEqual(noBaseError, "INVALID_ALLOWANCE_BASE", "missing allowance base error")

local badRateOk, badRateError = AGFPrepaymentPolicyService.quote(50000, 1000, {
    type = AGFPrepaymentPolicyType.CLOSED,
    chargeRate = -0.01
})
assertFalse(badRateOk, "negative charge rate rejected")
assertEqual(badRateError, "INVALID_PREPAYMENT_CHARGE_RATE", "negative charge rate error")

local unknownOk, unknownError = AGFPrepaymentPolicyService.quote(50000, 1000, {
    type = "futureMysteryPolicy"
})
assertFalse(unknownOk, "unknown policy rejected")
assertEqual(unknownError, "UNKNOWN_PREPAYMENT_POLICY", "unknown policy error")

local zeroPrincipalOk, zeroPrincipalError = AGFPrepaymentPolicyService.quote(0, 1000, {
    type = AGFPrepaymentPolicyType.OPEN
})
assertFalse(zeroPrincipalOk, "zero principal rejected")
assertEqual(zeroPrincipalError, "NO_OUTSTANDING_PRINCIPAL", "zero principal error")

local zeroPaymentOk, zeroPaymentError = AGFPrepaymentPolicyService.quote(50000, 0, {
    type = AGFPrepaymentPolicyType.OPEN
})
assertFalse(zeroPaymentOk, "zero prepayment rejected")
assertEqual(zeroPaymentError, "INVALID_PREPAYMENT_AMOUNT", "zero prepayment error")

print("offline_prepayment_policy_tests: PASS")
