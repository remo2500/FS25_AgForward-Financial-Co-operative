-- AgForward Financial Cooperative
-- Pure origination planning. Converts server-approved quote/facility terms and
-- underwriting results into a deterministic liability/security/closing plan.
-- This module creates no liability, lien, ledger entry, or FS25 cash movement.

AGFOriginationPlanService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function positiveInteger(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

local function positiveMoney(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number <= 0 then return nil end
    return number
end

local function nonNegativeMoney(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function copyList(rows)
    local result = {}
    for _, row in ipairs(rows or {}) do
        local copy = {}
        for key, value in pairs(row) do copy[key] = value end
        table.insert(result, copy)
    end
    return result
end

local function validateDecision(decision, manualApproval)
    if decision == nil or decision.status == nil then return false, "CREDIT_DECISION_REQUIRED" end
    if decision.status == AGFCreditDecisionStatus.DECLINE then return false, "CREDIT_DECISION_DECLINED" end
    if decision.status == AGFCreditDecisionStatus.REFER and manualApproval ~= true then
        return false, "MANUAL_APPROVAL_REQUIRED"
    end
    return true, nil
end

local function buildDecisionSummary(decision, manualApproval)
    return {
        status = decision.status,
        manualApproval = manualApproval == true,
        conditions = copyList(decision.conditions),
        referrals = copyList(decision.referrals),
        policyName = decision.policyName,
        policyVersion = decision.policyVersion
    }
end

local function buildSecurityPlan(product, parameters, principal)
    if product.collateralClass == AGFCollateralClass.NONE then
        return {mode = "unsecured", collateralClass = product.collateralClass}, nil
    end

    if product.collateralClass == AGFCollateralClass.GENERAL_FARM then
        return {
            mode = "generalSecurity",
            collateralClass = product.collateralClass,
            securedAmount = principal
        }, nil
    end

    if parameters.assetId == nil or parameters.assetId == "" then
        return nil, "SECURED_ASSET_REQUIRED"
    end

    local priority = positiveInteger(parameters.lienPriority or 1)
    if priority == nil then return nil, "INVALID_LIEN_PRIORITY" end

    return {
        mode = "specificLien",
        assetId = tostring(parameters.assetId),
        collateralClass = product.collateralClass,
        lienPriority = priority,
        securedAmount = principal
    }, nil
end

function AGFOriginationPlanService.buildTermPlan(parameters)
    parameters = parameters or {}

    local farmId = positiveInteger(parameters.farmId)
    if farmId == nil then return false, "INVALID_FARM_ID" end

    local productType = parameters.productType
    if not AGFProductCatalog.exists(productType) then return false, "UNKNOWN_PRODUCT" end
    local product = AGFProductCatalog.get(productType)
    if product.kind ~= AGFProductKind.TERM_CREDIT and product.kind ~= AGFProductKind.ASSET_FINANCE then
        return false, "TERM_PLAN_REQUIRES_TERM_OR_ASSET_PRODUCT"
    end

    local decisionOk, decisionError = validateDecision(parameters.creditDecision, parameters.manualApproval)
    if not decisionOk then return false, decisionError end

    local quote = parameters.quote
    if quote == nil or quote.amortization == nil or quote.pricing == nil then return false, "VALID_QUOTE_REQUIRED" end
    local principal = positiveMoney(quote.principal)
    if principal == nil then return false, "INVALID_QUOTE_PRINCIPAL" end

    local startYear = positiveInteger(parameters.startYear)
    local startPeriod = positiveInteger(parameters.startPeriod)
    if startYear == nil or startPeriod == nil or startPeriod > 12 then return false, "INVALID_CONTRACT_START" end

    local scheduleOk, scheduleOrError = AGFLoanContractScheduleService.build(quote, startYear, startPeriod)
    if not scheduleOk then return false, scheduleOrError end
    local contractSchedule = scheduleOrError

    local securityPlan, securityError = buildSecurityPlan(product, parameters, principal)
    if securityPlan == nil then return false, securityError end

    local purchasePrice = nonNegativeMoney(quote.purchasePrice or 0)
    local downPayment = nonNegativeMoney(quote.downPayment or 0)
    if purchasePrice == nil or downPayment == nil then return false, "INVALID_CLOSING_AMOUNTS" end

    if product.kind == AGFProductKind.ASSET_FINANCE then
        if purchasePrice <= 0 then return false, "ASSET_PURCHASE_PRICE_REQUIRED" end
        if not AGFCurrency.equals(AGFCurrency.round(principal + downPayment), purchasePrice) then
            return false, "CLOSING_SOURCES_DO_NOT_MATCH_PURCHASE_PRICE"
        end
    end

    local interestRate = tonumber(quote.pricing.annualRate)
    if interestRate == nil or not isFinite(interestRate) or interestRate < 0 then return false, "INVALID_QUOTE_RATE" end

    local maturity = contractSchedule.schedule[#contractSchedule.schedule]

    -- Project finance is a commitment with staged advances. The approved
    -- commitment is not day-one principal and the conversion amortization
    -- schedule is only a preview until actual construction draws are known.
    if productType == AGFProductType.PROJECT_FINANCE then
        local liabilityPlan = {
            farmId = farmId,
            productType = productType,
            status = "pendingClose",
            revolving = false,
            originalPrincipal = 0,
            principalBalance = 0,
            commitmentAmount = principal,
            undrawnCommitment = principal,
            interestRate = interestRate,
            constructionRate = interestRate,
            scheduledPayment = 0,
            startYear = startYear,
            startPeriod = startPeriod,
            contextFingerprint = parameters.contextFingerprint
        }

        return true, {
            planType = "projectCommitmentOrigination",
            farmId = farmId,
            productType = productType,
            productKind = product.kind,
            decision = buildDecisionSummary(parameters.creditDecision, parameters.manualApproval),
            liability = liabilityPlan,
            security = securityPlan,
            closing = {
                projectCost = purchasePrice,
                cashEquity = downPayment,
                approvedCommitment = principal,
                sourceTotal = AGFCurrency.round(downPayment + principal),
                stagedFunding = true
            },
            conversionPreview = {
                paymentFrequency = quote.paymentsPerYear or 12,
                totalPaymentPeriods = #contractSchedule.schedule,
                interestOnlyPeriods = quote.interestOnlyPeriods or 0,
                rateTermPeriods = quote.rateTermPeriods,
                scheduledPayment = quote.quotedRegularPayment,
                interestOnlyPayment = quote.interestOnlyPayment,
                balloonAmount = quote.balloonAmount or 0,
                firstDueYear = contractSchedule.firstDueYear,
                firstDuePeriod = contractSchedule.firstDuePeriod,
                maturityYear = maturity.dueYear,
                maturityPeriod = maturity.duePeriod,
                contractSchedule = contractSchedule
            },
            contextFingerprint = parameters.contextFingerprint
        }
    end

    local liabilityPlan = {
        farmId = farmId,
        productType = productType,
        status = "pendingClose",
        revolving = false,
        originalPrincipal = principal,
        principalBalance = principal,
        interestRate = interestRate,
        paymentFrequency = quote.paymentsPerYear or 12,
        totalPaymentPeriods = #contractSchedule.schedule,
        remainingPaymentPeriods = #contractSchedule.schedule,
        interestOnlyPeriods = quote.interestOnlyPeriods or 0,
        rateTermPeriods = quote.rateTermPeriods,
        scheduledPayment = quote.quotedRegularPayment,
        interestOnlyPayment = quote.interestOnlyPayment,
        balloonAmount = quote.balloonAmount or 0,
        startYear = startYear,
        startPeriod = startPeriod,
        firstDueYear = contractSchedule.firstDueYear,
        firstDuePeriod = contractSchedule.firstDuePeriod,
        maturityYear = maturity.dueYear,
        maturityPeriod = maturity.duePeriod,
        contextFingerprint = parameters.contextFingerprint
    }

    return true, {
        planType = "termOrigination",
        farmId = farmId,
        productType = productType,
        productKind = product.kind,
        decision = buildDecisionSummary(parameters.creditDecision, parameters.manualApproval),
        liability = liabilityPlan,
        security = securityPlan,
        closing = {
            purchasePrice = purchasePrice,
            cashEquity = downPayment,
            financedAmount = principal,
            sourceTotal = AGFCurrency.round(downPayment + principal),
            directPurchaseFunding = product.directPurchaseFunding == true
        },
        contractSchedule = contractSchedule,
        contextFingerprint = parameters.contextFingerprint
    }
end

function AGFOriginationPlanService.buildRevolvingPlan(parameters)
    parameters = parameters or {}

    local farmId = positiveInteger(parameters.farmId)
    if farmId == nil then return false, "INVALID_FARM_ID" end

    local productType = parameters.productType
    if not AGFProductCatalog.exists(productType) then return false, "UNKNOWN_PRODUCT" end
    local product = AGFProductCatalog.get(productType)
    if product.kind ~= AGFProductKind.REVOLVING_CREDIT then
        return false, "REVOLVING_PLAN_REQUIRES_REVOLVING_PRODUCT"
    end

    local decisionOk, decisionError = validateDecision(parameters.creditDecision, parameters.manualApproval)
    if not decisionOk then return false, decisionError end

    local approvedLimit = positiveMoney(parameters.approvedLimit)
    if approvedLimit == nil then return false, "APPROVED_LIMIT_REQUIRED" end

    local annualRate = tonumber(parameters.annualRate)
    if annualRate == nil or not isFinite(annualRate) or annualRate < 0 then return false, "INVALID_ANNUAL_RATE" end

    local borrowingBase = nil
    if parameters.borrowingBase ~= nil then
        borrowingBase = nonNegativeMoney(parameters.borrowingBase)
        if borrowingBase == nil then return false, "INVALID_BORROWING_BASE" end
    end

    local effectiveLimit = approvedLimit
    if borrowingBase ~= nil then effectiveLimit = math.min(effectiveLimit, borrowingBase) end
    effectiveLimit = AGFCurrency.round(effectiveLimit)

    local securityPlan, securityError = buildSecurityPlan(product, parameters, approvedLimit)
    if securityPlan == nil then return false, securityError end

    local season = nil
    if productType == AGFProductType.CROP_INPUT_LINE and parameters.seasonParameters ~= nil then
        local seasonParameters = {}
        for key, value in pairs(parameters.seasonParameters) do seasonParameters[key] = value end
        seasonParameters.creditLimit = approvedLimit
        seasonParameters.principalBalance = 0
        seasonParameters.reservedAmount = 0
        seasonParameters.borrowingBase = borrowingBase
        local seasonOk, seasonOrError = AGFCILOCSeasonService.assess(seasonParameters)
        if not seasonOk then return false, seasonOrError end
        season = seasonOrError
    end

    return true, {
        planType = "revolvingOrigination",
        farmId = farmId,
        productType = productType,
        productKind = product.kind,
        decision = buildDecisionSummary(parameters.creditDecision, parameters.manualApproval),
        liability = {
            farmId = farmId,
            productType = productType,
            status = "pendingClose",
            revolving = true,
            originalPrincipal = 0,
            principalBalance = 0,
            creditLimit = approvedLimit,
            effectiveLimit = effectiveLimit,
            interestRate = annualRate,
            contextFingerprint = parameters.contextFingerprint
        },
        security = securityPlan,
        season = season,
        contextFingerprint = parameters.contextFingerprint
    }
end

function AGFOriginationPlanService.build(parameters)
    parameters = parameters or {}
    local product = AGFProductCatalog.get(parameters.productType)
    if product == nil then return false, "UNKNOWN_PRODUCT" end
    if product.kind == AGFProductKind.REVOLVING_CREDIT then
        return AGFOriginationPlanService.buildRevolvingPlan(parameters)
    end
    if product.kind == AGFProductKind.TERM_CREDIT or product.kind == AGFProductKind.ASSET_FINANCE then
        return AGFOriginationPlanService.buildTermPlan(parameters)
    end
    return false, "ORIGINATION_NOT_SUPPORTED_FOR_PRODUCT_KIND"
end
