-- Offline validation for integrated Crop Input LOC facility review.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/credit/CILOCBudgetService.lua")
dofile("src/credit/CILOCBorrowingBaseService.lua")
dofile("src/credit/CILOCSeasonService.lua")
dofile("src/credit/CILOCFacilityReviewService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertNear(actual, expected, tolerance, message)
    if actual == nil or math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %.10f +/- %.10f, got %s", message or "assertNear", expected, tolerance, tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local function assertFalse(value, message)
    if value ~= false then error(message or "expected false") end
end

local budgetOk, budget = AGFCILOCBudgetService.create({
    {category = AGFExpenseCategory.SEED, plannedBudget = 50000, maxFinancedAmount = 40000},
    {category = AGFExpenseCategory.FERTILIZER, plannedBudget = 100000, maxFinancedAmount = 85000},
    {category = AGFExpenseCategory.FUEL, plannedBudget = 30000}
})
assertTrue(budgetOk, "budget creation")

local fertOk, fert = AGFCILOCBudgetService.applyPurchase(budget, AGFExpenseCategory.FERTILIZER, 30000, 25000, {})
assertTrue(fertOk, "fertilizer budget use")
local seedOk, seed = AGFCILOCBudgetService.applyPurchase(fert.state, AGFExpenseCategory.SEED, 20000, 15000, {})
assertTrue(seedOk, "seed budget use")

-- Borrowing base from crop acres is lower than the contractual line limit, so
-- it becomes the effective availability authority for the review.
local reviewOk, review = AGFCILOCFacilityReviewService.review({
    creditLimit = 250000,
    principalBalance = 40000,
    reservedAmount = 10000,
    budgetState = seed.state,
    cropRows = {
        {crop = "wheat", acres = 1000, costPerAcre = 160, eligibilityPercent = 1.0},
        {crop = "canola", acres = 500, costPerAcre = 220, eligibilityPercent = 0.90}
    },
    borrowingBasePolicy = {advanceRate = 0.75, adjustmentFactor = 1},
    seasonParameters = {
        currentYear = 10,
        currentPeriod = 4,
        startYear = 10,
        startPeriod = 1,
        maturityYear = 10,
        maturityPeriod = 11,
        cleanupWindowPeriods = 2,
        cleanupTargetBalance = 0,
        freezeNewDrawsDuringCleanup = true
    }
})
assertTrue(reviewOk, "facility review succeeds")
assertEqual(review.creditLimit, 250000, "contract line limit")
-- Eligible crop budget = 160,000 + 99,000 = 259,000; 75% = 194,250.
assertEqual(review.borrowingBase, 194250, "calculated borrowing base")
assertEqual(review.effectiveLimit, 194250, "borrowing base constrains facility")
assertEqual(review.usedCapacity, 50000, "principal plus reservation")
assertEqual(review.availableCapacity, 144250, "active-season availability")
assertNear(review.utilization, 50000 / 194250, 0.0000000001, "effective utilization")
assertEqual(review.budget.totalPlannedBudget, 180000, "planned crop-input budget")
assertEqual(review.budget.totalActualSpend, 50000, "actual input spend")
assertEqual(review.budget.totalFinancedSpend, 40000, "financed input spend")
assertEqual(review.budget.totalCashOrOtherFunding, 10000, "other funding")
assertEqual(review.budget.remainingFinancedCategoryCap, 85000, "remaining explicit category finance caps")
assertEqual(review.budget.overBudgetAmount, 0, "no overall budget overrun")
assertFalse(review.flags.overEffectiveLimit, "not over effective line")
assertFalse(review.flags.drawsFrozen, "active season draws open")
assertFalse(review.flags.budgetOverrun, "budget not overrun")
assertEqual(#review.attentionItems, 0, "healthy facility has no attention items")

-- Cleanup window can freeze new draws even when numerical line capacity remains.
local cleanupOk, cleanup = AGFCILOCFacilityReviewService.review({
    creditLimit = 250000,
    principalBalance = 90000,
    reservedAmount = 0,
    budgetState = seed.state,
    borrowingBase = 180000,
    seasonParameters = {
        currentYear = 10,
        currentPeriod = 10,
        startYear = 10,
        startPeriod = 1,
        maturityYear = 10,
        maturityPeriod = 11,
        cleanupWindowPeriods = 2,
        cleanupTargetBalance = 0,
        freezeNewDrawsDuringCleanup = true
    }
})
assertTrue(cleanupOk, "cleanup review succeeds")
assertEqual(cleanup.season.state, AGFCILOCSeasonState.CLEANUP_WINDOW, "cleanup state")
assertEqual(cleanup.baseAvailableCapacity, 90000, "numerical capacity remains")
assertEqual(cleanup.availableCapacity, 0, "draws frozen during cleanup")
assertTrue(cleanup.flags.drawsFrozen, "draw freeze flagged")
assertTrue(cleanup.flags.cleanupRequired, "cleanup paydown required")
assertEqual(cleanup.season.requiredCleanupPaydown, 90000, "required paydown")
assertEqual(cleanup.attentionItems[1].code, "CLEANUP_PAYDOWN_REQUIRED", "cleanup attention")

-- Facility review surfaces budget variance and unbudgeted eligible categories.
local overSeedOk, overSeed = AGFCILOCBudgetService.applyPurchase(
    seed.state,
    AGFExpenseCategory.SEED,
    40000,
    25000,
    {hardCategoryBudget = false, hardFinancedBudget = false}
)
assertTrue(overSeedOk, "soft budget overrun projected")
local unbudgetedOk, unbudgeted = AGFCILOCBudgetService.applyPurchase(
    overSeed.state,
    AGFExpenseCategory.CROP_PROTECTION,
    12000,
    12000,
    {}
)
assertTrue(unbudgetedOk, "unbudgeted eligible category projected")

local varianceOk, variance = AGFCILOCFacilityReviewService.review({
    creditLimit = 150000,
    principalBalance = 70000,
    reservedAmount = 0,
    budgetState = unbudgeted.state,
    borrowingBase = 150000,
    seasonParameters = {
        currentYear = 2,
        currentPeriod = 5,
        maturityYear = 2,
        maturityPeriod = 12,
        cleanupWindowPeriods = 1,
        cleanupTargetBalance = 0
    }
})
assertTrue(varianceOk, "variance review succeeds")
assertTrue(variance.flags.budgetOverrun, "budget overrun surfaced")
assertTrue(variance.flags.hasUnbudgetedSpend, "unbudgeted spend surfaced")
assertTrue(variance.budget.overBudgetCategoryCount >= 2, "over-budget categories counted")
assertEqual(variance.budget.unbudgetedCategoryCount, 1, "one unbudgeted category")
assertTrue(#variance.attentionItems >= 2, "budget attention items generated")

-- If utilization/reservations exceed the borrowing-base constrained limit, the
-- review reports the overage rather than pretending negative availability exists.
local overLimitOk, overLimit = AGFCILOCFacilityReviewService.review({
    creditLimit = 200000,
    principalBalance = 120000,
    reservedAmount = 20000,
    borrowingBase = 130000,
    seasonParameters = {
        currentYear = 3,
        currentPeriod = 3,
        maturityYear = 3,
        maturityPeriod = 12,
        cleanupWindowPeriods = 0,
        cleanupTargetBalance = 0
    }
})
assertTrue(overLimitOk, "over-limit review still evaluates")
assertEqual(overLimit.effectiveLimit, 130000, "effective limit")
assertEqual(overLimit.season.overEffectiveLimit, 10000, "over effective limit amount")
assertEqual(overLimit.availableCapacity, 0, "availability floored at zero")
assertTrue(overLimit.flags.overEffectiveLimit, "over-limit flag")
assertEqual(overLimit.attentionItems[1].code, "OVER_EFFECTIVE_LIMIT", "over-limit attention")

-- Invalid underlying borrowing-base input propagates a clear error.
local badBaseOk, badBaseError = AGFCILOCFacilityReviewService.review({
    creditLimit = 100000,
    principalBalance = 0,
    cropRows = {{crop = "wheat", acres = -1, costPerAcre = 100}},
    borrowingBasePolicy = {advanceRate = 0.75},
    seasonParameters = {currentYear = 1, currentPeriod = 1, maturityYear = 1, maturityPeriod = 12}
})
assertFalse(badBaseOk, "invalid crop budget rejected")
assertEqual(badBaseError, "INVALID_ACRES_ROW_1", "borrowing-base error propagated")

print("offline_ciloc_facility_review_tests: PASS")
