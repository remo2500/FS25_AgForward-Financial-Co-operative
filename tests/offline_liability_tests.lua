-- Offline validation for native liability registry ownership and mutation invariants.

function Class(classTable)
    return {__index = classTable}
end

g_currentMission = nil

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/liabilities/LiabilityRegistry.lua")

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
        return false, "LIABILITY_MUTATION_BLOCKED"
    end
}

local ids = AGFIdService.new()
local registry = AGFLiabilityRegistry.new(ids, runtime)

-- Draft creation does not register authority until explicitly committed.
local draft, draftError = registry:create(1, AGFProductType.CROP_INPUT_LINE, "Crop inputs")
assertEqual(draftError, nil, "draft create error")
assertTrue(draft ~= nil, "draft created")
assertEqual(#registry:getAll(), 0, "draft not registered yet")
draft.creditLimit = 50000
draft.principalBalance = 10000
draft.originalPrincipal = 10000
local registered, stored = registry:register(draft)
assertTrue(registered, "draft registered")
assertEqual(#registry:getAll(), 1, "registered count")
assertEqual(stored.creditLimit, 50000, "stored credit limit")

-- Draft/public copies cannot mutate authoritative balances.
draft.creditLimit = 999999
stored.principalBalance = 999999
assertEqual(registry:get(stored.id).creditLimit, 50000, "draft mutation cannot affect authority")
assertEqual(registry:get(stored.id).principalBalance, 10000, "returned register copy cannot affect authority")
local queried = registry:get(stored.id)
queried.principalBalance = 123
assertEqual(registry:get(stored.id).principalBalance, 10000, "get returns clone")

-- Indexes are deterministic and closed filtering works.
local secondDraft = registry:create(2, AGFProductType.OPERATING_LINE, "Farm two line")
secondDraft.creditLimit = 20000
local secondRegistered, second = registry:register(secondDraft)
assertTrue(secondRegistered, "second liability registered")
assertEqual(#registry:getFarmLiabilities(1, false), 1, "farm one liability count")
assertEqual(#registry:getFarmLiabilities(2, false), 1, "farm two liability count")
assertEqual(#registry:getFarmProductLiabilities(1, AGFProductType.CROP_INPUT_LINE, false), 1, "product index query")
assertEqual(registry:getTotalOutstanding(1), 10000, "farm outstanding total")

-- Draw preflight validates identity, product, lifecycle, and capacity.
local drawOk, drawLiability = registry:canDraw(stored.id, 1, 40000, AGFProductType.CROP_INPUT_LINE)
assertTrue(drawOk, "remaining line can be fully drawn")
assertEqual(drawLiability.id, stored.id, "preflight returns liability copy")
local overOk, overError = registry:canDraw(stored.id, 1, 40000.01, AGFProductType.CROP_INPUT_LINE)
assertFalse(overOk, "over-limit preflight rejected")
assertEqual(overError, "CREDIT_LIMIT_EXCEEDED", "over-limit preflight error")
local farmOk, farmError = registry:canDraw(stored.id, 2, 1, AGFProductType.CROP_INPUT_LINE)
assertFalse(farmOk, "wrong farm rejected")
assertEqual(farmError, "LIABILITY_FARM_MISMATCH", "wrong farm error")
local productOk, productError = registry:canDraw(stored.id, 1, 1, AGFProductType.OPERATING_LINE)
assertFalse(productOk, "wrong product rejected")
assertEqual(productError, "WRONG_PRODUCT_TYPE", "wrong product error")

-- Public mutations remain forbidden so every balance change must be journaled.
local publicDrawOk, publicDrawError = registry:applyDraw(stored.id, 1)
assertFalse(publicDrawOk, "public draw forbidden")
assertEqual(publicDrawError, "OPERATION_COORDINATOR_REQUIRED", "public draw gate")
local publicPayOk, publicPayError = registry:applyPrincipalPayment(stored.id, 1)
assertFalse(publicPayOk, "public payment forbidden")
assertEqual(publicPayError, "OPERATION_COORDINATOR_REQUIRED", "public payment gate")

-- Committed draw rechecks capacity at the mutation boundary.
local committedDrawOk, afterDraw = registry:applyDrawCommitted(stored.id, 5000, true)
assertTrue(committedDrawOk, "committed draw applied")
assertEqual(afterDraw.principalBalance, 15000, "committed draw balance")
local committedOverOk, committedOverError = registry:applyDrawCommitted(stored.id, 35000.01, true)
assertFalse(committedOverOk, "committed overdraw rejected")
assertEqual(committedOverError, "CREDIT_LIMIT_EXCEEDED", "committed overdraw error")
assertEqual(registry:get(stored.id).principalBalance, 15000, "failed overdraw leaves balance")

-- Draw compensation is exact; an oversized compensation may not silently zero debt.
local revertOk, afterRevert = registry:revertDrawCommitted(stored.id, 5000, true)
assertTrue(revertOk, "draw compensation succeeds")
assertEqual(afterRevert.principalBalance, 10000, "draw compensation balance")
local overRevertOk, overRevertError = registry:revertDrawCommitted(stored.id, 10000.01, true)
assertFalse(overRevertOk, "oversized draw compensation rejected")
assertEqual(overRevertError, "DRAW_REVERSION_EXCEEDS_PRINCIPAL", "oversized draw compensation error")
assertEqual(registry:get(stored.id).principalBalance, 10000, "oversized compensation preserves balance")

-- Principal payments apply only to existing principal and return the exact applied amount.
local payOk, applied, afterPay = registry:applyPrincipalPaymentCommitted(stored.id, 2500, true)
assertTrue(payOk, "principal payment applied")
assertEqual(applied, 2500, "exact principal applied")
assertEqual(afterPay.principalBalance, 7500, "principal after payment")
local payoffOk, payoffApplied, afterPayoff = registry:applyPrincipalPaymentCommitted(stored.id, 10000, true)
assertTrue(payoffOk, "oversized payment clips to payoff")
assertEqual(payoffApplied, 7500, "payoff clips to outstanding principal")
assertEqual(afterPayoff.principalBalance, 0, "principal paid off")

-- Compensating payment rollback restores the exact principal movement.
local restoreOk, restored = registry:revertPrincipalPaymentCommitted(stored.id, payoffApplied, true)
assertTrue(restoreOk, "principal-payment rollback succeeds")
assertEqual(restored.principalBalance, 7500, "principal-payment rollback balance")

-- Closed/charged-off records cannot accept normal principal payments or new draws.
registry:getInternal(stored.id).status = AGFLiabilityStatus.CLOSED
local closedPayOk, closedPayError = registry:applyPrincipalPaymentCommitted(stored.id, 1, true)
assertFalse(closedPayOk, "closed liability payment blocked")
assertEqual(closedPayError, "LIABILITY_NOT_OPEN", "closed liability payment error")
local closedDrawOk, closedDrawError = registry:applyDrawCommitted(stored.id, 1, true)
assertFalse(closedDrawOk, "closed liability draw blocked")
assertEqual(closedDrawError, "LIABILITY_NOT_ACTIVE", "closed liability draw error")
assertEqual(#registry:getFarmLiabilities(1, false), 0, "closed liability hidden from open query")
assertEqual(#registry:getFarmLiabilities(1, true), 1, "closed liability retained in history")

-- Runtime authority blocks creation/registration paths used by normal callers.
runtime.allowed = false
local blockedDraft, blockedDraftError = registry:create(1, AGFProductType.TERM_LOAN, "Blocked")
assertEqual(blockedDraft, nil, "blocked runtime returns no draft")
assertEqual(blockedDraftError, "LIABILITY_MUTATION_BLOCKED", "blocked create error")

registry:reset()
assertEqual(#registry:getAll(), 0, "registry reset clears authority")
assertEqual(registry:getTotalOutstanding(1), 0, "registry reset clears totals")

print("offline_liability_tests: PASS")
