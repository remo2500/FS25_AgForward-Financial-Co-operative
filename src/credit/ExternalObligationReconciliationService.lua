-- AgForward Financial Cooperative
-- Pure reconciliation planner for obligations managed outside AgForward.
-- Runtime adapters discover obligations; this service only compares stable
-- source keys and proposes add/update/retire operations.

AGFExternalObligationReconciliationService = {}

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function externalKey(row)
    if row == nil then return nil end
    if row.externalKey ~= nil and row.externalKey ~= "" then return tostring(row.externalKey) end
    if row.metadata ~= nil and row.metadata.externalKey ~= nil and row.metadata.externalKey ~= "" then
        return tostring(row.metadata.externalKey)
    end
    return nil
end

local function normalizeObservation(row, source)
    local key = externalKey(row)
    if key == nil then return nil, "EXTERNAL_KEY_REQUIRED" end
    if row.obligationType == nil then return nil, "OBLIGATION_TYPE_REQUIRED:" .. key end

    local principal = money(row.principalBalance)
    local debtService = money(row.annualDebtService)
    local fixedCharge = money(row.annualFixedCharge)
    if principal == nil or debtService == nil or fixedCharge == nil then
        return nil, "INVALID_EXTERNAL_OBLIGATION_AMOUNT:" .. key
    end

    return {
        externalKey = key,
        source = source or row.source or "external",
        obligationType = row.obligationType,
        displayName = row.displayName,
        principalBalance = principal,
        annualDebtService = debtService,
        annualFixedCharge = fixedCharge,
        dataQuality = row.dataQuality or "unknown",
        metadata = copyTable(row.metadata)
    }, nil
end

local function changedFields(existing, observed)
    local changed = {}
    local fields = {
        "obligationType",
        "displayName",
        "principalBalance",
        "annualDebtService",
        "annualFixedCharge",
        "dataQuality"
    }
    for _, field in ipairs(fields) do
        if existing[field] ~= observed[field] then table.insert(changed, field) end
    end
    return changed
end

function AGFExternalObligationReconciliationService.plan(existingObligations, observedRows, source)
    source = source or "external"
    local existingByKey = {}
    local unmatchedExisting = {}

    for _, existing in ipairs(existingObligations or {}) do
        if existing.active ~= false and tostring(existing.source or "external") == tostring(source) then
            local key = externalKey(existing)
            if key == nil then
                table.insert(unmatchedExisting, existing)
            elseif existingByKey[key] ~= nil then
                return false, "DUPLICATE_EXISTING_EXTERNAL_KEY:" .. key
            else
                existingByKey[key] = existing
            end
        end
    end

    local observedByKey = {}
    local normalizedObserved = {}
    for _, row in ipairs(observedRows or {}) do
        local normalized, errorCode = normalizeObservation(row, source)
        if normalized == nil then return false, errorCode end
        if observedByKey[normalized.externalKey] ~= nil then
            return false, "DUPLICATE_OBSERVED_EXTERNAL_KEY:" .. normalized.externalKey
        end
        observedByKey[normalized.externalKey] = normalized
        table.insert(normalizedObserved, normalized)
    end

    local result = {
        source = source,
        additions = {},
        updates = {},
        unchanged = {},
        retirements = {},
        unmatchedExisting = unmatchedExisting
    }

    for _, observed in ipairs(normalizedObserved) do
        local existing = existingByKey[observed.externalKey]
        if existing == nil then
            table.insert(result.additions, observed)
        else
            local changed = changedFields(existing, observed)
            if #changed == 0 then
                table.insert(result.unchanged, {
                    existingId = existing.id,
                    externalKey = observed.externalKey,
                    observation = observed
                })
            else
                table.insert(result.updates, {
                    existingId = existing.id,
                    externalKey = observed.externalKey,
                    changedFields = changed,
                    before = copyTable(existing),
                    after = observed
                })
            end
        end
    end

    for key, existing in pairs(existingByKey) do
        if observedByKey[key] == nil then
            table.insert(result.retirements, {
                existingId = existing.id,
                externalKey = key,
                existing = copyTable(existing)
            })
        end
    end

    local function sortByKey(rows)
        table.sort(rows, function(left, right)
            local leftKey = left.externalKey or externalKey(left) or ""
            local rightKey = right.externalKey or externalKey(right) or ""
            return tostring(leftKey) < tostring(rightKey)
        end)
    end
    sortByKey(result.additions)
    sortByKey(result.updates)
    sortByKey(result.unchanged)
    sortByKey(result.retirements)

    result.changeCount = #result.additions + #result.updates + #result.retirements
    result.hasChanges = result.changeCount > 0
    result.completeStableKeyCoverage = #result.unmatchedExisting == 0

    return true, result
end
