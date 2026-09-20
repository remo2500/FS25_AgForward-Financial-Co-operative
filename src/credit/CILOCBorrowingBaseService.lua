-- AgForward Financial Cooperative
-- Pure seasonal borrowing-base calculation for a future Crop Input Line of Credit.
-- This service estimates a policy limit; it does not approve or create credit.

AGFCILOCBorrowingBaseService = {}

local function normalizeNonNegative(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    if number < 0 then return nil end
    return number
end

function AGFCILOCBorrowingBaseService.calculate(cropRows, policy)
    policy = policy or {}
    local advanceRate = normalizeNonNegative(policy.advanceRate or 0)
    if advanceRate == nil or advanceRate > 1 then return false, "INVALID_ADVANCE_RATE" end

    local globalAdjustment = normalizeNonNegative(policy.adjustmentFactor or 1)
    if globalAdjustment == nil then return false, "INVALID_ADJUSTMENT_FACTOR" end

    local grossBudget = 0
    local eligibleBudget = 0
    local rows = {}

    for index, crop in ipairs(cropRows or {}) do
        local acres = normalizeNonNegative(crop.acres)
        local costPerAcre = normalizeNonNegative(crop.costPerAcre)
        local eligibility = normalizeNonNegative(crop.eligibilityPercent == nil and 1 or crop.eligibilityPercent)
        if acres == nil then return false, "INVALID_ACRES_ROW_" .. tostring(index) end
        if costPerAcre == nil then return false, "INVALID_COST_PER_ACRE_ROW_" .. tostring(index) end
        if eligibility == nil or eligibility > 1 then return false, "INVALID_ELIGIBILITY_ROW_" .. tostring(index) end

        local rowBudget = AGFCurrency.round(acres * costPerAcre)
        local rowEligible = AGFCurrency.round(rowBudget * eligibility)
        grossBudget = AGFCurrency.round(grossBudget + rowBudget)
        eligibleBudget = AGFCurrency.round(eligibleBudget + rowEligible)

        table.insert(rows, {
            crop = crop.crop or crop.name or ("row-" .. tostring(index)),
            acres = acres,
            costPerAcre = AGFCurrency.round(costPerAcre),
            eligibilityPercent = eligibility,
            grossBudget = rowBudget,
            eligibleBudget = rowEligible
        })
    end

    local adjustedEligibleBudget = AGFCurrency.round(eligibleBudget * globalAdjustment)
    local calculatedLimit = AGFCurrency.round(adjustedEligibleBudget * advanceRate)

    local maximumLimit = normalizeNonNegative(policy.maximumLimit)
    if policy.maximumLimit ~= nil and maximumLimit == nil then return false, "INVALID_MAXIMUM_LIMIT" end
    if maximumLimit ~= nil then calculatedLimit = math.min(calculatedLimit, AGFCurrency.round(maximumLimit)) end

    local minimumLimit = normalizeNonNegative(policy.minimumLimit)
    if policy.minimumLimit ~= nil and minimumLimit == nil then return false, "INVALID_MINIMUM_LIMIT" end
    if minimumLimit ~= nil and calculatedLimit > 0 then
        calculatedLimit = math.max(calculatedLimit, AGFCurrency.round(minimumLimit))
        if maximumLimit ~= nil then calculatedLimit = math.min(calculatedLimit, AGFCurrency.round(maximumLimit)) end
    end

    return true, {
        rows = rows,
        grossBudget = grossBudget,
        eligibleBudget = eligibleBudget,
        adjustmentFactor = globalAdjustment,
        adjustedEligibleBudget = adjustedEligibleBudget,
        advanceRate = advanceRate,
        calculatedLimit = AGFCurrency.round(calculatedLimit),
        minimumLimit = minimumLimit ~= nil and AGFCurrency.round(minimumLimit) or nil,
        maximumLimit = maximumLimit ~= nil and AGFCurrency.round(maximumLimit) or nil
    }
end
