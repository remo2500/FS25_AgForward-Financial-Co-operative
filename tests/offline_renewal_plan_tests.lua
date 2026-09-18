-- Offline rate-term renewal amendment-plan validation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/RateTermRenewalService.lua")
dofile("src/finance/StructuredAmortizationService.lua")
dofile("src/finance/LoanQuoteService.lua")
dofile("src/finance/PaymentFrequencyService.lua")
dofile("src/finance/LoanContractScheduleService.lua")
dofile("src/finance/LoanRenewalQuoteService.lua")
dofile("src/finance/LoanRenewalPlanService.lua")

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

local quoteOk, original = AGFLoanQuoteService.quote({
    principal = 500000,
    periods = 20,
    paymentsPerYear = 1,
    rateTermPeriods = 5,
    rateComponents = {baseRate = 0.05}
})
assertTrue(quoteOk, "original rate-term quote succeeds")

local scheduleOk, schedule = AGFLoanContractScheduleService.build(original, 2026, 9)
assertTrue(scheduleOk, "original contract schedule succeeds")
assertEqual(schedule.rateRenewalDueYear, 2031, "renewal year")
assertEqual(schedule.rateRenewalDuePeriod, 9, "renewal period")

local renewalOk, renewal = AGFLoanRenewalQuoteService.quote(original, {baseRate = 0.06}, {
    paymentsPerYear = 1,
    rateTermPeriods = 5
})
assertTrue(renewalOk, "renewal quote succeeds")

local liability = {
    id = "AGF-LIAB-RENEW-1",
    farmId = 1,
    productType = AGFProductType.LAND_FINANCE,
    status = "active",
    principalBalance = 450000,
    assetId = "AGF-ASSET-LAND-1",
    isRevolving = function() return false end
}
local decision = {status = "approve", conditions = {}, referrals = {}, policyName = "test", policyVersion = 1}

local earlyOk, earlyError = AGFLoanRenewalPlanService.build(liability, schedule, renewal, decision, 2029, 9, {
    reviewWindowPeriods = 12
})
assertFalse(earlyOk, "renewal too early rejected")
assertEqual(earlyError, "RENEWAL_WINDOW_NOT_OPEN", "early-renewal error")

local advanceOk, advance = AGFLoanRenewalPlanService.build(liability, schedule, renewal, decision, 2030, 9, {
    reviewWindowPeriods = 12
})
assertTrue(advanceOk, "advance renewal review succeeds")
assertEqual(advance.periodsUntilRenewal, 12, "advance renewal distance")
assertTrue(advance.requiresRequoteAtRenewal, "future renewal must be requoted against actual balance")
assertEqual(advance.cashDelta, 0, "rate renewal has no cash advance")
assertEqual(advance.createsNewLiability, false, "rate renewal preserves liability identity")
assertTrue(advance.preservesExistingSecurity, "rate renewal preserves security")

liability.principalBalance = renewal.renewalPrincipal
local dueOk, due = AGFLoanRenewalPlanService.build(liability, schedule, renewal, decision, 2031, 9, {
    reviewWindowPeriods = 12
})
assertTrue(dueOk, "renewal due-now plan succeeds")
assertEqual(due.periodsUntilRenewal, 0, "renewal due now")
assertEqual(due.liabilityAmendment.interestRate, renewal.renewedAnnualRate, "new rate")
assertEqual(due.liabilityAmendment.scheduledPayment, renewal.renewedRegularPayment, "new payment")
assertEqual(due.liabilityAmendment.nextPaymentYear, 2032, "renewed first payment year")
assertEqual(due.liabilityAmendment.nextPaymentPeriod, 9, "renewed first payment period")
assertEqual(#due.ledgerIntents, 0, "rate renewal posts no proceeds/payment by itself")

liability.principalBalance = AGFCurrency.round(renewal.renewalPrincipal - 1000)
local mismatchOk, mismatchError = AGFLoanRenewalPlanService.build(liability, schedule, renewal, decision, 2031, 9, {})
assertFalse(mismatchOk, "material actual-balance variance requires requote")
assertEqual(mismatchError, "RENEWAL_PRINCIPAL_CHANGED_REQUOTE_REQUIRED", "principal variance error")

liability.principalBalance = renewal.renewalPrincipal
local referDecision = {status = "refer", conditions = {}, referrals = {{id = "manual"}}}
local referOk, referError = AGFLoanRenewalPlanService.build(liability, schedule, renewal, referDecision, 2031, 9, {})
assertFalse(referOk, "unapproved referral cannot renew")
assertEqual(referError, "MANUAL_APPROVAL_REQUIRED", "manual approval error")

local manualOk = AGFLoanRenewalPlanService.build(liability, schedule, renewal, referDecision, 2031, 9, {manualApproval = true})
assertTrue(manualOk, "manual approval permits referred renewal")

print("offline_renewal_plan_tests: PASS")
