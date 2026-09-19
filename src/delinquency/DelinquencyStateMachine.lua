-- AgForward Financial Cooperative
-- Pure delinquency lifecycle shared by future loans, leases, and secured recovery.

AGFDelinquencyState = {
    CURRENT = "current",
    PAST_DUE = "pastDue",
    DELINQUENT = "delinquent",
    FINAL_NOTICE = "finalNotice",
    COLLECTIONS = "collections",
    RECOVERY = "recovery",
    RESOLVED = "resolved",
    CHARGED_OFF = "chargedOff"
}

AGFDelinquencyStateMachine = {}

local VALID_STATES = {}
for _, value in pairs(AGFDelinquencyState) do VALID_STATES[value] = true end

function AGFDelinquencyStateMachine.isValidState(state)
    return VALID_STATES[state] == true
end

function AGFDelinquencyStateMachine.defaultPolicy()
    return {
        pastDueAtMissedPayments = 1,
        delinquentAtMissedPayments = 2,
        finalNoticeAtMissedPayments = 3,
        collectionsAtMissedPayments = 4,
        recoveryAtMissedPayments = 5
    }
end

function AGFDelinquencyStateMachine.validatePolicy(policy)
    policy = policy or AGFDelinquencyStateMachine.defaultPolicy()
    local keys = {
        "pastDueAtMissedPayments",
        "delinquentAtMissedPayments",
        "finalNoticeAtMissedPayments",
        "collectionsAtMissedPayments",
        "recoveryAtMissedPayments"
    }

    local previous = 0
    for _, key in ipairs(keys) do
        local value = math.floor(tonumber(policy[key]) or -1)
        if value <= previous then
            return false, "INVALID_DELINQUENCY_POLICY_ORDER"
        end
        previous = value
    end
    return true, policy
end

function AGFDelinquencyStateMachine.stateForMissedPayments(missedPayments, policy)
    local valid, normalizedPolicyOrError = AGFDelinquencyStateMachine.validatePolicy(policy)
    if not valid then return nil, normalizedPolicyOrError end
    local p = normalizedPolicyOrError
    local missed = math.max(0, math.floor(tonumber(missedPayments) or 0))

    if missed >= p.recoveryAtMissedPayments then return AGFDelinquencyState.RECOVERY, nil end
    if missed >= p.collectionsAtMissedPayments then return AGFDelinquencyState.COLLECTIONS, nil end
    if missed >= p.finalNoticeAtMissedPayments then return AGFDelinquencyState.FINAL_NOTICE, nil end
    if missed >= p.delinquentAtMissedPayments then return AGFDelinquencyState.DELINQUENT, nil end
    if missed >= p.pastDueAtMissedPayments then return AGFDelinquencyState.PAST_DUE, nil end
    return AGFDelinquencyState.CURRENT, nil
end

function AGFDelinquencyStateMachine.newAccountState()
    return {
        state = AGFDelinquencyState.CURRENT,
        missedPayments = 0,
        pastDueAmount = 0,
        lastTransitionYear = nil,
        lastTransitionPeriod = nil,
        history = {}
    }
end

local function appendHistory(account, fromState, toState, reason, year, period)
    table.insert(account.history, {
        fromState = fromState,
        toState = toState,
        reason = reason,
        year = year,
        period = period
    })
end

function AGFDelinquencyStateMachine.recordMissedPayment(account, unpaidAmount, policy, year, period)
    if account == nil then return false, "ACCOUNT_STATE_REQUIRED" end
    local amount = math.abs(AGFCurrency.round(tonumber(unpaidAmount) or 0))
    if amount <= 0 then return false, "INVALID_UNPAID_AMOUNT" end

    local previousState = account.state or AGFDelinquencyState.CURRENT
    if previousState == AGFDelinquencyState.RESOLVED or previousState == AGFDelinquencyState.CHARGED_OFF then
        return false, "DELINQUENCY_ACCOUNT_CLOSED"
    end

    account.missedPayments = math.max(0, math.floor(tonumber(account.missedPayments) or 0)) + 1
    account.pastDueAmount = AGFCurrency.round((account.pastDueAmount or 0) + amount)

    local nextState, stateError = AGFDelinquencyStateMachine.stateForMissedPayments(account.missedPayments, policy)
    if nextState == nil then return false, stateError end
    account.state = nextState

    if nextState ~= previousState then
        account.lastTransitionYear = year
        account.lastTransitionPeriod = period
        appendHistory(account, previousState, nextState, "missedPayment", year, period)
    end

    return true, account
end

function AGFDelinquencyStateMachine.applyCurePayment(account, paymentAmount, year, period)
    if account == nil then return false, "ACCOUNT_STATE_REQUIRED" end
    local payment = math.abs(AGFCurrency.round(tonumber(paymentAmount) or 0))
    if payment <= 0 then return false, "INVALID_PAYMENT_AMOUNT" end

    local due = math.max(0, AGFCurrency.round(account.pastDueAmount or 0))
    local applied = math.min(payment, due)
    account.pastDueAmount = AGFCurrency.round(due - applied)
    local unapplied = AGFCurrency.round(payment - applied)

    if AGFCurrency.equals(account.pastDueAmount, 0) then
        local previousState = account.state or AGFDelinquencyState.CURRENT
        account.state = AGFDelinquencyState.CURRENT
        account.missedPayments = 0
        if previousState ~= AGFDelinquencyState.CURRENT then
            account.lastTransitionYear = year
            account.lastTransitionPeriod = period
            appendHistory(account, previousState, AGFDelinquencyState.CURRENT, "cured", year, period)
        end
    end

    return true, {
        account = account,
        applied = applied,
        unappliedAmount = unapplied
    }
end

function AGFDelinquencyStateMachine.transition(account, targetState, reason, year, period)
    if account == nil then return false, "ACCOUNT_STATE_REQUIRED" end
    if not AGFDelinquencyStateMachine.isValidState(targetState) then return false, "INVALID_TARGET_STATE" end

    local previousState = account.state or AGFDelinquencyState.CURRENT
    if previousState == targetState then return true, account end

    if previousState == AGFDelinquencyState.CHARGED_OFF then
        return false, "CHARGED_OFF_STATE_FINAL"
    end

    account.state = targetState
    account.lastTransitionYear = year
    account.lastTransitionPeriod = period
    appendHistory(account, previousState, targetState, reason or "manual", year, period)
    return true, account
end
