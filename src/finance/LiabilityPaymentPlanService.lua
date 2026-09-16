-- AgForward Financial Cooperative
-- Pure bridge between payment allocation and future coordinated ledger posting.
-- It never mutates a liability, posts a journal entry, or moves FS25 cash.

AGFLiabilityPaymentPlanService = {}

local function money(value)
    return math.max(0, AGFCurrency.round(tonumber(value) or 0))
end

local function buildIntent(transactionType, amount, liabilityId, fundingSource, expenseCategory, principal, interest, fees)
    return {
        transactionType = transactionType,
        amount = -money(amount),
        liabilityId = liabilityId,
        fundingSource = fundingSource,
        expenseCategory = expenseCategory,
        principal = money(principal),
        interest = money(interest),
        fees = money(fees),
        economicRole = "debtService"
    }
end

function AGFLiabilityPaymentPlanService.plan(liability, paymentAmount, allocationOrder, fundingSource)
    if liability == nil or liability.id == nil then
        return false, "INVALID_LIABILITY"
    end
    if liability.isOpen ~= nil and not liability:isOpen() then
        return false, "LIABILITY_NOT_OPEN"
    end

    local requested = money(paymentAmount)
    if requested <= 0 then return false, "INVALID_PAYMENT_AMOUNT" end

    local principalBefore = money(liability.principalBalance)
    local interestBefore = money(liability.accruedInterest)
    local feesBefore = money(liability.accruedFees)
    local totalBefore = AGFCurrency.round(principalBefore + interestBefore + feesBefore)
    if totalBefore <= 0 then return false, "NO_OUTSTANDING_BALANCE" end

    local allocated, allocation = AGFPaymentAllocationService.allocate(requested, {
        principal = principalBefore,
        interest = interestBefore,
        fees = feesBefore
    }, allocationOrder)
    if not allocated then return false, allocation end

    local accepted = AGFCurrency.round(
        allocation.appliedPrincipal + allocation.appliedInterest + allocation.appliedFees
    )
    if accepted <= 0 then return false, "NO_APPLICABLE_PAYMENT" end

    local source = fundingSource or AGFFundingSource.CASH
    local intents = {}

    if allocation.appliedFees > 0 then
        table.insert(intents, buildIntent(
            AGFTransactionType.FINANCE_FEE,
            allocation.appliedFees,
            liability.id,
            source,
            AGFExpenseCategory.FINANCE_FEE,
            0,
            0,
            allocation.appliedFees
        ))
    end

    if allocation.appliedInterest > 0 then
        table.insert(intents, buildIntent(
            AGFTransactionType.INTEREST_PAYMENT,
            allocation.appliedInterest,
            liability.id,
            source,
            AGFExpenseCategory.INTEREST,
            0,
            allocation.appliedInterest,
            0
        ))
    end

    if allocation.appliedPrincipal > 0 then
        table.insert(intents, buildIntent(
            AGFTransactionType.PRINCIPAL_PAYMENT,
            allocation.appliedPrincipal,
            liability.id,
            source,
            nil,
            allocation.appliedPrincipal,
            0,
            0
        ))
    end

    return true, {
        liabilityId = liability.id,
        farmId = liability.farmId,
        productType = liability.productType,
        allocationOrder = allocation.order,
        fundingSource = source,
        requestedPayment = requested,
        acceptedPayment = accepted,
        unappliedAmount = allocation.unappliedAmount,
        principalBefore = principalBefore,
        interestBefore = interestBefore,
        feesBefore = feesBefore,
        totalOutstandingBefore = totalBefore,
        appliedPrincipal = allocation.appliedPrincipal,
        appliedInterest = allocation.appliedInterest,
        appliedFees = allocation.appliedFees,
        principalAfter = allocation.principalAfter,
        interestAfter = allocation.interestAfter,
        feesAfter = allocation.feesAfter,
        totalOutstandingAfter = allocation.totalOutstandingAfter,
        fullyPaid = AGFCurrency.equals(allocation.totalOutstandingAfter, 0),
        journalIntents = intents
    }
end
