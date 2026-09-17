-- Offline validation for seasonal agricultural liquidity projection.

dofile("src/core/Currency.lua")
dofile("src/credit/LiquidityProjectionService.lua")

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

-- Seasonal farm: spring inputs create a borrowing need; fall grain sales repay it.
local seasonalOk, seasonal = AGFLiquidityProjectionService.project({
    openingCash = 75000,
    minimumCashBalance = 25000,
    operatingCreditLimit = 250000,
    openingOperatingCreditPrincipal = 0,
    autoDrawToMinimumCash = true,
    autoRepayExcessCash = true,
    periods = {
        {year = 1, period = 1, operatingOutflows = 60000, debtService = 10000},
        {year = 1, period = 2, operatingOutflows = 90000},
        {year = 1, period = 3, operatingOutflows = 70000},
        {year = 1, period = 4, operatingInflows = 35000, operatingOutflows = 25000},
        {year = 1, period = 5, operatingOutflows = 15000},
        {year = 1, period = 6, operatingOutflows = 15000},
        {year = 1, period = 7, operatingOutflows = 15000},
        {year = 1, period = 8, operatingInflows = 250000, operatingOutflows = 30000},
        {year = 1, period = 9, operatingInflows = 120000, operatingOutflows = 20000},
        {year = 1, period = 10, operatingInflows = 50000, debtService = 15000},
        {year = 1, period = 11, operatingOutflows = 10000},
        {year = 1, period = 12, operatingOutflows = 10000}
    }
})
assertTrue(seasonalOk, "seasonal projection succeeds")
assertTrue(seasonal.totalCreditDraws > 0, "spring requires operating credit")
assertTrue(seasonal.peakOperatingCreditPrincipal > 0, "line reaches positive peak")
assertEqual(seasonal.aggregateLiquidityShortfall, 0, "line covers seasonal shortfall")
assertTrue(seasonal.liquidityAdequate, "seasonal liquidity adequate")
assertTrue(seasonal.totalCreditRepayments > 0, "harvest cash repays line")
assertEqual(seasonal.endingOperatingCreditPrincipal, 0, "line cleans up by year end")
assertTrue(seasonal.endingCash >= 25000, "minimum cash retained")

-- Same operation without a sufficient line must expose the unmet liquidity gap.
local constrainedOk, constrained = AGFLiquidityProjectionService.project({
    openingCash = 20000,
    minimumCashBalance = 15000,
    operatingCreditLimit = 30000,
    openingOperatingCreditPrincipal = 0,
    autoDrawToMinimumCash = true,
    autoRepayExcessCash = false,
    periods = {
        {year = 2, period = 1, operatingOutflows = 60000},
        {year = 2, period = 2, operatingOutflows = 25000}
    }
})
assertTrue(constrainedOk, "constrained projection succeeds")
assertEqual(constrained.totalCreditDraws, 30000, "draw capped at line limit")
assertTrue(constrained.aggregateLiquidityShortfall > 0, "unmet liquidity is exposed")
assertTrue(constrained.shortfallPeriods > 0, "shortfall periods counted")
assertFalse(constrained.liquidityAdequate, "liquidity inadequate")
assertEqual(constrained.endingAvailableOperatingCredit, 0, "line fully utilized")

-- Projection does not auto-use credit unless explicitly told to.
local noAutoOk, noAuto = AGFLiquidityProjectionService.project({
    openingCash = 10000,
    minimumCashBalance = 5000,
    operatingCreditLimit = 100000,
    autoDrawToMinimumCash = false,
    periods = {
        {year = 3, period = 1, operatingOutflows = 25000}
    }
})
assertTrue(noAutoOk, "non-auto projection succeeds")
assertEqual(noAuto.totalCreditDraws, 0, "no implicit credit draw")
assertEqual(noAuto.endingOperatingCreditPrincipal, 0, "line remains undrawn")
assertTrue(noAuto.aggregateLiquidityShortfall > 0, "cash shortage remains visible")

-- Existing utilization reduces available borrowing capacity.
local utilizedOk, utilized = AGFLiquidityProjectionService.project({
    openingCash = 25000,
    minimumCashBalance = 10000,
    operatingCreditLimit = 100000,
    openingOperatingCreditPrincipal = 80000,
    autoDrawToMinimumCash = true,
    periods = {
        {year = 4, period = 1, operatingOutflows = 50000}
    }
})
assertTrue(utilizedOk, "utilized-line projection succeeds")
assertEqual(utilized.totalCreditDraws, 20000, "only remaining line capacity can draw")
assertEqual(utilized.endingOperatingCreditPrincipal, 100000, "line reaches limit")
assertTrue(utilized.aggregateLiquidityShortfall > 0, "remaining shortfall exposed")

-- Validation rejects impossible opening utilization and bad period values.
local badOpeningOk, badOpeningError = AGFLiquidityProjectionService.project({
    openingCash = 10000,
    operatingCreditLimit = 50000,
    openingOperatingCreditPrincipal = 60000,
    periods = {}
})
assertFalse(badOpeningOk, "opening balance over limit rejected")
assertEqual(badOpeningError, "OPENING_CREDIT_EXCEEDS_LIMIT", "opening limit error")

local badPeriodOk, badPeriodError = AGFLiquidityProjectionService.project({
    openingCash = 10000,
    periods = {{year = 1, period = 13, operatingOutflows = 1}}
})
assertFalse(badPeriodOk, "invalid financial period rejected")
assertEqual(badPeriodError, "INVALID_PERIOD_ROW_1", "invalid period error")

print("offline_liquidity_projection_tests: PASS")
