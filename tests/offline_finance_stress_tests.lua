-- Deterministic stress/property-style validation for AgForward finance math.
-- Stock Lua 5.1 only; this complements targeted examples with a wider matrix.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/StructuredAmortizationService.lua")
dofile("src/finance/RateTermRenewalService.lua")
dofile("src/finance/LoanQuoteService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local seed = 1729
local function nextRandom()
    -- Park-Miller LCG. Lua numbers exactly represent these integer magnitudes.
    seed = (seed * 48271) % 2147483647
    return seed / 2147483647
end

local function randomInteger(minimum, maximum)
    return minimum + math.floor(nextRandom() * (maximum - minimum + 1))
end

local frequencies = {1, 2, 4, 12}

local function sumSchedule(schedule)
    local principal = 0
    local interest = 0
    local payments = 0
    for _, row in ipairs(schedule or {}) do
        principal = AGFCurrency.round(principal + (row.regularPrincipal or 0) + (row.balloonPayment or 0))
        interest = AGFCurrency.round(interest + (row.interest or 0))
        payments = AGFCurrency.round(payments + (row.totalPayment or 0))
        assertTrue((row.openingBalance or 0) >= -0.001, "opening balance nonnegative")
        assertTrue((row.endingBalance or 0) >= -0.001, "ending balance nonnegative")
        assertTrue((row.interest or 0) >= -0.001, "interest nonnegative")
        assertTrue((row.regularPrincipal or 0) >= -0.001, "principal component nonnegative")
        assertTrue((row.totalPayment or 0) >= -0.001, "payment nonnegative")
    end
    return principal, interest, payments
end

-- Standard amortization matrix across payment frequencies, terms, rates, and balloons.
for caseIndex = 1, 300 do
    local frequency = frequencies[randomInteger(1, #frequencies)]
    local years = randomInteger(1, 30)
    local periods = years * frequency
    local principal = AGFCurrency.round(randomInteger(500, 2500000) + nextRandom())
    local annualRate = randomInteger(0, 1800) / 10000 -- 0.00% to 18.00%
    local balloonPercent = randomInteger(0, 50) / 100
    local balloon = AGFCurrency.round(principal * balloonPercent)

    local schedule, errorCode = AGFAmortizationService.generateSchedule(
        principal,
        annualRate,
        periods,
        balloon,
        frequency
    )
    assertTrue(schedule ~= nil, "standard stress schedule failed case " .. tostring(caseIndex) .. ": " .. tostring(errorCode))
    assertEqual(#schedule.schedule, periods, "standard stress row count")
    assertTrue(AGFCurrency.equals(schedule.schedule[#schedule.schedule].endingBalance, 0), "standard stress ending zero")
    assertTrue(AGFCurrency.equals(schedule.totalPrincipal, principal), "standard stress principal authority")

    local summedPrincipal, summedInterest, summedPayments = sumSchedule(schedule.schedule)
    assertTrue(AGFCurrency.equals(summedPrincipal, principal), "standard stress row principal reconciliation")
    assertTrue(AGFCurrency.equals(summedInterest, schedule.totalInterest), "standard stress row interest reconciliation")
    assertTrue(AGFCurrency.equals(summedPayments, schedule.totalPayments), "standard stress row payment reconciliation")
    assertTrue(AGFCurrency.equals(summedPayments, summedPrincipal + summedInterest), "standard stress cash components reconcile")

    -- A shorter rate term must leave exactly the row ending balance as renewal principal.
    if periods > 1 then
        local termPeriods = randomInteger(1, periods - 1)
        local termOk, term = AGFRateTermRenewalService.summarize(schedule, termPeriods)
        assertTrue(termOk, "rate-term stress summary")
        assertTrue(term.requiresRenewal, "shorter rate term requires renewal")
        assertTrue(AGFCurrency.equals(term.renewalPrincipal, schedule.schedule[termPeriods].endingBalance), "renewal principal equals term row ending balance")
        assertTrue(AGFCurrency.equals(term.termPrincipalPaid + term.renewalPrincipal, principal), "rate-term principal reconciliation")
    end
end

-- Structured interest-only matrix. The stated total term remains fixed; IO consumes
-- part of it and the remaining rows amortize the resulting contractual balance.
for caseIndex = 1, 200 do
    local frequency = frequencies[randomInteger(1, #frequencies)]
    local totalPeriods = randomInteger(2, 12 * frequency)
    local ioPeriods = randomInteger(1, totalPeriods - 1)
    local amortizingPeriods = totalPeriods - ioPeriods
    local principal = AGFCurrency.round(randomInteger(1000, 1500000) + nextRandom())
    local annualRate = randomInteger(0, 1600) / 10000
    local balloonPercent = randomInteger(0, 40) / 100
    local balloon = AGFCurrency.round(principal * balloonPercent)

    local schedule, errorCode = AGFStructuredAmortizationService.generateInterestOnlyThenAmortizing(
        principal,
        annualRate,
        ioPeriods,
        amortizingPeriods,
        balloon,
        frequency
    )
    assertTrue(schedule ~= nil, "structured stress schedule failed case " .. tostring(caseIndex) .. ": " .. tostring(errorCode))
    assertEqual(#schedule.schedule, totalPeriods, "structured stress total row count")
    assertTrue(AGFCurrency.equals(schedule.schedule[#schedule.schedule].endingBalance, 0), "structured stress ending zero")
    assertTrue(AGFCurrency.equals(schedule.totalPrincipal, principal), "structured stress principal authority")

    for index = 1, ioPeriods do
        local row = schedule.schedule[index]
        assertEqual(row.phase, "interestOnly", "structured stress IO phase")
        assertTrue(AGFCurrency.equals(row.regularPrincipal, 0), "structured stress IO principal zero")
        assertTrue(AGFCurrency.equals(row.endingBalance, principal), "structured stress IO balance unchanged")
    end
    assertEqual(schedule.schedule[ioPeriods + 1].phase, "amortizing", "structured stress amortization transition")

    local summedPrincipal, summedInterest, summedPayments = sumSchedule(schedule.schedule)
    assertTrue(AGFCurrency.equals(summedPrincipal, principal), "structured stress row principal reconciliation")
    assertTrue(AGFCurrency.equals(summedInterest, schedule.totalInterest), "structured stress interest reconciliation")
    assertTrue(AGFCurrency.equals(summedPayments, schedule.totalPayments), "structured stress payment reconciliation")
    assertTrue(AGFCurrency.equals(summedPayments, summedPrincipal + summedInterest), "structured stress cash components reconcile")
end

-- Unified quote matrix cross-checks purchase/down-payment/balloon/rate-term structures.
for caseIndex = 1, 150 do
    local frequency = frequencies[randomInteger(1, #frequencies)]
    local periods = randomInteger(2, 15 * frequency)
    local purchasePrice = AGFCurrency.round(randomInteger(10000, 2000000) + nextRandom())
    local downPercent = randomInteger(0, 40) / 100
    local downPayment = AGFCurrency.round(purchasePrice * downPercent)
    local principal = AGFCurrency.round(purchasePrice - downPayment)
    local balloonPercent = randomInteger(0, 30) / 100
    local interestOnlyPeriods = randomInteger(0, math.min(periods - 1, frequency * 2))
    local rateTermPeriods = randomInteger(1, periods)

    local ok, quoteOrError = AGFLoanQuoteService.quote({
        purchasePrice = purchasePrice,
        downPayment = downPayment,
        periods = periods,
        paymentsPerYear = frequency,
        interestOnlyPeriods = interestOnlyPeriods,
        rateTermPeriods = rateTermPeriods,
        balloonPercent = balloonPercent,
        rateComponents = {
            baseRate = randomInteger(0, 1000) / 10000,
            productSpread = randomInteger(0, 300) / 10000,
            riskSpread = randomInteger(0, 300) / 10000
        }
    })
    assertTrue(ok, "quote stress failed case " .. tostring(caseIndex) .. ": " .. tostring(quoteOrError))
    local quote = quoteOrError
    assertTrue(AGFCurrency.equals(quote.principal, principal), "quote stress principal")
    assertEqual(#quote.amortization.schedule, periods, "quote stress total term preserved")
    assertTrue(AGFCurrency.equals(quote.amortization.schedule[#quote.amortization.schedule].endingBalance, 0), "quote stress ending zero")
    assertTrue(quote.rateTermSummary ~= nil, "quote stress rate-term summary present")
    assertEqual(quote.rateTermSummary.rateTermPeriods, rateTermPeriods, "quote stress rate term retained")

    if rateTermPeriods < periods then
        assertTrue(quote.rateTermSummary.requiresRenewal, "quote stress shorter term renews")
        assertTrue(quote.rateTermSummary.renewalPrincipal > 0, "quote stress renewal balance positive")
    else
        assertFalse = nil -- Lua 5.1 has no local assertion here; explicit condition below.
        assertTrue(not quote.rateTermSummary.requiresRenewal, "quote stress maturity has no renewal")
        assertTrue(AGFCurrency.equals(quote.rateTermSummary.renewalPrincipal, 0), "quote stress maturity renewal zero")
    end
end

print("offline_finance_stress_tests: PASS")
