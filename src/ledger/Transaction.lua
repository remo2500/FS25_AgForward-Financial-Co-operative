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
    self.amount = tonumber(amount) or 0
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
    return self
end

function AGFTransaction:setGroupId(groupId)
    self.groupId = groupId
    return self
end

function AGFTransaction:setBreakdown(principal, interest, fees)
    self.principal = tonumber(principal) or 0
    self.interest = tonumber(interest) or 0
    self.fees = tonumber(fees) or 0
    return self
end

function AGFTransaction:setExpenseCategory(category)
    self.expenseCategory = category
    return self
end

function AGFTransaction:setFundingSource(source)
    self.fundingSource = source
    return self
end

function AGFTransaction:setAssetId(assetId)
    self.assetId = assetId
    return self
end

function AGFTransaction:setLiabilityId(liabilityId)
    self.liabilityId = liabilityId
    return self
end

function AGFTransaction:setPeriod(year, period)
    self.year = year
    self.period = period
    return self
end

function AGFTransaction:setDescription(description)
    self.description = description
    return self
end

function AGFTransaction:setMetadata(key, value)
    if key ~= nil then
        if value == nil then
            self.metadata[tostring(key)] = nil
        else
            self.metadata[tostring(key)] = tostring(value)
        end
    end
    return self
end

function AGFTransaction:saveToXMLFile(xmlFile, key)
    setXMLString(xmlFile, key .. "#id", tostring(self.id))
    setXMLInt(xmlFile, key .. "#farmId", tonumber(self.farmId) or 0)
    setXMLString(xmlFile, key .. "#type", tostring(self.transactionType or AGFTransactionType.ADJUSTMENT))
    setXMLFloat(xmlFile, key .. "#amount", tonumber(self.amount) or 0)
    setXMLFloat(xmlFile, key .. "#principal", tonumber(self.principal) or 0)
    setXMLFloat(xmlFile, key .. "#interest", tonumber(self.interest) or 0)
    setXMLFloat(xmlFile, key .. "#fees", tonumber(self.fees) or 0)

    setOptionalString(xmlFile, key .. "#groupId", self.groupId)
    setOptionalString(xmlFile, key .. "#expenseCategory", self.expenseCategory)
    setOptionalString(xmlFile, key .. "#fundingSource", self.fundingSource)
    setOptionalString(xmlFile, key .. "#assetId", self.assetId)
    setOptionalString(xmlFile, key .. "#liabilityId", self.liabilityId)
    setOptionalString(xmlFile, key .. "#description", self.description)

    if self.period ~= nil then
        setXMLInt(xmlFile, key .. "#period", tonumber(self.period) or 0)
    end
    if self.year ~= nil then
        setXMLInt(xmlFile, key .. "#year", tonumber(self.year) or 0)
    end

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
    transaction.principal = getXMLFloat(xmlFile, key .. "#principal") or 0
    transaction.interest = getXMLFloat(xmlFile, key .. "#interest") or 0
    transaction.fees = getXMLFloat(xmlFile, key .. "#fees") or 0
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
