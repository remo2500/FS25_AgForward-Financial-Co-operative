AGFIdService = {}
AGFIdService_mt = Class(AGFIdService)

function AGFIdService.new()
    local self = setmetatable({}, AGFIdService_mt)
    self.counters = {}
    return self
end

function AGFIdService:next(scope)
    scope = string.upper(scope or "GEN")
    local nextValue = (self.counters[scope] or 0) + 1
    self.counters[scope] = nextValue
    return string.format("AGF-%s-%06d", scope, nextValue)
end

function AGFIdService:setCounter(scope, value)
    scope = string.upper(scope or "GEN")
    self.counters[scope] = math.max(0, math.floor(tonumber(value) or 0))
end

function AGFIdService:getCounter(scope)
    scope = string.upper(scope or "GEN")
    return self.counters[scope] or 0
end

function AGFIdService:ensureAtLeast(scope, value)
    scope = string.upper(scope or "GEN")
    local numericValue = math.max(0, math.floor(tonumber(value) or 0))
    if numericValue > (self.counters[scope] or 0) then
        self.counters[scope] = numericValue
    end
end

function AGFIdService:observeId(id)
    if type(id) ~= "string" then
        return
    end

    local scope, value = string.match(id, "^AGF%-([A-Z0-9_]+)%-(%d+)$")
    if scope ~= nil and value ~= nil then
        self:ensureAtLeast(scope, tonumber(value))
    end
end

function AGFIdService:getCounters()
    local copy = {}
    for scope, value in pairs(self.counters) do
        copy[scope] = value
    end
    return copy
end

function AGFIdService:reset()
    self.counters = {}
end

function AGFIdService:saveToXMLFile(xmlFile, key)
    local scopes = {}
    for scope, _ in pairs(self.counters) do
        table.insert(scopes, scope)
    end
    table.sort(scopes)

    setXMLInt(xmlFile, key .. "#count", #scopes)

    for index, scope in ipairs(scopes) do
        local counterKey = string.format("%s.counter(%d)", key, index - 1)
        setXMLString(xmlFile, counterKey .. "#scope", scope)
        setXMLInt(xmlFile, counterKey .. "#value", self.counters[scope] or 0)
    end
end

function AGFIdService:loadFromXMLFile(xmlFile, key)
    self:reset()

    local index = 0
    while true do
        local counterKey = string.format("%s.counter(%d)", key, index)
        if not hasXMLProperty(xmlFile, counterKey .. "#scope") then
            break
        end

        local scope = getXMLString(xmlFile, counterKey .. "#scope")
        local value = getXMLInt(xmlFile, counterKey .. "#value") or 0
        if scope ~= nil and scope ~= "" then
            self:setCounter(scope, value)
        end

        index = index + 1
    end
end
