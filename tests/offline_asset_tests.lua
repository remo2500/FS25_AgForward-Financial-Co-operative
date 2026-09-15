-- Offline model validation for AgForward asset/right/lien foundations.
-- This does not exercise FS25 runtime object linking or sale hooks.

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
dofile("src/assets/AssetRight.lua")
dofile("src/assets/Lien.lua")
dofile("src/assets/AssetRegistry.lua")
dofile("src/assets/AssetRightRegistry.lua")
dofile("src/assets/LienRegistry.lua")
dofile("src/assets/AssetLinkQuarantine.lua")
dofile("src/assets/SecuredDispositionService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local function assertFalse(value, message)
    if value ~= false then error(message or "expected false") end
end

local ids = AGFIdService.new()
local liabilities = AGFLiabilityRegistry.new(ids, nil)
local assets = AGFAssetRegistry.new(ids, nil)
local rights = AGFAssetRightRegistry.new(ids, nil, assets)
local liens = AGFLienRegistry.new(ids, nil, assets, liabilities)
local quarantine = AGFAssetLinkQuarantine.new()
local disposition = AGFSecuredDispositionService.new(assets, liens, liabilities, rights)

-- Register secured term debt.
local liability, liabilityError = liabilities:create(1, AGFProductType.TERM_LOAN, "Equipment note")
assertEqual(liabilityError, nil, "liability create error")
liability.originalPrincipal = 60000
liability.principalBalance = 60000
local liabilityRegistered, liabilityRegisterError = liabilities:register(liability)
assertTrue(liabilityRegistered, liabilityRegisterError)

-- Register a vehicle with independent economic ownership.
local asset, assetError = assets:create(AGFAssetType.VEHICLE, "vehicle-guid-001", "Test Tractor")
assertEqual(assetError, nil, "asset create error")
asset.acquisitionCost = 100000
asset.currentValue = 50000
asset.linkState = AGFAssetLinkState.RESOLVED
local assetRegistered, assetRegisterError = assets:register(asset)
assertTrue(assetRegistered, assetRegisterError)

local ownerRight, ownerError = rights:create(asset.id, AGFAssetRightType.ECONOMIC_OWNER, AGFRightHolderType.FARM, 1)
assertEqual(ownerError, nil, "owner right error")
local ownerRegistered, ownerRegisterError = rights:register(ownerRight)
assertTrue(ownerRegistered, ownerRegisterError)
assertTrue(rights:isOwnedByFarm(asset.id, 1), "farm 1 owns test asset")
assertFalse(rights:isOwnedByFarm(asset.id, 2), "farm 2 does not own test asset")

-- Register lien against the vehicle.
local lien, lienError = liens:create(asset.id, liability.id, 1)
assertEqual(lienError, nil, "lien create error")
local lienRegistered, lienRegisterError = liens:register(lien)
assertTrue(lienRegistered, lienRegisterError)
assertTrue(liens:hasActiveLien(asset.id), "asset has active lien")

-- A $50k sale against $60k debt needs $10k borrower cash.
local preflightOk, preflight = disposition:preflight(asset.id, 50000, 5000, 1)
assertTrue(preflightOk, "preflight calculated")
assertFalse(preflight.allowed, "sale blocked with insufficient shortfall cash")
assertEqual(preflight.lienPayoff, 60000, "lien payoff")
assertEqual(preflight.requiredCashContribution, 10000, "required shortfall cash")
assertEqual(preflight.denialReason, "INSUFFICIENT_CASH_TO_CLEAR_LIENS", "shortfall denial")

local secondOk, secondPreflight = disposition:preflight(asset.id, 50000, 10000, 1)
assertTrue(secondOk, "second preflight calculated")
assertTrue(secondPreflight.allowed, "sale allowed when lien shortfall covered")
assertEqual(secondPreflight.netCashToOwner, 0, "no positive owner equity")

-- Different farm cannot dispose of economically owned collateral.
local wrongFarmOk, wrongFarmError = disposition:preflight(asset.id, 70000, 0, 2)
assertFalse(wrongFarmOk, "wrong farm rejected")
assertEqual(wrongFarmError, "ACTING_FARM_NOT_ECONOMIC_OWNER", "wrong farm error")

-- Quarantine is explicitly not disposal and blocks disposition.
local quarantined, quarantineAsset = assets:markQuarantined(asset.id, "runtime object not resolved")
assertTrue(quarantined, "asset quarantined")
local quarantineAdded = quarantine:add(asset.id, asset.stableKey, "runtime object not resolved")
assertTrue(quarantineAdded, "quarantine entry added")
assertEqual(quarantine:count(), 1, "quarantine count")

local quarantinedOk, quarantinedError = disposition:preflight(asset.id, 70000, 0, 1)
assertFalse(quarantinedOk, "quarantined disposition rejected")
assertEqual(quarantinedError, "ASSET_LINK_QUARANTINED", "quarantine disposition error")
assertEqual(assets:get(asset.id).status, AGFAssetStatus.ACTIVE, "quarantine does not dispose asset")

-- Duplicate stable keys and duplicate active rights are rejected.
local duplicateAsset, duplicateAssetError = assets:create(AGFAssetType.VEHICLE, "vehicle-guid-001", "Duplicate")
assertEqual(duplicateAsset, nil, "duplicate stable key rejected")
assertEqual(duplicateAssetError, "DUPLICATE_STABLE_KEY", "duplicate stable key error")

local duplicateRight, duplicateRightError = rights:create(asset.id, AGFAssetRightType.ECONOMIC_OWNER, AGFRightHolderType.FARM, 2)
assertEqual(duplicateRight, nil, "duplicate active owner right rejected")
assertEqual(duplicateRightError, "ACTIVE_RIGHT_ALREADY_EXISTS", "duplicate right error")

print("offline_asset_tests: PASS")
