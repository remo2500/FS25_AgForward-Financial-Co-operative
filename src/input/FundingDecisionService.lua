-- AgForward Financial Cooperative
-- Pure funding allocation for eligible crop-input purchases. No FS25 cash mutation.

AGFFundingPolicy = {
    OFF = "off",
    CASH_SHORTFALL_ONLY = "cashShortfallOnly",
    PREFER_LINE = "preferLine",
    ALWAYS_LINE = "alwaysLine"
}

AGFFundingDecisionService = {}

function AGFFundingDecisionService.decide(amount, cashAvailable, lineAvailable, eligible, policy)
    local purchaseAmount = math.abs(AGFCurrency.round(tonumber(amount) or 0))
    local cash = math.max(0, AGFCurrency.round(tonumber(cashAvailable) or 0))
    local line = math.max(0, AGFCurrency.round(tonumber(lineAvailable) or 0))
    local selectedPolicy = policy or AGFFundingPolicy.OFF

    if purchaseAmount <= 0 then
        return false, "INVALID_PURCHASE_AMOUNT"
    end

    if not eligible or selectedPolicy == AGFFundingPolicy.OFF then
        if AGFCurrency.toMinorUnits(cash) < AGFCurrency.toMinorUnits(purchaseAmount) then
            return false, "INSUFFICIENT_CASH"
        end
        return true, {
            amount = purchaseAmount,
            cashContribution = purchaseAmount,
            lineContribution = 0,
            policy = selectedPolicy,
            financed = false
        }
    end

    local cashContribution = 0
    local lineContribution = 0

    if selectedPolicy == AGFFundingPolicy.CASH_SHORTFALL_ONLY then
        cashContribution = math.min(cash, purchaseAmount)
        lineContribution = AGFCurrency.round(purchaseAmount - cashContribution)
        if AGFCurrency.toMinorUnits(lineContribution) > AGFCurrency.toMinorUnits(line) then
            return false, "INSUFFICIENT_COMBINED_LIQUIDITY"
        end
    elseif selectedPolicy == AGFFundingPolicy.PREFER_LINE then
        lineContribution = math.min(line, purchaseAmount)
        cashContribution = AGFCurrency.round(purchaseAmount - lineContribution)
        if AGFCurrency.toMinorUnits(cashContribution) > AGFCurrency.toMinorUnits(cash) then
            return false, "INSUFFICIENT_COMBINED_LIQUIDITY"
        end
    elseif selectedPolicy == AGFFundingPolicy.ALWAYS_LINE then
        if AGFCurrency.toMinorUnits(line) < AGFCurrency.toMinorUnits(purchaseAmount) then
            return false, "INSUFFICIENT_CREDIT"
        end
        lineContribution = purchaseAmount
        cashContribution = 0
    else
        return false, "UNKNOWN_FUNDING_POLICY"
    end

    local total = AGFCurrency.round(cashContribution + lineContribution)
    if not AGFCurrency.equals(total, purchaseAmount) then
        return false, "FUNDING_RECONCILIATION_FAILED"
    end

    return true, {
        amount = purchaseAmount,
        cashContribution = cashContribution,
        lineContribution = lineContribution,
        policy = selectedPolicy,
        financed = lineContribution > 0
    }
end
