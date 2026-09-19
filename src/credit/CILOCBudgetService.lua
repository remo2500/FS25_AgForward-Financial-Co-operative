-- AgForward Financial Cooperative
-- Pure crop-input budget/use tracking for CILOC underwriting/reporting.
-- It does not reserve line capacity, authorize a purchase, or move FS25 money.

AGFCILOCBudgetService = {}

local ELIGIBLE_CATEGORIES = {
    [AGFExpenseCategory.SEED] = true,
    [AGFExpenseCategory.FERTILIZER] = true,
    [AGFExpenseCategory.LIME_SOIL_AMENDMENT] = true,
    [AGFExpenseCategory.CROP_PROTECTION] = true,
    [AGFExpenseCategory.FUEL] = true,
    [AGFExpenseCategory.OTHER_INPUT] = true
}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function nonNegativeMoney(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function copyRow(row)
    local copy = {}
    for key, value in pairs(row or {}) do copy[key] = value end
    return copy
end

local function deepCopyState(state)
    local copy = {
        categories = {},
        order = {},
        totalPlannedBudget = AGFCurrency.round(state.totalPlannedBudget or 0),
        totalActualSpend = AGFCurrency.round(state.totalActualSpend or 0),
        totalFinancedSpend = AGFCurrency.round(state.totalFinancedSpend or 0),
        purchaseCount = math.max(0, math.floor(tonumber(state.purchaseCount) or 0))
    }
    for _, category in ipairs(state.order or {}) do
        table.insert(copy.order, category)
        copy.categories[category] = copyRow(state.categories[category])
    end
    return copy
end

local function refreshRow(row)
    row.remainingBudget = AGFCurrency.round((row.plannedBudget or 0) - (row.actualSpend or 0))
    row.overBudgetAmount = math.max(0, AGFCurrency.round((row.actualSpend or 0) - (row.plannedBudget or 0)))
    row.budgetUtilization = (row.plannedBudget or 0) > 0 and (row.actualSpend or 0) / row.plannedBudget or nil
    row.financedShare = (row.actualSpend or 0) > 0 and (row.financedSpend or 0) / row.actualSpend or nil
    if row.maxFinancedAmount ~= nil then
        row.remainingFinancedBudget = AGFCurrency.round((row.maxFinancedAmount or 0) - (row.financedSpend or 0))
        row.overFinancedBudgetAmount = math.max(0, AGFCurrency.round((row.financedSpend or 0) - (row.maxFinancedAmount or 0)))
    else
        row.remainingFinancedBudget = nil
        row.overFinancedBudgetAmount = 0
    end
end

local function refreshState(state)
    local planned = 0
    local actual = 0
    local financed = 0
    for _, category in ipairs(state.order or {}) do
        local row = state.categories[category]
        refreshRow(row)
        planned = AGFCurrency.round(planned + (row.plannedBudget or 0))
        actual = AGFCurrency.round(actual + (row.actualSpend or 0))
        financed = AGFCurrency.round(financed + (row.financedSpend or 0))
    end
    state.totalPlannedBudget = planned
    state.totalActualSpend = actual
    state.totalFinancedSpend = financed
    state.totalCashOrOtherFunding = AGFCurrency.round(actual - financed)
    state.remainingPlannedBudget = AGFCurrency.round(planned - actual)
    state.overBudgetAmount = math.max(0, AGFCurrency.round(actual - planned))
    state.financedShare = actual > 0 and financed / actual or nil
    return state
end

function AGFCILOCBudgetService.isEligibleCategory(category)
    return ELIGIBLE_CATEGORIES[category] == true
end

function AGFCILOCBudgetService.create(budgetRows)
    local state = {
        categories = {},
        order = {},
        totalPlannedBudget = 0,
        totalActualSpend = 0,
        totalFinancedSpend = 0,
        purchaseCount = 0
    }

    for index, source in ipairs(budgetRows or {}) do
        source = source or {}
        local category = source.category
        if not AGFCILOCBudgetService.isEligibleCategory(category) then
            return false, "INELIGIBLE_BUDGET_CATEGORY_ROW_" .. tostring(index)
        end
        if state.categories[category] ~= nil then
            return false, "DUPLICATE_BUDGET_CATEGORY:" .. tostring(category)
        end

        local plannedBudget = nonNegativeMoney(source.plannedBudget)
        if plannedBudget == nil then return false, "INVALID_PLANNED_BUDGET_ROW_" .. tostring(index) end

        local maxFinancedAmount = nil
        if source.maxFinancedAmount ~= nil then
            maxFinancedAmount = nonNegativeMoney(source.maxFinancedAmount)
            if maxFinancedAmount == nil then return false, "INVALID_MAX_FINANCED_ROW_" .. tostring(index) end
        end

        local row = {
            category = category,
            plannedBudget = plannedBudget,
            maxFinancedAmount = maxFinancedAmount,
            actualSpend = 0,
            financedSpend = 0,
            purchaseCount = 0,
            unbudgeted = false
        }
        refreshRow(row)
        state.categories[category] = row
        table.insert(state.order, category)
    end

    table.sort(state.order)
    refreshState(state)
    return true, state
end

function AGFCILOCBudgetService.applyPurchase(state, category, purchaseAmount, financedAmount, policy)
    policy = policy or {}
    if type(state) ~= "table" or type(state.categories) ~= "table" or type(state.order) ~= "table" then
        return false, "INVALID_BUDGET_STATE"
    end
    if not AGFCILOCBudgetService.isEligibleCategory(category) then
        return false, "INELIGIBLE_CROP_INPUT_CATEGORY"
    end

    local purchase = nonNegativeMoney(purchaseAmount)
    local financed = nonNegativeMoney(financedAmount or 0)
    if purchase == nil or purchase <= 0 then return false, "INVALID_PURCHASE_AMOUNT" end
    if financed == nil then return false, "INVALID_FINANCED_AMOUNT" end
    if AGFCurrency.toMinorUnits(financed) > AGFCurrency.toMinorUnits(purchase) then
        return false, "FINANCED_AMOUNT_EXCEEDS_PURCHASE"
    end

    local nextState = deepCopyState(state)
    local row = nextState.categories[category]
    if row == nil then
        if policy.allowUnbudgetedCategory == false then
            return false, "CATEGORY_NOT_IN_APPROVED_BUDGET"
        end
        row = {
            category = category,
            plannedBudget = 0,
            maxFinancedAmount = nil,
            actualSpend = 0,
            financedSpend = 0,
            purchaseCount = 0,
            unbudgeted = true
        }
        nextState.categories[category] = row
        table.insert(nextState.order, category)
        table.sort(nextState.order)
    end

    local proposedActual = AGFCurrency.round((row.actualSpend or 0) + purchase)
    local proposedFinanced = AGFCurrency.round((row.financedSpend or 0) + financed)
    local budgetExceeded = AGFCurrency.toMinorUnits(proposedActual) > AGFCurrency.toMinorUnits(row.plannedBudget or 0)
    local financeBudgetExceeded = row.maxFinancedAmount ~= nil
        and AGFCurrency.toMinorUnits(proposedFinanced) > AGFCurrency.toMinorUnits(row.maxFinancedAmount)

    if budgetExceeded and policy.hardCategoryBudget == true then
        return false, "CATEGORY_BUDGET_EXCEEDED"
    end
    if financeBudgetExceeded and policy.hardFinancedBudget == true then
        return false, "CATEGORY_FINANCED_BUDGET_EXCEEDED"
    end

    row.actualSpend = proposedActual
    row.financedSpend = proposedFinanced
    row.purchaseCount = (row.purchaseCount or 0) + 1
    nextState.purchaseCount = (nextState.purchaseCount or 0) + 1
    refreshState(nextState)

    return true, {
        state = nextState,
        category = category,
        purchaseAmount = purchase,
        financedAmount = financed,
        otherFundingAmount = AGFCurrency.round(purchase - financed),
        budgetExceeded = budgetExceeded,
        financedBudgetExceeded = financeBudgetExceeded,
        unbudgetedCategory = row.unbudgeted == true,
        categoryStatus = copyRow(nextState.categories[category])
    }
end

function AGFCILOCBudgetService.getSummary(state)
    if type(state) ~= "table" or type(state.categories) ~= "table" or type(state.order) ~= "table" then
        return nil, "INVALID_BUDGET_STATE"
    end
    local copy = deepCopyState(state)
    refreshState(copy)
    return copy, nil
end
