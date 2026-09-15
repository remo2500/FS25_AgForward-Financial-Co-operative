-- AgForward Financial Cooperative
-- High-level accounting API. This service records economic purpose separately
-- from financing source so operating credit does not erase expense categories.

AGFAccountingService = {}
AGFAccountingService_mt = Class(AGFAccountingService)

function AGFAccountingService.new(ledger)
    local self = setmetatable({}, AGFAccountingService_mt)
    self.ledger = ledger
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

    local groupId = self.ledger:createGroupId()

    local draw = self.ledger:createTransaction(farmId, AGFTransactionType.CREDIT_DRAW, amount)
    draw:setGroupId(groupId)
    draw:setFundingSource(fundingSource)
    draw:setLiabilityId(liabilityId)
    draw:setDescription(description)
    draw:setMetadata("economicRole", "financing")

    local purchase = self.ledger:createTransaction(farmId, AGFTransactionType.INPUT_PURCHASE, -amount)
    purchase:setGroupId(groupId)
    purchase:setExpenseCategory(expenseCategory)
    purchase:setFundingSource(fundingSource)
    purchase:setLiabilityId(liabilityId)
    purchase:setDescription(description)
    purchase:setMetadata("economicRole", "expense")

    local posted, errorCode = self.ledger:postBatch({draw, purchase})
    if not posted then
        return false, errorCode
    end

    return true, {
        groupId = groupId,
        draw = draw,
        purchase = purchase
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
