-- Offline staged project commitment/draw transaction planning.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/ProjectDrawPlanService.lua")

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

local facility = {
    id = "AGF-LIAB-PROJECT-1",
    farmId = 1,
    productType = AGFProductType.PROJECT_FINANCE,
    status = "active",
    commitmentAmount = 400000,
    principalBalance = 0,
    assetId = "AGF-ASSET-PROJECT-1"
}

local ok, plan = AGFProjectDrawPlanService.plan(facility, 80000, 100000, {
    cashAvailable = 30000,
    groupId = "GRP-PROJECT-1",
    useType = "construction",
    reference = "foundation"
})
assertTrue(ok, "project draw plan succeeds")
assertEqual(plan.commitmentAmount, 400000, "commitment")
assertEqual(plan.principalBefore, 0, "opening advanced principal")
assertEqual(plan.drawAmount, 80000, "draw")
assertEqual(plan.projectUseAmount, 100000, "project use")
assertEqual(plan.cashContribution, 20000, "cash contribution")
assertEqual(plan.principalAfter, 80000, "advanced principal after")
assertEqual(plan.undrawnCommitmentAfter, 320000, "undrawn commitment")
assertEqual(plan.fsCashDelta, -20000, "FS cash delta")
assertEqual(plan.ledgerNet, -20000, "ledger reconciles to cash")
assertEqual(plan.ledgerIntents[1].transactionType, AGFTransactionType.LOAN_PROCEEDS, "project financing inflow")
assertEqual(plan.ledgerIntents[1].fundingSource, AGFFundingSource.PROJECT_FINANCE, "project financing source")
assertEqual(plan.ledgerIntents[2].transactionType, AGFTransactionType.ASSET_PURCHASE, "project use")
assertEqual(plan.ledgerIntents[2].fundingBreakdown.cash, 20000, "project cash breakdown")
assertEqual(plan.ledgerIntents[2].metadata.reference, "foundation", "project reference retained")
assertTrue(plan.requiresInterestAccrualRecalculation, "draw changes interest accrual basis")

facility.principalBalance = 390000
local overOk, overError = AGFProjectDrawPlanService.plan(facility, 20000, 20000, {})
assertFalse(overOk, "draw cannot exceed undrawn commitment")
assertEqual(overError, "PROJECT_COMMITMENT_EXCEEDED", "commitment error")

facility.principalBalance = 100000
local cashOk, cashError = AGFProjectDrawPlanService.plan(facility, 50000, 100000, {cashAvailable = 49999.99})
assertFalse(cashOk, "cash contribution checked")
assertEqual(cashError, "INSUFFICIENT_CASH_FOR_PROJECT_USE", "cash error")

local excessDrawOk, excessDrawError = AGFProjectDrawPlanService.plan(facility, 100001, 100000, {cashAvailable = 0})
assertFalse(excessDrawOk, "draw cannot exceed current project use")
assertEqual(excessDrawError, "PROJECT_DRAW_EXCEEDS_CURRENT_USE", "draw/use error")

facility.principalBalance = 100000
local fullFinanceOk, fullFinance = AGFProjectDrawPlanService.plan(facility, 50000, 50000, {cashAvailable = 0})
assertTrue(fullFinanceOk, "fully financed project use succeeds")
assertEqual(fullFinance.cashContribution, 0, "fully financed use needs no cash")
assertEqual(fullFinance.fsCashDelta, 0, "fully financed use net cash neutral")

print("offline_project_draw_plan_tests: PASS")
