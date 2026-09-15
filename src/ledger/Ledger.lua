AGFLedger = {}
AGFLedger_mt = Class(AGFLedger)

function AGFLedger.new(idService)
    local self = setmetatable({}, AGFLedger_mt)
    self.idService = idService
    self.transactions = {}
    self.order = {}
    self.byFarm = {}
    self.byGroup = {}
    return self
end

function AGFLedger:reset()
    self.transactions = {}
    self.order = {}
    self.byFarm = {}
    self.byGroup = {}
end

function AGFLedger:createGroupId()
    return self.idService:next("GRP")
end

function AGFLedger:createTransaction(farmId, transactionType, amount)
    local id = self.idService:next("TX")
    local transaction = AGFTransaction.new(id, farmId, transactionType, amount)

    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        local environment = g_currentMission.environment
        transaction.period = environment.currentPeriod
        transaction.year = environment.currentYear
    end

    return transaction
end

function AGFLedger:validateTransaction(transaction, pendingIds)
    if transaction == nil or transaction.id == nil or transaction.farmId == nil then
        return false, "INVALID_TRANSACTION"
    end

    if self.transactions[transaction.id] ~= nil then
        return false, "DUPLICATE_TRANSACTION_ID"
    end

    if pendingIds ~= nil and pendingIds[transaction.id] then
        return false, "DUPLICATE_TRANSACTION_ID_IN_BATCH"
    end

    return true, nil
end

function AGFLedger:post(transaction)
    local valid, errorCode = self:validateTransaction(transaction)
    if not valid then
        return false, errorCode
    end

    self.transactions[transaction.id] = transaction
    table.insert(self.order, transaction.id)

    self.byFarm[transaction.farmId] = self.byFarm[transaction.farmId] or {}
    table.insert(self.byFarm[transaction.farmId], transaction.id)

    if transaction.groupId ~= nil and transaction.groupId ~= "" then
        self.byGroup[transaction.groupId] = self.byGroup[transaction.groupId] or {}
        table.insert(self.byGroup[transaction.groupId], transaction.id)
        self.idService:observeId(transaction.groupId)
    end

    self.idService:observeId(transaction.id)
    return true, nil
end

function AGFLedger:postBatch(transactions)
    if type(transactions) ~= "table" or #transactions == 0 then
        return false, "EMPTY_BATCH"
    end

    local pendingIds = {}
    for _, transaction in ipairs(transactions) do
        local valid, errorCode = self:validateTransaction(transaction, pendingIds)
        if not valid then
            return false, errorCode
        end
        pendingIds[transaction.id] = true
    end

    -- Validation occurs for the entire batch before any transaction is posted.
    -- With the current in-memory ledger, post() cannot fail after this point
    -- unless the ledger is externally mutated during this synchronous call.
    for _, transaction in ipairs(transactions) do
        local posted, errorCode = self:post(transaction)
        if not posted then
            return false, errorCode
        end
    end

    return true, nil
end

function AGFLedger:getTransaction(id)
    return self.transactions[id]
end

function AGFLedger:getAllTransactions()
    local result = {}
    for _, id in ipairs(self.order) do
        local transaction = self.transactions[id]
        if transaction ~= nil then
            table.insert(result, transaction)
        end
    end
    return result
end

function AGFLedger:getFarmTransactions(farmId)
    local result = {}
    for _, id in ipairs(self.byFarm[farmId] or {}) do
        local transaction = self.transactions[id]
        if transaction ~= nil then
            table.insert(result, transaction)
        end
    end
    return result
end

function AGFLedger:getGroupTransactions(groupId)
    local result = {}
    for _, id in ipairs(self.byGroup[groupId] or {}) do
        local transaction = self.transactions[id]
        if transaction ~= nil then
            table.insert(result, transaction)
        end
    end
    return result
end

function AGFLedger:getTransactionCount()
    return #self.order
end

function AGFLedger:saveToXMLFile(xmlFile, key)
    setXMLInt(xmlFile, key .. "#transactionCount", #self.order)

    local writeIndex = 0
    for _, id in ipairs(self.order) do
        local transaction = self.transactions[id]
        if transaction ~= nil then
            local transactionKey = string.format("%s.transactions.transaction(%d)", key, writeIndex)
            transaction:saveToXMLFile(xmlFile, transactionKey)
            writeIndex = writeIndex + 1
        end
    end
end

function AGFLedger:loadFromXMLFile(xmlFile, key)
    self:reset()

    local index = 0
    while true do
        local transactionKey = string.format("%s.transactions.transaction(%d)", key, index)
        if not hasXMLProperty(xmlFile, transactionKey .. "#id") then
            break
        end

        local transaction = AGFTransaction.loadFromXMLFile(xmlFile, transactionKey)
        if transaction ~= nil then
            local posted, errorCode = self:post(transaction)
            if not posted then
                print(string.format(
                    "Warning: AgForward skipped saved transaction '%s' (%s)",
                    tostring(transaction.id),
                    tostring(errorCode)
                ))
            end
        end

        index = index + 1
    end

    return #self.order
end
