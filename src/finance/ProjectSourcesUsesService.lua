-- AgForward Financial Cooperative
-- Pure project/facility finance sources-and-uses reconciliation. This service
-- calculates financing need and funding composition but performs no purchase.

AGFProjectUseType = {
    CONSTRUCTION = "construction",
    GROUNDWORK = "groundwork",
    EQUIPMENT = "equipment",
    PROFESSIONAL_FEES = "professionalFees",
    FINANCE_FEES = "financeFees",
    OTHER = "other"
}

AGFProjectSourceType = {
    CASH_EQUITY = "cashEquity",
    GRANT = "grant",
    OTHER_NON_DEBT = "otherNonDebt",
    AGFORWARD_LOAN = "agForwardLoan",
    OTHER_DEBT = "otherDebt"
}

AGFProjectSourcesUsesService = {}

local function normalizeAmount(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function normalizeRows(rows, kind)
    local result = {}
    local total = 0
    for index, row in ipairs(rows or {}) do
        local amount = normalizeAmount(row.amount)
        if amount == nil then return nil, nil, "INVALID_" .. kind .. "_AMOUNT_ROW_" .. tostring(index) end
        if amount > 0 then
            local copy = {
                type = row.type or "other",
                amount = amount,
                description = row.description,
                reference = row.reference,
                eligibleForCollateral = row.eligibleForCollateral == true,
                taxableOrGrantTreatment = row.taxableOrGrantTreatment
            }
            table.insert(result, copy)
            total = AGFCurrency.round(total + amount)
        end
    end
    return result, total, nil
end

function AGFProjectSourcesUsesService.calculateFinancingNeed(uses, nonDebtSources, options)
    options = options or {}
    local useRows, totalUses, useError = normalizeRows(uses, "USE")
    if useRows == nil then return false, useError end
    if totalUses <= 0 then return false, "PROJECT_HAS_NO_USES" end

    local sourceRows, totalNonDebt, sourceError = normalizeRows(nonDebtSources, "SOURCE")
    if sourceRows == nil then return false, sourceError end

    if AGFCurrency.toMinorUnits(totalNonDebt) > AGFCurrency.toMinorUnits(totalUses) then
        return false, "NON_DEBT_SOURCES_EXCEED_PROJECT_USES"
    end

    local financingNeed = AGFCurrency.round(totalUses - totalNonDebt)
    local maximumLoan = options.maximumLoan ~= nil and normalizeAmount(options.maximumLoan) or nil
    if options.maximumLoan ~= nil and maximumLoan == nil then return false, "INVALID_MAXIMUM_LOAN" end

    local proposedLoan = financingNeed
    if maximumLoan ~= nil then proposedLoan = math.min(proposedLoan, maximumLoan) end
    local fundingGap = AGFCurrency.round(financingNeed - proposedLoan)

    local collateralEligibleUses = 0
    for _, row in ipairs(useRows) do
        if row.eligibleForCollateral then
            collateralEligibleUses = AGFCurrency.round(collateralEligibleUses + row.amount)
        end
    end

    return true, {
        uses = useRows,
        nonDebtSources = sourceRows,
        totalUses = totalUses,
        totalNonDebtSources = totalNonDebt,
        financingNeed = financingNeed,
        proposedAgForwardLoan = AGFCurrency.round(proposedLoan),
        fundingGap = fundingGap,
        fullyFunded = AGFCurrency.equals(fundingGap, 0),
        collateralEligibleUses = collateralEligibleUses,
        loanToCost = totalUses > 0 and proposedLoan / totalUses or nil,
        cashAndGrantShare = totalUses > 0 and totalNonDebt / totalUses or nil
    }
end

function AGFProjectSourcesUsesService.reconcile(uses, sources)
    local useRows, totalUses, useError = normalizeRows(uses, "USE")
    if useRows == nil then return false, useError end
    local sourceRows, totalSources, sourceError = normalizeRows(sources, "SOURCE")
    if sourceRows == nil then return false, sourceError end

    local difference = AGFCurrency.round(totalSources - totalUses)
    return true, {
        uses = useRows,
        sources = sourceRows,
        totalUses = totalUses,
        totalSources = totalSources,
        difference = difference,
        balanced = AGFCurrency.equals(difference, 0),
        overfunded = difference > 0,
        underfunded = difference < 0
    }
end

function AGFProjectSourcesUsesService.buildSources(cashContribution, grantContribution, agForwardLoan, otherNonDebt, otherDebt)
    local rows = {}
    local function add(sourceType, amount, description)
        local normalized = normalizeAmount(amount or 0)
        if normalized == nil then return false end
        if normalized > 0 then
            table.insert(rows, {type = sourceType, amount = normalized, description = description})
        end
        return true
    end

    if not add(AGFProjectSourceType.CASH_EQUITY, cashContribution, "Cash equity") then return nil, "INVALID_CASH_CONTRIBUTION" end
    if not add(AGFProjectSourceType.GRANT, grantContribution, "Grant/program funding") then return nil, "INVALID_GRANT_CONTRIBUTION" end
    if not add(AGFProjectSourceType.AGFORWARD_LOAN, agForwardLoan, "AgForward financing") then return nil, "INVALID_AGFORWARD_LOAN" end
    if not add(AGFProjectSourceType.OTHER_NON_DEBT, otherNonDebt, "Other non-debt source") then return nil, "INVALID_OTHER_NON_DEBT" end
    if not add(AGFProjectSourceType.OTHER_DEBT, otherDebt, "Other debt") then return nil, "INVALID_OTHER_DEBT" end
    return rows, nil
end
