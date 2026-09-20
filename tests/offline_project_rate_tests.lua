-- Offline tests for variable-rate recasts and project sources/uses.

dofile("src/core/Currency.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/VariableRateService.lua")
dofile("src/finance/ProjectSourcesUsesService.lua")

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

-- Variable-rate history is monotonic and period-specific.
local history = {
    {effectiveYear = 2026, effectivePeriod = 1, annualRate = 0.06, reason = "origination"},
    {effectiveYear = 2026, effectivePeriod = 7, annualRate = 0.07, reason = "base rate reset"},
    {effectiveYear = 2027, effectivePeriod = 1, annualRate = 0.065, reason = "base rate reset"}
}

local validHistory, normalizedHistory = AGFVariableRateService.validateHistory(history)
assertTrue(validHistory, "variable rate history valid")
assertEqual(#normalizedHistory, 3, "rate history count")

local period3, period3Error = AGFVariableRateService.getRateForPeriod(history, 2026, 3)
assertEqual(period3Error, nil, "period 3 rate error")
assertNear(period3.annualRate, 0.06, 0.0000000001, "period 3 rate")

local period9, period9Error = AGFVariableRateService.getRateForPeriod(history, 2026, 9)
assertEqual(period9Error, nil, "period 9 rate error")
assertNear(period9.annualRate, 0.07, 0.0000000001, "period 9 rate")

local noRate, noRateError = AGFVariableRateService.getRateForPeriod(history, 2025, 12)
assertEqual(noRate, nil, "pre-origination rate absent")
assertEqual(noRateError, "NO_RATE_EFFECTIVE_FOR_PERIOD", "pre-origination error")

local badHistoryOk, badHistoryError = AGFVariableRateService.validateHistory({
    {effectiveYear = 2026, effectivePeriod = 7, annualRate = 0.06},
    {effectiveYear = 2026, effectivePeriod = 6, annualRate = 0.07}
})
assertFalse(badHistoryOk, "non-increasing rate history rejected")
assertEqual(badHistoryError, "NON_INCREASING_RATE_HISTORY_ROW_2", "non-increasing rate error")

-- Payment recast responds to new rate while keeping principal/term/balloon contracts.
local recastOk, recast = AGFVariableRateService.recast(
    100000,
    24,
    20000,
    0.08,
    4500,
    AGFVariableRateRecastPolicy.RECAST_PAYMENT
)
assertTrue(recastOk, "payment recast succeeds")
assertTrue(recast.newPayment > 0, "recast payment positive")
assertEqual(recast.principalBalance, 100000, "recast principal unchanged")
assertEqual(recast.balloonAmount, 20000, "recast balloon unchanged")

-- Keeping a payment that is too low for interest must not create silent negative amortization.
local keepFail, keepFailError = AGFVariableRateService.recast(
    100000,
    12,
    0,
    0.24,
    1000,
    AGFVariableRateRecastPolicy.KEEP_PAYMENT
)
assertFalse(keepFail, "negative amortization keep-payment rejected")
assertEqual(keepFailError, "KEEP_PAYMENT_CAUSES_NEGATIVE_AMORTIZATION", "keep-payment negative amortization error")

-- Project finance: $500k project less $100k cash and $50k grant -> $350k financing need.
local projectOk, project = AGFProjectSourcesUsesService.calculateFinancingNeed({
    {type = AGFProjectUseType.CONSTRUCTION, amount = 450000, description = "Grain bin", eligibleForCollateral = true},
    {type = AGFProjectUseType.GROUNDWORK, amount = 30000, description = "Site work", eligibleForCollateral = true},
    {type = AGFProjectUseType.PROFESSIONAL_FEES, amount = 20000, description = "Engineering", eligibleForCollateral = false}
}, {
    {type = AGFProjectSourceType.CASH_EQUITY, amount = 100000},
    {type = AGFProjectSourceType.GRANT, amount = 50000}
}, {})
assertTrue(projectOk, "project financing need succeeds")
assertEqual(project.totalUses, 500000, "project total uses")
assertEqual(project.totalNonDebtSources, 150000, "project non-debt sources")
assertEqual(project.financingNeed, 350000, "project financing need")
assertEqual(project.proposedAgForwardLoan, 350000, "project proposed loan")
assertEqual(project.fundingGap, 0, "project no funding gap")
assertTrue(project.fullyFunded, "project fully funded")
assertEqual(project.collateralEligibleUses, 480000, "collateral-eligible project uses")
assertNear(project.loanToCost, 0.70, 0.0000000001, "project loan-to-cost")

-- A lending cap is surfaced as a funding gap rather than being silently ignored.
local cappedOk, capped = AGFProjectSourcesUsesService.calculateFinancingNeed({
    {type = AGFProjectUseType.CONSTRUCTION, amount = 500000, eligibleForCollateral = true}
}, {
    {type = AGFProjectSourceType.CASH_EQUITY, amount = 100000}
}, {maximumLoan = 300000})
assertTrue(cappedOk, "capped project calculation succeeds")
assertEqual(capped.financingNeed, 400000, "capped project financing need")
assertEqual(capped.proposedAgForwardLoan, 300000, "capped proposed loan")
assertEqual(capped.fundingGap, 100000, "capped funding gap")
assertFalse(capped.fullyFunded, "capped project not fully funded")

-- Sources and uses reconciliation keeps grants/cash/loan distinct.
local sources, sourcesError = AGFProjectSourcesUsesService.buildSources(100000, 50000, 350000, 0, 0)
assertEqual(sourcesError, nil, "build sources error")
local reconcileOk, reconciliation = AGFProjectSourcesUsesService.reconcile({
    {type = AGFProjectUseType.CONSTRUCTION, amount = 500000}
}, sources)
assertTrue(reconcileOk, "project reconciliation runs")
assertTrue(reconciliation.balanced, "project sources and uses balance")
assertEqual(reconciliation.difference, 0, "project reconciliation difference")

local overSourceOk, overSourceError = AGFProjectSourcesUsesService.calculateFinancingNeed({
    {type = AGFProjectUseType.CONSTRUCTION, amount = 100000}
}, {
    {type = AGFProjectSourceType.GRANT, amount = 120000}
}, {})
assertFalse(overSourceOk, "non-debt overfunding rejected")
assertEqual(overSourceError, "NON_DEBT_SOURCES_EXCEED_PROJECT_USES", "overfunding error")

print("offline_project_rate_tests: PASS")
