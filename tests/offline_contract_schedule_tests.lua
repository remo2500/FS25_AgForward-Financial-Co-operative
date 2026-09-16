-- Offline validation for translating amortization rows into dated FS obligations.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/LoanQuoteService.lua")
dofile("src/finance/PaymentFrequencyService.lua")
dofile("src/finance/LoanContractScheduleService.lua")

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

local function quote(principal, periods, paymentsPerYear, rate)
    local ok, result = AGFLoanQuoteService.quote({
        principal = principal,
        periods = periods,
        paymentsPerYear = paymentsPerYear,
        rateComponents = {baseRate = rate}
    })
    assertTrue(ok, "quote creation")
    return result
end

-- Monthly schedule maps one amortization payment to each FS financial period.
local monthlyQuote = quote(120000, 24, 12, 0.06)
local monthlyOk, monthly = AGFLoanContractScheduleService.build(monthlyQuote, 2026, 6)
assertTrue(monthlyOk, "monthly dated schedule succeeds")
assertEqual(monthly.paymentsPerYear, 12, "monthly contract frequency")
assertEqual(monthly.intervalPeriods, 1, "monthly interval")
assertEqual(monthly.paymentCount, 24, "monthly payment count")
assertEqual(monthly.firstDueYear, 2026, "monthly first due year")
assertEqual(monthly.firstDuePeriod, 7, "monthly first due period")
assertEqual(monthly.maturityYear, 2028, "monthly maturity year")
assertEqual(monthly.maturityPeriod, 6, "monthly maturity period")
assertEqual(monthly.schedule[1].totalPayment, monthlyQuote.amortization.schedule[1].totalPayment, "monthly financial row preserved")
assertEqual(monthly.schedule[24].endingBalance, 0, "monthly maturity balance")

-- Quarterly schedules cross year boundaries while retaining the amortization math.
local quarterlyQuote = quote(200000, 8, 4, 0.08)
local quarterlyOk, quarterly = AGFLoanContractScheduleService.build(quarterlyQuote, 2026, 11)
assertTrue(quarterlyOk, "quarterly dated schedule succeeds")
assertEqual(quarterly.intervalPeriods, 3, "quarterly interval")
assertEqual(quarterly.firstDueYear, 2027, "quarterly first due year")
assertEqual(quarterly.firstDuePeriod, 2, "quarterly first due period")
assertEqual(quarterly.schedule[2].duePeriod, 5, "quarterly second due period")
assertEqual(quarterly.maturityYear, 2028, "quarterly maturity year")
assertEqual(quarterly.maturityPeriod, 11, "quarterly maturity period")

-- Annual agricultural payment schedules can stay anchored to the selected farm season.
local annualQuote = quote(300000, 3, 1, 0.07)
local annualOk, annual = AGFLoanContractScheduleService.build(annualQuote, 2026, 10)
assertTrue(annualOk, "annual dated schedule succeeds")
assertEqual(annual.firstDueYear, 2027, "annual first due year")
assertEqual(annual.firstDuePeriod, 10, "annual first due period")
assertEqual(annual.schedule[2].dueYear, 2028, "annual second due year")
assertEqual(annual.schedule[2].duePeriod, 10, "annual second due period")
assertEqual(annual.maturityYear, 2029, "annual maturity year")
assertEqual(annual.maturityPeriod, 10, "annual maturity period")

-- The dated view must reconcile exactly to the quote totals and never become a second calculator.
local datedTotal = 0
local datedInterest = 0
for _, row in ipairs(quarterly.schedule) do
    datedTotal = AGFCurrency.round(datedTotal + row.totalPayment)
    datedInterest = AGFCurrency.round(datedInterest + row.interest)
end
assertEqual(datedTotal, quarterlyQuote.totalPayments, "dated schedule payment total reconciles")
assertEqual(datedInterest, quarterlyQuote.totalInterest, "dated schedule interest total reconciles")
assertEqual(quarterly.totalPayments, quarterlyQuote.totalPayments, "contract summary uses quote total")
assertEqual(quarterly.totalInterest, quarterlyQuote.totalInterest, "contract summary uses quote interest")

-- A generic mathematical frequency that cannot land on whole FS months may be
-- quotable, but cannot become a dated FS settlement schedule.
local fivePerYearQuote = quote(100000, 10, 5, 0.05)
local fiveOk, fiveError = AGFLoanContractScheduleService.build(fivePerYearQuote, 2026, 1)
assertFalse(fiveOk, "unaligned FS frequency rejected by dated schedule")
assertEqual(fiveError, "PAYMENT_FREQUENCY_NOT_ALIGNED_TO_FINANCIAL_PERIODS", "unaligned dated schedule error")

local invalidOk, invalidError = AGFLoanContractScheduleService.build({}, 2026, 1)
assertFalse(invalidOk, "missing amortization rejected")
assertEqual(invalidError, "INVALID_QUOTE_AMORTIZATION", "missing amortization error")

print("offline_contract_schedule_tests: PASS")
