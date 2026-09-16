-- Offline validation for agricultural lease frequency, fixed charges, and due dates.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/core/IdService.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/PaymentFrequencyService.lua")
dofile("src/leasing/Lease.lua")
dofile("src/leasing/LeaseRegistry.lua")
dofile("src/leasing/LeaseScheduleService.lua")

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

local runtime = {canMutate = function() return true, nil end}
local ids = AGFIdService.new()
local registry = AGFLeaseRegistry.new(ids, runtime, nil)

-- Existing/default behavior remains monthly: $5,000 x 12 = $60,000 annual fixed charge.
local monthly, monthlyError = registry:create("FIELD-1", AGFLeaseType.FARMLAND, 1, 5000, 12, "Monthly field")
assertEqual(monthlyError, nil, "monthly lease create error")
assertEqual(monthly.paymentsPerYear, 12, "monthly lease default frequency")
assertEqual(monthly:getAnnualizedFixedCharge(), 60000, "monthly annualized fixed charge")
local monthlyRegistered, monthlyStored = registry:register(monthly)
assertTrue(monthlyRegistered, "monthly lease registered")
assertEqual(monthlyStored.paymentsPerYear, 12, "monthly frequency persisted in registry")
assertEqual(registry:getAnnualFixedCharges(1), 60000, "monthly fixed charges in farm total")

local monthlyScheduleOk, monthlySchedule = AGFLeaseScheduleService.build(monthlyStored, 2026, 4)
assertTrue(monthlyScheduleOk, "monthly lease schedule builds")
assertEqual(monthlySchedule.paymentCount, 12, "monthly payment count")
assertEqual(monthlySchedule.intervalPeriods, 1, "monthly interval")
assertEqual(monthlySchedule.firstDueYear, 2026, "monthly first due year")
assertEqual(monthlySchedule.firstDuePeriod, 5, "monthly first due period")
assertEqual(monthlySchedule.finalDueYear, 2027, "monthly final due year")
assertEqual(monthlySchedule.finalDuePeriod, 4, "monthly final due period")
assertEqual(monthlySchedule.totalContractedRent, 60000, "monthly total contracted rent")

-- Quarterly lease: $15,000 x 4 = the same $60,000 annual fixed charge.
local quarterly, quarterlyError = registry:create("FIELD-2", AGFLeaseType.FARMLAND, 1, 15000, 8, "Quarterly field", 4)
assertEqual(quarterlyError, nil, "quarterly lease create error")
assertEqual(quarterly.paymentsPerYear, 4, "quarterly lease frequency")
assertEqual(quarterly:getAnnualizedFixedCharge(), 60000, "quarterly annualized fixed charge")
local quarterlyRegistered, quarterlyStored = registry:register(quarterly)
assertTrue(quarterlyRegistered, "quarterly lease registered")
assertEqual(registry:getAnnualFixedCharges(1), 120000, "mixed-frequency farm fixed charges sum annual equivalents")

local quarterlyScheduleOk, quarterlySchedule = AGFLeaseScheduleService.build(quarterlyStored, 2026, 10)
assertTrue(quarterlyScheduleOk, "quarterly lease schedule builds")
assertEqual(quarterlySchedule.intervalPeriods, 3, "quarterly interval")
assertEqual(quarterlySchedule.paymentCount, 8, "quarterly two-year payment count")
assertEqual(quarterlySchedule.annualizedRent, 60000, "quarterly schedule annualized rent")
assertEqual(quarterlySchedule.totalContractedRent, 120000, "quarterly total contracted rent")
assertEqual(quarterlySchedule.firstDueYear, 2027, "quarterly first due year")
assertEqual(quarterlySchedule.firstDuePeriod, 1, "quarterly first due period")
assertEqual(quarterlySchedule.finalDueYear, 2028, "quarterly final due year")
assertEqual(quarterlySchedule.finalDuePeriod, 10, "quarterly final due period")

-- Semi-annual/annual structures align rent with agricultural cash-flow timing.
local semi, semiError = registry:create("FIELD-3", AGFLeaseType.FARMLAND, 2, 30000, 4, "Semiannual field", 2)
assertEqual(semiError, nil, "semiannual lease create error")
assertEqual(semi:getAnnualizedFixedCharge(), 60000, "semiannual annualized fixed charge")
assertTrue(registry:register(semi), "semiannual lease registered")
local semiScheduleOk, semiSchedule = AGFLeaseScheduleService.build(semi, 2026, 6)
assertTrue(semiScheduleOk, "semiannual schedule builds")
assertEqual(semiSchedule.intervalPeriods, 6, "semiannual interval")
assertEqual(semiSchedule.firstDueYear, 2026, "semiannual first due year")
assertEqual(semiSchedule.firstDuePeriod, 12, "semiannual first due period")
assertEqual(semiSchedule.schedule[2].dueYear, 2027, "semiannual second due year")
assertEqual(semiSchedule.schedule[2].duePeriod, 6, "semiannual second due period")

local annual, annualError = registry:create("FIELD-4", AGFLeaseType.FARMLAND, 2, 60000, 3, "Annual field", 1)
assertEqual(annualError, nil, "annual lease create error")
assertEqual(annual:getAnnualizedFixedCharge(), 60000, "annual lease annualized fixed charge")
assertTrue(registry:register(annual), "annual lease registered")
local annualScheduleOk, annualSchedule = AGFLeaseScheduleService.build(annual, 2026, 9)
assertTrue(annualScheduleOk, "annual schedule builds")
assertEqual(annualSchedule.firstDueYear, 2027, "annual first due year")
assertEqual(annualSchedule.firstDuePeriod, 9, "annual payment stays on selected farm-season month")
assertEqual(annualSchedule.finalDueYear, 2029, "annual final due year")
assertEqual(annualSchedule.finalDuePeriod, 9, "annual final due period")
assertEqual(annualSchedule.totalContractedRent, 180000, "annual three-year contracted rent")
assertEqual(registry:getAnnualFixedCharges(2), 120000, "two annual-equivalent leases summed")

-- First rent due can be explicitly deferred while later cadence remains intact.
local deferredOk, deferred = AGFLeaseScheduleService.build(quarterlyStored, 2026, 4, 6)
assertTrue(deferredOk, "deferred first rent schedule builds")
assertEqual(deferred.firstDueYear, 2026, "deferred first due year")
assertEqual(deferred.firstDuePeriod, 10, "deferred first due period")
assertEqual(deferred.schedule[2].dueYear, 2027, "deferred second due year")
assertEqual(deferred.schedule[2].duePeriod, 1, "deferred second due keeps quarterly cadence")

-- Clones retain frequency and returned records cannot rewrite registry authority.
local clone = quarterlyStored:clone()
assertEqual(clone.paymentsPerYear, 4, "lease clone preserves frequency")
clone.paymentsPerYear = 12
assertEqual(registry:get(quarterlyStored.id).paymentsPerYear, 4, "lease query remains authoritative")

-- Invalid frequencies/terms/money are rejected before registration.
local fivePerYear, fiveError = registry:create("FIELD-5", AGFLeaseType.FARMLAND, 1, 10000, 5, "Bad frequency", 5)
assertEqual(fivePerYear, nil, "five-payments/year lease rejected")
assertEqual(fiveError, "INVALID_LEASE_PAYMENT_FREQUENCY", "unaligned lease frequency error")

local nanRent, nanRentError = registry:create("FIELD-5", AGFLeaseType.FARMLAND, 1, 0 / 0, 12, "NaN rent", 12)
assertEqual(nanRent, nil, "NaN rent rejected")
assertEqual(nanRentError, "INVALID_RENT", "NaN rent error")

local fractionalTerm, fractionalTermError = registry:create("FIELD-5", AGFLeaseType.FARMLAND, 1, 1000, 12.5, "Fractional term", 12)
assertEqual(fractionalTerm, nil, "fractional lease term rejected")
assertEqual(fractionalTermError, "INVALID_LEASE_TERM", "fractional lease term error")

-- Registering a manually malformed lease also fails closed.
local malformed = AGFLease.new("AGF-LEASE-999999", "FIELD-5", AGFLeaseType.FARMLAND, 1)
malformed.periodicRent = 10000
malformed.termPeriods = 4
malformed.remainingPeriods = 4
malformed.paymentsPerYear = 5
local malformedOk, malformedError = registry:register(malformed)
assertFalse(malformedOk, "malformed frequency rejected at register boundary")
assertEqual(malformedError, "INVALID_LEASE_PAYMENT_FREQUENCY", "register frequency error")

-- Closing a lease removes it from annual fixed-charge underwriting while preserving history.
local beforeClose = registry:getAnnualFixedCharges(1)
assertEqual(beforeClose, 120000, "farm one fixed charges before close")
local closeOk, closed = registry:close(quarterlyStored.id, AGFLeaseStatus.COMPLETED, 2028, 10)
assertTrue(closeOk, "quarterly lease closes")
assertEqual(closed:getAnnualizedFixedCharge(), 0, "closed lease annual fixed charge zero")
assertEqual(registry:getAnnualFixedCharges(1), 60000, "closed lease removed from current fixed charges")
assertEqual(#registry:getFarmLeases(1, false), 1, "open lease query excludes closed lease")
assertEqual(#registry:getFarmLeases(1, true), 2, "historical lease query retains closed lease")

-- Schedule validation catches malformed direct lease records too.
local badScheduleLease = AGFLease.new("AGF-LEASE-888888", "FIELD-X", AGFLeaseType.FARMLAND, 1)
badScheduleLease.termPeriods = 0
badScheduleLease.periodicRent = 1000
local badScheduleOk, badScheduleError = AGFLeaseScheduleService.build(badScheduleLease, 2026, 1)
assertFalse(badScheduleOk, "zero-term lease schedule rejected")
assertEqual(badScheduleError, "INVALID_LEASE_TERM", "zero-term schedule error")

print("offline_lease_schedule_tests: PASS")
