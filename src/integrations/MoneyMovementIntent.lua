-- AgForward Financial Cooperative
-- Semantic bridge contract between AgForward accounting and future FS MoneyTypes.
-- No live MoneyType registration occurs in this module.

AGFMoneyMovementRole = {
    FINANCING_INFLOW = "financingInflow",
    LIABILITY_REDUCTION = "liabilityReduction",
    INTEREST_EXPENSE = "interestExpense",
    FINANCE_FEE_EXPENSE = "financeFeeExpense",
    LEASE_RENT_EXPENSE = "leaseRentExpense",
    OPERATING_PURCHASE = "operatingPurchase",
    ASSET_ACQUISITION = "assetAcquisition",
    ASSET_DISPOSAL = "assetDisposal",
    GRANT_FUNDING = "grantFunding"
}

AGFRedTapeTreatment = {
    IGNORE_TAX = "ignoreTax",
    NATIVE_RECONCILE = "nativeReconcile",
    SUPPLEMENT_IF_MISSING = "supplementIfMissing",
    EXTERNAL_AUTHORITY = "externalAuthority"
}

AGFMoneyMovementIntent = {}

local INTENTS = {
    [AGFTransactionType.LOAN_PROCEEDS] = {
        role = AGFMoneyMovementRole.FINANCING_INFLOW,
        cashDirection = 1,
        taxTreatment = AGFRedTapeTreatment.IGNORE_TAX,
        preferredStatistic = "other",
        requiresRuntimeProof = true
    },
    [AGFTransactionType.CREDIT_DRAW] = {
        role = AGFMoneyMovementRole.FINANCING_INFLOW,
        cashDirection = 1,
        taxTreatment = AGFRedTapeTreatment.IGNORE_TAX,
        preferredStatistic = "other",
        requiresRuntimeProof = true
    },
    [AGFTransactionType.PRINCIPAL_PAYMENT] = {
        role = AGFMoneyMovementRole.LIABILITY_REDUCTION,
        cashDirection = -1,
        taxTreatment = AGFRedTapeTreatment.IGNORE_TAX,
        preferredStatistic = "other",
        requiresRuntimeProof = true
    },
    [AGFTransactionType.CREDIT_REPAYMENT] = {
        role = AGFMoneyMovementRole.LIABILITY_REDUCTION,
        cashDirection = -1,
        taxTreatment = AGFRedTapeTreatment.IGNORE_TAX,
        preferredStatistic = "other",
        requiresRuntimeProof = true
    },
    [AGFTransactionType.INTEREST_PAYMENT] = {
        role = AGFMoneyMovementRole.INTEREST_EXPENSE,
        cashDirection = -1,
        taxTreatment = AGFRedTapeTreatment.NATIVE_RECONCILE,
        preferredStatistic = "bankLoanInterest",
        requiresRuntimeProof = true
    },
    [AGFTransactionType.FINANCE_FEE] = {
        role = AGFMoneyMovementRole.FINANCE_FEE_EXPENSE,
        cashDirection = -1,
        taxTreatment = AGFRedTapeTreatment.SUPPLEMENT_IF_MISSING,
        preferredStatistic = "other",
        requiresRuntimeProof = true
    },
    [AGFTransactionType.LATE_FEE] = {
        role = AGFMoneyMovementRole.FINANCE_FEE_EXPENSE,
        cashDirection = -1,
        taxTreatment = AGFRedTapeTreatment.SUPPLEMENT_IF_MISSING,
        preferredStatistic = "other",
        requiresRuntimeProof = true
    },
    [AGFTransactionType.LEASE_RENT] = {
        role = AGFMoneyMovementRole.LEASE_RENT_EXPENSE,
        cashDirection = -1,
        taxTreatment = AGFRedTapeTreatment.SUPPLEMENT_IF_MISSING,
        preferredStatistic = "agfLeaseRent",
        requiresRuntimeProof = true
    },
    [AGFTransactionType.INPUT_PURCHASE] = {
        role = AGFMoneyMovementRole.OPERATING_PURCHASE,
        cashDirection = -1,
        taxTreatment = AGFRedTapeTreatment.NATIVE_RECONCILE,
        preferredStatistic = nil,
        requiresRuntimeProof = true,
        preserveUnderlyingMoneyType = true
    },
    [AGFTransactionType.ASSET_PURCHASE] = {
        role = AGFMoneyMovementRole.ASSET_ACQUISITION,
        cashDirection = -1,
        taxTreatment = AGFRedTapeTreatment.NATIVE_RECONCILE,
        preferredStatistic = nil,
        requiresRuntimeProof = true,
        preserveUnderlyingMoneyType = true
    },
    [AGFTransactionType.ASSET_SALE] = {
        role = AGFMoneyMovementRole.ASSET_DISPOSAL,
        cashDirection = 1,
        taxTreatment = AGFRedTapeTreatment.NATIVE_RECONCILE,
        preferredStatistic = nil,
        requiresRuntimeProof = true,
        preserveUnderlyingMoneyType = true
    },
    [AGFTransactionType.GRANT_RECEIPT] = {
        role = AGFMoneyMovementRole.GRANT_FUNDING,
        cashDirection = 1,
        taxTreatment = AGFRedTapeTreatment.EXTERNAL_AUTHORITY,
        preferredStatistic = nil,
        requiresRuntimeProof = true,
        preserveUnderlyingMoneyType = true
    }
}

local function cloneIntent(intent)
    if intent == nil then return nil end
    local copy = {}
    for key, value in pairs(intent) do copy[key] = value end
    return copy
end

function AGFMoneyMovementIntent.get(transactionType)
    return cloneIntent(INTENTS[transactionType])
end

function AGFMoneyMovementIntent.has(transactionType)
    return INTENTS[transactionType] ~= nil
end

function AGFMoneyMovementIntent.getAll()
    local result = {}
    for transactionType, intent in pairs(INTENTS) do
        result[transactionType] = cloneIntent(intent)
    end
    return result
end

function AGFMoneyMovementIntent.validateCashAmount(transactionType, amount)
    local intent = INTENTS[transactionType]
    if intent == nil then return false, "UNKNOWN_MONEY_MOVEMENT_INTENT" end
    local normalized = AGFCurrency.round(tonumber(amount) or 0)
    if AGFCurrency.equals(normalized, 0) then return false, "ZERO_CASH_MOVEMENT" end
    if intent.cashDirection > 0 and normalized < 0 then return false, "CASH_DIRECTION_MISMATCH" end
    if intent.cashDirection < 0 and normalized > 0 then return false, "CASH_DIRECTION_MISMATCH" end
    return true, nil
end
