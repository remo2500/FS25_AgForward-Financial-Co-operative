-- Offline validation for the Phase-0 settlement marker, compatibility warnings,
-- and intentionally non-invasive Red Tape detection.

function Class(classTable)
    return {__index = classTable}
end

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

-- Minimal XML stand-in for settlement marker persistence.
function setXMLInt(xmlFile, key, value) xmlFile[key] = value end
function setXMLString(xmlFile, key, value) xmlFile[key] = value end
function getXMLString(xmlFile, key) return xmlFile[key] end

local runtime = {
    allowed = true,
    issues = {},
    canMutate = function(self)
        if self.allowed then return true, nil end
        return false, "RUNTIME_BLOCKED"
    end,
    addIssue = function(self, code, message, severity)
        table.insert(self.issues, {code = code, message = message, severity = severity})
    end
}

local services = {
    get = function(self, name)
        if name == "runtimeState" then return runtime end
        return nil
    end
}

g_currentMission = {environment = {currentYear = 2026, currentPeriod = 9}}
g_modIsLoaded = nil

dofile("src/settlement/SettlementCoordinator.lua")
dofile("src/core/CompatibilityService.lua")
dofile("src/integrations/RedTapeAdapter.lua")

-- Phase 0 settlement is a no-money idempotency marker only.
local settlement = AGFSettlementCoordinator.new(services)
assertEqual(AGFSettlementCoordinator.ENGINE_VERSION, 0, "Phase 0 settlement engine version")
assertEqual(settlement:getSettlementKey(), "v0:2026:9", "settlement key")
local firstOk, firstStatus = settlement:runPeriodSettlement()
assertTrue(firstOk, "first Phase 0 settlement marker succeeds")
assertEqual(firstStatus, "COMPLETED", "first settlement status")
assertEqual(settlement.lastCompletedSettlementKey, "v0:2026:9", "completed marker")

local secondOk, secondStatus = settlement:runPeriodSettlement()
assertTrue(secondOk, "duplicate period settlement is harmless")
assertEqual(secondStatus, "ALREADY_COMPLETED", "duplicate settlement status")

-- A later financial period receives its own marker.
g_currentMission.environment.currentPeriod = 10
local laterOk, laterStatus = settlement:runPeriodSettlement()
assertTrue(laterOk, "next period marker succeeds")
assertEqual(laterStatus, "COMPLETED", "next period status")
assertEqual(settlement.lastCompletedSettlementKey, "v0:2026:10", "next period marker")

-- Reentrancy is explicitly blocked even before a money-moving engine exists.
settlement.inProgressSettlementKey = "v0:2026:10"
g_currentMission.environment.currentPeriod = 11
local concurrentOk, concurrentError = settlement:runPeriodSettlement()
assertFalse(concurrentOk, "concurrent settlement rejected")
assertEqual(concurrentError, "SETTLEMENT_ALREADY_IN_PROGRESS", "concurrent settlement error")
settlement.inProgressSettlementKey = nil

-- Runtime authority and missing mission context fail closed.
runtime.allowed = false
local blockedOk, blockedError = settlement:runPeriodSettlement()
assertFalse(blockedOk, "runtime blocks settlement")
assertEqual(blockedError, "RUNTIME_BLOCKED", "settlement runtime error")
runtime.allowed = true

local savedMission = g_currentMission
g_currentMission = nil
assertEqual(settlement:getSettlementKey(), nil, "settlement key unavailable without mission")
local noMissionOk, noMissionError = settlement:runPeriodSettlement()
assertFalse(noMissionOk, "settlement without mission rejected")
assertEqual(noMissionError, "SETTLEMENT_KEY_UNAVAILABLE", "no mission settlement error")
g_currentMission = savedMission

-- Completion marker persists and in-progress state deliberately does not.
settlement.lastCompletedSettlementKey = "v0:2026:10"
settlement.inProgressSettlementKey = "transient"
local xml = {}
settlement:saveToXMLFile(xml, "settlement")
assertEqual(xml["settlement#engineVersion"], 0, "saved engine version")
assertEqual(xml["settlement#lastCompletedKey"], "v0:2026:10", "saved completion key")

local reloadedSettlement = AGFSettlementCoordinator.new(services)
reloadedSettlement.inProgressSettlementKey = "old-transient"
reloadedSettlement:loadFromXMLFile(xml, "settlement")
assertEqual(reloadedSettlement.lastCompletedSettlementKey, "v0:2026:10", "completion key restored")
assertEqual(reloadedSettlement.inProgressSettlementKey, nil, "in-progress marker never restored")
reloadedSettlement:reset()
assertEqual(reloadedSettlement.lastCompletedSettlementKey, nil, "settlement reset clears completion")

-- Known overlapping finance mods generate warnings; Red Tape is intentionally excluded.
runtime.issues = {}
g_modIsLoaded = {
    FS25_BankCredit = true,
    FS25_FinanceYourFleet = true,
    FS25_RedTape = true
}
local compatibility = AGFCompatibilityService.new(runtime)
local overlaps = compatibility:detect()
assertEqual(#overlaps, 2, "two overlapping finance mods detected")
assertEqual(overlaps[1], "FS25_BankCredit", "first overlap order")
assertEqual(overlaps[2], "FS25_FinanceYourFleet", "second overlap order")
assertEqual(#runtime.issues, 2, "overlap warnings recorded")
assertEqual(runtime.issues[1].severity, "warning", "overlap is warning, not safe-mode error")

local overlapCopy = compatibility:getDetectedOverlaps()
overlapCopy[1] = "mutated"
assertEqual(compatibility:getDetectedOverlaps()[1], "FS25_BankCredit", "overlap query returns copy")

-- Red Tape detection is deliberately degraded/non-invasive until transaction-by-
-- transaction runtime reconciliation proves the adapter can avoid double counting.
local redTape = AGFRedTapeAdapter.new()
local redTapeStatus = redTape:detect()
assertTrue(redTape:isInstalled(), "Red Tape detected")
assertEqual(redTapeStatus, AGFRedTapeAdapter.STATUS_DEGRADED, "Red Tape remains degraded in Phase 0")
assertEqual(redTape:getStatus(), AGFRedTapeAdapter.STATUS_DEGRADED, "Red Tape status readable")

-- Red Tape absence is normal and does not affect AgForward authority.
g_modIsLoaded = {}
local absentStatus = redTape:detect()
assertFalse(redTape:isInstalled(), "Red Tape absence detected")
assertEqual(absentStatus, AGFRedTapeAdapter.STATUS_NOT_INSTALLED, "Red Tape absent status")

-- Missing mod table is also safe.
g_modIsLoaded = nil
local noTableStatus = redTape:detect()
assertEqual(noTableStatus, AGFRedTapeAdapter.STATUS_NOT_INSTALLED, "missing mod table safe")
local noTableOverlaps = compatibility:detect()
assertEqual(#noTableOverlaps, 0, "missing mod table yields no false overlaps")

print("offline_runtime_foundation_tests: PASS")
