-- AgForward Financial Cooperative
-- Central runtime safety state. Financial mutation is allowed only when the
-- server has successfully loaded/validated a writable AgForward state.

AGFRuntimeState = {
    BOOTSTRAPPING = "BOOTSTRAPPING",
    NEW_STATE = "NEW_STATE",
    NORMAL = "NORMAL",
    RECOVERED = "RECOVERED",
    READ_ONLY_SAFE_MODE = "READ_ONLY_SAFE_MODE",
    CLIENT_WAITING_FOR_SYNC = "CLIENT_WAITING_FOR_SYNC",
    SHUTDOWN = "SHUTDOWN"
}

AGFRuntimeStateService = {}
AGFRuntimeStateService_mt = Class(AGFRuntimeStateService)

function AGFRuntimeStateService.new()
    local self = setmetatable({}, AGFRuntimeStateService_mt)
    self.state = AGFRuntimeState.BOOTSTRAPPING
    self.reason = nil
    self.issues = {}
    return self
end

function AGFRuntimeStateService:getIsServerAuthority()
    if g_currentMission == nil then
        return false
    end
    if g_currentMission.getIsServer ~= nil then
        return g_currentMission:getIsServer()
    end
    return true
end

function AGFRuntimeStateService:setState(state, reason)
    self.state = state or AGFRuntimeState.READ_ONLY_SAFE_MODE
    self.reason = reason
end

function AGFRuntimeStateService:addIssue(code, message, severity)
    table.insert(self.issues, {
        code = tostring(code or "UNKNOWN"),
        message = tostring(message or ""),
        severity = tostring(severity or "warning")
    })
end

function AGFRuntimeStateService:enterSafeMode(code, message)
    self:addIssue(code, message, "error")
    self:setState(AGFRuntimeState.READ_ONLY_SAFE_MODE, code)
    print(string.format("Warning: AgForward entered read-only safe mode (%s): %s", tostring(code), tostring(message)))
end

function AGFRuntimeStateService:canMutate()
    if not self:getIsServerAuthority() then
        return false, "SERVER_AUTHORITY_REQUIRED"
    end

    if self.state == AGFRuntimeState.NORMAL or self.state == AGFRuntimeState.NEW_STATE or self.state == AGFRuntimeState.RECOVERED then
        return true, nil
    end

    return false, "RUNTIME_STATE_NOT_WRITABLE_" .. tostring(self.state)
end

function AGFRuntimeStateService:canSave()
    return self:canMutate()
end

function AGFRuntimeStateService:getState()
    return self.state
end

function AGFRuntimeStateService:getIssues()
    local copy = {}
    for _, issue in ipairs(self.issues) do
        table.insert(copy, {
            code = issue.code,
            message = issue.message,
            severity = issue.severity
        })
    end
    return copy
end
