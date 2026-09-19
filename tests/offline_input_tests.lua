-- Offline validation for purchase classification and high-frequency input aggregation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/input/PurchaseClassificationService.lua")
dofile("src/input/InputPurchaseAccumulator.lua")

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

MoneyType = {
    PURCHASE_SEEDS = {name = "purchaseSeeds"},
    PURCHASE_FUEL = {name = "purchaseFuel"},
    PURCHASE_FERTILIZER = {name = "purchaseFertilizer"},
    BOUGHT_MATERIALS = {name = "boughtMaterials"},
    OTHER = {name = "other"}
}

local fillTypeNames = {
    [1] = "SEEDS",
    [2] = "FERTILIZER",
    [3] = "LIQUIDFERTILIZER",
    [4] = "LIME",
    [5] = "HERBICIDE",
    [6] = "DIESEL",
    [7] = "DEF",
    [8] = "METHANE",
    [9] = "ELECTRICCHARGE",
    [10] = "WHEAT"
}

g_fillTypeManager = {
    getFillTypeNameByIndex = function(self, index)
        return fillTypeNames[index]
    end
}

local classifier = AGFPurchaseClassificationService.new()

-- Explicit caller context is authoritative when AgForward already knows purpose.
local explicitCategory, explicitConfidence, explicitReason = classifier:classify(
    MoneyType.OTHER,
    10,
    {expenseCategory = AGFExpenseCategory.CROP_PROTECTION}
)
assertEqual(explicitCategory, AGFExpenseCategory.CROP_PROTECTION, "explicit category")
assertEqual(explicitConfidence, "EXPLICIT", "explicit confidence")
assertEqual(explicitReason, "CALLER_CONTEXT", "explicit reason")

-- Dedicated FS MoneyTypes retain their clear economic purpose.
local seedCategory, seedConfidence, seedReason = classifier:classify(MoneyType.PURCHASE_SEEDS, nil, {})
assertEqual(seedCategory, AGFExpenseCategory.SEED, "seed MoneyType")
assertEqual(seedConfidence, "HIGH", "seed confidence")
assertEqual(seedReason, "MONEYTYPE_PURCHASE_SEEDS", "seed reason")

local fuelCategory = classifier:classify(MoneyType.PURCHASE_FUEL, nil, {})
assertEqual(fuelCategory, AGFExpenseCategory.FUEL, "fuel MoneyType")

-- Fertilizer purchase paths are refined by fill type when lime/herbicide is known.
local herbicideCategory, herbicideConfidence, herbicideReason = classifier:classify(MoneyType.PURCHASE_FERTILIZER, 5, {})
assertEqual(herbicideCategory, AGFExpenseCategory.CROP_PROTECTION, "herbicide refinement")
assertEqual(herbicideConfidence, "HIGH", "herbicide confidence")
assertEqual(herbicideReason, "FILLTYPE_HERBICIDE", "herbicide reason")

local limeCategory = classifier:classify(MoneyType.PURCHASE_FERTILIZER, 4, {})
assertEqual(limeCategory, AGFExpenseCategory.LIME_SOIL_AMENDMENT, "lime refinement")

local fertilizerCategory, fertilizerConfidence = classifier:classify(MoneyType.PURCHASE_FERTILIZER, nil, {})
assertEqual(fertilizerCategory, AGFExpenseCategory.FERTILIZER, "fertilizer fallback")
assertEqual(fertilizerConfidence, "MEDIUM", "fertilizer fallback confidence")

-- Generic BOUGHT_MATERIALS must never guess without fill-type context.
local genericCategory, genericConfidence, genericReason = classifier:classify(MoneyType.BOUGHT_MATERIALS, nil, {})
assertEqual(genericCategory, nil, "generic material without fill type unclassified")
assertEqual(genericConfidence, "LOW", "generic material confidence")
assertEqual(genericReason, "BOUGHT_MATERIALS_REQUIRES_FILLTYPE_CONTEXT", "generic material reason")

local boughtLimeCategory, boughtLimeConfidence, boughtLimeReason = classifier:classify(MoneyType.BOUGHT_MATERIALS, 4, {})
assertEqual(boughtLimeCategory, AGFExpenseCategory.LIME_SOIL_AMENDMENT, "generic material with lime context")
assertEqual(boughtLimeConfidence, "HIGH", "generic material with context confidence")
assertEqual(boughtLimeReason, "BOUGHT_MATERIALS_WITH_FILLTYPE_LIME", "generic material with context reason")

-- Fill type can classify an otherwise generic/unknown MoneyType, but unmapped fill
-- types remain unclassified rather than being forced into an input category.
local dieselCategory = classifier:classify(MoneyType.OTHER, 6, {})
assertEqual(dieselCategory, AGFExpenseCategory.FUEL, "diesel fill type classification")
local wheatCategory, wheatConfidence, wheatReason = classifier:classify(MoneyType.OTHER, 10, {})
assertEqual(wheatCategory, nil, "unmapped fill type remains unclassified")
assertEqual(wheatConfidence, "NONE", "unmapped final classification confidence")
assertEqual(wheatReason, "UNCLASSIFIED_PURCHASE", "unmapped final reason")

-- Missing manager/context is safe and deterministic.
local savedManager = g_fillTypeManager
g_fillTypeManager = nil
local noManagerCategory = classifier:classify(MoneyType.BOUGHT_MATERIALS, 4, {})
assertEqual(noManagerCategory, nil, "missing fill-type manager does not guess")
g_fillTypeManager = savedManager

-- High-frequency accumulator preserves cents exactly.
local accumulator = AGFInputPurchaseAccumulator.new()
for _ = 1, 100 do
    local added, addError = accumulator:add(
        1,
        -0.01,
        AGFExpenseCategory.SEED,
        AGFFundingSource.CASH,
        nil,
        "AI seed"
    )
    assertTrue(added, "cent event accumulated")
    assertEqual(addError, nil, "cent event error")
end

local pending = accumulator:getPending()
assertEqual(#pending, 1, "cent events share one bucket")
assertEqual(pending[1].amount, 1.00, "one hundred cents remain exact")
assertEqual(pending[1].eventCount, 100, "event count retained")
assertEqual(pending[1].description, "AI seed", "description retained")

-- Funding source, liability, category, and farm are all bucket dimensions.
assertTrue(accumulator:add(1, 5.55, AGFExpenseCategory.SEED, AGFFundingSource.CROP_INPUT_LINE, "AGF-LIAB-000001", "financed seed"))
assertTrue(accumulator:add(1, 2.00, AGFExpenseCategory.FERTILIZER, AGFFundingSource.CASH, nil, "fertilizer"))
assertTrue(accumulator:add(2, 3.00, AGFExpenseCategory.SEED, AGFFundingSource.CASH, nil, "farm two"))
local separated = accumulator:getPending()
assertEqual(#separated, 4, "bucket dimensions remain separated")

local financedFound = false
for _, bucket in ipairs(separated) do
    if bucket.liabilityId == "AGF-LIAB-000001" then
        financedFound = true
        assertEqual(bucket.amount, 5.55, "financed bucket amount")
        assertEqual(bucket.fundingSource, AGFFundingSource.CROP_INPUT_LINE, "financed bucket source")
    end
end
assertTrue(financedFound, "financed bucket present")

-- Invalid/zero inputs do not create buckets.
local beforeInvalid = #accumulator:getPending()
local zeroAdded, zeroError = accumulator:add(1, 0, AGFExpenseCategory.SEED, AGFFundingSource.CASH)
assertFalse(zeroAdded, "zero input rejected")
assertEqual(zeroError, "INVALID_AMOUNT", "zero input error")
local missingContextAdded, missingContextError = accumulator:add(nil, 1, AGFExpenseCategory.SEED, AGFFundingSource.CASH)
assertFalse(missingContextAdded, "missing farm rejected")
assertEqual(missingContextError, "INVALID_ACCUMULATOR_CONTEXT", "missing farm error")
assertEqual(#accumulator:getPending(), beforeInvalid, "invalid inputs do not create buckets")

-- Drain is atomic from the caller's perspective and leaves a fresh empty accumulator.
local drained = accumulator:drain()
assertEqual(#drained, 4, "drain returns all pending buckets")
assertEqual(#accumulator:getPending(), 0, "drain empties accumulator")
assertTrue(accumulator:add(1, 1.23, AGFExpenseCategory.FUEL, AGFFundingSource.CASH, nil, "new cycle"))
assertEqual(#accumulator:getPending(), 1, "accumulator reusable after drain")
accumulator:reset()
assertEqual(#accumulator:getPending(), 0, "reset empties accumulator")

print("offline_input_tests: PASS")
