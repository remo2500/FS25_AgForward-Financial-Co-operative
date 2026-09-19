-- AgForward Financial Cooperative
-- Pure period-by-period liquidity projection for agricultural underwriting.
-- It can model an explicitly authorized operating-credit backstop, but does not
-- create draws, move FS25 money, or decide runtime settlement policy.

AGFLiquidityProjectionService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function money(value, allowNegative)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if not allowNegative and number < 0 then return nil end
    return number
end

local function positiveInteger(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

local function normalizePeriodRow(row, index)
    row = row or {}
    local inflowFields = {"operatingInflows", "capitalInflows", "otherInflows"}
    local outflowFields = {"operatingOutflows", "capitalOutflows", "debtService", "leasePayments", "taxPayments", "otherOutflows"}
    local normalized = {
        label = row.label,
        year = row.year ~= nil and positiveInteger(row.year) or nil,
        period = row.period ~= nil and positiveInteger(row.period) or nil
    }

    if row.period ~= nil and (normalized.period == nil or normalized.period > 12) then
        return nil, "INVALID_PERIOD_ROW_" .. tostring(index)
    end
    if row.year ~= nil and normalized.year == nil then
        return nil, "INVALID_YEAR_ROW_" .. tostring(index)
    end

    local totalInflows = 0
    for _, field in ipairs(inflowFields) do
        local value = money(row[field], false)
        if value == nil then return nil, "INVALID_" .. string.upper(field) .. "_ROW_" .. tostring(index) end
        normalized[field] = value
        totalInflows = AGFCurrency.round(totalInflows + value)
    end

    local totalOutflows = 0
    for _, field in ipairs(outflowFields) do
        local value = money(row[field], false)
        if value == nil then return nil, "INVALID_" .. string.upper(field) .. "_ROW_" .. tostring(index) end
        normalized[field] = value
        totalOutflows = AGFCurrency.round(totalOutflows + value)
    end

    normalized.totalInflows = totalInflows
    normalized.totalOutflows = totalOutflows
    normalized.netBeforeFinancing = AGFCurrency.round(totalInflows - totalOutflows)
    return normalized, nil
end

function AGFLiquidityProjectionService.project(parameters)
    parameters = parameters or {}

    local openingCash = money(parameters.openingCash, false)
    local minimumCash = money(parameters.minimumCashBalance or 0, false)
    local creditLimit = money(parameters.operatingCreditLimit or 0, false)
    local openingCreditPrincipal = money(parameters.openingOperatingCreditPrincipal or 0, false)
    if openingCash == nil then return false, "INVALID_OPENING_CASH" end
    if minimumCash == nil then return false, "INVALID_MINIMUM_CASH" end
    if creditLimit == nil then return false, "INVALID_OPERATING_CREDIT_LIMIT" end
    if openingCreditPrincipal == nil then return false, "INVALID_OPENING_CREDIT_PRINCIPAL" end
    if AGFCurrency.toMinorUnits(openingCreditPrincipal) > AGFCurrency.toMinorUnits(creditLimit) then
        return false, "OPENING_CREDIT_EXCEEDS_LIMIT"
    end

    local autoDraw = parameters.autoDrawToMinimumCash == true
    local autoRepay = parameters.autoRepayExcessCash == true
    local cash = openingCash
    local creditPrincipal = openingCreditPrincipal
    local rows = {}
    local totalInflows = 0
    local totalOutflows = 0
    local totalDraws = 0
    local totalRepayments = 0
    local peakCreditPrincipal = creditPrincipal
    local lowestCash = cash
    local aggregateLiquidityShortfall = 0
    local shortfallPeriods = 0

    for index, rawRow in ipairs(parameters.periods or {}) do
        local row, rowError = normalizePeriodRow(rawRow, index)
        if row == nil then return false, rowError end

        row.openingCash = cash
        row.openingOperatingCreditPrincipal = creditPrincipal
        local cashBeforeFinancing = AGFCurrency.round(cash + row.netBeforeFinancing)
        row.cashBeforeFinancing = cashBeforeFinancing
        row.creditDraw = 0
        row.creditRepayment = 0
        row.liquidityShortfall = 0

        if autoDraw and cashBeforeFinancing < minimumCash then
            local required = AGFCurrency.round(minimumCash - cashBeforeFinancing)
            local availableCredit = math.max(0, AGFCurrency.round(creditLimit - creditPrincipal))
            local draw = math.min(required, availableCredit)
            row.creditDraw = AGFCurrency.round(draw)
            creditPrincipal = AGFCurrency.round(creditPrincipal + row.creditDraw)
            cashBeforeFinancing = AGFCurrency.round(cashBeforeFinancing + row.creditDraw)
            totalDraws = AGFCurrency.round(totalDraws + row.creditDraw)
        end

        if autoRepay and cashBeforeFinancing > minimumCash and creditPrincipal > 0 then
            local excess = AGFCurrency.round(cashBeforeFinancing - minimumCash)
            local repayment = math.min(excess, creditPrincipal)
            row.creditRepayment = AGFCurrency.round(repayment)
            creditPrincipal = AGFCurrency.round(creditPrincipal - row.creditRepayment)
            cashBeforeFinancing = AGFCurrency.round(cashBeforeFinancing - row.creditRepayment)
            totalRepayments = AGFCurrency.round(totalRepayments + row.creditRepayment)
        end

        if cashBeforeFinancing < minimumCash then
            row.liquidityShortfall = AGFCurrency.round(minimumCash - cashBeforeFinancing)
            aggregateLiquidityShortfall = AGFCurrency.round(aggregateLiquidityShortfall + row.liquidityShortfall)
            shortfallPeriods = shortfallPeriods + 1
        end

        row.endingCash = cashBeforeFinancing
        row.endingOperatingCreditPrincipal = creditPrincipal
        row.availableOperatingCredit = math.max(0, AGFCurrency.round(creditLimit - creditPrincipal))
        cash = row.endingCash

        totalInflows = AGFCurrency.round(totalInflows + row.totalInflows)
        totalOutflows = AGFCurrency.round(totalOutflows + row.totalOutflows)
        peakCreditPrincipal = math.max(peakCreditPrincipal, creditPrincipal)
        lowestCash = math.min(lowestCash, cash)
        table.insert(rows, row)
    end

    local totalNetBeforeFinancing = AGFCurrency.round(totalInflows - totalOutflows)
    local endingAvailableCredit = math.max(0, AGFCurrency.round(creditLimit - creditPrincipal))

    return true, {
        openingCash = openingCash,
        minimumCashBalance = minimumCash,
        operatingCreditLimit = creditLimit,
        openingOperatingCreditPrincipal = openingCreditPrincipal,
        periods = rows,
        totalInflows = totalInflows,
        totalOutflows = totalOutflows,
        totalNetBeforeFinancing = totalNetBeforeFinancing,
        totalCreditDraws = totalDraws,
        totalCreditRepayments = totalRepayments,
        peakOperatingCreditPrincipal = AGFCurrency.round(peakCreditPrincipal),
        endingOperatingCreditPrincipal = creditPrincipal,
        endingAvailableOperatingCredit = endingAvailableCredit,
        endingCash = cash,
        lowestProjectedCash = AGFCurrency.round(lowestCash),
        aggregateLiquidityShortfall = aggregateLiquidityShortfall,
        shortfallPeriods = shortfallPeriods,
        liquidityAdequate = shortfallPeriods == 0,
        autoDrawToMinimumCash = autoDraw,
        autoRepayExcessCash = autoRepay
    }
end
