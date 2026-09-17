-- Offline validation for the future read-only Phase-0 diagnostic view model.

function Class(base)
    local class = {}
    class.__index = class
    return class
end

dofile("src/core/Currency.lua")
dofile("src/core/RuntimeStateService.lua")
dofile("src/integrations/RedTapeAdapter.lua")
dofile("src/settlement/SettlementCoordinator.lua")
dofile("src/reporting/DiagnosticSnapshotService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local function makeRuntime(state, issues, reason)
    return {
        reason = reason,
        getState = function() return state end,
        getIssues = function() return issues or {} end
    }
end

local compatibility = {
    detected = {},
    getDetectedOverlaps = function(self)
        local copy = {}
        for _, item in ipairs(self.detected) do table.insert(copy, item) end
        return copy
    end
}

local redTape = {
    status = AGFRedTapeAdapter.STATUS_NOT_INSTALLED,
    getStatus = function(self) return self.status end
}

local liabilityRegistry = {
    getFarmLiabilities = function(self, farmId, includeClosed)
        if farmId ~= 7 then return {} end
        return {
            {
                id = "AGF-LIAB-000002",
                productType = "equipmentFinance",
                status = "active",
                principalBalance = 90000,
                accruedInterest = 1000,
                accruedFees = 250,
                getOutstandingBalance = function(self)
                    return self.principalBalance + self.accruedInterest + self.accruedFees
                end
            },
            {
                id = "AGF-LIAB-000001",
                productType = "cropInputLine",
                status = "active",
                principalBalance = 40000,
                accruedInterest = 500,
                accruedFees = 0,
                getOutstandingBalance = function(self)
                    return self.principalBalance + self.accruedInterest + self.accruedFees
                end
            }
        }
    end
}

local ledger = {
    getFarmTransactions = function(self, farmId)
        if farmId ~= 7 then return {} end
        return {
            {id = "AGF-TX-000001", groupId = "AGF-GRP-000001", transactionType = "creditDraw", amount = 40000, liabilityId = "AGF-LIAB-000001", year = 1, period = 2},
            {id = "AGF-TX-000002", groupId = "AGF-GRP-000001", transactionType = "inputPurchase", amount = -40000, expenseCategory = "fertilizer", year = 1, period = 2},
            {id = "AGF-TX-000003", groupId = "AGF-GRP-000002", transactionType = "interestPayment", amount = -500, liabilityId = "AGF-LIAB-000001", year = 1, period = 3}
        }
    end
}

local settlement = {
    lastCompletedSettlementKey = "v0:1:2",
    inProgressSettlementKey = nil
}

local service = AGFDiagnosticSnapshotService.new(
    makeRuntime(AGFRuntimeState.NORMAL, {}),
    compatibility,
    redTape,
    liabilityRegistry,
    ledger,
    settlement
)

local snapshot = service:build(7, {
    buildVersion = "0.0.4.0",
    schemaVersion = 3,
    saveGeneration = 12,
    recentTransactionLimit = 2,
    serverAuthority = true,
    persistenceSource = "primary"
})
assertEqual(snapshot.runtimeState, AGFRuntimeState.NORMAL, "runtime state")
assertEqual(snapshot.health, "normal", "normal health")
assertTrue(snapshot.writable, "normal state writable")
assertEqual(snapshot.liabilityCount, 2, "liability count")
assertEqual(snapshot.totalOutstanding, 131750, "outstanding debt total")
assertEqual(snapshot.liabilities[1].id, "AGF-LIAB-000001", "liabilities sorted")
assertEqual(snapshot.transactionCount, 3, "transaction count")
assertEqual(#snapshot.recentTransactions, 2, "recent transaction limit")
assertEqual(snapshot.recentTransactions[1].id, "AGF-TX-000003", "newest transaction first")
assertEqual(snapshot.settlement.lastCompletedKey, "v0:1:2", "settlement marker")
assertEqual(snapshot.schemaVersion, 3, "schema surfaced")

-- Overlap and degraded Red Tape should show warning without fabricating an error.
compatibility.detected = {"FS25_BankCredit"}
redTape.status = AGFRedTapeAdapter.STATUS_DEGRADED
local warningService = AGFDiagnosticSnapshotService.new(
    makeRuntime(AGFRuntimeState.RECOVERED, {{code = "RECOVERED_COPY", message = "Loaded recovery copy", severity = "warning"}}),
    compatibility,
    redTape,
    liabilityRegistry,
    ledger,
    settlement
)
local warning = warningService:build(7, {})
assertEqual(warning.health, "warning", "warning health")
assertTrue(warning.writable, "recovered state remains writable")
assertEqual(#warning.overlappingFinanceMods, 1, "overlap surfaced")
assertEqual(warning.redTapeStatus, AGFRedTapeAdapter.STATUS_DEGRADED, "Red Tape status surfaced")

-- Safe mode is read-only and always presented as an error state.
compatibility.detected = {}
redTape.status = AGFRedTapeAdapter.STATUS_NOT_INSTALLED
local safeService = AGFDiagnosticSnapshotService.new(
    makeRuntime(
        AGFRuntimeState.READ_ONLY_SAFE_MODE,
        {{code = "SAVE_CORRUPT", message = "No valid financial copy", severity = "error"}},
        "SAVE_CORRUPT"
    ),
    compatibility,
    redTape,
    liabilityRegistry,
    ledger,
    settlement
)
local safe = safeService:build(7, {serverAuthority = true})
assertEqual(safe.health, "error", "safe mode health")
assertTrue(not safe.writable, "safe mode not writable")
assertEqual(safe.runtimeReason, "SAVE_CORRUPT", "safe mode reason")
assertEqual(#safe.issues, 1, "safe mode issue")

print("offline_diagnostic_snapshot_tests: PASS")
