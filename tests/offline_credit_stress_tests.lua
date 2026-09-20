-- Offline validation for configurable credit and liquidity stress scenarios.

dofile("src/core/Currency.lua")
dofile("src/credit/CreditMetrics.lua")
dofile("src/credit/LiquidityProjectionService.lua")
dofile("src/credit/CreditStressService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local function assertFalse(value, message)
    if value ~= false then error(message or "expected false") end
end

local baseInputs = {
    totalAssets = 2000000,
    totalLiabilities = 800000,
    currentAssets = 350000,
    currentLiabilities = 150000,
    annualDebtService = 120000,
    annualLeaseAndFixedCharges = 30000,
    cashAvailableForDebtService = 240000,
    cashAvailableForFixedCharges = 255000,
    securedDebt = 600000,
    collateralValue = 1200000,
    revolverPrincipal = 50000,
    revolverLimit = 250000,
    cashAndLiquidAssets = 100000,
    undrawnCommittedCredit = 200000,
    next12MonthObligations = 180000
}

local stressOk, stress = AGFCreditStressService.stressCreditInputs(baseInputs, {
    name = "crop-margin-compression",
    assetValueFactor = 0.90,
    collateralValueFactor = 0.85,
    currentAssetFactor = 0.80,
    cashFlowFactor = 0.70,
    debtServiceFactor = 1.10,
    fixedChargeFactor = 1.00,
    liquidAssetFactor = 0.75,
    undrawnCreditFactor = 0.70,
    obligationFactor = 1.10,
    revolverPrincipalIncrease = 50000
})
assertTrue(stressOk, "credit stress succeeds")
assertTrue(stress.stressed.totalAssets < stress.baseline.totalAssets, "asset stress reduces assets")
assertTrue(stress.stressed.collateralValue < stress.baseline.collateralValue, "collateral stress reduces collateral")
assertTrue(stress.stressed.dscr < stress.baseline.dscr, "cash/debt stress reduces DSCR")
assertTrue(stress.stressed.debtToAssets > stress.baseline.debtToAssets, "leverage worsens")
assertTrue(stress.stressed.ltv > stress.baseline.ltv, "LTV worsens")
assertTrue(stress.stressed.liquidityCoverage < stress.baseline.liquidityCoverage, "liquidity coverage worsens")
assertEqual(stress.stressed.revolverPrincipal, 100000, "revolver shock applied")

-- A liability shock can be modeled independently from operating cash-flow shocks.
local debtShockOk, debtShock = AGFCreditStressService.stressCreditInputs(baseInputs, {
    liabilityIncrease = 200000
})
assertTrue(debtShockOk, "liability stress succeeds")
assertEqual(debtShock.stressed.totalLiabilities, 1000000, "liability increase")
assertEqual(debtShock.stressed.currentLiabilities, 350000, "current-liability shock")
assertTrue(debtShock.stressed.debtToAssets > debtShock.baseline.debtToAssets, "debt/assets worsens")

local baseLiquidity = {
    openingCash = 50000,
    minimumCashBalance = 20000,
    operatingCreditLimit = 150000,
    openingOperatingCreditPrincipal = 0,
    autoDrawToMinimumCash = true,
    autoRepayExcessCash = true,
    periods = {
        {year = 1, period = 1, operatingOutflows = 70000},
        {year = 1, period = 2, operatingOutflows = 80000},
        {year = 1, period = 3, operatingInflows = 50000, operatingOutflows = 30000},
        {year = 1, period = 4, operatingInflows = 180000, operatingOutflows = 20000}
    }
}

local liquidityStressOk, liquidityStress = AGFCreditStressService.stressLiquidity(baseLiquidity, {
    name = "lower-yield-higher-input-cost",
    operatingInflowFactor = 0.70,
    operatingOutflowFactor = 1.20,
    operatingCreditLimitFactor = 0.80
})
assertTrue(liquidityStressOk, "liquidity stress succeeds")
assertTrue(liquidityStress.stressed.totalInflows < liquidityStress.baseline.totalInflows, "stressed inflows lower")
assertTrue(liquidityStress.stressed.totalOutflows > liquidityStress.baseline.totalOutflows, "stressed outflows higher")
assertTrue(liquidityStress.stressed.operatingCreditLimit < liquidityStress.baseline.operatingCreditLimit, "credit capacity stress lower")
assertTrue(liquidityStress.stressed.peakOperatingCreditPrincipal >= liquidityStress.baseline.peakOperatingCreditPrincipal, "peak utilization not improved")
assertTrue(liquidityStress.stressed.endingCash <= liquidityStress.baseline.endingCash, "ending cash not improved")

-- Invalid negative factors are rejected rather than producing nonsensical metrics.
local invalidOk, invalidError = AGFCreditStressService.stressCreditInputs(baseInputs, {cashFlowFactor = -0.1})
assertFalse(invalidOk, "negative stress factor rejected")
assertEqual(invalidError, "INVALID_CASH_FLOW_FACTOR", "negative factor error")

local badLiquidityOk, badLiquidityError = AGFCreditStressService.stressLiquidity(baseLiquidity, {operatingOutflowFactor = -1})
assertFalse(badLiquidityOk, "negative liquidity factor rejected")
assertEqual(badLiquidityError, "INVALID_OPERATING_OUTFLOW_FACTOR", "negative liquidity factor error")

print("offline_credit_stress_tests: PASS")
