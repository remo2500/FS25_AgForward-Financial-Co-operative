-- AgForward Financial Cooperative
-- Pure preflight for a prospective crop-input purchase. It combines purchase
-- classification, CILOC eligibility, funding allocation, facility availability,
-- and optional category-budget projection without reserving credit or moving FS25
-- money. The future runtime hook can use this result before affordability/commit.

AGFCILOCPurchasePreflightService = {}
AGFCILOCPurchasePreflightService_mt = Class(AGFCILOCPurchasePreflightService)

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
    number = AGFCurrency.round(math.abs(number))
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

function AGFCILOCPurchasePreflightService.new(classificationService)
    local self = setmetatable({}, AGFCILOCPurchasePreflightService_mt)
    self.classificationService = classificationService
    return self
end

function AGFCILOCPurchasePreflightService:validateLiability(liability, farmId)
    if liability == nil or liability.id == nil then return false, "CILOC_LIABILITY_REQUIRED" end
    if liability.farmId ~= farmId then return false, "LIABILITY_FARM_MISMATCH" end
    if liability.productType ~= AGFProductType.CROP_INPUT_LINE then return false, "LIABILITY_NOT_CROP_INPUT_LINE" end
    if liability.isRevolving ~= nil and not liability:isRevolving() then return false, "LIABILITY_NOT_REVOLVING" end
    if AGFLiabilityStatus ~= nil and liability.status ~= nil and liability.status ~= AGFLiabilityStatus.ACTIVE then
        return false, "LIABILITY_NOT_ACTIVE"
    end
    return true, nil
end

function AGFCILOCPurchasePreflightService:classify(parameters)
    if self.classificationService == nil or self.classificationService.classify == nil then
        return nil, "NONE", "CLASSIFICATION_SERVICE_UNAVAILABLE"
    end
    return self.classificationService:classify(
        parameters.moneyType,
        parameters.fillTypeIndex,
        parameters.purchaseContext or {}
    )
end

function AGFCILOCPurchasePreflightService:plan(parameters)
    parameters = parameters or {}

    local farmId = positiveInteger(parameters.farmId)
    if farmId == nil then return false, "INVALID_FARM_ID" end

    local amount = positiveMoney(parameters.amount)
    if amount == nil then return false, "INVALID_PURCHASE_AMOUNT" end

    local cashAvailable = nonNegativeMoney(parameters.cashAvailable)
    if cashAvailable == nil then return false, "INVALID_CASH_AVAILABLE" end

    local category, confidence, classificationReason = self:classify(parameters)
    local eligible = category ~= nil and AGFCILOCBudgetService.isEligibleCategory(category)

    local facilityReview = parameters.facilityReview
    local lineAvailable = 0
    if facilityReview ~= nil then
        lineAvailable = nonNegativeMoney(facilityReview.availableCapacity)
        if lineAvailable == nil then return false, "INVALID_FACILITY_AVAILABLE_CAPACITY" end
    end

    local fundingOk, fundingOrError = AGFFundingDecisionService.decide(
        amount,
        cashAvailable,
        lineAvailable,
        eligible,
        parameters.fundingPolicy
    )
    if not fundingOk then
        return false, fundingOrError
    end
    local funding = fundingOrError

    local liability = parameters.liability
    local budgetProjection = nil
    local projectedFacility = nil
    local reservationIntent = nil

    if funding.lineContribution > 0 then
        local liabilityOk, liabilityError = self:validateLiability(liability, farmId)
        if not liabilityOk then return false, liabilityError end
        if not eligible then return false, "PURCHASE_NOT_CILOC_ELIGIBLE" end
        if facilityReview == nil then return false, "FACILITY_REVIEW_REQUIRED" end
        if facilityReview.flags ~= nil and facilityReview.flags.drawsFrozen == true then
            return false, "CILOC_DRAWS_FROZEN"
        end
        if AGFCurrency.toMinorUnits(funding.lineContribution) > AGFCurrency.toMinorUnits(lineAvailable) then
            return false, "CILOC_AVAILABLE_CAPACITY_EXCEEDED"
        end

        if parameters.budgetState ~= nil then
            local budgetOk, budgetOrError = AGFCILOCBudgetService.applyPurchase(
                parameters.budgetState,
                category,
                amount,
                funding.lineContribution,
                parameters.budgetPolicy or {}
            )
            if not budgetOk then return false, budgetOrError end
            budgetProjection = budgetOrError
        end

        local usedCapacity = nonNegativeMoney(facilityReview.usedCapacity or 0)
        local effectiveLimit = nonNegativeMoney(facilityReview.effectiveLimit or 0)
        if usedCapacity == nil then return false, "INVALID_FACILITY_USED_CAPACITY" end
        if effectiveLimit == nil then return false, "INVALID_FACILITY_EFFECTIVE_LIMIT" end
        local projectedUsed = AGFCurrency.round(usedCapacity + funding.lineContribution)
        if AGFCurrency.toMinorUnits(projectedUsed) > AGFCurrency.toMinorUnits(effectiveLimit) then
            return false, "CILOC_EFFECTIVE_LIMIT_EXCEEDED"
        end
        projectedFacility = {
            effectiveLimit = effectiveLimit,
            usedCapacityBefore = usedCapacity,
            reservationAmount = funding.lineContribution,
            usedCapacityAfterReservation = projectedUsed,
            availableCapacityAfterReservation = AGFCurrency.round(effectiveLimit - projectedUsed),
            utilizationAfterReservation = effectiveLimit > 0 and projectedUsed / effectiveLimit or nil
        }

        reservationIntent = {
            farmId = farmId,
            liabilityId = liability.id,
            amount = funding.lineContribution,
            purpose = category,
            contextFingerprint = parameters.contextFingerprint
        }
    elseif parameters.budgetState ~= nil and category ~= nil then
        -- Cash-funded eligible purchases still consume the crop-input operating
        -- budget even though they do not consume CILOC principal/capacity.
        local budgetOk, budgetOrError = AGFCILOCBudgetService.applyPurchase(
            parameters.budgetState,
            category,
            amount,
            0,
            parameters.budgetPolicy or {}
        )
        if not budgetOk then return false, budgetOrError end
        budgetProjection = budgetOrError
    end

    local ledgerIntents = {}
    if funding.lineContribution > 0 then
        table.insert(ledgerIntents, {
            transactionType = AGFTransactionType.CREDIT_DRAW,
            amount = funding.lineContribution,
            liabilityId = liability.id,
            fundingSource = AGFFundingSource.CROP_INPUT_LINE,
            expenseCategory = nil
        })
    end
    table.insert(ledgerIntents, {
        transactionType = AGFTransactionType.INPUT_PURCHASE,
        amount = -amount,
        liabilityId = funding.lineContribution > 0 and liability.id or nil,
        fundingSource = funding.lineContribution > 0 and AGFFundingSource.CROP_INPUT_LINE or AGFFundingSource.CASH,
        expenseCategory = category
    })

    local netCashEffect = AGFCurrency.round(-funding.cashContribution)
    local groupNet = netCashEffect

    return true, {
        farmId = farmId,
        purchaseAmount = amount,
        expenseCategory = category,
        classificationConfidence = confidence,
        classificationReason = classificationReason,
        cilocEligible = eligible,
        funding = funding,
        netCashEffect = netCashEffect,
        expectedGroupNet = groupNet,
        facilityProjection = projectedFacility,
        budgetProjection = budgetProjection,
        reservationIntent = reservationIntent,
        ledgerIntents = ledgerIntents,
        contextFingerprint = parameters.contextFingerprint
    }
end
