-- AgForward Financial Cooperative
-- High-level accounting API. This service records economic purpose separately
-- from financing source so operating credit does not erase expense categories.

AGFAccountingService = {}
AGFAccountingService_mt = Class(AGFAccountingService)

function AGFAccountingService.new(ledger, liabilities)
    local self = setmetatable({}, AGFAccountingService_mt)
    self.ledger = ledger
    self.liabilities = liabilities
    return self
end

function AGFAccountingService:postCashExpense(farmId, amount, expenseCategory, description)
    amount = math.abs(tonumber(amount) or 0)
    if amount <= 0 then
        return false, "INVALID_AMOUNT"
    end

    local transaction = self.ledger:createTransaction(farmId, AGFTransactionType.INPUT_PURCHASE, -amount)
    transaction:setExpenseCategory(expenseCategory)
    transaction:setFundingSource(AGFFundingSource.CASH)
    transaction:setDescription(description)

    local posted, errorCode = self.ledger:post(transaction)
    if not posted then
        return false, errorCode
    end

    return true, transaction
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
    amount = math.abs(tonumber(amount) or 0)
    if amount <= 0 then
        return false, "INVALID_AMOUNT"
    end

    if fundingSource == nil or fundingSource == AGFFundingSource.CASH then
        return self:postCashExpense(farmId, amount, expenseCategory, description)
    end

    if liabilityId == nil or liabilityId == "" then
        return false, "LIABILITY_REQUIRED"
    end

    local expectedProductType = self:getExpectedRevolvingProduct(fundingSource)
    if expectedProductType == nil then
        return false, "UNSUPPORTED_DIRECT_FUNDING_SOURCE"
    end

    if self.liabilities == nil then
        return false, "LIABILITY_REGISTRY_UNAVAILABLE"
    end

    local canDraw, liabilityOrError = self.liabilities:canDraw(
        liabilityId,
        farmId,
        amount,
        expectedProductType
    )
    if not canDraw then
        return false, liabilityOrError
    end

    local liability = liabilityOrError
    local groupId = self.ledger:createGroupId()

    local draw = self.ledger:createTransaction(farmId, AGFTransactionType.CREDIT_DRAW, amount)
    draw:setGroupId(groupId)
    draw:setFundingSource(fundingSource)
    draw:setLiabilityId(liabilityId)
    draw:setDescription(description)
    draw:setMetadata("economicRole", "financing")
    draw:setMetadata("productType", liability.productType)

    local purchase = self.ledger:createTransaction(farmId, AGFTransactionType.INPUT_PURCHASE, -amount)
    purchase:setGroupId(groupId)
    purchase:setExpenseCategory(expenseCategory)
    purchase:setFundingSource(fundingSource)
    purchase:setLiabilityId(liabilityId)
    purchase:setDescription(description)
    purchase:setMetadata("economicRole", "expense")
    purchase:setMetadata("productType", liability.productType)

    local posted, errorCode = self.ledger:postBatch({draw, purchase})
    if not posted then
        return false, errorCode
    end

    -- The draw has already passed registry validation. Updating the principal
    -- only after the linked ledger batch succeeds prevents a liability balance
    -- increase without matching accounting entries.
    liability.principalBalance = liability.principalBalance + amount

    return true, {
        groupId = groupId,
        draw = draw,
        purchase = purchase,
        liability = liability
    }
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
