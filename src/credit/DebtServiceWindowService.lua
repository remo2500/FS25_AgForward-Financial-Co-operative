-- AgForward Financial Cooperative
-- Pure debt-service horizon calculator from dated contract schedule rows.
-- This avoids annualizing scheduled payments by assumption when exact due dates
-- and interest/principal/balloon components are available.

AGFDebtServiceWindowService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function positiveInteger(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

local function nonNegativeMoney(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function ordinal(year, period)
    local y = positiveInteger(year)
    local p = positiveInteger(period)
    if y == nil or p == nil or p > 12 then return nil end
    return y * 12 + (p - 1)
end

local function normalizeRow(row, contractIndex, rowIndex)
    row = row or {}
    local dueOrdinal = ordinal(row.dueYear, row.duePeriod)
    if dueOrdinal == nil then
        return nil, string.format("INVALID_DUE_PERIOD_CONTRACT_%d_ROW_%d", contractIndex, rowIndex)
    end

    local interest = nonNegativeMoney(row.interest)
    local regularPrincipal = nonNegativeMoney(row.regularPrincipal)
    local balloonPrincipal = nonNegativeMoney(row.balloonPayment)
    local fees = nonNegativeMoney(row.fees or row.scheduledFees or 0)
    if interest == nil then return nil, string.format("INVALID_INTEREST_CONTRACT_%d_ROW_%d", contractIndex, rowIndex) end
    if regularPrincipal == nil then return nil, string.format("INVALID_PRINCIPAL_CONTRACT_%d_ROW_%d", contractIndex, rowIndex) end
    if balloonPrincipal == nil then return nil, string.format("INVALID_BALLOON_CONTRACT_%d_ROW_%d", contractIndex, rowIndex) end
    if fees == nil then return nil, string.format("INVALID_FEES_CONTRACT_%d_ROW_%d", contractIndex, rowIndex) end

    local principal = AGFCurrency.round(regularPrincipal + balloonPrincipal)
    local calculatedPayment = AGFCurrency.round(interest + principal + fees)
    local statedPayment = row.totalPayment ~= nil and nonNegativeMoney(row.totalPayment) or nil
    if row.totalPayment ~= nil and statedPayment == nil then
        return nil, string.format("INVALID_TOTAL_PAYMENT_CONTRACT_%d_ROW_%d", contractIndex, rowIndex)
    end

    -- Existing amortization rows normally exclude fees from totalPayment. When
    -- a stated payment exists, it must reconcile to interest + principal; fees
    -- remain an additional scheduled cash obligation.
    if statedPayment ~= nil then
        local scheduleComponents = AGFCurrency.round(interest + principal)
        if not AGFCurrency.equals(statedPayment, scheduleComponents) then
            return nil, string.format("PAYMENT_COMPONENT_MISMATCH_CONTRACT_%d_ROW_%d", contractIndex, rowIndex)
        end
    end

    return {
        dueYear = row.dueYear,
        duePeriod = row.duePeriod,
        dueOrdinal = dueOrdinal,
        paymentNumber = row.paymentNumber or row.period,
        phase = row.phase,
        interest = interest,
        principal = principal,
        regularPrincipal = regularPrincipal,
        balloonPrincipal = balloonPrincipal,
        fees = fees,
        totalCashDue = calculatedPayment
    }, nil
end

function AGFDebtServiceWindowService.calculate(contracts, asOfYear, asOfPeriod, horizonPeriods)
    local startOrdinal = ordinal(asOfYear, asOfPeriod)
    if startOrdinal == nil then return false, "INVALID_AS_OF_PERIOD" end

    local horizon = positiveInteger(horizonPeriods or 12)
    if horizon == nil then return false, "INVALID_HORIZON" end
    local endExclusive = startOrdinal + horizon

    local resultRows = {}
    local byContract = {}
    local totalInterest = 0
    local totalPrincipal = 0
    local totalBalloonPrincipal = 0
    local totalFees = 0
    local totalDebtService = 0
    local paymentCount = 0

    for contractIndex, contract in ipairs(contracts or {}) do
        contract = contract or {}
        local contractId = tostring(contract.liabilityId or contract.contractId or ("contract-" .. tostring(contractIndex)))
        local contractTotal = {
            liabilityId = contract.liabilityId,
            contractId = contractId,
            interest = 0,
            principal = 0,
            balloonPrincipal = 0,
            fees = 0,
            totalDebtService = 0,
            paymentCount = 0
        }

        for rowIndex, sourceRow in ipairs(contract.schedule or {}) do
            local row, rowError = normalizeRow(sourceRow, contractIndex, rowIndex)
            if row == nil then return false, rowError end

            if row.dueOrdinal >= startOrdinal and row.dueOrdinal < endExclusive then
                row.liabilityId = contract.liabilityId
                row.contractId = contractId
                table.insert(resultRows, row)

                contractTotal.interest = AGFCurrency.round(contractTotal.interest + row.interest)
                contractTotal.principal = AGFCurrency.round(contractTotal.principal + row.principal)
                contractTotal.balloonPrincipal = AGFCurrency.round(contractTotal.balloonPrincipal + row.balloonPrincipal)
                contractTotal.fees = AGFCurrency.round(contractTotal.fees + row.fees)
                contractTotal.totalDebtService = AGFCurrency.round(contractTotal.totalDebtService + row.totalCashDue)
                contractTotal.paymentCount = contractTotal.paymentCount + 1

                totalInterest = AGFCurrency.round(totalInterest + row.interest)
                totalPrincipal = AGFCurrency.round(totalPrincipal + row.principal)
                totalBalloonPrincipal = AGFCurrency.round(totalBalloonPrincipal + row.balloonPrincipal)
                totalFees = AGFCurrency.round(totalFees + row.fees)
                totalDebtService = AGFCurrency.round(totalDebtService + row.totalCashDue)
                paymentCount = paymentCount + 1
            end
        end

        byContract[contractId] = contractTotal
    end

    table.sort(resultRows, function(left, right)
        if left.dueOrdinal == right.dueOrdinal then
            if tostring(left.contractId) == tostring(right.contractId) then
                return (tonumber(left.paymentNumber) or 0) < (tonumber(right.paymentNumber) or 0)
            end
            return tostring(left.contractId) < tostring(right.contractId)
        end
        return left.dueOrdinal < right.dueOrdinal
    end)

    return true, {
        asOfYear = asOfYear,
        asOfPeriod = asOfPeriod,
        horizonPeriods = horizon,
        windowStartOrdinal = startOrdinal,
        windowEndExclusiveOrdinal = endExclusive,
        interest = totalInterest,
        principal = totalPrincipal,
        balloonPrincipal = totalBalloonPrincipal,
        fees = totalFees,
        totalDebtService = totalDebtService,
        paymentCount = paymentCount,
        rows = resultRows,
        byContract = byContract
    }
end
