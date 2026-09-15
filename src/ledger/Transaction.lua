AGFTransaction = {}
AGFTransaction_mt = Class(AGFTransaction)

function AGFTransaction.new(id, farmId, transactionType, amount)
    local self = setmetatable({}, AGFTransaction_mt)
    self.id = id
    self.groupId = nil
    self.farmId = farmId
    self.transactionType = transactionType
    self.amount = amount or 0
    self.principal = 0
    self.interest = 0
    self.fees = 0
    self.expenseCategory = nil
    self.fundingSource = nil
    self.assetId = nil
    self.liabilityId = nil
    self.period = nil
    self.year = nil
    self.metadata = {}
    return self
end

function AGFTransaction:setGroupId(groupId)
    self.groupId = groupId
    return self
end

function AGFTransaction:setBreakdown(principal, interest, fees)
    self.principal = principal or 0
    self.interest = interest or 0
    self.fees = fees or 0
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
