-- Offline pure-math validation for AgForward finance foundations.
-- Runs under stock Lua 5.1 in CI; does not replace FS25 runtime testing.

dofile("src/core/Currency.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/LoanQuoteService.lua")
dofile("src/credit/CreditMetrics.lua")
dofile("src/input/FundingDecisionService.lua")

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

-- Currency normalization.
assertEqual(AGFCurrency.toMinorUnits(10.005), 1001, "positive half-cent rounds away from zero")
assertEqual(AGFCurrency.toMinorUnits(-10.005), -1001, "negative half-cent rounds away from zero")
assertTrue(AGFCurrency.equals(1.234, 1.23), "currency equality uses cents")

-- Rate storage/display convention.
local periodic, periodicError = AGFRateConvention.toPeriodicRate(0.12)
assertEqual(periodicError, nil, "periodic rate error")
assertNear(periodic, 0.01, 0.0000000001, "12% annual -> 1% monthly")

local displayed = AGFRateConvention.toDisplayPercent(0.0725)
assertNear(displayed, 7.25, 0.0000000001, "display percent")

local parsed, parseError = AGFRateConvention.fromDisplayPercent(7.25)
assertEqual(parseError, nil, "display percent parse error")
assertNear(parsed, 0.0725, 0.0000000001, "display percent parse")

local invalidRate, invalidRateError = AGFRateConvention.toPeriodicRate(-0.01)
assertEqual(invalidRate, nil, "negative rate rejected")
assertEqual(invalidRateError, "NEGATIVE_RATE_NOT_SUPPORTED", "negative rate error")

-- Componentized pricing: 4.50% base + 1.25% product + 0.75% risk + 0.10% term - 0.05% structure = 6.55%.
local pricingOk, pricing = AGFRatePricingService.quote({
    baseRate = 0.045,
    productSpread = 0.0125,
    riskSpread = 0.0075,
    termAdjustment = 0.001,
    structureAdjustment = -0.0005
})
assertTrue(pricingOk, "pricing quote approved")
assertNear(pricing.annualRate, 0.0655, 0.0000000001, "componentized annual rate")
assertNear(pricing.annualPercent, 6.55, 0.0000000001, "componentized display percent")

local negativePricingOk, negativePricingError = AGFRatePricingService.quote({
    baseRate = 0,
    productSpread = -0.01
})
assertFalse(negativePricingOk, "negative final rate rejected")
assertEqual(negativePricingError, "NEGATIVE_FINAL_RATE", "negative final rate error")

-- Standard amortizing loan.
local payment, paymentError = AGFAmortizationService.calculateRegularPayment(100000, 0.12, 12, 0)
assertEqual(paymentError, nil, "standard payment error")
assertEqual(payment, 8884.88, "standard quoted payment")

local schedule, scheduleError = AGFAmortizationService.generateSchedule(100000, 0.12, 12, 0)
assertEqual(scheduleError, nil, "standard schedule error")
assertEqual(#schedule.schedule, 12, "standard schedule length")
assertTrue(AGFCurrency.equals(schedule.totalPrincipal, 100000), "standard principal reconciles")
assertTrue(AGFCurrency.equals(schedule.schedule[#schedule.schedule].endingBalance, 0), "standard ending balance zero")

-- Bullet loan: interest-only regular payment, full principal at maturity.
local bulletPayment, bulletError = AGFAmortizationService.calculateRegularPayment(100000, 0.12, 12, 100000)
assertEqual(bulletError, nil, "bullet payment error")
assertEqual(bulletPayment, 1000, "bullet regular payment")

local bulletSchedule, bulletScheduleError = AGFAmortizationService.generateSchedule(100000, 0.12, 12, 100000)
assertEqual(bulletScheduleError, nil, "bullet schedule error")
local bulletFinal = bulletSchedule.schedule[#bulletSchedule.schedule]
assertEqual(bulletFinal.regularPayment, 1000, "bullet final regular interest payment")
assertEqual(bulletFinal.balloonPayment, 100000, "bullet balloon principal")
assertEqual(bulletFinal.totalPayment, 101000, "bullet final total payment")
assertTrue(AGFCurrency.equals(bulletFinal.endingBalance, 0), "bullet ending balance zero")

-- Zero-rate loan remains supported.
local zeroRatePayment = AGFAmortizationService.calculateRegularPayment(12000, 0, 12, 0)
assertEqual(zeroRatePayment, 1000, "zero-rate payment")

-- Payoff breakdown remains componentized.
local payoff, payoffError = AGFAmortizationService.calculatePayoff(50000, 250, 75, 0)
assertEqual(payoffError, nil, "payoff error")
assertEqual(payoff.principal, 50000, "payoff principal")
assertEqual(payoff.interest, 250, "payoff interest")
assertEqual(payoff.fees, 75, "payoff fees")
assertEqual(payoff.total, 50325, "payoff total")

-- Unified product quote shares pricing + amortization rather than product-local math.
local quoteOk, quote = AGFLoanQuoteService.quote({
    purchasePrice = 250000,
    downPayment = 50000,
    periods = 60,
    balloonPercent = 0.20,
    rateComponents = {
        baseRate = 0.045,
        productSpread = 0.0125,
        riskSpread = 0.0075,
        termAdjustment = 0.001,
        structureAdjustment = -0.0005
    }
})
assertTrue(quoteOk, "unified quote approved")
assertEqual(quote.principal, 200000, "quote principal")
assertEqual(quote.balloonAmount, 40000, "quote balloon")
assertNear(quote.pricing.annualRate, 0.0655, 0.0000000001, "quote rate")
assertTrue(quote.quotedRegularPayment > 0, "quote regular payment positive")
assertTrue(quote.totalInterest > 0, "quote interest positive")
assertTrue(AGFCurrency.equals(quote.amortization.totalPrincipal, 200000), "quote principal reconciles")

local invalidQuoteOk, invalidQuoteError = AGFLoanQuoteService.quote({
    purchasePrice = 100000,
    downPayment = 110000,
    periods = 12,
    rateComponents = {baseRate = 0.05}
})
assertFalse(invalidQuoteOk, "down payment above price rejected")
assertEqual(invalidQuoteError, "DOWN_PAYMENT_EXCEEDS_PURCHASE_PRICE", "invalid down payment error")

-- Whole-farm credit metrics.
assertNear(AGFCreditMetrics.calculateDSCR(150000, 100000), 1.5, 0.0000000001, "DSCR")
assertNear(AGFCreditMetrics.calculateFixedChargeCoverage(180000, 100000, 20000), 1.5, 0.0000000001, "FCCR")
assertNear(AGFCreditMetrics.calculateDebtToAssets(500000, 1000000), 0.5, 0.0000000001, "debt-to-assets")
assertNear(AGFCreditMetrics.calculateLoanToValue(300000, 500000), 0.6, 0.0000000001, "LTV")
assertEqual(AGFCreditMetrics.calculateWorkingCapital(250000, 175000), 75000, "working capital")
assertNear(AGFCreditMetrics.calculateCurrentRatio(250000, 125000), 2.0, 0.0000000001, "current ratio")
assertNear(AGFCreditMetrics.calculateRevolverUtilization(75000, 250000), 0.3, 0.0000000001, "revolver utilization")
assertNear(AGFCreditMetrics.calculateLiquidityCoverage(100000, 50000, 100000), 1.5, 0.0000000001, "liquidity coverage")
assertEqual(AGFCreditMetrics.calculateDSCR(100000, 0), nil, "no debt service -> DSCR N/A")

-- Crop Input LOC funding allocation policies.
local shortfallOk, shortfall = AGFFundingDecisionService.decide(
    30000,
    12000,
    100000,
    true,
    AGFFundingPolicy.CASH_SHORTFALL_ONLY
)
assertTrue(shortfallOk, "shortfall policy approved")
assertEqual(shortfall.cashContribution, 12000, "shortfall cash contribution")
assertEqual(shortfall.lineContribution, 18000, "shortfall line contribution")

local preferOk, prefer = AGFFundingDecisionService.decide(
    30000,
    15000,
    20000,
    true,
    AGFFundingPolicy.PREFER_LINE
)
assertTrue(preferOk, "prefer-line policy approved")
assertEqual(prefer.lineContribution, 20000, "prefer-line draw")
assertEqual(prefer.cashContribution, 10000, "prefer-line cash remainder")

local alwaysOk, always = AGFFundingDecisionService.decide(
    30000,
    50000,
    30000,
    true,
    AGFFundingPolicy.ALWAYS_LINE
)
assertTrue(alwaysOk, "always-line policy approved")
assertEqual(always.cashContribution, 0, "always-line cash contribution")
assertEqual(always.lineContribution, 30000, "always-line draw")

local alwaysFail, alwaysFailError = AGFFundingDecisionService.decide(
    30000,
    50000,
    29999.99,
    true,
    AGFFundingPolicy.ALWAYS_LINE
)
assertFalse(alwaysFail, "always-line insufficient credit rejected")
assertEqual(alwaysFailError, "INSUFFICIENT_CREDIT", "always-line insufficient credit error")

local ineligibleFail, ineligibleFailError = AGFFundingDecisionService.decide(
    30000,
    10000,
    100000,
    false,
    AGFFundingPolicy.PREFER_LINE
)
assertFalse(ineligibleFail, "ineligible purchase cannot borrow")
assertEqual(ineligibleFailError, "INSUFFICIENT_CASH", "ineligible purchase uses cash-only rule")

print("offline_finance_tests: PASS")
