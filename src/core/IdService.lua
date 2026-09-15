AGFIdService = {}
AGFIdService_mt = Class(AGFIdService)

function AGFIdService.new()
    local self = setmetatable({}, AGFIdService_mt)
    self.counters = {}
    return self
end

function AGFIdService:next(scope)
    scope = scope or "GEN"
    local nextValue = (self.counters[scope] or 0) + 1
    self.counters[scope] = nextValue
    return string.format("AGF-%s-%06d", string.upper(scope), nextValue)
end

function AGFIdService:setCounter(scope, value)
    self.counters[scope] = math.max(0, tonumber(value) or 0)
end

function AGFIdService:getCounter(scope)
    return self.counters[scope] or 0
end
