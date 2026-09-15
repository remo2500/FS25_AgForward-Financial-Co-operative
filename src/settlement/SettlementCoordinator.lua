AGFSettlementCoordinator = {}
AGFSettlementCoordinator_mt = Class(AGFSettlementCoordinator)

-- Increment when settlement semantics change materially. Including the engine
-- version in the key prevents a Phase 0 no-op marker from blocking Phase 1.
AGFSettlementCoordinator.ENGINE_VERSION = 0

function AGFSettlementCoordinator.new(services)
    local self = setmetatable({}, AGFSettlementCoordinator_mt)
    self.services = services
    self.lastCompletedSettlementKey = nil
    self.inProgressSettlementKey = nil
    return self
end

function AGFSettlementCoordinator:getSettlementKey()
    if g_currentMission == nil or g_currentMission.environment == nil then
        return nil
    end
    return string.format(
        "v%d:%s:%s",
        AGFSettlementCoordinator.ENGINE_VERSION,
        tostring(g_currentMission.environment.currentYear),
        tostring(g_currentMission.environment.currentPeriod)
    )
end

function AGFSettlementCoordinator:runPeriodSettlement()
    local runtimeState = self.services ~= nil and self.services:get("runtimeState") or nil
    if runtimeState == nil then return false, "RUNTIME_STATE_UNAVAILABLE" end
    local allowed, authorityError = runtimeState:canMutate()
    if not allowed then return false, authorityError end

    local key = self:getSettlementKey()
    if key == nil then return false, "SETTLEMENT_KEY_UNAVAILABLE" end
    if key == self.lastCompletedSettlementKey then return true, "ALREADY_COMPLETED" end
    if self.inProgressSettlementKey ~= nil then return false, "SETTLEMENT_ALREADY_IN_PROGRESS" end

    self.inProgressSettlementKey = key

    -- Phase 0 intentionally performs no money movement. Phase 1 will replace
    -- this section with the deterministic obligation pipeline. The completion
    -- marker is persisted so duplicate period-change events cannot double-run.
    local success = true

    if success then
        self.lastCompletedSettlementKey = key
        self.inProgressSettlementKey = nil
        return true, "COMPLETED"
    end

    self.inProgressSettlementKey = nil
    return false, "SETTLEMENT_FAILED"
end

function AGFSettlementCoordinator:saveToXMLFile(xmlFile, key)
    setXMLInt(xmlFile, key .. "#engineVersion", AGFSettlementCoordinator.ENGINE_VERSION)
    if self.lastCompletedSettlementKey ~= nil then
        setXMLString(xmlFile, key .. "#lastCompletedKey", self.lastCompletedSettlementKey)
    end
end

function AGFSettlementCoordinator:loadFromXMLFile(xmlFile, key)
    self.lastCompletedSettlementKey = getXMLString(xmlFile, key .. "#lastCompletedKey")
    self.inProgressSettlementKey = nil
end

function AGFSettlementCoordinator:reset()
    self.lastCompletedSettlementKey = nil
    self.inProgressSettlementKey = nil
end
