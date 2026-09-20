-- Offline native action-bar semantic model validation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/ui/UIInformationArchitecture.lua")
dofile("src/ui/NativeUIActionModelService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local writable = {serverMutationAvailable = true}

local operating = AGFNativeUIActionModelService.build(
    AGFUIPageId.BANKING,
    {id = "LOC-1", productType = AGFProductType.OPERATING_LINE},
    writable
)
assertEqual(#operating, 3, "operating line action count")
assertEqual(operating[1].id, AGFNativeUIActionId.DRAW, "operating draw action")
assertEqual(operating[2].id, AGFNativeUIActionId.REPAY, "operating repay action")
assertEqual(operating[3].id, AGFNativeUIActionId.APPLY, "bank application action")
assertTrue(operating[1].enabled, "operating draw enabled when server mutation available")

local ciloc = AGFNativeUIActionModelService.build(
    AGFUIPageId.BANKING,
    {id = "CILOC-1", productType = AGFProductType.CROP_INPUT_LINE},
    writable
)
assertEqual(ciloc[1].id, AGFNativeUIActionId.FUNDING_POLICY, "CILOC policy action")
assertEqual(ciloc[2].id, AGFNativeUIActionId.REPAY, "CILOC repay action")

local safe = AGFNativeUIActionModelService.build(
    AGFUIPageId.BANKING,
    {id = "LOC-1", productType = AGFProductType.OPERATING_LINE},
    {serverMutationAvailable = true, readOnlySafeMode = true}
)
assertEqual(safe[1].enabled, false, "safe mode disables draw")
assertEqual(safe[1].disabledReason, "READ_ONLY_SAFE_MODE", "safe-mode reason")
assertEqual(safe[2].enabled, false, "safe mode disables repay")
assertEqual(safe[3].enabled, false, "safe mode disables application")

local asset = AGFNativeUIActionModelService.build(
    AGFUIPageId.ASSET_FINANCE,
    {liabilityId = "LIAB-1"},
    {serverMutationAvailable = false}
)
assertEqual(#asset, 3, "asset actions")
assertTrue(asset[1].enabled, "asset details remain readable")
assertTrue(asset[2].enabled, "schedule remains readable")
assertEqual(asset[3].enabled, false, "payoff unavailable without server mutation")
assertEqual(asset[3].disabledReason, "SERVER_MUTATION_UNAVAILABLE", "payoff disabled reason")

local delinquent = AGFNativeUIActionModelService.build(
    AGFUIPageId.PAYMENTS,
    {liabilityId = "LIAB-2", pastDue = 5000},
    writable
)
assertEqual(#delinquent, 4, "delinquent account actions")
assertEqual(delinquent[1].id, AGFNativeUIActionId.PAY, "payment action")
assertEqual(delinquent[2].id, AGFNativeUIActionId.CURE, "cure action")
assertEqual(delinquent[3].id, AGFNativeUIActionId.PAYOFF, "payoff action")
assertEqual(delinquent[4].id, AGFNativeUIActionId.SCHEDULE, "schedule action")

local report = AGFNativeUIActionModelService.build(
    AGFUIPageId.REPORTS,
    {id = "financialPosition"},
    {readOnlySafeMode = true, serverMutationAvailable = false}
)
assertEqual(#report, 1, "report action")
assertEqual(report[1].id, AGFNativeUIActionId.REPORT, "report open action")
assertTrue(report[1].enabled, "reports remain usable in safe mode")

print("offline_native_ui_action_model_tests: PASS")
