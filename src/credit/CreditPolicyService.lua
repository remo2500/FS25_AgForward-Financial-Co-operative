-- AgForward Financial Cooperative
-- Generic configurable underwriting policy evaluation. Metric calculation remains
-- separate; this service contains no hard-coded lending thresholds.

AGFCreditDecisionStatus = {
    APPROVE = "approve",
    APPROVE_WITH_CONDITIONS = "approveWithConditions",
    REFER = "refer",
    DECLINE = "decline"
}

AGFCreditRuleSeverity = {
    CONDITION = "condition",
    REFER = "refer",
    DECLINE = "decline"
}

AGFCreditPolicyService = {}

local function compare(actual, comparator, threshold)
    if comparator == "min" then return actual >= threshold end
    if comparator == "max" then return actual <= threshold end
    if comparator == "gt" then return actual > threshold end
    if comparator == "lt" then return actual < threshold end
    if comparator == "eq" then return actual == threshold end
    return nil
end

local function severityRank(severity)
    if severity == AGFCreditRuleSeverity.DECLINE then return 3 end
    if severity == AGFCreditRuleSeverity.REFER then return 2 end
    if severity == AGFCreditRuleSeverity.CONDITION then return 1 end
    return 0
end

function AGFCreditPolicyService.evaluate(metrics, policy, context)
    metrics = metrics or {}
    policy = policy or {}
    context = context or {}

    local result = {
        status = AGFCreditDecisionStatus.APPROVE,
        passedRules = {},
        failedRules = {},
        conditions = {},
        referrals = {},
        declineReasons = {},
        missingMetrics = {},
        policyName = policy.name,
        policyVersion = policy.version
    }

    local highestSeverity = 0

    for index, rule in ipairs(policy.rules or {}) do
        local metricName = rule.metric
        local actual = metrics[metricName]
        local ruleId = rule.id or (metricName and (metricName .. "-" .. tostring(index)) or ("rule-" .. tostring(index)))

        if actual == nil then
            table.insert(result.missingMetrics, metricName or ruleId)
            local missingSeverity = rule.missingSeverity or AGFCreditRuleSeverity.REFER
            local failure = {
                id = ruleId,
                metric = metricName,
                reason = "MISSING_METRIC",
                severity = missingSeverity,
                threshold = rule.value,
                comparator = rule.comparator
            }
            table.insert(result.failedRules, failure)
            highestSeverity = math.max(highestSeverity, severityRank(missingSeverity))
            if missingSeverity == AGFCreditRuleSeverity.DECLINE then table.insert(result.declineReasons, failure)
            elseif missingSeverity == AGFCreditRuleSeverity.REFER then table.insert(result.referrals, failure)
            else table.insert(result.conditions, failure) end
        else
            local threshold = tonumber(rule.value)
            if threshold == nil then
                return false, "INVALID_POLICY_THRESHOLD:" .. tostring(ruleId)
            end
            local passed = compare(actual, rule.comparator, threshold)
            if passed == nil then
                return false, "INVALID_POLICY_COMPARATOR:" .. tostring(ruleId)
            end

            local record = {
                id = ruleId,
                metric = metricName,
                actual = actual,
                threshold = threshold,
                comparator = rule.comparator,
                severity = rule.severity or AGFCreditRuleSeverity.REFER,
                message = rule.message
            }

            if passed then
                table.insert(result.passedRules, record)
            else
                table.insert(result.failedRules, record)
                local severity = record.severity
                highestSeverity = math.max(highestSeverity, severityRank(severity))
                if severity == AGFCreditRuleSeverity.DECLINE then table.insert(result.declineReasons, record)
                elseif severity == AGFCreditRuleSeverity.REFER then table.insert(result.referrals, record)
                else table.insert(result.conditions, record) end
            end
        end
    end

    if policy.allowedDataQualities ~= nil and context.dataQuality ~= nil then
        local allowed = false
        for _, quality in ipairs(policy.allowedDataQualities) do
            if quality == context.dataQuality then allowed = true break end
        end
        if not allowed then
            local severity = policy.dataQualitySeverity or AGFCreditRuleSeverity.REFER
            local failure = {
                id = "dataQuality",
                metric = "dataQuality",
                actual = context.dataQuality,
                reason = "DATA_QUALITY_NOT_ALLOWED",
                severity = severity
            }
            table.insert(result.failedRules, failure)
            highestSeverity = math.max(highestSeverity, severityRank(severity))
            if severity == AGFCreditRuleSeverity.DECLINE then table.insert(result.declineReasons, failure)
            elseif severity == AGFCreditRuleSeverity.REFER then table.insert(result.referrals, failure)
            else table.insert(result.conditions, failure) end
        end
    end

    if highestSeverity >= 3 then result.status = AGFCreditDecisionStatus.DECLINE
    elseif highestSeverity == 2 then result.status = AGFCreditDecisionStatus.REFER
    elseif highestSeverity == 1 then result.status = AGFCreditDecisionStatus.APPROVE_WITH_CONDITIONS
    else result.status = AGFCreditDecisionStatus.APPROVE end

    return true, result
end
