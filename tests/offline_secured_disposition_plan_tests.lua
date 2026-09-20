-- Offline secured asset sale/payoff/release transaction planning.

function Class(classTable)
    return {__index = classTable}
end

g_currentMission = nil

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/liabilities/LiabilityRegistry.lua")
dofile("src/assets/AssetRecord.lua")
dofile("src/assets/AssetRegistry.lua")
dofile("src/assets/AssetRight.lua")
dofile("src/assets/AssetRightRegistry.lua")
dofile("src/assets/Lien.lua")
dofile("src/assets/LienRegistry.lua")
dofile("src/finance/PaymentAllocationService.lua")
dofile("src/finance/LiabilityPaymentPlanService.lua")
dofile("src/finance/PrepaymentPolicyService.lua")
dofile("src/finance/LiabilityPayoffQuoteService.lua")
dofile("src/assets/SecuredDispositionService.lua")
dofile("src/assets/SecuredDispositionExecutionPlanService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local runtime = {canMutate = function() return true, nil end}
local ids = AGFIdService.new()
local assets = AGFAssetRegistry.new(ids, runtime)
local liabilities = AGFLiabilityRegistry.new(ids, runtime)
local rights = AGFAssetRightRegistry.new(ids, runtime, assets)
local liens = AGFLienRegistry.new(ids, runtime, assets, liabilities)

local asset = assert(assets:create(AGFAssetType.VEHICLE, "veh-sale-1", "Financed tractor"))
asset.currentValue = 80000
asset.linkState = AGFAssetLinkState.RESOLVED
assertTrue(assets:register(asset), "asset registered")
local owner = assert(rights:create(asset.id, AGFAssetRightType.ECONOMIC_OWNER, AGFRightHolderType.FARM, 1))
assertTrue(rights:register(owner), "owner right registered")

local loan = assert(liabilities:create(1, AGFProductType.EQUIPMENT_FINANCE, "Tractor note"))
loan.status = AGFLiabilityStatus.ACTIVE
loan.principalBalance = 60000
loan.accruedInterest = 1000
loan.accruedFees = 500
assertTrue(liabilities:register(loan), "loan registered")

local lien = assert(liens:create(asset.id, loan.id, 1))
lien.securedAmountCap = 0
assertTrue(liens:register(lien), "lien registered")

local disposition = AGFSecuredDispositionService.new(assets, liens, liabilities, rights)
local preflightOk, preflight = disposition:preflight(asset.id, 80000, 0, 1)
assertTrue(preflightOk, "sale preflight")
assertTrue(preflight.allowed, "sale allowed before contractual charge check")
assertEqual(preflight.lienPayoff, 61500, "base lien payoff")

local storedLoan = liabilities:get(loan.id)
local openOk, openPlan = AGFSecuredDispositionExecutionPlanService.build(
    preflight,
    {[loan.id] = storedLoan},
    {[loan.id] = {type = AGFPrepaymentPolicyType.OPEN}},
    {farmId = 1, groupId = "GRP-SALE-OPEN"}
)
assertTrue(openOk, "open-prepay sale plan")
assertEqual(openPlan.grossProceeds, 80000, "gross sale")
assertEqual(openPlan.totalPayoffCash, 61500, "open payoff cash")
assertEqual(openPlan.netCashToOwner, 18500, "net owner cash")
assertEqual(openPlan.requiredCashContribution, 0, "no cash contribution")
assertEqual(openPlan.fsCashDelta, 18500, "net FS cash")
assertEqual(openPlan.ledgerNet, 18500, "ledger net")
assertEqual(#openPlan.liabilityPayoffPlans, 1, "one payoff")
assertTrue(openPlan.liabilityPayoffPlans[1].paymentPlan.fullyPaid, "liability fully paid")
assertEqual(#openPlan.lienReleaseIntents, 1, "lien released after payoff")
assertEqual(openPlan.journalIntents[1].transactionType, AGFTransactionType.ASSET_SALE, "sale proceeds first")

local chargedOk, chargedPlan = AGFSecuredDispositionExecutionPlanService.build(
    preflight,
    {[loan.id] = storedLoan},
    {[loan.id] = {
        type = AGFPrepaymentPolicyType.CLOSED,
        chargeRate = 0.02,
        fixedCharge = 100
    }},
    {farmId = 1, groupId = "GRP-SALE-CHARGED"}
)
assertTrue(chargedOk, "charged-prepay sale plan")
assertEqual(chargedPlan.totalPayoffCash, 62800, "payoff including charge")
assertEqual(chargedPlan.netCashToOwner, 17200, "net owner cash after charge")
assertEqual(chargedPlan.journalIntents[#chargedPlan.journalIntents].transactionType, AGFTransactionType.FINANCE_FEE, "prepay charge separate fee")
assertEqual(chargedPlan.journalIntents[#chargedPlan.journalIntents].amount, -1300, "prepay fee amount")

local lowProceedsOk, lowPreflight = disposition:preflight(asset.id, 50000, 10000, 1)
assertTrue(lowProceedsOk, "low-proceeds preflight computes base cash need")
assertEqual(lowPreflight.allowed, false, "base preflight already disallows insufficient cash")

local nearPreflightOk, nearPreflight = disposition:preflight(asset.id, 55000, 6500, 1)
assertTrue(nearPreflightOk, "near-payoff preflight")
assertTrue(nearPreflight.allowed, "base payoff just clears with cash")
local chargedFailOk, chargedFailError = AGFSecuredDispositionExecutionPlanService.build(
    nearPreflight,
    {[loan.id] = storedLoan},
    {[loan.id] = {
        type = AGFPrepaymentPolicyType.CLOSED,
        chargeRate = 0.02,
        fixedCharge = 100
    }},
    {farmId = 1}
)
assertEqual(chargedFailOk, false, "prepayment charge can make disposition infeasible")
assertEqual(chargedFailError, "INSUFFICIENT_CASH_TO_CLEAR_PAYOFF_AND_CHARGES", "charged cash shortfall error")

local noPolicyOk, noPolicyError = AGFSecuredDispositionExecutionPlanService.build(
    preflight,
    {[loan.id] = storedLoan},
    {},
    {farmId = 1}
)
assertEqual(noPolicyOk, false, "unknown payoff policy rejected")
assertEqual(noPolicyError, "PREPAYMENT_POLICY_REQUIRED:" .. loan.id, "payoff policy error")

-- A lien cap below total obligation needs a separate partial-release policy.
local cappedLien = liens:get(lien.id)
cappedLien.securedAmountCap = 50000
-- Build a preflight-shaped row directly; authoritative registry mutation is not needed for this pure test.
local cappedPreflight = {
    allowed = true,
    assetId = asset.id,
    grossProceeds = 80000,
    availableCash = 0,
    lienBreakdown = {
        {lienId = lien.id, liabilityId = loan.id, priority = 1, payoff = 50000}
    }
}
local cappedOk, cappedError = AGFSecuredDispositionExecutionPlanService.build(
    cappedPreflight,
    {[loan.id] = storedLoan},
    {[loan.id] = {type = AGFPrepaymentPolicyType.OPEN}},
    {farmId = 1}
)
assertEqual(cappedOk, false, "capped lien partial release is not guessed")
assertEqual(cappedError, "CAPPED_LIEN_DISPOSITION_POLICY_REQUIRED:" .. lien.id, "capped lien policy error")

print("offline_secured_disposition_plan_tests: PASS")
