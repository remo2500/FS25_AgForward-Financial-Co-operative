-- AgForward Financial Cooperative
-- Pure UI information architecture. No GIANTS GUI is loaded here.
-- This model defines page identity, ordering, icon concepts, visibility and
-- mutation boundaries before runtime XML/profile integration.

AGFUIPageId = {
    OVERVIEW = "overview",
    BANKING = "banking",
    ASSET_FINANCE = "assetFinance",
    LAND_LEASES = "landLeases",
    PAYMENTS = "payments",
    REPORTS = "reports",
    GOVERNMENT = "government",
    SETTINGS = "settings"
}

AGFUIInformationArchitecture = {}

local PAGES = {
    {
        id = AGFUIPageId.OVERVIEW,
        order = 10,
        titleKey = "agf_ui_overview",
        iconConcept = "farmFinanceOverview",
        mutating = false,
        alwaysVisible = true
    },
    {
        id = AGFUIPageId.BANKING,
        order = 20,
        titleKey = "agf_ui_bankingCredit",
        iconConcept = "creditFacility",
        mutating = true,
        alwaysVisible = true
    },
    {
        id = AGFUIPageId.ASSET_FINANCE,
        order = 30,
        titleKey = "agf_ui_assetFinance",
        iconConcept = "equipmentFinance",
        mutating = true,
        alwaysVisible = true
    },
    {
        id = AGFUIPageId.LAND_LEASES,
        order = 40,
        titleKey = "agf_ui_landLeases",
        iconConcept = "farmlandFinance",
        mutating = true,
        alwaysVisible = true
    },
    {
        id = AGFUIPageId.PAYMENTS,
        order = 50,
        titleKey = "agf_ui_paymentsObligations",
        iconConcept = "paymentObligation",
        mutating = true,
        alwaysVisible = true
    },
    {
        id = AGFUIPageId.REPORTS,
        order = 60,
        titleKey = "agf_ui_reports",
        iconConcept = "financialReport",
        mutating = false,
        alwaysVisible = true
    },
    {
        id = AGFUIPageId.GOVERNMENT,
        order = 70,
        titleKey = "agf_ui_government",
        iconConcept = "governmentIntegration",
        mutating = false,
        alwaysVisible = false,
        visibilityFlag = "governmentIntegrationAvailable"
    },
    {
        id = AGFUIPageId.SETTINGS,
        order = 80,
        titleKey = "agf_ui_settings",
        iconConcept = "financeSettings",
        mutating = true,
        alwaysVisible = true
    }
}

local function clonePage(page)
    local result = {}
    for key, value in pairs(page) do result[key] = value end
    return result
end

function AGFUIInformationArchitecture.getAllPages()
    local result = {}
    for _, page in ipairs(PAGES) do table.insert(result, clonePage(page)) end
    return result
end

function AGFUIInformationArchitecture.getPage(pageId)
    for _, page in ipairs(PAGES) do
        if page.id == pageId then return clonePage(page) end
    end
    return nil
end

function AGFUIInformationArchitecture.getVisiblePages(context)
    context = context or {}
    local result = {}

    for _, page in ipairs(PAGES) do
        local visible = page.alwaysVisible == true
        if not visible and page.visibilityFlag ~= nil then
            visible = context[page.visibilityFlag] == true
        end

        if visible then
            local copy = clonePage(page)
            copy.actionsEnabled = context.readOnlySafeMode ~= true
                and context.clientWaitingForSync ~= true
                and (page.mutating ~= true or context.serverMutationAvailable == true)
            if page.mutating ~= true then
                copy.actionsEnabled = true
            end
            table.insert(result, copy)
        end
    end

    table.sort(result, function(left, right)
        if left.order == right.order then return tostring(left.id) < tostring(right.id) end
        return left.order < right.order
    end)
    return result
end

function AGFUIInformationArchitecture.getFirstPageId(context)
    local pages = AGFUIInformationArchitecture.getVisiblePages(context)
    return #pages > 0 and pages[1].id or nil
end

function AGFUIInformationArchitecture.isMutationAllowed(pageId, context)
    local page = AGFUIInformationArchitecture.getPage(pageId)
    if page == nil then return false, "UNKNOWN_UI_PAGE" end
    if page.mutating ~= true then return true, nil end

    context = context or {}
    if context.readOnlySafeMode == true then return false, "READ_ONLY_SAFE_MODE" end
    if context.clientWaitingForSync == true then return false, "CLIENT_WAITING_FOR_SYNC" end
    if context.serverMutationAvailable ~= true then return false, "SERVER_MUTATION_UNAVAILABLE" end
    return true, nil
end
