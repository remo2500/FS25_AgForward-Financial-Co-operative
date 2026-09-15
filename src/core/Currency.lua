-- AgForward Financial Cooperative
-- Shared currency normalization. AgForward persists FS-compatible numeric
-- amounts, but all new financial operations normalize to the nearest cent.

AGFCurrency = {}
AGFCurrency.MINOR_UNITS_PER_MAJOR = 100

function AGFCurrency.toMinorUnits(amount)
    local value = tonumber(amount) or 0
    if value >= 0 then
        return math.floor(value * AGFCurrency.MINOR_UNITS_PER_MAJOR + 0.5)
    end
    return math.ceil(value * AGFCurrency.MINOR_UNITS_PER_MAJOR - 0.5)
end

function AGFCurrency.fromMinorUnits(minorUnits)
    return (tonumber(minorUnits) or 0) / AGFCurrency.MINOR_UNITS_PER_MAJOR
end

function AGFCurrency.round(amount)
    return AGFCurrency.fromMinorUnits(AGFCurrency.toMinorUnits(amount))
end

function AGFCurrency.equals(left, right)
    return AGFCurrency.toMinorUnits(left) == AGFCurrency.toMinorUnits(right)
end

function AGFCurrency.isPositive(amount)
    return AGFCurrency.toMinorUnits(amount) > 0
end
