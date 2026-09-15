-- Offline tests for configurable whole-farm credit policy evaluation.

dofile("src/credit/CreditPolicyService.lua")

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

local policy = {
    name = "test-equipment-policy",
    version = 1,
    allowedDataQualities = {"complete"},
    dataQualitySeverity = AGFCreditRuleSeverity.REFER,
    rules = {
        {id = "minDSCR", metric = "dscr", comparator = "min", value = 1.25, severity = AGFCreditRuleSeverity.DECLINE},
        {id = "maxLTV", metric = "ltv", comparator = "max", value = 0.80, severity = AGFCreditRuleSeverity.DECLINE},
        {id = "minCurrentRatio", metric = "currentRatio", comparator = "min", value = 1.10, severity = AGFCreditRuleSeverity.CONDITION},
        {id = "maxDebtAssets", metric = "debtToAssets", comparator = "max", value = 0.65, severity = AGFCreditRuleSeverity.REFER}
    }
}

local approvedOk, approved = AGFCreditPolicyService.evaluate({
    dscr = 1.60,
    ltv = 0.65,
    currentRatio = 1.50,
    debtToAssets = 0.40
}, policy, {dataQuality = "complete"})
assertTrue(approvedOk, "approved policy evaluation runs")
assertEqual(approved.status, AGFCreditDecisionStatus.APPROVE, "strong borrower approved")
assertEqual(#approved.failedRules, 0, "strong borrower has no failed rules")

local conditionedOk, conditioned = AGFCreditPolicyService.evaluate({
    dscr = 1.40,
    ltv = 0.70,
    currentRatio = 1.00,
    debtToAssets = 0.50
}, policy, {dataQuality = "complete"})
assertTrue(conditionedOk, "condition policy evaluation runs")
assertEqual(conditioned.status, AGFCreditDecisionStatus.APPROVE_WITH_CONDITIONS, "current ratio condition")
assertEqual(#conditioned.conditions, 1, "one condition")
assertEqual(conditioned.conditions[1].id, "minCurrentRatio", "condition source")

local referredOk, referred = AGFCreditPolicyService.evaluate({
    dscr = 1.40,
    ltv = 0.70,
    currentRatio = 1.20,
    debtToAssets = 0.70
}, policy, {dataQuality = "complete"})
assertTrue(referredOk, "refer policy evaluation runs")
assertEqual(referred.status, AGFCreditDecisionStatus.REFER, "leverage breach referred")
assertEqual(#referred.referrals, 1, "one referral")

local declinedOk, declined = AGFCreditPolicyService.evaluate({
    dscr = 1.10,
    ltv = 0.85,
    currentRatio = 1.50,
    debtToAssets = 0.40
}, policy, {dataQuality = "complete"})
assertTrue(declinedOk, "decline policy evaluation runs")
assertEqual(declined.status, AGFCreditDecisionStatus.DECLINE, "hard coverage/LTV breaches decline")
assertEqual(#declined.declineReasons, 2, "two decline reasons preserved")

local missingOk, missing = AGFCreditPolicyService.evaluate({
    ltv = 0.60,
    currentRatio = 1.30,
    debtToAssets = 0.40
}, policy, {dataQuality = "complete"})
assertTrue(missingOk, "missing metric evaluation runs")
assertEqual(missing.status, AGFCreditDecisionStatus.DECLINE, "missing DSCR inherits rule missing severity default decline? no")

-- Explicit missing severity can refer rather than treat missing data as zero.
local missingPolicy = {
    rules = {
        {id = "minDSCR", metric = "dscr", comparator = "min", value = 1.25, severity = AGFCreditRuleSeverity.DECLINE, missingSeverity = AGFCreditRuleSeverity.REFER}
    }
}
local missingReferOk, missingRefer = AGFCreditPolicyService.evaluate({}, missingPolicy, {})
assertTrue(missingReferOk, "missing metric referral runs")
assertEqual(missingRefer.status, AGFCreditDecisionStatus.REFER, "missing metric referred")
assertEqual(missingRefer.failedRules[1].reason, "MISSING_METRIC", "missing metric reason")

local qualityOk, quality = AGFCreditPolicyService.evaluate({
    dscr = 1.50,
    ltv = 0.60,
    currentRatio = 1.40,
    debtToAssets = 0.40
}, policy, {dataQuality = "unknownExternalDebt"})
assertTrue(qualityOk, "data quality evaluation runs")
assertEqual(quality.status, AGFCreditDecisionStatus.REFER, "unknown data quality referred")

local invalidOk, invalidError = AGFCreditPolicyService.evaluate({dscr = 1.5}, {
    rules = {{id = "bad", metric = "dscr", comparator = "nonsense", value = 1}}
}, {})
assertFalse(invalidOk, "invalid comparator rejected")
assertEqual(invalidError, "INVALID_POLICY_COMPARATOR:bad", "invalid comparator error")

print("offline_credit_policy_tests: PASS")
