-- AgForward Financial Cooperative
-- Pure servicing review for existing liabilities. This service is read-only:
-- it identifies upcoming contractual events and review conditions but never
-- approves, renews, collects, accelerates, or mutates a liability.

AGFServicingReviewService = {}

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

local function periodIndex(year, period, periodsPerYear)
    local y = positiveInteger(year)
    local p = positiveInteger(period)
    if y == nil or p == nil or p > periodsPerYear then return nil end
    return (y * periodsPerYear) + (p - 1)
end

local function periodsUntil(currentYear, currentPeriod, targetYear, targetPeriod, periodsPerYear)
    local current = periodIndex(currentYear, currentPeriod, periodsPerYear)
    local target = periodIndex(targetYear, targetPeriod, periodsPerYear)
    if current == nil or target == nil then return nil end
    return target - current
end

local function shallowCopy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function addReason(result, code, severity, source, detail)
    table.insert(result.reviewReasons, {
        code = code,
        severity = severity,
        source = source,
        detail = detail
    })

    local rank = severity == "urgent" and 2 or (severity == "review" and 1 or 0)
    result.highestSeverity = math.max(result.highestSeverity, rank)
end

local function findNextScheduleRow(contractSchedule, currentYear, currentPeriod, periodsPerYear)
    local bestRow = nil
    local bestDistance = nil
    for _, row in ipairs(contractSchedule ~= nil and contractSchedule.schedule or {}) do
        local distance = periodsUntil(currentYear, currentPeriod, row.dueYear, row.duePeriod, periodsPerYear)
        if distance ~= nil and distance >= 0 and (bestDistance == nil or distance < bestDistance) then
            bestRow = row
            bestDistance = distance
        end
    end
    return bestRow, bestDistance
end

function AGFServicingReviewService.build(liability, contractSchedule, delinquencyAccount, covenantReview, currentYear, currentPeriod, options)
    options = options or {}
    if liability == nil or liability.id == nil then return false, "LIABILITY_REQUIRED" end

    local periodsPerYear = positiveInteger(options.periodsPerYear or 12)
    if periodsPerYear == nil then return false, "INVALID_PERIODS_PER_YEAR" end
    if periodIndex(currentYear, currentPeriod, periodsPerYear) == nil then
        return false, "INVALID_CURRENT_PERIOD"
    end

    local paymentLookahead = math.max(0, math.floor(tonumber(options.paymentLookaheadPeriods) or 1))
    local renewalLookahead = math.max(0, math.floor(tonumber(options.renewalLookaheadPeriods) or periodsPerYear))
    local maturityLookahead = math.max(0, math.floor(tonumber(options.maturityLookaheadPeriods) or periodsPerYear))

    local principal = nonNegativeMoney(liability.principalBalance)
    local accruedInterest = nonNegativeMoney(liability.accruedInterest)
    local accruedFees = nonNegativeMoney(liability.accruedFees)
    if principal == nil or accruedInterest == nil or accruedFees == nil then
        return false, "INVALID_LIABILITY_BALANCE"
    end

    local result = {
        liabilityId = liability.id,
        farmId = liability.farmId,
        productType = liability.productType,
        liabilityStatus = liability.status,
        asOfYear = currentYear,
        asOfPeriod = currentPeriod,
        principalBalance = principal,
        accruedInterest = accruedInterest,
        accruedFees = accruedFees,
        outstandingBalance = AGFCurrency.round(principal + accruedInterest + accruedFees),
        nextPayment = nil,
        rateRenewal = nil,
        maturity = nil,
        delinquency = nil,
        covenant = nil,
        reviewReasons = {},
        highestSeverity = 0,
        requiresReview = false,
        status = "current"
    }

    if liability.status == "closed" then
        result.status = "closed"
        if result.outstandingBalance > 0 then
            addReason(result, "CLOSED_WITH_BALANCE", "urgent", "liability", {
                outstandingBalance = result.outstandingBalance
            })
            result.status = "urgent"
        end
        result.requiresReview = #result.reviewReasons > 0
        return true, result
    end

    if liability.status == "chargedOff" then
        addReason(result, "CHARGED_OFF_ACCOUNT", "review", "liability", {
            outstandingBalance = result.outstandingBalance
        })
    end

    local nextYear = positiveInteger(liability.nextPaymentYear)
    local nextPeriod = positiveInteger(liability.nextPaymentPeriod)
    local nextAmount = nonNegativeMoney(liability.scheduledPayment)

    if nextYear == nil or nextPeriod == nil or nextPeriod > periodsPerYear then
        local nextRow, rowDistance = findNextScheduleRow(contractSchedule, currentYear, currentPeriod, periodsPerYear)
        if nextRow ~= nil then
            nextYear = nextRow.dueYear
            nextPeriod = nextRow.duePeriod
            nextAmount = nonNegativeMoney(nextRow.totalPayment or nextRow.regularPayment or 0) or 0
            result.nextPayment = {
                dueYear = nextYear,
                duePeriod = nextPeriod,
                amount = nextAmount,
                periodsUntil = rowDistance,
                source = "contractSchedule",
                paymentNumber = nextRow.paymentNumber
            }
        end
    else
        local distance = periodsUntil(currentYear, currentPeriod, nextYear, nextPeriod, periodsPerYear)
        result.nextPayment = {
            dueYear = nextYear,
            duePeriod = nextPeriod,
            amount = nextAmount or 0,
            periodsUntil = distance,
            source = "liability"
        }
    end

    if result.nextPayment ~= nil and result.nextPayment.periodsUntil ~= nil then
        local distance = result.nextPayment.periodsUntil
        if distance < 0 then
            addReason(result, "PAYMENT_DATE_PASSED", "urgent", "payment", shallowCopy(result.nextPayment))
        elseif distance == 0 then
            addReason(result, "PAYMENT_DUE_NOW", "review", "payment", shallowCopy(result.nextPayment))
        elseif distance <= paymentLookahead then
            addReason(result, "PAYMENT_DUE_SOON", "notice", "payment", shallowCopy(result.nextPayment))
        end
    end

    if contractSchedule ~= nil and contractSchedule.rateRenewalDueYear ~= nil and contractSchedule.rateRenewalDuePeriod ~= nil then
        local distance = periodsUntil(
            currentYear,
            currentPeriod,
            contractSchedule.rateRenewalDueYear,
            contractSchedule.rateRenewalDuePeriod,
            periodsPerYear
        )
        result.rateRenewal = {
            dueYear = contractSchedule.rateRenewalDueYear,
            duePeriod = contractSchedule.rateRenewalDuePeriod,
            renewalPrincipal = nonNegativeMoney(contractSchedule.renewalPrincipal or 0) or 0,
            periodsUntil = distance
        }
        if distance ~= nil then
            if distance < 0 then
                addReason(result, "RATE_RENEWAL_PAST_DUE", "urgent", "rateRenewal", shallowCopy(result.rateRenewal))
            elseif distance == 0 then
                addReason(result, "RATE_RENEWAL_DUE_NOW", "review", "rateRenewal", shallowCopy(result.rateRenewal))
            elseif distance <= renewalLookahead then
                addReason(result, "RATE_RENEWAL_DUE_SOON", "review", "rateRenewal", shallowCopy(result.rateRenewal))
            end
        end
    end

    if contractSchedule ~= nil and contractSchedule.maturityYear ~= nil and contractSchedule.maturityPeriod ~= nil then
        local distance = periodsUntil(
            currentYear,
            currentPeriod,
            contractSchedule.maturityYear,
            contractSchedule.maturityPeriod,
            periodsPerYear
        )
        result.maturity = {
            dueYear = contractSchedule.maturityYear,
            duePeriod = contractSchedule.maturityPeriod,
            balloonAmount = nonNegativeMoney(contractSchedule.balloonAmount or liability.balloonAmount or 0) or 0,
            periodsUntil = distance
        }
        if distance ~= nil then
            if distance < 0 and result.outstandingBalance > 0 then
                addReason(result, "MATURITY_PAST_DUE", "urgent", "maturity", shallowCopy(result.maturity))
            elseif distance == 0 then
                addReason(result, "MATURITY_DUE_NOW", "urgent", "maturity", shallowCopy(result.maturity))
            elseif distance <= maturityLookahead then
                addReason(result, "MATURITY_DUE_SOON", "review", "maturity", shallowCopy(result.maturity))
            end
        end
    end

    if delinquencyAccount ~= nil then
        result.delinquency = {
            state = delinquencyAccount.state,
            missedPayments = math.max(0, math.floor(tonumber(delinquencyAccount.missedPayments) or 0)),
            pastDueAmount = nonNegativeMoney(delinquencyAccount.pastDueAmount or 0) or 0
        }

        local state = tostring(result.delinquency.state or "current")
        if state ~= "current" and state ~= "resolved" then
            local severity = (state == "collections" or state == "recovery" or state == "chargedOff") and "urgent" or "review"
            addReason(result, "DELINQUENCY_REVIEW_REQUIRED", severity, "delinquency", shallowCopy(result.delinquency))
        elseif result.delinquency.pastDueAmount > 0 then
            addReason(result, "PAST_DUE_AMOUNT_WITH_CURRENT_STATE", "review", "delinquency", shallowCopy(result.delinquency))
        end
    elseif liability.status == "pastDue" or liability.status == "delinquent" or liability.status == "collections" then
        addReason(result, "LIABILITY_STATUS_REQUIRES_SERVICING_REVIEW", "review", "liability", {
            liabilityStatus = liability.status
        })
    end

    if covenantReview ~= nil then
        result.covenant = {
            status = covenantReview.status,
            reviewRequired = covenantReview.reviewRequired == true,
            breachCount = #(covenantReview.breaches or {}),
            warningCount = #(covenantReview.warnings or {}),
            missingCount = #(covenantReview.missing or {})
        }

        if result.covenant.breachCount > 0 then
            addReason(result, "COVENANT_BREACH_REVIEW", "urgent", "covenant", shallowCopy(result.covenant))
        elseif result.covenant.reviewRequired then
            addReason(result, "COVENANT_REVIEW_REQUIRED", "review", "covenant", shallowCopy(result.covenant))
        end
    end

    result.requiresReview = #result.reviewReasons > 0
    if result.highestSeverity >= 2 then
        result.status = "urgent"
    elseif result.highestSeverity >= 1 then
        result.status = "review"
    elseif result.requiresReview then
        result.status = "upcoming"
    end

    return true, result
end
