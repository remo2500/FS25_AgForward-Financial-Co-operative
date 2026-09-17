-- Offline validation for deterministic origination planning.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/products/ProductCatalog.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/StructuredAmortizationService.lua")
dofile("src/finance/RateTermRenewalService.lua")
dofile("src/finance/LoanQuoteService.lua")
dofile("src/finance/PaymentFrequencyService.lua")
dofile("src/finance/LoanContractScheduleService.lua")
dofile("src/credit/CreditPolicyService.lua")
dofile("src/credit/CILOCSeasonService.lua")
dofile("src/finance/OriginationPlanService.lua")

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

local approve = {
    status = AGFCreditDecisionStatus.APPROVE,
    conditions = {},
    referrals = {},
    policyName = "test-policy",
    policyVersion = "1"
}

local conditional = {
    status = AGFCreditDecisionStatus.APPROVE_WITH_CONDITIONS,
    conditions = {{id = "equity", message = "Maintain required equity"}},
    referrals = {},
    policyName = "test-policy",
    policyVersion = "1"
}

local referred = {
    status = AGFCreditDecisionStatus.REFER,
    conditions = {},
    referrals = {{id = "manual", message = "Manual review"}},
    policyName = "test-policy",
    policyVersion = "1"
}

local declined = {
    status = AGFCreditDecisionStatus.DECLINE,
    conditions = {},
    referrals = {},
    policyName = "test-policy",
    policyVersion = "1"
}

-- Equipment finance plan ties server-approved quote to a specific lien/context.
local quoteOk, equipmentQuote = AGFLoanQuoteService.quote({
    purchasePrice = 500000,
    downPayment = 100000,
    periods = 60,
    paymentsPerYear = 12,
    rateTermPeriods = 36,
    balloonPercent = 0.10,
    rateComponents = {baseRate = 0.045, productSpread = 0.0125, riskSpread = 0.005}
})
assertTrue(quoteOk, "equipment quote succeeds")

local equipmentPlanOk, equipmentPlan = AGFOriginationPlanService.build({
    farmId = 2,
    productType = AGFProductType.EQUIPMENT_FINANCE,
    quote = equipmentQuote,
    creditDecision = conditional,
    assetId = "AGF-ASSET-000101",
    lienPriority = 1,
    startYear = 4,
    startPeriod = 3,
    contextFingerprint = "vehicle:tractor:configA"
})
assertTrue(equipmentPlanOk, "equipment origination plan succeeds")
assertEqual(equipmentPlan.planType, "termOrigination", "term plan type")
assertEqual(equipmentPlan.liability.principalBalance, 400000, "equipment principal")
assertEqual(equipmentPlan.liability.paymentFrequency, 12, "monthly frequency")
assertEqual(equipmentPlan.liability.totalPaymentPeriods, 60, "payment count")
assertEqual(equipmentPlan.liability.rateTermPeriods, 36, "rate term retained")
assertEqual(equipmentPlan.security.mode, "specificLien", "specific lien mode")
assertEqual(equipmentPlan.security.assetId, "AGF-ASSET-000101", "asset binding")
assertEqual(equipmentPlan.security.collateralClass, AGFCollateralClass.VEHICLE, "vehicle collateral")
assertEqual(equipmentPlan.closing.cashEquity, 100000, "cash equity")
assertEqual(equipmentPlan.closing.financedAmount, 400000, "financed amount")
assertEqual(equipmentPlan.closing.sourceTotal, 500000, "sources reconcile")
assertEqual(#equipmentPlan.contractSchedule.schedule, 60, "contract schedule rows")
assertEqual(#equipmentPlan.decision.conditions, 1, "credit conditions retained")

-- Asset products cannot originate without their secured asset link.
local noAssetOk, noAssetError = AGFOriginationPlanService.build({
    farmId = 2,
    productType = AGFProductType.EQUIPMENT_FINANCE,
    quote = equipmentQuote,
    creditDecision = approve,
    startYear = 4,
    startPeriod = 3
})
assertFalse(noAssetOk, "missing secured asset rejected")
assertEqual(noAssetError, "SECURED_ASSET_REQUIRED", "missing asset error")

-- Decline is never bypassed by origination planning.
local declineOk, declineError = AGFOriginationPlanService.build({
    farmId = 2,
    productType = AGFProductType.EQUIPMENT_FINANCE,
    quote = equipmentQuote,
    creditDecision = declined,
    assetId = "AGF-ASSET-000101",
    startYear = 4,
    startPeriod = 3
})
assertFalse(declineOk, "declined credit cannot originate")
assertEqual(declineError, "CREDIT_DECISION_DECLINED", "decline error")

-- Referred credit needs an explicit server/manual approval flag.
local referOk, referError = AGFOriginationPlanService.build({
    farmId = 2,
    productType = AGFProductType.EQUIPMENT_FINANCE,
    quote = equipmentQuote,
    creditDecision = referred,
    assetId = "AGF-ASSET-000101",
    startYear = 4,
    startPeriod = 3
})
assertFalse(referOk, "referred credit not auto-originated")
assertEqual(referError, "MANUAL_APPROVAL_REQUIRED", "manual approval error")

local manualOk, manualPlan = AGFOriginationPlanService.build({
    farmId = 2,
    productType = AGFProductType.EQUIPMENT_FINANCE,
    quote = equipmentQuote,
    creditDecision = referred,
    manualApproval = true,
    assetId = "AGF-ASSET-000101",
    startYear = 4,
    startPeriod = 3
})
assertTrue(manualOk, "manual approval permits referred origination")
assertTrue(manualPlan.decision.manualApproval, "manual approval recorded")

-- General term credit carries general security but does not require a specific asset.
local termQuoteOk, termQuote = AGFLoanQuoteService.quote({
    principal = 150000,
    periods = 20,
    paymentsPerYear = 4,
    rateComponents = {baseRate = 0.05, productSpread = 0.015, riskSpread = 0.0075}
})
assertTrue(termQuoteOk, "general term quote")
local termPlanOk, termPlan = AGFOriginationPlanService.build({
    farmId = 3,
    productType = AGFProductType.TERM_LOAN,
    quote = termQuote,
    creditDecision = approve,
    startYear = 6,
    startPeriod = 1
})
assertTrue(termPlanOk, "general term origination")
assertEqual(termPlan.security.mode, "generalSecurity", "general security mode")
assertEqual(termPlan.liability.paymentFrequency, 4, "quarterly frequency")
assertEqual(termPlan.liability.totalPaymentPeriods, 20, "quarterly payment count")

-- CILOC facility plan starts undrawn and can be borrowing-base constrained.
local cilocPlanOk, cilocPlan = AGFOriginationPlanService.build({
    farmId = 4,
    productType = AGFProductType.CROP_INPUT_LINE,
    creditDecision = approve,
    approvedLimit = 300000,
    borrowingBase = 240000,
    annualRate = 0.0725,
    seasonParameters = {
        currentYear = 10,
        currentPeriod = 2,
        startYear = 10,
        startPeriod = 1,
        maturityYear = 10,
        maturityPeriod = 11,
        cleanupWindowPeriods = 2,
        cleanupTargetBalance = 0,
        freezeNewDrawsDuringCleanup = true
    }
})
assertTrue(cilocPlanOk, "CILOC origination plan")
assertEqual(cilocPlan.planType, "revolvingOrigination", "revolving plan type")
assertEqual(cilocPlan.liability.creditLimit, 300000, "approved line limit")
assertEqual(cilocPlan.liability.effectiveLimit, 240000, "borrowing-base effective limit")
assertEqual(cilocPlan.liability.principalBalance, 0, "line starts undrawn")
assertEqual(cilocPlan.security.mode, "generalSecurity", "CILOC general security")
assertEqual(cilocPlan.season.state, AGFCILOCSeasonState.ACTIVE_SEASON, "season state")
assertEqual(cilocPlan.season.availableCapacity, 240000, "season capacity")

-- Wrong product path is rejected explicitly.
local leasePlanOk, leasePlanError = AGFOriginationPlanService.build({
    farmId = 5,
    productType = AGFProductType.LAND_LEASE,
    creditDecision = approve
})
assertFalse(leasePlanOk, "lease not originated as debt")
assertEqual(leasePlanError, "ORIGINATION_NOT_SUPPORTED_FOR_PRODUCT_KIND", "lease origination error")

print("offline_origination_plan_tests: PASS")
