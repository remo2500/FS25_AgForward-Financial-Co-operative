-- Offline validation for contractual interest-only phases followed by amortization.
-- These are loan-structure tests, not delinquency or missed-payment behavior.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/StructuredAmortizationService.lua")
dofile("src/finance/LoanQuoteService.lua")
dofile("src/finance/PaymentFrequencyService.lua")
dofile("src/finance/LoanContractScheduleService.lua")

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

-- Six monthly interest-only payments followed by 18 amortizing payments.
local structured, structuredError = AGFStructuredAmortizationService.generateInterestOnlyThenAmortizing(
    100000,
    0.12,
    6,
    18,
    0,
    12
)
assertEqual(structuredError, nil, "structured schedule error")
assertEqual(structured.periods, 24, "structured total contractual periods")
assertEqual(structured.interestOnlyPeriods, 6, "interest-only period count")
assertEqual(structured.amortizingPeriods, 18, "amortizing period count")
assertEqual(structured.interestOnlyPayment, 1000, "monthly interest-only payment")
assertEqual(#structured.schedule, 24, "structured row count")

for index = 1, 6 do
    local row = structured.schedule[index]
    assertEqual(row.phase, "interestOnly", "interest-only phase marker")
    assertEqual(row.interest, 1000, "interest-only row interest")
    assertEqual(row.regularPrincipal, 0, "interest-only principal remains zero")
    assertEqual(row.regularPayment, 1000, "interest-only row payment")
    assertEqual(row.openingBalance, 100000, "interest-only opening balance")
    assertEqual(row.endingBalance, 100000, "interest-only balance unchanged")
end

assertEqual(structured.schedule[7].phase, "amortizing", "amortization phase begins after IO")
assertTrue(structured.schedule[7].regularPrincipal > 0, "amortization phase reduces principal")
assertEqual(structured.schedule[24].endingBalance, 0, "structured maturity ending balance")
assertTrue(AGFCurrency.equals(structured.totalPrincipal, 100000), "structured principal reconciles")

-- The post-IO phase is exactly the common amortization engine, with IO interest added on top.
local directAmortization, directError = AGFAmortizationService.generateSchedule(100000, 0.12, 18, 0, 12)
assertEqual(directError, nil, "direct amortization comparison error")
assertEqual(structured.quotedRegularPayment, directAmortization.quotedRegularPayment, "post-IO payment uses common amortization engine")
assertEqual(structured.totalInterest, AGFCurrency.round(directAmortization.totalInterest + 6000), "structured total interest reconciliation")
assertEqual(structured.totalPayments, AGFCurrency.round(directAmortization.totalPayments + 6000), "structured total payments reconciliation")

-- Zero-rate loans can still carry an explicit contractual IO phase; those rows are zero cash payments.
local zeroRate, zeroRateError = AGFStructuredAmortizationService.generateInterestOnlyThenAmortizing(
    12000,
    0,
    3,
    12,
    0,
    12
)
assertEqual(zeroRateError, nil, "zero-rate structured schedule error")
assertEqual(zeroRate.interestOnlyPayment, 0, "zero-rate IO payment")
assertEqual(zeroRate.schedule[1].totalPayment, 0, "zero-rate IO row has no cash payment")
assertEqual(zeroRate.schedule[3].endingBalance, 12000, "zero-rate IO preserves principal")
assertEqual(zeroRate.schedule[4].regularPayment, 1000, "zero-rate amortization begins normally")
assertEqual(zeroRate.schedule[#zeroRate.schedule].endingBalance, 0, "zero-rate structured maturity")

-- Semi-annual farm lending uses the selected frequency for IO interest and later amortization.
local semiAnnual, semiAnnualError = AGFStructuredAmortizationService.generateInterestOnlyThenAmortizing(
    200000,
    0.08,
    2,
    4,
    0,
    2
)
assertEqual(semiAnnualError, nil, "semi-annual structured error")
assertNear(semiAnnual.periodicRate, 0.04, 0.0000000001, "semi-annual periodic rate")
assertEqual(semiAnnual.interestOnlyPayment, 8000, "semi-annual IO payment")
assertEqual(semiAnnual.schedule[1].interest, 8000, "semi-annual first IO interest")
assertEqual(semiAnnual.schedule[3].phase, "amortizing", "semi-annual amortization phase")
assertEqual(semiAnnual.schedule[#semiAnnual.schedule].endingBalance, 0, "semi-annual maturity")

-- Balloon principal remains due at final maturity after the IO phase.
local balloon, balloonError = AGFStructuredAmortizationService.generateInterestOnlyThenAmortizing(
    200000,
    0.08,
    2,
    6,
    50000,
    2
)
assertEqual(balloonError, nil, "structured balloon error")
assertEqual(balloon.balloonAmount, 50000, "structured balloon amount")
assertEqual(balloon.schedule[#balloon.schedule].balloonPayment, 50000, "balloon due on final row")
assertTrue(AGFCurrency.equals(balloon.totalPrincipal, 200000), "structured balloon principal reconciles")
assertEqual(balloon.schedule[#balloon.schedule].endingBalance, 0, "structured balloon ending balance")

-- Unified quote treats interest-only periods as part of the stated contract term, not an extension.
local quoteOk, quote = AGFLoanQuoteService.quote({
    principal = 100000,
    periods = 24,
    interestOnlyPeriods = 6,
    paymentsPerYear = 12,
    rateComponents = {baseRate = 0.12}
})
assertTrue(quoteOk, "structured unified quote succeeds")
assertEqual(quote.periods, 24, "quote total term")
assertEqual(quote.interestOnlyPeriods, 6, "quote IO term")
assertEqual(quote.amortizingPeriods, 18, "quote amortizing term")
assertEqual(quote.interestOnlyPayment, 1000, "quote IO payment")
assertEqual(#quote.amortization.schedule, 24, "quote total payment rows")
assertEqual(quote.amortization.schedule[1].phase, "interestOnly", "quote IO phase preserved")
assertEqual(quote.amortization.schedule[7].phase, "amortizing", "quote amortization phase preserved")
assertEqual(quote.amortization.schedule[24].endingBalance, 0, "quote maturity balance")

-- The dated contract view preserves phases and maps them to real FS financial periods.
local datedOk, dated = AGFLoanContractScheduleService.build(quote, 2026, 4)
assertTrue(datedOk, "dated structured quote succeeds")
assertEqual(dated.paymentCount, 24, "dated structured payment count")
assertEqual(dated.interestOnlyPeriods, 6, "dated structured IO count")
assertEqual(dated.schedule[1].phase, "interestOnly", "dated first phase")
assertEqual(dated.schedule[6].phase, "interestOnly", "dated final IO phase")
assertEqual(dated.schedule[7].phase, "amortizing", "dated first amortization phase")
assertEqual(dated.firstDueYear, 2026, "dated first due year")
assertEqual(dated.firstDuePeriod, 5, "dated first due period")
assertEqual(dated.maturityYear, 2028, "dated maturity year")
assertEqual(dated.maturityPeriod, 4, "dated maturity period")
assertEqual(dated.totalInterest, quote.totalInterest, "dated structured interest uses quote authority")
assertEqual(dated.totalPayments, quote.totalPayments, "dated structured payment total uses quote authority")

-- Invalid IO phase definitions are rejected rather than turning into delinquency-like state.
local fullIoOk, fullIoError = AGFLoanQuoteService.quote({
    principal = 100000,
    periods = 12,
    interestOnlyPeriods = 12,
    rateComponents = {baseRate = 0.05}
})
assertFalse(fullIoOk, "all-IO quote rejected")
assertEqual(fullIoError, "INTEREST_ONLY_PHASE_REQUIRES_AMORTIZING_PERIOD", "all-IO error")

local negativeIoOk, negativeIoError = AGFLoanQuoteService.quote({
    principal = 100000,
    periods = 12,
    interestOnlyPeriods = -1,
    rateComponents = {baseRate = 0.05}
})
assertFalse(negativeIoOk, "negative IO quote rejected")
assertEqual(negativeIoError, "INVALID_INTEREST_ONLY_PERIODS", "negative IO error")

local fractionalIoOk, fractionalIoError = AGFLoanQuoteService.quote({
    principal = 100000,
    periods = 12,
    interestOnlyPeriods = 1.5,
    rateComponents = {baseRate = 0.05}
})
assertFalse(fractionalIoOk, "fractional IO quote rejected")
assertEqual(fractionalIoError, "INVALID_INTEREST_ONLY_PERIODS", "fractional IO error")

local invalidAmortization, invalidAmortizationError = AGFStructuredAmortizationService.generateInterestOnlyThenAmortizing(
    100000,
    0.05,
    3,
    0,
    0,
    12
)
assertEqual(invalidAmortization, nil, "zero amortizing phase rejected")
assertEqual(invalidAmortizationError, "INVALID_AMORTIZING_PERIODS", "zero amortizing phase error")

print("offline_structured_amortization_tests: PASS")
