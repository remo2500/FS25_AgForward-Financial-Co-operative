-- AgForward Financial Cooperative
-- Pure time-weighted revolving-credit interest calculation. Balance changes are
-- expressed as fractions of a financial period, making the calculation independent
-- from the player's configured number of FS gameplay days per month.

AGFRevolvingInterestService = {}

local function normalizeFraction(value)
    local fraction = tonumber(value)
    if fraction == nil or fraction ~= fraction then return nil end
    if fraction < 0 or fraction > 1 then return nil end
    return fraction
end

function AGFRevolvingInterestService.calculateAverageBalance(openingBalance, balanceChanges)
    local opening = AGFCurrency.round(tonumber(openingBalance) or 0)
    if opening < 0 then return nil, "NEGATIVE_OPENING_BALANCE" end

    local changes = {}
    for _, change in ipairs(balanceChanges or {}) do
        local fraction = normalizeFraction(change.periodFraction)
        local amount = AGFCurrency.round(tonumber(change.amount) or 0)
        if fraction == nil then return nil, "INVALID_PERIOD_FRACTION" end
        table.insert(changes, {
            periodFraction = fraction,
            amount = amount,
            sequence = tonumber(change.sequence) or 0
        })
    end

    table.sort(changes, function(left, right)
        if left.periodFraction == right.periodFraction then
            return left.sequence < right.sequence
        end
        return left.periodFraction < right.periodFraction
    end)

    local balance = opening
    local previousFraction = 0
    local weightedBalance = 0

    for _, change in ipairs(changes) do
        local duration = change.periodFraction - previousFraction
        if duration < 0 then return nil, "UNSORTED_PERIOD_FRACTION" end
        weightedBalance = weightedBalance + balance * duration
        balance = AGFCurrency.round(balance + change.amount)
        if balance < 0 then return nil, "BALANCE_CHANGE_OVER_REPAYS_LINE" end
        previousFraction = change.periodFraction
    end

    weightedBalance = weightedBalance + balance * (1 - previousFraction)
    return {
        openingBalance = opening,
        endingBalance = balance,
        averageBalance = AGFCurrency.round(weightedBalance),
        exactAverageBalance = weightedBalance,
        changes = changes
    }, nil
end

function AGFRevolvingInterestService.calculatePeriodInterest(openingBalance, balanceChanges, annualRate)
    local balanceResult, balanceError = AGFRevolvingInterestService.calculateAverageBalance(openingBalance, balanceChanges)
    if balanceResult == nil then return nil, balanceError end

    local periodicRate, rateError = AGFRateConvention.toPeriodicRate(annualRate)
    if periodicRate == nil then return nil, rateError end

    local interest = AGFCurrency.round(balanceResult.exactAverageBalance * periodicRate)
    return {
        openingBalance = balanceResult.openingBalance,
        endingBalance = balanceResult.endingBalance,
        averageBalance = balanceResult.averageBalance,
        periodicRate = periodicRate,
        annualRate = annualRate,
        interest = interest,
        changes = balanceResult.changes
    }, nil
end
