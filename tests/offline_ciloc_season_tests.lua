-- Offline validation for seasonal Crop Input Line cycle/cleanup behavior.

dofile("src/core/Currency.lua")
dofile("src/credit/CILOCSeasonService.lua")

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

local base = {
    creditLimit = 200000,
    borrowingBase = 150000,
    principalBalance = 60000,
    reservedAmount = 10000,
    startYear = 2026,
    startPeriod = 2,
    maturityYear = 2027,
    maturityPeriod = 1,
    cleanupWindowPeriods = 2,
    cleanupTargetBalance = 0,
    freezeNewDrawsDuringCleanup = true
}

-- During the growing season, capacity is min(contract limit, borrowing base) less
-- drawn principal and outstanding reservations.
local activeParams = {}
for key, value in pairs(base) do activeParams[key] = value end
activeParams.currentYear = 2026
activeParams.currentPeriod = 7
local activeOk, active = AGFCILOCSeasonService.assess(activeParams)
assertTrue(activeOk, "active season assessment")
assertEqual(active.state, AGFCILOCSeasonState.ACTIVE_SEASON, "active season state")
assertEqual(active.effectiveLimit, 150000, "borrowing base constrains commitment")
assertEqual(active.usedCapacity, 70000, "principal plus reservations uses capacity")
assertEqual(active.baseAvailableCapacity, 80000, "active base availability")
assertEqual(active.availableCapacity, 80000, "active available capacity")
assertFalse(active.drawsFrozen, "active draws not frozen")
assertTrue(active.canAcceptNewDraw, "active season accepts new draw")
assertEqual(active.requiredCleanupPaydown, 60000, "active cleanup paydown projection")
assertFalse(active.cleanupSatisfied, "active line not yet cleaned up")
assertFalse(active.renewalRequired, "active line not at renewal yet")

-- Cleanup window can freeze new input draws while still exposing what must be paid down.
local cleanupParams = {}
for key, value in pairs(base) do cleanupParams[key] = value end
cleanupParams.currentYear = 2026
cleanupParams.currentPeriod = 11
local cleanupOk, cleanup = AGFCILOCSeasonService.assess(cleanupParams)
assertTrue(cleanupOk, "cleanup window assessment")
assertEqual(cleanup.state, AGFCILOCSeasonState.CLEANUP_WINDOW, "cleanup window state")
assertTrue(cleanup.cleanupWindowStarted, "cleanup window flag")
assertTrue(cleanup.drawsFrozen, "cleanup draw freeze")
assertEqual(cleanup.baseAvailableCapacity, 80000, "cleanup underlying capacity preserved")
assertEqual(cleanup.availableCapacity, 0, "cleanup authorization capacity frozen")
assertFalse(cleanup.canAcceptNewDraw, "cleanup cannot accept new draw while frozen")
assertEqual(cleanup.periodsUntilMaturity, 2, "cleanup periods until maturity")

-- Policy can choose not to freeze during cleanup; maturity still freezes by default.
cleanupParams.freezeNewDrawsDuringCleanup = false
local openCleanupOk, openCleanup = AGFCILOCSeasonService.assess(cleanupParams)
assertTrue(openCleanupOk, "open cleanup assessment")
assertFalse(openCleanup.drawsFrozen, "cleanup not frozen by policy")
assertEqual(openCleanup.availableCapacity, 80000, "cleanup capacity available under policy")
assertTrue(openCleanup.canAcceptNewDraw, "cleanup draw allowed by policy")

local maturityParams = {}
for key, value in pairs(base) do maturityParams[key] = value end
maturityParams.currentYear = 2027
maturityParams.currentPeriod = 1
local maturityOk, maturity = AGFCILOCSeasonService.assess(maturityParams)
assertTrue(maturityOk, "maturity assessment")
assertEqual(maturity.state, AGFCILOCSeasonState.MATURED, "maturity state")
assertEqual(maturity.periodsUntilMaturity, 0, "maturity countdown zero")
assertTrue(maturity.drawsFrozen, "maturity draws frozen")
assertEqual(maturity.availableCapacity, 0, "maturity available capacity zero")
assertTrue(maturity.renewalRequired, "unclean balance requires renewal/workout decision")
assertEqual(maturity.requiredCleanupPaydown, 60000, "maturity cleanup paydown")
assertFalse(maturity.canAcceptNewDraw, "matured line cannot accept new draw")

-- A cleaned-up line reaches maturity without a residual renewal balance.
local cleanParams = {}
for key, value in pairs(base) do cleanParams[key] = value end
cleanParams.currentYear = 2027
cleanParams.currentPeriod = 1
cleanParams.principalBalance = 0
cleanParams.reservedAmount = 0
local cleanOk, clean = AGFCILOCSeasonService.assess(cleanParams)
assertTrue(cleanOk, "clean maturity assessment")
assertTrue(clean.cleanupSatisfied, "cleanup target satisfied")
assertEqual(clean.requiredCleanupPaydown, 0, "no cleanup paydown remains")
assertFalse(clean.renewalRequired, "clean line has no balance requiring renewal")

-- A non-zero cleanup target supports policies that require a seasonal reduction
-- rather than complete zero balance.
local targetParams = {}
for key, value in pairs(base) do targetParams[key] = value end
targetParams.currentYear = 2026
targetParams.currentPeriod = 11
targetParams.cleanupTargetBalance = 25000
targetParams.principalBalance = 40000
local targetOk, target = AGFCILOCSeasonService.assess(targetParams)
assertTrue(targetOk, "non-zero cleanup target assessment")
assertEqual(target.requiredCleanupPaydown, 15000, "paydown to cleanup target")
assertFalse(target.cleanupSatisfied, "target not yet satisfied")
targetParams.principalBalance = 25000
local targetSatisfiedOk, targetSatisfied = AGFCILOCSeasonService.assess(targetParams)
assertTrue(targetSatisfiedOk, "cleanup target satisfied assessment")
assertTrue(targetSatisfied.cleanupSatisfied, "non-zero target satisfied")
assertEqual(targetSatisfied.requiredCleanupPaydown, 0, "no paydown after target met")

-- Borrowing-base deterioration can create an over-advance condition independently
-- of contractual credit limit.
local overAdvanceParams = {}
for key, value in pairs(base) do overAdvanceParams[key] = value end
overAdvanceParams.currentYear = 2026
overAdvanceParams.currentPeriod = 8
overAdvanceParams.borrowingBase = 50000
overAdvanceParams.principalBalance = 60000
overAdvanceParams.reservedAmount = 5000
local overAdvanceOk, overAdvance = AGFCILOCSeasonService.assess(overAdvanceParams)
assertTrue(overAdvanceOk, "over-advance assessment")
assertEqual(overAdvance.effectiveLimit, 50000, "deteriorated borrowing base effective limit")
assertEqual(overAdvance.usedCapacity, 65000, "over-advance used capacity")
assertEqual(overAdvance.overEffectiveLimit, 15000, "over-advance amount")
assertEqual(overAdvance.baseAvailableCapacity, 0, "over-advance no capacity")
assertFalse(overAdvance.canAcceptNewDraw, "over-advance cannot draw")

-- With no borrowing base, contractual limit is the effective limit.
local noBaseParams = {}
for key, value in pairs(base) do noBaseParams[key] = value end
noBaseParams.borrowingBase = nil
noBaseParams.currentYear = 2026
noBaseParams.currentPeriod = 7
local noBaseOk, noBase = AGFCILOCSeasonService.assess(noBaseParams)
assertTrue(noBaseOk, "no borrowing-base assessment")
assertEqual(noBase.effectiveLimit, 200000, "contractual limit without borrowing base")
assertEqual(noBase.availableCapacity, 130000, "contractual capacity less used")

-- Maturity freeze can be disabled only as an explicit policy input; the state still
-- remains matured and therefore canAcceptNewDraw remains false.
local maturityOpenParams = {}
for key, value in pairs(base) do maturityOpenParams[key] = value end
maturityOpenParams.currentYear = 2027
maturityOpenParams.currentPeriod = 1
maturityOpenParams.freezeNewDrawsAtMaturity = false
local maturityOpenOk, maturityOpen = AGFCILOCSeasonService.assess(maturityOpenParams)
assertTrue(maturityOpenOk, "maturity-open assessment")
assertFalse(maturityOpen.drawsFrozen, "maturity freeze flag can be disabled")
assertEqual(maturityOpen.availableCapacity, 80000, "underlying matured capacity can still be reported")
assertFalse(maturityOpen.canAcceptNewDraw, "matured state never authorizes new draw")

-- Invalid chronology and numeric context are explicit failures.
local badStartParams = {}
for key, value in pairs(base) do badStartParams[key] = value end
badStartParams.startYear = 2027
badStartParams.startPeriod = 1
badStartParams.maturityYear = 2027
badStartParams.maturityPeriod = 1
badStartParams.currentYear = 2027
badStartParams.currentPeriod = 1
local badStartOk, badStartError = AGFCILOCSeasonService.assess(badStartParams)
assertFalse(badStartOk, "maturity must follow season start")
assertEqual(badStartError, "MATURITY_MUST_FOLLOW_START", "maturity chronology error")

local beforeStartParams = {}
for key, value in pairs(base) do beforeStartParams[key] = value end
beforeStartParams.currentYear = 2026
beforeStartParams.currentPeriod = 1
local beforeStartOk, beforeStartError = AGFCILOCSeasonService.assess(beforeStartParams)
assertFalse(beforeStartOk, "current before season start rejected")
assertEqual(beforeStartError, "CURRENT_PERIOD_BEFORE_SEASON_START", "current before start error")

local invalidPeriodParams = {}
for key, value in pairs(base) do invalidPeriodParams[key] = value end
invalidPeriodParams.currentYear = 2026
invalidPeriodParams.currentPeriod = 13
local invalidPeriodOk, invalidPeriodError = AGFCILOCSeasonService.assess(invalidPeriodParams)
assertFalse(invalidPeriodOk, "invalid current period rejected")
assertEqual(invalidPeriodError, "INVALID_CURRENT_PERIOD", "invalid current period error")

local invalidLimitParams = {}
for key, value in pairs(base) do invalidLimitParams[key] = value end
invalidLimitParams.currentYear = 2026
invalidLimitParams.currentPeriod = 7
invalidLimitParams.creditLimit = 0 / 0
local invalidLimitOk, invalidLimitError = AGFCILOCSeasonService.assess(invalidLimitParams)
assertFalse(invalidLimitOk, "NaN credit limit rejected")
assertEqual(invalidLimitError, "INVALID_CREDIT_LIMIT", "NaN credit limit error")

print("offline_ciloc_season_tests: PASS")
