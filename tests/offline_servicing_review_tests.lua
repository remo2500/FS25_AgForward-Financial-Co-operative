-- Offline servicing-review validation. No liability, cash, or collection mutation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/finance/ServicingReviewService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local liability = {
    id = "AGF-LIAB-000200",
    farmId = 1,
    productType = "landFinance",
    status = "active",
    principalBalance = 400000,
    accruedInterest = 2500,
    accruedFees = 0,
    scheduledPayment = 30000,
    nextPaymentYear = 2026,
    nextPaymentPeriod = 10,
    balloonAmount = 100000
}

local schedule = {
    rateRenewalDueYear = 2027,
    rateRenewalDuePeriod = 9,
    renewalPrincipal = 350000,
    maturityYear = 2030,
    maturityPeriod = 9,
    balloonAmount = 100000,
    schedule = {
        {paymentNumber = 1, dueYear = 2026, duePeriod = 10, totalPayment = 30000},
        {paymentNumber = 2, dueYear = 2027, duePeriod = 10, totalPayment = 30000}
    }
}

local ok, review = AGFServicingReviewService.build(
    liability,
    schedule,
    {state = "current", missedPayments = 0, pastDueAmount = 0},
    {status = "compliant", reviewRequired = false, breaches = {}, warnings = {}, missing = {}},
    2026,
    9,
    {paymentLookaheadPeriods = 1, renewalLookaheadPeriods = 12, maturityLookaheadPeriods = 12}
)
assertTrue(ok, "servicing review succeeds")
assertEqual(review.outstandingBalance, 402500, "outstanding balance")
assertEqual(review.nextPayment.periodsUntil, 1, "payment lookahead")
assertEqual(review.rateRenewal.periodsUntil, 12, "renewal lookahead")
assertEqual(review.status, "review", "rate renewal elevates review")
assertTrue(review.requiresReview, "upcoming contractual events require review")
assertEqual(#review.reviewReasons, 2, "payment and renewal reasons")

local delinquentOk, delinquent = AGFServicingReviewService.build(
    liability,
    schedule,
    {state = "collections", missedPayments = 4, pastDueAmount = 60000},
    {status = "breach", reviewRequired = true, breaches = {{id = "dscr"}}, warnings = {}, missing = {}},
    2026,
    9,
    {}
)
assertTrue(delinquentOk, "delinquent review succeeds")
assertEqual(delinquent.status, "urgent", "collections/covenant breach urgent")
assertTrue(delinquent.highestSeverity >= 2, "urgent severity retained")

local overdueLiability = {
    id = "AGF-LIAB-000201",
    farmId = 1,
    productType = "termLoan",
    status = "active",
    principalBalance = 50000,
    accruedInterest = 0,
    accruedFees = 0,
    scheduledPayment = 5000,
    nextPaymentYear = 2026,
    nextPaymentPeriod = 8
}
local overdueOk, overdue = AGFServicingReviewService.build(overdueLiability, nil, nil, nil, 2026, 9, {})
assertTrue(overdueOk, "overdue review succeeds")
assertEqual(overdue.status, "urgent", "past payment date urgent")
assertEqual(overdue.reviewReasons[1].code, "PAYMENT_DATE_PASSED", "past-payment reason")

local closedLiability = {
    id = "AGF-LIAB-000202",
    farmId = 1,
    productType = "termLoan",
    status = "closed",
    principalBalance = 0,
    accruedInterest = 0,
    accruedFees = 0
}
local closedOk, closed = AGFServicingReviewService.build(closedLiability, nil, nil, nil, 2026, 9, {})
assertTrue(closedOk, "closed review succeeds")
assertEqual(closed.status, "closed", "closed liability status")
assertEqual(closed.requiresReview, false, "clean closed liability needs no review")

closedLiability.principalBalance = 100
local badClosedOk, badClosed = AGFServicingReviewService.build(closedLiability, nil, nil, nil, 2026, 9, {})
assertTrue(badClosedOk, "closed-with-balance review succeeds")
assertEqual(badClosed.status, "urgent", "closed liability with balance flagged")
assertEqual(badClosed.reviewReasons[1].code, "CLOSED_WITH_BALANCE", "closed-balance reason")

print("offline_servicing_review_tests: PASS")
