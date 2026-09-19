-- AgForward Financial Cooperative
-- Pure view-model builder for the native-style in-game finance frame.
-- It owns no balances and performs no financial mutation.

AGFNativeUIViewModelService = {}

local PRODUCT_KEYS = {
    [AGFProductType.OPERATING_LINE] = "agf_ui_product_operatingLine",
    [AGFProductType.CROP_INPUT_LINE] = "agf_ui_product_cropInputLine",
    [AGFProductType.TERM_LOAN] = "agf_ui_product_termLoan",
    [AGFProductType.EQUIPMENT_FINANCE] = "agf_ui_product_equipmentFinance",
    [AGFProductType.PROJECT_FINANCE] = "agf_ui_product_projectFinance",
    [AGFProductType.LAND_FINANCE] = "agf_ui_product_landFinance",
    [AGFProductType.LAND_LEASE] = "agf_ui_product_landLease"
}

local REPORTS = {
    {id = "financialPosition", titleKey = "agf_ui_report_financialPosition", description = "Assets, liabilities, equity, liquidity and leverage."},
    {id = "debtSchedule", titleKey = "agf_ui_report_debtSchedule", description = "Principal, interest, fees, payments and maturities."},
    {id = "history", titleKey = "agf_ui_report_history", description = "Period and annual financial history from the AgForward ledger."},
    {id = "cropInputs", titleKey = "agf_ui_report_cropInputs", description = "Seed, fertilizer, crop protection, lime and fuel by funding source."},
    {id = "assetsLiens", titleKey = "agf_ui_report_assetsLiens", description = "Economically owned assets, collateral values and active liens."},
    {id = "leases", titleKey = "agf_ui_report_leases", description = "Lease commitments, rent schedule and fixed-charge exposure."}
}

local function money(value)
    return AGFCurrency.round(tonumber(value) or 0)
end

local function ratio(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

local function productKey(productType)
    return PRODUCT_KEYS[productType] or "agf_ui_product_termLoan"
end

local function copyReports()
    local rows = {}
    for _, report in ipairs(REPORTS) do
        local row = {}
        for key, value in pairs(report) do row[key] = value end
        table.insert(rows, row)
    end
    return rows
end

function AGFNativeUIViewModelService.build(context)
    context = context or {}
    local overview = context.overview or {}
    local credit = context.creditProfile or {}
    local diagnostic = context.diagnostic or {}
    local liabilities = context.liabilities or diagnostic.liabilities or {}
    local obligations = context.obligations or {}

    local facilities = {}
    for _, liability in ipairs(liabilities) do
        local isRevolving = liability.productType == AGFProductType.OPERATING_LINE
            or liability.productType == AGFProductType.CROP_INPUT_LINE
        if isRevolving then
            local balance = money(liability.principalBalance)
            local limit = money(liability.creditLimit)
            if limit <= 0 and liability.productType == AGFProductType.OPERATING_LINE then
                limit = money(context.operatingLineLimit)
            elseif limit <= 0 and liability.productType == AGFProductType.CROP_INPUT_LINE then
                limit = money(context.cropInputLineLimit)
            end
            local available = math.max(0, money(limit - balance))

            table.insert(facilities, {
                id = liability.id,
                productType = liability.productType,
                productKey = productKey(liability.productType),
                balance = balance,
                limit = limit,
                available = available,
                interestRate = tonumber(liability.interestRate) or 0,
                status = liability.status or "active",
                outstanding = money(
                    (liability.principalBalance or 0)
                    + (liability.accruedInterest or 0)
                    + (liability.accruedFees or 0)
                )
            })
        end
    end

    table.sort(facilities, function(left, right)
        if left.productType == right.productType then return tostring(left.id) < tostring(right.id) end
        return tostring(left.productType) < tostring(right.productType)
    end)

    local normalizedObligations = {}
    for _, obligation in ipairs(obligations) do
        table.insert(normalizedObligations, {
            id = obligation.id,
            dueYear = obligation.dueYear,
            duePeriod = obligation.duePeriod,
            label = obligation.label or obligation.obligationType or obligation.productType or "obligation",
            amountDue = money(obligation.amountDue),
            status = obligation.status or "scheduled",
            sourceType = obligation.sourceType
        })
    end

    table.sort(normalizedObligations, function(left, right)
        local ly = tonumber(left.dueYear) or 0
        local ry = tonumber(right.dueYear) or 0
        if ly ~= ry then return ly < ry end
        local lp = tonumber(left.duePeriod) or 0
        local rp = tonumber(right.duePeriod) or 0
        if lp ~= rp then return lp < rp end
        return tostring(left.id) < tostring(right.id)
    end)

    return {
        farmId = context.farmId or overview.farmId or diagnostic.farmId,
        currentBalance = money(context.currentBalance or overview.cashBalance),
        overview = {
            cash = money(overview.cashBalance),
            equity = money(overview.representedEquity),
            totalDebt = money(overview.representedLiabilities),
            workingCapital = money(credit.workingCapital),
            dscr = ratio(credit.dscr),
            fixedChargeCoverage = ratio(credit.fixedChargeCoverage),
            debtToAssets = ratio(credit.debtToAssets),
            dataQuality = overview.dataQuality or diagnostic.health or "unknown"
        },
        facilities = facilities,
        obligations = normalizedObligations,
        reports = copyReports(),
        runtime = {
            state = diagnostic.runtimeState,
            health = diagnostic.health,
            writable = diagnostic.writable == true,
            redTapeStatus = diagnostic.redTapeStatus,
            persistenceSource = diagnostic.persistenceSource
        }
    }
end
