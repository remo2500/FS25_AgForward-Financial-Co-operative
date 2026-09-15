-- AgForward Financial Cooperative
-- Pure amortization/payoff mathematics. No Farming Simulator balance mutation.

AGFAmortizationService = {}

local function normalizeNonNegativeMoney(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    number = AGFCurrency.round(number)
    if number < 0 then
        return nil
    end
    return number
end

local function normalizePeriods(periods)
    local value = tonumber(periods)
    if value == nil then
        return nil
    end
    value = math.floor(value)
    if value <= 0 then
        return nil
    end
    return value
end

function AGFAmortizationService.validateTerms(principal, annualRate, periods, balloonAmount)
    local normalizedPrincipal = normalizeNonNegativeMoney(principal)
    if normalizedPrincipal == nil or normalizedPrincipal <= 0 then
        return false, "INVALID_PRINCIPAL"
    end

    local normalizedPeriods = normalizePeriods(periods)
    if normalizedPeriods == nil then
        return false, "INVALID_TERM"
    end

    local rateValid, normalizedRateOrError = AGFRateConvention.validateAnnualRate(annualRate)
    if not rateValid then
        return false, normalizedRateOrError
    end

    local normalizedBalloon = normalizeNonNegativeMoney(balloonAmount or 0)
    if normalizedBalloon == nil then
        return false, "INVALID_BALLOON"
    end
    if AGFCurrency.toMinorUnits(normalizedBalloon) > AGFCurrency.toMinorUnits(normalizedPrincipal) then
        return false, "BALLOON_EXCEEDS_PRINCIPAL"
    end

    return true, {
        principal = normalizedPrincipal,
        annualRate = normalizedRateOrError,
        periods = normalizedPeriods,
        balloonAmount = normalizedBalloon
    }
end

function AGFAmortizationService.calculateRegularPayment(principal, annualRate, periods, balloonAmount)
    local valid, termsOrError = AGFAmortizationService.validateTerms(principal, annualRate, periods, balloonAmount)
    if not valid then
        return nil, termsOrError
    end

    local terms = termsOrError
    local periodicRate, rateError = AGFRateConvention.toPeriodicRate(terms.annualRate)
    if periodicRate == nil then
        return nil, rateError
    end

    local payment
    if periodicRate == 0 then
        payment = (terms.principal - terms.balloonAmount) / terms.periods
    else
        local growth = (1 + periodicRate) ^ terms.periods
        local balloonPresentValue = terms.balloonAmount / growth
        local denominator = 1 - ((1 + periodicRate) ^ (-terms.periods))
        if denominator == 0 then
            return nil, "PAYMENT_DENOMINATOR_ZERO"
        end
        payment = (terms.principal - balloonPresentValue) * periodicRate / denominator
    end

    payment = AGFCurrency.round(payment)
    if payment < 0 then
        return nil, "NEGATIVE_PAYMENT"
    end

    return payment, nil
end

function AGFAmortizationService.generateSchedule(principal, annualRate, periods, balloonAmount)
    local valid, termsOrError = AGFAmortizationService.validateTerms(principal, annualRate, periods, balloonAmount)
    if not valid then
        return nil, termsOrError
    end

    local terms = termsOrError
    local regularPayment, paymentError = AGFAmortizationService.calculateRegularPayment(
        terms.principal,
        terms.annualRate,
        terms.periods,
        terms.balloonAmount
    )
    if regularPayment == nil then
        return nil, paymentError
    end

    local periodicRate, rateError = AGFRateConvention.toPeriodicRate(terms.annualRate)
    if periodicRate == nil then
        return nil, rateError
    end

    local rows = {}
    local openingBalance = terms.principal
    local totalInterest = 0
    local totalRegularPrincipal = 0
    local totalPayments = 0

    for periodIndex = 1, terms.periods do
        openingBalance = AGFCurrency.round(openingBalance)
        local interest = AGFCurrency.round(openingBalance * periodicRate)
        local regularPrincipal
        local periodRegularPayment
        local balloonPayment = 0

        if periodIndex == terms.periods then
            regularPrincipal = AGFCurrency.round(math.max(0, openingBalance - terms.balloonAmount))
            periodRegularPayment = AGFCurrency.round(interest + regularPrincipal)
            balloonPayment = AGFCurrency.round(math.min(terms.balloonAmount, math.max(0, openingBalance - regularPrincipal)))
        else
            regularPrincipal = AGFCurrency.round(regularPayment - interest)
            if regularPrincipal < 0 then
                return nil, "NEGATIVE_AMORTIZATION"
            end

            local maximumPrincipal = AGFCurrency.round(math.max(0, openingBalance - terms.balloonAmount))
            if AGFCurrency.toMinorUnits(regularPrincipal) > AGFCurrency.toMinorUnits(maximumPrincipal) then
                regularPrincipal = maximumPrincipal
            end
            periodRegularPayment = AGFCurrency.round(interest + regularPrincipal)
        end

        local balanceBeforeBalloon = AGFCurrency.round(math.max(0, openingBalance - regularPrincipal))
        local endingBalance = AGFCurrency.round(math.max(0, balanceBeforeBalloon - balloonPayment))
        local totalPayment = AGFCurrency.round(periodRegularPayment + balloonPayment)

        table.insert(rows, {
            period = periodIndex,
            openingBalance = openingBalance,
            annualRate = terms.annualRate,
            periodicRate = periodicRate,
            interest = interest,
            regularPrincipal = regularPrincipal,
            regularPayment = periodRegularPayment,
            balloonPayment = balloonPayment,
            totalPayment = totalPayment,
            endingBalance = endingBalance
        })

        totalInterest = AGFCurrency.round(totalInterest + interest)
        totalRegularPrincipal = AGFCurrency.round(totalRegularPrincipal + regularPrincipal)
        totalPayments = AGFCurrency.round(totalPayments + totalPayment)
        openingBalance = endingBalance
    end

    local principalRepaid = AGFCurrency.round(totalRegularPrincipal + terms.balloonAmount)
    if not AGFCurrency.equals(principalRepaid, terms.principal) then
        return nil, "PRINCIPAL_RECONCILIATION_FAILED"
    end

    if not AGFCurrency.equals(openingBalance, 0) then
        return nil, "ENDING_BALANCE_NOT_ZERO"
    end

    return {
        principal = terms.principal,
        annualRate = terms.annualRate,
        periodicRate = periodicRate,
        periods = terms.periods,
        balloonAmount = terms.balloonAmount,
        quotedRegularPayment = regularPayment,
        schedule = rows,
        totalInterest = totalInterest,
        totalPrincipal = principalRepaid,
        totalPayments = totalPayments
    }, nil
end

function AGFAmortizationService.calculatePayoff(principalBalance, accruedInterest, accruedFees, payoffCharges)
    local principal = normalizeNonNegativeMoney(principalBalance)
    local interest = normalizeNonNegativeMoney(accruedInterest or 0)
    local fees = normalizeNonNegativeMoney(accruedFees or 0)
    local charges = normalizeNonNegativeMoney(payoffCharges or 0)

    if principal == nil then return nil, "INVALID_PRINCIPAL" end
    if interest == nil then return nil, "INVALID_ACCRUED_INTEREST" end
    if fees == nil then return nil, "INVALID_ACCRUED_FEES" end
    if charges == nil then return nil, "INVALID_PAYOFF_CHARGES" end

    return {
        principal = principal,
        interest = interest,
        fees = fees,
        payoffCharges = charges,
        total = AGFCurrency.round(principal + interest + fees + charges)
    }, nil
end
