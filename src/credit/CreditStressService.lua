-- AgForward Financial Cooperative
-- Pure stress-scenario transforms for credit metrics and seasonal liquidity.
-- This module applies user/policy-supplied shocks; it contains no approval
-- thresholds and performs no FS25 mutation.

AGFCreditStressService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function factor(value, defaultValue)
    if value == nil then return defaultValue end
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number < 0 then return nil end
    return number
end

local function money(value, defaultValue)
    if value == nil then return defaultValue or 0 end
    local number = tonumber(value)
    if number == nil or not isFinite(number) then return nil end
    return AGFCurrency.round(number)
end

local function copyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function applyFactor(value, multiplier)
    return AGFCurrency.round((tonumber(value) or 0) * multiplier)
end

function AGFCreditStressService.stressCreditInputs(baseInputs, scenario)
    baseInputs = baseInputs or {}
    scenario = scenario or {}

    local assetFactor = factor(scenario.assetValueFactor, 1)
    local collateralFactor = factor(scenario.collateralValueFactor, assetFactor)
    local currentAssetFactor = factor(scenario.currentAssetFactor, 1)
    local cashFlowFactor = factor(scenario.cashFlowFactor, 1)
    local debtServiceFactor = factor(scenario.debtServiceFactor, 1)
    local fixedChargeFactor = factor(scenario.fixedChargeFactor, 1)
    local liquidAssetFactor = factor(scenario.liquidAssetFactor, 1)
    local undrawnCreditFactor = factor(scenario.undrawnCreditFactor, 1)
    local obligationFactor = factor(scenario.obligationFactor, 1)
    if assetFactor == nil then return false, "INVALID_ASSET_VALUE_FACTOR" end
    if collateralFactor == nil then return false, "INVALID_COLLATERAL_VALUE_FACTOR" end
    if currentAssetFactor == nil then return false, "INVALID_CURRENT_ASSET_FACTOR" end
    if cashFlowFactor == nil then return false, "INVALID_CASH_FLOW_FACTOR" end
    if debtServiceFactor == nil then return false, "INVALID_DEBT_SERVICE_FACTOR" end
    if fixedChargeFactor == nil then return false, "INVALID_FIXED_CHARGE_FACTOR" end
    if liquidAssetFactor == nil then return false, "INVALID_LIQUID_ASSET_FACTOR" end
    if undrawnCreditFactor == nil then return false, "INVALID_UNDRAWN_CREDIT_FACTOR" end
    if obligationFactor == nil then return false, "INVALID_OBLIGATION_FACTOR" end

    local revolverPrincipalIncrease = money(scenario.revolverPrincipalIncrease, 0)
    local liabilityIncrease = money(scenario.liabilityIncrease, 0)
    if revolverPrincipalIncrease == nil then return false, "INVALID_REVOLVER_PRINCIPAL_INCREASE" end
    if liabilityIncrease == nil then return false, "INVALID_LIABILITY_INCREASE" end

    local stressed = copyTable(baseInputs)
    stressed.totalAssets = applyFactor(baseInputs.totalAssets, assetFactor)
    stressed.totalLiabilities = AGFCurrency.round((tonumber(baseInputs.totalLiabilities) or 0) + liabilityIncrease)
    stressed.currentAssets = applyFactor(baseInputs.currentAssets, currentAssetFactor)
    stressed.currentLiabilities = AGFCurrency.round((tonumber(baseInputs.currentLiabilities) or 0) + math.max(0, liabilityIncrease))
    stressed.annualDebtService = applyFactor(baseInputs.annualDebtService, debtServiceFactor)
    stressed.annualLeaseAndFixedCharges = applyFactor(baseInputs.annualLeaseAndFixedCharges, fixedChargeFactor)
    stressed.cashAvailableForDebtService = applyFactor(baseInputs.cashAvailableForDebtService, cashFlowFactor)
    stressed.cashAvailableForFixedCharges = applyFactor(
        baseInputs.cashAvailableForFixedCharges or baseInputs.cashAvailableForDebtService,
        cashFlowFactor
    )
    stressed.securedDebt = AGFCurrency.round((tonumber(baseInputs.securedDebt) or 0) + math.max(0, liabilityIncrease))
    stressed.collateralValue = applyFactor(baseInputs.collateralValue, collateralFactor)
    stressed.revolverPrincipal = AGFCurrency.round((tonumber(baseInputs.revolverPrincipal) or 0) + revolverPrincipalIncrease)
    stressed.revolverLimit = AGFCurrency.round(tonumber(baseInputs.revolverLimit) or 0)
    stressed.cashAndLiquidAssets = applyFactor(baseInputs.cashAndLiquidAssets, liquidAssetFactor)
    stressed.undrawnCommittedCredit = applyFactor(baseInputs.undrawnCommittedCredit, undrawnCreditFactor)
    stressed.next12MonthObligations = applyFactor(baseInputs.next12MonthObligations, obligationFactor)

    local baseline = AGFCreditMetrics.buildSnapshot(baseInputs)
    local stressedSnapshot = AGFCreditMetrics.buildSnapshot(stressed)

    return true, {
        name = scenario.name,
        baselineInputs = copyTable(baseInputs),
        stressedInputs = stressed,
        baseline = baseline,
        stressed = stressedSnapshot,
        deltas = {
            equity = stressedSnapshot.equity ~= nil and baseline.equity ~= nil and AGFCurrency.round(stressedSnapshot.equity - baseline.equity) or nil,
            workingCapital = stressedSnapshot.workingCapital ~= nil and baseline.workingCapital ~= nil and AGFCurrency.round(stressedSnapshot.workingCapital - baseline.workingCapital) or nil,
            dscr = stressedSnapshot.dscr ~= nil and baseline.dscr ~= nil and stressedSnapshot.dscr - baseline.dscr or nil,
            fixedChargeCoverage = stressedSnapshot.fixedChargeCoverage ~= nil and baseline.fixedChargeCoverage ~= nil and stressedSnapshot.fixedChargeCoverage - baseline.fixedChargeCoverage or nil,
            debtToAssets = stressedSnapshot.debtToAssets ~= nil and baseline.debtToAssets ~= nil and stressedSnapshot.debtToAssets - baseline.debtToAssets or nil,
            ltv = stressedSnapshot.ltv ~= nil and baseline.ltv ~= nil and stressedSnapshot.ltv - baseline.ltv or nil,
            liquidityCoverage = stressedSnapshot.liquidityCoverage ~= nil and baseline.liquidityCoverage ~= nil and stressedSnapshot.liquidityCoverage - baseline.liquidityCoverage or nil
        },
        assumptions = copyTable(scenario)
    }
end

function AGFCreditStressService.stressLiquidity(baseParameters, scenario)
    baseParameters = baseParameters or {}
    scenario = scenario or {}

    local operatingInflowFactor = factor(scenario.operatingInflowFactor, 1)
    local capitalInflowFactor = factor(scenario.capitalInflowFactor, 1)
    local operatingOutflowFactor = factor(scenario.operatingOutflowFactor, 1)
    local capitalOutflowFactor = factor(scenario.capitalOutflowFactor, 1)
    local debtServiceFactor = factor(scenario.debtServiceFactor, 1)
    local leaseFactor = factor(scenario.leasePaymentFactor, 1)
    local taxFactor = factor(scenario.taxPaymentFactor, 1)
    local creditLimitFactor = factor(scenario.operatingCreditLimitFactor, 1)
    if operatingInflowFactor == nil then return false, "INVALID_OPERATING_INFLOW_FACTOR" end
    if capitalInflowFactor == nil then return false, "INVALID_CAPITAL_INFLOW_FACTOR" end
    if operatingOutflowFactor == nil then return false, "INVALID_OPERATING_OUTFLOW_FACTOR" end
    if capitalOutflowFactor == nil then return false, "INVALID_CAPITAL_OUTFLOW_FACTOR" end
    if debtServiceFactor == nil then return false, "INVALID_DEBT_SERVICE_FACTOR" end
    if leaseFactor == nil then return false, "INVALID_LEASE_PAYMENT_FACTOR" end
    if taxFactor == nil then return false, "INVALID_TAX_PAYMENT_FACTOR" end
    if creditLimitFactor == nil then return false, "INVALID_OPERATING_CREDIT_LIMIT_FACTOR" end

    local stressedParameters = copyTable(baseParameters)
    stressedParameters.operatingCreditLimit = applyFactor(baseParameters.operatingCreditLimit, creditLimitFactor)
    stressedParameters.periods = {}

    for _, sourceRow in ipairs(baseParameters.periods or {}) do
        local row = copyTable(sourceRow)
        row.operatingInflows = applyFactor(sourceRow.operatingInflows, operatingInflowFactor)
        row.capitalInflows = applyFactor(sourceRow.capitalInflows, capitalInflowFactor)
        row.operatingOutflows = applyFactor(sourceRow.operatingOutflows, operatingOutflowFactor)
        row.capitalOutflows = applyFactor(sourceRow.capitalOutflows, capitalOutflowFactor)
        row.debtService = applyFactor(sourceRow.debtService, debtServiceFactor)
        row.leasePayments = applyFactor(sourceRow.leasePayments, leaseFactor)
        row.taxPayments = applyFactor(sourceRow.taxPayments, taxFactor)
        table.insert(stressedParameters.periods, row)
    end

    local baselineOk, baselineOrError = AGFLiquidityProjectionService.project(baseParameters)
    if not baselineOk then return false, "BASELINE_LIQUIDITY_INVALID:" .. tostring(baselineOrError) end
    local stressedOk, stressedOrError = AGFLiquidityProjectionService.project(stressedParameters)
    if not stressedOk then return false, "STRESSED_LIQUIDITY_INVALID:" .. tostring(stressedOrError) end

    return true, {
        name = scenario.name,
        baseline = baselineOrError,
        stressed = stressedOrError,
        stressedParameters = stressedParameters,
        assumptions = copyTable(scenario),
        deltas = {
            endingCash = AGFCurrency.round(stressedOrError.endingCash - baselineOrError.endingCash),
            peakOperatingCreditPrincipal = AGFCurrency.round(stressedOrError.peakOperatingCreditPrincipal - baselineOrError.peakOperatingCreditPrincipal),
            aggregateLiquidityShortfall = AGFCurrency.round(stressedOrError.aggregateLiquidityShortfall - baselineOrError.aggregateLiquidityShortfall)
        }
    }
end
