-- AgForward Financial Cooperative
-- Pure calculation for optional harvest/grain-sale proceeds sweeps on revolving
-- operating credit. It does not intercept sales or move cash.

AGFHarvestSweepService = {}

function AGFHarvestSweepService.calculate(saleProceeds, principalBalance, policy)
    policy = policy or {}
    local proceeds = math.max(0, AGFCurrency.round(tonumber(saleProceeds) or 0))
    local principal = math.max(0, AGFCurrency.round(tonumber(principalBalance) or 0))
    local sweepPercent = tonumber(policy.sweepPercent or 0)
    local cashRetention = math.max(0, AGFCurrency.round(tonumber(policy.cashRetentionAmount) or 0))
    local minimumSweep = math.max(0, AGFCurrency.round(tonumber(policy.minimumSweepAmount) or 0))
    local maximumSweep = policy.maximumSweepAmount ~= nil and math.max(0, AGFCurrency.round(tonumber(policy.maximumSweepAmount) or 0)) or nil

    if sweepPercent == nil or sweepPercent < 0 or sweepPercent > 1 then
        return false, "INVALID_SWEEP_PERCENT"
    end

    if proceeds <= 0 or principal <= 0 or sweepPercent == 0 then
        return true, {
            saleProceeds = proceeds,
            eligibleProceeds = 0,
            proposedSweep = 0,
            remainingPrincipal = principal,
            retainedCash = proceeds
        }
    end

    local eligibleProceeds = math.max(0, AGFCurrency.round(proceeds - cashRetention))
    local proposed = AGFCurrency.round(eligibleProceeds * sweepPercent)
    proposed = math.min(proposed, principal)
    if maximumSweep ~= nil then proposed = math.min(proposed, maximumSweep) end

    if proposed > 0 and proposed < minimumSweep then
        proposed = 0
    end

    return true, {
        saleProceeds = proceeds,
        eligibleProceeds = eligibleProceeds,
        sweepPercent = sweepPercent,
        proposedSweep = AGFCurrency.round(proposed),
        remainingPrincipal = AGFCurrency.round(principal - proposed),
        retainedCash = AGFCurrency.round(proceeds - proposed),
        cashRetentionAmount = cashRetention,
        minimumSweepAmount = minimumSweep,
        maximumSweepAmount = maximumSweep
    }
end
