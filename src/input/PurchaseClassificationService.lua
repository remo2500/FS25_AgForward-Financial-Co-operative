-- AgForward Financial Cooperative
-- Maps observed FS25 purchase context into AgForward economic-purpose categories.
-- MoneyType alone is intentionally not considered sufficient for generic material purchases.

AGFPurchaseClassificationService = {}
AGFPurchaseClassificationService_mt = Class(AGFPurchaseClassificationService)

function AGFPurchaseClassificationService.new()
    return setmetatable({}, AGFPurchaseClassificationService_mt)
end

function AGFPurchaseClassificationService:getFillTypeName(fillTypeIndex)
    if fillTypeIndex == nil or g_fillTypeManager == nil or g_fillTypeManager.getFillTypeNameByIndex == nil then
        return nil
    end
    local name = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)
    return name ~= nil and string.upper(tostring(name)) or nil
end

function AGFPurchaseClassificationService:classifyByFillType(fillTypeIndex)
    local name = self:getFillTypeName(fillTypeIndex)
    if name == nil then return nil, "NONE", "NO_FILLTYPE_CONTEXT" end

    if name == "SEEDS" or name == "SEED" then
        return AGFExpenseCategory.SEED, "HIGH", "FILLTYPE_" .. name
    end
    if name == "FERTILIZER" or name == "LIQUIDFERTILIZER" then
        return AGFExpenseCategory.FERTILIZER, "HIGH", "FILLTYPE_" .. name
    end
    if name == "LIME" then
        return AGFExpenseCategory.LIME_SOIL_AMENDMENT, "HIGH", "FILLTYPE_LIME"
    end
    if name == "HERBICIDE" then
        return AGFExpenseCategory.CROP_PROTECTION, "HIGH", "FILLTYPE_HERBICIDE"
    end
    if name == "DIESEL" or name == "DEF" or name == "METHANE" or name == "ELECTRICCHARGE" then
        return AGFExpenseCategory.FUEL, "HIGH", "FILLTYPE_" .. name
    end

    return nil, "LOW", "UNMAPPED_FILLTYPE_" .. name
end

function AGFPurchaseClassificationService:moneyTypeEquals(moneyType, key)
    if MoneyType == nil then return false end
    local candidate = rawget(MoneyType, key)
    return candidate ~= nil and moneyType == candidate
end

function AGFPurchaseClassificationService:classify(moneyType, fillTypeIndex, context)
    context = context or {}

    if context.expenseCategory ~= nil then
        return context.expenseCategory, "EXPLICIT", "CALLER_CONTEXT"
    end

    local fillCategory, fillConfidence, fillReason = self:classifyByFillType(fillTypeIndex)

    if self:moneyTypeEquals(moneyType, "PURCHASE_SEEDS") then
        return AGFExpenseCategory.SEED, "HIGH", "MONEYTYPE_PURCHASE_SEEDS"
    end

    if self:moneyTypeEquals(moneyType, "PURCHASE_FUEL") then
        return AGFExpenseCategory.FUEL, "HIGH", "MONEYTYPE_PURCHASE_FUEL"
    end

    if self:moneyTypeEquals(moneyType, "PURCHASE_FERTILIZER") then
        if fillCategory == AGFExpenseCategory.CROP_PROTECTION or fillCategory == AGFExpenseCategory.LIME_SOIL_AMENDMENT then
            return fillCategory, "HIGH", fillReason
        end
        return fillCategory or AGFExpenseCategory.FERTILIZER, fillCategory ~= nil and "HIGH" or "MEDIUM", fillCategory ~= nil and fillReason or "MONEYTYPE_PURCHASE_FERTILIZER"
    end

    if self:moneyTypeEquals(moneyType, "BOUGHT_MATERIALS") then
        if fillCategory ~= nil then
            return fillCategory, "HIGH", "BOUGHT_MATERIALS_WITH_" .. fillReason
        end
        return nil, "LOW", "BOUGHT_MATERIALS_REQUIRES_FILLTYPE_CONTEXT"
    end

    if fillCategory ~= nil then
        return fillCategory, fillConfidence, fillReason
    end

    return nil, "NONE", "UNCLASSIFIED_PURCHASE"
end
