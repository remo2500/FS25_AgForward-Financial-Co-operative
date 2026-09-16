-- AgForward Financial Cooperative
-- Pure lease-payment due schedule. Economic lease authority remains in LeaseRegistry;
-- this service only derives dates/contracted rent for reporting and future settlement.

AGFLeaseScheduleService = {}

function AGFLeaseScheduleService.build(lease, startYear, startPeriod, firstPaymentDelayPeriods)
    if lease == nil or lease.id == nil then return false, "INVALID_LEASE" end

    local paymentCount = tonumber(lease.termPeriods)
    if paymentCount == nil or paymentCount <= 0 or paymentCount ~= math.floor(paymentCount) then
        return false, "INVALID_LEASE_TERM"
    end

    local paymentsPerYear = tonumber(lease.paymentsPerYear or 12)
    local dueSchedule, dueError = AGFPaymentFrequencyService.buildDueSchedule(
        startYear,
        startPeriod,
        paymentCount,
        paymentsPerYear,
        firstPaymentDelayPeriods
    )
    if dueSchedule == nil then return false, dueError end

    local rent = AGFCurrency.round(tonumber(lease.periodicRent) or 0)
    if rent < 0 then return false, "NEGATIVE_RENT" end

    local rows = {}
    local totalRent = 0
    for _, due in ipairs(dueSchedule.schedule) do
        totalRent = AGFCurrency.round(totalRent + rent)
        table.insert(rows, {
            paymentNumber = due.paymentNumber,
            dueYear = due.dueYear,
            duePeriod = due.duePeriod,
            periodsFromStart = due.periodsFromStart,
            rent = rent
        })
    end

    local first = rows[1]
    local last = rows[#rows]
    return true, {
        leaseId = lease.id,
        assetId = lease.assetId,
        lesseeFarmId = lease.lesseeFarmId,
        paymentsPerYear = paymentsPerYear,
        intervalPeriods = dueSchedule.intervalPeriods,
        paymentCount = paymentCount,
        periodicRent = rent,
        annualizedRent = AGFCurrency.round(rent * paymentsPerYear),
        totalContractedRent = totalRent,
        firstDueYear = first.dueYear,
        firstDuePeriod = first.duePeriod,
        finalDueYear = last.dueYear,
        finalDuePeriod = last.duePeriod,
        schedule = rows
    }
end
