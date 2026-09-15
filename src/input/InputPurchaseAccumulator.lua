-- AgForward Financial Cooperative
-- Aggregates high-frequency input purchases (AI seed/fertilizer/fuel charges)
-- into exact cent-based buckets before they are posted to the financial ledger.

AGFInputPurchaseAccumulator = {}
AGFInputPurchaseAccumulator_mt = Class(AGFInputPurchaseAccumulator)

function AGFInputPurchaseAccumulator.new()
    local self = setmetatable({}, AGFInputPurchaseAccumulator_mt)
    self.buckets = {}
    return self
end

function AGFInputPurchaseAccumulator:makeKey(farmId, expenseCategory, fundingSource, liabilityId)
    return table.concat({
        tostring(farmId or 0),
        tostring(expenseCategory or "unknown"),
        tostring(fundingSource or AGFFundingSource.CASH),
        tostring(liabilityId or "")
    }, "|")
end

function AGFInputPurchaseAccumulator:add(farmId, amount, expenseCategory, fundingSource, liabilityId, description)
    local minorUnits = math.abs(AGFCurrency.toMinorUnits(amount))
    if minorUnits <= 0 then return false, "INVALID_AMOUNT" end
    if farmId == nil or expenseCategory == nil then return false, "INVALID_ACCUMULATOR_CONTEXT" end

    local key = self:makeKey(farmId, expenseCategory, fundingSource, liabilityId)
    local bucket = self.buckets[key]
    if bucket == nil then
        bucket = {
            farmId = farmId,
            expenseCategory = expenseCategory,
            fundingSource = fundingSource or AGFFundingSource.CASH,
            liabilityId = liabilityId,
            minorUnits = 0,
            eventCount = 0,
            description = description
        }
        self.buckets[key] = bucket
    end

    bucket.minorUnits = bucket.minorUnits + minorUnits
    bucket.eventCount = bucket.eventCount + 1
    if description ~= nil then bucket.description = description end
    return true, nil
end

function AGFInputPurchaseAccumulator:getPending()
    local result = {}
    for _, bucket in pairs(self.buckets) do
        table.insert(result, {
            farmId = bucket.farmId,
            expenseCategory = bucket.expenseCategory,
            fundingSource = bucket.fundingSource,
            liabilityId = bucket.liabilityId,
            amount = AGFCurrency.fromMinorUnits(bucket.minorUnits),
            eventCount = bucket.eventCount,
            description = bucket.description
        })
    end

    table.sort(result, function(left, right)
        local leftKey = self:makeKey(left.farmId, left.expenseCategory, left.fundingSource, left.liabilityId)
        local rightKey = self:makeKey(right.farmId, right.expenseCategory, right.fundingSource, right.liabilityId)
        return leftKey < rightKey
    end)
    return result
end

function AGFInputPurchaseAccumulator:drain()
    local result = self:getPending()
    self.buckets = {}
    return result
end

function AGFInputPurchaseAccumulator:reset()
    self.buckets = {}
end
