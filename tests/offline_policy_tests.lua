-- Offline validation for reservations, underwriting, leases, delinquency, settlement,
-- and multiplayer protocol state. No FS25 runtime hooks are exercised.

function Class(classTable)
    return {__index = classTable}
end

g_currentMission = nil

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/LoanQuoteService.lua")
dofile("src/finance/PaymentAllocationService.lua")
dofile("src/credit/CreditMetrics.lua")
dofile("src/credit/ProFormaUnderwritingService.lua")
dofile("src/liabilities/Liability.lua")
dofile("src/input/CreditReservationService.lua")
dofile("src/leasing/Lease.lua")
dofile("src/leasing/LeaseRegistry.lua")
dofile("src/delinquency/DelinquencyStateMachine.lua")
dofile("src/settlement/SettlementPlanner.lua")
dofile("src/network/FinancialProtocolState.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertNear(actual, expected, tolerance, message)
    if actual == nil or math.abs(actual - expected) > tolerance then
        error(string.format("%s: expected %.10f +/- %.10f, got %s", message or "assertNear", expected, tolerance, tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local function assertFalse(value, message)
    if value ~= false then error(message or "expected false") end
end

local writableRuntime = {canMutate = function() return true, nil end}
local ids = AGFIdService.new()

-- CILOC reservations reduce effective available credit before principal changes.
local ciloc = AGFLiability.new("AGF-LIAB-000001", 1, AGFProductType.CROP_INPUT_LINE)
ciloc.creditLimit = 100000
ciloc.principalBalance = 25000
local reservations = AGFCreditReservationService.new(ids)
assertEqual(reservations:getEffectiveAvailableCredit(ciloc), 75000, "initial effective available credit")

local reserveOk, reservation = reservations:reserveAgainstLiability(ciloc, 1, 30000, "fertilizer", "purchase-1")
assertTrue(reserveOk, "first reservation succeeds")
assertEqual(reservation.amount, 30000, "reservation amount")
assertEqual(reservations:getReservedAmount(ciloc.id), 30000, "reserved total")
assertEqual(reservations:getEffectiveAvailableCredit(ciloc), 45000, "effective availability after reservation")

local reserveFail, reserveError = reservations:reserveAgainstLiability(ciloc, 1, 50000, "seed", "purchase-2")
assertFalse(reserveFail, "reservation cannot double-spend line availability")
assertEqual(reserveError, "CREDIT_LIMIT_EXCEEDED_BY_RESERVATIONS", "reservation limit error")

local consumeOk, consumed = reservations:consume(reservation.id)
assertTrue(consumeOk, "reservation consumed")
assertEqual(consumed.status, AGFCreditReservationStatus.CONSUMED, "reservation consumed state")
assertEqual(reservations:getReservedAmount(ciloc.id), 0, "consumed reservation no longer blocks capacity")

local releaseReservation = reservations:create(1, ciloc.id, 10000, "fuel", "purchase-3")
local registerRelease = reservations:register(releaseReservation)
assertTrue(registerRelease, "release test reservation registered")
local releasedOk, released = reservations:release(releaseReservation.id)
assertTrue(releasedOk, "reservation released")
assertEqual(released.status, AGFCreditReservationStatus.RELEASED, "reservation release state")

-- Pro-forma underwriting shows the proposed debt/down payment effect.
local quoteOk, quote = AGFLoanQuoteService.quote({
    purchasePrice = 250000,
    downPayment = 50000,
    periods = 60,
    balloonPercent = 0.20,
    rateComponents = {baseRate = 0.045, productSpread = 0.015, riskSpread = 0.005}
})
assertTrue(quoteOk, "quote for pro-forma succeeds")

local projection, projectionError = AGFProFormaUnderwritingService.fromLoanQuote({
    totalAssets = 1000000,
    totalLiabilities = 300000,
    currentAssets = 250000,
    currentLiabilities = 100000,
    annualDebtService = 80000,
    annualLeaseAndFixedCharges = 20000,
    cashAvailableForDebtService = 160000,
    cashAvailableForFixedCharges = 180000,
    securedDebt = 200000,
    collateralValue = 500000,
    cashAndLiquidAssets = 150000,
    next12MonthObligations = 100000
}, quote, {acquiredAssetValue = 250000, newEligibleCollateral = 225000})
assertEqual(projectionError, nil, "pro-forma projection error")
assertTrue(projection.after.totalLiabilities > projection.before.totalLiabilities, "pro-forma liabilities increase")
assertTrue(projection.after.workingCapital < projection.before.workingCapital, "down payment reduces working capital")
assertTrue(projection.after.dscr < projection.before.dscr, "new debt service lowers DSCR")

-- Payment allocation keeps fees, interest, and principal separately auditable.
local allocationOk, allocation = AGFPaymentAllocationService.allocate(1500, {
    principal = 10000,
    interest = 800,
    fees = 200
})
assertTrue(allocationOk, "payment allocation succeeds")
assertEqual(allocation.appliedFees, 200, "fees paid first")
assertEqual(allocation.appliedInterest, 800, "interest paid second")
assertEqual(allocation.appliedPrincipal, 500, "remaining payment to principal")
assertEqual(allocation.principalAfter, 9500, "principal after allocation")
assertEqual(allocation.unappliedAmount, 0, "no unapplied allocation")

local payoffAllocationOk, payoffAllocation = AGFPaymentAllocationService.allocate(12000, {
    principal = 10000,
    interest = 800,
    fees = 200
})
assertTrue(payoffAllocationOk, "overpayment allocation succeeds")
assertEqual(payoffAllocation.totalOutstandingAfter, 0, "full payoff clears components")
assertEqual(payoffAllocation.unappliedAmount, 1000, "excess remains unapplied")

-- Lease registry creates fixed-charge obligations without owned-debt semantics.
local leases = AGFLeaseRegistry.new(ids, writableRuntime, nil)
local lease, leaseError = leases:create("AGF-ASSET-000900", AGFLeaseType.FARMLAND, 1, 5000, 36, "Quarter lease")
assertEqual(leaseError, nil, "lease create error")
local leaseRegistered, leaseRecord = leases:register(lease)
assertTrue(leaseRegistered, "lease registered")
local activated, activeLease = leases:activate(leaseRecord.id, 2026, 9)
assertTrue(activated, "lease activated")
assertEqual(activeLease.status, AGFLeaseStatus.ACTIVE, "lease active state")
assertEqual(leases:getAnnualFixedCharges(1), 60000, "annualized lease fixed charge")

local accruedOk, accrued = leases:accruePeriodicRent(activeLease.id)
assertTrue(accruedOk, "periodic rent accrued")
assertEqual(accrued.accruedRent, 5000, "accrued rent")
local rentPaidOk, rentPayment = leases:applyRentPayment(activeLease.id, 5000)
assertTrue(rentPaidOk, "rent payment applied")
assertEqual(rentPayment.appliedRent, 5000, "rent payment component")
assertEqual(rentPayment.lease.accruedRent, 0, "rent cured")

-- Delinquency progression and cure are deterministic.
local delinquency = AGFDelinquencyStateMachine.newAccountState()
local missed1 = AGFDelinquencyStateMachine.recordMissedPayment(delinquency, 1000, nil, 2026, 9)
assertTrue(missed1, "first missed payment recorded")
assertEqual(delinquency.state, AGFDelinquencyState.PAST_DUE, "first missed payment state")
local missed2 = AGFDelinquencyStateMachine.recordMissedPayment(delinquency, 1000, nil, 2026, 10)
assertTrue(missed2, "second missed payment recorded")
assertEqual(delinquency.state, AGFDelinquencyState.DELINQUENT, "second missed payment state")
assertEqual(delinquency.pastDueAmount, 2000, "past due amount")

local partialCureOk, partialCure = AGFDelinquencyStateMachine.applyCurePayment(delinquency, 500, 2026, 10)
assertTrue(partialCureOk, "partial cure applied")
assertEqual(partialCure.applied, 500, "partial cure amount")
assertEqual(delinquency.state, AGFDelinquencyState.DELINQUENT, "partial cure does not reset state")
local fullCureOk = AGFDelinquencyStateMachine.applyCurePayment(delinquency, 1500, 2026, 10)
assertTrue(fullCureOk, "full cure applied")
assertEqual(delinquency.state, AGFDelinquencyState.CURRENT, "full cure returns current")
assertEqual(delinquency.missedPayments, 0, "full cure clears missed-payment count")

-- Settlement planning is deterministic and separates planning from execution.
local settlementOk, settlement = AGFSettlementPlanner.plan({
    {id = "LEASE-1", obligationType = "leaseRent", priority = 20, amountDue = 2000, minimumPayment = 2000, allowPartial = false, allowCreditDraw = false},
    {id = "LOAN-1", obligationType = "securedDebt", priority = 10, amountDue = 5000, minimumPayment = 2500, allowPartial = true, allowCreditDraw = true},
    {id = "LOAN-2", obligationType = "termDebt", priority = 30, amountDue = 3000, minimumPayment = 3000, allowPartial = false, allowCreditDraw = true}
}, 4000, 5000)
assertTrue(settlementOk, "settlement plan succeeds")
assertEqual(settlement.allocations[1].obligationId, "LOAN-1", "priority 10 first")
assertEqual(settlement.allocations[1].paid, 5000, "first obligation fully paid")
assertEqual(settlement.allocations[1].cashUsed, 4000, "cash used before credit")
assertEqual(settlement.allocations[1].creditDraw, 1000, "authorized credit draw fills first obligation")
assertEqual(settlement.allocations[2].obligationId, "LEASE-1", "priority 20 second")
assertEqual(settlement.allocations[2].paid, 0, "lease cannot use credit and no cash remains")
assertEqual(settlement.allocations[3].obligationId, "LOAN-2", "priority 30 third")
assertEqual(settlement.allocations[3].paid, 3000, "remaining authorized credit pays term obligation")
assertEqual(settlement.totalCreditDraw, 4000, "settlement total credit draw")
assertEqual(settlement.totalPaid, 8000, "settlement total paid")
assertEqual(settlement.totalUnpaid, 2000, "settlement unpaid amount")
assertEqual(settlement.endingOptionalCredit, 1000, "remaining optional credit")

-- Multiplayer request model is revision checked and idempotent.
local protocol = AGFFinancialProtocolState.new(ids, 16)
local beginOk, requestContext = protocol:beginRequest("REQ-1", "connection-1", "CREATE_LOAN", 0)
assertTrue(beginOk, "request begins at current revision")
assertFalse(requestContext.duplicate, "first request not duplicate")
local commitOk, result = protocol:commitRequest(requestContext, "SUCCESS", {liabilityId = "AGF-LIAB-000100"})
assertTrue(commitOk, "request committed")
assertEqual(result.previousRevision, 0, "operation previous revision")
assertEqual(result.newRevision, 1, "operation new revision")
assertEqual(protocol:getRevision(), 1, "server revision advanced")

local duplicateOk, duplicateContext = protocol:beginRequest("REQ-1", "connection-1", "CREATE_LOAN", 0)
assertTrue(duplicateOk, "duplicate request recognized")
assertTrue(duplicateContext.duplicate, "duplicate flag")
assertEqual(duplicateContext.cachedResult.operationId, result.operationId, "duplicate returns same operation")
assertEqual(protocol:getRevision(), 1, "duplicate does not advance revision")

local staleOk, staleError, expectedRevision = protocol:beginRequest("REQ-2", "connection-1", "DRAW_CREDIT", 0)
assertFalse(staleOk, "stale request rejected")
assertEqual(staleError, "STALE_STATE_REVISION", "stale revision error")
assertEqual(expectedRevision, 1, "authoritative revision returned")

local collisionOk, collisionError = protocol:beginRequest("REQ-1", "connection-2", "CREATE_LOAN", 1)
assertFalse(collisionOk, "request ID collision rejected")
assertEqual(collisionError, "REQUEST_ID_COLLISION", "request collision error")

print("offline_policy_tests: PASS")
