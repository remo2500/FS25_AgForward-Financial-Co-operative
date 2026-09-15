-- AgForward Financial Cooperative
-- Authoritative registry for all native AgForward liabilities.

AGFLiabilityRegistry = {}
AGFLiabilityRegistry_mt = Class(AGFLiabilityRegistry)

function AGFLiabilityRegistry.new(idService)
    local self = setmetatable({}, AGFLiabilityRegistry_mt)
    self.idService = idService
    self.liabilities = {}
    self.order = {}
    self.byFarm = {}
    self.byProduct = {}
    return self
end

function AGFLiabilityRegistry:reset()
    self.liabilities = {}
    self.order = {}
    self.byFarm = {}
    self.byProduct = {}
end

function AGFLiabilityRegistry:create(farmId, productType, displayName)
    if farmId == nil or productType == nil then
        return nil, "INVALID_LIABILITY_ARGUMENTS"
    end

    local liability = AGFLiability.new(self.idService:next("LIAB"), farmId, productType)
    liability.displayName = displayName

    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        liability.startYear = g_currentMission.environment.currentYear
        liability.startPeriod = g_currentMission.environment.currentPeriod
    end

    return liability, nil
end

function AGFLiabilityRegistry:register(liability)
    if liability == nil or liability.id == nil or liability.farmId == nil or liability.productType == nil then
        return false, "INVALID_LIABILITY"
    end

    if self.liabilities[liability.id] ~= nil then
        return false, "DUPLICATE_LIABILITY_ID"
    end

    self.liabilities[liability.id] = liability
    table.insert(self.order, liability.id)

    self.byFarm[liability.farmId] = self.byFarm[liability.farmId] or {}
    table.insert(self.byFarm[liability.farmId], liability.id)

    self.byProduct[liability.productType] = self.byProduct[liability.productType] or {}
    table.insert(self.byProduct[liability.productType], liability.id)

    self.idService:observeId(liability.id)
    return true, nil
end

function AGFLiabilityRegistry:get(id)
    return self.liabilities[id]
end

function AGFLiabilityRegistry:getAll()
    local result = {}
    for _, id in ipairs(self.order) do
        local liability = self.liabilities[id]
        if liability ~= nil then
            table.insert(result, liability)
        end
    end
    return result
end

function AGFLiabilityRegistry:getFarmLiabilities(farmId, includeClosed)
    local result = {}
    for _, id in ipairs(self.byFarm[farmId] or {}) do
        local liability = self.liabilities[id]
        if liability ~= nil and (includeClosed or liability:isOpen()) then
            table.insert(result, liability)
        end
    end
    return result
end

function AGFLiabilityRegistry:getFarmProductLiabilities(farmId, productType, includeClosed)
    local result = {}
    for _, liability in ipairs(self:getFarmLiabilities(farmId, includeClosed)) do
        if liability.productType == productType then
            table.insert(result, liability)
        end
    end
    return result
end

function AGFLiabilityRegistry:getTotalOutstanding(farmId)
    local total = 0
    for _, liability in ipairs(self:getFarmLiabilities(farmId, false)) do
        total = total + liability:getOutstandingBalance()
    end
    return total
end

function AGFLiabilityRegistry:canDraw(liabilityId, farmId, amount, expectedProductType)
    amount = math.abs(tonumber(amount) or 0)
    if amount <= 0 then
        return false, "INVALID_AMOUNT"
    end

    local liability = self:get(liabilityId)
    if liability == nil then
        return false, "UNKNOWN_LIABILITY"
    end

    if farmId ~= nil and liability.farmId ~= farmId then
        return false, "LIABILITY_FARM_MISMATCH"
    end

    if expectedProductType ~= nil and liability.productType ~= expectedProductType then
        return false, "WRONG_PRODUCT_TYPE"
    end

    if not liability:isOpen() or liability.status ~= AGFLiabilityStatus.ACTIVE then
        return false, "LIABILITY_NOT_ACTIVE"
    end

    if not liability:isRevolving() then
        return false, "LIABILITY_NOT_REVOLVING"
    end

    if amount > liability:getAvailableCredit() + 0.005 then
        return false, "CREDIT_LIMIT_EXCEEDED"
    end

    return true, liability
end

function AGFLiabilityRegistry:applyDraw(liabilityId, amount)
    amount = math.abs(tonumber(amount) or 0)
    local liability = self:get(liabilityId)
    if liability == nil then
        return false, "UNKNOWN_LIABILITY"
    end

    local canDraw, result = self:canDraw(liabilityId, liability.farmId, amount)
    if not canDraw then
        return false, result
    end

    liability.principalBalance = liability.principalBalance + amount
    return true, liability
end

function AGFLiabilityRegistry:applyPrincipalPayment(liabilityId, amount)
    amount = math.abs(tonumber(amount) or 0)
    if amount <= 0 then
        return false, "INVALID_AMOUNT"
    end

    local liability = self:get(liabilityId)
    if liability == nil then
        return false, "UNKNOWN_LIABILITY"
    end

    local applied = math.min(amount, math.max(0, liability.principalBalance))
    liability.principalBalance = math.max(0, liability.principalBalance - applied)
    return true, applied
end

function AGFLiabilityRegistry:saveToXMLFile(xmlFile, key)
    setXMLInt(xmlFile, key .. "#count", #self.order)

    local writeIndex = 0
    for _, id in ipairs(self.order) do
        local liability = self.liabilities[id]
        if liability ~= nil then
            local liabilityKey = string.format("%s.liability(%d)", key, writeIndex)
            liability:saveToXMLFile(xmlFile, liabilityKey)
            writeIndex = writeIndex + 1
        end
    end
end

function AGFLiabilityRegistry:loadFromXMLFile(xmlFile, key)
    self:reset()

    local index = 0
    while true do
        local liabilityKey = string.format("%s.liability(%d)", key, index)
        if not hasXMLProperty(xmlFile, liabilityKey .. "#id") then
            break
        end

        local liability = AGFLiability.loadFromXMLFile(xmlFile, liabilityKey)
        if liability ~= nil then
            local registered, errorCode = self:register(liability)
            if not registered then
                print(string.format(
                    "Warning: AgForward skipped saved liability '%s' (%s)",
                    tostring(liability.id),
                    tostring(errorCode)
                ))
            end
        end

        index = index + 1
    end

    return #self.order
end
