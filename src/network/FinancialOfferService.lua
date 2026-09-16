-- AgForward Financial Cooperative
-- Ephemeral server-side offer registry for future dealer/construction/land/UI
-- workflows. Clients should accept an offer ID; they must not supply authoritative
-- APR/payment/credit terms back to the server.
--
-- Offers are deliberately not savegame authority. A reload/reconnect can request
-- a fresh quote against the current financial state and policy.

AGFFinancialOfferStatus = {
    ACTIVE = "active",
    CONSUMED = "consumed",
    CANCELLED = "cancelled",
    EXPIRED = "expired"
}

AGFFinancialOfferService = {}
AGFFinancialOfferService_mt = Class(AGFFinancialOfferService)

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function normalizeNonNegativeInteger(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number < 0 or number ~= math.floor(number) then return nil end
    return number
end

local function normalizePositiveInteger(value)
    local number = normalizeNonNegativeInteger(value)
    if number == nil or number <= 0 then return nil end
    return number
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(item, seen)
    end
    return copy
end

local function periodOrdinal(year, period)
    local normalizedYear = normalizePositiveInteger(year)
    local normalizedPeriod = normalizePositiveInteger(period)
    if normalizedYear == nil or normalizedPeriod == nil or normalizedPeriod > 12 then return nil end
    return normalizedYear * 12 + (normalizedPeriod - 1)
end

function AGFFinancialOfferService.new(idService, maxActiveOffers)
    local self = setmetatable({}, AGFFinancialOfferService_mt)
    self.idService = idService
    self.maxActiveOffers = math.max(16, math.floor(tonumber(maxActiveOffers) or 128))
    self.offers = {}
    self.order = {}
    return self
end

function AGFFinancialOfferService:clone(offer)
    return deepCopy(offer)
end

function AGFFinancialOfferService:get(id)
    if id == nil then return nil end
    return self:clone(self.offers[tostring(id)])
end

function AGFFinancialOfferService:getActiveCount()
    local count = 0
    for _, id in ipairs(self.order) do
        local offer = self.offers[id]
        if offer ~= nil and offer.status == AGFFinancialOfferStatus.ACTIVE then count = count + 1 end
    end
    return count
end

function AGFFinancialOfferService:create(parameters)
    parameters = parameters or {}
    if self.idService == nil then return false, "ID_SERVICE_UNAVAILABLE" end
    if parameters.connectionKey == nil or parameters.connectionKey == "" then return false, "OFFER_CONNECTION_REQUIRED" end

    local farmId = normalizePositiveInteger(parameters.farmId)
    if farmId == nil then return false, "INVALID_OFFER_FARM" end
    if parameters.productType == nil or parameters.productType == "" then return false, "OFFER_PRODUCT_REQUIRED" end
    if type(parameters.quote) ~= "table" then return false, "OFFER_QUOTE_REQUIRED" end

    local revision = normalizeNonNegativeInteger(parameters.stateRevision)
    if revision == nil then return false, "INVALID_OFFER_REVISION" end

    local expiresOrdinal = nil
    if parameters.expiresYear ~= nil or parameters.expiresPeriod ~= nil then
        expiresOrdinal = periodOrdinal(parameters.expiresYear, parameters.expiresPeriod)
        if expiresOrdinal == nil then return false, "INVALID_OFFER_EXPIRY" end
    end

    -- Avoid an unbounded session cache. Only terminal offers are evicted; if all
    -- slots are still active, force the caller to expire/cancel instead of
    -- silently discarding an offer a player may be viewing.
    self:trimTerminalOffers()
    if self:getActiveCount() >= self.maxActiveOffers then
        return false, "TOO_MANY_ACTIVE_OFFERS"
    end

    local offerId = self.idService:next("OFFER")
    local offer = {
        id = offerId,
        connectionKey = tostring(parameters.connectionKey),
        farmId = farmId,
        productType = parameters.productType,
        stateRevision = revision,
        quote = deepCopy(parameters.quote),
        decisionStatus = parameters.decisionStatus,
        policyVersion = parameters.policyVersion,
        pricingVersion = parameters.pricingVersion,
        contextFingerprint = parameters.contextFingerprint,
        createdYear = normalizePositiveInteger(parameters.createdYear),
        createdPeriod = normalizePositiveInteger(parameters.createdPeriod),
        expiresYear = normalizePositiveInteger(parameters.expiresYear),
        expiresPeriod = normalizePositiveInteger(parameters.expiresPeriod),
        expiresOrdinal = expiresOrdinal,
        status = AGFFinancialOfferStatus.ACTIVE,
        metadata = deepCopy(parameters.metadata or {})
    }

    self.offers[offerId] = offer
    table.insert(self.order, offerId)
    return true, self:get(offerId)
end

function AGFFinancialOfferService:isExpired(offer, currentYear, currentPeriod)
    if offer == nil or offer.expiresOrdinal == nil then return false end
    local current = periodOrdinal(currentYear, currentPeriod)
    if current == nil then return nil, "INVALID_CURRENT_PERIOD" end
    return current > offer.expiresOrdinal, nil
end

function AGFFinancialOfferService:validateForAcceptance(id, connectionKey, farmId, currentRevision, context)
    context = context or {}
    local offer = self.offers[tostring(id or "")]
    if offer == nil then return false, "UNKNOWN_OFFER" end
    if offer.status ~= AGFFinancialOfferStatus.ACTIVE then return false, "OFFER_NOT_ACTIVE" end
    if tostring(connectionKey or "") ~= offer.connectionKey then return false, "OFFER_CONNECTION_MISMATCH" end

    local normalizedFarm = normalizePositiveInteger(farmId)
    if normalizedFarm == nil or normalizedFarm ~= offer.farmId then return false, "OFFER_FARM_MISMATCH" end

    local revision = normalizeNonNegativeInteger(currentRevision)
    if revision == nil then return false, "INVALID_CURRENT_REVISION" end
    if revision ~= offer.stateRevision then return false, "OFFER_STATE_STALE" end

    if context.expectedProductType ~= nil and context.expectedProductType ~= offer.productType then
        return false, "OFFER_PRODUCT_MISMATCH"
    end
    if context.contextFingerprint ~= nil and tostring(context.contextFingerprint) ~= tostring(offer.contextFingerprint) then
        return false, "OFFER_CONTEXT_MISMATCH"
    end

    if offer.expiresOrdinal ~= nil then
        local expired, expiryError = self:isExpired(offer, context.currentYear, context.currentPeriod)
        if expired == nil then return false, expiryError end
        if expired then
            offer.status = AGFFinancialOfferStatus.EXPIRED
            return false, "OFFER_EXPIRED"
        end
    end

    return true, self:get(offer.id)
end

function AGFFinancialOfferService:consume(id, connectionKey, farmId, currentRevision, context)
    local valid, offerOrError = self:validateForAcceptance(id, connectionKey, farmId, currentRevision, context)
    if not valid then return false, offerOrError end

    local offer = self.offers[tostring(id)]
    offer.status = AGFFinancialOfferStatus.CONSUMED
    return true, self:get(offer.id)
end

function AGFFinancialOfferService:cancel(id, connectionKey)
    local offer = self.offers[tostring(id or "")]
    if offer == nil then return false, "UNKNOWN_OFFER" end
    if offer.status ~= AGFFinancialOfferStatus.ACTIVE then return false, "OFFER_NOT_ACTIVE" end
    if connectionKey ~= nil and tostring(connectionKey) ~= offer.connectionKey then
        return false, "OFFER_CONNECTION_MISMATCH"
    end
    offer.status = AGFFinancialOfferStatus.CANCELLED
    return true, self:get(offer.id)
end

function AGFFinancialOfferService:expireThrough(currentYear, currentPeriod)
    local current = periodOrdinal(currentYear, currentPeriod)
    if current == nil then return false, "INVALID_CURRENT_PERIOD" end

    local expiredCount = 0
    for _, id in ipairs(self.order) do
        local offer = self.offers[id]
        if offer ~= nil and offer.status == AGFFinancialOfferStatus.ACTIVE
            and offer.expiresOrdinal ~= nil and current > offer.expiresOrdinal then
            offer.status = AGFFinancialOfferStatus.EXPIRED
            expiredCount = expiredCount + 1
        end
    end
    return true, expiredCount
end

function AGFFinancialOfferService:trimTerminalOffers()
    while #self.order > self.maxActiveOffers * 2 do
        local removed = false
        for index, id in ipairs(self.order) do
            local offer = self.offers[id]
            if offer == nil or offer.status ~= AGFFinancialOfferStatus.ACTIVE then
                self.offers[id] = nil
                table.remove(self.order, index)
                removed = true
                break
            end
        end
        if not removed then break end
    end
end

function AGFFinancialOfferService:reset()
    self.offers = {}
    self.order = {}
end
