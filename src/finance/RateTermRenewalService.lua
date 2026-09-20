-- AgForward Financial Cooperative
-- Pure distinction between amortization/maturity and an earlier rate term.
-- A rate-term renewal is not a balloon payoff: remaining principal continues
-- under a new/repriced contract term after server re-underwriting/repricing.

AGFRateTermRenewalService = {}

local function normalizePositiveInteger(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    if number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

function AGFRateTermRenewalService.summarize(amortization, rateTermPeriods)
    if amortization == nil or type(amortization.schedule) ~= "table" or #amortization.schedule == 0 then
        return false, "INVALID_AMORTIZATION"
    end

    local term = normalizePositiveInteger(rateTermPeriods)
    if term == nil then return false, "INVALID_RATE_TERM" end

    local totalPeriods = #amortization.schedule
    if term > totalPeriods then return false, "RATE_TERM_EXCEEDS_AMORTIZATION" end

    local termInterest = 0
    local termPrincipal = 0
    local termPayments = 0
    local termBalloonPayments = 0

    for index = 1, term do
        local row = amortization.schedule[index]
        termInterest = AGFCurrency.round(termInterest + (tonumber(row.interest) or 0))
        termPrincipal = AGFCurrency.round(termPrincipal + (tonumber(row.regularPrincipal) or 0) + (tonumber(row.balloonPayment) or 0))
        termPayments = AGFCurrency.round(termPayments + (tonumber(row.totalPayment) or 0))
        termBalloonPayments = AGFCurrency.round(termBalloonPayments + (tonumber(row.balloonPayment) or 0))
    end

    local finalTermRow = amortization.schedule[term]
    local renewalPrincipal = AGFCurrency.round(math.max(0, tonumber(finalTermRow.endingBalance) or 0))
    local remainingPeriods = totalPeriods - term

    -- If a true contractual balloon/maturity payment occurred inside the rate
    -- term, its principal was actually due. Renewal principal is simply the
    -- balance remaining after the selected term row.
    local requiresRenewal = term < totalPeriods and renewalPrincipal > 0

    return true, {
        rateTermPeriods = term,
        totalAmortizationPeriods = totalPeriods,
        remainingAmortizationPeriods = remainingPeriods,
        renewalAfterPaymentNumber = term,
        renewalPrincipal = renewalPrincipal,
        requiresRenewal = requiresRenewal,
        termInterest = termInterest,
        termPrincipalPaid = termPrincipal,
        termPayments = termPayments,
        termBalloonPayments = termBalloonPayments,
        endingBalanceAtRenewal = renewalPrincipal,
        paymentFrequency = amortization.periodsPerYear,
        originalPrincipal = amortization.principal,
        originalAnnualRate = amortization.annualRate
    }
end
