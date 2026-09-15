AGFSettlementCoordinator = {}
AGFSettlementCoordinator_mt = Class(AGFSettlementCoordinator)

function AGFSettlementCoordinator.new(services)
    local self = setmetatable({}, AGFSettlementCoordinator_mt)
    self.services = services
    self.lastSettlementKey = nil
    return self
end

function AGFSettlementCoordinator:getSettlementKey()
    if g_currentMission == nil or g_currentMission.environment == nil then
        return nil
    end
    return string.format("%s:%s", tostring(g_currentMission.environment.currentYear), tostring(g_currentMission.environment.currentPeriod))
end

function AGFSettlementCoordinator:runPeriodSettlement()
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return
    end

    local key = self:getSettlementKey()
    if key ~= nil and key == self.lastSettlementKey then
        return
    end

    self.lastSettlementKey = key

    -- Phase 0 intentionally performs no money movement.
    -- Later phases will gather obligations, validate liquidity, apply
    -- authorized revolving-credit rules, settle deterministically, and post
    -- principal/interest/fees/rent through the central ledger.
end
