-- AgForward Financial Cooperative
-- Common product capability catalog. Pricing/approval thresholds are deliberately
-- excluded so product policy can evolve without duplicating financial engines.

AGFProductKind = {
    REVOLVING_CREDIT = "revolvingCredit",
    TERM_CREDIT = "termCredit",
    ASSET_FINANCE = "assetFinance",
    LEASE = "lease"
}

AGFCollateralClass = {
    NONE = "none",
    GENERAL_FARM = "generalFarm",
    VEHICLE = "vehicle",
    PLACEABLE = "placeable",
    FARMLAND = "farmland"
}

AGFProductCatalog = {}

local PRODUCTS = {
    [AGFProductType.OPERATING_LINE] = {
        displayKey = "agf_product_operatingLine",
        kind = AGFProductKind.REVOLVING_CREDIT,
        revolving = true,
        supportsFixedRate = true,
        supportsVariableRate = true,
        supportsBalloon = false,
        directPurchaseFunding = true,
        restrictedPurpose = false,
        collateralClass = AGFCollateralClass.GENERAL_FARM,
        settlementCreditEligible = true
    },
    [AGFProductType.CROP_INPUT_LINE] = {
        displayKey = "agf_product_cropInputLine",
        kind = AGFProductKind.REVOLVING_CREDIT,
        revolving = true,
        supportsFixedRate = true,
        supportsVariableRate = true,
        supportsBalloon = false,
        directPurchaseFunding = true,
        restrictedPurpose = true,
        collateralClass = AGFCollateralClass.GENERAL_FARM,
        settlementCreditEligible = false
    },
    [AGFProductType.TERM_LOAN] = {
        displayKey = "agf_product_termLoan",
        kind = AGFProductKind.TERM_CREDIT,
        revolving = false,
        supportsFixedRate = true,
        supportsVariableRate = true,
        supportsBalloon = true,
        directPurchaseFunding = false,
        restrictedPurpose = false,
        collateralClass = AGFCollateralClass.GENERAL_FARM,
        settlementCreditEligible = false
    },
    [AGFProductType.EQUIPMENT_FINANCE] = {
        displayKey = "agf_product_equipmentFinance",
        kind = AGFProductKind.ASSET_FINANCE,
        revolving = false,
        supportsFixedRate = true,
        supportsVariableRate = true,
        supportsBalloon = true,
        directPurchaseFunding = true,
        restrictedPurpose = true,
        collateralClass = AGFCollateralClass.VEHICLE,
        settlementCreditEligible = false
    },
    [AGFProductType.PROJECT_FINANCE] = {
        displayKey = "agf_product_projectFinance",
        kind = AGFProductKind.ASSET_FINANCE,
        revolving = false,
        supportsFixedRate = true,
        supportsVariableRate = true,
        supportsBalloon = true,
        directPurchaseFunding = true,
        restrictedPurpose = true,
        collateralClass = AGFCollateralClass.PLACEABLE,
        settlementCreditEligible = false
    },
    [AGFProductType.LAND_FINANCE] = {
        displayKey = "agf_product_landFinance",
        kind = AGFProductKind.ASSET_FINANCE,
        revolving = false,
        supportsFixedRate = true,
        supportsVariableRate = true,
        supportsBalloon = true,
        directPurchaseFunding = true,
        restrictedPurpose = true,
        collateralClass = AGFCollateralClass.FARMLAND,
        settlementCreditEligible = false
    },
    [AGFProductType.LAND_LEASE] = {
        displayKey = "agf_product_landLease",
        kind = AGFProductKind.LEASE,
        revolving = false,
        supportsFixedRate = false,
        supportsVariableRate = false,
        supportsBalloon = false,
        directPurchaseFunding = false,
        restrictedPurpose = true,
        collateralClass = AGFCollateralClass.NONE,
        settlementCreditEligible = false
    }
}

local function cloneProduct(productType, product)
    if product == nil then return nil end
    local copy = {productType = productType}
    for key, value in pairs(product) do copy[key] = value end
    return copy
end

function AGFProductCatalog.get(productType)
    return cloneProduct(productType, PRODUCTS[productType])
end

function AGFProductCatalog.exists(productType)
    return PRODUCTS[productType] ~= nil
end

function AGFProductCatalog.getAll()
    local result = {}
    for productType, product in pairs(PRODUCTS) do
        table.insert(result, cloneProduct(productType, product))
    end
    table.sort(result, function(left, right) return tostring(left.productType) < tostring(right.productType) end)
    return result
end

function AGFProductCatalog.supports(productType, capability)
    local product = PRODUCTS[productType]
    return product ~= nil and product[capability] == true
end
