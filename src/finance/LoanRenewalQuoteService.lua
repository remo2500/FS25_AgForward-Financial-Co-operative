-- AgForward Financial Cooperative
-- Pure repricing/re-amortization of a balance at contractual rate-term renewal.
-- This service does not approve renewal, move money, or mutate the old loan.

AGFLoanRenewalQuoteService = {}

local function normalizeNonNegativeMoney(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function normalizePositiveInteger(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    if number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

function AGFLoanRenewalQuoteService.quote(originalQuote, newRateComponents, options)
    options = options or {}
    if originalQuote == nil or originalQuote.rateTermSummary == nil then
        return false, "ORIGINAL_QUOTE_HAS_NO_RATE_TERM"
    end

    local summary = originalQuote.rateTermSummary
    if summary.requiresRenewal ~= true then
        return false, "RATE_TERM_DOES_NOT_REQUIRE_RENEWAL"
    end

    local renewalPrincipal = normalizeNonNegativeMoney(summary.renewalPrincipal)
    if renewalPrincipal == nil or renewalPrincipal <= 0 then
        return false, "INVALID_RENEWAL_PRINCIPAL"
    end

    local remainingPeriods = normalizePositiveInteger(summary.remainingAmortizationPeriods)
    if remainingPeriods == nil then return false, "INVALID_REMAINING_AMORTIZATION" end

    local paymentsPerYear = normalizePositiveInteger(options.paymentsPerYear or originalQuote.paymentsPerYear or 12)
    if paymentsPerYear == nil then return false, "INVALID_PAYMENTS_PER_YEAR" end

    local balloonAmount
    if options.balloonAmount ~= nil then
        balloonAmount = normalizeNonNegativeMoney(options.balloonAmount)
    else
        balloonAmount = normalizeNonNegativeMoney(originalQuote.balloonAmount or 0)
    end
    if balloonAmount == nil then return false, "INVALID_BALLOON" end
    if AGFCurrency.toMinorUnits(balloonAmount) > AGFCurrency.toMinorUnits(renewalPrincipal) then
        return false, "BALLOON_EXCEEDS_RENEWAL_PRINCIPAL"
    end

    local newRateTermPeriods = options.rateTermPeriods
    if newRateTermPeriods ~= nil then
        newRateTermPeriods = normalizePositiveInteger(newRateTermPeriods)
        if newRateTermPeriods == nil then return false, "INVALID_RATE_TERM" end
        if newRateTermPeriods > remainingPeriods then return false, "RATE_TERM_EXCEEDS_REMAINING_AMORTIZATION" end
    end

    local interestOnlyPeriods = options.interestOnlyPeriods or 0

    local quoteOk, renewedOrError = AGFLoanQuoteService.quote({
        principal = renewalPrincipal,
        periods = remainingPeriods,
        paymentsPerYear = paymentsPerYear,
        interestOnlyPeriods = interestOnlyPeriods,
        rateTermPeriods = newRateTermPeriods,
        balloonAmount = balloonAmount,
        rateComponents = newRateComponents or {}
    })
    if not quoteOk then return false, renewedOrError end
    local renewed = renewedOrError

    local renewalAfter = tonumber(summary.renewalAfterPaymentNumber) or 0
    local nextOldRow = originalQuote.amortization ~= nil
        and originalQuote.amortization.schedule ~= nil
        and originalQuote.amortization.schedule[renewalAfter + 1]
        or nil
    local oldProjectedPayment = nextOldRow ~= nil and AGFCurrency.round(nextOldRow.regularPayment or nextOldRow.totalPayment or 0) or nil
    local oldRate = originalQuote.pricing ~= nil and tonumber(originalQuote.pricing.annualRate) or tonumber(summary.originalAnnualRate)
    local newRate = renewed.pricing ~= nil and tonumber(renewed.pricing.annualRate) or nil

    return true, {
        renewalPrincipal = renewalPrincipal,
        remainingAmortizationPeriods = remainingPeriods,
        paymentsPerYear = paymentsPerYear,
        preservedBalloonAmount = balloonAmount,
        priorRateTermSummary = summary,
        priorAnnualRate = oldRate,
        renewedAnnualRate = newRate,
        annualRateChange = oldRate ~= nil and newRate ~= nil and (newRate - oldRate) or nil,
        priorProjectedRegularPayment = oldProjectedPayment,
        renewedRegularPayment = renewed.quotedRegularPayment,
        regularPaymentChange = oldProjectedPayment ~= nil and AGFCurrency.round(renewed.quotedRegularPayment - oldProjectedPayment) or nil,
        renewedQuote = renewed
    }
end
