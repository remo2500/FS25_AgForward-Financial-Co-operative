-- Offline tests for the whole-farm credit profile builder.

function Class(classTable)
    return {__index = classTable}
end

g_currentMission = nil

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/liabilities/LiabilityRegistry.lua")
dofile("src/credit/ExternalObligation.lua")
dofile("src/credit/ExternalObligationRegistry.lua")
dofile("src/assets/AssetRecord.lua")
dofile("src/assets/AssetRight.lua")
dofile("src/assets/Lien.lua")
dofile("src/assets/AssetRegistry.lua")
dofile("src/assets/AssetRightRegistry.lua")
dofile("src/assets/LienRegistry.lua")
dofile("src/leasing/Lease.lua")
dofile("src/leasing/LeaseRegistry.lua")
dofile("src/credit/CreditMetrics.lua")
dofile("src/credit/FarmCreditProfile.lua")
dofile("src/credit/CreditProfileBuilder.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertNear(actual, expected, tolerance, message)
    if actual == nil or math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %.10f +/- %.10f, got %s", message or "assertNear", expected, tolerance, tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local writableRuntime = {canMutate = function() return true, nil end}
local ids = AGFIdService.new()
local liabilities = AGFLiabilityRegistry.new(ids, writableRuntime)
local external = AGFExternalObligationRegistry.new(ids)
local assets = AGFAssetRegistry.new(ids, writableRuntime)
local rights = AGFAssetRightRegistry.new(ids, writableRuntime, assets)
local liens = AGFLienRegistry.new(ids, writableRuntime, assets, liabilities)
local leases = AGFLeaseRegistry.new(ids, writableRuntime, assets)
local builder = AGFCreditProfileBuilder.new(liabilities, external, assets, rights, liens, leases)

-- Secured term loan: $60k principal, $5k monthly payment, 24 periods remaining.
local termLoan = liabilities:create(1, AGFProductType.TERM_LOAN, "Equipment Note")
termLoan.principalBalance = 60000
termLoan.originalPrincipal = 80000
termLoan.scheduledPayment = 5000
termLoan.remainingTermMonths = 24
local termRegistered, termError = liabilities:register(termLoan)
assertTrue(termRegistered, termError)

-- Crop input revolver: $20k drawn against $100k line.
local ciloc = liabilities:create(1, AGFProductType.CROP_INPUT_LINE, "Crop Input Line")
ciloc.principalBalance = 20000
ciloc.creditLimit = 100000
local cilocRegistered, cilocError = liabilities:register(ciloc)
assertTrue(cilocRegistered, cilocError)

-- Existing verified base-game debt.
local baseDebt = external:create(1, AGFExternalObligationType.BASE_GAME_LOAN, "baseGame", "Existing Loan")
baseDebt.principalBalance = 20000
baseDebt.annualDebtService = 4000
baseDebt.dataQuality = AGFExternalObligationQuality.VERIFIED
local externalRegistered, externalError = external:register(baseDebt)
assertTrue(externalRegistered, externalError)

-- Economically owned $100k vehicle securing the term note.
local vehicle = assets:create(AGFAssetType.VEHICLE, "vehicle-guid-credit-profile", "Secured Tractor")
vehicle.currentValue = 100000
vehicle.linkState = AGFAssetLinkState.RESOLVED
local vehicleRegistered, vehicleError = assets:register(vehicle)
assertTrue(vehicleRegistered, vehicleError)

local owner = rights:create(vehicle.id, AGFAssetRightType.ECONOMIC_OWNER, AGFRightHolderType.FARM, 1)
local ownerRegistered, ownerError = rights:register(owner)
assertTrue(ownerRegistered, ownerError)

local lien = liens:create(vehicle.id, termLoan.id, 1)
local lienRegistered, lienError = liens:register(lien)
assertTrue(lienRegistered, lienError)

-- $1,000/month land lease affects fixed-charge coverage but is not debt/collateral.
local leasedLand = assets:create(AGFAssetType.FARMLAND, "farmland-42", "Leased Quarter")
leasedLand.currentValue = 250000
leasedLand.linkState = AGFAssetLinkState.NOT_REQUIRED
local landRegistered, landError = assets:register(leasedLand)
assertTrue(landRegistered, landError)

local landOwner = rights:create(leasedLand.id, AGFAssetRightType.ECONOMIC_OWNER, AGFRightHolderType.EXTERNAL, "landlord")
local landOwnerRegistered, landOwnerError = rights:register(landOwner)
assertTrue(landOwnerRegistered, landOwnerError)

local landTenant = rights:create(leasedLand.id, AGFAssetRightType.TENANT, AGFRightHolderType.FARM, 1)
local landTenantRegistered, landTenantError = rights:register(landTenant)
assertTrue(landTenantRegistered, landTenantError)

local lease = leases:create(leasedLand.id, AGFLeaseType.FARMLAND, 1, 1000, 36, "Land Lease")
local leaseRegistered, leaseError = leases:register(lease)
assertTrue(leaseRegistered, leaseError)
local leaseActivated, leaseActivateError = leases:activate(lease.id, 2026, 9)
assertTrue(leaseActivated, leaseActivateError)

local profile = builder:build(1, {
    asOfYear = 2026,
    asOfPeriod = 9,
    cashAndLiquidAssets = 50000,
    otherOwnedAssetValue = 50000,
    currentAssets = 80000,
    otherCurrentLiabilities = 10000,
    externalCurrentLiabilities = 5000,
    cashAvailableForDebtService = 128000,
    cashAvailableForFixedCharges = 152000
})

assertEqual(profile.dataQuality, AGFCreditDataQuality.COMPLETE, "complete represented borrower profile")
assertEqual(profile.nativeLiabilityCount, 2, "native liability count")
assertEqual(profile.externalObligationCount, 1, "external obligation count")
assertEqual(profile.activeLienCount, 1, "active lien count")
assertEqual(profile.unresolvedAssetCount, 0, "no unresolved asset links")
assertEqual(profile.metrics.totalAssets, 200000, "only economically owned asset value enters assets")
assertEqual(profile.metrics.totalLiabilities, 100000, "native plus external liabilities")
assertEqual(profile.metrics.equity, 100000, "represented equity")
assertNear(profile.metrics.debtToAssets, 0.5, 0.0000000001, "debt to assets")
assertEqual(profile.metrics.annualDebtService, 64000, "native plus external annual debt service")
assertEqual(profile.metrics.annualLeaseAndFixedCharges, 12000, "lease fixed charges")
assertNear(profile.metrics.dscr, 2.0, 0.0000000001, "DSCR")
assertNear(profile.metrics.fixedChargeCoverage, 2.0, 0.0000000001, "fixed charge coverage")
assertNear(profile.metrics.ltv, 0.6, 0.0000000001, "secured LTV")
assertNear(profile.metrics.revolverUtilization, 0.2, 0.0000000001, "revolver utilization")
assertEqual(profile.metrics.workingCapital, 5000, "working capital")
assertNear(profile.metrics.currentRatio, 80000 / 75000, 0.0000000001, "current ratio")
assertNear(profile.metrics.liquidityCoverage, 130000 / 76000, 0.0000000001, "liquidity coverage")

-- Leased land must not be counted as owned collateral/assets.
assertEqual(profile.metadata.ownedRegisteredAssetValue, "100000", "leased land excluded from owned registered asset value")
assertEqual(profile.metadata.annualLeaseCharges, "12000", "lease charge metadata")
assertEqual(profile.metadata.undrawnCommittedCredit, "80000", "undrawn revolver metadata")

-- Unresolved collateral degrades profile quality without deleting the asset or debt.
local unresolvedSet, unresolvedError = assets:setRuntimeLink(vehicle.id, nil)
assertTrue(unresolvedSet, unresolvedError)
local unresolvedProfile = builder:build(1, {
    cashAndLiquidAssets = 50000,
    otherOwnedAssetValue = 50000,
    currentAssets = 80000,
    otherCurrentLiabilities = 10000,
    externalCurrentLiabilities = 5000,
    cashAvailableForDebtService = 128000,
    cashAvailableForFixedCharges = 152000
})
assertEqual(unresolvedProfile.dataQuality, AGFCreditDataQuality.ASSET_LINK_UNRESOLVED, "unresolved collateral degrades data quality")
assertEqual(unresolvedProfile.unresolvedAssetCount, 1, "unresolved asset counted")
assertEqual(unresolvedProfile.metrics.totalLiabilities, 100000, "unresolved asset does not erase debt")

-- Unknown external debt has higher data-quality severity than unresolved collateral.
local unknownDebt = external:create(1, AGFExternalObligationType.THIRD_PARTY_DEBT, "unknownMod", "Unknown External Debt")
unknownDebt.dataQuality = AGFExternalObligationQuality.UNKNOWN
local unknownRegistered, unknownError = external:register(unknownDebt)
assertTrue(unknownRegistered, unknownError)
local unknownProfile = builder:build(1, {
    cashAndLiquidAssets = 50000,
    otherOwnedAssetValue = 50000,
    currentAssets = 80000,
    cashAvailableForDebtService = 128000,
    cashAvailableForFixedCharges = 152000
})
assertEqual(unknownProfile.dataQuality, AGFCreditDataQuality.UNKNOWN_EXTERNAL_DEBT, "unknown external debt receives highest quality warning")

print("offline_credit_profile_tests: PASS")
