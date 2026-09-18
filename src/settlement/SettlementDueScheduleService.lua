-- AgForward Financial Cooperative
-- Pure current-period due extractor. It converts dated loan/lease contract rows
-- into planner-compatible obligations but never decides final production policy
-- or mutates cash, liabilities, leases, or delinquency state.

AGFSettlementDueScheduleService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function positiveInteger(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function policyFor(policy, productType, obligationType)
    policy = policy or {}
    local result = {}
    for key, value in pairs(policy.default or {}) do result[key] = value end
    if policy.byObligationType ~= nil and policy.byObligationType[obligationType] ~= nil then
        for key, value in pairs(policy.byObligationType[obligationType]) do result[key] = value end
    end
    if policy.byProduct ~= nil and policy.byProduct[productType] ~= nil then
        for key, value in pairs(policy.byProduct[productType]) do result[key] = value end
    end
    return result
end

local function minimumPayment(amountDue, rule)
    if rule.minimumPaymentAmount ~= nil then
        local amount = money(rule.minimumPaymentAmount)
        if amount == nil then return nil, "INVALID_MINIMUM_PAYMENT_AMOUNT" end
        return math.min(amountDue, amount), nil
    end
    if rule.minimumPaymentPercent ~= nil then
        local percent = tonumber(rule.minimumPaymentPercent)
        if percent == nil or not isFinite(percent) or percent < 0 or percent > 1 then
            return nil, "INVALID_MINIMUM_PAYMENT_PERCENT"
        end
        return AGFCurrency.round(amountDue * percent), nil
    end
    return amountDue, nil
end

local function addPlannerPolicy(row, policy)
    local rule = policyFor(policy, row.productType, row.obligationType)
    local minimum, minimumError = minimumPayment(row.amountDue, rule)
    if minimum == nil then return false, minimumError end

    row.priority = tonumber(rule.priority) or 1000
    row.allowPartial = rule.allowPartial == true
    row.allowCreditDraw = rule.allowCreditDraw == true
    row.minimumPayment = minimum
    row.plannerObligation = {
        id = row.id,
        obligationType = row.obligationType,
        priority = row.priority,
        amountDue = row.amountDue,
        minimumPayment = row.minimumPayment,
        allowPartial = row.allowPartial,
        allowCreditDraw = row.allowCreditDraw,
        dueYear = row.dueYear,
        duePeriod = row.duePeriod
    }
    return true, nil
end

function AGFSettlementDueScheduleService.build(currentYear, currentPeriod, loanEntries, leaseEntries, policy)
    local year = positiveInteger(currentYear)
    local period = positiveInteger(currentPeriod)
    if year == nil or period == nil or period > 12 then return false, "INVALID_SETTLEMENT_PERIOD" end

    local result = {
        year = year,
        period = period,
        due = {},
        totalScheduledDue = 0,
        loanDue = 0,
        leaseDue = 0,
        requiresAuthoritativeReconciliation = true
    }

    for _, entry in ipairs(loanEntries or {}) do
        if entry.liabilityId == nil or entry.contractSchedule == nil then
            return false, "INVALID_LOAN_SCHEDULE_ENTRY"
        end
        for _, row in ipairs(entry.contractSchedule.schedule or {}) do
            if tonumber(row.dueYear) == year and tonumber(row.duePeriod) == period then
                local amountDue = money(row.totalPayment)
                local interest = money(row.interest)
                local regularPrincipal = money(row.regularPrincipal)
                local balloon = money(row.balloonPayment)
                if amountDue == nil or interest == nil or regularPrincipal == nil or balloon == nil then
                    return false, "INVALID_LOAN_DUE_ROW:" .. tostring(entry.liabilityId)
                end
                local scheduledPrincipal = AGFCurrency.round(regularPrincipal + balloon)
                if not AGFCurrency.equals(amountDue, AGFCurrency.round(scheduledPrincipal + interest)) then
                    return false, "LOAN_DUE_ROW_DOES_NOT_RECONCILE:" .. tostring(entry.liabilityId)
                end

                local due = {
                    id = "loan:" .. tostring(entry.liabilityId) .. ":" .. tostring(row.paymentNumber or 0),
                    sourceType = "loan",
                    obligationType = entry.obligationType or "loanPayment",
                    farmId = entry.farmId,
                    liabilityId = entry.liabilityId,
                    productType = entry.productType,
                    paymentNumber = row.paymentNumber,
                    dueYear = year,
                    duePeriod = period,
                    amountDue = amountDue,
                    scheduledPrincipal = scheduledPrincipal,
                    scheduledInterest = interest,
                    scheduledBalloon = balloon,
                    rateRenewalDue = row.rateRenewalDue == true,
                    requiresAuthoritativeBalanceReconciliation = true
                }
                local policyOk, policyError = addPlannerPolicy(due, policy)
                if not policyOk then return false, policyError end
                table.insert(result.due, due)
                result.totalScheduledDue = AGFCurrency.round(result.totalScheduledDue + amountDue)
                result.loanDue = AGFCurrency.round(result.loanDue + amountDue)
            end
        end
    end

    for _, entry in ipairs(leaseEntries or {}) do
        if entry.leaseId == nil or entry.leaseSchedule == nil then
            return false, "INVALID_LEASE_SCHEDULE_ENTRY"
        end
        for _, row in ipairs(entry.leaseSchedule.schedule or {}) do
            if tonumber(row.dueYear) == year and tonumber(row.duePeriod) == period then
                local rent = money(row.rent)
                if rent == nil then return false, "INVALID_LEASE_DUE_ROW:" .. tostring(entry.leaseId) end

                local due = {
                    id = "lease:" .. tostring(entry.leaseId) .. ":" .. tostring(row.paymentNumber or 0),
                    sourceType = "lease",
                    obligationType = entry.obligationType or "leaseRent",
                    farmId = entry.farmId,
                    leaseId = entry.leaseId,
                    productType = entry.productType or AGFProductType.LAND_LEASE,
                    paymentNumber = row.paymentNumber,
                    dueYear = year,
                    duePeriod = period,
                    amountDue = rent,
                    scheduledRent = rent,
                    requiresAuthoritativeBalanceReconciliation = true
                }
                local policyOk, policyError = addPlannerPolicy(due, policy)
                if not policyOk then return false, policyError end
                table.insert(result.due, due)
                result.totalScheduledDue = AGFCurrency.round(result.totalScheduledDue + rent)
                result.leaseDue = AGFCurrency.round(result.leaseDue + rent)
            end
        end
    end

    table.sort(result.due, function(left, right)
        if left.priority ~= right.priority then return left.priority < right.priority end
        return tostring(left.id) < tostring(right.id)
    end)

    result.plannerObligations = {}
    for _, row in ipairs(result.due) do table.insert(result.plannerObligations, row.plannerObligation) end
    return true, result
end
