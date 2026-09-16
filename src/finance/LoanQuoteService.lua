-- AgForward Financial Cooperative
-- Shared pure quote engine for term/equipment/project/land finance products.

AGFLoanQuoteService = {}

local function normalizeNonNegativeMoney(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function normalizePositiveInteger(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = math.floor(number)
    if number <= 0 then return nil end
    return number
end

local function normalizeNonNegativeInteger(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    if number < 0 or number ~= math.floor(number) then return nil end
    return number
end

function AGFLoanQuoteService.quote(parameters)
    parameters = parameters or {}

    local purchasePrice = normalizeNonNegativeMoney(parameters.purchasePrice or 0)
    local downPayment = normalizeNonNegativeMoney(parameters.downPayment or 0)
    if purchasePrice == nil then return false, "INVALID_PURCHASE_PRICE" end
    if downPayment == nil then return false, "INVALID_DOWN_PAYMENT" end
    if downPayment > purchasePrice and parameters.principal == nil then
        return false, "DOWN_PAYMENT_EXCEEDS_PURCHASE_PRICE"
    end

    local principal
    if parameters.principal ~= nil then
        principal = normalizeNonNegativeMoney(parameters.principal)
    else
        principal = AGFCurrency.round(purchasePrice - downPayment)
    end
    if principal == nil or principal <= 0 then return false, "INVALID_PRINCIPAL" end

    -- `periods` is the total contractual payment-period count. If an initial
    -- interest-only phase is requested, those periods are part of (not added
    -- on top of) the stated term so maturity does not silently extend.
    local periods = normalizePositiveInteger(parameters.periods)
    if periods == nil then return false, "INVALID_TERM" end

    local interestOnlyPeriods = normalizeNonNegativeInteger(parameters.interestOnlyPeriods or 0)
    if interestOnlyPeriods == nil then return false, "INVALID_INTEREST_ONLY_PERIODS" end
    if interestOnlyPeriods >= periods then return false, "INTEREST_ONLY_PHASE_REQUIRES_AMORTIZING_PERIOD" end
    local amortizingPeriods = periods - interestOnlyPeriods

    -- Defaults preserve the original monthly quote behavior. Agricultural
    -- products may instead quote quarterly, semi-annual, or annual payments by
    -- providing the number of payments per year explicitly.
    local paymentsPerYear = normalizePositiveInteger(parameters.paymentsPerYear or AGFRateConvention.PERIODS_PER_YEAR)
    if paymentsPerYear == nil then return false, "INVALID_PAYMENTS_PER_YEAR" end

    local pricingOk, pricingOrError = AGFRatePricingService.quote(parameters.rateComponents or {})
    if not pricingOk then return false, pricingOrError end
    local pricing = pricingOrError

    local balloonAmount = nil
    if parameters.balloonAmount ~= nil and parameters.balloonPercent ~= nil then
        return false, "BALLOON_AMOUNT_AND_PERCENT_BOTH_SET"
    end

    if parameters.balloonPercent ~= nil then
        local percent = tonumber(parameters.balloonPercent)
        if percent == nil or percent ~= percent or percent == math.huge or percent == -math.huge or percent < 0 or percent > 1 then
            return false, "INVALID_BALLOON_PERCENT"
        end
        balloonAmount = AGFCurrency.round(principal * percent)
    else
        balloonAmount = normalizeNonNegativeMoney(parameters.balloonAmount or 0)
        if balloonAmount == nil then return false, "INVALID_BALLOON" end
    end

    local amortization
    local amortizationError
    if interestOnlyPeriods > 0 then
        if AGFStructuredAmortizationService == nil then
            return false, "STRUCTURED_AMORTIZATION_SERVICE_UNAVAILABLE"
        end
        amortization, amortizationError = AGFStructuredAmortizationService.generateInterestOnlyThenAmortizing(
            principal,
            pricing.annualRate,
            interestOnlyPeriods,
            amortizingPeriods,
            balloonAmount,
            paymentsPerYear
        )
    else
        amortization, amortizationError = AGFAmortizationService.generateSchedule(
            principal,
            pricing.annualRate,
            periods,
            balloonAmount,
            paymentsPerYear
        )
    end
    if amortization == nil then return false, amortizationError end

    local financedShare = purchasePrice > 0 and principal / purchasePrice or nil
    local downPaymentShare = purchasePrice > 0 and downPayment / purchasePrice or nil

    return true, {
        purchasePrice = purchasePrice,
        downPayment = downPayment,
        principal = principal,
        periods = periods,
        interestOnlyPeriods = interestOnlyPeriods,
        amortizingPeriods = amortizingPeriods,
        paymentsPerYear = paymentsPerYear,
        balloonAmount = balloonAmount,
        pricing = pricing,
        interestOnlyPayment = amortization.interestOnlyPayment,
        quotedRegularPayment = amortization.quotedRegularPayment,
        totalInterest = amortization.totalInterest,
        totalPayments = amortization.totalPayments,
        finalPayment = amortization.schedule[#amortization.schedule].totalPayment,
        financedShare = financedShare,
        downPaymentShare = downPaymentShare,
        amortization = amortization
    }
end
