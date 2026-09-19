-- Offline validation for the pure liability payment posting plan.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/finance/PaymentAllocationService.lua")
dofile("src/finance/LiabilityPaymentPlanService.lua")

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

local liability = AGFLiability.new("AGF-LIAB-000100", 1, AGFProductType.EQUIPMENT_FINANCE)
liability.principalBalance = 10000
liability.accruedInterest = 500
liability.accruedFees = 100
liability.status = AGFLiabilityStatus.ACTIVE

-- Default ordering is fees -> interest -> principal and preserves component intent.
local planOk, plan = AGFLiabilityPaymentPlanService.plan(liability, 1000)
assertTrue(planOk, "default payment plan succeeds")
assertEqual(plan.requestedPayment, 1000, "requested payment")
assertEqual(plan.acceptedPayment, 1000, "accepted payment")
assertEqual(plan.appliedFees, 100, "fees applied first")
assertEqual(plan.appliedInterest, 500, "interest applied second")
assertEqual(plan.appliedPrincipal, 400, "principal receives remainder")
assertEqual(plan.feesAfter, 0, "fees cleared")
assertEqual(plan.interestAfter, 0, "interest cleared")
assertEqual(plan.principalAfter, 9600, "principal after partial payment")
assertEqual(plan.totalOutstandingAfter, 9600, "remaining total")
assertFalse(plan.fullyPaid, "partial payment not payoff")
assertEqual(#plan.journalIntents, 3, "three accounting intents")
assertEqual(plan.journalIntents[1].transactionType, AGFTransactionType.FINANCE_FEE, "fee intent first")
assertEqual(plan.journalIntents[1].amount, -100, "fee cash amount")
assertEqual(plan.journalIntents[1].fees, 100, "fee breakdown")
assertEqual(plan.journalIntents[1].expenseCategory, AGFExpenseCategory.FINANCE_FEE, "fee expense category")
assertEqual(plan.journalIntents[2].transactionType, AGFTransactionType.INTEREST_PAYMENT, "interest intent second")
assertEqual(plan.journalIntents[2].interest, 500, "interest breakdown")
assertEqual(plan.journalIntents[2].expenseCategory, AGFExpenseCategory.INTEREST, "interest expense category")
assertEqual(plan.journalIntents[3].transactionType, AGFTransactionType.PRINCIPAL_PAYMENT, "principal intent third")
assertEqual(plan.journalIntents[3].principal, 400, "principal breakdown")
assertEqual(plan.journalIntents[3].expenseCategory, nil, "principal is not an expense category")

-- Planning is pure; the liability is unchanged.
assertEqual(liability.principalBalance, 10000, "planning does not mutate principal")
assertEqual(liability.accruedInterest, 500, "planning does not mutate interest")
assertEqual(liability.accruedFees, 100, "planning does not mutate fees")

-- Overpayment accepts only the exact payoff and leaves an explicit unapplied amount.
local payoffOk, payoff = AGFLiabilityPaymentPlanService.plan(liability, 12000)
assertTrue(payoffOk, "overpayment payoff plan succeeds")
assertEqual(payoff.acceptedPayment, 10600, "accepted amount capped at payoff")
assertEqual(payoff.unappliedAmount, 1400, "excess remains unapplied")
assertEqual(payoff.totalOutstandingAfter, 0, "payoff clears represented debt")
assertTrue(payoff.fullyPaid, "payoff marked fully paid")
assertEqual(#payoff.journalIntents, 3, "payoff component intents")
local payoffJournalTotal = 0
for _, intent in ipairs(payoff.journalIntents) do payoffJournalTotal = AGFCurrency.round(payoffJournalTotal + intent.amount) end
assertEqual(payoffJournalTotal, -10600, "journal intents never debit the unapplied excess")

-- Alternative allocation order remains explicit contract policy.
local interestFirstOk, interestFirst = AGFLiabilityPaymentPlanService.plan(
    liability,
    550,
    AGFPaymentAllocationOrder.INTEREST_FEES_PRINCIPAL
)
assertTrue(interestFirstOk, "interest-first payment plan succeeds")
assertEqual(interestFirst.appliedInterest, 500, "interest-first interest")
assertEqual(interestFirst.appliedFees, 50, "interest-first fees")
assertEqual(interestFirst.appliedPrincipal, 0, "interest-first no principal")
assertEqual(#interestFirst.journalIntents, 2, "zero principal creates no principal intent")
assertEqual(interestFirst.journalIntents[1].transactionType, AGFTransactionType.FINANCE_FEE, "journal ordering remains canonical fee/interest")
assertEqual(interestFirst.journalIntents[2].transactionType, AGFTransactionType.INTEREST_PAYMENT, "journal interest intent present")

local principalOnlyOk, principalOnly = AGFLiabilityPaymentPlanService.plan(
    liability,
    2500,
    AGFPaymentAllocationOrder.PRINCIPAL_ONLY
)
assertTrue(principalOnlyOk, "principal-only plan succeeds")
assertEqual(principalOnly.appliedPrincipal, 2500, "principal-only applied")
assertEqual(principalOnly.appliedInterest, 0, "principal-only leaves interest")
assertEqual(principalOnly.appliedFees, 0, "principal-only leaves fees")
assertEqual(principalOnly.interestAfter, 500, "principal-only accrued interest retained")
assertEqual(principalOnly.feesAfter, 100, "principal-only accrued fees retained")
assertEqual(#principalOnly.journalIntents, 1, "principal-only one intent")

-- Funding source is descriptive and can later distinguish settlement cash/credit.
local fundedOk, funded = AGFLiabilityPaymentPlanService.plan(
    liability,
    100,
    AGFPaymentAllocationOrder.FEES_INTEREST_PRINCIPAL,
    AGFFundingSource.OPERATING_LINE
)
assertTrue(fundedOk, "funded payment plan succeeds")
assertEqual(funded.fundingSource, AGFFundingSource.OPERATING_LINE, "payment funding source")
assertEqual(funded.journalIntents[1].fundingSource, AGFFundingSource.OPERATING_LINE, "intent funding source")

-- Closed/empty/invalid payments fail without producing intents.
liability.status = AGFLiabilityStatus.CLOSED
local closedOk, closedError = AGFLiabilityPaymentPlanService.plan(liability, 100)
assertFalse(closedOk, "closed liability rejected")
assertEqual(closedError, "LIABILITY_NOT_OPEN", "closed liability error")
liability.status = AGFLiabilityStatus.ACTIVE

local zeroPaymentOk, zeroPaymentError = AGFLiabilityPaymentPlanService.plan(liability, 0)
assertFalse(zeroPaymentOk, "zero payment rejected")
assertEqual(zeroPaymentError, "INVALID_PAYMENT_AMOUNT", "zero payment error")

local empty = AGFLiability.new("AGF-LIAB-000101", 1, AGFProductType.TERM_LOAN)
local emptyOk, emptyError = AGFLiabilityPaymentPlanService.plan(empty, 100)
assertFalse(emptyOk, "zero-balance liability rejected")
assertEqual(emptyError, "NO_OUTSTANDING_BALANCE", "zero-balance error")

local invalidOk, invalidError = AGFLiabilityPaymentPlanService.plan(nil, 100)
assertFalse(invalidOk, "nil liability rejected")
assertEqual(invalidError, "INVALID_LIABILITY", "nil liability error")

print("offline_payment_plan_tests: PASS")
