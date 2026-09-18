-- Offline liability payoff quote validation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/finance/PrepaymentPolicyService.lua")
dofile("src/finance/LiabilityPayoffQuoteService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local loan = AGFLiability.new("AGF-LIAB-PAYOFF-1", 1, AGFProductType.EQUIPMENT_FINANCE)
loan.status = AGFLiabilityStatus.ACTIVE
loan.principalBalance = 60000
loan.accruedInterest = 1000
loan.accruedFees = 500

local openOk, open = AGFLiabilityPayoffQuoteService.quote(loan, {
    type = AGFPrepaymentPolicyType.OPEN
}, {})
assertTrue(openOk, "open payoff quote")
assertEqual(open.principal, 60000, "payoff principal")
assertEqual(open.accruedInterest, 1000, "payoff interest")
assertEqual(open.accruedFees, 500, "payoff accrued fees")
assertEqual(open.prepaymentCharge, 0, "open payoff charge")
assertEqual(open.totalCashRequired, 61500, "open payoff total")

local closedOk, closed = AGFLiabilityPayoffQuoteService.quote(loan, {
    type = AGFPrepaymentPolicyType.CLOSED,
    chargeRate = 0.02,
    fixedCharge = 100
}, {})
assertTrue(closedOk, "closed-term payoff quote")
assertEqual(closed.prepaymentCharge, 1300, "prepayment charge")
assertEqual(closed.totalCashRequired, 62800, "charged payoff total")

local maturityOk, maturity = AGFLiabilityPayoffQuoteService.quote(loan, {
    type = AGFPrepaymentPolicyType.NONE,
    chargeRate = 1
}, {atMaturity = true})
assertTrue(maturityOk, "maturity payoff bypasses early-prepay restriction")
assertEqual(maturity.prepaymentCharge, 0, "no early-prepay charge at maturity")
assertEqual(maturity.totalCashRequired, 61500, "maturity payoff total")

local blockedOk, blockedError = AGFLiabilityPayoffQuoteService.quote(loan, {
    type = AGFPrepaymentPolicyType.NONE
}, {})
assertEqual(blockedOk, false, "contractually blocked prepay rejected")
assertEqual(blockedError, "PREPAYMENT_NOT_ALLOWED", "blocked payoff error")

print("offline_payoff_quote_tests: PASS")
