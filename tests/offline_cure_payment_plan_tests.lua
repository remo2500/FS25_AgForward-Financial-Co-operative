-- Offline delinquency cure-payment planning.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/finance/PaymentAllocationService.lua")
dofile("src/finance/LiabilityPaymentPlanService.lua")
dofile("src/delinquency/DelinquencyStateMachine.lua")
dofile("src/delinquency/CurePaymentPlanService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local loan = AGFLiability.new("AGF-LIAB-CURE-1", 1, AGFProductType.TERM_LOAN)
loan.status = AGFLiabilityStatus.DELINQUENT
loan.principalBalance = 10000
loan.accruedInterest = 500
loan.accruedFees = 100

local account = AGFDelinquencyStateMachine.newAccountState()
account.state = AGFDelinquencyState.DELINQUENT
account.missedPayments = 2
account.pastDueAmount = 5000
account.history = {{fromState = "pastDue", toState = "delinquent", reason = "missedPayment", year = 2026, period = 8}}

local partialOk, partial = AGFCurePaymentPlanService.build(
    loan, account, 3000, 2026, 9, {groupId = "GRP-CURE-PART"}
)
assertTrue(partialOk, "partial cure plan")
assertEqual(partial.cureApplied, 3000, "partial cure amount")
assertEqual(partial.regularPaymentPortion, 0, "no excess over arrears")
assertEqual(partial.delinquencyAfter.pastDueAmount, 2000, "remaining arrears")
assertEqual(partial.delinquencyAfter.state, AGFDelinquencyState.DELINQUENT, "partial cure retains state")
assertEqual(partial.delinquencyBefore.pastDueAmount, 5000, "source delinquency copy retained")
assertEqual(account.pastDueAmount, 5000, "source account not mutated")
assertEqual(partial.fsCashDelta, -3000, "partial cure cash delta")
assertEqual(partial.paymentPlan.appliedFees, 100, "fees first")
assertEqual(partial.paymentPlan.appliedInterest, 500, "interest second")
assertEqual(partial.paymentPlan.appliedPrincipal, 2400, "principal remainder")

local fullOk, full = AGFCurePaymentPlanService.build(
    loan, account, 5000, 2026, 9, {groupId = "GRP-CURE-FULL"}
)
assertTrue(fullOk, "full cure plan")
assertTrue(full.fullyCured, "arrears fully cured")
assertEqual(full.delinquencyAfter.pastDueAmount, 0, "no remaining arrears")
assertEqual(full.delinquencyAfter.state, AGFDelinquencyState.CURRENT, "state returns current")
assertEqual(full.delinquencyAfter.missedPayments, 0, "missed count reset")
assertEqual(full.recommendedLiabilityStatus, AGFLiabilityStatus.ACTIVE, "liability returns active")

local excessOk, excess = AGFCurePaymentPlanService.build(
    loan, account, 6000, 2026, 9, {}
)
assertTrue(excessOk, "payment can cure arrears and reduce current balance")
assertEqual(excess.cureApplied, 5000, "only arrears counted as cure")
assertEqual(excess.regularPaymentPortion, 1000, "remaining accepted payment is normal debt service")
assertTrue(excess.fullyCured, "excess payment still cures")

local tooMuchOk, tooMuchError = AGFCurePaymentPlanService.build(
    loan, account, 20000, 2026, 9, {}
)
assertEqual(tooMuchOk, false, "overpayment rejected")
assertEqual(tooMuchError, "CURE_PAYMENT_EXCEEDS_OUTSTANDING", "overpayment error")

local currentAccount = AGFDelinquencyStateMachine.newAccountState()
local noDueOk, noDueError = AGFCurePaymentPlanService.build(
    loan, currentAccount, 1000, 2026, 9, {}
)
assertEqual(noDueOk, false, "no-arrears cure rejected")
assertEqual(noDueError, "NO_PAST_DUE_BALANCE", "no-arrears error")

print("offline_cure_payment_plan_tests: PASS")
