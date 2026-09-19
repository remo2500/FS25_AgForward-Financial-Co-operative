-- AgForward Financial Cooperative
-- Pure whole-farm credit metrics. This module contains no approval policy.

AGFCreditMetrics = {}

local function normalize(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local function ratio(numerator, denominator)
    numerator = normalize(numerator)
    denominator = normalize(denominator)
    if numerator == nil or denominator == nil then
        return nil
    end
    if math.abs(denominator) < 0.0000001 then
        return nil
    end
    return numerator / denominator
end

function AGFCreditMetrics.calculateDSCR(cashAvailableForDebtService, annualDebtService)
    local debtService = normalize(annualDebtService)
    if debtService == nil or debtService <= 0 then
        return nil
    end
    return ratio(cashAvailableForDebtService, debtService)
end

function AGFCreditMetrics.calculateFixedChargeCoverage(cashAvailableForFixedCharges, annualDebtService, annualLeaseAndFixedCharges)
    local debtService = normalize(annualDebtService) or 0
    local fixedCharges = normalize(annualLeaseAndFixedCharges) or 0
    local denominator = debtService + fixedCharges
    if denominator <= 0 then
        return nil
    end
    return ratio(cashAvailableForFixedCharges, denominator)
end

function AGFCreditMetrics.calculateDebtToAssets(totalLiabilities, totalAssets)
    local assets = normalize(totalAssets)
    if assets == nil or assets <= 0 then
        return nil
    end
    return ratio(totalLiabilities, assets)
end

function AGFCreditMetrics.calculateLoanToValue(securedDebt, collateralValue)
    local collateral = normalize(collateralValue)
    if collateral == nil or collateral <= 0 then
        return nil
    end
    return ratio(securedDebt, collateral)
end

function AGFCreditMetrics.calculateWorkingCapital(currentAssets, currentLiabilities)
    local assets = normalize(currentAssets)
    local liabilities = normalize(currentLiabilities)
    if assets == nil or liabilities == nil then
        return nil
    end
    return AGFCurrency.round(assets - liabilities)
end

function AGFCreditMetrics.calculateCurrentRatio(currentAssets, currentLiabilities)
    local liabilities = normalize(currentLiabilities)
    if liabilities == nil or liabilities <= 0 then
        return nil
    end
    return ratio(currentAssets, liabilities)
end

function AGFCreditMetrics.calculateRevolverUtilization(principalBalance, creditLimit)
    local limit = normalize(creditLimit)
    if limit == nil or limit <= 0 then
        return nil
    end
    local balance = normalize(principalBalance)
    if balance == nil then
        return nil
    end
    return math.max(0, balance) / limit
end

function AGFCreditMetrics.calculateLiquidityCoverage(cashAndLiquidAssets, undrawnCommittedCredit, next12MonthObligations)
    local obligations = normalize(next12MonthObligations)
    if obligations == nil or obligations <= 0 then
        return nil
    end

    local liquid = normalize(cashAndLiquidAssets) or 0
    local undrawn = normalize(undrawnCommittedCredit) or 0
    return ratio(liquid + math.max(0, undrawn), obligations)
end

function AGFCreditMetrics.calculateEquity(totalAssets, totalLiabilities)
    local assets = normalize(totalAssets)
    local liabilities = normalize(totalLiabilities)
    if assets == nil or liabilities == nil then
        return nil
    end
    return AGFCurrency.round(assets - liabilities)
end

function AGFCreditMetrics.calculateEquityRatio(totalAssets, totalLiabilities)
    local assets = normalize(totalAssets)
    if assets == nil or assets <= 0 then
        return nil
    end
    local equity = AGFCreditMetrics.calculateEquity(totalAssets, totalLiabilities)
    if equity == nil then
        return nil
    end
    return equity / assets
end

function AGFCreditMetrics.buildSnapshot(inputs)
    inputs = inputs or {}

    local snapshot = {
        totalAssets = AGFCurrency.round(inputs.totalAssets or 0),
        totalLiabilities = AGFCurrency.round(inputs.totalLiabilities or 0),
        currentAssets = AGFCurrency.round(inputs.currentAssets or 0),
        currentLiabilities = AGFCurrency.round(inputs.currentLiabilities or 0),
        annualDebtService = AGFCurrency.round(inputs.annualDebtService or 0),
        annualLeaseAndFixedCharges = AGFCurrency.round(inputs.annualLeaseAndFixedCharges or 0),
        cashAvailableForDebtService = AGFCurrency.round(inputs.cashAvailableForDebtService or 0),
        cashAvailableForFixedCharges = AGFCurrency.round(inputs.cashAvailableForFixedCharges or inputs.cashAvailableForDebtService or 0),
        securedDebt = AGFCurrency.round(inputs.securedDebt or 0),
        collateralValue = AGFCurrency.round(inputs.collateralValue or 0),
        revolverPrincipal = AGFCurrency.round(inputs.revolverPrincipal or 0),
        revolverLimit = AGFCurrency.round(inputs.revolverLimit or 0),
        cashAndLiquidAssets = AGFCurrency.round(inputs.cashAndLiquidAssets or 0),
        undrawnCommittedCredit = AGFCurrency.round(inputs.undrawnCommittedCredit or 0),
        next12MonthObligations = AGFCurrency.round(inputs.next12MonthObligations or 0)
    }

    snapshot.equity = AGFCreditMetrics.calculateEquity(snapshot.totalAssets, snapshot.totalLiabilities)
    snapshot.equityRatio = AGFCreditMetrics.calculateEquityRatio(snapshot.totalAssets, snapshot.totalLiabilities)
    snapshot.debtToAssets = AGFCreditMetrics.calculateDebtToAssets(snapshot.totalLiabilities, snapshot.totalAssets)
    snapshot.workingCapital = AGFCreditMetrics.calculateWorkingCapital(snapshot.currentAssets, snapshot.currentLiabilities)
    snapshot.currentRatio = AGFCreditMetrics.calculateCurrentRatio(snapshot.currentAssets, snapshot.currentLiabilities)
    snapshot.dscr = AGFCreditMetrics.calculateDSCR(snapshot.cashAvailableForDebtService, snapshot.annualDebtService)
    snapshot.fixedChargeCoverage = AGFCreditMetrics.calculateFixedChargeCoverage(
        snapshot.cashAvailableForFixedCharges,
        snapshot.annualDebtService,
        snapshot.annualLeaseAndFixedCharges
    )
    snapshot.ltv = AGFCreditMetrics.calculateLoanToValue(snapshot.securedDebt, snapshot.collateralValue)
    snapshot.revolverUtilization = AGFCreditMetrics.calculateRevolverUtilization(snapshot.revolverPrincipal, snapshot.revolverLimit)
    snapshot.liquidityCoverage = AGFCreditMetrics.calculateLiquidityCoverage(
        snapshot.cashAndLiquidAssets,
        snapshot.undrawnCommittedCredit,
        snapshot.next12MonthObligations
    )

    return snapshot
end
