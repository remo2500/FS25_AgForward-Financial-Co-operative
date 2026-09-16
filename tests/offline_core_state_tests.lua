-- Offline validation for runtime authority, IDs, immutable transactions, and ledger rollback.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/core/RuntimeStateService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/ledger/Transaction.lua")
dofile("src/ledger/Ledger.lua")

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

-- Runtime authority is explicit and fail-closed.
g_currentMission = nil
local runtime = AGFRuntimeStateService.new()
assertEqual(runtime:getState(), AGFRuntimeState.BOOTSTRAPPING, "initial runtime state")
local bootAllowed, bootError = runtime:canMutate()
assertFalse(bootAllowed, "no mission cannot mutate")
assertEqual(bootError, "SERVER_AUTHORITY_REQUIRED", "no mission authority error")

g_currentMission = {getIsServer = function() return true end}
runtime:setState(AGFRuntimeState.NEW_STATE, "new")
assertTrue(runtime:canMutate(), "new validated state writable")
runtime:setState(AGFRuntimeState.NORMAL, "normal")
assertTrue(runtime:canSave(), "normal state saveable")
runtime:setState(AGFRuntimeState.RECOVERED, "recovered")
assertTrue(runtime:canMutate(), "validated recovered state writable")
runtime:setState(AGFRuntimeState.SHUTDOWN, "shutdown")
local shutdownAllowed, shutdownError = runtime:canMutate()
assertFalse(shutdownAllowed, "shutdown state blocked")
assertEqual(shutdownError, "RUNTIME_STATE_NOT_WRITABLE_SHUTDOWN", "shutdown error")

runtime:enterSafeMode("TEST_SAFE_MODE", "test reason")
assertEqual(runtime:getState(), AGFRuntimeState.READ_ONLY_SAFE_MODE, "safe mode state")
assertEqual(runtime.reason, "TEST_SAFE_MODE", "safe mode reason")
local issues = runtime:getIssues()
assertEqual(#issues, 1, "safe mode issue recorded")
assertEqual(issues[1].severity, "error", "safe mode issue severity")
issues[1].code = "MUTATED_COPY"
assertEqual(runtime:getIssues()[1].code, "TEST_SAFE_MODE", "issue query returns copy")

g_currentMission.getIsServer = function() return false end
runtime:setState(AGFRuntimeState.NORMAL, "client")
local clientAllowed, clientError = runtime:canMutate()
assertFalse(clientAllowed, "client cannot mutate")
assertEqual(clientError, "SERVER_AUTHORITY_REQUIRED", "client authority error")
g_currentMission.getIsServer = function() return true end

-- ID service is monotonic, observes restored IDs, and returns defensive copies.
local ids = AGFIdService.new()
assertEqual(ids:next("TX"), "AGF-TX-000001", "first transaction ID")
assertEqual(ids:next("TX"), "AGF-TX-000002", "second transaction ID")
ids:observeId("AGF-TX-000125")
assertEqual(ids:next("TX"), "AGF-TX-000126", "observed ID advances counter")
ids:observeId("not-an-agforward-id")
assertEqual(ids:getCounter("TX"), 126, "invalid ID ignored")
ids:ensureAtLeast("LIAB", 5)
ids:ensureAtLeast("LIAB", 2)
assertEqual(ids:getCounter("LIAB"), 5, "counter never moves backward")
local counters = ids:getCounters()
counters.TX = 1
assertEqual(ids:getCounter("TX"), 126, "counter query returns copy")

-- Fresh writable runtime for ledger tests.
local ledgerRuntime = {
    allowed = true,
    canMutate = function(self)
        if self.allowed then return true, nil end
        return false, "LEDGER_MUTATION_BLOCKED"
    end
}
local ledgerIds = AGFIdService.new()
local ledger = AGFLedger.new(ledgerIds, ledgerRuntime)

local tx1 = ledger:createTransaction(1, AGFTransactionType.ADJUSTMENT, 100)
tx1:setDescription("first")
local posted1, post1Error = ledger:post(tx1)
assertTrue(posted1, "first transaction posts: " .. tostring(post1Error))
assertTrue(tx1:isSealed(), "posted transaction sealed")
assertEqual(ledger:getTransactionCount(), 1, "ledger count after post")

tx1:setDescription("should not change")
assertEqual(ledger:getTransaction(tx1.id).description, "first", "sealed transaction cannot be edited")
local publicTx = ledger:getTransaction(tx1.id)
publicTx.amount = 999999
assertEqual(ledger:getTransaction(tx1.id).amount, 100, "public transaction query returns clone")

-- Posting validation rejects malformed state before it enters authority.
local badFarm = ledger:createTransaction(0, AGFTransactionType.ADJUSTMENT, 1)
local badFarmOk, badFarmError = ledger:post(badFarm)
assertFalse(badFarmOk, "farm zero rejected")
assertEqual(badFarmError, "INVALID_TRANSACTION_FARM", "farm validation error")

local missingType = ledger:createTransaction(1, nil, 1)
local missingTypeOk, missingTypeError = ledger:post(missingType)
assertFalse(missingTypeOk, "missing type rejected")
assertEqual(missingTypeError, "INVALID_TRANSACTION_TYPE", "missing type error")

local nanTx = ledger:createTransaction(1, AGFTransactionType.ADJUSTMENT, 1)
nanTx.amount = 0 / 0
local nanOk, nanError = ledger:post(nanTx)
assertFalse(nanOk, "NaN amount rejected")
assertEqual(nanError, "INVALID_TRANSACTION_AMOUNT", "NaN amount error")

local negativeBreakdown = ledger:createTransaction(1, AGFTransactionType.LOAN_PAYMENT, -100)
negativeBreakdown:setBreakdown(-1, 0, 0)
local negativeOk, negativeError = ledger:post(negativeBreakdown)
assertFalse(negativeOk, "negative breakdown rejected")
assertEqual(negativeError, "NEGATIVE_TRANSACTION_BREAKDOWN", "negative breakdown error")

-- Batch prevalidation is all-or-nothing, including duplicate IDs within the batch.
local batchA = ledger:createTransaction(1, AGFTransactionType.ADJUSTMENT, 10)
local batchB = ledger:createTransaction(1, AGFTransactionType.ADJUSTMENT, 20)
batchB.id = batchA.id
local countBeforeDuplicate = ledger:getTransactionCount()
local duplicateOk, duplicateError = ledger:postBatch({batchA, batchB})
assertFalse(duplicateOk, "duplicate batch ID rejected")
assertEqual(duplicateError, "DUPLICATE_TRANSACTION_ID_IN_BATCH", "duplicate batch error")
assertEqual(ledger:getTransactionCount(), countBeforeDuplicate, "duplicate batch posts nothing")
assertFalse(batchA:isSealed(), "prevalidation failure seals nothing")

-- Build a three-record suffix for rollback tests.
local tx2 = ledger:createTransaction(1, AGFTransactionType.ADJUSTMENT, 200)
local tx3 = ledger:createTransaction(1, AGFTransactionType.ADJUSTMENT, 300)
assertTrue(ledger:postBatch({tx2, tx3}), "two-record batch posts")
assertEqual(ledger:getTransactionCount(), 3, "three records present")

-- Invalid rollback ordering must be rejected before removing any record.
local invalidRollback, invalidRollbackError = ledger:rollbackBatch({tx1.id, tx3.id}, true)
assertFalse(invalidRollback, "non-contiguous rollback rejected")
assertEqual(invalidRollbackError, "ROLLBACK_NOT_AT_LEDGER_TAIL", "rollback suffix error")
assertEqual(ledger:getTransactionCount(), 3, "failed rollback is atomic")
assertTrue(ledger:getTransaction(tx3.id) ~= nil, "tail survives failed rollback")

local rollbackOk, rollbackError = ledger:rollbackBatch({tx2.id, tx3.id}, true)
assertTrue(rollbackOk, "valid tail rollback succeeds: " .. tostring(rollbackError))
assertEqual(ledger:getTransactionCount(), 1, "valid rollback removes suffix")
assertEqual(ledger:getTransaction(tx2.id), nil, "rolled-back transaction removed")
assertEqual(ledger:getTransaction(tx3.id), nil, "rolled-back tail removed")
assertTrue(ledger:getTransaction(tx1.id) ~= nil, "earlier ledger history preserved")

local publicRollbackOk, publicRollbackError = ledger:rollbackBatch({tx1.id}, false)
assertFalse(publicRollbackOk, "public rollback forbidden")
assertEqual(publicRollbackError, "INTERNAL_ROLLBACK_ONLY", "public rollback error")

ledgerRuntime.allowed = false
local blockedTx = ledger:createTransaction(1, AGFTransactionType.ADJUSTMENT, 1)
local blockedPost, blockedPostError = ledger:post(blockedTx)
assertFalse(blockedPost, "runtime blocks ledger post")
assertEqual(blockedPostError, "LEDGER_MUTATION_BLOCKED", "runtime ledger error")
assertEqual(ledger:getTransactionCount(), 1, "blocked post leaves ledger unchanged")

print("offline_core_state_tests: PASS")
