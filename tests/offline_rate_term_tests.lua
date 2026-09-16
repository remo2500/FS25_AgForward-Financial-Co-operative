-- Offline validation for distinguishing rate term/renewal from loan amortization.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/StructuredAmortizationService.lua")
dofile("src/finance/RateTermRenewalService.lua")
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

-- Twenty-year monthly amortization with a five-year rate term.
local land, landError = AGFAmortizationService.generateSchedule(500000, 0.06, 240, 0, 12)
assertEqual(landError, nil, "land amortization error")
local termOk, term = AGFRateTermRenewalService.summarize(land, 60)
assertTrue(termOk, "five-year rate term succeeds")
assertEqual(term.rateTermPeriods, 60, "five-year term periods")
assertEqual(term.totalAmortizationPeriods, 240, "twenty-year amortization periods")
assertEqual(term.remainingAmortizationPeriods, 180, "remaining amortization after rate term")
assertTrue(term.requiresRenewal, "rate term requires renewal")
assertTrue(term.renewalPrincipal > 0, "renewal principal remains")
assertTrue(term.renewalPrincipal < 500000, "renewal principal reduced by scheduled amortization")
assertEqual(term.termBalloonPayments, 0, "rate renewal is not a balloon")
assertTrue(AGFCurrency.equals(term.termPrincipalPaid + term.renewalPrincipal, 500000), "principal paid plus renewal balance reconciles")

-- If rate term equals full amortization/maturity, no renewal principal remains.
local fullOk, full = AGFRateTermRenewalService.summarize(land, 240)
assertTrue(fullOk, "full-term summary succeeds")
assertFalse(full.requiresRenewal, "maturity requires no rate renewal")
assertEqual(full.remainingAmortizationPeriods, 0, "no amortization remains")
assertEqual(full.renewalPrincipal, 0, "no renewal principal at maturity")
assertEqual(full.termInterest, land.totalInterest, "full-term interest reconciles")
assertEqual(full.termPayments, land.totalPayments, "full-term payments reconcile")
assertTrue(AGFCurrency.equals(full.termPrincipalPaid, 500000), "full-term principal reconciles")

-- Annual agricultural payment structures can still have a shorter multi-year rate term.
local annual, annualError = AGFAmortizationService.generateSchedule(300000, 0.07, 20, 0, 1)
assertEqual(annualError, nil, "annual land schedule error")
local annualTermOk, annualTerm = AGFRateTermRenewalService.summarize(annual, 5)
assertTrue(annualTermOk, "annual five-year rate term succeeds")
assertEqual(annualTerm.paymentFrequency, 1, "annual payment frequency retained")
assertEqual(annualTerm.remainingAmortizationPeriods, 15, "annual remaining amortization")
assertTrue(annualTerm.renewalPrincipal > 0, "annual renewal principal remains")

-- A rate term ending during the contractual interest-only phase leaves all principal for renewal.
local io, ioError = AGFStructuredAmortizationService.generateInterestOnlyThenAmortizing(
    100000,
    0.12,
    6,
    18,
    0,
    12
)
assertEqual(ioError, nil, "interest-only structured schedule error")
local ioTermOk, ioTerm = AGFRateTermRenewalService.summarize(io, 6)
assertTrue(ioTermOk, "rate term through IO phase succeeds")
assertEqual(ioTerm.termPrincipalPaid, 0, "IO rate term pays no principal")
assertEqual(ioTerm.renewalPrincipal, 100000, "IO rate term renews full principal")
assertEqual(ioTerm.termInterest, 6000, "IO rate-term interest")
assertTrue(ioTerm.requiresRenewal, "IO-only rate term requires renewal")

local ioLaterOk, ioLater = AGFRateTermRenewalService.summarize(io, 12)
assertTrue(ioLaterOk, "rate term extending into amortization succeeds")
assertTrue(ioLater.termPrincipalPaid > 0, "post-IO term includes principal")
assertTrue(ioLater.renewalPrincipal < 100000, "post-IO renewal balance is reduced")
assertTrue(AGFCurrency.equals(ioLater.termPrincipalPaid + ioLater.renewalPrincipal, 100000), "post-IO principal reconciliation")

-- A contractual balloon remains distinct from a rate-term renewal.
local balloon, balloonError = AGFAmortizationService.generateSchedule(200000, 0.08, 12, 50000, 12)
assertEqual(balloonError, nil, "balloon amortization error")
local preBalloonOk, preBalloon = AGFRateTermRenewalService.summarize(balloon, 6)
assertTrue(preBalloonOk, "pre-balloon rate term succeeds")
assertEqual(preBalloon.termBalloonPayments, 0, "no balloon paid before maturity")
assertTrue(preBalloon.renewalPrincipal > 50000, "renewal principal includes future balloon portion")
assertTrue(preBalloon.requiresRenewal, "pre-balloon term renews")

local balloonMaturityOk, balloonMaturity = AGFRateTermRenewalService.summarize(balloon, 12)
assertTrue(balloonMaturityOk, "balloon maturity summary succeeds")
assertEqual(balloonMaturity.termBalloonPayments, 50000, "maturity includes contractual balloon")
assertEqual(balloonMaturity.renewalPrincipal, 0, "balloon maturity leaves no renewal principal")
assertFalse(balloonMaturity.requiresRenewal, "balloon maturity no renewal")

-- Unified quotes can carry a shorter rate term without treating renewal balance as a balloon.
local quoteOk, quote = AGFLoanQuoteService.quote({
    principal = 300000,
    periods = 20,
    paymentsPerYear = 1,
    rateTermPeriods = 5,
    rateComponents = {baseRate = 0.07}
})
assertTrue(quoteOk, "land quote with rate term succeeds")
assertEqual(quote.periods, 20, "land quote amortization periods")
assertEqual(quote.rateTermPeriods, 5, "land quote rate term")
assertTrue(quote.rateTermSummary ~= nil, "land quote rate-term summary")
assertTrue(quote.rateTermSummary.requiresRenewal, "land quote renewal required")
assertTrue(quote.rateTermSummary.renewalPrincipal > 0, "land quote renewal balance")
assertEqual(quote.balloonAmount, 0, "rate renewal is not quoted as balloon")

local datedOk, dated = AGFLoanContractScheduleService.build(quote, 2026, 10)
assertTrue(datedOk, "dated land contract succeeds")
assertEqual(dated.rateRenewalDueYear, 2031, "rate renewal due year")
assertEqual(dated.rateRenewalDuePeriod, 10, "rate renewal stays on annual farm payment anchor")
assertEqual(dated.schedule[5].rateRenewalDue, true, "rate renewal row marked")
assertEqual(dated.schedule[5].renewalPrincipal, quote.rateTermSummary.renewalPrincipal, "dated renewal principal")
assertFalse(dated.schedule[4].rateRenewalDue, "row before renewal not marked")
assertFalse(dated.schedule[6].rateRenewalDue, "row after renewal not marked")
assertEqual(dated.maturityYear, 2046, "amortization maturity remains later than rate renewal")
assertEqual(dated.maturityPeriod, 10, "maturity stays on annual anchor")

-- An interest-only quote can also have a rate term; renewal calculations use the structured schedule.
local ioQuoteOk, ioQuote = AGFLoanQuoteService.quote({
    principal = 100000,
    periods = 24,
    interestOnlyPeriods = 6,
    paymentsPerYear = 12,
    rateTermPeriods = 6,
    rateComponents = {baseRate = 0.12}
})
assertTrue(ioQuoteOk, "structured quote with rate term succeeds")
assertEqual(ioQuote.rateTermSummary.renewalPrincipal, 100000, "IO quote renews full principal at IO term")
assertEqual(ioQuote.rateTermSummary.termPrincipalPaid, 0, "IO quote rate term principal paid")

-- Invalid rate terms are explicit errors.
local tooLongOk, tooLongError = AGFRateTermRenewalService.summarize(land, 241)
assertFalse(tooLongOk, "rate term beyond amortization rejected")
assertEqual(tooLongError, "RATE_TERM_EXCEEDS_AMORTIZATION", "too-long rate term error")

local fractionalOk, fractionalError = AGFRateTermRenewalService.summarize(land, 12.5)
assertFalse(fractionalOk, "fractional rate term rejected")
assertEqual(fractionalError, "INVALID_RATE_TERM", "fractional rate term error")

local invalidScheduleOk, invalidScheduleError = AGFRateTermRenewalService.summarize({}, 12)
assertFalse(invalidScheduleOk, "missing amortization schedule rejected")
assertEqual(invalidScheduleError, "INVALID_AMORTIZATION", "missing amortization error")

local quoteTooLongOk, quoteTooLongError = AGFLoanQuoteService.quote({
    principal = 100000,
    periods = 12,
    rateTermPeriods = 13,
    rateComponents = {baseRate = 0.05}
})
assertFalse(quoteTooLongOk, "quote rate term beyond amortization rejected")
assertEqual(quoteTooLongError, "RATE_TERM_EXCEEDS_AMORTIZATION", "quote rate-term length error")

print("offline_rate_term_tests: PASS")
