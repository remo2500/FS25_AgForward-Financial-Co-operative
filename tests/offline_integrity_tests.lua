-- Offline validation for post-load/pre-save financial integrity rules.

function Class(classTable)
    return {__index = classTable}
end

g_currentMission = nil
g_farmManager = nil

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/ledger/Transaction.lua")
dofile("src/ledger/Ledger.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/liabilities/LiabilityRegistry.lua")
dofile("src/core/IntegrityService.lua")

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

local function hasCode(items, code)
    for _, item in ipairs(items or {}) do
        if item.code == code then return true end
    end
    return false
end

local runtime = {canMutate = function() return true, nil end}

local function buildCore()
    local ids = AGFIdService.new()
    local ledger = AGFLedger.new(ids, runtime)
    local liabilities = AGFLiabilityRegistry.new(ids, runtime)
    local services = {
        get = function(self, name)
            if name == "idService" then return ids end
            if name == "ledger" then return ledger end
            if name == "liabilities" then return liabilities end
            return nil
        end
    }
    local integrity = AGFIntegrityService.new(services)
    return ids, ledger, liabilities, integrity
end

local function addHealthyLine(liabilities, idOverride)
    local draft = AGFLiability.new(idOverride or "AGF-LIAB-000010", 1, AGFProductType.CROP_INPUT_LINE)
    draft.status = AGFLiabilityStatus.ACTIVE
    draft.originalPrincipal = 10000
    draft.principalBalance = 10000
    draft.creditLimit = 50000
    draft.accruedInterest = 100
    draft.accruedFees = 25
    draft.interestRate = 0.06
    draft.termMonths = 12
    draft.remainingTermMonths = 10
    draft.scheduledPayment = 500
    draft.balloonAmount = 0
    draft.startYear = 2026
    draft.startPeriod = 3
    draft.nextPaymentYear = 2026
    draft.nextPaymentPeriod = 4
    local registered = liabilities:register(draft, true)
    assertTrue(registered, "healthy liability registered")
    return draft.id
end

local function addBalancedGroup(ledger, liabilityId)
    local draw = AGFTransaction.new("AGF-TX-000020", 1, AGFTransactionType.CREDIT_DRAW, 2500)
    draw:setGroupId("AGF-GRP-000030")
    draw:setLiabilityId(liabilityId)
    draw:setFundingSource(AGFFundingSource.CROP_INPUT_LINE)
    draw:setMetadata("economicRole", "financing")
    draw:setPeriod(2026, 4)

    local expense = AGFTransaction.new("AGF-TX-000021", 1, AGFTransactionType.INPUT_PURCHASE, -2500)
    expense:setGroupId("AGF-GRP-000030")
    expense:setLiabilityId(liabilityId)
    expense:setFundingSource(AGFFundingSource.CROP_INPUT_LINE)
    expense:setExpenseCategory(AGFExpenseCategory.FERTILIZER)
    expense:setMetadata("economicRole", "expense")
    expense:setPeriod(2026, 4)

    local posted, postError = ledger:postBatch({draw, expense}, true)
    assertTrue(posted, "healthy group posted: " .. tostring(postError))
end

-- Healthy authoritative state passes and observed IDs advance counters.
local ids, ledger, liabilities, integrity = buildCore()
local lineId = addHealthyLine(liabilities)
addBalancedGroup(ledger, lineId)
local valid, report = integrity:run(3)
assertTrue(valid, "healthy state passes integrity")
assertEqual(#report.errors, 0, "healthy state has no errors")
assertEqual(report.liabilityCount, 1, "healthy liability count")
assertEqual(report.transactionCount, 2, "healthy transaction count")
assertTrue(ids:getCounter("LIAB") >= 10, "liability ID observed")
assertTrue(ids:getCounter("TX") >= 21, "transaction IDs observed")
assertTrue(ids:getCounter("GRP") >= 30, "group IDs observed")

-- Unknown liability status is fatal rather than silently becoming active.
local _, _, statusLiabilities, statusIntegrity = buildCore()
local statusId = addHealthyLine(statusLiabilities)
statusLiabilities:getInternal(statusId).status = "mysteryStatus"
local statusValid, statusReport = statusIntegrity:run(3)
assertFalse(statusValid, "unknown liability status rejected")
assertTrue(hasCode(statusReport.errors, "LIABILITY_STATUS_UNKNOWN"), "unknown status error present")

-- Negative liability values are rejected across principal/accrual/payment fields.
local _, _, negativeLiabilities, negativeIntegrity = buildCore()
local negativeId = addHealthyLine(negativeLiabilities)
negativeLiabilities:getInternal(negativeId).accruedInterest = -1
local negativeValid, negativeReport = negativeIntegrity:run(3)
assertFalse(negativeValid, "negative accrued interest rejected")
assertTrue(hasCode(negativeReport.errors, "LIABILITY_NEGATIVE_VALUE"), "negative value error present")

-- Revolver utilization above the contractual limit is fatal.
local _, _, limitLiabilities, limitIntegrity = buildCore()
local limitId = addHealthyLine(limitLiabilities)
limitLiabilities:getInternal(limitId).principalBalance = 50000.01
local limitValid, limitReport = limitIntegrity:run(3)
assertFalse(limitValid, "revolver over-limit state rejected")
assertTrue(hasCode(limitReport.errors, "REVOLVING_LIMIT_EXCEEDED"), "revolver limit error present")

-- Term metadata must be internally coherent.
local _, _, termLiabilities, termIntegrity = buildCore()
local termId = addHealthyLine(termLiabilities)
termLiabilities:getInternal(termId).remainingTermMonths = 13
local termValid, termReport = termIntegrity:run(3)
assertFalse(termValid, "remaining term above original rejected")
assertTrue(hasCode(termReport.errors, "LIABILITY_REMAINING_TERM_EXCEEDS_ORIGINAL"), "remaining term error present")

local _, _, periodLiabilities, periodIntegrity = buildCore()
local periodId = addHealthyLine(periodLiabilities)
periodLiabilities:getInternal(periodId).nextPaymentPeriod = 13
local periodValid, periodReport = periodIntegrity:run(3)
assertFalse(periodValid, "invalid payment period rejected")
assertTrue(hasCode(periodReport.errors, "LIABILITY_PERIOD_INVALID"), "liability period error present")

-- Authoritative ledger records must remain sealed.
local _, unsealedLedger, unsealedLiabilities, unsealedIntegrity = buildCore()
local unsealedLine = addHealthyLine(unsealedLiabilities)
addBalancedGroup(unsealedLedger, unsealedLine)
unsealedLedger:getAllTransactionsInternal()[1]._sealed = false
local unsealedValid, unsealedReport = unsealedIntegrity:run(3)
assertFalse(unsealedValid, "unsealed authoritative transaction rejected")
assertTrue(hasCode(unsealedReport.errors, "TRANSACTION_NOT_SEALED"), "unsealed transaction error present")

-- Negative breakdown components are invalid even when the signed transaction amount is valid.
local _, breakdownLedger, breakdownLiabilities, breakdownIntegrity = buildCore()
local breakdownLine = addHealthyLine(breakdownLiabilities)
addBalancedGroup(breakdownLedger, breakdownLine)
breakdownLedger:getAllTransactionsInternal()[1].interest = -0.01
local breakdownValid, breakdownReport = breakdownIntegrity:run(3)
assertFalse(breakdownValid, "negative transaction component rejected")
assertTrue(hasCode(breakdownReport.errors, "TRANSACTION_BREAKDOWN_NEGATIVE"), "negative component error present")

-- A funding/expense group that does not net to zero is fatal.
local _, unbalancedLedger, unbalancedLiabilities, unbalancedIntegrity = buildCore()
local unbalancedLine = addHealthyLine(unbalancedLiabilities)
addBalancedGroup(unbalancedLedger, unbalancedLine)
unbalancedLedger:getAllTransactionsInternal()[2].amount = -2400
local unbalancedValid, unbalancedReport = unbalancedIntegrity:run(3)
assertFalse(unbalancedValid, "unbalanced linked group rejected")
assertTrue(hasCode(unbalancedReport.errors, "GROUP_NOT_BALANCED"), "group balance error present")

-- Missing liability references are fatal for schema v2+ but remain a legacy warning for v1.
local _, orphanLedger, orphanLiabilities, orphanIntegrity = buildCore()
local orphan = AGFTransaction.new("AGF-TX-000050", 1, AGFTransactionType.PRINCIPAL_PAYMENT, -100)
orphan:setLiabilityId("AGF-LIAB-999999")
assertTrue(orphanLedger:post(orphan, true), "orphan test transaction posted")
local orphanValid, orphanReport = orphanIntegrity:run(3)
assertFalse(orphanValid, "schema 3 orphan rejected")
assertTrue(hasCode(orphanReport.errors, "ORPHAN_LIABILITY_REFERENCE"), "schema 3 orphan error present")

local legacyValid, legacyReport = orphanIntegrity:run(1)
assertTrue(legacyValid, "schema 1 orphan remains loadable")
assertTrue(hasCode(legacyReport.warnings, "LEGACY_LIABILITY_REFERENCE"), "schema 1 orphan warning present")

-- Unknown funding/category values are preserved as warnings for forward compatibility.
local _, warningLedger, warningLiabilities, warningIntegrity = buildCore()
local warningLine = addHealthyLine(warningLiabilities)
local warningTx = AGFTransaction.new("AGF-TX-000060", 1, AGFTransactionType.ADJUSTMENT, 0)
warningTx:setFundingSource("futureFundingSource")
warningTx:setExpenseCategory("futureExpenseCategory")
assertTrue(warningLedger:post(warningTx, true), "warning test transaction posted")
local warningValid, warningReport = warningIntegrity:run(3)
assertTrue(warningValid, "unknown descriptive taxonomy remains nonfatal")
assertTrue(hasCode(warningReport.warnings, "FUNDING_SOURCE_UNKNOWN"), "unknown funding warning present")
assertTrue(hasCode(warningReport.warnings, "EXPENSE_CATEGORY_UNKNOWN"), "unknown category warning present")

print("offline_integrity_tests: PASS")
