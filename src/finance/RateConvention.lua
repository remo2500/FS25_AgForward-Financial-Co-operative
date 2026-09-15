-- AgForward Financial Cooperative
-- Shared pure-math rate convention. This module performs no FS25 money movement.

AGFRateConvention = {}
AGFRateConvention.PERIODS_PER_YEAR = 12

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

function AGFRateConvention.validateAnnualRate(annualRate)
    local value = tonumber(annualRate)
    if value == nil or not isFinite(value) then
        return false, "INVALID_RATE"
    end
    if value < 0 then
        return false, "NEGATIVE_RATE_NOT_SUPPORTED"
    end
    return true, value
end

function AGFRateConvention.toPeriodicRate(annualRate, periodsPerYear)
    local valid, valueOrError = AGFRateConvention.validateAnnualRate(annualRate)
    if not valid then
        return nil, valueOrError
    end

    local periods = math.floor(tonumber(periodsPerYear) or AGFRateConvention.PERIODS_PER_YEAR)
    if periods <= 0 then
        return nil, "INVALID_PERIODS_PER_YEAR"
    end

    return valueOrError / periods, nil
end

function AGFRateConvention.toDisplayPercent(annualRate)
    local valid, valueOrError = AGFRateConvention.validateAnnualRate(annualRate)
    if not valid then
        return nil, valueOrError
    end
    return valueOrError * 100, nil
end

function AGFRateConvention.fromDisplayPercent(percent)
    local value = tonumber(percent)
    if value == nil or not isFinite(value) then
        return nil, "INVALID_PERCENT"
    end

    local valid, rateOrError = AGFRateConvention.validateAnnualRate(value / 100)
    if not valid then
        return nil, rateOrError
    end
    return rateOrError, nil
end
