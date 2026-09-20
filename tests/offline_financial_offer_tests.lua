-- Offline validation for ephemeral server-authoritative loan/finance offers.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/IdService.lua")
dofile("src/network/FinancialOfferService.lua")

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

local ids = AGFIdService.new()
local offers = AGFFinancialOfferService.new(ids, 16)

local authoritativeQuote = {
    principal = 200000,
    quotedRegularPayment = 3950.25,
    pricing = {annualRate = 0.065},
    amortization = {periods = 60}
}

local createdOk, created = offers:create({
    connectionKey = "conn-1",
    farmId = 1,
    productType = "equipmentFinance",
    stateRevision = 10,
    quote = authoritativeQuote,
    decisionStatus = "approve",
    policyVersion = 3,
    pricingVersion = 2,
    contextFingerprint = "dealer:tractor:config-A",
    createdYear = 2026,
    createdPeriod = 9,
    expiresYear = 2026,
    expiresPeriod = 10,
    metadata = {storeItem = "tractorA", nested = {serverPriced = true}}
})
assertTrue(createdOk, "offer created")
assertTrue(created.id ~= nil, "offer receives server ID")
assertEqual(created.status, AGFFinancialOfferStatus.ACTIVE, "new offer active")
assertEqual(created.stateRevision, 10, "offer bound to state revision")
assertEqual(created.quote.principal, 200000, "offer quote snapshot")
assertEqual(offers:getActiveCount(), 1, "one active offer")

-- Caller-owned quote and returned copies cannot rewrite the server offer.
authoritativeQuote.principal = 999999
authoritativeQuote.pricing.annualRate = 0.99
created.quote.principal = 888888
created.metadata.nested.serverPriced = false
local stored = offers:get(created.id)
assertEqual(stored.quote.principal, 200000, "server quote immune to caller mutation")
assertEqual(stored.quote.pricing.annualRate, 0.065, "nested quote deep copied")
assertTrue(stored.metadata.nested.serverPriced, "metadata deep copied")
stored.quote.principal = 777777
assertEqual(offers:get(created.id).quote.principal, 200000, "get returns defensive copy")

-- Acceptance is bound to connection, farm, product context, fingerprint, revision, and expiry.
local wrongConnectionOk, wrongConnectionError = offers:validateForAcceptance(created.id, "conn-2", 1, 10, {
    expectedProductType = "equipmentFinance",
    contextFingerprint = "dealer:tractor:config-A",
    currentYear = 2026,
    currentPeriod = 9
})
assertFalse(wrongConnectionOk, "offer cannot cross connections")
assertEqual(wrongConnectionError, "OFFER_CONNECTION_MISMATCH", "connection mismatch error")

local wrongFarmOk, wrongFarmError = offers:validateForAcceptance(created.id, "conn-1", 2, 10, {
    expectedProductType = "equipmentFinance",
    contextFingerprint = "dealer:tractor:config-A",
    currentYear = 2026,
    currentPeriod = 9
})
assertFalse(wrongFarmOk, "offer cannot cross farms")
assertEqual(wrongFarmError, "OFFER_FARM_MISMATCH", "farm mismatch error")

local staleOk, staleError = offers:validateForAcceptance(created.id, "conn-1", 1, 11, {
    expectedProductType = "equipmentFinance",
    contextFingerprint = "dealer:tractor:config-A",
    currentYear = 2026,
    currentPeriod = 9
})
assertFalse(staleOk, "state change invalidates old offer")
assertEqual(staleError, "OFFER_STATE_STALE", "stale offer error")

local wrongProductOk, wrongProductError = offers:validateForAcceptance(created.id, "conn-1", 1, 10, {
    expectedProductType = "landFinance",
    contextFingerprint = "dealer:tractor:config-A",
    currentYear = 2026,
    currentPeriod = 9
})
assertFalse(wrongProductOk, "offer product mismatch rejected")
assertEqual(wrongProductError, "OFFER_PRODUCT_MISMATCH", "product mismatch error")

local wrongContextOk, wrongContextError = offers:validateForAcceptance(created.id, "conn-1", 1, 10, {
    expectedProductType = "equipmentFinance",
    contextFingerprint = "dealer:tractor:config-B",
    currentYear = 2026,
    currentPeriod = 9
})
assertFalse(wrongContextOk, "changed purchase context rejected")
assertEqual(wrongContextError, "OFFER_CONTEXT_MISMATCH", "context mismatch error")

local validOk, validOffer = offers:validateForAcceptance(created.id, "conn-1", 1, 10, {
    expectedProductType = "equipmentFinance",
    contextFingerprint = "dealer:tractor:config-A",
    currentYear = 2026,
    currentPeriod = 10
})
assertTrue(validOk, "offer valid through expiry period")
assertEqual(validOffer.id, created.id, "validated offer returned")

-- Consumption is one-time; client replay cannot finance the asset twice.
local consumeOk, consumed = offers:consume(created.id, "conn-1", 1, 10, {
    expectedProductType = "equipmentFinance",
    contextFingerprint = "dealer:tractor:config-A",
    currentYear = 2026,
    currentPeriod = 10
})
assertTrue(consumeOk, "offer consumed")
assertEqual(consumed.status, AGFFinancialOfferStatus.CONSUMED, "consumed status")
assertEqual(offers:getActiveCount(), 0, "consumed offer no longer active")
local replayOk, replayError = offers:consume(created.id, "conn-1", 1, 10, {
    currentYear = 2026,
    currentPeriod = 10
})
assertFalse(replayOk, "consumed offer cannot be replayed")
assertEqual(replayError, "OFFER_NOT_ACTIVE", "consumed offer replay error")

-- Expiration changes state only when current period moves beyond valid-through period.
local expiringOk, expiring = offers:create({
    connectionKey = "conn-1",
    farmId = 1,
    productType = "landFinance",
    stateRevision = 20,
    quote = {principal = 500000},
    expiresYear = 2026,
    expiresPeriod = 12
})
assertTrue(expiringOk, "expiring offer created")
local throughExpiryOk = offers:validateForAcceptance(expiring.id, "conn-1", 1, 20, {
    currentYear = 2026,
    currentPeriod = 12
})
assertTrue(throughExpiryOk, "offer remains valid through expiry period")
local expiredOk, expiredError = offers:validateForAcceptance(expiring.id, "conn-1", 1, 20, {
    currentYear = 2027,
    currentPeriod = 1
})
assertFalse(expiredOk, "offer expires next period")
assertEqual(expiredError, "OFFER_EXPIRED", "offer expiry error")
assertEqual(offers:get(expiring.id).status, AGFFinancialOfferStatus.EXPIRED, "expired status persisted in session")

-- Bulk expiry is deterministic and does not affect undated offers.
local datedOk, dated = offers:create({
    connectionKey = "conn-1",
    farmId = 1,
    productType = "projectFinance",
    stateRevision = 30,
    quote = {principal = 300000},
    expiresYear = 2027,
    expiresPeriod = 3
})
assertTrue(datedOk, "dated offer created")
local undatedOk, undated = offers:create({
    connectionKey = "conn-1",
    farmId = 1,
    productType = "operatingLine",
    stateRevision = 30,
    quote = {creditLimit = 100000}
})
assertTrue(undatedOk, "undated offer created")
local expireOk, expiredCount = offers:expireThrough(2027, 4)
assertTrue(expireOk, "bulk expiry succeeds")
assertEqual(expiredCount, 1, "one active dated offer expired")
assertEqual(offers:get(dated.id).status, AGFFinancialOfferStatus.EXPIRED, "bulk expired dated offer")
assertEqual(offers:get(undated.id).status, AGFFinancialOfferStatus.ACTIVE, "undated offer remains active")

-- Cancellation is owner-connection scoped.
local wrongCancelOk, wrongCancelError = offers:cancel(undated.id, "conn-2")
assertFalse(wrongCancelOk, "wrong connection cannot cancel")
assertEqual(wrongCancelError, "OFFER_CONNECTION_MISMATCH", "cancel connection mismatch")
local cancelOk, cancelled = offers:cancel(undated.id, "conn-1")
assertTrue(cancelOk, "owner connection cancels")
assertEqual(cancelled.status, AGFFinancialOfferStatus.CANCELLED, "cancelled status")

-- Validation rejects malformed offers rather than creating client-exploitable partial state.
local noConnectionOk, noConnectionError = offers:create({farmId = 1, productType = "termLoan", stateRevision = 1, quote = {}})
assertFalse(noConnectionOk, "missing connection rejected")
assertEqual(noConnectionError, "OFFER_CONNECTION_REQUIRED", "missing connection error")
local badFarmOk, badFarmError = offers:create({connectionKey = "conn", farmId = 0, productType = "termLoan", stateRevision = 1, quote = {}})
assertFalse(badFarmOk, "invalid farm rejected")
assertEqual(badFarmError, "INVALID_OFFER_FARM", "invalid farm error")
local noProductOk, noProductError = offers:create({connectionKey = "conn", farmId = 1, stateRevision = 1, quote = {}})
assertFalse(noProductOk, "missing product rejected")
assertEqual(noProductError, "OFFER_PRODUCT_REQUIRED", "missing product error")
local noQuoteOk, noQuoteError = offers:create({connectionKey = "conn", farmId = 1, productType = "termLoan", stateRevision = 1})
assertFalse(noQuoteOk, "missing quote rejected")
assertEqual(noQuoteError, "OFFER_QUOTE_REQUIRED", "missing quote error")
local badRevisionOk, badRevisionError = offers:create({connectionKey = "conn", farmId = 1, productType = "termLoan", stateRevision = -1, quote = {}})
assertFalse(badRevisionOk, "invalid revision rejected")
assertEqual(badRevisionError, "INVALID_OFFER_REVISION", "invalid revision error")
local badExpiryOk, badExpiryError = offers:create({connectionKey = "conn", farmId = 1, productType = "termLoan", stateRevision = 1, quote = {}, expiresYear = 2026, expiresPeriod = 13})
assertFalse(badExpiryOk, "invalid expiry rejected")
assertEqual(badExpiryError, "INVALID_OFFER_EXPIRY", "invalid expiry error")

-- Active-offer cap refuses silent eviction of offers players may still be reviewing.
local capped = AGFFinancialOfferService.new(ids, 16)
for index = 1, 16 do
    local capOk = capped:create({
        connectionKey = "cap-conn",
        farmId = 1,
        productType = "termLoan",
        stateRevision = 1,
        quote = {index = index}
    })
    assertTrue(capOk, "active cap seed offer")
end
local overflowOk, overflowError = capped:create({
    connectionKey = "cap-conn",
    farmId = 1,
    productType = "termLoan",
    stateRevision = 1,
    quote = {index = 17}
})
assertFalse(overflowOk, "active offer cap enforced")
assertEqual(overflowError, "TOO_MANY_ACTIVE_OFFERS", "active offer cap error")

capped:reset()
assertEqual(capped:getActiveCount(), 0, "offer reset clears ephemeral state")

print("offline_financial_offer_tests: PASS")
