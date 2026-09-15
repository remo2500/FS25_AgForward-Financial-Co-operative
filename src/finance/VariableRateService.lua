-- AgForward Financial Cooperative
-- Pure variable-rate history and recast calculations. No agreement mutation or
-- Farming Simulator money movement occurs in this module.

AGFVariableRateRecastPolicy = {
    RECAST_PAYMENT = "recastPayment",
    KEEP_PAYMENT = "keepPayment"
}

AGFVariableRateService = {}

local function periodSerial(year, period)
    local y = math.floor(tonumber(year) or -1)
    local p = math.floor(tonumber(period) or -1)
    if y < 0 or p < 1 or p > AGFRateConvention.PERIODS_PER_YEAR then
        return nil
    end
    return y * AGFRateConvention.PERIODS_PER_YEAR + (p - 1)
end

local function copyEntry(entry)
    local result = {}
    for key, value in pairs(entry or {}) do result[key] = value end
    return result
end

function AGFVariableRateService.validateHistory(history)
    local normalized = {}
    local lastSerial = nil

    for index, entry in ipairs(history or {}) do
        local serial = periodSerial(entry.effectiveYear, entry.effectivePeriod)
        if serial == nil then return false, "INVALID_EFFECTIVE_PERIOD_ROW_" .. tostring(index) end
        local rateValid, rateOrError = AGFRateConvention.validateAnnualRate(entry.annualRate)
        if not rateValid then return false, tostring(rateOrError) .. "_ROW_" .. tostring(index) end
        if lastSerial ~= nil and serial <= lastSerial then
            return false, "NON_INCREASING_RATE_HISTORY_ROW_" .. tostring(index)
        end

        table.insert(normalized, {
            effectiveYear = math.floor(tonumber(entry.effectiveYear)),
            effectivePeriod = math.floor(tonumber(entry.effectivePeriod)),
            serial = serial,
            annualRate = rateOrError,
            baseRate = tonumber(entry.baseRate),
            productSpread = tonumber(entry.productSpread),
            riskSpread = tonumber(entry.riskSpread),
            termAdjustment = tonumber(entry.termAdjustment),
            structureAdjustment = tonumber(entry.structureAdjustment),
            reason = entry.reason,
            source = entry.source
        })
        lastSerial = serial
    end

    return true, normalized
end

function AGFVariableRateService.addReset(history, entry)
    local copy = {}
    for _, existing in ipairs(history or {}) do table.insert(copy, copyEntry(existing)) end
    table.insert(copy, copyEntry(entry))
    local valid, normalizedOrError = AGFVariableRateService.validateHistory(copy)
    if not valid then return false, normalizedOrError end
    return true, normalizedOrError
end

function AGFVariableRateService.getRateForPeriod(history, year, period)
    local targetSerial = periodSerial(year, period)
    if targetSerial == nil then return nil, "INVALID_TARGET_PERIOD" end

    local valid, normalizedOrError = AGFVariableRateService.validateHistory(history)
    if not valid then return nil, normalizedOrError end

    local selected = nil
    for _, entry in ipairs(normalizedOrError) do
        if entry.serial <= targetSerial then
            selected = entry
        else
            break
        end
    end

    if selected == nil then return nil, "NO_RATE_EFFECTIVE_FOR_PERIOD" end
    return copyEntry(selected), nil
end

function AGFVariableRateService.recast(principalBalance, remainingPeriods, balloonAmount, newAnnualRate, existingPayment, policy)
    local principal = math.max(0, AGFCurrency.round(tonumber(principalBalance) or 0))
    local periods = math.floor(tonumber(remainingPeriods) or 0)
    local balloon = math.max(0, AGFCurrency.round(tonumber(balloonAmount) or 0))
    local selectedPolicy = policy or AGFVariableRateRecastPolicy.RECAST_PAYMENT

    if principal <= 0 then return false, "INVALID_PRINCIPAL" end
    if periods <= 0 then return false, "INVALID_REMAINING_TERM" end
    if balloon > principal then return false, "BALLOON_EXCEEDS_PRINCIPAL" end

    local rateValid, rateOrError = AGFRateConvention.validateAnnualRate(newAnnualRate)
    if not rateValid then return false, rateOrError end

    if selectedPolicy == AGFVariableRateRecastPolicy.RECAST_PAYMENT then
        local newPayment, paymentError = AGFAmortizationService.calculateRegularPayment(
            principal,
            rateOrError,
            periods,
            balloon
        )
        if newPayment == nil then return false, paymentError end
        return true, {
            policy = selectedPolicy,
            principalBalance = principal,
            remainingPeriods = periods,
            balloonAmount = balloon,
            annualRate = rateOrError,
            priorPayment = existingPayment ~= nil and AGFCurrency.round(existingPayment) or nil,
            newPayment = newPayment
        }
    end

    if selectedPolicy == AGFVariableRateRecastPolicy.KEEP_PAYMENT then
        local payment = math.max(0, AGFCurrency.round(tonumber(existingPayment) or 0))
        if payment <= 0 then return false, "EXISTING_PAYMENT_REQUIRED" end

        local periodicRate, periodicError = AGFRateConvention.toPeriodicRate(rateOrError)
        if periodicRate == nil then return false, periodicError end

        local balance = principal
        local negativeAmortization = false
        for _ = 1, periods do
            local interest = AGFCurrency.round(balance * periodicRate)
            local regularPrincipal = AGFCurrency.round(payment - interest)
            if regularPrincipal < 0 then
                negativeAmortization = true
                break
            end
            local maximumPrincipal = math.max(0, AGFCurrency.round(balance - balloon))
            regularPrincipal = math.min(regularPrincipal, maximumPrincipal)
            balance = AGFCurrency.round(balance - regularPrincipal)
        end

        if negativeAmortization then return false, "KEEP_PAYMENT_CAUSES_NEGATIVE_AMORTIZATION" end

        return true, {
            policy = selectedPolicy,
            principalBalance = principal,
            remainingPeriods = periods,
            contractualBalloon = balloon,
            annualRate = rateOrError,
            priorPayment = payment,
            newPayment = payment,
            projectedBalanceAtMaturity = balance,
            projectedAdditionalBalloon = AGFCurrency.round(math.max(0, balance - balloon))
        }
    end

    return false, "UNKNOWN_RECAST_POLICY"
end
