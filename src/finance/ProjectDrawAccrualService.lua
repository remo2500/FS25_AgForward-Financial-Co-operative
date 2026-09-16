-- AgForward Financial Cooperative
-- Pure staged construction/project draw model. Interest accrues on funds actually
-- advanced during each FS financial period rather than on the full commitment.
-- This service performs no construction, cash movement, or liability mutation.

AGFProjectDrawAccrualService = {}

local function normalizeMoney(value)
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

local function normalizeFraction(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    if number < 0 or number > 1 then return nil end
    return number
end

function AGFProjectDrawAccrualService.calculate(commitmentAmount, openingPrincipal, annualRate, periodCount, draws)
    local commitment = normalizeMoney(commitmentAmount)
    if commitment == nil or commitment <= 0 then return false, "INVALID_COMMITMENT" end

    local opening = normalizeMoney(openingPrincipal or 0)
    if opening == nil then return false, "INVALID_OPENING_PRINCIPAL" end
    if AGFCurrency.toMinorUnits(opening) > AGFCurrency.toMinorUnits(commitment) then
        return false, "OPENING_PRINCIPAL_EXCEEDS_COMMITMENT"
    end

    local periods = normalizePositiveInteger(periodCount)
    if periods == nil then return false, "INVALID_PERIOD_COUNT" end

    local rateValid, rateOrError = AGFRateConvention.validateAnnualRate(annualRate)
    if not rateValid then return false, rateOrError end
    local normalizedRate = rateOrError

    local byPeriod = {}
    local normalizedDraws = {}
    for index, draw in ipairs(draws or {}) do
        local periodIndex = normalizePositiveInteger(draw.period)
        if periodIndex == nil or periodIndex > periods then
            return false, "INVALID_DRAW_PERIOD_ROW_" .. tostring(index)
        end
        local fraction = normalizeFraction(draw.periodFraction == nil and 0 or draw.periodFraction)
        if fraction == nil then return false, "INVALID_DRAW_FRACTION_ROW_" .. tostring(index) end
        local amount = normalizeMoney(draw.amount)
        if amount == nil or amount <= 0 then return false, "INVALID_DRAW_AMOUNT_ROW_" .. tostring(index) end

        local row = {
            period = periodIndex,
            periodFraction = fraction,
            amount = amount,
            sequence = tonumber(draw.sequence) or index,
            useType = draw.useType,
            description = draw.description,
            reference = draw.reference
        }
        table.insert(normalizedDraws, row)
        byPeriod[periodIndex] = byPeriod[periodIndex] or {}
        table.insert(byPeriod[periodIndex], row)
    end

    local principal = opening
    local totalDraws = 0
    local totalInterest = 0
    local rows = {}

    for periodIndex = 1, periods do
        local periodDraws = byPeriod[periodIndex] or {}
        table.sort(periodDraws, function(left, right)
            if left.periodFraction == right.periodFraction then
                return left.sequence < right.sequence
            end
            return left.periodFraction < right.periodFraction
        end)

        local runningPrincipal = principal
        local balanceChanges = {}
        local periodDrawTotal = 0
        for _, draw in ipairs(periodDraws) do
            runningPrincipal = AGFCurrency.round(runningPrincipal + draw.amount)
            if AGFCurrency.toMinorUnits(runningPrincipal) > AGFCurrency.toMinorUnits(commitment) then
                return false, "PROJECT_COMMITMENT_EXCEEDED"
            end
            periodDrawTotal = AGFCurrency.round(periodDrawTotal + draw.amount)
            table.insert(balanceChanges, {
                periodFraction = draw.periodFraction,
                amount = draw.amount,
                sequence = draw.sequence
            })
        end

        local accrual, accrualError = AGFRevolvingInterestService.calculatePeriodInterest(
            principal,
            balanceChanges,
            normalizedRate
        )
        if accrual == nil then return false, accrualError end

        principal = accrual.endingBalance
        totalDraws = AGFCurrency.round(totalDraws + periodDrawTotal)
        totalInterest = AGFCurrency.round(totalInterest + accrual.interest)

        local copiedDraws = {}
        for _, draw in ipairs(periodDraws) do
            table.insert(copiedDraws, {
                period = draw.period,
                periodFraction = draw.periodFraction,
                amount = draw.amount,
                sequence = draw.sequence,
                useType = draw.useType,
                description = draw.description,
                reference = draw.reference
            })
        end

        table.insert(rows, {
            period = periodIndex,
            openingPrincipal = accrual.openingBalance,
            draws = copiedDraws,
            periodDrawTotal = periodDrawTotal,
            averagePrincipal = accrual.averageBalance,
            annualRate = accrual.annualRate,
            periodicRate = accrual.periodicRate,
            interestAccrued = accrual.interest,
            endingPrincipal = accrual.endingBalance,
            undrawnCommitment = AGFCurrency.round(commitment - accrual.endingBalance)
        })
    end

    return true, {
        commitmentAmount = commitment,
        openingPrincipal = opening,
        annualRate = normalizedRate,
        periods = periods,
        draws = normalizedDraws,
        periodRows = rows,
        totalDraws = totalDraws,
        totalInterestAccrued = totalInterest,
        endingPrincipal = principal,
        undrawnCommitment = AGFCurrency.round(commitment - principal),
        conversionPrincipal = principal
    }
end
