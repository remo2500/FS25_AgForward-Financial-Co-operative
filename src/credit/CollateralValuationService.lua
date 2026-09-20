-- AgForward Financial Cooperative
-- Pure collateral-lending-value calculation. Market value is kept separate from
-- policy eligibility, advance rates, and prior claims so underwriting can explain
-- why lending value differs from the asset's displayed economic value.

AGFCollateralValuationService = {}

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

local function ratio(value, defaultValue)
    if value == nil then return defaultValue end
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number < 0 or number > 1 then return nil end
    return number
end

function AGFCollateralValuationService.evaluate(assetRows, proposedSecuredDebt)
    local proposedDebt = money(proposedSecuredDebt or 0)
    if proposedDebt == nil then return false, "INVALID_PROPOSED_SECURED_DEBT" end

    local seen = {}
    local rows = {}
    local grossMarketValue = 0
    local eligibleMarketValue = 0
    local grossLendingValue = 0
    local priorClaims = 0
    local netLendingValue = 0

    for index, source in ipairs(assetRows or {}) do
        source = source or {}
        local assetId = source.assetId ~= nil and tostring(source.assetId) or nil
        if assetId == nil or assetId == "" then return false, "ASSET_ID_REQUIRED_ROW_" .. tostring(index) end
        if seen[assetId] then return false, "DUPLICATE_ASSET_ID:" .. assetId end
        seen[assetId] = true

        local marketValue = money(source.marketValue)
        if marketValue == nil then return false, "INVALID_MARKET_VALUE_ROW_" .. tostring(index) end
        local eligibilityPercent = ratio(source.eligibilityPercent, 1)
        if eligibilityPercent == nil then return false, "INVALID_ELIGIBILITY_ROW_" .. tostring(index) end
        local advanceRate = ratio(source.advanceRate, 1)
        if advanceRate == nil then return false, "INVALID_ADVANCE_RATE_ROW_" .. tostring(index) end
        local existingPriorClaims = money(source.priorClaims or 0)
        if existingPriorClaims == nil then return false, "INVALID_PRIOR_CLAIMS_ROW_" .. tostring(index) end

        local rowEligibleValue = AGFCurrency.round(marketValue * eligibilityPercent)
        local rowGrossLendingValue = AGFCurrency.round(rowEligibleValue * advanceRate)
        local rowNetLendingValue = math.max(0, AGFCurrency.round(rowGrossLendingValue - existingPriorClaims))

        grossMarketValue = AGFCurrency.round(grossMarketValue + marketValue)
        eligibleMarketValue = AGFCurrency.round(eligibleMarketValue + rowEligibleValue)
        grossLendingValue = AGFCurrency.round(grossLendingValue + rowGrossLendingValue)
        priorClaims = AGFCurrency.round(priorClaims + existingPriorClaims)
        netLendingValue = AGFCurrency.round(netLendingValue + rowNetLendingValue)

        table.insert(rows, {
            assetId = assetId,
            assetType = source.assetType,
            marketValue = marketValue,
            eligibilityPercent = eligibilityPercent,
            eligibleMarketValue = rowEligibleValue,
            advanceRate = advanceRate,
            grossLendingValue = rowGrossLendingValue,
            priorClaims = existingPriorClaims,
            netLendingValue = rowNetLendingValue,
            exhaustedByPriorClaims = rowNetLendingValue <= 0 and existingPriorClaims > 0
        })
    end

    local grossLtv = nil
    if eligibleMarketValue > 0 and proposedDebt > 0 then grossLtv = proposedDebt / eligibleMarketValue end

    local lendingValueLtv = nil
    if grossLendingValue > 0 and proposedDebt > 0 then lendingValueLtv = proposedDebt / grossLendingValue end

    local netCoverage = nil
    if proposedDebt > 0 then netCoverage = netLendingValue / proposedDebt end

    local collateralSurplus = AGFCurrency.round(netLendingValue - proposedDebt)
    local collateralShortfall = math.max(0, AGFCurrency.round(proposedDebt - netLendingValue))

    return true, {
        assets = rows,
        grossMarketValue = grossMarketValue,
        eligibleMarketValue = eligibleMarketValue,
        grossLendingValue = grossLendingValue,
        priorClaims = priorClaims,
        netLendingValue = netLendingValue,
        proposedSecuredDebt = proposedDebt,
        grossLtv = grossLtv,
        lendingValueLtv = lendingValueLtv,
        netCoverage = netCoverage,
        collateralSurplus = collateralSurplus,
        collateralShortfall = collateralShortfall,
        fullyCoveredByPolicyLendingValue = collateralShortfall == 0
    }
end
