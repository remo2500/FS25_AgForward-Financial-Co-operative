-- Offline Red Tape/native reconciliation expectation validation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/integrations/MoneyMovementIntent.lua")
dofile("src/integrations/RedTapeReconciliationExpectationService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local rows = {
    {id = "TX-1", transactionType = AGFTransactionType.CREDIT_DRAW, amount = 30000, fundingSource = AGFFundingSource.CROP_INPUT_LINE},
    {id = "TX-2", transactionType = AGFTransactionType.INPUT_PURCHASE, amount = -30000, expenseCategory = AGFExpenseCategory.FERTILIZER, fundingSource = AGFFundingSource.CROP_INPUT_LINE},
    {id = "TX-3", transactionType = AGFTransactionType.INTEREST_PAYMENT, amount = -500, expenseCategory = AGFExpenseCategory.INTEREST},
    {id = "TX-4", transactionType = AGFTransactionType.FINANCE_FEE, amount = -50, expenseCategory = AGFExpenseCategory.FINANCE_FEE},
    {id = "TX-5", transactionType = AGFTransactionType.GRANT_RECEIPT, amount = 10000},
    {id = "TX-6", transactionType = AGFTransactionType.PRINCIPAL_PAYMENT, amount = -2000},
    {id = "TX-7", transactionType = AGFTransactionType.LOAN_PAYMENT, amount = -2500}
}

local result = AGFRedTapeReconciliationExpectationService.build(rows)
assertEqual(result.transactionCount, 7, "transaction count")
assertEqual(result.mappedCount, 6, "mapped count")
assertEqual(result.unresolvedCount, 1, "unresolved combined payment")
assertEqual(result.unresolved[1].transactionType, AGFTransactionType.LOAN_PAYMENT, "unresolved transaction type")
assertTrue(result.blockingUnknownTransactionTypes, "unknown movement blocks automatic treatment")
assertEqual(result.safeToAutoInject, false, "service never authorizes auto injection")

assertEqual(result.byTreatment[AGFRedTapeTreatment.IGNORE_TAX].count, 2, "draw/principal ignored for tax")
assertEqual(result.byTreatment[AGFRedTapeTreatment.IGNORE_TAX].netAmount, 28000, "ignore-tax net movement")
assertEqual(result.byTreatment[AGFRedTapeTreatment.IGNORE_TAX].cashVolume, 32000, "ignore-tax cash volume")
assertEqual(result.byTreatment[AGFRedTapeTreatment.NATIVE_RECONCILE].count, 2, "input and interest reconcile natively")
assertEqual(result.byTreatment[AGFRedTapeTreatment.NATIVE_RECONCILE].netAmount, -30500, "native-reconcile net")
assertEqual(result.byTreatment[AGFRedTapeTreatment.SUPPLEMENT_IF_MISSING].count, 1, "fee supplement candidate")
assertEqual(result.byTreatment[AGFRedTapeTreatment.EXTERNAL_AUTHORITY].count, 1, "grant external authority")

assertEqual(#result.nativeReconcile, 2, "native reconcile rows")
assertEqual(#result.supplementIfMissing, 1, "supplement rows")
assertEqual(#result.ignoredForTax, 2, "ignore rows")
assertEqual(#result.externalAuthority, 1, "external authority rows")
assertEqual(result.byPreferredStatistic.bankLoanInterest.count, 1, "interest preferred statistic")
assertTrue(result.requiresRuntimeReconciliation, "runtime reconciliation still required")

local badDirection = AGFRedTapeReconciliationExpectationService.build({
    {id = "BAD", transactionType = AGFTransactionType.CREDIT_DRAW, amount = -100}
})
assertEqual(badDirection.rows[1].directionValid, false, "cash direction mismatch retained as evidence")
assertEqual(badDirection.rows[1].directionError, "CASH_DIRECTION_MISMATCH", "cash direction error")

print("offline_red_tape_reconciliation_tests: PASS")
