-- Offline validation for configurable credit covenant monitoring.

dofile("src/credit/CovenantMonitoringService.lua")

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

local covenants = {
    name = "example-monitoring-set",
    version = "1",
    rules = {
        {id = "dscr", metric = "dscr", comparator = "min", value = 1.20, severity = AGFCovenantSeverity.BREACH},
        {id = "leverage", metric = "debtToAssets", comparator = "max", value = 0.65, severity = AGFCovenantSeverity.WARNING},
        {id = "cleanup", metric = "cleanupSatisfied", comparator = "eq", value = true, severity = AGFCovenantSeverity.BREACH},
        {id = "workingCapital", metric = "workingCapital", comparator = "min", value = 50000, severity = AGFCovenantSeverity.WARNING},
        {id = "liquidity", metric = "liquidityCoverage", comparator = "min", value = 1.0, severity = AGFCovenantSeverity.WARNING, missingBehavior = "warning"}
    }
}

local compliantOk, compliant = AGFCovenantMonitoringService.evaluate({
    dscr = 1.55,
    debtToAssets = 0.50,
    cleanupSatisfied = true,
    workingCapital = 100000,
    liquidityCoverage = 1.4
}, covenants, {asOfYear = 10, asOfPeriod = 12})
assertTrue(compliantOk, "compliant review succeeds")
assertEqual(compliant.status, AGFCovenantStatus.COMPLIANT, "compliant status")
assertTrue(compliant.compliant, "compliant boolean")
assertFalse(compliant.reviewRequired, "compliant review needs no exception review")
assertEqual(#compliant.passed, 5, "all rules pass")
assertEqual(compliant.asOfYear, 10, "review year retained")

-- Warning conditions do not become automatic default/breach.
local warningOk, warning = AGFCovenantMonitoringService.evaluate({
    dscr = 1.30,
    debtToAssets = 0.70,
    cleanupSatisfied = true,
    workingCapital = 40000,
    liquidityCoverage = 1.2
}, covenants, {})
assertTrue(warningOk, "warning review succeeds")
assertEqual(warning.status, AGFCovenantStatus.WARNING, "warning status")
assertEqual(#warning.warnings, 2, "two warnings")
assertEqual(#warning.breaches, 0, "warnings are not breaches")
assertTrue(warning.reviewRequired, "warning review required")

-- A true covenant breach is surfaced distinctly.
local breachOk, breach = AGFCovenantMonitoringService.evaluate({
    dscr = 1.10,
    debtToAssets = 0.55,
    cleanupSatisfied = false,
    workingCapital = 100000,
    liquidityCoverage = 1.2
}, covenants, {})
assertTrue(breachOk, "breach review succeeds")
assertEqual(breach.status, AGFCovenantStatus.BREACH, "breach status")
assertEqual(#breach.breaches, 2, "DSCR and cleanup breaches")
assertTrue(breach.reviewRequired, "breach review required")

-- Missing values follow explicit missing-data behavior rather than being invented.
local missingOk, missing = AGFCovenantMonitoringService.evaluate({
    dscr = 1.5,
    debtToAssets = 0.50,
    cleanupSatisfied = true,
    workingCapital = 75000
}, covenants, {})
assertTrue(missingOk, "missing-value review succeeds")
assertEqual(#missing.missing, 1, "one missing metric")
assertEqual(#missing.warnings, 1, "missing liquidity is warning")
assertEqual(missing.status, AGFCovenantStatus.WARNING, "missing warning status")

local strictMissingOk, strictMissing = AGFCovenantMonitoringService.evaluate({}, {
    rules = {
        {id = "mustKnow", metric = "requiredMetric", comparator = "min", value = 1, missingBehavior = "breach"}
    }
}, {})
assertTrue(strictMissingOk, "strict missing review evaluates")
assertEqual(strictMissing.status, AGFCovenantStatus.BREACH, "missing-required value is breach")
assertEqual(#strictMissing.breaches, 1, "missing breach recorded")

local ignoredMissingOk, ignoredMissing = AGFCovenantMonitoringService.evaluate({}, {
    rules = {
        {id = "optional", metric = "optionalMetric", comparator = "min", value = 1, missingBehavior = "ignore"}
    }
}, {})
assertTrue(ignoredMissingOk, "ignored missing evaluates")
assertEqual(ignoredMissing.status, AGFCovenantStatus.INCOMPLETE, "ignored missing still documents incomplete data")
assertEqual(#ignoredMissing.warnings, 0, "ignored missing not warning")
assertEqual(#ignoredMissing.breaches, 0, "ignored missing not breach")

-- Review comparison identifies new, cured and continuing exceptions.
local previousOk, previous = AGFCovenantMonitoringService.evaluate({
    dscr = 1.10,
    debtToAssets = 0.70,
    cleanupSatisfied = true,
    workingCapital = 100000,
    liquidityCoverage = 1.2
}, covenants, {})
assertTrue(previousOk, "previous review")

local currentOk, current = AGFCovenantMonitoringService.evaluate({
    dscr = 1.30,
    debtToAssets = 0.70,
    cleanupSatisfied = false,
    workingCapital = 100000,
    liquidityCoverage = 1.2
}, covenants, {})
assertTrue(currentOk, "current review")

local compareOk, comparison = AGFCovenantMonitoringService.compareReviews(previous, current)
assertTrue(compareOk, "review comparison succeeds")
assertEqual(#comparison.newExceptions, 1, "cleanup is new exception")
assertEqual(comparison.newExceptions[1].id, "cleanup", "new cleanup exception")
assertEqual(#comparison.curedExceptions, 1, "DSCR is cured")
assertEqual(comparison.curedExceptions[1].id, "dscr", "cured DSCR exception")
assertEqual(#comparison.continuingExceptions, 1, "leverage continues")
assertEqual(comparison.continuingExceptions[1].id, "leverage", "continuing leverage warning")

-- Invalid policy definitions fail closed.
local badComparatorOk, badComparatorError = AGFCovenantMonitoringService.evaluate({x = 1}, {
    rules = {{id = "bad", metric = "x", comparator = "around", value = 1}}
}, {})
assertFalse(badComparatorOk, "bad comparator rejected")
assertEqual(badComparatorError, "INVALID_COVENANT_COMPARATOR:bad", "bad comparator error")

local badThresholdOk, badThresholdError = AGFCovenantMonitoringService.evaluate({x = 1}, {
    rules = {{id = "bad", metric = "x", comparator = "min", value = 0/0}}
}, {})
assertFalse(badThresholdOk, "non-finite threshold rejected")
assertEqual(badThresholdError, "INVALID_COVENANT_THRESHOLD:bad", "bad threshold error")

print("offline_covenant_monitoring_tests: PASS")
