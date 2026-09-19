-- Offline validation for staged construction/project loan draws.

dofile("src/core/Currency.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RevolvingInterestService.lua")
dofile("src/finance/ProjectDrawAccrualService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertNear(actual, expected, tolerance, message)
    if actual == nil or math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %.10f +/- %.10f, got %s", message or "assertNear", expected, tolerance, tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local function assertFalse(value, message)
    if value ~= false then error(message or "expected false") end
end

-- $500k commitment, with three staged draws over three financial periods.
-- At 12% nominal annual, the monthly periodic rate is 1%.
local ok, result = AGFProjectDrawAccrualService.calculate(
    500000,
    0,
    0.12,
    3,
    {
        {period = 1, periodFraction = 0.00, amount = 100000, useType = "construction", reference = "foundation"},
        {period = 2, periodFraction = 0.50, amount = 100000, useType = "construction", reference = "structure"},
        {period = 3, periodFraction = 0.25, amount = 50000, useType = "equipment", reference = "handling-system"}
    }
)
assertTrue(ok, "staged project draw model succeeds")
assertEqual(result.totalDraws, 250000, "total project draws")
assertEqual(result.endingPrincipal, 250000, "ending advanced principal")
assertEqual(result.undrawnCommitment, 250000, "remaining commitment")
assertEqual(result.conversionPrincipal, 250000, "conversion principal")
assertEqual(#result.periodRows, 3, "period row count")

-- Period 1: $100k is outstanding for the entire period.
assertEqual(result.periodRows[1].openingPrincipal, 0, "period 1 opening")
assertEqual(result.periodRows[1].periodDrawTotal, 100000, "period 1 draw")
assertEqual(result.periodRows[1].averagePrincipal, 100000, "period 1 average")
assertEqual(result.periodRows[1].interestAccrued, 1000, "period 1 interest")
assertEqual(result.periodRows[1].endingPrincipal, 100000, "period 1 ending")

-- Period 2: $100k for first half, $200k for second half => $150k average.
assertEqual(result.periodRows[2].openingPrincipal, 100000, "period 2 opening")
assertEqual(result.periodRows[2].averagePrincipal, 150000, "period 2 average")
assertEqual(result.periodRows[2].interestAccrued, 1500, "period 2 interest")
assertEqual(result.periodRows[2].endingPrincipal, 200000, "period 2 ending")

-- Period 3: $200k for 1/4 and $250k for 3/4 => $237.5k average.
assertEqual(result.periodRows[3].averagePrincipal, 237500, "period 3 average")
assertEqual(result.periodRows[3].interestAccrued, 2375, "period 3 interest")
assertEqual(result.periodRows[3].endingPrincipal, 250000, "period 3 ending")
assertEqual(result.totalInterestAccrued, 4875, "total staged interest")

-- Draw metadata remains attached to the period plan without changing the balance math.
assertEqual(result.periodRows[1].draws[1].useType, "construction", "draw use type retained")
assertEqual(result.periodRows[3].draws[1].reference, "handling-system", "draw reference retained")

-- Existing opening principal is included before new draws.
local existingOk, existing = AGFProjectDrawAccrualService.calculate(
    300000,
    100000,
    0.12,
    2,
    {
        {period = 2, periodFraction = 0.50, amount = 50000}
    }
)
assertTrue(existingOk, "opening principal model succeeds")
assertEqual(existing.periodRows[1].averagePrincipal, 100000, "existing principal full first period")
assertEqual(existing.periodRows[1].interestAccrued, 1000, "existing principal first interest")
assertEqual(existing.periodRows[2].averagePrincipal, 125000, "existing principal plus midperiod draw average")
assertEqual(existing.periodRows[2].interestAccrued, 1250, "existing principal second interest")
assertEqual(existing.endingPrincipal, 150000, "existing principal ending balance")
assertEqual(existing.totalInterestAccrued, 2250, "existing principal total interest")

-- Multiple same-time draws use sequence only for deterministic ordering; combined balance is exact.
local sameTimeOk, sameTime = AGFProjectDrawAccrualService.calculate(
    100000,
    0,
    0.12,
    1,
    {
        {period = 1, periodFraction = 0.5, amount = 20000, sequence = 2, reference = "second"},
        {period = 1, periodFraction = 0.5, amount = 10000, sequence = 1, reference = "first"}
    }
)
assertTrue(sameTimeOk, "same-time draws succeed")
assertEqual(sameTime.periodRows[1].draws[1].reference, "first", "same-time sequence order")
assertEqual(sameTime.periodRows[1].draws[2].reference, "second", "same-time second sequence")
assertEqual(sameTime.periodRows[1].averagePrincipal, 15000, "same-time combined weighted average")
assertEqual(sameTime.periodRows[1].interestAccrued, 150, "same-time interest")
assertEqual(sameTime.endingPrincipal, 30000, "same-time ending principal")

-- Unused periods still accrue interest on already advanced principal.
local idleOk, idle = AGFProjectDrawAccrualService.calculate(
    100000,
    50000,
    0.06,
    2,
    {}
)
assertTrue(idleOk, "idle construction periods succeed")
assertEqual(idle.totalDraws, 0, "idle no new draws")
assertEqual(idle.endingPrincipal, 50000, "idle ending principal unchanged")
assertEqual(idle.periodRows[1].averagePrincipal, 50000, "idle average principal")
assertEqual(idle.periodRows[2].averagePrincipal, 50000, "idle second average principal")
assertEqual(idle.periodRows[1].interestAccrued, 250, "idle first interest")
assertEqual(idle.periodRows[2].interestAccrued, 250, "idle second interest")
assertEqual(idle.totalInterestAccrued, 500, "idle total interest")

-- Commitment is enforced chronologically; no row can over-advance the project facility.
local overOk, overError = AGFProjectDrawAccrualService.calculate(
    100000,
    50000,
    0.08,
    2,
    {
        {period = 1, periodFraction = 0.25, amount = 40000},
        {period = 1, periodFraction = 0.75, amount = 10000.01}
    }
)
assertFalse(overOk, "commitment excess rejected")
assertEqual(overError, "PROJECT_COMMITMENT_EXCEEDED", "commitment excess error")

local openingOverOk, openingOverError = AGFProjectDrawAccrualService.calculate(100000, 100000.01, 0.05, 1, {})
assertFalse(openingOverOk, "opening principal over commitment rejected")
assertEqual(openingOverError, "OPENING_PRINCIPAL_EXCEEDS_COMMITMENT", "opening commitment error")

local badPeriodOk, badPeriodError = AGFProjectDrawAccrualService.calculate(
    100000, 0, 0.05, 2, {{period = 3, periodFraction = 0, amount = 1000}}
)
assertFalse(badPeriodOk, "draw outside project periods rejected")
assertEqual(badPeriodError, "INVALID_DRAW_PERIOD_ROW_1", "draw period error")

local badFractionOk, badFractionError = AGFProjectDrawAccrualService.calculate(
    100000, 0, 0.05, 2, {{period = 1, periodFraction = 1.1, amount = 1000}}
)
assertFalse(badFractionOk, "invalid draw fraction rejected")
assertEqual(badFractionError, "INVALID_DRAW_FRACTION_ROW_1", "draw fraction error")

local badAmountOk, badAmountError = AGFProjectDrawAccrualService.calculate(
    100000, 0, 0.05, 2, {{period = 1, periodFraction = 0.5, amount = 0}}
)
assertFalse(badAmountOk, "zero draw rejected")
assertEqual(badAmountError, "INVALID_DRAW_AMOUNT_ROW_1", "draw amount error")

local badRateOk, badRateError = AGFProjectDrawAccrualService.calculate(100000, 0, -0.01, 2, {})
assertFalse(badRateOk, "negative project rate rejected")
assertEqual(badRateError, "NEGATIVE_RATE_NOT_SUPPORTED", "negative project rate error")

print("offline_project_draw_tests: PASS")
