-- AgForward Financial Cooperative
-- Pure atomic-close planner. It translates an approved origination plan into
-- semantic mutation intents without touching FS25 cash, assets, liabilities,
-- liens, or the canonical ledger.

AGFOriginationClosePlanService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function nonNegativeMoney(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function positiveMoney(value)
    local number = nonNegativeMoney(value)
    if number == nil or number <= 0 then return nil end
    return number
end

local function positiveInteger(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

local function copyTable(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            local child = {}
            for childKey, childValue in pairs(value) do child[childKey] = childValue end
            result[key] = child
        else
            result[key] = value
        end
    end
    return result
end

local function fundingSourceForProduct(productType)
    if productType == AGFProductType.OPERATING_LINE then return AGFFundingSource.OPERATING_LINE end
    if productType == AGFProductType.CROP_INPUT_LINE then return AGFFundingSource.CROP_INPUT_LINE end
    if productType == AGFProductType.EQUIPMENT_FINANCE then return AGFFundingSource.EQUIPMENT_FINANCE end
    if productType == AGFProductType.PROJECT_FINANCE then return AGFFundingSource.PROJECT_FINANCE end
    if productType == AGFProductType.LAND_FINANCE then return AGFFundingSource.LAND_FINANCE end
    return AGFFundingSource.TERM_LOAN
end

function AGFOriginationClosePlanService.build(originationPlan, context)
    context = context or {}
    if originationPlan == nil or originationPlan.planType == nil then
        return false, "ORIGINATION_PLAN_REQUIRED"
    end

    local farmId = positiveInteger(originationPlan.farmId)
    if farmId == nil then return false, "INVALID_FARM_ID" end
    if originationPlan.liability == nil then return false, "LIABILITY_PLAN_REQUIRED" end

    local productType = originationPlan.productType or originationPlan.liability.productType
    if productType == nil then return false, "PRODUCT_TYPE_REQUIRED" end

    -- Project finance has a staged-draw model. Treating the approved commitment
    -- as fully advanced on closing would overstate principal and cash.
    if productType == AGFProductType.PROJECT_FINANCE then
        return false, "PROJECT_FINANCE_REQUIRES_DRAW_BASED_CLOSE"
    end

    local groupId = context.groupId or "PENDING_ORIGINATION_GROUP"
    local liabilityIntent = copyTable(originationPlan.liability)
    liabilityIntent.status = "active"
    liabilityIntent.farmId = farmId
    liabilityIntent.productType = productType
    liabilityIntent.proposedLiabilityId = context.liabilityId

    local securityIntent = copyTable(originationPlan.security)
    if securityIntent.mode == "specificLien" then
        if securityIntent.assetId == nil or securityIntent.assetId == "" then
            return false, "SPECIFIC_LIEN_ASSET_REQUIRED"
        end
        if context.assetId ~= nil and tostring(context.assetId) ~= tostring(securityIntent.assetId) then
            return false, "ASSET_CONTEXT_MISMATCH"
        end
        securityIntent.proposedLienId = context.lienId
    end

    if originationPlan.planType == "revolvingOrigination" then
        local principal = nonNegativeMoney(liabilityIntent.principalBalance or 0)
        local creditLimit = positiveMoney(liabilityIntent.creditLimit)
        if principal == nil or principal > 0 then return false, "REVOLVING_CLOSE_MUST_START_UNDRAWN" end
        if creditLimit == nil then return false, "REVOLVING_CREDIT_LIMIT_REQUIRED" end

        return true, {
            closeType = "revolvingFacilityOpen",
            farmId = farmId,
            productType = productType,
            groupId = groupId,
            liabilityIntent = liabilityIntent,
            securityIntent = securityIntent,
            ledgerIntents = {},
            fsCashDelta = 0,
            netLedgerAmount = 0,
            requiresAssetAcquisition = false,
            atomicEffects = {
                "createLiability",
                securityIntent.mode ~= nil and "createSecurity" or nil
            },
            reconciliation = {
                balanced = true,
                expectedCashDelta = 0,
                ledgerNet = 0
            }
        }
    end

    if originationPlan.planType ~= "termOrigination" then
        return false, "UNSUPPORTED_ORIGINATION_PLAN_TYPE"
    end

    local closing = originationPlan.closing or {}
    local purchasePrice = nonNegativeMoney(closing.purchasePrice or 0)
    local cashEquity = nonNegativeMoney(closing.cashEquity or 0)
    local financedAmount = positiveMoney(closing.financedAmount or liabilityIntent.originalPrincipal)
    local liabilityPrincipal = positiveMoney(liabilityIntent.originalPrincipal or liabilityIntent.principalBalance)
    if purchasePrice == nil or cashEquity == nil or financedAmount == nil or liabilityPrincipal == nil then
        return false, "INVALID_CLOSING_AMOUNTS"
    end
    if not AGFCurrency.equals(financedAmount, liabilityPrincipal) then
        return false, "FINANCED_AMOUNT_DOES_NOT_MATCH_LIABILITY"
    end

    if purchasePrice > 0 then
        if not AGFCurrency.equals(AGFCurrency.round(cashEquity + financedAmount), purchasePrice) then
            return false, "CLOSING_SOURCES_DO_NOT_MATCH_PURCHASE_PRICE"
        end
    elseif cashEquity > 0 then
        return false, "CASH_EQUITY_WITHOUT_PURCHASE"
    end

    if context.cashAvailable ~= nil then
        local available = nonNegativeMoney(context.cashAvailable)
        if available == nil then return false, "INVALID_AVAILABLE_CASH" end
        if AGFCurrency.toMinorUnits(cashEquity) > AGFCurrency.toMinorUnits(available) then
            return false, "INSUFFICIENT_CASH_EQUITY"
        end
    end

    local fundingSource = fundingSourceForProduct(productType)
    local ledgerIntents = {
        {
            transactionType = AGFTransactionType.LOAN_PROCEEDS,
            amount = financedAmount,
            fundingSource = fundingSource,
            farmId = farmId,
            groupId = groupId,
            liabilityLink = "newLiability",
            economicRole = "financing"
        }
    }

    local requiresAssetAcquisition = purchasePrice > 0
    if requiresAssetAcquisition then
        table.insert(ledgerIntents, {
            transactionType = AGFTransactionType.ASSET_PURCHASE,
            amount = -purchasePrice,
            farmId = farmId,
            groupId = groupId,
            assetId = securityIntent.assetId or context.assetId,
            liabilityLink = "newLiability",
            economicRole = "assetAcquisition",
            fundingBreakdown = {
                cash = cashEquity,
                financed = financedAmount,
                financeSource = fundingSource
            }
        })
    end

    local netLedgerAmount = 0
    for _, intent in ipairs(ledgerIntents) do
        netLedgerAmount = AGFCurrency.round(netLedgerAmount + (intent.amount or 0))
    end

    local expectedCashDelta = requiresAssetAcquisition and -cashEquity or financedAmount
    if not AGFCurrency.equals(netLedgerAmount, expectedCashDelta) then
        return false, "CLOSE_PLAN_RECONCILIATION_FAILED"
    end

    local atomicEffects = {"createLiability"}
    if securityIntent.mode ~= nil then table.insert(atomicEffects, "createSecurity") end
    if requiresAssetAcquisition then table.insert(atomicEffects, "acquireAsset") end
    table.insert(atomicEffects, "postLedgerGroup")
    table.insert(atomicEffects, "moveFSCash")

    return true, {
        closeType = requiresAssetAcquisition and "financedAssetPurchase" or "termLoanAdvance",
        farmId = farmId,
        productType = productType,
        groupId = groupId,
        liabilityIntent = liabilityIntent,
        securityIntent = securityIntent,
        ledgerIntents = ledgerIntents,
        fsCashDelta = expectedCashDelta,
        netLedgerAmount = netLedgerAmount,
        requiresAssetAcquisition = requiresAssetAcquisition,
        cashEquity = cashEquity,
        financedAmount = financedAmount,
        purchasePrice = purchasePrice,
        atomicEffects = atomicEffects,
        reconciliation = {
            balanced = true,
            expectedCashDelta = expectedCashDelta,
            ledgerNet = netLedgerAmount,
            sourceTotal = AGFCurrency.round(cashEquity + financedAmount)
        }
    }
end
