-- Offline validation for exact dated debt-service measurement.

dofile("src/core/Currency.lua")
dofile("src/credit/DebtServiceWindowService.lua")

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

-- Mix monthly, quarterly, interest-only, fees, and a maturity balloon. The
-- horizon includes financial periods 1..12 of year 2, but excludes year 3.
local ok, result = AGFDebtServiceWindowService.calculate({
    {
        liabilityId = "MONTHLY",
        schedule = {
            {paymentNumber = 1, dueYear = 2, duePeriod = 1, interest = 100, regularPrincipal = 900, balloonPayment = 0, totalPayment = 1000},
            {paymentNumber = 2, dueYear = 2, duePeriod = 2, interest = 90, regularPrincipal = 910, balloonPayment = 0, totalPayment = 1000},
            {paymentNumber = 3, dueYear = 3, duePeriod = 1, interest = 80, regularPrincipal = 920, balloonPayment = 0, totalPayment = 1000}
        }
    },
    {
        liabilityId = "QUARTERLY",
        schedule = {
            {paymentNumber = 1, dueYear = 2, duePeriod = 3, interest = 300, regularPrincipal = 4700, balloonPayment = 0, fees = 25, totalPayment = 5000},
            {paymentNumber = 2, dueYear = 2, duePeriod = 6, interest = 250, regularPrincipal = 4750, balloonPayment = 0, totalPayment = 5000},
            {paymentNumber = 3, dueYear = 2, duePeriod = 9, interest = 200, regularPrincipal = 4800, balloonPayment = 0, totalPayment = 5000},
            {paymentNumber = 4, dueYear = 2, duePeriod = 12, interest = 150, regularPrincipal = 4850, balloonPayment = 10000, totalPayment = 15000}
        }
    },
    {
        liabilityId = "IO",
        schedule = {
            {paymentNumber = 1, phase = "interestOnly", dueYear = 1, duePeriod = 12, interest = 500, regularPrincipal = 0, balloonPayment = 0, totalPayment = 500},
            {paymentNumber = 2, phase = "interestOnly", dueYear = 2, duePeriod = 4, interest = 500, regularPrincipal = 0, balloonPayment = 0, totalPayment = 500}
        }
    }
}, 2, 1, 12)
assertTrue(ok, "debt service window succeeds")
assertEqual(result.paymentCount, 7, "seven payments in 12-period window")
assertEqual(result.interest, 1590, "interest total")
assertEqual(result.principal, 34910, "principal including balloon")
assertEqual(result.balloonPrincipal, 10000, "balloon principal separately visible")
assertEqual(result.fees, 25, "scheduled fee total")
assertEqual(result.totalDebtService, 36525, "cash debt service total")
assertEqual(result.byContract.MONTHLY.paymentCount, 2, "monthly contract window count")
assertEqual(result.byContract.QUARTERLY.paymentCount, 4, "quarterly contract window count")
assertEqual(result.byContract.IO.paymentCount, 1, "interest-only window count")
assertEqual(result.rows[1].duePeriod, 1, "rows sorted chronologically")
assertEqual(result.rows[#result.rows].duePeriod, 12, "last included payment at period 12")

-- A shorter horizon counts only obligations actually due in that window.
local shortOk, short = AGFDebtServiceWindowService.calculate({
    {
        liabilityId = "ANNUAL",
        schedule = {
            {paymentNumber = 1, dueYear = 5, duePeriod = 4, interest = 1000, regularPrincipal = 9000, balloonPayment = 0, totalPayment = 10000},
            {paymentNumber = 2, dueYear = 6, duePeriod = 4, interest = 900, regularPrincipal = 9100, balloonPayment = 0, totalPayment = 10000}
        }
    }
}, 5, 1, 6)
assertTrue(shortOk, "short horizon succeeds")
assertEqual(short.paymentCount, 1, "one annual payment inside six-period horizon")
assertEqual(short.totalDebtService, 10000, "short-horizon debt service")

-- Fee cash obligations are additive but are not misclassified as principal/interest.
local feeOk, feeResult = AGFDebtServiceWindowService.calculate({
    {
        liabilityId = "FEE",
        schedule = {
            {dueYear = 1, duePeriod = 1, interest = 50, regularPrincipal = 950, balloonPayment = 0, scheduledFees = 75, totalPayment = 1000}
        }
    }
}, 1, 1, 12)
assertTrue(feeOk, "fee schedule succeeds")
assertEqual(feeResult.interest, 50, "fee schedule interest")
assertEqual(feeResult.principal, 950, "fee schedule principal")
assertEqual(feeResult.fees, 75, "fee schedule fees")
assertEqual(feeResult.totalDebtService, 1075, "fee added to cash due")

-- Inconsistent rows fail instead of silently corrupting debt-service analysis.
local mismatchOk, mismatchError = AGFDebtServiceWindowService.calculate({
    {
        liabilityId = "BAD",
        schedule = {
            {dueYear = 1, duePeriod = 1, interest = 100, regularPrincipal = 900, balloonPayment = 0, totalPayment = 999}
        }
    }
}, 1, 1, 12)
assertFalse(mismatchOk, "component mismatch rejected")
assertEqual(mismatchError, "PAYMENT_COMPONENT_MISMATCH_CONTRACT_1_ROW_1", "component mismatch error")

local badDateOk, badDateError = AGFDebtServiceWindowService.calculate({
    {
        liabilityId = "BADDATE",
        schedule = {{dueYear = 1, duePeriod = 13, interest = 0, regularPrincipal = 1, totalPayment = 1}}
    }
}, 1, 1, 12)
assertFalse(badDateOk, "bad due period rejected")
assertEqual(badDateError, "INVALID_DUE_PERIOD_CONTRACT_1_ROW_1", "bad due date error")

print("offline_debt_service_window_tests: PASS")
