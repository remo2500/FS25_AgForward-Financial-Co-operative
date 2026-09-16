-- AgForward Financial Cooperative
-- Pure merger of an amortization schedule with FS financial-period due dates.
-- Standard annuity rows assume equal payment intervals; full payment deferral or
-- other irregular-period math must use an explicit structured schedule rather
-- than changing dates after the financial calculations are complete.

AGFLoanContractScheduleService = {}

function AGFLoanContractScheduleService.build(quote, startYear, startPeriod)
    if quote == nil or quote.amortization == nil or type(quote.amortization.schedule) ~= "table" then
        return false, "INVALID_QUOTE_AMORTIZATION"
    end

    local amortization = quote.amortization
    local paymentCount = #amortization.schedule
    if paymentCount <= 0 then return false, "EMPTY_AMORTIZATION_SCHEDULE" end

    local paymentsPerYear = quote.paymentsPerYear or amortization.periodsPerYear or AGFRateConvention.PERIODS_PER_YEAR
    local dueSchedule, dueError = AGFPaymentFrequencyService.buildDueSchedule(
        startYear,
        startPeriod,
        paymentCount,
        paymentsPerYear
    )
    if dueSchedule == nil then return false, dueError end

    local renewalPaymentNumber = nil
    local renewalPrincipal = nil
    if quote.rateTermSummary ~= nil and quote.rateTermSummary.requiresRenewal then
        renewalPaymentNumber = quote.rateTermSummary.renewalAfterPaymentNumber
        renewalPrincipal = quote.rateTermSummary.renewalPrincipal
    end

    local rows = {}
    for index, amortizationRow in ipairs(amortization.schedule) do
        local due = dueSchedule.schedule[index]
        local isRenewal = renewalPaymentNumber ~= nil and index == renewalPaymentNumber
        table.insert(rows, {
            paymentNumber = index,
            phase = amortizationRow.phase or "amortizing",
            dueYear = due.dueYear,
            duePeriod = due.duePeriod,
            periodsFromStart = due.periodsFromStart,
            openingBalance = amortizationRow.openingBalance,
            annualRate = amortizationRow.annualRate,
            periodicRate = amortizationRow.periodicRate,
            interest = amortizationRow.interest,
            regularPrincipal = amortizationRow.regularPrincipal,
            regularPayment = amortizationRow.regularPayment,
            balloonPayment = amortizationRow.balloonPayment,
            totalPayment = amortizationRow.totalPayment,
            endingBalance = amortizationRow.endingBalance,
            rateRenewalDue = isRenewal,
            renewalPrincipal = isRenewal and renewalPrincipal or nil
        })
    end

    local first = rows[1]
    local last = rows[#rows]
    local renewalRow = renewalPaymentNumber ~= nil and rows[renewalPaymentNumber] or nil
    return true, {
        startYear = startYear,
        startPeriod = startPeriod,
        paymentsPerYear = paymentsPerYear,
        intervalPeriods = dueSchedule.intervalPeriods,
        paymentCount = paymentCount,
        interestOnlyPeriods = quote.interestOnlyPeriods or amortization.interestOnlyPeriods or 0,
        rateTermPeriods = quote.rateTermPeriods,
        rateTermSummary = quote.rateTermSummary,
        firstDueYear = first.dueYear,
        firstDuePeriod = first.duePeriod,
        rateRenewalDueYear = renewalRow ~= nil and renewalRow.dueYear or nil,
        rateRenewalDuePeriod = renewalRow ~= nil and renewalRow.duePeriod or nil,
        renewalPrincipal = renewalRow ~= nil and renewalRow.renewalPrincipal or nil,
        maturityYear = last.dueYear,
        maturityPeriod = last.duePeriod,
        principal = amortization.principal,
        annualRate = amortization.annualRate,
        interestOnlyPayment = amortization.interestOnlyPayment,
        quotedRegularPayment = amortization.quotedRegularPayment,
        balloonAmount = amortization.balloonAmount,
        totalInterest = amortization.totalInterest,
        totalPayments = amortization.totalPayments,
        schedule = rows
    }
end
