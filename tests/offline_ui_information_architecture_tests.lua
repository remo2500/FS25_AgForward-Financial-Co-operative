-- Offline native-FS25 UI information-architecture validation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/ui/UIInformationArchitecture.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local pages = AGFUIInformationArchitecture.getVisiblePages({
    serverMutationAvailable = true,
    governmentIntegrationAvailable = false
})
assertEqual(#pages, 7, "government page hidden without integration")
assertEqual(pages[1].id, AGFUIPageId.OVERVIEW, "overview first")
assertEqual(pages[#pages].id, AGFUIPageId.SETTINGS, "settings last")
assertEqual(AGFUIInformationArchitecture.getFirstPageId({}), AGFUIPageId.OVERVIEW, "default first page")

local withGovernment = AGFUIInformationArchitecture.getVisiblePages({
    serverMutationAvailable = true,
    governmentIntegrationAvailable = true
})
assertEqual(#withGovernment, 8, "government page visible when integration available")
assertEqual(withGovernment[7].id, AGFUIPageId.GOVERNMENT, "government page placement")

local banking = AGFUIInformationArchitecture.getPage(AGFUIPageId.BANKING)
assertTrue(banking.mutating, "banking is mutation-capable")
assertEqual(banking.titleKey, "agf_ui_bankingCredit", "banking title key")

local reports = AGFUIInformationArchitecture.getPage(AGFUIPageId.REPORTS)
assertEqual(reports.mutating, false, "reports read only")

local safePages = AGFUIInformationArchitecture.getVisiblePages({
    serverMutationAvailable = true,
    readOnlySafeMode = true,
    governmentIntegrationAvailable = true
})
for _, page in ipairs(safePages) do
    if page.mutating then
        assertEqual(page.actionsEnabled, false, "mutating page disabled in safe mode: " .. page.id)
    else
        assertEqual(page.actionsEnabled, true, "read-only page remains usable: " .. page.id)
    end
end

local allowed, allowError = AGFUIInformationArchitecture.isMutationAllowed(
    AGFUIPageId.BANKING,
    {serverMutationAvailable = true}
)
assertTrue(allowed, allowError)

local safeAllowed, safeError = AGFUIInformationArchitecture.isMutationAllowed(
    AGFUIPageId.BANKING,
    {serverMutationAvailable = true, readOnlySafeMode = true}
)
assertEqual(safeAllowed, false, "safe mode blocks banking mutation")
assertEqual(safeError, "READ_ONLY_SAFE_MODE", "safe-mode block reason")

local reportAllowed = AGFUIInformationArchitecture.isMutationAllowed(
    AGFUIPageId.REPORTS,
    {serverMutationAvailable = false, readOnlySafeMode = true}
)
assertTrue(reportAllowed, "read-only report navigation remains available")

local waitingAllowed, waitingError = AGFUIInformationArchitecture.isMutationAllowed(
    AGFUIPageId.PAYMENTS,
    {serverMutationAvailable = true, clientWaitingForSync = true}
)
assertEqual(waitingAllowed, false, "waiting client cannot mutate")
assertEqual(waitingError, "CLIENT_WAITING_FOR_SYNC", "waiting-client reason")

print("offline_ui_information_architecture_tests: PASS")
