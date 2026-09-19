-- Offline financial-statement validation. Leased/operated assets are not owned assets.

function Class(classTable)
    return {__index = classTable}
end

g_currentMission = nil

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/assets/AssetRecord.lua")
dofile("src/assets/AssetRegistry.lua")
dofile("src/assets/AssetRight.lua")
dofile("src/assets/AssetRightRegistry.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/liabilities/LiabilityRegistry.lua")
dofile("src/credit/ExternalObligation.lua")
dofile("src/credit/ExternalObligationRegistry.lua")
dofile("src/leasing/Lease.lua")
dofile("src/leasing/LeaseRegistry.lua")
dofile("src/reporting/FinancialStatementService.lua")

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
local rights = AGFAssetRightRegistry.new(ids, runtime, assets)
local liabilities = AGFLiabilityRegistry.new(ids, runtime)
local external = AGFExternalObligationRegistry.new(ids)
local leases = AGFLeaseRegistry.new(ids, runtime, assets)

local vehicle = assert(assets:create(AGFAssetType.VEHICLE, "vehicle-1", "Owned tractor"))
vehicle.currentValue = 200000
vehicle.acquisitionCost = 250000
vehicle.linkState = AGFAssetLinkState.RESOLVED
assertTrue(assets:register(vehicle), "vehicle registered")
local vehicleOwner = assert(rights:create(vehicle.id, AGFAssetRightType.ECONOMIC_OWNER, AGFRightHolderType.FARM, 1))
assertTrue(rights:register(vehicleOwner), "vehicle ownership registered")

local farmland = assert(assets:create(AGFAssetType.FARMLAND, "land-1", "Rented quarter"))
farmland.currentValue = 300000
farmland.acquisitionCost = 300000
farmland.linkState = AGFAssetLinkState.RESOLVED
assertTrue(assets:register(farmland), "farmland registered")
local landOwner = assert(rights:create(farmland.id, AGFAssetRightType.ECONOMIC_OWNER, AGFRightHolderType.EXTERNAL, "landlord"))
assertTrue(rights:register(landOwner), "external land owner registered")
local tenant = assert(rights:create(farmland.id, AGFAssetRightType.TENANT, AGFRightHolderType.FARM, 1))
assertTrue(rights:register(tenant), "tenant right registered")

local loan = assert(liabilities:create(1, AGFProductType.EQUIPMENT_FINANCE, "Tractor loan"))
loan.principalBalance = 80000
loan.accruedInterest = 1000
assertTrue(liabilities:register(loan), "native loan registered")

local ext = assert(external:create(1, AGFExternalObligationType.BASE_GAME_LOAN, "baseGame", "Base loan"))
ext.principalBalance = 20000
ext.annualDebtService = 6000
ext.annualFixedCharge = 10000
ext.dataQuality = AGFExternalObligationQuality.VERIFIED
assertTrue(external:register(ext), "external debt registered")

local lease = assert(leases:create(farmland.id, AGFLeaseType.FARMLAND, 1, 5000, 36, "Quarter rent", 12))
assertTrue(leases:register(lease), "lease registered")
assertTrue(leases:activate(lease.id, 2026, 9), "lease activated")

local statements = AGFFinancialStatementService.new(assets, rights, liabilities, external, leases, nil)
local statement = statements:build(1, {
    cashBalance = 100000,
    otherOwnedAssetValue = 50000,
    currentYear = 2026,
    currentPeriod = 9
})

assertEqual(statement.assets.registered, 200000, "only economically owned registered asset counted")
assertEqual(statement.assets.byType[AGFAssetType.VEHICLE], 200000, "owned vehicle value")
assertEqual(statement.assets.byType[AGFAssetType.FARMLAND], nil, "leased farmland excluded from owned assets")
assertEqual(statement.assets.total, 350000, "total assets")
assertEqual(statement.liabilities.nativeOutstanding, 81000, "native outstanding")
assertEqual(statement.liabilities.externalPrincipal, 20000, "external principal")
assertEqual(statement.liabilities.total, 101000, "total liabilities")
assertEqual(statement.equity, 249000, "represented equity")
assertEqual(statement.leaseAnnualFixedCharges, 60000, "lease annual fixed charges")
assertEqual(statement.annualFixedCharges, 70000, "lease plus external fixed charges")
assertEqual(statement.assets.ownedAssetCount, 1, "owned asset count")
assertTrue(statement.debtToAssets > 0.28 and statement.debtToAssets < 0.30, "debt-to-assets ratio")

local missingCash = statements:build(1, {otherOwnedAssetValue = 50000})
assertEqual(missingCash.dataQuality.complete, false, "missing cash lowers data quality")
assertEqual(missingCash.dataQuality.issues[1], "CASH_BALANCE_NOT_SUPPLIED", "missing cash issue")

print("offline_financial_statement_tests: PASS")
