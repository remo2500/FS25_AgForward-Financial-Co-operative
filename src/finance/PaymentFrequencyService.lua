-- AgForward Financial Cooperative
-- Pure mapping between agricultural payment frequency and FS financial periods.
-- No liability/ledger mutation is performed here.

AGFPaymentFrequency = {
    MONTHLY = 12,
    QUARTERLY = 4,
    SEMI_ANNUAL = 2,
    ANNUAL = 1
}

AGFPaymentFrequencyService = {}

local LABELS = {
    [AGFPaymentFrequency.MONTHLY] = "monthly",
    [AGFPaymentFrequency.QUARTERLY] = "quarterly",
    [AGFPaymentFrequency.SEMI_ANNUAL] = "semiAnnual",
    [AGFPaymentFrequency.ANNUAL] = "annual"
}

local function normalizePositiveInteger(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = math.floor(number)
    if number <= 0 then return nil end
    return number
end

function AGFPaymentFrequencyService.validate(paymentsPerYear)
    local value = normalizePositiveInteger(paymentsPerYear)
    if value == nil then return false, "INVALID_PAYMENTS_PER_YEAR" end
    if AGFRateConvention.PERIODS_PER_YEAR % value ~= 0 then
        return false, "PAYMENT_FREQUENCY_NOT_ALIGNED_TO_FINANCIAL_PERIODS"
    end
    return true, value
end

function AGFPaymentFrequencyService.getIntervalPeriods(paymentsPerYear)
    local valid, valueOrError = AGFPaymentFrequencyService.validate(paymentsPerYear)
    if not valid then return nil, valueOrError end
    return AGFRateConvention.PERIODS_PER_YEAR / valueOrError, nil
end

function AGFPaymentFrequencyService.getLabel(paymentsPerYear)
    local valid, valueOrError = AGFPaymentFrequencyService.validate(paymentsPerYear)
    if not valid then return nil, valueOrError end
    return LABELS[valueOrError] or (tostring(valueOrError) .. "PerYear"), nil
end

function AGFPaymentFrequencyService.countPaymentsForTermMonths(termMonths, paymentsPerYear)
    local months = normalizePositiveInteger(termMonths)
    if months == nil then return nil, "INVALID_TERM_MONTHS" end

    local interval, intervalError = AGFPaymentFrequencyService.getIntervalPeriods(paymentsPerYear)
    if interval == nil then return nil, intervalError end
    if months % interval ~= 0 then
        return nil, "TERM_NOT_ALIGNED_TO_PAYMENT_FREQUENCY"
    end

    return months / interval, nil
end

local function advancePeriod(year, period, delta)
    local absolute = year * AGFRateConvention.PERIODS_PER_YEAR + (period - 1) + delta
    local resultingYear = math.floor(absolute / AGFRateConvention.PERIODS_PER_YEAR)
    local resultingPeriod = (absolute % AGFRateConvention.PERIODS_PER_YEAR) + 1
    return resultingYear, resultingPeriod
end

function AGFPaymentFrequencyService.buildDueSchedule(startYear, startPeriod, paymentCount, paymentsPerYear, firstPaymentDelayPeriods)
    local year = normalizePositiveInteger(startYear)
    local period = normalizePositiveInteger(startPeriod)
    local count = normalizePositiveInteger(paymentCount)
    if year == nil then return nil, "INVALID_START_YEAR" end
    if period == nil or period > AGFRateConvention.PERIODS_PER_YEAR then return nil, "INVALID_START_PERIOD" end
    if count == nil then return nil, "INVALID_PAYMENT_COUNT" end

    local interval, intervalError = AGFPaymentFrequencyService.getIntervalPeriods(paymentsPerYear)
    if interval == nil then return nil, intervalError end

    local firstDelay = firstPaymentDelayPeriods == nil and interval or normalizePositiveInteger(firstPaymentDelayPeriods)
    if firstDelay == nil then return nil, "INVALID_FIRST_PAYMENT_DELAY" end

    local schedule = {}
    for index = 1, count do
        local offset = firstDelay + ((index - 1) * interval)
        local dueYear, duePeriod = advancePeriod(year, period, offset)
        table.insert(schedule, {
            paymentNumber = index,
            dueYear = dueYear,
            duePeriod = duePeriod,
            periodsFromStart = offset
        })
    end

    return {
        paymentsPerYear = paymentsPerYear,
        intervalPeriods = interval,
        paymentCount = count,
        startYear = year,
        startPeriod = period,
        firstPaymentDelayPeriods = firstDelay,
        schedule = schedule
    }, nil
end
