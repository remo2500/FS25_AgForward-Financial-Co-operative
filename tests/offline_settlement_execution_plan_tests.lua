-- Offline atomic settlement execution-plan validation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/finance/PaymentAllocationService.lua")
dofile("src/finance/LiabilityPaymentPlanService.lua")
dofile("src/settlement/SettlementPlanner.lua")
dofile("src/settlement/SettlementExecutionPlanService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local equipment = AGFLiability.new("AGF-LIAB-EQ-1", 1, AGFProductType.EQUIPMENT_FINANCE)
equipment.status = AGFLiabilityStatus.ACTIVE
equipment.principalBalance = 100000
equipment.accruedInterest = 800
equipment.accruedFees = 0

local operatingLine = AGFLiability.new("AGF-LIAB-LOC-1", 1, AGFProductType.OPERATING_LINE)
operatingLine.status = AGFLiabilityStatus.ACTIVE
operatingLine.creditLimit = 10000
operatingLine.principalBalance = 0

local dueSchedule = {
    due = {
        {
            id = "loan:AGF-LIAB-EQ-1:1",
            sourceType = "loan",
            obligationType = "securedDebt",
            farmId = 1,
            liabilityId = equipment.id,
            productType = equipment.productType,
            amountDue = 5000
        },
        {
            id = "lease:AGF-LEASE-1:1",
            sourceType = "lease",
            obligationType = "leaseRent",
            farmId = 1,
            leaseId = "AGF-LEASE-1",
            productType = AGFProductType.LAND_LEASE,
            amountDue = 3000
        }
    }
}

local plannerOk, settlement = AGFSettlementPlanner.plan({
    {id = "loan:AGF-LIAB-EQ-1:1", obligationType = "securedDebt", priority = 10, amountDue = 5000, minimumPayment = 2500, allowPartial = true, allowCreditDraw = true},
    {id = "lease:AGF-LEASE-1:1", obligationType = "leaseRent", priority = 20, amountDue = 3000, minimumPayment = 3000, allowPartial = false, allowCreditDraw = false}
}, 4000, 3000)
assertTrue(plannerOk, "settlement allocation succeeds")

local executionOk, execution = AGFSettlementExecutionPlanService.build(
    settlement,
    dueSchedule,
    {[equipment.id] = equipment},
    operatingLine,
    {groupId = "GRP-SETTLEMENT-1"}
)
assertTrue(executionOk, "settlement execution plan succeeds")
assertEqual(execution.totalPaid, 5000, "only equipment paid")
assertEqual(execution.totalCashUsed, 4000, "cash used")
assertEqual(execution.totalCreditDraw, 1000, "operating line draw")
assertEqual(execution.fsCashDelta, -4000, "net FS cash movement")
assertEqual(execution.ledgerNet, -4000, "ledger net reconciles")
assertEqual(execution.creditDrawMutation.principalAfter, 1000, "line principal after proposed draw")
assertEqual(#execution.liabilityPaymentPlans, 1, "one liability payment plan")
assertEqual(execution.liabilityPaymentPlans[1].appliedInterest, 800, "actual accrued interest paid first")
assertEqual(execution.liabilityPaymentPlans[1].appliedPrincipal, 4200, "remaining payment to principal")
assertEqual(#execution.leasePaymentPlans, 0, "unpaid lease has no payment mutation")
assertEqual(#execution.servicingExceptions, 1, "unpaid lease becomes servicing review candidate")
assertEqual(execution.servicingExceptions[1].unpaid, 3000, "lease unpaid amount")
assertEqual(execution.journalIntents[1].transactionType, AGFTransactionType.CREDIT_DRAW, "credit draw posted before payments")

-- With enough cash both obligations pay without a credit draw.
local cashPlannerOk, cashSettlement = AGFSettlementPlanner.plan({
    {id = "loan:AGF-LIAB-EQ-1:1", obligationType = "securedDebt", priority = 10, amountDue = 5000, minimumPayment = 5000, allowPartial = false, allowCreditDraw = false},
    {id = "lease:AGF-LEASE-1:1", obligationType = "leaseRent", priority = 20, amountDue = 3000, minimumPayment = 3000, allowPartial = false, allowCreditDraw = false}
}, 8000, 0)
assertTrue(cashPlannerOk, "cash-only settlement allocation")
local cashExecutionOk, cashExecution = AGFSettlementExecutionPlanService.build(
    cashSettlement,
    dueSchedule,
    {[equipment.id] = equipment},
    nil,
    {groupId = "GRP-SETTLEMENT-2"}
)
assertTrue(cashExecutionOk, "cash-only execution")
assertEqual(cashExecution.totalCreditDraw, 0, "no credit draw")
assertEqual(cashExecution.fsCashDelta, -8000, "all cash used")
assertEqual(#cashExecution.leasePaymentPlans, 1, "lease payment included")
assertEqual(#cashExecution.servicingExceptions, 0, "all obligations paid")
assertEqual(cashExecution.leasePaymentPlans[1].appliedRent, 3000, "lease rent applied")

-- Generic CILOC cannot be used as a settlement backstop.
local ciloc = AGFLiability.new("AGF-LIAB-CILOC-1", 1, AGFProductType.CROP_INPUT_LINE)
ciloc.status = AGFLiabilityStatus.ACTIVE
ciloc.creditLimit = 10000
local wrongCreditOk, wrongCreditError = AGFSettlementExecutionPlanService.build(
    settlement,
    dueSchedule,
    {[equipment.id] = equipment},
    ciloc,
    {}
)
assertEqual(wrongCreditOk, false, "CILOC rejected as generic settlement credit")
assertEqual(wrongCreditError, "SETTLEMENT_CREDIT_MUST_BE_OPERATING_LINE", "settlement credit product error")

print("offline_settlement_execution_plan_tests: PASS")
