-- AgForward Financial Cooperative
-- Pure before/after underwriting projection. This module does not approve loans;
-- it shows how a proposed obligation changes the borrower metrics.

AGFProFormaUnderwritingService = {}

local function copyInputs(inputs)
    local copy = {}
    for key, value in pairs(inputs or {}) do copy[key] = value end
    return copy
end

function AGFProFormaUnderwritingService.project(currentInputs, proposal)
    currentInputs = currentInputs or {}
    proposal = proposal or {}

    local before = AGFCreditMetrics.buildSnapshot(currentInputs)
    local afterInputs = copyInputs(currentInputs)

    local newPrincipal = AGFCurrency.round(proposal.newPrincipal or 0)
    local newAnnualDebtService = AGFCurrency.round(proposal.newAnnualDebtService or 0)
    local newCurrentLiability = AGFCurrency.round(proposal.newCurrentLiability or 0)
    local cashDownPayment = AGFCurrency.round(proposal.cashDownPayment or 0)
    local acquiredAssetValue = AGFCurrency.round(proposal.acquiredAssetValue or 0)
    local newSecuredDebt = AGFCurrency.round(proposal.newSecuredDebt or newPrincipal)
    local newEligibleCollateral = AGFCurrency.round(proposal.newEligibleCollateral or acquiredAssetValue)
    local newRevolverPrincipal = AGFCurrency.round(proposal.newRevolverPrincipal or 0)
    local newRevolverLimit = AGFCurrency.round(proposal.newRevolverLimit or 0)
    local newAnnualFixedCharge = AGFCurrency.round(proposal.newAnnualFixedCharge or 0)

    afterInputs.totalAssets = AGFCurrency.round((afterInputs.totalAssets or 0) + acquiredAssetValue - cashDownPayment)
    afterInputs.totalLiabilities = AGFCurrency.round((afterInputs.totalLiabilities or 0) + newPrincipal)
    afterInputs.currentAssets = AGFCurrency.round((afterInputs.currentAssets or 0) - cashDownPayment)
    afterInputs.currentLiabilities = AGFCurrency.round((afterInputs.currentLiabilities or 0) + newCurrentLiability)
    afterInputs.annualDebtService = AGFCurrency.round((afterInputs.annualDebtService or 0) + newAnnualDebtService)
    afterInputs.annualLeaseAndFixedCharges = AGFCurrency.round((afterInputs.annualLeaseAndFixedCharges or 0) + newAnnualFixedCharge)
    afterInputs.securedDebt = AGFCurrency.round((afterInputs.securedDebt or 0) + newSecuredDebt)
    afterInputs.collateralValue = AGFCurrency.round((afterInputs.collateralValue or 0) + newEligibleCollateral)
    afterInputs.revolverPrincipal = AGFCurrency.round((afterInputs.revolverPrincipal or 0) + newRevolverPrincipal)
    afterInputs.revolverLimit = AGFCurrency.round((afterInputs.revolverLimit or 0) + newRevolverLimit)
    afterInputs.cashAndLiquidAssets = AGFCurrency.round((afterInputs.cashAndLiquidAssets or 0) - cashDownPayment)
    afterInputs.next12MonthObligations = AGFCurrency.round((afterInputs.next12MonthObligations or 0) + newAnnualDebtService + newAnnualFixedCharge)

    local after = AGFCreditMetrics.buildSnapshot(afterInputs)

    return {
        before = before,
        after = after,
        proposal = {
            newPrincipal = newPrincipal,
            newAnnualDebtService = newAnnualDebtService,
            newCurrentLiability = newCurrentLiability,
            cashDownPayment = cashDownPayment,
            acquiredAssetValue = acquiredAssetValue,
            newSecuredDebt = newSecuredDebt,
            newEligibleCollateral = newEligibleCollateral,
            newRevolverPrincipal = newRevolverPrincipal,
            newRevolverLimit = newRevolverLimit,
            newAnnualFixedCharge = newAnnualFixedCharge
        },
        deltas = {
            debtToAssets = after.debtToAssets ~= nil and before.debtToAssets ~= nil and (after.debtToAssets - before.debtToAssets) or nil,
            dscr = after.dscr ~= nil and before.dscr ~= nil and (after.dscr - before.dscr) or nil,
            fixedChargeCoverage = after.fixedChargeCoverage ~= nil and before.fixedChargeCoverage ~= nil and (after.fixedChargeCoverage - before.fixedChargeCoverage) or nil,
            workingCapital = after.workingCapital ~= nil and before.workingCapital ~= nil and AGFCurrency.round(after.workingCapital - before.workingCapital) or nil,
            ltv = after.ltv ~= nil and before.ltv ~= nil and (after.ltv - before.ltv) or nil,
            liquidityCoverage = after.liquidityCoverage ~= nil and before.liquidityCoverage ~= nil and (after.liquidityCoverage - before.liquidityCoverage) or nil
        }
    }
end

function AGFProFormaUnderwritingService.fromLoanQuote(currentInputs, quote, options)
    if quote == nil or quote.amortization == nil then
        return nil, "INVALID_LOAN_QUOTE"
    end
    options = options or {}

    local annualDebtService = 0
    local schedule = quote.amortization.schedule or {}
    local periodsToMeasure = math.min(12, #schedule)
    for index = 1, periodsToMeasure do
        annualDebtService = AGFCurrency.round(annualDebtService + (schedule[index].totalPayment or 0))
    end

    local principalDueWithin12 = 0
    for index = 1, periodsToMeasure do
        local row = schedule[index]
        principalDueWithin12 = AGFCurrency.round(
            principalDueWithin12 + (row.regularPrincipal or 0) + (row.balloonPayment or 0)
        )
    end

    return AGFProFormaUnderwritingService.project(currentInputs, {
        newPrincipal = quote.principal or 0,
        newAnnualDebtService = annualDebtService,
        newCurrentLiability = options.currentLiabilityAmount or principalDueWithin12,
        cashDownPayment = quote.downPayment or 0,
        acquiredAssetValue = options.acquiredAssetValue or quote.purchasePrice or 0,
        newSecuredDebt = options.newSecuredDebt or quote.principal or 0,
        newEligibleCollateral = options.newEligibleCollateral or options.acquiredAssetValue or quote.purchasePrice or 0,
        newAnnualFixedCharge = options.newAnnualFixedCharge or 0
    }), nil
end
