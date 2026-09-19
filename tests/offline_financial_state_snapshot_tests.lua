-- Offline farm snapshot/delta validation. No GIANTS network serialization.

function Class(classTable)
    return {__index = classTable}
end

g_currentMission = nil

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/ledger/Transaction.lua")
dofile("src/ledger/Ledger.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/liabilities/LiabilityRegistry.lua")
dofile("src/assets/AssetRecord.lua")
dofile("src/assets/AssetRegistry.lua")
dofile("src/assets/AssetRight.lua")
dofile("src/assets/AssetRightRegistry.lua")
dofile("src/assets/Lien.lua")
dofile("src/assets/LienRegistry.lua")
dofile("src/leasing/Lease.lua")
dofile("src/leasing/LeaseRegistry.lua")
dofile("src/credit/ExternalObligation.lua")
dofile("src/credit/ExternalObligationRegistry.lua")
dofile("src/network/FinancialProtocolState.lua")
dofile("src/network/FinancialStateSnapshotService.lua")

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
local ledger = AGFLedger.new(ids, runtime)
local liabilities = AGFLiabilityRegistry.new(ids, runtime)
local assets = AGFAssetRegistry.new(ids, runtime)
local rights = AGFAssetRightRegistry.new(ids, runtime, assets)
local liens = AGFLienRegistry.new(ids, runtime, assets, liabilities)
local leases = AGFLeaseRegistry.new(ids, runtime, assets)
local external = AGFExternalObligationRegistry.new(ids)
local protocol = AGFFinancialProtocolState.new(ids, 32)

local vehicle = assert(assets:create(AGFAssetType.VEHICLE, "veh-stable-1", "Tractor"))
vehicle.currentValue = 150000
vehicle.linkState = AGFAssetLinkState.RESOLVED
assertTrue(assets:register(vehicle), "asset registered")
local owner = assert(rights:create(vehicle.id, AGFAssetRightType.ECONOMIC_OWNER, AGFRightHolderType.FARM, 1))
assertTrue(rights:register(owner), "ownership registered")

local loan = assert(liabilities:create(1, AGFProductType.EQUIPMENT_FINANCE, "Tractor note"))
loan.principalBalance = 90000
loan.originalPrincipal = 100000
loan.assetId = vehicle.id
assertTrue(liabilities:register(loan), "loan registered")

local lien = assert(liens:create(vehicle.id, loan.id, 1))
lien.securedAmountCap = 100000
assertTrue(liens:register(lien), "lien registered")

local ext = assert(external:create(1, AGFExternalObligationType.BASE_GAME_LOAN, "baseGame", "Base loan"))
ext.principalBalance = 25000
ext.dataQuality = AGFExternalObligationQuality.VERIFIED
ext:setMetadata("externalKey", "farm.loan")
assertTrue(external:register(ext), "external debt registered")

local tx = ledger:createTransaction(1, AGFTransactionType.PRINCIPAL_PAYMENT, -10000)
tx:setLiabilityId(loan.id)
tx:setPeriod(2026, 9)
assertTrue(ledger:post(tx), "ledger tx posted")

local snapshots = AGFFinancialStateSnapshotService.new(
    liabilities, assets, rights, liens, leases, external, ledger, protocol
)
local firstOk, first = snapshots:build(1, {ledgerLimit = 20})
assertTrue(firstOk, "initial snapshot succeeds")
assertEqual(first.revision, 0, "initial revision")
assertEqual(first.counts.liabilities, 1, "liability count")
assertEqual(first.counts.assets, 1, "relevant asset count")
assertEqual(first.counts.rights, 1, "right count")
assertEqual(first.counts.liens, 1, "lien count")
assertEqual(first.counts.externalObligations, 1, "external count")
assertEqual(first.counts.transactions, 1, "ledger tail count")
assertEqual(first.assets[1].runtimeObjectId, nil, "ephemeral runtime object ID not synchronized")

-- Mutate authoritative test state, then explicitly advance protocol revision.
assertTrue(assets:setValue(vehicle.id, 140000), "asset value changed")
local tx2 = ledger:createTransaction(1, AGFTransactionType.INTEREST_PAYMENT, -500)
tx2:setLiabilityId(loan.id)
tx2:setPeriod(2026, 10)
assertTrue(ledger:post(tx2), "second ledger tx posted")
assertTrue(protocol:setRevision(1), "revision advanced")

local secondOk, second = snapshots:build(1, {ledgerLimit = 20})
assertTrue(secondOk, "second snapshot succeeds")
local deltaOk, delta = AGFFinancialStateSnapshotService.diff(first, second)
assertTrue(deltaOk, "snapshot delta succeeds")
assertEqual(delta.fromRevision, 0, "delta from revision")
assertEqual(delta.toRevision, 1, "delta to revision")
assertEqual(delta.collections.assets.changeCount, 1, "asset update detected")
assertEqual(delta.collections.assets.updates[1].after.currentValue, 140000, "asset updated value")
assertEqual(delta.ledger.changeCount, 1, "new journal transaction detected")
assertEqual(delta.ledger.additions[1].id, tx2.id, "new ledger tx ID")
assertEqual(delta.requiresFullSnapshot, false, "overlapping ledger tail preserves continuity")

-- Same state revision with changed content is an invariant failure.
second.revision = first.revision
local sameRevisionOk, sameRevisionError = AGFFinancialStateSnapshotService.diff(first, second)
assertEqual(sameRevisionOk, false, "changed state without revision rejected")
assertEqual(sameRevisionError, "STATE_CHANGED_WITHOUT_REVISION", "same-revision error")
second.revision = 1

-- If bounded ledger windows no longer overlap, require a full resync instead of guessing.
local oldWindow = {
    farmId = 1,
    revision = 1,
    liabilities = {}, assets = {}, rights = {}, liens = {}, leases = {}, externalObligations = {},
    transactions = {{id = "TX-OLD", amount = -1}}
}
local newWindow = {
    farmId = 1,
    revision = 2,
    liabilities = {}, assets = {}, rights = {}, liens = {}, leases = {}, externalObligations = {},
    transactions = {{id = "TX-NEW", amount = -2}}
}
local windowOk, windowDelta = AGFFinancialStateSnapshotService.diff(oldWindow, newWindow)
assertTrue(windowOk, "non-overlapping window diff still returns delta metadata")
assertTrue(windowDelta.requiresFullSnapshot, "non-overlapping ledger tails require resync")

-- Immutable journal overlap is enforced.
local tamperedCurrent = {
    farmId = 1,
    revision = 2,
    liabilities = {}, assets = {}, rights = {}, liens = {}, leases = {}, externalObligations = {},
    transactions = {{id = "TX-SAME", amount = -99}}
}
local tamperedPrevious = {
    farmId = 1,
    revision = 1,
    liabilities = {}, assets = {}, rights = {}, liens = {}, leases = {}, externalObligations = {},
    transactions = {{id = "TX-SAME", amount = -1}}
}
local tamperOk, tamperError = AGFFinancialStateSnapshotService.diff(tamperedPrevious, tamperedCurrent)
assertEqual(tamperOk, false, "changed journal history rejected")
assertEqual(tamperError, "LEDGER_HISTORY_CHANGED:TX-SAME", "journal tamper error")

print("offline_financial_state_snapshot_tests: PASS")
