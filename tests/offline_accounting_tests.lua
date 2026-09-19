-- Offline validation for the high-level accounting API and funding-source separation.

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
dofile("src/ledger/FinancialOperationCoordinator.lua")
dofile("src/ledger/AccountingService.lua")

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

local runtime = {
    allowed = true,
    canMutate = function(self)
        if self.allowed then return true, nil end
        return false, "ACCOUNTING_MUTATION_BLOCKED"
    end,
    enterSafeMode = function(self, reason, detail)
        self.allowed = false
        self.safeModeReason = reason
        self.safeModeDetail = detail
    end
}

local ids = AGFIdService.new()
local ledger = AGFLedger.new(ids, runtime)
local liabilities = AGFLiabilityRegistry.new(ids, runtime)
local operations = AGFFinancialOperationCoordinator.new(ledger, liabilities, runtime)
local accounting = AGFAccountingService.new(ledger, liabilities, operations, runtime)

local function createLine(productType, limit)
    local draft, createError = liabilities:create(1, productType, "Test facility")
    assertEqual(createError, nil, "line create error")
    draft.creditLimit = limit
    draft.status = AGFLiabilityStatus.ACTIVE
    local registered, record = liabilities:register(draft)
    assertTrue(registered, "line registered")
    return record
end

local ciloc = createLine(AGFProductType.CROP_INPUT_LINE, 50000)
local operating = createLine(AGFProductType.OPERATING_LINE, 25000)

-- Cash purchases create only the expense record; funding remains explicitly cash.
local cashOk, cashTx = accounting:postCashExpense(1, 1234.56, AGFExpenseCategory.SEED, "Cash seed")
assertTrue(cashOk, "cash expense posts")
assertEqual(cashTx.transactionType, AGFTransactionType.INPUT_PURCHASE, "cash transaction type")
assertEqual(cashTx.amount, -1234.56, "cash expense signed amount")
assertEqual(cashTx.expenseCategory, AGFExpenseCategory.SEED, "cash expense category")
assertEqual(cashTx.fundingSource, AGFFundingSource.CASH, "cash funding source")
assertEqual(ledger:getTransactionCount(), 1, "cash purchase creates one journal record")

-- CILOC preserves fertilizer purpose while separately recording its funding draw.
local cilocOk, cilocResult = accounting:postCropInputLinePurchase(
    1,
    10000,
    AGFExpenseCategory.FERTILIZER,
    ciloc.id,
    "Spring fertilizer"
)
assertTrue(cilocOk, "CILOC purchase posts")
assertEqual(liabilities:get(ciloc.id).principalBalance, 10000, "CILOC principal increases")
assertEqual(cilocResult.purchase.expenseCategory, AGFExpenseCategory.FERTILIZER, "CILOC purpose preserved")
assertEqual(cilocResult.purchase.fundingSource, AGFFundingSource.CROP_INPUT_LINE, "CILOC funding source")
assertEqual(cilocResult.draw.transactionType, AGFTransactionType.CREDIT_DRAW, "CILOC draw transaction type")
assertEqual(cilocResult.draw.amount, 10000, "CILOC financing inflow")
assertEqual(cilocResult.purchase.amount, -10000, "CILOC economic purchase outflow")
assertEqual(ledger:getTransactionCount(), 3, "CILOC adds linked draw and purchase")

-- General operating line uses the same coordinator but requires its own product type.
local operatingOk, operatingResult = accounting:postFundedInputPurchase(
    1,
    5000,
    AGFExpenseCategory.FUEL,
    AGFFundingSource.OPERATING_LINE,
    operating.id,
    "Operating fuel"
)
assertTrue(operatingOk, "operating-line purchase posts")
assertEqual(liabilities:get(operating.id).principalBalance, 5000, "operating line principal increases")
assertEqual(operatingResult.purchase.expenseCategory, AGFExpenseCategory.FUEL, "operating purpose preserved")
assertEqual(operatingResult.purchase.fundingSource, AGFFundingSource.OPERATING_LINE, "operating funding source preserved")

-- Cash route through the common method must not require a liability.
local routedCashOk, routedCash = accounting:postFundedInputPurchase(
    1,
    250,
    AGFExpenseCategory.LIME_SOIL_AMENDMENT,
    AGFFundingSource.CASH,
    nil,
    "Cash lime"
)
assertTrue(routedCashOk, "common funded API routes cash correctly")
assertEqual(routedCash.fundingSource, AGFFundingSource.CASH, "routed cash source")

-- CILOC rejects categories outside crop-input policy before any mutation.
local countBeforeIneligible = ledger:getTransactionCount()
local principalBeforeIneligible = liabilities:get(ciloc.id).principalBalance
local ineligibleOk, ineligibleError = accounting:postCropInputLinePurchase(
    1,
    1000,
    AGFExpenseCategory.LAND_RENT,
    ciloc.id,
    "Not an input"
)
assertFalse(ineligibleOk, "ineligible CILOC category rejected")
assertEqual(ineligibleError, "INELIGIBLE_CROP_INPUT_CATEGORY", "ineligible CILOC error")
assertEqual(ledger:getTransactionCount(), countBeforeIneligible, "ineligible CILOC posts nothing")
assertEqual(liabilities:get(ciloc.id).principalBalance, principalBeforeIneligible, "ineligible CILOC leaves debt unchanged")

-- Direct funded purchases must name a liability and use a supported revolver source.
local noLiabilityOk, noLiabilityError = accounting:postFundedInputPurchase(
    1, 100, AGFExpenseCategory.SEED, AGFFundingSource.CROP_INPUT_LINE, nil, "Missing liability"
)
assertFalse(noLiabilityOk, "funded purchase without liability rejected")
assertEqual(noLiabilityError, "LIABILITY_REQUIRED", "missing liability error")

local unsupportedOk, unsupportedError = accounting:postFundedInputPurchase(
    1, 100, AGFExpenseCategory.SEED, AGFFundingSource.TERM_LOAN, ciloc.id, "Unsupported direct funding"
)
assertFalse(unsupportedOk, "term loan cannot act as direct input revolver")
assertEqual(unsupportedError, "UNSUPPORTED_DIRECT_FUNDING_SOURCE", "unsupported source error")

-- Funding source and product type cannot be mismatched.
local mismatchOk, mismatchError = accounting:postFundedInputPurchase(
    1, 100, AGFExpenseCategory.SEED, AGFFundingSource.OPERATING_LINE, ciloc.id, "Mismatch"
)
assertFalse(mismatchOk, "funding source/product mismatch rejected")
assertEqual(mismatchError, "WRONG_PRODUCT_TYPE", "funding/product mismatch error")

-- Invalid amounts and runtime authority failures remain fail-closed.
local zeroOk, zeroError = accounting:postCashExpense(1, 0, AGFExpenseCategory.SEED, "Zero")
assertFalse(zeroOk, "zero cash expense rejected")
assertEqual(zeroError, "INVALID_AMOUNT", "zero cash error")

local badFarmOk, badFarmError = accounting:postCashExpense(0, 1, AGFExpenseCategory.SEED, "Bad farm")
assertFalse(badFarmOk, "invalid farm cannot enter ledger")
assertEqual(badFarmError, "INVALID_TRANSACTION_FARM", "invalid farm error propagates")

runtime.allowed = false
local blockedOk, blockedError = accounting:postCashExpense(1, 1, AGFExpenseCategory.SEED, "Blocked")
assertFalse(blockedOk, "runtime blocks cash accounting mutation")
assertEqual(blockedError, "ACCOUNTING_MUTATION_BLOCKED", "runtime accounting error")

print("offline_accounting_tests: PASS")
