-- Offline validation for the Phase-0 ledger/liability coordinated mutation boundary.
-- This exercises the real core Lua classes under stock Lua 5.1 without FS25.

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

local function newRuntime()
    local runtime = {allowed = true, safeModeReason = nil, safeModeDetail = nil}
    function runtime:canMutate()
        if self.allowed then return true, nil end
        return false, "MUTATION_BLOCKED"
    end
    function runtime:enterSafeMode(reason, detail)
        self.safeModeReason = reason
        self.safeModeDetail = detail
        self.allowed = false
    end
    return runtime
end

local function buildCore()
    local runtime = newRuntime()
    local ids = AGFIdService.new()
    local ledger = AGFLedger.new(ids, runtime)
    local liabilities = AGFLiabilityRegistry.new(ids, runtime)
    local coordinator = AGFFinancialOperationCoordinator.new(ledger, liabilities, runtime)
    return runtime, ids, ledger, liabilities, coordinator
end

local function registerLine(liabilities, farmId, productType, limit, principal)
    local draft, createError = liabilities:create(farmId, productType, "Test line")
    assertEqual(createError, nil, "liability create error")
    draft.creditLimit = limit
    draft.principalBalance = principal or 0
    draft.originalPrincipal = principal or 0
    draft.status = AGFLiabilityStatus.ACTIVE
    local registered, record = liabilities:register(draft)
    assertTrue(registered, "liability registered")
    return record
end

-- Successful CILOC purchase creates a balanced two-entry group and one debt draw.
local runtime, ids, ledger, liabilities, coordinator = buildCore()
local line = registerLine(liabilities, 1, AGFProductType.CROP_INPUT_LINE, 50000, 10000)
local ok, result = coordinator:executeRevolvingInputPurchase(
    1,
    20000,
    AGFExpenseCategory.FERTILIZER,
    AGFFundingSource.CROP_INPUT_LINE,
    line.id,
    "Spring fertilizer",
    AGFProductType.CROP_INPUT_LINE
)
assertTrue(ok, "coordinated input purchase succeeds")
assertEqual(ledger:getTransactionCount(), 2, "two journal records")
assertEqual(liabilities:get(line.id).principalBalance, 30000, "principal increased exactly once")
assertEqual(result.draw.amount, 20000, "draw is financing inflow")
assertEqual(result.purchase.amount, -20000, "purchase is expense outflow")
assertEqual(result.draw.groupId, result.purchase.groupId, "linked records share group")
assertEqual(result.purchase.expenseCategory, AGFExpenseCategory.FERTILIZER, "expense purpose preserved")
assertEqual(result.draw.fundingSource, AGFFundingSource.CROP_INPUT_LINE, "funding source preserved")
assertEqual(result.purchase.liabilityId, line.id, "purchase retains liability trace")

local grouped = ledger:getGroupTransactions(result.groupId)
assertEqual(#grouped, 2, "group query returns both entries")
assertTrue(AGFCurrency.equals(grouped[1].amount + grouped[2].amount, 0), "financing/purchase group reconciles to zero")

-- Public return values are clones; caller mutation cannot corrupt authority.
result.draw.amount = 999999
result.liability.principalBalance = 999999
assertEqual(ledger:getGroupTransactions(result.groupId)[1].amount, 20000, "returned transaction is not authoritative")
assertEqual(liabilities:get(line.id).principalBalance, 30000, "returned liability is not authoritative")

-- Wrong farm, wrong product and over-limit requests are rejected before journaling.
local beforeCount = ledger:getTransactionCount()
local wrongFarmOk, wrongFarmError = coordinator:executeRevolvingInputPurchase(
    2, 1000, AGFExpenseCategory.SEED, AGFFundingSource.CROP_INPUT_LINE,
    line.id, "Wrong farm", AGFProductType.CROP_INPUT_LINE
)
assertFalse(wrongFarmOk, "wrong farm rejected")
assertEqual(wrongFarmError, "LIABILITY_FARM_MISMATCH", "wrong farm error")
assertEqual(ledger:getTransactionCount(), beforeCount, "wrong farm posts nothing")

local wrongProductOk, wrongProductError = coordinator:executeRevolvingInputPurchase(
    1, 1000, AGFExpenseCategory.SEED, AGFFundingSource.CROP_INPUT_LINE,
    line.id, "Wrong product", AGFProductType.OPERATING_LINE
)
assertFalse(wrongProductOk, "wrong product rejected")
assertEqual(wrongProductError, "WRONG_PRODUCT_TYPE", "wrong product error")
assertEqual(ledger:getTransactionCount(), beforeCount, "wrong product posts nothing")

local overLimitOk, overLimitError = coordinator:executeRevolvingInputPurchase(
    1, 20000.01, AGFExpenseCategory.SEED, AGFFundingSource.CROP_INPUT_LINE,
    line.id, "Over limit", AGFProductType.CROP_INPUT_LINE
)
assertFalse(overLimitOk, "over-limit draw rejected")
assertEqual(overLimitError, "CREDIT_LIMIT_EXCEEDED", "over-limit error")
assertEqual(liabilities:get(line.id).principalBalance, 30000, "over-limit leaves principal unchanged")
assertEqual(ledger:getTransactionCount(), beforeCount, "over-limit posts nothing")

-- Runtime authority blocks all mutations before IDs/ledger/debt are consumed.
runtime.allowed = false
local blockedOk, blockedError = coordinator:executeRevolvingInputPurchase(
    1, 1000, AGFExpenseCategory.FUEL, AGFFundingSource.CROP_INPUT_LINE,
    line.id, "Blocked", AGFProductType.CROP_INPUT_LINE
)
assertFalse(blockedOk, "blocked runtime rejects operation")
assertEqual(blockedError, "MUTATION_BLOCKED", "blocked runtime error")
assertEqual(ledger:getTransactionCount(), beforeCount, "blocked runtime posts nothing")
runtime.allowed = true

-- Public debt mutators remain forbidden; coordinator is the journal gate.
local publicDrawOk, publicDrawError = liabilities:applyDraw(line.id, 1000)
assertFalse(publicDrawOk, "public draw mutation blocked")
assertEqual(publicDrawError, "OPERATION_COORDINATOR_REQUIRED", "public draw requires coordinator")
local publicPaymentOk, publicPaymentError = liabilities:applyPrincipalPayment(line.id, 1000)
assertFalse(publicPaymentOk, "public payment mutation blocked")
assertEqual(publicPaymentError, "OPERATION_COORDINATOR_REQUIRED", "public payment requires coordinator")

-- Even an internal committed draw must not be able to break the revolver limit.
-- This is defense-in-depth for future multiplayer/interleaving logic.
local directOverdrawOk, directOverdrawError = liabilities:applyDrawCommitted(line.id, 20000.01, true)
assertFalse(directOverdrawOk, "committed draw cannot bypass credit limit")
assertEqual(directOverdrawError, "CREDIT_LIMIT_EXCEEDED", "committed overdraw error")
assertEqual(liabilities:get(line.id).principalBalance, 30000, "committed overdraw leaves balance unchanged")

-- If debt application fails after journal posting, the just-posted batch rolls back.
local runtime2, ids2, ledger2, liabilities2, coordinator2 = buildCore()
local line2 = registerLine(liabilities2, 1, AGFProductType.CROP_INPUT_LINE, 50000, 0)
local originalApply = liabilities2.applyDrawCommitted
liabilities2.applyDrawCommitted = function(self, liabilityId, amount, internal)
    return false, "FORCED_DEBT_APPLY_FAILURE"
end
local failedOk, failedError = coordinator2:executeRevolvingInputPurchase(
    1, 5000, AGFExpenseCategory.SEED, AGFFundingSource.CROP_INPUT_LINE,
    line2.id, "Rollback test", AGFProductType.CROP_INPUT_LINE
)
assertFalse(failedOk, "forced debt failure rejects operation")
assertEqual(failedError, "FORCED_DEBT_APPLY_FAILURE", "forced debt failure returned")
assertEqual(ledger2:getTransactionCount(), 0, "failed operation rolls journal back")
assertEqual(liabilities2:get(line2.id).principalBalance, 0, "failed operation leaves debt unchanged")
assertEqual(runtime2.safeModeReason, nil, "successful rollback does not enter safe mode")
liabilities2.applyDrawCommitted = originalApply

-- If the compensating rollback itself fails, the coordinator must stop mutation.
local runtime3 = newRuntime()
local fakeLiability = AGFLiability.new("AGF-LIAB-999999", 1, AGFProductType.CROP_INPUT_LINE)
fakeLiability.creditLimit = 50000
fakeLiability.status = AGFLiabilityStatus.ACTIVE
local fakeLiabilities = {
    canDraw = function(self, liabilityId, farmId, amount, expectedProductType)
        return true, fakeLiability:clone()
    end,
    applyDrawCommitted = function(self, liabilityId, amount, internal)
        return false, "FORCED_DEBT_APPLY_FAILURE"
    end
}
local transactionCounter = 0
local fakeLedger = {
    createGroupId = function(self) return "AGF-GRP-999999" end,
    createTransaction = function(self, farmId, transactionType, amount)
        transactionCounter = transactionCounter + 1
        return AGFTransaction.new("AGF-TX-" .. string.format("%06d", transactionCounter), farmId, transactionType, amount)
    end,
    postBatch = function(self, transactions) return true, nil end,
    rollbackBatch = function(self, ids, internal) return false, "FORCED_ROLLBACK_FAILURE" end
}
local coordinator3 = AGFFinancialOperationCoordinator.new(fakeLedger, fakeLiabilities, runtime3)
local rollbackFailOk, rollbackFailError = coordinator3:executeRevolvingInputPurchase(
    1, 5000, AGFExpenseCategory.SEED, AGFFundingSource.CROP_INPUT_LINE,
    fakeLiability.id, "Rollback failure", AGFProductType.CROP_INPUT_LINE
)
assertFalse(rollbackFailOk, "rollback failure operation rejected")
assertEqual(rollbackFailError, "FORCED_DEBT_APPLY_FAILURE", "original debt failure retained")
assertEqual(runtime3.safeModeReason, "OPERATION_ROLLBACK_FAILED", "rollback failure enters safe mode")
assertFalse(runtime3.allowed, "safe mode blocks future mutations")

print("offline_operation_tests: PASS")
