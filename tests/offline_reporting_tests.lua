-- Offline reporting validation. Reports must derive from common ledgers/registries
-- and must not become independent balance authorities.

function Class(classTable)
    return {__index = classTable}
end

g_currentMission = nil

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/ledger/Transaction.lua")
dofile("src/ledger/Ledger.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/liabilities/LiabilityRegistry.lua")
dofile("src/credit/ExternalObligation.lua")
dofile("src/credit/ExternalObligationRegistry.lua")
dofile("src/reporting/LedgerReportService.lua")
dofile("src/reporting/DebtScheduleReportService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local writableRuntime = {canMutate = function() return true, nil end}
local ids = AGFIdService.new()
local ledger = AGFLedger.new(ids, writableRuntime)
local liabilities = AGFLiabilityRegistry.new(ids, writableRuntime)
local external = AGFExternalObligationRegistry.new(ids)
local ledgerReports = AGFLedgerReportService.new(ledger)
local debtReports = AGFDebtScheduleReportService.new(liabilities, external)

-- Linked fertilizer purchase: financing source and economic purpose remain separate.
local groupId = ledger:createGroupId()
local draw = ledger:createTransaction(1, AGFTransactionType.CREDIT_DRAW, 30000)
draw:setGroupId(groupId)
draw:setFundingSource(AGFFundingSource.CROP_INPUT_LINE)
draw:setLiabilityId("AGF-LIAB-000100")
draw:setMetadata("economicRole", "financing")

local fertilizer = ledger:createTransaction(1, AGFTransactionType.INPUT_PURCHASE, -30000)
fertilizer:setGroupId(groupId)
fertilizer:setFundingSource(AGFFundingSource.CROP_INPUT_LINE)
fertilizer:setExpenseCategory(AGFExpenseCategory.FERTILIZER)
fertilizer:setLiabilityId("AGF-LIAB-000100")
fertilizer:setMetadata("economicRole", "expense")

local posted, postError = ledger:postBatch({draw, fertilizer})
assertTrue(posted, postError)

-- Cash seed purchase.
local seed = ledger:createTransaction(1, AGFTransactionType.INPUT_PURCHASE, -5000)
seed:setFundingSource(AGFFundingSource.CASH)
seed:setExpenseCategory(AGFExpenseCategory.SEED)
local seedPosted, seedError = ledger:post(seed)
assertTrue(seedPosted, seedError)

local summary = ledgerReports:buildFarmSummary(1)
assertEqual(summary.transactionCount, 3, "report transaction count")
assertEqual(summary.byExpenseCategory[AGFExpenseCategory.FERTILIZER], -30000, "fertilizer economic outflow")
assertEqual(summary.byExpenseCategory[AGFExpenseCategory.SEED], -5000, "seed economic outflow")
assertEqual(summary.financedInputPurchases[AGFExpenseCategory.FERTILIZER], 30000, "financed fertilizer total")
assertEqual(summary.cashInputPurchases[AGFExpenseCategory.SEED], 5000, "cash seed total")
assertEqual(summary.sourceOfFundsByExpenseCategory[AGFExpenseCategory.FERTILIZER][AGFFundingSource.CROP_INPUT_LINE], 30000, "fertilizer CILOC source")
assertEqual(summary.sourceOfFundsByExpenseCategory[AGFExpenseCategory.SEED][AGFFundingSource.CASH], 5000, "seed cash source")

local groupSummary = ledgerReports:buildTransactionGroup(groupId)
assertEqual(groupSummary.transactionCount, 2, "group transaction count")
assertEqual(groupSummary.netAmount, 0, "group net immediate cash")
assertTrue(groupSummary.balancedEconomicCash, "linked draw/purchase group balances")

-- Native + external debt report.
local ciloc, cilocError = liabilities:create(1, AGFProductType.CROP_INPUT_LINE, "Crop Input Line")
assertEqual(cilocError, nil, "CILOC create error")
ciloc.creditLimit = 100000
ciloc.principalBalance = 30000
ciloc.accruedInterest = 500
ciloc.interestRate = 0.07
local cilocRegistered, cilocRegisterError = liabilities:register(ciloc)
assertTrue(cilocRegistered, cilocRegisterError)

local termLoan, termError = liabilities:create(1, AGFProductType.TERM_LOAN, "Term Note")
assertEqual(termError, nil, "term loan create error")
termLoan.principalBalance = 50000
termLoan.accruedInterest = 250
termLoan.accruedFees = 25
termLoan.scheduledPayment = 4500
local termRegistered, termRegisterError = liabilities:register(termLoan)
assertTrue(termRegistered, termRegisterError)

local baseLoan, baseError = external:create(1, AGFExternalObligationType.BASE_GAME_LOAN, "baseGame", "Base Game Loan")
assertEqual(baseError, nil, "external create error")
baseLoan.principalBalance = 20000
baseLoan.annualDebtService = 6000
baseLoan.dataQuality = AGFExternalObligationQuality.VERIFIED
local baseRegistered, baseRegisterError = external:register(baseLoan)
assertTrue(baseRegistered, baseRegisterError)

local debt = debtReports:build(1)
assertEqual(#debt.native, 2, "native debt rows")
assertEqual(#debt.external, 1, "external debt rows")
assertEqual(debt.totals.nativePrincipal, 80000, "native principal")
assertEqual(debt.totals.nativeAccruedInterest, 750, "native accrued interest")
assertEqual(debt.totals.nativeAccruedFees, 25, "native accrued fees")
assertEqual(debt.totals.nativeOutstanding, 80775, "native outstanding")
assertEqual(debt.totals.externalPrincipal, 20000, "external principal")
assertEqual(debt.totals.representedDebt, 100775, "represented debt")
assertEqual(debt.byProduct[AGFProductType.CROP_INPUT_LINE].availableCredit, 70000, "CILOC available credit report")
assertEqual(debt.dataQuality.verifiedExternal, 1, "verified external debt count")

print("offline_reporting_tests: PASS")
