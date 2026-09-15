-- AgForward Financial Cooperative
-- High-level accounting API. Economic purpose remains separate from financing
-- source; multi-record financed purchases are committed by the operation coordinator.

AGFAccountingService = {}
AGFAccountingService_mt = Class(AGFAccountingService)

function AGFAccountingService.new(ledger, liabilities, operations, runtimeState)
    local self = setmetatable({}, AGFAccountingService_mt)
    self.ledger = ledger
    self.liabilities = liabilities
    self.operations = operations
    self.runtimeState = runtimeState
    return self
end

function AGFAccountingService:checkMutationAllowed()
    if self.runtimeState == nil then return false, "RUNTIME_STATE_UNAVAILABLE" end
    return self.runtimeState:canMutate()
end

function AGFAccountingService:postCashExpense(farmId, amount, expenseCategory, description)
    local allowed, authorityError = self:checkMutationAllowed()
    if not allowed then return false, authorityError end

    amount = math.abs(AGFCurrency.round(amount or 0))
    if amount <= 0 then return false, "INVALID_AMOUNT" end

    local transaction = self.ledger:createTransaction(farmId, AGFTransactionType.INPUT_PURCHASE, -amount)
    transaction:setExpenseCategory(expenseCategory)
    transaction:setFundingSource(AGFFundingSource.CASH)
    transaction:setDescription(description)

    local posted, errorCode = self.ledger:post(transaction)
    if not posted then return false, errorCode end
    return true, transaction:clone()
end

function AGFAccountingService:getExpectedRevolvingProduct(fundingSource)
    if fundingSource == AGFFundingSource.OPERATING_LINE then
        return AGFProductType.OPERATING_LINE
    end
    if fundingSource == AGFFundingSource.CROP_INPUT_LINE then
        return AGFProductType.CROP_INPUT_LINE
    end
    return nil
end

function AGFAccountingService:postFundedInputPurchase(farmId, amount, expenseCategory, fundingSource, liabilityId, description)
    if fundingSource == nil or fundingSource == AGFFundingSource.CASH then
        return self:postCashExpense(farmId, amount, expenseCategory, description)
    end

    if liabilityId == nil or liabilityId == "" then return false, "LIABILITY_REQUIRED" end
    local expectedProductType = self:getExpectedRevolvingProduct(fundingSource)
    if expectedProductType == nil then return false, "UNSUPPORTED_DIRECT_FUNDING_SOURCE" end
    if self.operations == nil then return false, "OPERATION_COORDINATOR_UNAVAILABLE" end

    return self.operations:executeRevolvingInputPurchase(
        farmId,
        amount,
        expenseCategory,
        fundingSource,
        liabilityId,
        description,
        expectedProductType
    )
end

function AGFAccountingService:postCropInputLinePurchase(farmId, amount, expenseCategory, liabilityId, description)
    local supportedCategories = {
        [AGFExpenseCategory.SEED] = true,
        [AGFExpenseCategory.FERTILIZER] = true,
        [AGFExpenseCategory.LIME_SOIL_AMENDMENT] = true,
        [AGFExpenseCategory.CROP_PROTECTION] = true,
        [AGFExpenseCategory.FUEL] = true,
        [AGFExpenseCategory.OTHER_INPUT] = true
    }

    if not supportedCategories[expenseCategory] then
        return false, "INELIGIBLE_CROP_INPUT_CATEGORY"
    end

    return self:postFundedInputPurchase(
        farmId,
        amount,
        expenseCategory,
        AGFFundingSource.CROP_INPUT_LINE,
        liabilityId,
        description
    )
end
