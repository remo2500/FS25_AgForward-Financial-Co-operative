-- AgForward Financial Cooperative
-- Coordinates multi-record financial mutations so liability and ledger state
-- either commit together or are rolled back together.

AGFFinancialOperationCoordinator = {}
AGFFinancialOperationCoordinator_mt = Class(AGFFinancialOperationCoordinator)

function AGFFinancialOperationCoordinator.new(ledger, liabilities, runtimeState)
    local self = setmetatable({}, AGFFinancialOperationCoordinator_mt)
    self.ledger = ledger
    self.liabilities = liabilities
    self.runtimeState = runtimeState
    return self
end

function AGFFinancialOperationCoordinator:executeRevolvingInputPurchase(farmId, amount, expenseCategory, fundingSource, liabilityId, description, expectedProductType)
    if self.runtimeState == nil then return false, "RUNTIME_STATE_UNAVAILABLE" end
    local allowed, authorityError = self.runtimeState:canMutate()
    if not allowed then return false, authorityError end

    amount = math.abs(AGFCurrency.round(amount or 0))
    if amount <= 0 then return false, "INVALID_AMOUNT" end

    local canDraw, liabilityOrError = self.liabilities:canDraw(liabilityId, farmId, amount, expectedProductType)
    if not canDraw then return false, liabilityOrError end
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

    local posted, postError = self.ledger:postBatch({draw, purchase})
    if not posted then return false, postError end

    local applied, applyResult = self.liabilities:applyDrawCommitted(liabilityId, amount, true)
    if not applied then
        local rolledBack, rollbackError = self.ledger:rollbackBatch({draw.id, purchase.id}, true)
        if not rolledBack and self.runtimeState ~= nil then
            self.runtimeState:enterSafeMode(
                "OPERATION_ROLLBACK_FAILED",
                string.format("Liability draw failed (%s) and ledger rollback failed (%s)", tostring(applyResult), tostring(rollbackError))
            )
        end
        return false, applyResult
    end

    return true, {
        groupId = groupId,
        draw = draw:clone(),
        purchase = purchase:clone(),
        liability = applyResult
    }
end
