-- AgForward Financial Cooperative
-- Authoritative registry for all native AgForward liabilities.

AGFLiabilityRegistry = {}
AGFLiabilityRegistry_mt = Class(AGFLiabilityRegistry)

function AGFLiabilityRegistry.new(idService, runtimeState)
    local self = setmetatable({}, AGFLiabilityRegistry_mt)
    self.idService = idService
    self.runtimeState = runtimeState
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

function AGFLiabilityRegistry:checkMutationAllowed(internal)
    if internal then return true, nil end
    if self.runtimeState == nil then return false, "RUNTIME_STATE_UNAVAILABLE" end
    return self.runtimeState:canMutate()
end

function AGFLiabilityRegistry:create(farmId, productType, displayName)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return nil, errorCode end
    if farmId == nil or productType == nil then
        return nil, "INVALID_LIABILITY_ARGUMENTS"
    end

    local liability = AGFLiability.new(self.idService:next("LIAB"), farmId, productType)
    liability.displayName = displayName

    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        liability.startYear = g_currentMission.environment.currentYear
        liability.startPeriod = g_currentMission.environment.currentPeriod
    end

    -- Returned record is a mutable draft. register() clones it into authoritative
    -- storage so the caller cannot mutate a registered liability through this handle.
    return liability, nil
end

function AGFLiabilityRegistry:register(liability, internal)
    local allowed, errorCode = self:checkMutationAllowed(internal)
    if not allowed then return false, errorCode end
    if liability == nil or liability.id == nil or liability.farmId == nil or liability.productType == nil then
        return false, "INVALID_LIABILITY"
    end
    if self.liabilities[liability.id] ~= nil then
        return false, "DUPLICATE_LIABILITY_ID"
    end

    local stored = liability:clone()
    self.liabilities[stored.id] = stored
    table.insert(self.order, stored.id)

    self.byFarm[stored.farmId] = self.byFarm[stored.farmId] or {}
    table.insert(self.byFarm[stored.farmId], stored.id)

    self.byProduct[stored.productType] = self.byProduct[stored.productType] or {}
    table.insert(self.byProduct[stored.productType], stored.id)

    self.idService:observeId(stored.id)
    return true, stored:clone()
end

function AGFLiabilityRegistry:getInternal(id)
    return self.liabilities[id]
end

function AGFLiabilityRegistry:get(id)
    local liability = self.liabilities[id]
    return liability ~= nil and liability:clone() or nil
end

function AGFLiabilityRegistry:getAllInternal()
    local result = {}
    for _, id in ipairs(self.order) do
        local liability = self.liabilities[id]
        if liability ~= nil then table.insert(result, liability) end
    end
    return result
end

function AGFLiabilityRegistry:getAll()
    local result = {}
    for _, liability in ipairs(self:getAllInternal()) do
        table.insert(result, liability:clone())
    end
    return result
end

function AGFLiabilityRegistry:getFarmLiabilities(farmId, includeClosed)
    local result = {}
    for _, id in ipairs(self.byFarm[farmId] or {}) do
        local liability = self.liabilities[id]
        if liability ~= nil and (includeClosed or liability:isOpen()) then
            table.insert(result, liability:clone())
        end
    end
    return result
end

function AGFLiabilityRegistry:getFarmProductLiabilities(farmId, productType, includeClosed)
    local result = {}
    for _, liability in ipairs(self:getFarmLiabilities(farmId, includeClosed)) do
        if liability.productType == productType then table.insert(result, liability) end
    end
    return result
end

function AGFLiabilityRegistry:getTotalOutstanding(farmId)
    local total = 0
    for _, id in ipairs(self.byFarm[farmId] or {}) do
        local liability = self.liabilities[id]
        if liability ~= nil and liability:isOpen() then
            total = total + liability:getOutstandingBalance()
        end
    end
    return AGFCurrency.round(total)
end

function AGFLiabilityRegistry:canDraw(liabilityId, farmId, amount, expectedProductType)
    amount = math.abs(AGFCurrency.round(amount or 0))
    if amount <= 0 then return false, "INVALID_AMOUNT" end

    local liability = self:getInternal(liabilityId)
    if liability == nil then return false, "UNKNOWN_LIABILITY" end
    if farmId ~= nil and liability.farmId ~= farmId then return false, "LIABILITY_FARM_MISMATCH" end
    if expectedProductType ~= nil and liability.productType ~= expectedProductType then return false, "WRONG_PRODUCT_TYPE" end
    if not liability:isOpen() or liability.status ~= AGFLiabilityStatus.ACTIVE then return false, "LIABILITY_NOT_ACTIVE" end
    if not liability:isRevolving() then return false, "LIABILITY_NOT_REVOLVING" end
    if AGFCurrency.toMinorUnits(amount) > AGFCurrency.toMinorUnits(liability:getAvailableCredit()) then
        return false, "CREDIT_LIMIT_EXCEEDED"
    end

    return true, liability:clone()
end

-- Public balance changes are deliberately blocked. Every debt mutation must be
-- journaled by the financial operation coordinator before using an internal
-- committed mutation below.
function AGFLiabilityRegistry:applyDraw(liabilityId, amount)
    return false, "OPERATION_COORDINATOR_REQUIRED"
end

function AGFLiabilityRegistry:applyPrincipalPayment(liabilityId, amount)
    return false, "OPERATION_COORDINATOR_REQUIRED"
end

function AGFLiabilityRegistry:applyDrawCommitted(liabilityId, amount, internal)
    local allowed, errorCode = self:checkMutationAllowed(internal)
    if not allowed then return false, errorCode end

    local liability = self:getInternal(liabilityId)
    if liability == nil then return false, "UNKNOWN_LIABILITY" end
    amount = math.abs(AGFCurrency.round(amount or 0))
    if amount <= 0 then return false, "INVALID_AMOUNT" end

    -- Recheck the core revolver invariants at the actual mutation boundary.
    -- The coordinator performs preflight validation, but committed mutations
    -- must remain safe if a future multiplayer/request path changes state
    -- between preflight and commit or accidentally calls this API directly.
    if not liability:isOpen() or liability.status ~= AGFLiabilityStatus.ACTIVE then
        return false, "LIABILITY_NOT_ACTIVE"
    end
    if not liability:isRevolving() then
        return false, "LIABILITY_NOT_REVOLVING"
    end
    if AGFCurrency.toMinorUnits(amount) > AGFCurrency.toMinorUnits(liability:getAvailableCredit()) then
        return false, "CREDIT_LIMIT_EXCEEDED"
    end

    liability.principalBalance = AGFCurrency.round((liability.principalBalance or 0) + amount)
    return true, liability:clone()
end

function AGFLiabilityRegistry:revertDrawCommitted(liabilityId, amount, internal)
    local allowed, errorCode = self:checkMutationAllowed(internal)
    if not allowed then return false, errorCode end

    local liability = self:getInternal(liabilityId)
    if liability == nil then return false, "UNKNOWN_LIABILITY" end
    amount = math.abs(AGFCurrency.round(amount or 0))
    liability.principalBalance = math.max(0, AGFCurrency.round((liability.principalBalance or 0) - amount))
    return true, liability:clone()
end

function AGFLiabilityRegistry:applyPrincipalPaymentCommitted(liabilityId, amount, internal)
    local allowed, errorCode = self:checkMutationAllowed(internal)
    if not allowed then return false, errorCode end

    amount = math.abs(AGFCurrency.round(amount or 0))
    if amount <= 0 then return false, "INVALID_AMOUNT" end
    local liability = self:getInternal(liabilityId)
    if liability == nil then return false, "UNKNOWN_LIABILITY" end

    local applied = AGFCurrency.round(math.min(amount, math.max(0, liability.principalBalance)))
    liability.principalBalance = math.max(0, AGFCurrency.round(liability.principalBalance - applied))
    return true, applied, liability:clone()
end

function AGFLiabilityRegistry:revertPrincipalPaymentCommitted(liabilityId, amount, internal)
    local allowed, errorCode = self:checkMutationAllowed(internal)
    if not allowed then return false, errorCode end

    amount = math.abs(AGFCurrency.round(amount or 0))
    if amount <= 0 then return false, "INVALID_AMOUNT" end
    local liability = self:getInternal(liabilityId)
    if liability == nil then return false, "UNKNOWN_LIABILITY" end

    liability.principalBalance = AGFCurrency.round((liability.principalBalance or 0) + amount)
    return true, liability:clone()
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
    local errors = {}

    while true do
        local liabilityKey = string.format("%s.liability(%d)", key, index)
        if not hasXMLProperty(xmlFile, liabilityKey .. "#id") then break end

        local liability = AGFLiability.loadFromXMLFile(xmlFile, liabilityKey)
        if liability ~= nil then
            local registered, errorCode = self:register(liability, true)
            if not registered then
                table.insert(errors, string.format("%s:%s", tostring(liability.id), tostring(errorCode)))
            end
        end
        index = index + 1
    end

    return #self.order, errors
end
