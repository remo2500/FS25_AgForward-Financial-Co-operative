-- AgForward Financial Cooperative
-- Shared pure quote engine for term/equipment/project/land finance products.

AGFLoanQuoteService = {}

local function normalizeNonNegativeMoney(value)
    local number = tonumber(value)
    if number == nil then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
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

    local periods = math.floor(tonumber(parameters.periods) or 0)
    if periods <= 0 then return false, "INVALID_TERM" end

    local pricingOk, pricingOrError = AGFRatePricingService.quote(parameters.rateComponents or {})
    if not pricingOk then return false, pricingOrError end
    local pricing = pricingOrError

    local balloonAmount = nil
    if parameters.balloonAmount ~= nil and parameters.balloonPercent ~= nil then
        return false, "BALLOON_AMOUNT_AND_PERCENT_BOTH_SET"
    end

    if parameters.balloonPercent ~= nil then
        local percent = tonumber(parameters.balloonPercent)
        if percent == nil or percent < 0 or percent > 1 then
            return false, "INVALID_BALLOON_PERCENT"
        end
        balloonAmount = AGFCurrency.round(principal * percent)
    else
        balloonAmount = normalizeNonNegativeMoney(parameters.balloonAmount or 0)
        if balloonAmount == nil then return false, "INVALID_BALLOON" end
    end

    local amortization, amortizationError = AGFAmortizationService.generateSchedule(
        principal,
        pricing.annualRate,
        periods,
        balloonAmount
    )
    if amortization == nil then return false, amortizationError end

    local financedShare = purchasePrice > 0 and principal / purchasePrice or nil
    local downPaymentShare = purchasePrice > 0 and downPayment / purchasePrice or nil

    return true, {
        purchasePrice = purchasePrice,
        downPayment = downPayment,
        principal = principal,
        periods = periods,
        balloonAmount = balloonAmount,
        pricing = pricing,
        quotedRegularPayment = amortization.quotedRegularPayment,
        totalInterest = amortization.totalInterest,
        totalPayments = amortization.totalPayments,
        finalPayment = amortization.schedule[#amortization.schedule].totalPayment,
        financedShare = financedShare,
        downPaymentShare = downPaymentShare,
        amortization = amortization
    }
end
