-- Deterministic invariant test matrix for AgForward financial math.
-- This is not random/fuzzy runtime testing; it systematically exercises many
-- valid combinations under stock Lua 5.1.

dofile("src/core/Currency.lua")
dofile("src/finance/RateConvention.lua")
dofile("src/finance/RatePricingService.lua")
dofile("src/finance/AmortizationService.lua")
dofile("src/finance/RevolvingInterestService.lua")
dofile("src/input/FundingDecisionService.lua")

local function fail(message)
    error(message)
end

local principals = {1000, 9999.99, 50000, 250000, 1000000}
local rates = {0, 0.025, 0.05, 0.0875, 0.15}
local terms = {1, 6, 12, 60, 120}
local balloonRatios = {0, 0.10, 0.50, 1.0}

local scheduleCount = 0
for _, principal in ipairs(principals) do
    for _, rate in ipairs(rates) do
        for _, term in ipairs(terms) do
            for _, balloonRatio in ipairs(balloonRatios) do
                local balloon = AGFCurrency.round(principal * balloonRatio)
                local result, errorCode = AGFAmortizationService.generateSchedule(principal, rate, term, balloon)
                if result == nil then
                    fail(string.format(
                        "schedule failed p=%s rate=%s term=%s balloon=%s: %s",
                        tostring(principal), tostring(rate), tostring(term), tostring(balloon), tostring(errorCode)
                    ))
                end

                if #result.schedule ~= term then
                    fail("schedule length mismatch")
                end
                if not AGFCurrency.equals(result.totalPrincipal, principal) then
                    fail("principal reconciliation mismatch")
                end
                if not AGFCurrency.equals(result.schedule[#result.schedule].endingBalance, 0) then
                    fail("ending balance not zero")
                end
                if result.totalInterest < 0 then
                    fail("negative total interest")
                end
                if not AGFCurrency.equals(result.totalPayments, result.totalPrincipal + result.totalInterest) then
                    fail("payments do not reconcile to principal plus interest")
                end

                local previousEnding = AGFCurrency.round(principal)
                for index, row in ipairs(result.schedule) do
                    if not AGFCurrency.equals(row.openingBalance, previousEnding) then
                        fail(string.format("opening/ending continuity mismatch at period %d", index))
                    end
                    if row.interest < 0 or row.regularPrincipal < 0 or row.balloonPayment < 0 or row.totalPayment < 0 then
                        fail("negative schedule component")
                    end
                    if row.endingBalance < 0 then
                        fail("negative ending balance")
                    end
                    previousEnding = row.endingBalance
                end

                scheduleCount = scheduleCount + 1
            end
        end
    end
end

-- Revolving-credit invariant matrix: a draw/repayment path must reproduce its
-- final balance and never produce negative interest.
local revolvingCount = 0
for _, opening in ipairs({0, 1000, 25000, 100000}) do
    for _, annualRate in ipairs({0, 0.03, 0.08, 0.15}) do
        local changes = {
            {periodFraction = 0.20, amount = 10000, sequence = 1},
            {periodFraction = 0.60, amount = 5000, sequence = 2},
            {periodFraction = 0.90, amount = -5000, sequence = 3}
        }
        local result, errorCode = AGFRevolvingInterestService.calculatePeriodInterest(opening, changes, annualRate)
        if result == nil then
            fail("revolving calculation failed: " .. tostring(errorCode))
        end
        if not AGFCurrency.equals(result.endingBalance, opening + 10000) then
            fail("revolving ending balance mismatch")
        end
        if result.averageBalance < 0 or result.interest < 0 then
            fail("negative revolving result")
        end
        revolvingCount = revolvingCount + 1
    end
end

-- Funding decisions must always reconcile to the purchase amount when approved.
local fundingCount = 0
for _, policy in ipairs({
    AGFFundingPolicy.OFF,
    AGFFundingPolicy.CASH_SHORTFALL_ONLY,
    AGFFundingPolicy.PREFER_LINE,
    AGFFundingPolicy.ALWAYS_LINE
}) do
    for _, amount in ipairs({100, 1234.56, 10000}) do
        for _, cash in ipairs({0, amount / 2, amount, amount * 2}) do
            for _, line in ipairs({0, amount / 2, amount, amount * 2}) do
                local ok, resultOrError = AGFFundingDecisionService.decide(amount, cash, line, true, policy)
                if ok then
                    local result = resultOrError
                    if not AGFCurrency.equals(result.cashContribution + result.lineContribution, amount) then
                        fail("funding allocation does not reconcile")
                    end
                    if result.cashContribution < 0 or result.lineContribution < 0 then
                        fail("negative funding contribution")
                    end
                    if AGFCurrency.toMinorUnits(result.cashContribution) > AGFCurrency.toMinorUnits(cash) then
                        fail("funding uses more cash than available")
                    end
                    if AGFCurrency.toMinorUnits(result.lineContribution) > AGFCurrency.toMinorUnits(line) then
                        fail("funding uses more line than available")
                    end
                end
                fundingCount = fundingCount + 1
            end
        end
    end
end

print(string.format(
    "offline_invariant_tests: PASS (%d amortization schedules, %d revolver cases, %d funding cases)",
    scheduleCount,
    revolvingCount,
    fundingCount
))
