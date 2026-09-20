-- AgForward Financial Cooperative
-- Pure semantic action-bar model for the future native FS25 menu integration.
-- It deliberately does not bind GIANTS InputAction names until runtime testing
-- confirms the exact action/button conventions.

AGFNativeUIActionId = {
    OPEN = "open",
    APPLY = "apply",
    DRAW = "draw",
    REPAY = "repay",
    PAY = "pay",
    PAYOFF = "payoff",
    CURE = "cure",
    SCHEDULE = "schedule",
    REPORT = "report",
    FUNDING_POLICY = "fundingPolicy",
    DETAILS = "details"
}

AGFNativeUIActionModelService = {}

local ACTION_DEFINITIONS = {
    [AGFNativeUIActionId.OPEN] = {titleKey = "agf_ui_action_open", mutating = false},
    [AGFNativeUIActionId.APPLY] = {titleKey = "agf_ui_action_apply", mutating = true},
    [AGFNativeUIActionId.DRAW] = {titleKey = "agf_ui_action_draw", mutating = true},
    [AGFNativeUIActionId.REPAY] = {titleKey = "agf_ui_action_repay", mutating = true},
    [AGFNativeUIActionId.PAY] = {titleKey = "agf_ui_action_pay", mutating = true},
    [AGFNativeUIActionId.PAYOFF] = {titleKey = "agf_ui_action_payoff", mutating = true},
    [AGFNativeUIActionId.CURE] = {titleKey = "agf_ui_action_cure", mutating = true},
    [AGFNativeUIActionId.SCHEDULE] = {titleKey = "agf_ui_action_schedule", mutating = false},
    [AGFNativeUIActionId.REPORT] = {titleKey = "agf_ui_action_report", mutating = false},
    [AGFNativeUIActionId.FUNDING_POLICY] = {titleKey = "agf_ui_action_policy", mutating = true},
    [AGFNativeUIActionId.DETAILS] = {titleKey = "agf_ui_action_details", mutating = false}
}

local function cloneDefinition(actionId)
    local definition = ACTION_DEFINITIONS[actionId]
    if definition == nil then return nil end
    return {
        id = actionId,
        titleKey = definition.titleKey,
        mutating = definition.mutating == true
    }
end

local function actionAllowed(action, context)
    if action.mutating ~= true then return true, nil end
    if context.readOnlySafeMode == true then return false, "READ_ONLY_SAFE_MODE" end
    if context.clientWaitingForSync == true then return false, "CLIENT_WAITING_FOR_SYNC" end
    if context.serverMutationAvailable ~= true then return false, "SERVER_MUTATION_UNAVAILABLE" end
    return true, nil
end

local function addAction(actions, actionId, context, extra)
    local action = cloneDefinition(actionId)
    if action == nil then return end
    local enabled, reason = actionAllowed(action, context)
    action.enabled = enabled
    action.disabledReason = reason
    for key, value in pairs(extra or {}) do action[key] = value end
    table.insert(actions, action)
end

function AGFNativeUIActionModelService.build(pageId, selection, context)
    context = context or {}
    selection = selection or {}
    local actions = {}

    if pageId == AGFUIPageId.OVERVIEW then
        addAction(actions, AGFNativeUIActionId.DETAILS, context, {target = "financialPosition"})
        return actions
    end

    if pageId == AGFUIPageId.BANKING then
        if selection.productType == AGFProductType.OPERATING_LINE then
            addAction(actions, AGFNativeUIActionId.DRAW, context, {targetId = selection.id})
            addAction(actions, AGFNativeUIActionId.REPAY, context, {targetId = selection.id})
        elseif selection.productType == AGFProductType.CROP_INPUT_LINE then
            addAction(actions, AGFNativeUIActionId.FUNDING_POLICY, context, {targetId = selection.id})
            addAction(actions, AGFNativeUIActionId.REPAY, context, {targetId = selection.id})
        end
        addAction(actions, AGFNativeUIActionId.APPLY, context, {productFamily = "banking"})
        return actions
    end

    if pageId == AGFUIPageId.ASSET_FINANCE then
        if selection.liabilityId ~= nil then
            addAction(actions, AGFNativeUIActionId.DETAILS, context, {targetId = selection.liabilityId})
            addAction(actions, AGFNativeUIActionId.SCHEDULE, context, {targetId = selection.liabilityId})
            addAction(actions, AGFNativeUIActionId.PAYOFF, context, {targetId = selection.liabilityId})
        end
        return actions
    end

    if pageId == AGFUIPageId.LAND_LEASES then
        if selection.id ~= nil then
            addAction(actions, AGFNativeUIActionId.DETAILS, context, {targetId = selection.id})
            if selection.arrangement == "finance" then
                addAction(actions, AGFNativeUIActionId.SCHEDULE, context, {targetId = selection.id})
                addAction(actions, AGFNativeUIActionId.PAYOFF, context, {targetId = selection.id})
            end
        end
        return actions
    end

    if pageId == AGFUIPageId.PAYMENTS then
        if selection.liabilityId ~= nil then
            addAction(actions, AGFNativeUIActionId.PAY, context, {targetId = selection.liabilityId})
            if (tonumber(selection.pastDue) or 0) > 0 then
                addAction(actions, AGFNativeUIActionId.CURE, context, {targetId = selection.liabilityId})
            end
            addAction(actions, AGFNativeUIActionId.PAYOFF, context, {targetId = selection.liabilityId})
            addAction(actions, AGFNativeUIActionId.SCHEDULE, context, {targetId = selection.liabilityId})
        end
        return actions
    end

    if pageId == AGFUIPageId.REPORTS then
        if selection.id ~= nil then
            addAction(actions, AGFNativeUIActionId.REPORT, context, {targetId = selection.id})
        end
        return actions
    end

    if pageId == AGFUIPageId.GOVERNMENT then
        if context.governmentIntegrationAvailable == true then
            addAction(actions, AGFNativeUIActionId.DETAILS, context, {target = "governmentIntegration"})
        end
        return actions
    end

    return actions
end
