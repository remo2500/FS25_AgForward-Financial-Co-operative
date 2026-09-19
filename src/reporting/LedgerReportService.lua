-- AgForward Financial Cooperative
-- Read-only ledger reporting. All summaries are derived; no duplicate balances.

AGFLedgerReportService = {}
AGFLedgerReportService_mt = Class(AGFLedgerReportService)

function AGFLedgerReportService.new(ledger)
    local self = setmetatable({}, AGFLedgerReportService_mt)
    self.ledger = ledger
    return self
end

local function addMoney(map, key, amount)
    local normalizedKey = key or "unclassified"
    map[normalizedKey] = AGFCurrency.round((map[normalizedKey] or 0) + (amount or 0))
end

function AGFLedgerReportService:filterFarmTransactions(farmId, options)
    options = options or {}
    local result = {}
    local transactions = self.ledger ~= nil and self.ledger:getFarmTransactions(farmId) or {}

    for _, transaction in ipairs(transactions) do
        local include = true
        if options.startYear ~= nil and transaction.year ~= nil and transaction.year < options.startYear then include = false end
        if options.endYear ~= nil and transaction.year ~= nil and transaction.year > options.endYear then include = false end
        if options.transactionType ~= nil and transaction.transactionType ~= options.transactionType then include = false end
        if options.expenseCategory ~= nil and transaction.expenseCategory ~= options.expenseCategory then include = false end
        if options.fundingSource ~= nil and transaction.fundingSource ~= options.fundingSource then include = false end
        if options.liabilityId ~= nil and transaction.liabilityId ~= options.liabilityId then include = false end
        if include then table.insert(result, transaction) end
    end
    return result
end

function AGFLedgerReportService:buildFarmSummary(farmId, options)
    local summary = {
        farmId = farmId,
        transactionCount = 0,
        netAmount = 0,
        totalPrincipal = 0,
        totalInterest = 0,
        totalFees = 0,
        byTransactionType = {},
        byExpenseCategory = {},
        byFundingSource = {},
        financedInputPurchases = {},
        cashInputPurchases = {},
        sourceOfFundsByExpenseCategory = {}
    }

    for _, transaction in ipairs(self:filterFarmTransactions(farmId, options)) do
        summary.transactionCount = summary.transactionCount + 1
        summary.netAmount = AGFCurrency.round(summary.netAmount + (transaction.amount or 0))
        summary.totalPrincipal = AGFCurrency.round(summary.totalPrincipal + (transaction.principal or 0))
        summary.totalInterest = AGFCurrency.round(summary.totalInterest + (transaction.interest or 0))
        summary.totalFees = AGFCurrency.round(summary.totalFees + (transaction.fees or 0))

        addMoney(summary.byTransactionType, transaction.transactionType, transaction.amount or 0)
        if transaction.expenseCategory ~= nil then
            addMoney(summary.byExpenseCategory, transaction.expenseCategory, transaction.amount or 0)
        end
        if transaction.fundingSource ~= nil then
            addMoney(summary.byFundingSource, transaction.fundingSource, transaction.amount or 0)
        end

        if transaction.transactionType == AGFTransactionType.INPUT_PURCHASE then
            local category = transaction.expenseCategory or "unclassified"
            local source = transaction.fundingSource or "unknown"
            local purchaseAmount = math.abs(AGFCurrency.round(transaction.amount or 0))

            summary.sourceOfFundsByExpenseCategory[category] = summary.sourceOfFundsByExpenseCategory[category] or {}
            addMoney(summary.sourceOfFundsByExpenseCategory[category], source, purchaseAmount)

            if source == AGFFundingSource.CASH then
                addMoney(summary.cashInputPurchases, category, purchaseAmount)
            else
                addMoney(summary.financedInputPurchases, category, purchaseAmount)
            end
        end
    end

    return summary
end

function AGFLedgerReportService:buildTransactionGroup(groupId)
    local transactions = self.ledger ~= nil and self.ledger:getGroupTransactions(groupId) or {}
    local summary = {
        groupId = groupId,
        transactionCount = #transactions,
        netAmount = 0,
        transactions = transactions,
        balancedEconomicCash = false
    }

    for _, transaction in ipairs(transactions) do
        summary.netAmount = AGFCurrency.round(summary.netAmount + (transaction.amount or 0))
    end
    summary.balancedEconomicCash = AGFCurrency.equals(summary.netAmount, 0)
    return summary
end
