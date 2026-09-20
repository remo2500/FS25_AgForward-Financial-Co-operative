-- Offline validation for future Crop Input Line borrowing-base and harvest-sweep policy.

dofile("src/core/Currency.lua")
dofile("src/credit/CILOCBorrowingBaseService.lua")
dofile("src/credit/HarvestSweepService.lua")

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

-- 2,000 acres wheat at $120/ac + 1,000 acres canola at $180/ac = $420k budget.
-- Both fully eligible, 75% advance -> $315k CILOC borrowing base.
local baseOk, borrowingBase = AGFCILOCBorrowingBaseService.calculate({
    {crop = "wheat", acres = 2000, costPerAcre = 120, eligibilityPercent = 1},
    {crop = "canola", acres = 1000, costPerAcre = 180, eligibilityPercent = 1}
}, {
    advanceRate = 0.75,
    adjustmentFactor = 1
})
assertTrue(baseOk, "borrowing base calculated")
assertEqual(borrowingBase.grossBudget, 420000, "gross seasonal input budget")
assertEqual(borrowingBase.eligibleBudget, 420000, "eligible seasonal input budget")
assertEqual(borrowingBase.calculatedLimit, 315000, "75 percent borrowing base")

-- Partial crop eligibility and a risk/seasonal adjustment are explicit.
local adjustedOk, adjusted = AGFCILOCBorrowingBaseService.calculate({
    {crop = "wheat", acres = 1000, costPerAcre = 100, eligibilityPercent = 1},
    {crop = "specialty", acres = 500, costPerAcre = 200, eligibilityPercent = 0.5}
}, {
    advanceRate = 0.80,
    adjustmentFactor = 0.90,
    maximumLimit = 150000
})
assertTrue(adjustedOk, "adjusted borrowing base calculated")
assertEqual(adjusted.grossBudget, 200000, "adjusted gross budget")
assertEqual(adjusted.eligibleBudget, 150000, "adjusted eligible budget")
assertEqual(adjusted.adjustedEligibleBudget, 135000, "risk adjusted eligible budget")
assertEqual(adjusted.calculatedLimit, 108000, "adjusted line limit")

local invalidBaseOk, invalidBaseError = AGFCILOCBorrowingBaseService.calculate({
    {crop = "wheat", acres = -1, costPerAcre = 100}
}, {advanceRate = 0.75})
assertFalse(invalidBaseOk, "negative acres rejected")
assertEqual(invalidBaseError, "INVALID_ACRES_ROW_1", "negative acres error")

-- Harvest sweep: retain first $20k of $100k sale; sweep 50% of $80k = $40k.
local sweepOk, sweep = AGFHarvestSweepService.calculate(100000, 90000, {
    sweepPercent = 0.50,
    cashRetentionAmount = 20000
})
assertTrue(sweepOk, "harvest sweep calculated")
assertEqual(sweep.eligibleProceeds, 80000, "eligible sweep proceeds")
assertEqual(sweep.proposedSweep, 40000, "proposed principal sweep")
assertEqual(sweep.remainingPrincipal, 50000, "remaining line principal")
assertEqual(sweep.retainedCash, 60000, "farm retained cash after sweep")

-- Sweep cannot exceed remaining principal.
local cappedPrincipalOk, cappedPrincipal = AGFHarvestSweepService.calculate(100000, 15000, {
    sweepPercent = 1,
    cashRetentionAmount = 0
})
assertTrue(cappedPrincipalOk, "principal-capped sweep calculated")
assertEqual(cappedPrincipal.proposedSweep, 15000, "sweep capped at principal")
assertEqual(cappedPrincipal.remainingPrincipal, 0, "line principal cleared")
assertEqual(cappedPrincipal.retainedCash, 85000, "surplus proceeds retained")

-- Minimum sweep avoids tiny automatic principal transactions.
local minimumOk, minimum = AGFHarvestSweepService.calculate(10000, 50000, {
    sweepPercent = 0.10,
    minimumSweepAmount = 2500
})
assertTrue(minimumOk, "minimum sweep calculation succeeds")
assertEqual(minimum.proposedSweep, 0, "sub-minimum sweep suppressed")
assertEqual(minimum.retainedCash, 10000, "cash retained when sweep suppressed")

local badSweepOk, badSweepError = AGFHarvestSweepService.calculate(10000, 5000, {sweepPercent = 1.1})
assertFalse(badSweepOk, "invalid sweep rate rejected")
assertEqual(badSweepError, "INVALID_SWEEP_PERCENT", "invalid sweep rate error")

print("offline_ciloc_policy_tests: PASS")
