-- AgForward Financial Cooperative
-- Pure staged project draw transaction plan. The approved commitment is separate
-- from advanced principal. No construction, cash, liability, or ledger mutation occurs here.

AGFProjectDrawPlanService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function positiveMoney(value)
    local amount = money(value)
    if amount == nil or amount <= 0 then return nil end
    return amount
end

function AGFProjectDrawPlanService.plan(liability, requestedDraw, projectUseAmount, context)
    context = context or {}
    if liability == nil or liability.id == nil then return false, "PROJECT_LIABILITY_REQUIRED" end
    if liability.productType ~= AGFProductType.PROJECT_FINANCE then return false, "WRONG_PROJECT_PRODUCT" end
    if liability.status ~= nil and liability.status ~= "active" then return false, "PROJECT_FACILITY_NOT_ACTIVE" end

    local commitment = positiveMoney(liability.commitmentAmount or context.commitmentAmount)
    local principalBefore = money(liability.principalBalance or 0)
    local draw = positiveMoney(requestedDraw)
    local useAmount = positiveMoney(projectUseAmount)
    if commitment == nil then return false, "PROJECT_COMMITMENT_REQUIRED" end
    if principalBefore == nil then return false, "INVALID_PROJECT_PRINCIPAL" end
    if draw == nil then return false, "INVALID_PROJECT_DRAW" end
    if useAmount == nil then return false, "INVALID_PROJECT_USE" end
    if AGFCurrency.toMinorUnits(principalBefore) > AGFCurrency.toMinorUnits(commitment) then
        return false, "PROJECT_PRINCIPAL_EXCEEDS_COMMITMENT"
    end
    if AGFCurrency.toMinorUnits(draw) > AGFCurrency.toMinorUnits(AGFCurrency.round(commitment - principalBefore)) then
        return false, "PROJECT_COMMITMENT_EXCEEDED"
    end
    if AGFCurrency.toMinorUnits(draw) > AGFCurrency.toMinorUnits(useAmount) then
        return false, "PROJECT_DRAW_EXCEEDS_CURRENT_USE"
    end

    local cashContribution = AGFCurrency.round(useAmount - draw)
    if context.cashAvailable ~= nil then
        local cashAvailable = money(context.cashAvailable)
        if cashAvailable == nil then return false, "INVALID_AVAILABLE_CASH" end
        if AGFCurrency.toMinorUnits(cashContribution) > AGFCurrency.toMinorUnits(cashAvailable) then
            return false, "INSUFFICIENT_CASH_FOR_PROJECT_USE"
        end
    end

    local principalAfter = AGFCurrency.round(principalBefore + draw)
    local undrawnAfter = AGFCurrency.round(commitment - principalAfter)
    local groupId = context.groupId or "PENDING_PROJECT_DRAW_GROUP"
    local assetId = context.assetId or liability.assetId

    local ledgerIntents = {
        {
            transactionType = AGFTransactionType.LOAN_PROCEEDS,
            amount = draw,
            fundingSource = AGFFundingSource.PROJECT_FINANCE,
            farmId = liability.farmId,
            liabilityId = liability.id,
            assetId = assetId,
            groupId = groupId,
            economicRole = "projectDraw"
        },
        {
            transactionType = AGFTransactionType.ASSET_PURCHASE,
            amount = -useAmount,
            farmId = liability.farmId,
            liabilityId = liability.id,
            assetId = assetId,
            groupId = groupId,
            economicRole = "projectUse",
            fundingBreakdown = {
                cash = cashContribution,
                financed = draw,
                financeSource = AGFFundingSource.PROJECT_FINANCE
            },
            metadata = {
                useType = context.useType,
                reference = context.reference,
                description = context.description
            }
        }
    }

    local ledgerNet = AGFCurrency.round(draw - useAmount)
    local expectedCashDelta = -cashContribution
    if not AGFCurrency.equals(ledgerNet, expectedCashDelta) then
        return false, "PROJECT_DRAW_RECONCILIATION_FAILED"
    end

    return true, {
        planType = "projectDraw",
        farmId = liability.farmId,
        liabilityId = liability.id,
        assetId = assetId,
        groupId = groupId,
        commitmentAmount = commitment,
        principalBefore = principalBefore,
        drawAmount = draw,
        projectUseAmount = useAmount,
        cashContribution = cashContribution,
        principalAfter = principalAfter,
        undrawnCommitmentAfter = undrawnAfter,
        fsCashDelta = expectedCashDelta,
        ledgerNet = ledgerNet,
        ledgerIntents = ledgerIntents,
        liabilityMutation = {
            principalDelta = draw,
            principalAfter = principalAfter,
            undrawnCommitmentAfter = undrawnAfter
        },
        requiresInterestAccrualRecalculation = true
    }
end
