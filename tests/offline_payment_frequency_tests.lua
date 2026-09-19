-- Offline validation for flexible agricultural payment frequencies and due dates.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/LoanQuoteService.lua")
dofile("src/finance/PaymentFrequencyService.lua")

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

-- Existing monthly behavior remains the default.
local defaultMonthly, defaultMonthlyError = AGFAmortizationService.calculateRegularPayment(100000, 0.12, 24, 0)
assertEqual(defaultMonthlyError, nil, "default monthly error")
assertEqual(defaultMonthly, 4707.35, "default monthly payment unchanged")

local explicitMonthly = AGFAmortizationService.calculateRegularPayment(100000, 0.12, 24, 0, 12)
assertEqual(explicitMonthly, defaultMonthly, "explicit monthly matches default")

-- The same annual nominal rate can be quoted against quarterly or annual payments.
local quarterly, quarterlyError = AGFAmortizationService.calculateRegularPayment(100000, 0.12, 8, 0, 4)
assertEqual(quarterlyError, nil, "quarterly payment error")
assertEqual(quarterly, 14245.64, "quarterly payment")

local annual, annualError = AGFAmortizationService.calculateRegularPayment(100000, 0.12, 2, 0, 1)
assertEqual(annualError, nil, "annual payment error")
assertEqual(annual, 59169.81, "annual payment")

local annualSchedule, annualScheduleError = AGFAmortizationService.generateSchedule(100000, 0.12, 2, 0, 1)
assertEqual(annualScheduleError, nil, "annual schedule error")
assertEqual(annualSchedule.periodsPerYear, 1, "annual schedule frequency")
assertNear(annualSchedule.periodicRate, 0.12, 0.0000000001, "annual periodic rate")
assertEqual(#annualSchedule.schedule, 2, "annual schedule row count")
assertTrue(AGFCurrency.equals(annualSchedule.totalPrincipal, 100000), "annual principal reconciles")
assertTrue(AGFCurrency.equals(annualSchedule.schedule[#annualSchedule.schedule].endingBalance, 0), "annual ending balance zero")

-- Balloon math respects the selected payment frequency.
local semiBalloon, semiBalloonError = AGFAmortizationService.generateSchedule(200000, 0.08, 6, 50000, 2)
assertEqual(semiBalloonError, nil, "semiannual balloon schedule error")
assertEqual(semiBalloon.periodsPerYear, 2, "semiannual frequency")
assertNear(semiBalloon.periodicRate, 0.04, 0.0000000001, "semiannual periodic rate")
assertEqual(semiBalloon.schedule[#semiBalloon.schedule].balloonPayment, 50000, "semiannual balloon amount")
assertTrue(AGFCurrency.equals(semiBalloon.totalPrincipal, 200000), "semiannual balloon principal reconciles")

-- Unified quote passes the frequency into the one amortization engine.
local quoteOk, quote = AGFLoanQuoteService.quote({
    purchasePrice = 300000,
    downPayment = 60000,
    periods = 20,
    paymentsPerYear = 4,
    balloonPercent = 0.10,
    rateComponents = {baseRate = 0.05, productSpread = 0.01}
})
assertTrue(quoteOk, "quarterly unified quote succeeds")
assertEqual(quote.paymentsPerYear, 4, "quote frequency")
assertEqual(quote.amortization.periodsPerYear, 4, "amortization receives quote frequency")
assertNear(quote.amortization.periodicRate, 0.015, 0.0000000001, "quarterly quote periodic rate")
assertEqual(quote.principal, 240000, "quarterly quote principal")
assertEqual(quote.balloonAmount, 24000, "quarterly quote balloon")

local invalidQuoteOk, invalidQuoteError = AGFLoanQuoteService.quote({
    principal = 100000,
    periods = 5,
    paymentsPerYear = 0,
    rateComponents = {baseRate = 0.05}
})
assertFalse(invalidQuoteOk, "zero payment frequency rejected")
assertEqual(invalidQuoteError, "INVALID_PAYMENTS_PER_YEAR", "zero payment frequency error")

-- Frequency-to-FS-period mapping supports standard agricultural schedules.
local monthlyInterval = AGFPaymentFrequencyService.getIntervalPeriods(AGFPaymentFrequency.MONTHLY)
assertEqual(monthlyInterval, 1, "monthly interval")
local quarterlyInterval = AGFPaymentFrequencyService.getIntervalPeriods(AGFPaymentFrequency.QUARTERLY)
assertEqual(quarterlyInterval, 3, "quarterly interval")
local semiInterval = AGFPaymentFrequencyService.getIntervalPeriods(AGFPaymentFrequency.SEMI_ANNUAL)
assertEqual(semiInterval, 6, "semiannual interval")
local annualInterval = AGFPaymentFrequencyService.getIntervalPeriods(AGFPaymentFrequency.ANNUAL)
assertEqual(annualInterval, 12, "annual interval")

assertEqual(AGFPaymentFrequencyService.getLabel(12), "monthly", "monthly label")
assertEqual(AGFPaymentFrequencyService.getLabel(4), "quarterly", "quarterly label")
assertEqual(AGFPaymentFrequencyService.getLabel(2), "semiAnnual", "semiannual label")
assertEqual(AGFPaymentFrequencyService.getLabel(1), "annual", "annual label")

local twoYearQuarterlyCount, countError = AGFPaymentFrequencyService.countPaymentsForTermMonths(24, 4)
assertEqual(countError, nil, "payment count error")
assertEqual(twoYearQuarterlyCount, 8, "two-year quarterly payment count")

local misalignedCount, misalignedError = AGFPaymentFrequencyService.countPaymentsForTermMonths(25, 4)
assertEqual(misalignedCount, nil, "misaligned term rejected")
assertEqual(misalignedError, "TERM_NOT_ALIGNED_TO_PAYMENT_FREQUENCY", "misaligned term error")

-- Due-date generation crosses calendar years deterministically.
local quarterlyDates, quarterlyDatesError = AGFPaymentFrequencyService.buildDueSchedule(2026, 10, 4, 4)
assertEqual(quarterlyDatesError, nil, "quarterly due schedule error")
assertEqual(quarterlyDates.intervalPeriods, 3, "quarterly due interval")
assertEqual(quarterlyDates.schedule[1].dueYear, 2027, "first quarterly due year")
assertEqual(quarterlyDates.schedule[1].duePeriod, 1, "first quarterly due period")
assertEqual(quarterlyDates.schedule[2].dueYear, 2027, "second quarterly due year")
assertEqual(quarterlyDates.schedule[2].duePeriod, 4, "second quarterly due period")
assertEqual(quarterlyDates.schedule[4].duePeriod, 10, "fourth quarterly due period")

local annualDates, annualDatesError = AGFPaymentFrequencyService.buildDueSchedule(2026, 3, 3, 1)
assertEqual(annualDatesError, nil, "annual due schedule error")
assertEqual(annualDates.schedule[1].dueYear, 2027, "annual first due year")
assertEqual(annualDates.schedule[1].duePeriod, 3, "annual first due month")
assertEqual(annualDates.schedule[3].dueYear, 2029, "annual third due year")
assertEqual(annualDates.schedule[3].duePeriod, 3, "annual third due month")

-- First payment can be deliberately deferred while later payments remain on cadence.
local deferred, deferredError = AGFPaymentFrequencyService.buildDueSchedule(2026, 4, 3, 2, 9)
assertEqual(deferredError, nil, "deferred schedule error")
assertEqual(deferred.schedule[1].dueYear, 2027, "deferred first due year")
assertEqual(deferred.schedule[1].duePeriod, 1, "deferred first due period")
assertEqual(deferred.schedule[2].duePeriod, 7, "semiannual cadence after deferral")
assertEqual(deferred.schedule[3].dueYear, 2028, "third deferred due year")
assertEqual(deferred.schedule[3].duePeriod, 1, "third deferred due period")

-- Frequencies that cannot land on whole FS financial periods are rejected by
-- the due-date service even though the generic amortization math is capable of them.
local badFrequency, badFrequencyError = AGFPaymentFrequencyService.getIntervalPeriods(5)
assertEqual(badFrequency, nil, "five payments/year not FS-period aligned")
assertEqual(badFrequencyError, "PAYMENT_FREQUENCY_NOT_ALIGNED_TO_FINANCIAL_PERIODS", "unaligned frequency error")

print("offline_payment_frequency_tests: PASS")
