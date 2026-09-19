-- Offline collateral recovery liquidation planning.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/finance/PaymentAllocationService.lua")
dofile("src/finance/LiabilityPaymentPlanService.lua")
dofile("src/delinquency/DelinquencyStateMachine.lua")
dofile("src/delinquency/RecoveryLiquidationPlanService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local loan = AGFLiability.new("AGF-LIAB-REC-1", 1, AGFProductType.EQUIPMENT_FINANCE)
loan.status = AGFLiabilityStatus.COLLECTIONS
loan.principalBalance = 60000
loan.accruedInterest = 1000
loan.accruedFees = 500

local account = AGFDelinquencyStateMachine.newAccountState()
account.state = AGFDelinquencyState.RECOVERY
account.missedPayments = 5
account.pastDueAmount = 15000

local deficiencyOk, deficiency = AGFRecoveryLiquidationPlanService.build(
    loan,
    account,
    "AGF-ASSET-REC-1",
    "AGF-LIEN-REC-1",
    50000,
    2000,
    {recoveryAuthorized = true, groupId = "GRP-REC-DEF"}
)
assertTrue(deficiencyOk, "deficiency recovery plan")
assertEqual(deficiency.netLiquidationProceeds, 48000, "net recovery proceeds")
assertEqual(deficiency.amountAppliedToDebt, 48000, "amount applied")
assertEqual(deficiency.deficiency, 13500, "remaining deficiency")
assertEqual(deficiency.surplus, 0, "no borrower surplus")
assertEqual(deficiency.fsCashDelta, 0, "no farm cash in deficiency recovery")
assertEqual(deficiency.paymentPlan.appliedFees, 500, "fees cleared first")
assertEqual(deficiency.paymentPlan.appliedInterest, 1000, "interest cleared second")
assertEqual(deficiency.paymentPlan.appliedPrincipal, 46500, "remaining proceeds to principal")
assertEqual(deficiency.liabilityOutcome.recommendedStatus, AGFLiabilityStatus.COLLECTIONS, "deficiency remains collections liability")
assertEqual(deficiency.delinquencyOutcome.recommendedState, AGFDelinquencyState.RECOVERY, "deficiency remains recovery state")
assertTrue(deficiency.lienReleaseIntent.releaseBecauseCollateralDisposed, "disposed collateral lien released")
assertEqual(deficiency.journalIntents[1].transactionType, AGFTransactionType.ASSET_SALE, "sale proceeds recorded")
assertEqual(deficiency.journalIntents[2].transactionType, AGFTransactionType.FINANCE_FEE, "recovery cost separate")

local surplusOk, surplus = AGFRecoveryLiquidationPlanService.build(
    loan,
    account,
    "AGF-ASSET-REC-1",
    "AGF-LIEN-REC-1",
    80000,
    2000,
    {recoveryAuthorized = true, groupId = "GRP-REC-SURPLUS"}
)
assertTrue(surplusOk, "surplus recovery plan")
assertEqual(surplus.netLiquidationProceeds, 78000, "surplus net proceeds")
assertEqual(surplus.amountAppliedToDebt, 61500, "full debt payoff")
assertEqual(surplus.deficiency, 0, "no deficiency")
assertEqual(surplus.surplus, 16500, "borrower surplus")
assertEqual(surplus.fsCashDelta, 16500, "only surplus reaches farm cash")
assertEqual(surplus.ledgerNet, 16500, "ledger reconciles to surplus")
assertEqual(surplus.liabilityOutcome.recommendedStatus, AGFLiabilityStatus.CLOSED, "satisfied liability closes")
assertEqual(surplus.delinquencyOutcome.recommendedState, AGFDelinquencyState.RESOLVED, "delinquency resolved")

local authOk, authError = AGFRecoveryLiquidationPlanService.build(
    loan, account, "A", "L", 50000, 0, {}
)
assertEqual(authOk, false, "recovery requires explicit authorization")
assertEqual(authError, "RECOVERY_AUTHORIZATION_REQUIRED", "authorization error")

local notRecovery = AGFDelinquencyStateMachine.newAccountState()
notRecovery.state = AGFDelinquencyState.COLLECTIONS
local stateOk, stateError = AGFRecoveryLiquidationPlanService.build(
    loan, notRecovery, "A", "L", 50000, 0, {recoveryAuthorized = true}
)
assertEqual(stateOk, false, "collections alone does not authorize liquidation")
assertEqual(stateError, "DELINQUENCY_NOT_IN_RECOVERY", "recovery-state error")

local costsOk, costsError = AGFRecoveryLiquidationPlanService.build(
    loan, account, "A", "L", 1000, 1000.01, {recoveryAuthorized = true}
)
assertEqual(costsOk, false, "cost capitalization not guessed")
assertEqual(costsError, "RECOVERY_COSTS_EXCEED_PROCEEDS", "excess-cost error")

print("offline_recovery_liquidation_plan_tests: PASS")
