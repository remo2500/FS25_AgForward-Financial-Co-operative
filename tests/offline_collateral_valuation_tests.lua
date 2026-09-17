-- Offline validation for policy-driven collateral lending value.

dofile("src/core/Currency.lua")
dofile("src/credit/CollateralValuationService.lua")

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

-- Mixed collateral keeps market value, policy lending value, and prior claims separate.
local ok, result = AGFCollateralValuationService.evaluate({
    {
        assetId = "LAND-1",
        assetType = "farmland",
        marketValue = 1000000,
        eligibilityPercent = 1.00,
        advanceRate = 0.65,
        priorClaims = 200000
    },
    {
        assetId = "VEH-1",
        assetType = "vehicle",
        marketValue = 400000,
        eligibilityPercent = 0.90,
        advanceRate = 0.60,
        priorClaims = 50000
    }
}, 500000)
assertTrue(ok, "collateral valuation succeeds")
assertEqual(result.grossMarketValue, 1400000, "gross market value")
assertEqual(result.eligibleMarketValue, 1360000, "eligible market value")
assertEqual(result.grossLendingValue, 866000, "gross lending value")
assertEqual(result.priorClaims, 250000, "prior claims")
assertEqual(result.netLendingValue, 616000, "net lending value")
assertEqual(result.collateralSurplus, 116000, "collateral surplus")
assertEqual(result.collateralShortfall, 0, "no shortfall")
assertTrue(result.fullyCoveredByPolicyLendingValue, "proposed debt covered")
assertTrue(result.netCoverage > 1, "coverage ratio above one")

-- Prior claims can exhaust one asset without producing negative lending value.
local exhaustedOk, exhausted = AGFCollateralValuationService.evaluate({
    {
        assetId = "VEH-2",
        marketValue = 100000,
        eligibilityPercent = 1,
        advanceRate = 0.50,
        priorClaims = 80000
    }
}, 25000)
assertTrue(exhaustedOk, "exhausted collateral evaluates")
assertEqual(exhausted.grossLendingValue, 50000, "gross lending value")
assertEqual(exhausted.netLendingValue, 0, "net lending value floor")
assertEqual(exhausted.collateralShortfall, 25000, "full proposed debt shortfall")
assertTrue(exhausted.assets[1].exhaustedByPriorClaims, "asset flagged exhausted")
assertFalse(exhausted.fullyCoveredByPolicyLendingValue, "debt not covered")

-- Policy may deliberately exclude part or all of an asset's market value.
local ineligibleOk, ineligible = AGFCollateralValuationService.evaluate({
    {assetId = "OTHER-1", marketValue = 500000, eligibilityPercent = 0, advanceRate = 0.75, priorClaims = 0},
    {assetId = "LAND-2", marketValue = 300000, eligibilityPercent = 0.80, advanceRate = 0.50, priorClaims = 0}
}, 100000)
assertTrue(ineligibleOk, "eligibility policy evaluates")
assertEqual(ineligible.grossMarketValue, 800000, "all market value retained")
assertEqual(ineligible.eligibleMarketValue, 240000, "only policy-eligible value counted")
assertEqual(ineligible.grossLendingValue, 120000, "advance rate applied to eligible value")
assertEqual(ineligible.netLendingValue, 120000, "net value")
assertTrue(ineligible.fullyCoveredByPolicyLendingValue, "covered by lending value")

-- Duplicate identity and invalid percentages are rejected.
local dupOk, dupError = AGFCollateralValuationService.evaluate({
    {assetId = "A", marketValue = 100000},
    {assetId = "A", marketValue = 200000}
}, 50000)
assertFalse(dupOk, "duplicate asset rejected")
assertEqual(dupError, "DUPLICATE_ASSET_ID:A", "duplicate error")

local badAdvanceOk, badAdvanceError = AGFCollateralValuationService.evaluate({
    {assetId = "A", marketValue = 100000, advanceRate = 1.2}
}, 50000)
assertFalse(badAdvanceOk, "advance rate above 100% rejected")
assertEqual(badAdvanceError, "INVALID_ADVANCE_RATE_ROW_1", "advance rate error")

print("offline_collateral_valuation_tests: PASS")
