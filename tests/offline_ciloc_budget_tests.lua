-- Offline validation for crop-input budget tracking.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/credit/CILOCBudgetService.lua")

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

local ok, budget = AGFCILOCBudgetService.create({
    {category = AGFExpenseCategory.SEED, plannedBudget = 50000, maxFinancedAmount = 40000},
    {category = AGFExpenseCategory.FERTILIZER, plannedBudget = 100000, maxFinancedAmount = 90000},
    {category = AGFExpenseCategory.FUEL, plannedBudget = 30000}
})
assertTrue(ok, "budget creation succeeds")
assertEqual(budget.totalPlannedBudget, 180000, "total planned input budget")
assertEqual(budget.totalActualSpend, 0, "initial actual zero")
assertEqual(budget.totalFinancedSpend, 0, "initial financed zero")

-- Fertilizer purchase can be partly CILOC-financed while retaining fertilizer
-- as the economic expense purpose.
local fertilizerOk, fertilizerResult = AGFCILOCBudgetService.applyPurchase(
    budget,
    AGFExpenseCategory.FERTILIZER,
    30000,
    25000,
    {}
)
assertTrue(fertilizerOk, "fertilizer purchase tracked")
assertEqual(fertilizerResult.category, AGFExpenseCategory.FERTILIZER, "fertilizer category retained")
assertEqual(fertilizerResult.purchaseAmount, 30000, "fertilizer purchase amount")
assertEqual(fertilizerResult.financedAmount, 25000, "fertilizer financed amount")
assertEqual(fertilizerResult.otherFundingAmount, 5000, "fertilizer other funding")
assertEqual(fertilizerResult.state.totalActualSpend, 30000, "actual spend total")
assertEqual(fertilizerResult.state.totalFinancedSpend, 25000, "financed spend total")
assertEqual(fertilizerResult.categoryStatus.remainingBudget, 70000, "fertilizer budget remaining")
assertFalse(fertilizerResult.budgetExceeded, "fertilizer budget not exceeded")

-- Original state is immutable; caller receives a new budget state.
assertEqual(budget.totalActualSpend, 0, "original budget unchanged")
assertEqual(budget.categories[AGFExpenseCategory.FERTILIZER].actualSpend, 0, "original category unchanged")

local current = fertilizerResult.state
local seedOk, seedResult = AGFCILOCBudgetService.applyPurchase(
    current,
    AGFExpenseCategory.SEED,
    45000,
    40000,
    {}
)
assertTrue(seedOk, "seed purchase tracked")
assertEqual(seedResult.categoryStatus.actualSpend, 45000, "seed spend")
assertEqual(seedResult.categoryStatus.financedSpend, 40000, "seed financed spend")
assertEqual(seedResult.categoryStatus.remainingFinancedBudget, 0, "seed finance budget used")

-- Soft management budgets can be exceeded and reported without pretending the
-- line itself has approved extra capacity.
local softOverOk, softOver = AGFCILOCBudgetService.applyPurchase(
    seedResult.state,
    AGFExpenseCategory.SEED,
    10000,
    0,
    {hardCategoryBudget = false}
)
assertTrue(softOverOk, "soft budget overage allowed")
assertTrue(softOver.budgetExceeded, "soft overage flagged")
assertEqual(softOver.categoryStatus.overBudgetAmount, 5000, "seed over-budget amount")
assertEqual(softOver.categoryStatus.financedSpend, 40000, "cash overage does not change financed use")

-- Hard category budgets reject without mutating the supplied state.
local hardSource = seedResult.state
local beforeSpend = hardSource.categories[AGFExpenseCategory.SEED].actualSpend
local hardOverOk, hardOverError = AGFCILOCBudgetService.applyPurchase(
    hardSource,
    AGFExpenseCategory.SEED,
    10000,
    0,
    {hardCategoryBudget = true}
)
assertFalse(hardOverOk, "hard category budget rejected")
assertEqual(hardOverError, "CATEGORY_BUDGET_EXCEEDED", "hard budget error")
assertEqual(hardSource.categories[AGFExpenseCategory.SEED].actualSpend, beforeSpend, "hard rejection leaves state unchanged")

-- Separate optional financed budget can also be enforced.
local financeCapOk, financeCapError = AGFCILOCBudgetService.applyPurchase(
    seedResult.state,
    AGFExpenseCategory.SEED,
    1000,
    1000,
    {hardFinancedBudget = true}
)
assertFalse(financeCapOk, "financed category cap rejected")
assertEqual(financeCapError, "CATEGORY_FINANCED_BUDGET_EXCEEDED", "financed cap error")

-- Eligible but unbudgeted crop protection can be shown as an unbudgeted variance
-- under soft policy, or rejected under strict approved-budget policy.
local unbudgetedOk, unbudgeted = AGFCILOCBudgetService.applyPurchase(
    seedResult.state,
    AGFExpenseCategory.CROP_PROTECTION,
    12000,
    12000,
    {}
)
assertTrue(unbudgetedOk, "unbudgeted eligible input tracked")
assertTrue(unbudgeted.unbudgetedCategory, "unbudgeted category flagged")
assertTrue(unbudgeted.budgetExceeded, "zero planned budget shows variance")
assertEqual(unbudgeted.categoryStatus.overBudgetAmount, 12000, "unbudgeted variance amount")

local strictUnbudgetedOk, strictUnbudgetedError = AGFCILOCBudgetService.applyPurchase(
    seedResult.state,
    AGFExpenseCategory.CROP_PROTECTION,
    12000,
    12000,
    {allowUnbudgetedCategory = false}
)
assertFalse(strictUnbudgetedOk, "strict budget rejects unbudgeted category")
assertEqual(strictUnbudgetedError, "CATEGORY_NOT_IN_APPROVED_BUDGET", "strict unbudgeted error")

-- Financing cannot exceed the underlying purchase amount.
local overFinanceOk, overFinanceError = AGFCILOCBudgetService.applyPurchase(
    seedResult.state,
    AGFExpenseCategory.FUEL,
    1000,
    1000.01,
    {}
)
assertFalse(overFinanceOk, "financing above purchase rejected")
assertEqual(overFinanceError, "FINANCED_AMOUNT_EXCEEDS_PURCHASE", "over-financing error")

-- Non-crop-input categories do not become eligible merely by being a ledger expense.
local ineligibleOk, ineligibleError = AGFCILOCBudgetService.applyPurchase(
    seedResult.state,
    AGFExpenseCategory.INTEREST,
    1000,
    1000,
    {}
)
assertFalse(ineligibleOk, "interest cannot be a crop-input budget category")
assertEqual(ineligibleError, "INELIGIBLE_CROP_INPUT_CATEGORY", "ineligible category error")

local badCreateOk, badCreateError = AGFCILOCBudgetService.create({
    {category = AGFExpenseCategory.INTEREST, plannedBudget = 1000}
})
assertFalse(badCreateOk, "ineligible planned category rejected")
assertEqual(badCreateError, "INELIGIBLE_BUDGET_CATEGORY_ROW_1", "bad planned category error")

print("offline_ciloc_budget_tests: PASS")
