-- AgForward Financial Cooperative
-- Read-only period and trend reporting derived from the canonical ledger.
-- History rows are views over journal data; they never become a second balance authority.

AGFFinancialHistoryService = {}
AGFFinancialHistoryService_mt = Class(AGFFinancialHistoryService)

local function addMoney(map, key, amount)
    local normalizedKey = key or "unclassified"
    map[normalizedKey] = AGFCurrency.round((map[normalizedKey] or 0) + (amount or 0))
end

local function addMovementBucket(map, key, amount)
    local normalizedKey = key or "other"
    map[normalizedKey] = map[normalizedKey] or {count = 0, net = 0, inflows = 0, outflows = 0}
    local bucket = map[normalizedKey]
    local value = AGFCurrency.round(amount or 0)
    bucket.count = bucket.count + 1
    bucket.net = AGFCurrency.round(bucket.net + value)
    if value >= 0 then
        bucket.inflows = AGFCurrency.round(bucket.inflows + value)
    else
        bucket.outflows = AGFCurrency.round(bucket.outflows + math.abs(value))
    end
end

local function movementClass(transactionType)
    if transactionType == AGFTransactionType.CREDIT_DRAW
        or transactionType == AGFTransactionType.CREDIT_REPAYMENT
        or transactionType == AGFTransactionType.LOAN_PROCEEDS
        or transactionType == AGFTransactionType.LOAN_PAYMENT
        or transactionType == AGFTransactionType.PRINCIPAL_PAYMENT then
        return "financing"
    end

    if transactionType == AGFTransactionType.INPUT_PURCHASE
        or transactionType == AGFTransactionType.LEASE_RENT
        or transactionType == AGFTransactionType.INTEREST_PAYMENT
        or transactionType == AGFTransactionType.FINANCE_FEE
        or transactionType == AGFTransactionType.LATE_FEE then
        return "operating"
    end

    if transactionType == AGFTransactionType.ASSET_PURCHASE
        or transactionType == AGFTransactionType.ASSET_SALE then
        return "investing"
    end

    if transactionType == AGFTransactionType.GRANT_RECEIPT
        or transactionType == AGFTransactionType.TAX_PAYMENT then
        return "government"
    end

    return "other"
end

local function validPeriod(year, period, periodsPerYear)
    local y = tonumber(year)
    local p = tonumber(period)
    return y ~= nil and y > 0 and y == math.floor(y)
        and p ~= nil and p > 0 and p <= periodsPerYear and p == math.floor(p)
end

local function newPeriodResult(farmId, year, period)
    return {
        farmId = farmId,
        year = year,
        period = period,
        transactionCount = 0,
        netAmount = 0,
        cashFlow = {inflows = 0, outflows = 0, net = 0},
        components = {principal = 0, interest = 0, fees = 0},
        byMovementClass = {},
        byTransactionType = {},
        byExpenseCategory = {},
        byFundingSource = {},
        inputPurchases = {total = 0, cash = 0, financed = 0, unknownSource = 0},
        sourceOfFundsByExpenseCategory = {}
    }
end

local function cloneMap(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            result[key] = cloneMap(value)
        else
            result[key] = value
        end
    end
    return result
end

function AGFFinancialHistoryService.new(ledger)
    local self = setmetatable({}, AGFFinancialHistoryService_mt)
    self.ledger = ledger
    return self
end

function AGFFinancialHistoryService:buildPeriod(farmId, year, period, periodsPerYear)
    periodsPerYear = tonumber(periodsPerYear) or 12
    if not validPeriod(year, period, periodsPerYear) then
        return false, "INVALID_HISTORY_PERIOD"
    end

    local result = newPeriodResult(farmId, year, period)
    local transactions = self.ledger ~= nil and self.ledger:getFarmTransactions(farmId) or {}

    for _, transaction in ipairs(transactions) do
        if tonumber(transaction.year) == tonumber(year) and tonumber(transaction.period) == tonumber(period) then
            local amount = AGFCurrency.round(transaction.amount or 0)
            result.transactionCount = result.transactionCount + 1
            result.netAmount = AGFCurrency.round(result.netAmount + amount)
            result.cashFlow.net = AGFCurrency.round(result.cashFlow.net + amount)
            if amount >= 0 then
                result.cashFlow.inflows = AGFCurrency.round(result.cashFlow.inflows + amount)
            else
                result.cashFlow.outflows = AGFCurrency.round(result.cashFlow.outflows + math.abs(amount))
            end

            result.components.principal = AGFCurrency.round(result.components.principal + (transaction.principal or 0))
            result.components.interest = AGFCurrency.round(result.components.interest + (transaction.interest or 0))
            result.components.fees = AGFCurrency.round(result.components.fees + (transaction.fees or 0))

            addMovementBucket(result.byMovementClass, movementClass(transaction.transactionType), amount)
            addMoney(result.byTransactionType, transaction.transactionType, amount)
            if transaction.expenseCategory ~= nil then
                addMoney(result.byExpenseCategory, transaction.expenseCategory, amount)
            end
            if transaction.fundingSource ~= nil then
                addMoney(result.byFundingSource, transaction.fundingSource, amount)
            end

            if transaction.transactionType == AGFTransactionType.INPUT_PURCHASE then
                local purchaseAmount = math.abs(amount)
                result.inputPurchases.total = AGFCurrency.round(result.inputPurchases.total + purchaseAmount)
                local source = transaction.fundingSource
                if source == AGFFundingSource.CASH then
                    result.inputPurchases.cash = AGFCurrency.round(result.inputPurchases.cash + purchaseAmount)
                elseif source ~= nil then
                    result.inputPurchases.financed = AGFCurrency.round(result.inputPurchases.financed + purchaseAmount)
                else
                    result.inputPurchases.unknownSource = AGFCurrency.round(result.inputPurchases.unknownSource + purchaseAmount)
                end

                local category = transaction.expenseCategory or "unclassified"
                local sourceKey = source or "unknown"
                result.sourceOfFundsByExpenseCategory[category] = result.sourceOfFundsByExpenseCategory[category] or {}
                addMoney(result.sourceOfFundsByExpenseCategory[category], sourceKey, purchaseAmount)
            end
        end
    end

    return true, result
end

local function mergeMoneyMap(target, source)
    for key, value in pairs(source or {}) do
        target[key] = AGFCurrency.round((target[key] or 0) + value)
    end
end

local function mergeMovementMap(target, source)
    for key, value in pairs(source or {}) do
        target[key] = target[key] or {count = 0, net = 0, inflows = 0, outflows = 0}
        local bucket = target[key]
        bucket.count = bucket.count + (value.count or 0)
        bucket.net = AGFCurrency.round(bucket.net + (value.net or 0))
        bucket.inflows = AGFCurrency.round(bucket.inflows + (value.inflows or 0))
        bucket.outflows = AGFCurrency.round(bucket.outflows + (value.outflows or 0))
    end
end

function AGFFinancialHistoryService:buildRange(farmId, startYear, startPeriod, endYear, endPeriod, periodsPerYear)
    periodsPerYear = tonumber(periodsPerYear) or 12
    if not validPeriod(startYear, startPeriod, periodsPerYear)
        or not validPeriod(endYear, endPeriod, periodsPerYear) then
        return false, "INVALID_HISTORY_RANGE"
    end

    local startIndex = (startYear * periodsPerYear) + (startPeriod - 1)
    local endIndex = (endYear * periodsPerYear) + (endPeriod - 1)
    if endIndex < startIndex then return false, "HISTORY_RANGE_REVERSED" end
    if endIndex - startIndex > (periodsPerYear * 50) then return false, "HISTORY_RANGE_TOO_LARGE" end

    local result = {
        farmId = farmId,
        startYear = startYear,
        startPeriod = startPeriod,
        endYear = endYear,
        endPeriod = endPeriod,
        periodCount = 0,
        transactionCount = 0,
        netAmount = 0,
        cashFlow = {inflows = 0, outflows = 0, net = 0},
        components = {principal = 0, interest = 0, fees = 0},
        byMovementClass = {},
        byTransactionType = {},
        byExpenseCategory = {},
        byFundingSource = {},
        inputPurchases = {total = 0, cash = 0, financed = 0, unknownSource = 0},
        periods = {}
    }

    for index = startIndex, endIndex do
        local year = math.floor(index / periodsPerYear)
        local period = (index % periodsPerYear) + 1
        local ok, periodResult = self:buildPeriod(farmId, year, period, periodsPerYear)
        if not ok then return false, periodResult end

        table.insert(result.periods, periodResult)
        result.periodCount = result.periodCount + 1
        result.transactionCount = result.transactionCount + periodResult.transactionCount
        result.netAmount = AGFCurrency.round(result.netAmount + periodResult.netAmount)
        result.cashFlow.inflows = AGFCurrency.round(result.cashFlow.inflows + periodResult.cashFlow.inflows)
        result.cashFlow.outflows = AGFCurrency.round(result.cashFlow.outflows + periodResult.cashFlow.outflows)
        result.cashFlow.net = AGFCurrency.round(result.cashFlow.net + periodResult.cashFlow.net)
        result.components.principal = AGFCurrency.round(result.components.principal + periodResult.components.principal)
        result.components.interest = AGFCurrency.round(result.components.interest + periodResult.components.interest)
        result.components.fees = AGFCurrency.round(result.components.fees + periodResult.components.fees)
        result.inputPurchases.total = AGFCurrency.round(result.inputPurchases.total + periodResult.inputPurchases.total)
        result.inputPurchases.cash = AGFCurrency.round(result.inputPurchases.cash + periodResult.inputPurchases.cash)
        result.inputPurchases.financed = AGFCurrency.round(result.inputPurchases.financed + periodResult.inputPurchases.financed)
        result.inputPurchases.unknownSource = AGFCurrency.round(result.inputPurchases.unknownSource + periodResult.inputPurchases.unknownSource)

        mergeMovementMap(result.byMovementClass, periodResult.byMovementClass)
        mergeMoneyMap(result.byTransactionType, periodResult.byTransactionType)
        mergeMoneyMap(result.byExpenseCategory, periodResult.byExpenseCategory)
        mergeMoneyMap(result.byFundingSource, periodResult.byFundingSource)
    end

    result.byMovementClass = cloneMap(result.byMovementClass)
    return true, result
end

function AGFFinancialHistoryService:buildAnnual(farmId, year, periodsPerYear)
    periodsPerYear = tonumber(periodsPerYear) or 12
    if not validPeriod(year, 1, periodsPerYear) then return false, "INVALID_HISTORY_YEAR" end
    return self:buildRange(farmId, year, 1, year, periodsPerYear, periodsPerYear)
end
