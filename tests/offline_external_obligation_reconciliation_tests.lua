-- Offline external-obligation reconciliation validation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/credit/ExternalObligation.lua")
dofile("src/credit/ExternalObligationReconciliationService.lua")

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

local existingLoan = AGFExternalObligation.new("AGF-EXT-1", 1, AGFExternalObligationType.BASE_GAME_LOAN, "baseGame")
existingLoan.displayName = "Base Game Loan"
existingLoan.principalBalance = 50000
existingLoan.annualDebtService = 12000
existingLoan.dataQuality = AGFExternalObligationQuality.VERIFIED
existingLoan:setMetadata("externalKey", "farm.loan")

local existingLease = AGFExternalObligation.new("AGF-EXT-2", 1, AGFExternalObligationType.VEHICLE_LEASE, "baseGame")
existingLease.displayName = "Leased tractor"
existingLease.principalBalance = 0
existingLease.annualFixedCharge = 18000
existingLease.dataQuality = AGFExternalObligationQuality.PARTIAL
existingLease:setMetadata("externalKey", "vehicleLease:123")

local ok, plan = AGFExternalObligationReconciliationService.plan(
    {existingLoan, existingLease},
    {
        {
            externalKey = "farm.loan",
            obligationType = AGFExternalObligationType.BASE_GAME_LOAN,
            displayName = "Base Game Loan",
            principalBalance = 45000,
            annualDebtService = 12000,
            annualFixedCharge = 0,
            dataQuality = AGFExternalObligationQuality.VERIFIED
        },
        {
            externalKey = "vehicleLease:456",
            obligationType = AGFExternalObligationType.VEHICLE_LEASE,
            displayName = "Leased combine",
            principalBalance = 0,
            annualDebtService = 0,
            annualFixedCharge = 24000,
            dataQuality = AGFExternalObligationQuality.PARTIAL
        }
    },
    "baseGame"
)
assertTrue(ok, "reconciliation plan succeeds")
assertEqual(#plan.updates, 1, "one changed obligation")
assertEqual(plan.updates[1].externalKey, "farm.loan", "base loan update matched by stable key")
assertEqual(#plan.additions, 1, "one new obligation")
assertEqual(plan.additions[1].externalKey, "vehicleLease:456", "new lease addition")
assertEqual(#plan.retirements, 1, "missing old lease retired")
assertEqual(plan.retirements[1].externalKey, "vehicleLease:123", "old lease retirement")
assertEqual(plan.changeCount, 3, "change count")
assertTrue(plan.hasChanges, "changes reported")
assertTrue(plan.completeStableKeyCoverage, "all existing rows have stable keys")

local unchangedOk, unchanged = AGFExternalObligationReconciliationService.plan(
    {existingLoan},
    {{
        externalKey = "farm.loan",
        obligationType = AGFExternalObligationType.BASE_GAME_LOAN,
        displayName = "Base Game Loan",
        principalBalance = 50000,
        annualDebtService = 12000,
        annualFixedCharge = 0,
        dataQuality = AGFExternalObligationQuality.VERIFIED
    }},
    "baseGame"
)
assertTrue(unchangedOk, "unchanged reconciliation succeeds")
assertEqual(#unchanged.unchanged, 1, "unchanged row recognized")
assertEqual(unchanged.hasChanges, false, "no false change")

local duplicateOk, duplicateError = AGFExternalObligationReconciliationService.plan({}, {
    {externalKey = "farm.loan", obligationType = AGFExternalObligationType.BASE_GAME_LOAN},
    {externalKey = "farm.loan", obligationType = AGFExternalObligationType.BASE_GAME_LOAN}
}, "baseGame")
assertFalse(duplicateOk, "duplicate observed key rejected")
assertEqual(duplicateError, "DUPLICATE_OBSERVED_EXTERNAL_KEY:farm.loan", "duplicate key error")

local unkeyed = AGFExternalObligation.new("AGF-EXT-3", 1, AGFExternalObligationType.OTHER, "baseGame")
local coverageOk, coverage = AGFExternalObligationReconciliationService.plan({unkeyed}, {}, "baseGame")
assertTrue(coverageOk, "unkeyed existing row does not crash reconciliation")
assertEqual(coverage.completeStableKeyCoverage, false, "unkeyed existing row reported")
assertEqual(#coverage.unmatchedExisting, 1, "unmatched existing row count")

print("offline_external_obligation_reconciliation_tests: PASS")
