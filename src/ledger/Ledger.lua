AGFLedger = {}
AGFLedger_mt = Class(AGFLedger)

function AGFLedger.new(idService)
    local self = setmetatable({}, AGFLedger_mt)
    self.idService = idService
    self.transactions = {}
    self.byFarm = {}
    self.byGroup = {}
    return self
end

function AGFLedger:createTransaction(farmId, transactionType, amount)
    local id = self.idService:next("TX")
    return AGFTransaction.new(id, farmId, transactionType, amount)
end

function AGFLedger:post(transaction)
    if transaction == nil or transaction.id == nil or transaction.farmId == nil then
        return false
    end

    self.transactions[transaction.id] = transaction

    self.byFarm[transaction.farmId] = self.byFarm[transaction.farmId] or {}
    table.insert(self.byFarm[transaction.farmId], transaction.id)

    if transaction.groupId ~= nil then
        self.byGroup[transaction.groupId] = self.byGroup[transaction.groupId] or {}
        table.insert(self.byGroup[transaction.groupId], transaction.id)
    end

    return true
end

function AGFLedger:getTransaction(id)
    return self.transactions[id]
end

function AGFLedger:getFarmTransactions(farmId)
    local result = {}
    for _, id in ipairs(self.byFarm[farmId] or {}) do
        local tx = self.transactions[id]
        if tx ~= nil then
            table.insert(result, tx)
        end
    end
    return result
end

function AGFLedger:getGroupTransactions(groupId)
    local result = {}
    for _, id in ipairs(self.byGroup[groupId] or {}) do
        local tx = self.transactions[id]
        if tx ~= nil then
            table.insert(result, tx)
        end
    end
    return result
end
