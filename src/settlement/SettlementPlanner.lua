-- AgForward Financial Cooperative
-- Pure deterministic obligation planner. It decides proposed allocations only;
-- it never moves FS25 money or mutates agreements.

AGFSettlementPlanner = {}

local function cloneObligation(obligation)
    local copy = {}
    for key, value in pairs(obligation or {}) do copy[key] = value end
    return copy
end

local function normalizeMoney(value)
    return math.max(0, AGFCurrency.round(tonumber(value) or 0))
end

local function validateObligation(obligation)
    if obligation == nil or obligation.id == nil then return false, "INVALID_OBLIGATION" end
    local due = normalizeMoney(obligation.amountDue)
    if due <= 0 then return false, "INVALID_OBLIGATION_AMOUNT" end
    local minimum = normalizeMoney(obligation.minimumPayment or due)
    if minimum > due then return false, "MINIMUM_EXCEEDS_AMOUNT_DUE" end
    return true, nil
end

local function sortObligations(obligations)
    table.sort(obligations, function(left, right)
        local leftPriority = tonumber(left.priority) or 1000
        local rightPriority = tonumber(right.priority) or 1000
        if leftPriority ~= rightPriority then return leftPriority < rightPriority end

        local leftYear = tonumber(left.dueYear) or 999999
        local rightYear = tonumber(right.dueYear) or 999999
        if leftYear ~= rightYear then return leftYear < rightYear end

        local leftPeriod = tonumber(left.duePeriod) or 999999
        local rightPeriod = tonumber(right.duePeriod) or 999999
        if leftPeriod ~= rightPeriod then return leftPeriod < rightPeriod end

        return tostring(left.id) < tostring(right.id)
    end)
end

function AGFSettlementPlanner.plan(obligations, availableCash, optionalCreditAvailable)
    local cash = normalizeMoney(availableCash)
    local credit = normalizeMoney(optionalCreditAvailable or 0)
    local normalized = {}

    for _, obligation in ipairs(obligations or {}) do
        local valid, errorCode = validateObligation(obligation)
        if not valid then return false, errorCode .. ":" .. tostring(obligation and obligation.id) end
        local copy = cloneObligation(obligation)
        copy.amountDue = normalizeMoney(copy.amountDue)
        copy.minimumPayment = normalizeMoney(copy.minimumPayment or copy.amountDue)
        copy.allowPartial = copy.allowPartial == true
        copy.allowCreditDraw = copy.allowCreditDraw == true
        table.insert(normalized, copy)
    end

    sortObligations(normalized)

    local plan = {
        startingCash = cash,
        startingOptionalCredit = credit,
        allocations = {},
        totalCashUsed = 0,
        totalCreditDraw = 0,
        totalPaid = 0,
        totalUnpaid = 0,
        endingCash = cash,
        endingOptionalCredit = credit
    }

    for _, obligation in ipairs(normalized) do
        local liquidity = cash
        local permittedCredit = obligation.allowCreditDraw and credit or 0
        local maximumLiquidity = AGFCurrency.round(liquidity + permittedCredit)
        local targetPayment = obligation.amountDue
        local payment = 0

        if AGFCurrency.toMinorUnits(maximumLiquidity) >= AGFCurrency.toMinorUnits(targetPayment) then
            payment = targetPayment
        elseif obligation.allowPartial then
            if AGFCurrency.toMinorUnits(maximumLiquidity) >= AGFCurrency.toMinorUnits(obligation.minimumPayment) then
                payment = maximumLiquidity
            end
        end

        payment = math.min(targetPayment, AGFCurrency.round(payment))
        local cashUsed = math.min(cash, payment)
        local remainingPayment = AGFCurrency.round(payment - cashUsed)
        local creditDraw = 0
        if remainingPayment > 0 and obligation.allowCreditDraw then
            creditDraw = math.min(credit, remainingPayment)
        end

        local actualPayment = AGFCurrency.round(cashUsed + creditDraw)
        if AGFCurrency.toMinorUnits(actualPayment) < AGFCurrency.toMinorUnits(obligation.minimumPayment) and actualPayment > 0 then
            -- Defensive guard: do not make a sub-minimum partial payment.
            actualPayment = 0
            cashUsed = 0
            creditDraw = 0
        end

        cash = AGFCurrency.round(cash - cashUsed)
        credit = AGFCurrency.round(credit - creditDraw)
        local unpaid = AGFCurrency.round(obligation.amountDue - actualPayment)

        table.insert(plan.allocations, {
            obligationId = obligation.id,
            obligationType = obligation.obligationType,
            priority = obligation.priority,
            amountDue = obligation.amountDue,
            minimumPayment = obligation.minimumPayment,
            paid = actualPayment,
            unpaid = unpaid,
            cashUsed = cashUsed,
            creditDraw = creditDraw,
            fullyPaid = AGFCurrency.equals(unpaid, 0),
            skipped = AGFCurrency.equals(actualPayment, 0)
        })

        plan.totalCashUsed = AGFCurrency.round(plan.totalCashUsed + cashUsed)
        plan.totalCreditDraw = AGFCurrency.round(plan.totalCreditDraw + creditDraw)
        plan.totalPaid = AGFCurrency.round(plan.totalPaid + actualPayment)
        plan.totalUnpaid = AGFCurrency.round(plan.totalUnpaid + unpaid)
    end

    plan.endingCash = cash
    plan.endingOptionalCredit = credit
    return true, plan
end
