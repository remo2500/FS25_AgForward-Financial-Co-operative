-- Offline validation for integrated Crop Input LOC purchase preflight.

function Class(classTable)
    return {__index = classTable}
end

MoneyType = {
    PURCHASE_SEEDS = "purchaseSeeds",
    PURCHASE_FUEL = "purchaseFuel",
    PURCHASE_FERTILIZER = "purchaseFertilizer",
    BOUGHT_MATERIALS = "boughtMaterials"
}

g_fillTypeManager = {
    getFillTypeNameByIndex = function(self, index)
        local names = {
            [1] = "FERTILIZER",
            [2] = "HERBICIDE",
            [3] = "SEEDS",
            [4] = "UNKNOWN_MATERIAL"
        }
        return names[index]
    end
}

AGFLiabilityStatus = {ACTIVE = "active"}

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/input/PurchaseClassificationService.lua")
dofile("src/input/FundingDecisionService.lua")
dofile("src/credit/CILOCBudgetService.lua")
dofile("src/input/CILOCPurchasePreflightService.lua")

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

local classifier = AGFPurchaseClassificationService.new()
local service = AGFCILOCPurchasePreflightService.new(classifier)

local liability = {
    id = "AGF-LIAB-CILOC-1",
    farmId = 1,
    productType = AGFProductType.CROP_INPUT_LINE,
    status = AGFLiabilityStatus.ACTIVE,
    isRevolving = function(self) return true end
}

local facility = {
    effectiveLimit = 150000,
    usedCapacity = 50000,
    availableCapacity = 100000,
    flags = {drawsFrozen = false}
}

local budgetOk, budget = AGFCILOCBudgetService.create({
    {category = AGFExpenseCategory.FERTILIZER, plannedBudget = 100000, maxFinancedAmount = 90000},
    {category = AGFExpenseCategory.CROP_PROTECTION, plannedBudget = 25000, maxFinancedAmount = 20000},
    {category = AGFExpenseCategory.SEED, plannedBudget = 50000, maxFinancedAmount = 40000}
})
assertTrue(budgetOk, "budget created")

-- Fully financed fertilizer purchase: line draw and fertilizer expense remain
-- separate economic facts, with no immediate cash contribution.
local fullOk, full = service:plan({
    farmId = 1,
    amount = 30000,
    cashAvailable = 5000,
    fundingPolicy = AGFFundingPolicy.ALWAYS_LINE,
    moneyType = MoneyType.PURCHASE_FERTILIZER,
    fillTypeIndex = 1,
    liability = liability,
    facilityReview = facility,
    budgetState = budget,
    budgetPolicy = {hardCategoryBudget = true, hardFinancedBudget = true},
    contextFingerprint = "fillstation:fertilizer:1"
})
assertTrue(fullOk, "full line-funded fertilizer preflight")
assertEqual(full.expenseCategory, AGFExpenseCategory.FERTILIZER, "fertilizer purpose")
assertTrue(full.cilocEligible, "fertilizer CILOC eligible")
assertEqual(full.funding.cashContribution, 0, "no cash contribution")
assertEqual(full.funding.lineContribution, 30000, "line contribution")
assertEqual(full.netCashEffect, 0, "zero immediate cash effect")
assertEqual(full.expectedGroupNet, 0, "linked group nets zero")
assertEqual(full.reservationIntent.amount, 30000, "reservation amount")
assertEqual(full.reservationIntent.liabilityId, liability.id, "reservation liability")
assertEqual(full.facilityProjection.usedCapacityAfterReservation, 80000, "projected used capacity")
assertEqual(full.facilityProjection.availableCapacityAfterReservation, 70000, "projected remaining facility")
assertEqual(full.budgetProjection.categoryStatus.actualSpend, 30000, "fertilizer budget actual")
assertEqual(full.budgetProjection.categoryStatus.financedSpend, 30000, "fertilizer budget financed")
assertEqual(#full.ledgerIntents, 2, "draw plus purchase intents")
assertEqual(full.ledgerIntents[1].transactionType, AGFTransactionType.CREDIT_DRAW, "first intent draw")
assertEqual(full.ledgerIntents[1].amount, 30000, "draw amount")
assertEqual(full.ledgerIntents[2].transactionType, AGFTransactionType.INPUT_PURCHASE, "second intent purchase")
assertEqual(full.ledgerIntents[2].amount, -30000, "purchase amount")
assertEqual(full.ledgerIntents[2].expenseCategory, AGFExpenseCategory.FERTILIZER, "ledger fertilizer category")

-- Partial funding uses available cash first under CASH_SHORTFALL_ONLY, then line.
local partialOk, partial = service:plan({
    farmId = 1,
    amount = 30000,
    cashAvailable = 10000,
    fundingPolicy = AGFFundingPolicy.CASH_SHORTFALL_ONLY,
    moneyType = MoneyType.PURCHASE_FERTILIZER,
    fillTypeIndex = 1,
    liability = liability,
    facilityReview = facility,
    budgetState = budget,
    contextFingerprint = "fillstation:fertilizer:2"
})
assertTrue(partialOk, "partial funding preflight")
assertEqual(partial.funding.cashContribution, 10000, "partial cash")
assertEqual(partial.funding.lineContribution, 20000, "partial line")
assertEqual(partial.netCashEffect, -10000, "cash portion leaves farm")
assertEqual(partial.expectedGroupNet, -10000, "group net equals cash portion")
assertEqual(partial.budgetProjection.categoryStatus.actualSpend, 30000, "budget counts full purchase")
assertEqual(partial.budgetProjection.categoryStatus.financedSpend, 20000, "budget counts line portion only")

-- Fill-type refinement correctly treats herbicide carried under a generic
-- fertilizer/material MoneyType as crop protection.
local herbicideOk, herbicide = service:plan({
    farmId = 1,
    amount = 12000,
    cashAvailable = 0,
    fundingPolicy = AGFFundingPolicy.ALWAYS_LINE,
    moneyType = MoneyType.PURCHASE_FERTILIZER,
    fillTypeIndex = 2,
    liability = liability,
    facilityReview = facility,
    budgetState = budget,
    contextFingerprint = "fillstation:herbicide:1"
})
assertTrue(herbicideOk, "herbicide preflight")
assertEqual(herbicide.expenseCategory, AGFExpenseCategory.CROP_PROTECTION, "herbicide classified crop protection")
assertEqual(herbicide.ledgerIntents[2].expenseCategory, AGFExpenseCategory.CROP_PROTECTION, "crop protection ledger purpose")

-- An unresolved generic material cannot use CILOC. If sufficient cash exists,
-- it may remain a cash purchase, but no credit reservation/draw is proposed.
local unknownCashOk, unknownCash = service:plan({
    farmId = 1,
    amount = 5000,
    cashAvailable = 10000,
    fundingPolicy = AGFFundingPolicy.ALWAYS_LINE,
    moneyType = MoneyType.BOUGHT_MATERIALS,
    fillTypeIndex = 4,
    liability = liability,
    facilityReview = facility
})
assertTrue(unknownCashOk, "unknown material falls back to cash when affordable")
assertFalse(unknownCash.cilocEligible, "unknown material not CILOC eligible")
assertEqual(unknownCash.funding.lineContribution, 0, "unknown material no credit")
assertEqual(unknownCash.funding.cashContribution, 5000, "unknown material cash")
assertEqual(unknownCash.reservationIntent, nil, "unknown material no reservation")
assertEqual(#unknownCash.ledgerIntents, 1, "cash-only unresolved purchase has no draw")

local unknownNoCashOk, unknownNoCashError = service:plan({
    farmId = 1,
    amount = 5000,
    cashAvailable = 1000,
    fundingPolicy = AGFFundingPolicy.ALWAYS_LINE,
    moneyType = MoneyType.BOUGHT_MATERIALS,
    fillTypeIndex = 4,
    liability = liability,
    facilityReview = facility
})
assertFalse(unknownNoCashOk, "unknown material cannot borrow when cash insufficient")
assertEqual(unknownNoCashError, "INSUFFICIENT_CASH", "unknown material cash error")

-- Cash-funded eligible input still consumes the management budget, but creates
-- no CILOC reservation or draw.
local cashOk, cashPlan = service:plan({
    farmId = 1,
    amount = 10000,
    cashAvailable = 25000,
    fundingPolicy = AGFFundingPolicy.OFF,
    moneyType = MoneyType.PURCHASE_SEEDS,
    fillTypeIndex = 3,
    liability = liability,
    facilityReview = facility,
    budgetState = budget
})
assertTrue(cashOk, "cash-funded seed preflight")
assertEqual(cashPlan.expenseCategory, AGFExpenseCategory.SEED, "seed category")
assertEqual(cashPlan.funding.lineContribution, 0, "seed no line")
assertEqual(cashPlan.netCashEffect, -10000, "seed cash outflow")
assertEqual(cashPlan.budgetProjection.categoryStatus.actualSpend, 10000, "cash seed counts in budget")
assertEqual(cashPlan.budgetProjection.categoryStatus.financedSpend, 0, "cash seed not financed")
assertEqual(cashPlan.reservationIntent, nil, "cash seed no reservation")

-- Cleanup/freeze policy is enforced independently from raw numerical capacity.
local frozenOk, frozenError = service:plan({
    farmId = 1,
    amount = 10000,
    cashAvailable = 0,
    fundingPolicy = AGFFundingPolicy.ALWAYS_LINE,
    moneyType = MoneyType.PURCHASE_FERTILIZER,
    fillTypeIndex = 1,
    liability = liability,
    facilityReview = {
        effectiveLimit = 150000,
        usedCapacity = 50000,
        availableCapacity = 100000,
        flags = {drawsFrozen = true}
    },
    budgetState = budget
})
assertFalse(frozenOk, "draw freeze blocks financed purchase")
assertEqual(frozenError, "CILOC_DRAWS_FROZEN", "draw-freeze error")

-- Hard category budget is preflighted before any reservation intent is returned.
local nearlyFullBudgetOk, nearlyFullBudget = AGFCILOCBudgetService.applyPurchase(
    budget,
    AGFExpenseCategory.FERTILIZER,
    95000,
    85000,
    {}
)
assertTrue(nearlyFullBudgetOk, "prepare near-full fertilizer budget")
local budgetRejectOk, budgetRejectError = service:plan({
    farmId = 1,
    amount = 10000,
    cashAvailable = 0,
    fundingPolicy = AGFFundingPolicy.ALWAYS_LINE,
    moneyType = MoneyType.PURCHASE_FERTILIZER,
    fillTypeIndex = 1,
    liability = liability,
    facilityReview = facility,
    budgetState = nearlyFullBudget.state,
    budgetPolicy = {hardCategoryBudget = true}
})
assertFalse(budgetRejectOk, "hard budget rejection")
assertEqual(budgetRejectError, "CATEGORY_BUDGET_EXCEEDED", "hard budget error")
assertEqual(nearlyFullBudget.state.categories[AGFExpenseCategory.FERTILIZER].actualSpend, 95000, "rejected preflight leaves budget unchanged")

-- Liability/farm/product authority must match the server purchase context.
local wrongFarmOk, wrongFarmError = service:plan({
    farmId = 2,
    amount = 10000,
    cashAvailable = 0,
    fundingPolicy = AGFFundingPolicy.ALWAYS_LINE,
    moneyType = MoneyType.PURCHASE_FERTILIZER,
    fillTypeIndex = 1,
    liability = liability,
    facilityReview = facility
})
assertFalse(wrongFarmOk, "wrong-farm line rejected")
assertEqual(wrongFarmError, "LIABILITY_FARM_MISMATCH", "wrong farm error")

local wrongProduct = {
    id = "AGF-LIAB-TERM",
    farmId = 1,
    productType = AGFProductType.TERM_LOAN,
    status = AGFLiabilityStatus.ACTIVE,
    isRevolving = function(self) return false end
}
local wrongProductOk, wrongProductError = service:plan({
    farmId = 1,
    amount = 10000,
    cashAvailable = 0,
    fundingPolicy = AGFFundingPolicy.ALWAYS_LINE,
    moneyType = MoneyType.PURCHASE_FERTILIZER,
    fillTypeIndex = 1,
    liability = wrongProduct,
    facilityReview = facility
})
assertFalse(wrongProductOk, "term loan cannot masquerade as CILOC")
assertEqual(wrongProductError, "LIABILITY_NOT_CROP_INPUT_LINE", "wrong product error")

print("offline_ciloc_purchase_preflight_tests: PASS")
