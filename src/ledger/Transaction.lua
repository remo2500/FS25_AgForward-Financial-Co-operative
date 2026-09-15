AGFTransaction = {}
AGFTransaction_mt = Class(AGFTransaction)

local function setOptionalString(xmlFile, key, value)
    if value ~= nil and value ~= "" then
        setXMLString(xmlFile, key, tostring(value))
    end
end

function AGFTransaction.new(id, farmId, transactionType, amount)
    local self = setmetatable({}, AGFTransaction_mt)
    self.id = id
    self.groupId = nil
    self.farmId = farmId
    self.transactionType = transactionType
    self.amount = AGFCurrency.round(amount or 0)
    self.principal = 0
    self.interest = 0
    self.fees = 0
    self.expenseCategory = nil
    self.fundingSource = nil
    self.assetId = nil
    self.liabilityId = nil
    self.period = nil
    self.year = nil
    self.description = nil
    self.metadata = {}
    self._sealed = false
    return self
end

function AGFTransaction:isSealed()
    return self._sealed == true
end

function AGFTransaction:seal()
    self._sealed = true
    return self
end

function AGFTransaction:canEdit()
    return self._sealed ~= true
end

function AGFTransaction:setGroupId(groupId)
    if self:canEdit() then self.groupId = groupId end
    return self
end

function AGFTransaction:setBreakdown(principal, interest, fees)
    if self:canEdit() then
        self.principal = AGFCurrency.round(principal or 0)
        self.interest = AGFCurrency.round(interest or 0)
        self.fees = AGFCurrency.round(fees or 0)
    end
    return self
end

function AGFTransaction:setExpenseCategory(category)
    if self:canEdit() then self.expenseCategory = category end
    return self
end

function AGFTransaction:setFundingSource(source)
    if self:canEdit() then self.fundingSource = source end
    return self
end

function AGFTransaction:setAssetId(assetId)
    if self:canEdit() then self.assetId = assetId end
    return self
end

function AGFTransaction:setLiabilityId(liabilityId)
    if self:canEdit() then self.liabilityId = liabilityId end
    return self
end

function AGFTransaction:setPeriod(year, period)
    if self:canEdit() then
        self.year = year
        self.period = period
    end
    return self
end

function AGFTransaction:setDescription(description)
    if self:canEdit() then self.description = description end
    return self
end

function AGFTransaction:setMetadata(key, value)
    if self:canEdit() and key ~= nil then
        if value == nil then
            self.metadata[tostring(key)] = nil
        else
            self.metadata[tostring(key)] = tostring(value)
        end
    end
    return self
end

function AGFTransaction:clone()
    local copy = AGFTransaction.new(self.id, self.farmId, self.transactionType, self.amount)
    copy.groupId = self.groupId
    copy.principal = self.principal
    copy.interest = self.interest
    copy.fees = self.fees
    copy.expenseCategory = self.expenseCategory
    copy.fundingSource = self.fundingSource
    copy.assetId = self.assetId
    copy.liabilityId = self.liabilityId
    copy.period = self.period
    copy.year = self.year
    copy.description = self.description
    copy.metadata = {}
    for key, value in pairs(self.metadata or {}) do
        copy.metadata[key] = value
    end
    copy._sealed = self._sealed
    return copy
end

function AGFTransaction:saveToXMLFile(xmlFile, key)
    setXMLString(xmlFile, key .. "#id", tostring(self.id))
    setXMLInt(xmlFile, key .. "#farmId", tonumber(self.farmId) or 0)
    setXMLString(xmlFile, key .. "#type", tostring(self.transactionType or AGFTransactionType.ADJUSTMENT))
    setXMLFloat(xmlFile, key .. "#amount", AGFCurrency.round(self.amount or 0))
    setXMLFloat(xmlFile, key .. "#principal", AGFCurrency.round(self.principal or 0))
    setXMLFloat(xmlFile, key .. "#interest", AGFCurrency.round(self.interest or 0))
    setXMLFloat(xmlFile, key .. "#fees", AGFCurrency.round(self.fees or 0))

    setOptionalString(xmlFile, key .. "#groupId", self.groupId)
    setOptionalString(xmlFile, key .. "#expenseCategory", self.expenseCategory)
    setOptionalString(xmlFile, key .. "#fundingSource", self.fundingSource)
    setOptionalString(xmlFile, key .. "#assetId", self.assetId)
    setOptionalString(xmlFile, key .. "#liabilityId", self.liabilityId)
    setOptionalString(xmlFile, key .. "#description", self.description)

    if self.period ~= nil then setXMLInt(xmlFile, key .. "#period", tonumber(self.period) or 0) end
    if self.year ~= nil then setXMLInt(xmlFile, key .. "#year", tonumber(self.year) or 0) end

    local metadataKeys = {}
    for metadataKey, _ in pairs(self.metadata or {}) do
        table.insert(metadataKeys, metadataKey)
    end
    table.sort(metadataKeys)

    for index, metadataKey in ipairs(metadataKeys) do
        local metadataNode = string.format("%s.metadata.entry(%d)", key, index - 1)
        setXMLString(xmlFile, metadataNode .. "#key", metadataKey)
        setXMLString(xmlFile, metadataNode .. "#value", tostring(self.metadata[metadataKey]))
    end
end

function AGFTransaction.loadFromXMLFile(xmlFile, key)
    if not hasXMLProperty(xmlFile, key .. "#id") then
        return nil
    end

    local id = getXMLString(xmlFile, key .. "#id")
    local farmId = getXMLInt(xmlFile, key .. "#farmId")
    local transactionType = getXMLString(xmlFile, key .. "#type") or AGFTransactionType.ADJUSTMENT
    local amount = getXMLFloat(xmlFile, key .. "#amount") or 0

    local transaction = AGFTransaction.new(id, farmId, transactionType, amount)
    transaction.principal = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#principal") or 0)
    transaction.interest = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#interest") or 0)
    transaction.fees = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#fees") or 0)
    transaction.groupId = getXMLString(xmlFile, key .. "#groupId")
    transaction.expenseCategory = getXMLString(xmlFile, key .. "#expenseCategory")
    transaction.fundingSource = getXMLString(xmlFile, key .. "#fundingSource")
    transaction.assetId = getXMLString(xmlFile, key .. "#assetId")
    transaction.liabilityId = getXMLString(xmlFile, key .. "#liabilityId")
    transaction.description = getXMLString(xmlFile, key .. "#description")
    transaction.period = getXMLInt(xmlFile, key .. "#period")
    transaction.year = getXMLInt(xmlFile, key .. "#year")

    local metadataIndex = 0
    while true do
        local metadataNode = string.format("%s.metadata.entry(%d)", key, metadataIndex)
        if not hasXMLProperty(xmlFile, metadataNode .. "#key") then
            break
        end

        local metadataKey = getXMLString(xmlFile, metadataNode .. "#key")
        local metadataValue = getXMLString(xmlFile, metadataNode .. "#value")
        if metadataKey ~= nil then
            transaction.metadata[metadataKey] = metadataValue or ""
        end
        metadataIndex = metadataIndex + 1
    end

    return transaction
end
