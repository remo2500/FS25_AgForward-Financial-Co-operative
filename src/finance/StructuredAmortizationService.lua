-- AgForward Financial Cooperative
-- Pure structured-repayment mathematics for agricultural loans that begin with
-- a contractual interest-only phase and then convert to normal amortization.
-- This is not delinquency or a missed-payment model.

AGFStructuredAmortizationService = {}

local function normalizeNonNegativeInteger(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    if number < 0 or number ~= math.floor(number) then return nil end
    return number
end

function AGFStructuredAmortizationService.generateInterestOnlyThenAmortizing(
    principal,
    annualRate,
    interestOnlyPeriods,
    amortizingPeriods,
    balloonAmount,
    periodsPerYear
)
    local ioPeriods = normalizeNonNegativeInteger(interestOnlyPeriods)
    if ioPeriods == nil then return nil, "INVALID_INTEREST_ONLY_PERIODS" end

    local amortPeriods = normalizeNonNegativeInteger(amortizingPeriods)
    if amortPeriods == nil or amortPeriods <= 0 then return nil, "INVALID_AMORTIZING_PERIODS" end

    local valid, termsOrError = AGFAmortizationService.validateTerms(
        principal,
        annualRate,
        amortPeriods,
        balloonAmount,
        periodsPerYear
    )
    if not valid then return nil, termsOrError end
    local terms = termsOrError

    local amortization, amortizationError = AGFAmortizationService.generateSchedule(
        terms.principal,
        terms.annualRate,
        terms.periods,
        terms.balloonAmount,
        terms.periodsPerYear
    )
    if amortization == nil then return nil, amortizationError end

    local periodicRate, rateError = AGFRateConvention.toPeriodicRate(terms.annualRate, terms.periodsPerYear)
    if periodicRate == nil then return nil, rateError end

    local rows = {}
    local totalInterest = 0
    local totalPayments = 0
    local interestOnlyPayment = AGFCurrency.round(terms.principal * periodicRate)

    for index = 1, ioPeriods do
        local interest = interestOnlyPayment
        table.insert(rows, {
            period = index,
            phase = "interestOnly",
            openingBalance = terms.principal,
            annualRate = terms.annualRate,
            periodicRate = periodicRate,
            interest = interest,
            regularPrincipal = 0,
            regularPayment = interest,
            balloonPayment = 0,
            totalPayment = interest,
            endingBalance = terms.principal
        })
        totalInterest = AGFCurrency.round(totalInterest + interest)
        totalPayments = AGFCurrency.round(totalPayments + interest)
    end

    for _, sourceRow in ipairs(amortization.schedule) do
        local row = {
            period = ioPeriods + sourceRow.period,
            phase = "amortizing",
            openingBalance = sourceRow.openingBalance,
            annualRate = sourceRow.annualRate,
            periodicRate = sourceRow.periodicRate,
            interest = sourceRow.interest,
            regularPrincipal = sourceRow.regularPrincipal,
            regularPayment = sourceRow.regularPayment,
            balloonPayment = sourceRow.balloonPayment,
            totalPayment = sourceRow.totalPayment,
            endingBalance = sourceRow.endingBalance
        }
        table.insert(rows, row)
        totalInterest = AGFCurrency.round(totalInterest + row.interest)
        totalPayments = AGFCurrency.round(totalPayments + row.totalPayment)
    end

    local finalRow = rows[#rows]
    if finalRow == nil or not AGFCurrency.equals(finalRow.endingBalance, 0) then
        return nil, "ENDING_BALANCE_NOT_ZERO"
    end

    return {
        principal = terms.principal,
        annualRate = terms.annualRate,
        periodicRate = periodicRate,
        periodsPerYear = terms.periodsPerYear,
        interestOnlyPeriods = ioPeriods,
        amortizingPeriods = amortPeriods,
        periods = ioPeriods + amortPeriods,
        balloonAmount = terms.balloonAmount,
        interestOnlyPayment = interestOnlyPayment,
        quotedRegularPayment = amortization.quotedRegularPayment,
        schedule = rows,
        totalInterest = totalInterest,
        totalPrincipal = amortization.totalPrincipal,
        totalPayments = totalPayments
    }, nil
end
