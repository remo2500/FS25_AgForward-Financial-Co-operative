-- AgForward Financial Cooperative
-- Read-only expectation model for Red Tape/native-accounting coexistence.
-- This service does not call Red Tape, register MoneyTypes, or inject tax rows.

AGFRedTapeReconciliationExpectationService = {}

local function addBucket(map, key, amount)
    local normalizedKey = key or "unclassified"
    map[normalizedKey] = map[normalizedKey] or {
        count = 0,
        netAmount = 0,
        cashVolume = 0
    }
    local bucket = map[normalizedKey]
    local value = AGFCurrency.round(tonumber(amount) or 0)
    bucket.count = bucket.count + 1
    bucket.netAmount = AGFCurrency.round(bucket.netAmount + value)
    bucket.cashVolume = AGFCurrency.round(bucket.cashVolume + math.abs(value))
end

local function copyMetadata(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

function AGFRedTapeReconciliationExpectationService.build(transactions)
    local result = {
        transactionCount = 0,
        mappedCount = 0,
        unresolvedCount = 0,
        mappedCashVolume = 0,
        unresolvedCashVolume = 0,
        byTreatment = {},
        byRole = {},
        byPreferredStatistic = {},
        rows = {},
        unresolved = {},
        nativeReconcile = {},
        supplementIfMissing = {},
        ignoredForTax = {},
        externalAuthority = {}
    }

    for _, transaction in ipairs(transactions or {}) do
        result.transactionCount = result.transactionCount + 1
        local amount = AGFCurrency.round(tonumber(transaction.amount) or 0)
        local intent = AGFMoneyMovementIntent.get(transaction.transactionType)

        if intent == nil then
            result.unresolvedCount = result.unresolvedCount + 1
            result.unresolvedCashVolume = AGFCurrency.round(result.unresolvedCashVolume + math.abs(amount))
            table.insert(result.unresolved, {
                transactionId = transaction.id,
                groupId = transaction.groupId,
                transactionType = transaction.transactionType,
                amount = amount,
                reason = "NO_MONEY_MOVEMENT_INTENT"
            })
        else
            result.mappedCount = result.mappedCount + 1
            result.mappedCashVolume = AGFCurrency.round(result.mappedCashVolume + math.abs(amount))

            local directionValid = true
            local directionError = nil
            if not AGFCurrency.equals(amount, 0) then
                directionValid, directionError = AGFMoneyMovementIntent.validateCashAmount(
                    transaction.transactionType,
                    amount
                )
            end

            local row = {
                transactionId = transaction.id,
                groupId = transaction.groupId,
                transactionType = transaction.transactionType,
                amount = amount,
                role = intent.role,
                taxTreatment = intent.taxTreatment,
                preferredStatistic = intent.preferredStatistic,
                preserveUnderlyingMoneyType = intent.preserveUnderlyingMoneyType == true,
                requiresRuntimeProof = intent.requiresRuntimeProof == true,
                directionValid = directionValid,
                directionError = directionError,
                expenseCategory = transaction.expenseCategory,
                fundingSource = transaction.fundingSource,
                liabilityId = transaction.liabilityId,
                assetId = transaction.assetId,
                metadata = copyMetadata(transaction.metadata)
            }
            table.insert(result.rows, row)

            addBucket(result.byTreatment, intent.taxTreatment, amount)
            addBucket(result.byRole, intent.role, amount)
            addBucket(result.byPreferredStatistic, intent.preferredStatistic or "underlyingOrNone", amount)

            if intent.taxTreatment == AGFRedTapeTreatment.NATIVE_RECONCILE then
                table.insert(result.nativeReconcile, row)
            elseif intent.taxTreatment == AGFRedTapeTreatment.SUPPLEMENT_IF_MISSING then
                table.insert(result.supplementIfMissing, row)
            elseif intent.taxTreatment == AGFRedTapeTreatment.IGNORE_TAX then
                table.insert(result.ignoredForTax, row)
            elseif intent.taxTreatment == AGFRedTapeTreatment.EXTERNAL_AUTHORITY then
                table.insert(result.externalAuthority, row)
            end
        end
    end

    result.requiresRuntimeReconciliation = #result.nativeReconcile > 0
        or #result.supplementIfMissing > 0
        or result.unresolvedCount > 0
    result.safeToAutoInject = false
    result.blockingUnknownTransactionTypes = result.unresolvedCount > 0

    return result
end
