-- AgForward Financial Cooperative
-- Post-load and pre-save reconciliation. Serious inconsistencies prevent
-- financial mutation/save rather than being silently ignored.

AGFIntegrityService = {}
AGFIntegrityService_mt = Class(AGFIntegrityService)

local function isFiniteNumber(value)
    local number = tonumber(value)
    return number ~= nil and number == number and number ~= math.huge and number ~= -math.huge
end

local function buildValueSet(source)
    local result = {}
    for _, value in pairs(source or {}) do
        result[value] = true
    end
    return result
end

function AGFIntegrityService.new(services)
    local self = setmetatable({}, AGFIntegrityService_mt)
    self.services = services
    self.lastReport = nil
    return self
end

function AGFIntegrityService:run(schemaVersion)
    local report = {
        errors = {},
        warnings = {},
        transactionCount = 0,
        liabilityCount = 0
    }

    local function addError(code, message)
        table.insert(report.errors, {code = code, message = message})
    end

    local function addWarning(code, message)
        table.insert(report.warnings, {code = code, message = message})
    end

    local transactionTypes = buildValueSet(AGFTransactionType)
    local fundingSources = buildValueSet(AGFFundingSource)
    local expenseCategories = buildValueSet(AGFExpenseCategory)
    local productTypes = buildValueSet(AGFProductType)

    local liabilities = self.services:get("liabilities")
    local ledger = self.services:get("ledger")
    local idService = self.services:get("idService")

    local liabilityIds = {}
    if liabilities ~= nil then
        local rawLiabilities = liabilities.getAllInternal ~= nil and liabilities:getAllInternal() or liabilities:getAll()
        report.liabilityCount = #rawLiabilities

        for _, liability in ipairs(rawLiabilities) do
            if liability.id == nil or liability.id == "" then
                addError("LIABILITY_ID_MISSING", "A saved liability has no ID")
            else
                liabilityIds[liability.id] = true
                if idService ~= nil then
                    idService:observeId(liability.id)
                end
            end

            if tonumber(liability.farmId) == nil or tonumber(liability.farmId) < 1 then
                addError("LIABILITY_FARM_INVALID", "Liability " .. tostring(liability.id) .. " has an invalid farm ID")
            elseif g_farmManager ~= nil and g_farmManager.getFarmById ~= nil and g_farmManager:getFarmById(liability.farmId) == nil then
                addWarning("LIABILITY_FARM_NOT_FOUND", "Liability " .. tostring(liability.id) .. " references a farm not currently present")
            end

            if not productTypes[liability.productType] then
                addError("LIABILITY_PRODUCT_UNKNOWN", "Liability " .. tostring(liability.id) .. " has unknown product type " .. tostring(liability.productType))
            end

            for fieldName, value in pairs({
                principalBalance = liability.principalBalance,
                originalPrincipal = liability.originalPrincipal,
                creditLimit = liability.creditLimit,
                accruedInterest = liability.accruedInterest,
                accruedFees = liability.accruedFees,
                interestRate = liability.interestRate,
                scheduledPayment = liability.scheduledPayment,
                balloonAmount = liability.balloonAmount
            }) do
                if not isFiniteNumber(value) then
                    addError("LIABILITY_NUMBER_INVALID", string.format("Liability %s has invalid %s", tostring(liability.id), fieldName))
                end
            end

            if (tonumber(liability.principalBalance) or 0) < -0.005 or (tonumber(liability.creditLimit) or 0) < -0.005 then
                addError("LIABILITY_NEGATIVE_BALANCE", "Liability " .. tostring(liability.id) .. " has a negative principal/limit")
            end

            if liability.isRevolving ~= nil and liability:isRevolving() and (tonumber(liability.principalBalance) or 0) > (tonumber(liability.creditLimit) or 0) + 0.005 then
                addError("REVOLVING_LIMIT_EXCEEDED", "Liability " .. tostring(liability.id) .. " is above its credit limit")
            end
        end
    end

    local groupSums = {}
    local groupRoles = {}
    if ledger ~= nil then
        local transactions = ledger.getAllTransactionsInternal ~= nil and ledger:getAllTransactionsInternal() or ledger:getAllTransactions()
        report.transactionCount = #transactions

        for _, transaction in ipairs(transactions) do
            if transaction.id == nil or transaction.id == "" then
                addError("TRANSACTION_ID_MISSING", "A saved transaction has no ID")
            elseif idService ~= nil then
                idService:observeId(transaction.id)
            end

            if tonumber(transaction.farmId) == nil or tonumber(transaction.farmId) < 1 then
                addError("TRANSACTION_FARM_INVALID", "Transaction " .. tostring(transaction.id) .. " has an invalid farm ID")
            end

            if not transactionTypes[transaction.transactionType] then
                addError("TRANSACTION_TYPE_UNKNOWN", "Transaction " .. tostring(transaction.id) .. " has unknown type " .. tostring(transaction.transactionType))
            end

            if not isFiniteNumber(transaction.amount) or not isFiniteNumber(transaction.principal) or not isFiniteNumber(transaction.interest) or not isFiniteNumber(transaction.fees) then
                addError("TRANSACTION_NUMBER_INVALID", "Transaction " .. tostring(transaction.id) .. " contains a non-finite amount")
            end

            if transaction.fundingSource ~= nil and transaction.fundingSource ~= "" and not fundingSources[transaction.fundingSource] then
                addWarning("FUNDING_SOURCE_UNKNOWN", "Transaction " .. tostring(transaction.id) .. " has unknown funding source " .. tostring(transaction.fundingSource))
            end

            if transaction.expenseCategory ~= nil and transaction.expenseCategory ~= "" and not expenseCategories[transaction.expenseCategory] then
                addWarning("EXPENSE_CATEGORY_UNKNOWN", "Transaction " .. tostring(transaction.id) .. " has unknown expense category " .. tostring(transaction.expenseCategory))
            end

            if transaction.liabilityId ~= nil and transaction.liabilityId ~= "" and not liabilityIds[transaction.liabilityId] then
                if (tonumber(schemaVersion) or 0) >= 2 then
                    addError("ORPHAN_LIABILITY_REFERENCE", "Transaction " .. tostring(transaction.id) .. " references missing liability " .. tostring(transaction.liabilityId))
                else
                    addWarning("LEGACY_LIABILITY_REFERENCE", "Legacy transaction " .. tostring(transaction.id) .. " references a liability unavailable in the legacy schema")
                end
            end

            if transaction.groupId ~= nil and transaction.groupId ~= "" then
                if idService ~= nil then
                    idService:observeId(transaction.groupId)
                end
                groupSums[transaction.groupId] = (groupSums[transaction.groupId] or 0) + (tonumber(transaction.amount) or 0)
                local role = transaction.metadata ~= nil and transaction.metadata.economicRole or nil
                if role == "financing" or role == "expense" then
                    groupRoles[transaction.groupId] = true
                end
            end
        end
    end

    for groupId, isFundingExpenseGroup in pairs(groupRoles) do
        if isFundingExpenseGroup and not AGFCurrency.equals(groupSums[groupId] or 0, 0) then
            addError("GROUP_NOT_BALANCED", string.format("Linked funding/expense group %s does not net to zero (%.2f)", tostring(groupId), tonumber(groupSums[groupId]) or 0))
        end
    end

    self.lastReport = report
    return #report.errors == 0, report
end

function AGFIntegrityService:getLastReport()
    return self.lastReport
end
