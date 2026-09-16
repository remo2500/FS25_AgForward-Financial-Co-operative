-- Offline validation for repricing a loan at contractual rate-term renewal.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/StructuredAmortizationService.lua")
dofile("src/finance/RateTermRenewalService.lua")
dofile("src/finance/LoanQuoteService.lua")
dofile("src/finance/LoanRenewalQuoteService.lua")

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

-- 20-year annual land amortization, five-year initial rate term.
local originalOk, original = AGFLoanQuoteService.quote({
    principal = 300000,
    periods = 20,
    paymentsPerYear = 1,
    rateTermPeriods = 5,
    rateComponents = {baseRate = 0.07}
})
assertTrue(originalOk, "original land quote succeeds")
assertTrue(original.rateTermSummary.requiresRenewal, "original land rate term renews")
assertEqual(original.rateTermSummary.remainingAmortizationPeriods, 15, "remaining amortization at renewal")

-- Renewal at a higher 8% rate preserves balance/amortization, but reprices payment.
local higherOk, higher = AGFLoanRenewalQuoteService.quote(original, {baseRate = 0.08})
assertTrue(higherOk, "higher-rate renewal quote succeeds")
assertEqual(higher.renewalPrincipal, original.rateTermSummary.renewalPrincipal, "renewal principal uses original term ending balance")
assertEqual(higher.remainingAmortizationPeriods, 15, "renewal keeps remaining amortization")
assertEqual(higher.paymentsPerYear, 1, "renewal keeps annual payment cadence")
assertEqual(higher.preservedBalloonAmount, 0, "land renewal no balloon")
assertEqual(higher.priorAnnualRate, 0.07, "prior annual rate")
assertEqual(higher.renewedAnnualRate, 0.08, "renewed annual rate")
assertTrue(higher.annualRateChange > 0, "renewal rate increase reported")
assertEqual(higher.renewedQuote.principal, higher.renewalPrincipal, "renewed quote principal")
assertEqual(higher.renewedQuote.periods, 15, "renewed quote term")
assertEqual(#higher.renewedQuote.amortization.schedule, 15, "renewed schedule row count")
assertEqual(higher.renewedQuote.amortization.schedule[#higher.renewedQuote.amortization.schedule].endingBalance, 0, "renewed maturity balance")
assertTrue(higher.renewedRegularPayment > higher.priorProjectedRegularPayment, "higher rate increases projected annual payment")
assertTrue(higher.regularPaymentChange > 0, "payment change reported positive")

-- Lower repricing reduces projected payment without changing renewal principal.
local lowerOk, lower = AGFLoanRenewalQuoteService.quote(original, {baseRate = 0.05})
assertTrue(lowerOk, "lower-rate renewal quote succeeds")
assertEqual(lower.renewalPrincipal, higher.renewalPrincipal, "renewal principal independent from new rate")
assertTrue(lower.annualRateChange < 0, "lower rate change reported")
assertTrue(lower.renewedRegularPayment < lower.priorProjectedRegularPayment, "lower rate reduces payment")
assertTrue(lower.regularPaymentChange < 0, "lower-rate payment change negative")

-- New rate term can be shorter than the remaining amortization, creating another renewal later.
local secondTermOk, secondTerm = AGFLoanRenewalQuoteService.quote(original, {baseRate = 0.075}, {
    rateTermPeriods = 5
})
assertTrue(secondTermOk, "renewal with new five-year rate term succeeds")
assertEqual(secondTerm.renewedQuote.rateTermPeriods, 5, "new renewal rate term")
assertTrue(secondTerm.renewedQuote.rateTermSummary.requiresRenewal, "new shorter term creates future renewal")
assertEqual(secondTerm.renewedQuote.rateTermSummary.remainingAmortizationPeriods, 10, "second renewal remaining amortization")

-- Original maturity balloon is preserved through repricing unless contract restructuring overrides it.
local balloonOriginalOk, balloonOriginal = AGFLoanQuoteService.quote({
    principal = 200000,
    periods = 12,
    paymentsPerYear = 12,
    balloonAmount = 50000,
    rateTermPeriods = 6,
    rateComponents = {baseRate = 0.06}
})
assertTrue(balloonOriginalOk, "balloon original quote succeeds")
local balloonRenewalOk, balloonRenewal = AGFLoanRenewalQuoteService.quote(balloonOriginal, {baseRate = 0.07})
assertTrue(balloonRenewalOk, "balloon renewal succeeds")
assertEqual(balloonRenewal.preservedBalloonAmount, 50000, "balloon preserved at renewal")
assertEqual(balloonRenewal.renewedQuote.balloonAmount, 50000, "renewed quote carries balloon")
assertEqual(balloonRenewal.renewedQuote.amortization.schedule[#balloonRenewal.renewedQuote.amortization.schedule].balloonPayment, 50000, "renewed maturity balloon due")
assertEqual(balloonRenewal.renewedQuote.amortization.schedule[#balloonRenewal.renewedQuote.amortization.schedule].endingBalance, 0, "balloon renewal maturity clears")

-- Contract restructuring may explicitly remove/reduce the balloon.
local restructuredOk, restructured = AGFLoanRenewalQuoteService.quote(balloonOriginal, {baseRate = 0.07}, {
    balloonAmount = 0
})
assertTrue(restructuredOk, "balloon restructuring renewal succeeds")
assertEqual(restructured.preservedBalloonAmount, 0, "balloon restructured to zero")
assertEqual(restructured.renewedQuote.balloonAmount, 0, "renewed quote no balloon")

-- A renewal can intentionally introduce a short contractual IO phase, but still
-- uses only the remaining original amortization periods.
local ioRenewalOk, ioRenewal = AGFLoanRenewalQuoteService.quote(original, {baseRate = 0.08}, {
    interestOnlyPeriods = 2
})
assertTrue(ioRenewalOk, "renewal with IO phase succeeds")
assertEqual(ioRenewal.renewedQuote.periods, 15, "renewal IO does not extend remaining amortization")
assertEqual(ioRenewal.renewedQuote.interestOnlyPeriods, 2, "renewal IO count")
assertEqual(ioRenewal.renewedQuote.amortizingPeriods, 13, "renewal remaining amortization after IO")
assertEqual(ioRenewal.renewedQuote.amortization.schedule[1].phase, "interestOnly", "renewal first row IO")
assertEqual(ioRenewal.renewedQuote.amortization.schedule[3].phase, "amortizing", "renewal amortization starts after IO")

-- Invalid/non-renewal originals fail explicitly.
local noTermOk, noTerm = AGFLoanQuoteService.quote({
    principal = 100000,
    periods = 12,
    rateComponents = {baseRate = 0.05}
})
assertTrue(noTermOk, "no-term original quote succeeds")
local missingTermOk, missingTermError = AGFLoanRenewalQuoteService.quote(noTerm, {baseRate = 0.06})
assertFalse(missingTermOk, "quote without rate term cannot renew")
assertEqual(missingTermError, "ORIGINAL_QUOTE_HAS_NO_RATE_TERM", "missing rate-term renewal error")

local maturityTermOk, maturityTerm = AGFLoanQuoteService.quote({
    principal = 100000,
    periods = 12,
    rateTermPeriods = 12,
    rateComponents = {baseRate = 0.05}
})
assertTrue(maturityTermOk, "maturity-term quote succeeds")
local noRenewalOk, noRenewalError = AGFLoanRenewalQuoteService.quote(maturityTerm, {baseRate = 0.06})
assertFalse(noRenewalOk, "rate term at maturity does not renew")
assertEqual(noRenewalError, "RATE_TERM_DOES_NOT_REQUIRE_RENEWAL", "maturity renewal error")

local tooLongTermOk, tooLongTermError = AGFLoanRenewalQuoteService.quote(original, {baseRate = 0.06}, {
    rateTermPeriods = 16
})
assertFalse(tooLongTermOk, "new rate term beyond remaining amortization rejected")
assertEqual(tooLongTermError, "RATE_TERM_EXCEEDS_REMAINING_AMORTIZATION", "renewal rate-term length error")

local tooLargeBalloonOk, tooLargeBalloonError = AGFLoanRenewalQuoteService.quote(original, {baseRate = 0.06}, {
    balloonAmount = original.rateTermSummary.renewalPrincipal + 0.01
})
assertFalse(tooLargeBalloonOk, "renewal balloon above balance rejected")
assertEqual(tooLargeBalloonError, "BALLOON_EXCEEDS_RENEWAL_PRINCIPAL", "renewal balloon error")

print("offline_loan_renewal_tests: PASS")
