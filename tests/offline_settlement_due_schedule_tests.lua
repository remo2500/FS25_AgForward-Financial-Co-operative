-- Offline current-period settlement due extraction and planner integration.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/settlement/SettlementDueScheduleService.lua")
dofile("src/settlement/SettlementPlanner.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local loanEntries = {
    {
        liabilityId = "AGF-LIAB-1",
        farmId = 1,
        productType = AGFProductType.EQUIPMENT_FINANCE,
        obligationType = "securedDebt",
        contractSchedule = {
            schedule = {
                {paymentNumber = 1, dueYear = 2026, duePeriod = 9, regularPrincipal = 4200, interest = 800, balloonPayment = 0, totalPayment = 5000},
                {paymentNumber = 2, dueYear = 2026, duePeriod = 10, regularPrincipal = 4250, interest = 750, balloonPayment = 0, totalPayment = 5000}
            }
        }
    },
    {
        liabilityId = "AGF-LIAB-2",
        farmId = 1,
        productType = AGFProductType.LAND_FINANCE,
        obligationType = "landDebt",
        contractSchedule = {
            schedule = {
                {paymentNumber = 1, dueYear = 2026, duePeriod = 12, regularPrincipal = 10000, interest = 5000, balloonPayment = 0, totalPayment = 15000}
            }
        }
    }
}

local leaseEntries = {
    {
        leaseId = "AGF-LEASE-1",
        farmId = 1,
        productType = AGFProductType.LAND_LEASE,
        obligationType = "leaseRent",
        leaseSchedule = {
            schedule = {
                {paymentNumber = 1, dueYear = 2026, duePeriod = 9, rent = 3000}
            }
        }
    }
}

local policy = {
    default = {priority = 100, allowPartial = false, allowCreditDraw = false},
    byObligationType = {
        leaseRent = {priority = 20, allowPartial = false, allowCreditDraw = false}
    },
    byProduct = {
        [AGFProductType.EQUIPMENT_FINANCE] = {
            priority = 10,
            allowPartial = true,
            allowCreditDraw = true,
            minimumPaymentPercent = 0.50
        }
    }
}

local ok, due = AGFSettlementDueScheduleService.build(2026, 9, loanEntries, leaseEntries, policy)
assertTrue(ok, "due schedule succeeds")
assertEqual(#due.due, 2, "two obligations due")
assertEqual(due.totalScheduledDue, 8000, "total scheduled due")
assertEqual(due.loanDue, 5000, "loan due")
assertEqual(due.leaseDue, 3000, "lease due")
assertEqual(due.due[1].liabilityId, "AGF-LIAB-1", "equipment priority first")
assertEqual(due.due[1].minimumPayment, 2500, "equipment minimum policy")
assertEqual(due.due[1].scheduledPrincipal, 4200, "scheduled principal")
assertEqual(due.due[1].scheduledInterest, 800, "scheduled interest")
assertTrue(due.due[1].requiresAuthoritativeBalanceReconciliation, "schedule is not live balance authority")
assertEqual(due.due[2].leaseId, "AGF-LEASE-1", "lease priority second")

local settlementOk, settlement = AGFSettlementPlanner.plan(due.plannerObligations, 4000, 3000)
assertTrue(settlementOk, "planner accepts due schedule obligations")
assertEqual(settlement.allocations[1].paid, 5000, "equipment paid using cash plus credit")
assertEqual(settlement.allocations[1].cashUsed, 4000, "cash first")
assertEqual(settlement.allocations[1].creditDraw, 1000, "credit fills equipment payment")
assertEqual(settlement.allocations[2].paid, 0, "lease cannot use optional credit")
assertEqual(settlement.totalUnpaid, 3000, "lease unpaid")

local reconcileOk, reconcileError = AGFSettlementDueScheduleService.build(2026, 9, {{
    liabilityId = "BAD",
    farmId = 1,
    productType = AGFProductType.TERM_LOAN,
    contractSchedule = {
        schedule = {
            {paymentNumber = 1, dueYear = 2026, duePeriod = 9, regularPrincipal = 1000, interest = 100, balloonPayment = 0, totalPayment = 1200}
        }
    }
}}, {}, {})
assertEqual(reconcileOk, false, "non-reconciling contract row rejected")
assertEqual(reconcileError, "LOAN_DUE_ROW_DOES_NOT_RECONCILE:BAD", "reconciliation error")

print("offline_settlement_due_schedule_tests: PASS")
