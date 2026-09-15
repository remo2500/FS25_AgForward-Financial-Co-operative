-- AgForward Financial Cooperative
-- Pure componentized loan pricing. Approval/risk-grade thresholds live elsewhere.

AGFRatePricingService = {}
AGFRatePricingService.BASIS_POINT = 0.0001

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function normalizeComponent(value, name)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then
        return nil, "INVALID_" .. tostring(name)
    end
    return number, nil
end

function AGFRatePricingService.roundToBasisPoint(rate)
    local value = tonumber(rate) or 0
    local bp = AGFRatePricingService.BASIS_POINT
    if value >= 0 then
        return math.floor(value / bp + 0.5) * bp
    end
    return math.ceil(value / bp - 0.5) * bp
end

function AGFRatePricingService.quote(components)
    components = components or {}

    local baseRate, baseError = normalizeComponent(components.baseRate, "BASE_RATE")
    if baseRate == nil then return false, baseError end
    if baseRate < 0 then return false, "NEGATIVE_BASE_RATE_NOT_SUPPORTED" end

    local productSpread, productError = normalizeComponent(components.productSpread, "PRODUCT_SPREAD")
    if productSpread == nil then return false, productError end
    local riskSpread, riskError = normalizeComponent(components.riskSpread, "RISK_SPREAD")
    if riskSpread == nil then return false, riskError end
    local termAdjustment, termError = normalizeComponent(components.termAdjustment, "TERM_ADJUSTMENT")
    if termAdjustment == nil then return false, termError end
    local structureAdjustment, structureError = normalizeComponent(components.structureAdjustment, "STRUCTURE_ADJUSTMENT")
    if structureAdjustment == nil then return false, structureError end

    local rawRate = baseRate + productSpread + riskSpread + termAdjustment + structureAdjustment
    if rawRate < 0 then return false, "NEGATIVE_FINAL_RATE" end

    local finalRate = AGFRatePricingService.roundToBasisPoint(rawRate)
    local valid, rateOrError = AGFRateConvention.validateAnnualRate(finalRate)
    if not valid then return false, rateOrError end

    return true, {
        baseRate = AGFRatePricingService.roundToBasisPoint(baseRate),
        productSpread = AGFRatePricingService.roundToBasisPoint(productSpread),
        riskSpread = AGFRatePricingService.roundToBasisPoint(riskSpread),
        termAdjustment = AGFRatePricingService.roundToBasisPoint(termAdjustment),
        structureAdjustment = AGFRatePricingService.roundToBasisPoint(structureAdjustment),
        annualRate = rateOrError,
        annualPercent = rateOrError * 100
    }
end
