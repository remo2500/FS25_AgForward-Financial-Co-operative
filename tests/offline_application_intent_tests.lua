-- Offline validation for server-derived financial application intent.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/products/ProductCatalog.lua")
dofile("src/network/FinancialApplicationIntentService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local function assertFalse(value, message)
    if value ~= false then error(message or "expected false") end
end

-- Revolving CILOC intent derives farm identity from server context and preserves
-- only borrower preferences, not authoritative credit terms.
local cilocOk, ciloc = AGFFinancialApplicationIntentService.sanitize({
    productType = AGFProductType.CROP_INPUT_LINE,
    requestedLimit = 250000,
    ratePreference = "variable",
    purposeCode = "2027-crop-inputs",
    metadata = {note = "spring inputs", requestedByUI = true}
}, {
    derivedFarmId = 7,
    connectionKey = "conn-7"
})
assertTrue(cilocOk, "CILOC intent sanitizes")
assertEqual(ciloc.farmId, 7, "server-derived farm ID")
assertEqual(ciloc.requestedLimit, 250000, "requested limit retained")
assertEqual(ciloc.ratePreference, "variable", "rate preference retained")
assertEqual(ciloc.connectionKey, "conn-7", "connection context retained")

-- Client may never assert farm identity or pricing/approval facts.
local forbiddenCases = {
    {field = "farmId", value = 99},
    {field = "annualRate", value = 0.01},
    {field = "quote", value = {}},
    {field = "decisionStatus", value = "approve"},
    {field = "creditLimit", value = 999999},
    {field = "collateralValue", value = 1000000}
}
for _, forbidden in ipairs(forbiddenCases) do
    local intent = {
        productType = AGFProductType.OPERATING_LINE,
        requestedLimit = 100000
    }
    intent[forbidden.field] = forbidden.value
    local ok, errorCode = AGFFinancialApplicationIntentService.sanitize(intent, {derivedFarmId = 1})
    assertFalse(ok, "authoritative field rejected: " .. forbidden.field)
    assertEqual(errorCode, "AUTHORITATIVE_FIELD_NOT_ALLOWED:" .. forbidden.field, "authoritative field error")
end

-- Asset finance uses the server-resolved purchase price/context, never a client price.
local equipmentOk, equipment = AGFFinancialApplicationIntentService.sanitize({
    productType = AGFProductType.EQUIPMENT_FINANCE,
    requestedDownPaymentPercent = 0.20,
    requestedTermPeriods = 60,
    paymentsPerYear = 12,
    balloonPercent = 0.15,
    ratePreference = "fixed"
}, {
    derivedFarmId = 2,
    connectionKey = "conn-2",
    purchasePrice = 500000,
    contextFingerprint = "vehicle:tractor:configA"
})
assertTrue(equipmentOk, "equipment application sanitizes")
assertEqual(equipment.purchasePrice, 500000, "server purchase price retained")
assertEqual(equipment.requestedDownPaymentPercent, 0.20, "down-payment preference retained")
assertEqual(equipment.requestedTermPeriods, 60, "requested term retained")
assertEqual(equipment.contextFingerprint, "vehicle:tractor:configA", "server context fingerprint retained")

local missingPriceOk, missingPriceError = AGFFinancialApplicationIntentService.sanitize({
    productType = AGFProductType.EQUIPMENT_FINANCE,
    requestedDownPayment = 10000
}, {
    derivedFarmId = 2,
    contextFingerprint = "vehicle:x"
})
assertFalse(missingPriceOk, "asset finance needs server price")
assertEqual(missingPriceError, "SERVER_PURCHASE_PRICE_REQUIRED", "missing server price error")

local purchaseFieldOk, purchaseFieldError = AGFFinancialApplicationIntentService.sanitize({
    productType = AGFProductType.OPERATING_LINE,
    requestedLimit = 100000,
    requestedDownPayment = 1000
}, {derivedFarmId = 1})
assertFalse(purchaseFieldOk, "revolver purchase fields rejected")
assertEqual(purchaseFieldError, "REVOLVER_PURCHASE_FIELDS_NOT_ALLOWED", "revolver field error")

local termOk, term = AGFFinancialApplicationIntentService.sanitize({
    productType = AGFProductType.TERM_LOAN,
    requestedAmount = 175000,
    requestedTermPeriods = 36,
    paymentsPerYear = 4,
    ratePreference = "either"
}, {derivedFarmId = 3})
assertTrue(termOk, "general term intent sanitizes")
assertEqual(term.requestedAmount, 175000, "term amount retained")
assertEqual(term.paymentsPerYear, 4, "quarterly preference retained")

local badFrequencyOk, badFrequencyError = AGFFinancialApplicationIntentService.sanitize({
    productType = AGFProductType.TERM_LOAN,
    requestedAmount = 50000,
    paymentsPerYear = 3
}, {derivedFarmId = 3})
assertFalse(badFrequencyOk, "unsupported frequency rejected")
assertEqual(badFrequencyError, "INVALID_PAYMENT_FREQUENCY", "frequency error")

local badBalloonOk, badBalloonError = AGFFinancialApplicationIntentService.sanitize({
    productType = AGFProductType.CROP_INPUT_LINE,
    requestedLimit = 100000,
    balloonPercent = 0.20
}, {derivedFarmId = 4})
assertFalse(badBalloonOk, "revolver balloon rejected")
assertEqual(badBalloonError, "BALLOON_NOT_SUPPORTED", "balloon capability error")

local leaseOk, lease = AGFFinancialApplicationIntentService.sanitize({
    productType = AGFProductType.LAND_LEASE,
    requestedLeaseTermPeriods = 24
}, {
    derivedFarmId = 5,
    contextFingerprint = "farmland:17"
})
assertTrue(leaseOk, "land lease application sanitizes")
assertEqual(lease.requestedLeaseTermPeriods, 24, "lease term retained")

print("offline_application_intent_tests: PASS")
