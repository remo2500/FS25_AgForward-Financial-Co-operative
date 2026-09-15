-- Offline contract tests for product capabilities and future FS money semantics.

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/products/ProductCatalog.lua")
dofile("src/integrations/MoneyMovementIntent.lua")

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

-- Every locked product family has a common capability definition.
for _, productType in ipairs({
    AGFProductType.OPERATING_LINE,
    AGFProductType.CROP_INPUT_LINE,
    AGFProductType.TERM_LOAN,
    AGFProductType.EQUIPMENT_FINANCE,
    AGFProductType.PROJECT_FINANCE,
    AGFProductType.LAND_FINANCE,
    AGFProductType.LAND_LEASE
}) do
    assertTrue(AGFProductCatalog.exists(productType), "catalog entry missing: " .. tostring(productType))
end

local operating = AGFProductCatalog.get(AGFProductType.OPERATING_LINE)
assertEqual(operating.kind, AGFProductKind.REVOLVING_CREDIT, "operating line product kind")
assertTrue(operating.revolving, "operating line revolving")
assertTrue(operating.settlementCreditEligible, "general line can be settlement liquidity when policy allows")

local ciloc = AGFProductCatalog.get(AGFProductType.CROP_INPUT_LINE)
assertTrue(ciloc.revolving, "CILOC revolving")
assertTrue(ciloc.restrictedPurpose, "CILOC purpose restricted")
assertFalse(ciloc.settlementCreditEligible, "CILOC not generic settlement liquidity")

local equipment = AGFProductCatalog.get(AGFProductType.EQUIPMENT_FINANCE)
assertEqual(equipment.collateralClass, AGFCollateralClass.VEHICLE, "equipment collateral class")
assertTrue(equipment.supportsBalloon, "equipment finance supports balloon")

local project = AGFProductCatalog.get(AGFProductType.PROJECT_FINANCE)
assertEqual(project.collateralClass, AGFCollateralClass.PLACEABLE, "project collateral class")

local land = AGFProductCatalog.get(AGFProductType.LAND_FINANCE)
assertEqual(land.collateralClass, AGFCollateralClass.FARMLAND, "land collateral class")

local landLease = AGFProductCatalog.get(AGFProductType.LAND_LEASE)
assertEqual(landLease.kind, AGFProductKind.LEASE, "land lease product kind")
assertEqual(landLease.collateralClass, AGFCollateralClass.NONE, "land lease is not owned collateral")

-- Finance cash movements have semantic intent independent from final runtime MoneyType registration.
local drawIntent = AGFMoneyMovementIntent.get(AGFTransactionType.CREDIT_DRAW)
assertEqual(drawIntent.role, AGFMoneyMovementRole.FINANCING_INFLOW, "credit draw role")
assertEqual(drawIntent.cashDirection, 1, "credit draw cash direction")
assertEqual(drawIntent.taxTreatment, AGFRedTapeTreatment.IGNORE_TAX, "credit draw not taxable income")

local principalIntent = AGFMoneyMovementIntent.get(AGFTransactionType.PRINCIPAL_PAYMENT)
assertEqual(principalIntent.role, AGFMoneyMovementRole.LIABILITY_REDUCTION, "principal role")
assertEqual(principalIntent.cashDirection, -1, "principal cash direction")
assertEqual(principalIntent.taxTreatment, AGFRedTapeTreatment.IGNORE_TAX, "principal not tax expense")

local interestIntent = AGFMoneyMovementIntent.get(AGFTransactionType.INTEREST_PAYMENT)
assertEqual(interestIntent.role, AGFMoneyMovementRole.INTEREST_EXPENSE, "interest role")
assertEqual(interestIntent.cashDirection, -1, "interest cash direction")
assertEqual(interestIntent.taxTreatment, AGFRedTapeTreatment.NATIVE_RECONCILE, "interest must reconcile")

local inputIntent = AGFMoneyMovementIntent.get(AGFTransactionType.INPUT_PURCHASE)
assertTrue(inputIntent.preserveUnderlyingMoneyType, "input purchase preserves native purchase MoneyType")
assertEqual(inputIntent.role, AGFMoneyMovementRole.OPERATING_PURCHASE, "input purchase role")

local grantIntent = AGFMoneyMovementIntent.get(AGFTransactionType.GRANT_RECEIPT)
assertEqual(grantIntent.taxTreatment, AGFRedTapeTreatment.EXTERNAL_AUTHORITY, "Red Tape remains grant authority")

local validDraw, validDrawError = AGFMoneyMovementIntent.validateCashAmount(AGFTransactionType.CREDIT_DRAW, 10000)
assertTrue(validDraw, validDrawError)
local invalidDraw, invalidDrawError = AGFMoneyMovementIntent.validateCashAmount(AGFTransactionType.CREDIT_DRAW, -10000)
assertFalse(invalidDraw, "negative draw movement rejected")
assertEqual(invalidDrawError, "CASH_DIRECTION_MISMATCH", "draw direction mismatch error")

local validInterest, validInterestError = AGFMoneyMovementIntent.validateCashAmount(AGFTransactionType.INTEREST_PAYMENT, -500)
assertTrue(validInterest, validInterestError)

print("offline_contract_tests: PASS")
