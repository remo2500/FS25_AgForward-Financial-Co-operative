-- Offline financial-history validation. Period history is derived from the ledger only.

function Class(classTable)
    return {__index = classTable}
end

g_currentMission = nil

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/ledger/Transaction.lua")
dofile("src/ledger/Ledger.lua")
dofile("src/reporting/FinancialHistoryService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local runtime = {canMutate = function() return true, nil end}
local ids = AGFIdService.new()
local ledger = AGFLedger.new(ids, runtime)
local history = AGFFinancialHistoryService.new(ledger)

local function post(transaction)
    local ok, err = ledger:post(transaction)
    assertTrue(ok, err)
end

local draw = ledger:createTransaction(1, AGFTransactionType.CREDIT_DRAW, 30000)
draw:setPeriod(2026, 9)
draw:setFundingSource(AGFFundingSource.CROP_INPUT_LINE)
post(draw)

local fertilizer = ledger:createTransaction(1, AGFTransactionType.INPUT_PURCHASE, -30000)
fertilizer:setPeriod(2026, 9)
fertilizer:setExpenseCategory(AGFExpenseCategory.FERTILIZER)
fertilizer:setFundingSource(AGFFundingSource.CROP_INPUT_LINE)
post(fertilizer)

local seed = ledger:createTransaction(1, AGFTransactionType.INPUT_PURCHASE, -5000)
seed:setPeriod(2026, 9)
seed:setExpenseCategory(AGFExpenseCategory.SEED)
seed:setFundingSource(AGFFundingSource.CASH)
post(seed)

local payment = ledger:createTransaction(1, AGFTransactionType.LOAN_PAYMENT, -12000)
payment:setPeriod(2026, 10)
payment:setBreakdown(9500, 2300, 200)
payment:setFundingSource(AGFFundingSource.CASH)
post(payment)

local asset = ledger:createTransaction(1, AGFTransactionType.ASSET_PURCHASE, -100000)
asset:setPeriod(2026, 10)
post(asset)

local grant = ledger:createTransaction(1, AGFTransactionType.GRANT_RECEIPT, 25000)
grant:setPeriod(2026, 10)
post(grant)

local p9Ok, p9 = history:buildPeriod(1, 2026, 9)
assertTrue(p9Ok, "period 9 history succeeds")
assertEqual(p9.transactionCount, 3, "period 9 transaction count")
assertEqual(p9.cashFlow.inflows, 30000, "period 9 inflows")
assertEqual(p9.cashFlow.outflows, 35000, "period 9 outflows")
assertEqual(p9.cashFlow.net, -5000, "period 9 net cash")
assertEqual(p9.inputPurchases.total, 35000, "period 9 inputs")
assertEqual(p9.inputPurchases.financed, 30000, "period 9 financed inputs")
assertEqual(p9.inputPurchases.cash, 5000, "period 9 cash inputs")
assertEqual(p9.sourceOfFundsByExpenseCategory[AGFExpenseCategory.FERTILIZER][AGFFundingSource.CROP_INPUT_LINE], 30000, "fertilizer finance source")
assertEqual(p9.byMovementClass.financing.net, 30000, "financing movement")
assertEqual(p9.byMovementClass.operating.net, -35000, "operating movement")

local p10Ok, p10 = history:buildPeriod(1, 2026, 10)
assertTrue(p10Ok, "period 10 history succeeds")
assertEqual(p10.transactionCount, 3, "period 10 transaction count")
assertEqual(p10.components.principal, 9500, "period 10 principal component")
assertEqual(p10.components.interest, 2300, "period 10 interest component")
assertEqual(p10.components.fees, 200, "period 10 fee component")
assertEqual(p10.byMovementClass.investing.outflows, 100000, "asset purchase investing outflow")
assertEqual(p10.byMovementClass.government.inflows, 25000, "grant inflow")

local rangeOk, range = history:buildRange(1, 2026, 9, 2026, 10)
assertTrue(rangeOk, "history range succeeds")
assertEqual(range.periodCount, 2, "range period count")
assertEqual(range.transactionCount, 6, "range transaction count")
assertEqual(range.cashFlow.inflows, 55000, "range inflows")
assertEqual(range.cashFlow.outflows, 147000, "range outflows")
assertEqual(range.cashFlow.net, -92000, "range net")
assertEqual(range.inputPurchases.total, 35000, "range input total")
assertEqual(range.components.principal, 9500, "range principal components")

local annualOk, annual = history:buildAnnual(1, 2026)
assertTrue(annualOk, "annual history succeeds")
assertEqual(annual.periodCount, 12, "annual period count")
assertEqual(annual.transactionCount, 6, "annual transaction count")
assertEqual(annual.cashFlow.net, -92000, "annual net")

local reverseOk, reverseError = history:buildRange(1, 2026, 10, 2026, 9)
assertEqual(reverseOk, false, "reversed range rejected")
assertEqual(reverseError, "HISTORY_RANGE_REVERSED", "reversed range error")

print("offline_financial_history_tests: PASS")
