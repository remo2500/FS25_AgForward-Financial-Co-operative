-- AgForward Financial Cooperative
-- Pure rate-term renewal amendment planning. A normal rate renewal amends the
-- existing liability; it is not a payoff, new advance, or duplicate liability.

AGFLoanRenewalPlanService = {}

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
    return y * periodsPerYear + (p - 1)
end

local function copyList(rows)
    local result = {}
    for _, row in ipairs(rows or {}) do
        local copy = {}
        for key, value in pairs(row) do copy[key] = value end
        table.insert(result, copy)
    end
    return result
end

local function validateDecision(decision, manualApproval)
    if decision == nil or decision.status == nil then return false, "CREDIT_DECISION_REQUIRED" end
    if decision.status == "decline" then return false, "CREDIT_DECISION_DECLINED" end
    if decision.status == "refer" and manualApproval ~= true then return false, "MANUAL_APPROVAL_REQUIRED" end
    return true, nil
end

function AGFLoanRenewalPlanService.build(liability, contractSchedule, renewalQuote, creditDecision, currentYear, currentPeriod, options)
    options = options or {}
    if liability == nil or liability.id == nil then return false, "LIABILITY_REQUIRED" end
    if liability.status == "closed" or liability.status == "chargedOff" then
        return false, "LIABILITY_NOT_RENEWABLE"
    end
    if liability.isRevolving ~= nil and liability:isRevolving() then
        return false, "REVOLVING_FACILITY_USES_SEPARATE_REVIEW"
    end
    if contractSchedule == nil or contractSchedule.rateRenewalDueYear == nil or contractSchedule.rateRenewalDuePeriod == nil then
        return false, "RATE_RENEWAL_DATE_REQUIRED"
    end
    if renewalQuote == nil or renewalQuote.renewedQuote == nil then
        return false, "RENEWAL_QUOTE_REQUIRED"
    end

    local decisionOk, decisionError = validateDecision(creditDecision, options.manualApproval)
    if not decisionOk then return false, decisionError end

    local periodsPerYear = positiveInteger(options.periodsPerYear or 12)
    if periodsPerYear == nil then return false, "INVALID_PERIODS_PER_YEAR" end
    local currentSerial = periodIndex(currentYear, currentPeriod, periodsPerYear)
    local renewalSerial = periodIndex(contractSchedule.rateRenewalDueYear, contractSchedule.rateRenewalDuePeriod, periodsPerYear)
    if currentSerial == nil or renewalSerial == nil then return false, "INVALID_RENEWAL_PERIOD" end

    local periodsUntilRenewal = renewalSerial - currentSerial
    local reviewWindow = math.max(0, math.floor(tonumber(options.reviewWindowPeriods) or periodsPerYear))
    if periodsUntilRenewal > reviewWindow then
        return false, "RENEWAL_WINDOW_NOT_OPEN"
    end

    local projectedPrincipal = nonNegativeMoney(renewalQuote.renewalPrincipal)
    local actualPrincipal = nonNegativeMoney(liability.principalBalance)
    if projectedPrincipal == nil or projectedPrincipal <= 0 or actualPrincipal == nil then
        return false, "INVALID_RENEWAL_PRINCIPAL"
    end

    local principalVariance = AGFCurrency.round(actualPrincipal - projectedPrincipal)
    local principalTolerance = nonNegativeMoney(options.principalTolerance or 0.01)
    if principalTolerance == nil then return false, "INVALID_PRINCIPAL_TOLERANCE" end

    -- Before the contractual renewal date, the current principal will normally be
    -- higher than the projected renewal principal because future scheduled
    -- payments have not happened yet. At/after renewal, material variance means
    -- the quote must be rebuilt from the authoritative balance.
    if periodsUntilRenewal <= 0
        and math.abs(AGFCurrency.toMinorUnits(principalVariance)) > math.abs(AGFCurrency.toMinorUnits(principalTolerance))
        and options.allowPrincipalVariance ~= true then
        return false, "RENEWAL_PRINCIPAL_CHANGED_REQUOTE_REQUIRED"
    end

    local renewed = renewalQuote.renewedQuote
    if renewed.pricing == nil or renewed.amortization == nil then
        return false, "INVALID_RENEWED_QUOTE"
    end

    local newRate = tonumber(renewed.pricing.annualRate)
    if newRate == nil or not isFinite(newRate) or newRate < 0 then return false, "INVALID_RENEWED_RATE" end
    local newPayment = nonNegativeMoney(renewed.quotedRegularPayment)
    if newPayment == nil or newPayment <= 0 then return false, "INVALID_RENEWED_PAYMENT" end

    local scheduleOk, newScheduleOrError = AGFLoanContractScheduleService.build(
        renewed,
        contractSchedule.rateRenewalDueYear,
        contractSchedule.rateRenewalDuePeriod
    )
    if not scheduleOk then return false, newScheduleOrError end
    local newSchedule = newScheduleOrError

    local amendmentPrincipal = periodsUntilRenewal <= 0 and actualPrincipal or projectedPrincipal
    local conditions = copyList(creditDecision.conditions)
    local referrals = copyList(creditDecision.referrals)

    return true, {
        planType = "rateTermRenewalAmendment",
        liabilityId = liability.id,
        farmId = liability.farmId,
        productType = liability.productType,
        assetId = liability.assetId,
        asOfYear = currentYear,
        asOfPeriod = currentPeriod,
        renewalDueYear = contractSchedule.rateRenewalDueYear,
        renewalDuePeriod = contractSchedule.rateRenewalDuePeriod,
        periodsUntilRenewal = periodsUntilRenewal,
        pastDueRenewal = periodsUntilRenewal < 0,
        projectedRenewalPrincipal = projectedPrincipal,
        actualPrincipal = actualPrincipal,
        principalVariance = principalVariance,
        amendmentPrincipal = amendmentPrincipal,
        creditDecision = {
            status = creditDecision.status,
            manualApproval = options.manualApproval == true,
            conditions = conditions,
            referrals = referrals,
            policyName = creditDecision.policyName,
            policyVersion = creditDecision.policyVersion
        },
        liabilityAmendment = {
            interestRate = newRate,
            scheduledPayment = newPayment,
            balloonAmount = nonNegativeMoney(renewed.balloonAmount or 0) or 0,
            paymentFrequency = renewed.paymentsPerYear or 12,
            remainingPaymentPeriods = #renewed.amortization.schedule,
            rateTermPeriods = renewed.rateTermPeriods,
            nextPaymentYear = newSchedule.firstDueYear,
            nextPaymentPeriod = newSchedule.firstDuePeriod,
            maturityYear = newSchedule.maturityYear,
            maturityPeriod = newSchedule.maturityPeriod
        },
        newContractSchedule = newSchedule,
        cashDelta = 0,
        ledgerIntents = {},
        createsNewLiability = false,
        preservesExistingSecurity = true,
        requiresRequoteAtRenewal = periodsUntilRenewal > 0
    }
end
