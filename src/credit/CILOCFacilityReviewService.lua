-- AgForward Financial Cooperative
-- Pure integrated review of a Crop Input LOC. Combines budget, borrowing-base,
-- utilization, reservation, and season/cleanup information for underwriting and
-- reporting. It does not authorize draws or mutate any source state.

AGFCILOCFacilityReviewService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function copyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function summarizeFinancedBudgets(budgetSummary)
    local totalCap = 0
    local totalRemaining = 0
    local cappedCategoryCount = 0
    local overFinancedBudget = 0
    local unbudgetedCategories = 0
    local overBudgetCategories = 0

    for _, category in ipairs(budgetSummary.order or {}) do
        local row = budgetSummary.categories[category]
        if row ~= nil then
            if row.maxFinancedAmount ~= nil then
                cappedCategoryCount = cappedCategoryCount + 1
                totalCap = AGFCurrency.round(totalCap + (row.maxFinancedAmount or 0))
                totalRemaining = AGFCurrency.round(totalRemaining + math.max(0, row.remainingFinancedBudget or 0))
                overFinancedBudget = AGFCurrency.round(overFinancedBudget + math.max(0, row.overFinancedBudgetAmount or 0))
            end
            if row.unbudgeted == true and (row.actualSpend or 0) > 0 then
                unbudgetedCategories = unbudgetedCategories + 1
            end
            if (row.overBudgetAmount or 0) > 0 then
                overBudgetCategories = overBudgetCategories + 1
            end
        end
    end

    return {
        cappedCategoryCount = cappedCategoryCount,
        totalFinancedCategoryCap = totalCap,
        remainingFinancedCategoryCap = totalRemaining,
        overFinancedCategoryCap = overFinancedBudget,
        unbudgetedCategoryCount = unbudgetedCategories,
        overBudgetCategoryCount = overBudgetCategories
    }
end

function AGFCILOCFacilityReviewService.review(parameters)
    parameters = parameters or {}

    local creditLimit = money(parameters.creditLimit)
    local principal = money(parameters.principalBalance)
    local reserved = money(parameters.reservedAmount or 0)
    if creditLimit == nil or creditLimit <= 0 then return false, "INVALID_CREDIT_LIMIT" end
    if principal == nil then return false, "INVALID_PRINCIPAL_BALANCE" end
    if reserved == nil then return false, "INVALID_RESERVED_AMOUNT" end

    local budgetSummary = nil
    if parameters.budgetState ~= nil then
        budgetSummary = AGFCILOCBudgetService.getSummary(parameters.budgetState)
        if budgetSummary == nil then return false, "INVALID_BUDGET_STATE" end
    end

    local borrowingBaseSummary = nil
    local borrowingBase = nil
    if parameters.cropRows ~= nil then
        local baseOk, baseOrError = AGFCILOCBorrowingBaseService.calculate(parameters.cropRows, parameters.borrowingBasePolicy or {})
        if not baseOk then return false, baseOrError end
        borrowingBaseSummary = baseOrError
        borrowingBase = borrowingBaseSummary.calculatedLimit
    elseif parameters.borrowingBase ~= nil then
        borrowingBase = money(parameters.borrowingBase)
        if borrowingBase == nil then return false, "INVALID_BORROWING_BASE" end
    end

    local seasonParameters = copyTable(parameters.seasonParameters)
    seasonParameters.creditLimit = creditLimit
    seasonParameters.principalBalance = principal
    seasonParameters.reservedAmount = reserved
    seasonParameters.borrowingBase = borrowingBase

    local seasonOk, seasonOrError = AGFCILOCSeasonService.assess(seasonParameters)
    if not seasonOk then return false, seasonOrError end
    local season = seasonOrError

    local usedCapacity = season.usedCapacity
    local utilization = season.effectiveLimit > 0 and usedCapacity / season.effectiveLimit or nil
    local principalUtilization = season.effectiveLimit > 0 and principal / season.effectiveLimit or nil

    local budgetMetrics = nil
    if budgetSummary ~= nil then
        local financedCaps = summarizeFinancedBudgets(budgetSummary)
        local totalPlanned = budgetSummary.totalPlannedBudget or 0
        local totalActual = budgetSummary.totalActualSpend or 0
        local totalFinanced = budgetSummary.totalFinancedSpend or 0
        local facilityCoverageOfPlannedBudget = totalPlanned > 0 and season.effectiveLimit / totalPlanned or nil
        local financedShareOfActual = totalActual > 0 and totalFinanced / totalActual or nil

        budgetMetrics = {
            totalPlannedBudget = totalPlanned,
            totalActualSpend = totalActual,
            totalFinancedSpend = totalFinanced,
            totalCashOrOtherFunding = budgetSummary.totalCashOrOtherFunding or 0,
            remainingPlannedBudget = budgetSummary.remainingPlannedBudget or 0,
            overBudgetAmount = budgetSummary.overBudgetAmount or 0,
            budgetUtilization = totalPlanned > 0 and totalActual / totalPlanned or nil,
            financedShareOfActual = financedShareOfActual,
            facilityCoverageOfPlannedBudget = facilityCoverageOfPlannedBudget,
            cappedCategoryCount = financedCaps.cappedCategoryCount,
            totalFinancedCategoryCap = financedCaps.totalFinancedCategoryCap,
            remainingFinancedCategoryCap = financedCaps.remainingFinancedCategoryCap,
            overFinancedCategoryCap = financedCaps.overFinancedCategoryCap,
            unbudgetedCategoryCount = financedCaps.unbudgetedCategoryCount,
            overBudgetCategoryCount = financedCaps.overBudgetCategoryCount
        }
    end

    local flags = {
        overEffectiveLimit = season.overEffectiveLimit > 0,
        drawsFrozen = season.drawsFrozen == true,
        cleanupRequired = season.requiredCleanupPaydown > 0,
        cleanupSatisfied = season.cleanupSatisfied == true,
        renewalRequired = season.renewalRequired == true,
        budgetOverrun = budgetMetrics ~= nil and budgetMetrics.overBudgetAmount > 0 or false,
        financedCategoryOverrun = budgetMetrics ~= nil and budgetMetrics.overFinancedCategoryCap > 0 or false,
        hasUnbudgetedSpend = budgetMetrics ~= nil and budgetMetrics.unbudgetedCategoryCount > 0 or false
    }

    local attentionItems = {}
    local function addAttention(code, amount)
        table.insert(attentionItems, {code = code, amount = amount})
    end
    if flags.overEffectiveLimit then addAttention("OVER_EFFECTIVE_LIMIT", season.overEffectiveLimit) end
    if flags.cleanupRequired and season.state ~= AGFCILOCSeasonState.ACTIVE_SEASON then
        addAttention("CLEANUP_PAYDOWN_REQUIRED", season.requiredCleanupPaydown)
    end
    if flags.renewalRequired then addAttention("MATURITY_RENEWAL_OR_PAYDOWN_REQUIRED", season.requiredCleanupPaydown) end
    if flags.budgetOverrun then addAttention("INPUT_BUDGET_OVERRUN", budgetMetrics.overBudgetAmount) end
    if flags.financedCategoryOverrun then addAttention("FINANCED_CATEGORY_BUDGET_OVERRUN", budgetMetrics.overFinancedCategoryCap) end
    if flags.hasUnbudgetedSpend then addAttention("UNBUDGETED_ELIGIBLE_INPUT_SPEND", nil) end

    return true, {
        creditLimit = creditLimit,
        borrowingBase = borrowingBase,
        borrowingBaseSummary = borrowingBaseSummary,
        effectiveLimit = season.effectiveLimit,
        principalBalance = principal,
        reservedAmount = reserved,
        usedCapacity = usedCapacity,
        availableCapacity = season.availableCapacity,
        baseAvailableCapacity = season.baseAvailableCapacity,
        utilization = utilization,
        principalUtilization = principalUtilization,
        season = season,
        budget = budgetMetrics,
        flags = flags,
        attentionItems = attentionItems
    }
end
