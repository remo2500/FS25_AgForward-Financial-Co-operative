-- AgForward Financial Cooperative
-- Pure reservation model for pre-authorizing revolving credit before an FS25
-- purchase is committed. This service performs no cash or liability mutation.

AGFCreditReservationStatus = {
    ACTIVE = "active",
    CONSUMED = "consumed",
    RELEASED = "released",
    EXPIRED = "expired"
}

AGFCreditReservationService = {}
AGFCreditReservationService_mt = Class(AGFCreditReservationService)

function AGFCreditReservationService.new(idService)
    local self = setmetatable({}, AGFCreditReservationService_mt)
    self.idService = idService
    self.reservations = {}
    self.order = {}
    self.byLiability = {}
    return self
end

function AGFCreditReservationService:create(farmId, liabilityId, amount, purpose, contextFingerprint)
    if farmId == nil or liabilityId == nil then
        return nil, "INVALID_RESERVATION_ARGUMENTS"
    end

    local normalizedAmount = math.abs(AGFCurrency.round(tonumber(amount) or 0))
    if normalizedAmount <= 0 then
        return nil, "INVALID_RESERVATION_AMOUNT"
    end

    local reservation = {
        id = self.idService:next("RSV"),
        farmId = farmId,
        liabilityId = liabilityId,
        amount = normalizedAmount,
        purpose = purpose,
        contextFingerprint = contextFingerprint,
        status = AGFCreditReservationStatus.ACTIVE,
        createdYear = nil,
        createdPeriod = nil,
        consumedAmount = 0,
        metadata = {}
    }

    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        reservation.createdYear = g_currentMission.environment.currentYear
        reservation.createdPeriod = g_currentMission.environment.currentPeriod
    end

    return reservation, nil
end

function AGFCreditReservationService:register(reservation)
    if reservation == nil or reservation.id == nil or reservation.farmId == nil or reservation.liabilityId == nil then
        return false, "INVALID_RESERVATION"
    end
    if self.reservations[reservation.id] ~= nil then
        return false, "DUPLICATE_RESERVATION_ID"
    end

    local amount = math.abs(AGFCurrency.round(tonumber(reservation.amount) or 0))
    if amount <= 0 then
        return false, "INVALID_RESERVATION_AMOUNT"
    end

    local stored = {
        id = reservation.id,
        farmId = reservation.farmId,
        liabilityId = reservation.liabilityId,
        amount = amount,
        purpose = reservation.purpose,
        contextFingerprint = reservation.contextFingerprint,
        status = reservation.status or AGFCreditReservationStatus.ACTIVE,
        createdYear = reservation.createdYear,
        createdPeriod = reservation.createdPeriod,
        consumedAmount = AGFCurrency.round(reservation.consumedAmount or 0),
        metadata = {}
    }
    for key, value in pairs(reservation.metadata or {}) do
        stored.metadata[key] = value
    end

    self.reservations[stored.id] = stored
    table.insert(self.order, stored.id)
    self.byLiability[stored.liabilityId] = self.byLiability[stored.liabilityId] or {}
    table.insert(self.byLiability[stored.liabilityId], stored.id)
    if self.idService ~= nil then self.idService:observeId(stored.id) end
    return true, self:get(stored.id)
end

function AGFCreditReservationService:clone(reservation)
    if reservation == nil then return nil end
    local copy = {}
    for key, value in pairs(reservation) do
        if key == "metadata" then
            copy.metadata = {}
            for metadataKey, metadataValue in pairs(value or {}) do
                copy.metadata[metadataKey] = metadataValue
            end
        else
            copy[key] = value
        end
    end
    return copy
end

function AGFCreditReservationService:get(id)
    return self:clone(self.reservations[id])
end

function AGFCreditReservationService:getActiveForLiability(liabilityId)
    local result = {}
    for _, id in ipairs(self.byLiability[liabilityId] or {}) do
        local reservation = self.reservations[id]
        if reservation ~= nil and reservation.status == AGFCreditReservationStatus.ACTIVE then
            table.insert(result, self:clone(reservation))
        end
    end
    return result
end

function AGFCreditReservationService:getReservedAmount(liabilityId)
    local total = 0
    for _, reservation in ipairs(self:getActiveForLiability(liabilityId)) do
        total = AGFCurrency.round(total + reservation.amount)
    end
    return total
end

function AGFCreditReservationService:getEffectiveAvailableCredit(liability)
    if liability == nil or liability.id == nil or liability.getAvailableCredit == nil then
        return 0
    end
    local available = liability:getAvailableCredit()
    local reserved = self:getReservedAmount(liability.id)
    return math.max(0, AGFCurrency.round(available - reserved))
end

function AGFCreditReservationService:reserveAgainstLiability(liability, farmId, amount, purpose, contextFingerprint)
    if liability == nil or liability.id == nil then
        return false, "UNKNOWN_LIABILITY"
    end
    if farmId ~= nil and liability.farmId ~= farmId then
        return false, "LIABILITY_FARM_MISMATCH"
    end
    if not liability:isRevolving() then
        return false, "LIABILITY_NOT_REVOLVING"
    end
    if liability.status ~= nil and AGFLiabilityStatus ~= nil and liability.status ~= AGFLiabilityStatus.ACTIVE then
        return false, "LIABILITY_NOT_ACTIVE"
    end

    local requested = math.abs(AGFCurrency.round(tonumber(amount) or 0))
    if requested <= 0 then
        return false, "INVALID_RESERVATION_AMOUNT"
    end
    local available = self:getEffectiveAvailableCredit(liability)
    if AGFCurrency.toMinorUnits(requested) > AGFCurrency.toMinorUnits(available) then
        return false, "CREDIT_LIMIT_EXCEEDED_BY_RESERVATIONS"
    end

    local reservation, createError = self:create(farmId, liability.id, requested, purpose, contextFingerprint)
    if reservation == nil then return false, createError end
    local registered, resultOrError = self:register(reservation)
    if not registered then return false, resultOrError end
    return true, resultOrError
end

function AGFCreditReservationService:consume(id, amount)
    local reservation = self.reservations[id]
    if reservation == nil then return false, "UNKNOWN_RESERVATION" end
    if reservation.status ~= AGFCreditReservationStatus.ACTIVE then return false, "RESERVATION_NOT_ACTIVE" end

    local consumeAmount = amount == nil and reservation.amount or math.abs(AGFCurrency.round(tonumber(amount) or 0))
    if consumeAmount <= 0 then return false, "INVALID_CONSUME_AMOUNT" end
    if AGFCurrency.toMinorUnits(consumeAmount) > AGFCurrency.toMinorUnits(reservation.amount) then
        return false, "CONSUME_EXCEEDS_RESERVATION"
    end

    reservation.consumedAmount = consumeAmount
    reservation.status = AGFCreditReservationStatus.CONSUMED
    return true, self:get(id)
end

function AGFCreditReservationService:release(id, status)
    local reservation = self.reservations[id]
    if reservation == nil then return false, "UNKNOWN_RESERVATION" end
    if reservation.status ~= AGFCreditReservationStatus.ACTIVE then return false, "RESERVATION_NOT_ACTIVE" end
    reservation.status = status or AGFCreditReservationStatus.RELEASED
    return true, self:get(id)
end

function AGFCreditReservationService:expireAll(predicate)
    local expired = 0
    for _, id in ipairs(self.order) do
        local reservation = self.reservations[id]
        if reservation ~= nil and reservation.status == AGFCreditReservationStatus.ACTIVE then
            local shouldExpire = predicate == nil or predicate(self:clone(reservation)) == true
            if shouldExpire then
                reservation.status = AGFCreditReservationStatus.EXPIRED
                expired = expired + 1
            end
        end
    end
    return expired
end
