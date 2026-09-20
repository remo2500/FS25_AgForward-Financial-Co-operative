-- Offline origination-close validation. Plans semantic atomic effects only.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/OriginationClosePlanService.lua")

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

local equipmentPlan = {
    planType = "termOrigination",
    farmId = 1,
    productType = AGFProductType.EQUIPMENT_FINANCE,
    liability = {
        farmId = 1,
        productType = AGFProductType.EQUIPMENT_FINANCE,
        status = "pendingClose",
        originalPrincipal = 200000,
        principalBalance = 200000,
        interestRate = 0.065
    },
    security = {
        mode = "specificLien",
        assetId = "AGF-ASSET-000010",
        lienPriority = 1,
        securedAmount = 200000
    },
    closing = {
        purchasePrice = 250000,
        cashEquity = 50000,
        financedAmount = 200000,
        directPurchaseFunding = true
    }
}

local equipmentOk, equipment = AGFOriginationClosePlanService.build(equipmentPlan, {
    cashAvailable = 75000,
    groupId = "GRP-CLOSE-1",
    liabilityId = "AGF-LIAB-000010",
    lienId = "AGF-LIEN-000010",
    assetId = "AGF-ASSET-000010"
})
assertTrue(equipmentOk, "equipment close plan succeeds")
assertEqual(equipment.closeType, "financedAssetPurchase", "equipment close type")
assertEqual(equipment.fsCashDelta, -50000, "equipment cash delta equals equity")
assertEqual(equipment.netLedgerAmount, -50000, "equipment ledger reconciles to cash")
assertEqual(#equipment.ledgerIntents, 2, "equipment ledger intent count")
assertEqual(equipment.ledgerIntents[1].transactionType, AGFTransactionType.LOAN_PROCEEDS, "loan proceeds first")
assertEqual(equipment.ledgerIntents[1].fundingSource, AGFFundingSource.EQUIPMENT_FINANCE, "equipment funding source")
assertEqual(equipment.ledgerIntents[2].transactionType, AGFTransactionType.ASSET_PURCHASE, "asset purchase second")
assertEqual(equipment.ledgerIntents[2].fundingBreakdown.cash, 50000, "cash-equity breakdown")
assertEqual(equipment.liabilityIntent.status, "active", "new liability activates at close")
assertTrue(equipment.reconciliation.balanced, "equipment close reconciles")

local insufficientOk, insufficientError = AGFOriginationClosePlanService.build(equipmentPlan, {cashAvailable = 49999.99})
assertFalse(insufficientOk, "insufficient equity rejected")
assertEqual(insufficientError, "INSUFFICIENT_CASH_EQUITY", "insufficient-equity error")

local tampered = {
    planType = equipmentPlan.planType,
    farmId = equipmentPlan.farmId,
    productType = equipmentPlan.productType,
    liability = equipmentPlan.liability,
    security = equipmentPlan.security,
    closing = {
        purchasePrice = 250000,
        cashEquity = 40000,
        financedAmount = 200000
    }
}
local tamperedOk, tamperedError = AGFOriginationClosePlanService.build(tampered, {cashAvailable = 100000})
assertFalse(tamperedOk, "unreconciled sources rejected")
assertEqual(tamperedError, "CLOSING_SOURCES_DO_NOT_MATCH_PURCHASE_PRICE", "source mismatch error")

local termPlan = {
    planType = "termOrigination",
    farmId = 1,
    productType = AGFProductType.TERM_LOAN,
    liability = {
        farmId = 1,
        productType = AGFProductType.TERM_LOAN,
        originalPrincipal = 100000,
        principalBalance = 100000
    },
    security = {mode = "generalSecurity", securedAmount = 100000},
    closing = {purchasePrice = 0, cashEquity = 0, financedAmount = 100000}
}
local termOk, term = AGFOriginationClosePlanService.build(termPlan, {groupId = "GRP-CLOSE-2"})
assertTrue(termOk, "general term advance succeeds")
assertEqual(term.closeType, "termLoanAdvance", "term close type")
assertEqual(term.fsCashDelta, 100000, "term advance adds cash")
assertEqual(#term.ledgerIntents, 1, "term advance one ledger intent")
assertEqual(term.ledgerIntents[1].fundingSource, AGFFundingSource.TERM_LOAN, "term funding source")

local revolvingPlan = {
    planType = "revolvingOrigination",
    farmId = 1,
    productType = AGFProductType.CROP_INPUT_LINE,
    liability = {
        farmId = 1,
        productType = AGFProductType.CROP_INPUT_LINE,
        principalBalance = 0,
        creditLimit = 150000,
        interestRate = 0.07
    },
    security = {mode = "generalSecurity", securedAmount = 150000}
}
local revolverOk, revolver = AGFOriginationClosePlanService.build(revolvingPlan, {})
assertTrue(revolverOk, "revolver open succeeds")
assertEqual(revolver.closeType, "revolvingFacilityOpen", "revolver close type")
assertEqual(revolver.fsCashDelta, 0, "opening undrawn revolver does not move cash")
assertEqual(#revolver.ledgerIntents, 0, "opening undrawn revolver has no ledger movement")

revolvingPlan.liability.principalBalance = 1
local drawnOpenOk, drawnOpenError = AGFOriginationClosePlanService.build(revolvingPlan, {})
assertFalse(drawnOpenOk, "revolver cannot originate already drawn")
assertEqual(drawnOpenError, "REVOLVING_CLOSE_MUST_START_UNDRAWN", "drawn-open error")
revolvingPlan.liability.principalBalance = 0

local projectPlan = {
    planType = "projectCommitmentOrigination",
    farmId = 1,
    productType = AGFProductType.PROJECT_FINANCE,
    liability = {
        productType = AGFProductType.PROJECT_FINANCE,
        originalPrincipal = 0,
        principalBalance = 0,
        commitmentAmount = 500000
    },
    security = {mode = "specificLien", assetId = "AGF-ASSET-PROJECT"},
    closing = {projectCost = 600000, cashEquity = 100000, approvedCommitment = 500000}
}
local projectOk, project = AGFOriginationClosePlanService.build(projectPlan, {assetId = "AGF-ASSET-PROJECT"})
assertTrue(projectOk, "staged project commitment opens without advance")
assertEqual(project.closeType, "projectCommitmentOpen", "project commitment close type")
assertEqual(project.fsCashDelta, 0, "project commitment open moves no cash")
assertEqual(project.liabilityIntent.principalBalance, 0, "project commitment opens undrawn")
assertEqual(project.liabilityIntent.undrawnCommitment, 500000, "full commitment undrawn")
assertEqual(#project.ledgerIntents, 0, "commitment opening posts no proceeds")

local legacyProject = {
    planType = "termOrigination",
    farmId = 1,
    productType = AGFProductType.PROJECT_FINANCE,
    liability = {originalPrincipal = 500000, principalBalance = 500000},
    security = {mode = "specificLien", assetId = "AGF-ASSET-PROJECT"},
    closing = {purchasePrice = 600000, cashEquity = 100000, financedAmount = 500000}
}
local legacyOk, legacyError = AGFOriginationClosePlanService.build(legacyProject, {})
assertFalse(legacyOk, "legacy full-advance project close rejected")
assertEqual(legacyError, "PROJECT_FINANCE_REQUIRES_COMMITMENT_ORIGINATION", "legacy project close boundary")

print("offline_origination_close_plan_tests: PASS")
