-- AgForward Financial Cooperative
-- Pure sanitization/normalization for future client finance applications.
-- Clients may express intent/preferences; they never supply authoritative farm,
-- pricing, approval, balance, collateral-value, asset-context, or quote fields.

AGFFinancialApplicationIntentService = {}

local AUTHORITATIVE_FIELDS = {
    "farmId",
    "connectionKey",
    "annualRate",
    "contractRate",
    "apr",
    "pricing",
    "pricingVersion",
    "quote",
    "decisionStatus",
    "approvalStatus",
    "manualApproval",
    "policyVersion",
    "stateRevision",
    "liabilityId",
    "principalBalance",
    "creditLimit",
    "scheduledPayment",
    "totalInterest",
    "collateralValue",
    "appraisedValue",
    "marketValue",
    "priorClaims",
    "borrowingBase",
    "purchasePrice",
    "assetId",
    "lienPriority",
    "contextFingerprint"
}

local VALID_RATE_PREFERENCES = {
    fixed = true,
    variable = true,
    either = true
}

local VALID_PAYMENT_FREQUENCIES = {
    [1] = true,
    [2] = true,
    [4] = true,
    [12] = true
}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function positiveInteger(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

local function nonNegativeInteger(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) or number < 0 or number ~= math.floor(number) then return nil end
    return number
end

local function positiveMoney(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number <= 0 then return nil end
    return number
end

local function nonNegativeMoney(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function copyMetadata(metadata)
    local copy = {}
    for key, value in pairs(metadata or {}) do
        local valueType = type(value)
        if valueType == "string" or valueType == "number" or valueType == "boolean" then
            copy[tostring(key)] = value
        end
    end
    return copy
end

local function rejectAuthoritativeFields(rawIntent)
    for _, field in ipairs(AUTHORITATIVE_FIELDS) do
        if rawIntent[field] ~= nil then
            return false, "AUTHORITATIVE_FIELD_NOT_ALLOWED:" .. field
        end
    end
    return true, nil
end

local function anyPresent(rawIntent, fields)
    for _, field in ipairs(fields) do
        if rawIntent[field] ~= nil then return true end
    end
    return false
end

local function applyRatePreference(rawIntent, product, intent)
    if not product.supportsFixedRate and not product.supportsVariableRate then
        if rawIntent.ratePreference ~= nil then return false, "RATE_PREFERENCE_NOT_APPLICABLE" end
        intent.ratePreference = nil
        return true, nil
    end

    if rawIntent.ratePreference ~= nil then
        local preference = tostring(rawIntent.ratePreference)
        if not VALID_RATE_PREFERENCES[preference] then return false, "INVALID_RATE_PREFERENCE" end
        if preference == "fixed" and not product.supportsFixedRate then return false, "FIXED_RATE_NOT_SUPPORTED" end
        if preference == "variable" and not product.supportsVariableRate then return false, "VARIABLE_RATE_NOT_SUPPORTED" end
        intent.ratePreference = preference
    else
        intent.ratePreference = "either"
    end
    return true, nil
end

local function applyCommonCreditPreferences(rawIntent, product, intent)
    local rateOk, rateError = applyRatePreference(rawIntent, product, intent)
    if not rateOk then return false, rateError end

    if rawIntent.requestedTermPeriods ~= nil then
        intent.requestedTermPeriods = positiveInteger(rawIntent.requestedTermPeriods)
        if intent.requestedTermPeriods == nil then return false, "INVALID_REQUESTED_TERM" end
    end

    if rawIntent.paymentsPerYear ~= nil then
        local frequency = positiveInteger(rawIntent.paymentsPerYear)
        if frequency == nil or not VALID_PAYMENT_FREQUENCIES[frequency] then
            return false, "INVALID_PAYMENT_FREQUENCY"
        end
        intent.paymentsPerYear = frequency
    end

    if rawIntent.interestOnlyPeriods ~= nil then
        intent.interestOnlyPeriods = nonNegativeInteger(rawIntent.interestOnlyPeriods)
        if intent.interestOnlyPeriods == nil then return false, "INVALID_INTEREST_ONLY_PERIODS" end
    end

    if rawIntent.balloonPercent ~= nil then
        local balloon = tonumber(rawIntent.balloonPercent)
        if balloon == nil or not isFinite(balloon) or balloon < 0 or balloon > 1 then
            return false, "INVALID_BALLOON_PERCENT"
        end
        if balloon > 0 and not product.supportsBalloon then return false, "BALLOON_NOT_SUPPORTED" end
        intent.balloonPercent = balloon
    end

    return true, nil
end

function AGFFinancialApplicationIntentService.sanitize(rawIntent, serverContext)
    rawIntent = rawIntent or {}
    serverContext = serverContext or {}

    local authoritativeOk, authoritativeError = rejectAuthoritativeFields(rawIntent)
    if not authoritativeOk then return false, authoritativeError end

    local farmId = positiveInteger(serverContext.derivedFarmId)
    if farmId == nil then return false, "SERVER_FARM_REQUIRED" end

    local productType = rawIntent.productType
    if productType == nil or not AGFProductCatalog.exists(productType) then
        return false, "UNKNOWN_PRODUCT"
    end

    local product = AGFProductCatalog.get(productType)
    local intent = {
        farmId = farmId,
        connectionKey = serverContext.connectionKey ~= nil and tostring(serverContext.connectionKey) or nil,
        productType = productType,
        productKind = product.kind,
        contextFingerprint = serverContext.contextFingerprint,
        purposeCode = rawIntent.purposeCode ~= nil and tostring(rawIntent.purposeCode) or nil,
        metadata = copyMetadata(rawIntent.metadata)
    }

    if product.kind == AGFProductKind.LEASE then
        if anyPresent(rawIntent, {
            "requestedAmount",
            "requestedLimit",
            "requestedDownPayment",
            "requestedDownPaymentPercent",
            "requestedTermPeriods",
            "paymentsPerYear",
            "ratePreference",
            "interestOnlyPeriods",
            "balloonPercent"
        }) then
            return false, "LEASE_FINANCE_FIELDS_NOT_ALLOWED"
        end
        if serverContext.contextFingerprint == nil or serverContext.contextFingerprint == "" then
            return false, "SERVER_CONTEXT_FINGERPRINT_REQUIRED"
        end
        intent.ratePreference = nil
        intent.requestedLeaseTermPeriods = positiveInteger(rawIntent.requestedLeaseTermPeriods)
        if intent.requestedLeaseTermPeriods == nil then return false, "REQUESTED_LEASE_TERM_REQUIRED" end
        return true, intent
    end

    local preferenceOk, preferenceError = applyCommonCreditPreferences(rawIntent, product, intent)
    if not preferenceOk then return false, preferenceError end

    if product.kind == AGFProductKind.REVOLVING_CREDIT then
        intent.requestedLimit = positiveMoney(rawIntent.requestedLimit)
        if intent.requestedLimit == nil then return false, "REQUESTED_LIMIT_REQUIRED" end
        if anyPresent(rawIntent, {"requestedAmount", "requestedDownPayment", "requestedDownPaymentPercent", "interestOnlyPeriods"}) then
            return false, "REVOLVER_PURCHASE_FIELDS_NOT_ALLOWED"
        end
    elseif product.kind == AGFProductKind.TERM_CREDIT then
        intent.requestedAmount = positiveMoney(rawIntent.requestedAmount)
        if intent.requestedAmount == nil then return false, "REQUESTED_AMOUNT_REQUIRED" end
        if anyPresent(rawIntent, {"requestedLimit", "requestedDownPayment", "requestedDownPaymentPercent"}) then
            return false, "TERM_DOWN_PAYMENT_NOT_APPLICABLE"
        end
    elseif product.kind == AGFProductKind.ASSET_FINANCE then
        if rawIntent.requestedLimit ~= nil or rawIntent.requestedAmount ~= nil then
            return false, "ASSET_FINANCE_AMOUNT_IS_SERVER_DERIVED"
        end

        local serverPrice = positiveMoney(serverContext.purchasePrice)
        if serverPrice == nil then return false, "SERVER_PURCHASE_PRICE_REQUIRED" end
        if serverContext.contextFingerprint == nil or serverContext.contextFingerprint == "" then
            return false, "SERVER_CONTEXT_FINGERPRINT_REQUIRED"
        end
        intent.purchasePrice = serverPrice

        if rawIntent.requestedDownPayment ~= nil and rawIntent.requestedDownPaymentPercent ~= nil then
            return false, "DOWN_PAYMENT_AMOUNT_AND_PERCENT_BOTH_SET"
        end
        if rawIntent.requestedDownPayment ~= nil then
            local downPayment = nonNegativeMoney(rawIntent.requestedDownPayment)
            if downPayment == nil or downPayment > serverPrice then return false, "INVALID_REQUESTED_DOWN_PAYMENT" end
            intent.requestedDownPayment = downPayment
        elseif rawIntent.requestedDownPaymentPercent ~= nil then
            local percent = tonumber(rawIntent.requestedDownPaymentPercent)
            if percent == nil or not isFinite(percent) or percent < 0 or percent > 1 then
                return false, "INVALID_REQUESTED_DOWN_PAYMENT_PERCENT"
            end
            intent.requestedDownPaymentPercent = percent
        end
    else
        return false, "UNSUPPORTED_PRODUCT_KIND"
    end

    return true, intent
end
