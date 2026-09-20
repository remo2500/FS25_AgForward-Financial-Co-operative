-- AgForward Financial Cooperative
-- Pure atomic month/period settlement transaction planner. It joins the generic
-- liquidity allocation with current liability payment allocation and lease rent
-- intents. No balances, cash, delinquency, or journal records are mutated.

AGFSettlementExecutionPlanService = {}

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function copyIntent(intent)
    local copy = {}
    for key, value in pairs(intent or {}) do
        if type(value) == "table" then
            local child = {}
            for childKey, childValue in pairs(value) do child[childKey] = childValue end
            copy[key] = child
        else
            copy[key] = value
        end
    end
    return copy
end

local function indexDueRows(dueSchedule)
    local byId = {}
    for _, row in ipairs(dueSchedule ~= nil and dueSchedule.due or {}) do
        if row.id == nil then return nil, "DUE_ROW_ID_REQUIRED" end
        if byId[tostring(row.id)] ~= nil then return nil, "DUPLICATE_DUE_ROW:" .. tostring(row.id) end
        byId[tostring(row.id)] = row
    end
    return byId, nil
end

function AGFSettlementExecutionPlanService.build(settlementPlan, dueSchedule, liabilitiesById, optionalCreditFacility, context)
    context = context or {}
    if settlementPlan == nil or type(settlementPlan.allocations) ~= "table" then
        return false, "SETTLEMENT_PLAN_REQUIRED"
    end

    local dueById, dueError = indexDueRows(dueSchedule)
    if dueById == nil then return false, dueError end

    local totalCashUsed = money(settlementPlan.totalCashUsed)
    local totalCreditDraw = money(settlementPlan.totalCreditDraw)
    local totalPaid = money(settlementPlan.totalPaid)
    if totalCashUsed == nil or totalCreditDraw == nil or totalPaid == nil then
        return false, "INVALID_SETTLEMENT_TOTALS"
    end
    if not AGFCurrency.equals(totalPaid, AGFCurrency.round(totalCashUsed + totalCreditDraw)) then
        return false, "SETTLEMENT_LIQUIDITY_DOES_NOT_RECONCILE"
    end

    local groupId = context.groupId or "PENDING_SETTLEMENT_GROUP"
    local journalIntents = {}
    local creditDrawMutation = nil

    if totalCreditDraw > 0 then
        if optionalCreditFacility == nil or optionalCreditFacility.id == nil then
            return false, "SETTLEMENT_CREDIT_FACILITY_REQUIRED"
        end
        if optionalCreditFacility.productType ~= AGFProductType.OPERATING_LINE then
            return false, "SETTLEMENT_CREDIT_MUST_BE_OPERATING_LINE"
        end
        if optionalCreditFacility.status ~= nil and optionalCreditFacility.status ~= "active" then
            return false, "SETTLEMENT_CREDIT_NOT_ACTIVE"
        end
        if optionalCreditFacility.isRevolving ~= nil and not optionalCreditFacility:isRevolving() then
            return false, "SETTLEMENT_CREDIT_NOT_REVOLVING"
        end

        local available = optionalCreditFacility.getAvailableCredit ~= nil
            and money(optionalCreditFacility:getAvailableCredit())
            or money(context.optionalCreditAvailable)
        if available == nil then return false, "SETTLEMENT_CREDIT_AVAILABILITY_REQUIRED" end
        if AGFCurrency.toMinorUnits(totalCreditDraw) > AGFCurrency.toMinorUnits(available) then
            return false, "SETTLEMENT_CREDIT_LIMIT_EXCEEDED"
        end

        local principalBefore = money(optionalCreditFacility.principalBalance or 0) or 0
        creditDrawMutation = {
            liabilityId = optionalCreditFacility.id,
            principalDelta = totalCreditDraw,
            principalBefore = principalBefore,
            principalAfter = AGFCurrency.round(principalBefore + totalCreditDraw)
        }
        table.insert(journalIntents, {
            transactionType = AGFTransactionType.CREDIT_DRAW,
            amount = totalCreditDraw,
            farmId = optionalCreditFacility.farmId,
            liabilityId = optionalCreditFacility.id,
            fundingSource = AGFFundingSource.OPERATING_LINE,
            groupId = groupId,
            economicRole = "settlementLiquidity"
        })
    end

    local liabilityPaymentPlans = {}
    local leasePaymentPlans = {}
    local servicingExceptions = {}
    local calculatedPaid = 0

    for _, allocation in ipairs(settlementPlan.allocations) do
        local due = dueById[tostring(allocation.obligationId)]
        if due == nil then return false, "SETTLEMENT_ALLOCATION_NOT_IN_DUE_SCHEDULE:" .. tostring(allocation.obligationId) end

        local paid = money(allocation.paid)
        local unpaid = money(allocation.unpaid)
        local amountDue = money(due.amountDue)
        if paid == nil or unpaid == nil or amountDue == nil then return false, "INVALID_SETTLEMENT_ALLOCATION" end
        if not AGFCurrency.equals(AGFCurrency.round(paid + unpaid), amountDue) then
            return false, "ALLOCATION_DOES_NOT_RECONCILE:" .. tostring(allocation.obligationId)
        end

        if paid > 0 then
            calculatedPaid = AGFCurrency.round(calculatedPaid + paid)

            if due.sourceType == "loan" then
                local liability = liabilitiesById ~= nil and liabilitiesById[tostring(due.liabilityId)] or nil
                if liability == nil then return false, "SETTLEMENT_LIABILITY_REQUIRED:" .. tostring(due.liabilityId) end

                local paymentOk, paymentPlan = AGFLiabilityPaymentPlanService.plan(
                    liability,
                    paid,
                    context.paymentAllocationOrder,
                    AGFFundingSource.CASH
                )
                if not paymentOk then return false, paymentPlan end
                if not AGFCurrency.equals(paymentPlan.acceptedPayment, paid) or paymentPlan.unappliedAmount > 0 then
                    return false, "SETTLEMENT_PAYMENT_EXCEEDS_CURRENT_OUTSTANDING:" .. tostring(due.liabilityId)
                end

                paymentPlan.obligationId = due.id
                table.insert(liabilityPaymentPlans, paymentPlan)
                for _, intent in ipairs(paymentPlan.journalIntents) do
                    local copied = copyIntent(intent)
                    copied.farmId = liability.farmId
                    copied.groupId = groupId
                    copied.obligationId = due.id
                    table.insert(journalIntents, copied)
                end
            elseif due.sourceType == "lease" then
                table.insert(leasePaymentPlans, {
                    obligationId = due.id,
                    leaseId = due.leaseId,
                    farmId = due.farmId,
                    appliedRent = paid,
                    unpaidRent = unpaid
                })
                table.insert(journalIntents, {
                    transactionType = AGFTransactionType.LEASE_RENT,
                    amount = -paid,
                    farmId = due.farmId,
                    assetId = due.assetId,
                    fundingSource = AGFFundingSource.CASH,
                    expenseCategory = AGFExpenseCategory.LAND_RENT,
                    groupId = groupId,
                    obligationId = due.id,
                    leaseId = due.leaseId,
                    economicRole = "leaseSettlement"
                })
            else
                return false, "UNSUPPORTED_SETTLEMENT_SOURCE_TYPE:" .. tostring(due.sourceType)
            end
        end

        if unpaid > 0 then
            table.insert(servicingExceptions, {
                obligationId = due.id,
                sourceType = due.sourceType,
                liabilityId = due.liabilityId,
                leaseId = due.leaseId,
                amountDue = amountDue,
                paid = paid,
                unpaid = unpaid,
                fullyUnpaid = AGFCurrency.equals(paid, 0),
                partial = paid > 0,
                action = "servicingReview"
            })
        end
    end

    if not AGFCurrency.equals(calculatedPaid, totalPaid) then
        return false, "SETTLEMENT_PAID_TOTAL_MISMATCH"
    end

    local ledgerNet = 0
    for _, intent in ipairs(journalIntents) do
        ledgerNet = AGFCurrency.round(ledgerNet + (intent.amount or 0))
    end
    local expectedCashDelta = -totalCashUsed
    if not AGFCurrency.equals(ledgerNet, expectedCashDelta) then
        return false, "SETTLEMENT_EXECUTION_RECONCILIATION_FAILED"
    end

    return true, {
        planType = "periodSettlement",
        groupId = groupId,
        totalPaid = totalPaid,
        totalCashUsed = totalCashUsed,
        totalCreditDraw = totalCreditDraw,
        totalUnpaid = money(settlementPlan.totalUnpaid) or 0,
        fsCashDelta = expectedCashDelta,
        ledgerNet = ledgerNet,
        journalIntents = journalIntents,
        creditDrawMutation = creditDrawMutation,
        liabilityPaymentPlans = liabilityPaymentPlans,
        leasePaymentPlans = leasePaymentPlans,
        servicingExceptions = servicingExceptions,
        atomicEffects = {
            totalCreditDraw > 0 and "drawSettlementCredit" or nil,
            "moveFSCash",
            "applyLiabilityPayments",
            "applyLeasePayments",
            "postLedgerGroup",
            "updateServicingState"
        }
    }
end
