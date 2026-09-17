-- AgForward Financial Cooperative
-- Pure covenant/condition monitoring for existing credit facilities. This is
-- intentionally separate from origination approval: a covenant exception is an
-- information/review state, not an automatic default, repossession, or denial.

AGFCovenantStatus = {
    COMPLIANT = "compliant",
    WARNING = "warning",
    BREACH = "breach",
    INCOMPLETE = "incomplete"
}

AGFCovenantSeverity = {
    WARNING = "warning",
    BREACH = "breach"
}

AGFCovenantMonitoringService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function compare(actual, comparator, threshold)
    if comparator == "min" then return actual >= threshold end
    if comparator == "max" then return actual <= threshold end
    if comparator == "gt" then return actual > threshold end
    if comparator == "lt" then return actual < threshold end
    if comparator == "eq" then return actual == threshold end
    if comparator == "ne" then return actual ~= threshold end
    return nil
end

local function severityRank(severity)
    if severity == AGFCovenantSeverity.BREACH then return 2 end
    if severity == AGFCovenantSeverity.WARNING then return 1 end
    return 0
end

local function normalizeThreshold(value)
    if type(value) == "boolean" or type(value) == "string" then return value end
    local number = tonumber(value)
    if number == nil or not isFinite(number) then return nil end
    return number
end

local function copyTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

function AGFCovenantMonitoringService.evaluate(values, covenantSet, context)
    values = values or {}
    covenantSet = covenantSet or {}
    context = context or {}

    local result = {
        status = AGFCovenantStatus.COMPLIANT,
        setName = covenantSet.name,
        setVersion = covenantSet.version,
        asOfYear = context.asOfYear,
        asOfPeriod = context.asOfPeriod,
        passed = {},
        warnings = {},
        breaches = {},
        missing = {},
        ruleCount = 0,
        highestSeverity = 0
    }

    for index, rule in ipairs(covenantSet.rules or {}) do
        result.ruleCount = result.ruleCount + 1
        local ruleId = rule.id or ((rule.metric or "covenant") .. "-" .. tostring(index))
        local metricName = rule.metric
        local actual = metricName ~= nil and values[metricName] or nil
        local threshold = normalizeThreshold(rule.value)
        if threshold == nil then return false, "INVALID_COVENANT_THRESHOLD:" .. tostring(ruleId) end

        local severity = rule.severity or AGFCovenantSeverity.BREACH
        if severity ~= AGFCovenantSeverity.WARNING and severity ~= AGFCovenantSeverity.BREACH then
            return false, "INVALID_COVENANT_SEVERITY:" .. tostring(ruleId)
        end

        if actual == nil then
            local missingBehavior = rule.missingBehavior or "warning"
            local record = {
                id = ruleId,
                metric = metricName,
                comparator = rule.comparator,
                threshold = threshold,
                severity = severity,
                message = rule.message,
                reason = "MISSING_VALUE"
            }
            table.insert(result.missing, record)

            if missingBehavior == "breach" then
                record.severity = AGFCovenantSeverity.BREACH
                table.insert(result.breaches, record)
                result.highestSeverity = math.max(result.highestSeverity, 2)
            elseif missingBehavior == "warning" then
                record.severity = AGFCovenantSeverity.WARNING
                table.insert(result.warnings, record)
                result.highestSeverity = math.max(result.highestSeverity, 1)
            elseif missingBehavior ~= "ignore" then
                return false, "INVALID_MISSING_BEHAVIOR:" .. tostring(ruleId)
            end
        else
            if type(actual) == "number" and not isFinite(actual) then
                return false, "INVALID_COVENANT_VALUE:" .. tostring(ruleId)
            end
            local passed = compare(actual, rule.comparator, threshold)
            if passed == nil then return false, "INVALID_COVENANT_COMPARATOR:" .. tostring(ruleId) end

            local record = {
                id = ruleId,
                metric = metricName,
                actual = actual,
                comparator = rule.comparator,
                threshold = threshold,
                severity = severity,
                message = rule.message,
                metadata = copyTable(rule.metadata)
            }

            if passed then
                table.insert(result.passed, record)
            elseif severity == AGFCovenantSeverity.BREACH then
                table.insert(result.breaches, record)
                result.highestSeverity = math.max(result.highestSeverity, severityRank(severity))
            else
                table.insert(result.warnings, record)
                result.highestSeverity = math.max(result.highestSeverity, severityRank(severity))
            end
        end
    end

    if #result.breaches > 0 then
        result.status = AGFCovenantStatus.BREACH
    elseif #result.warnings > 0 then
        result.status = AGFCovenantStatus.WARNING
    elseif #result.missing > 0 then
        result.status = AGFCovenantStatus.INCOMPLETE
    else
        result.status = AGFCovenantStatus.COMPLIANT
    end

    result.compliant = #result.breaches == 0 and #result.warnings == 0 and #result.missing == 0
    result.reviewRequired = #result.breaches > 0 or #result.warnings > 0 or #result.missing > 0
    return true, result
end

function AGFCovenantMonitoringService.compareReviews(previousReview, currentReview)
    if previousReview == nil or currentReview == nil then return false, "REVIEW_REQUIRED" end

    local previousFailures = {}
    for _, row in ipairs(previousReview.warnings or {}) do previousFailures[row.id] = row end
    for _, row in ipairs(previousReview.breaches or {}) do previousFailures[row.id] = row end
    for _, row in ipairs(previousReview.missing or {}) do previousFailures[row.id] = row end

    local currentFailures = {}
    for _, row in ipairs(currentReview.warnings or {}) do currentFailures[row.id] = row end
    for _, row in ipairs(currentReview.breaches or {}) do currentFailures[row.id] = row end
    for _, row in ipairs(currentReview.missing or {}) do currentFailures[row.id] = row end

    local newExceptions = {}
    local curedExceptions = {}
    local continuingExceptions = {}

    for id, row in pairs(currentFailures) do
        if previousFailures[id] == nil then table.insert(newExceptions, row)
        else table.insert(continuingExceptions, row) end
    end
    for id, row in pairs(previousFailures) do
        if currentFailures[id] == nil then table.insert(curedExceptions, row) end
    end

    local function sortById(rows)
        table.sort(rows, function(left, right) return tostring(left.id) < tostring(right.id) end)
    end
    sortById(newExceptions)
    sortById(curedExceptions)
    sortById(continuingExceptions)

    return true, {
        previousStatus = previousReview.status,
        currentStatus = currentReview.status,
        newExceptions = newExceptions,
        curedExceptions = curedExceptions,
        continuingExceptions = continuingExceptions
    }
end
