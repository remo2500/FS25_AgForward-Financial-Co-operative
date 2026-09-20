AGFIdService = {}
AGFIdService_mt = Class(AGFIdService)

local function normalizeScope(scope)
    local value = string.upper(tostring(scope or "GEN"))
    if value == "" then return "GEN" end
    return value
end

local function normalizeCounterValue(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        return 0
    end
    if number <= 0 then return 0 end
    return math.floor(number)
end

function AGFIdService.new()
    local self = setmetatable({}, AGFIdService_mt)
    self.counters = {}
    return self
end

function AGFIdService:next(scope)
    scope = normalizeScope(scope)
    local current = normalizeCounterValue(self.counters[scope])
    local nextValue = current + 1
    self.counters[scope] = nextValue
    return string.format("AGF-%s-%06d", scope, nextValue)
end

function AGFIdService:setCounter(scope, value)
    scope = normalizeScope(scope)
    self.counters[scope] = normalizeCounterValue(value)
end

function AGFIdService:getCounter(scope)
    scope = normalizeScope(scope)
    return normalizeCounterValue(self.counters[scope])
end

function AGFIdService:ensureAtLeast(scope, value)
    scope = normalizeScope(scope)
    local numericValue = normalizeCounterValue(value)
    local current = normalizeCounterValue(self.counters[scope])
    if numericValue > current then
        self.counters[scope] = numericValue
    elseif self.counters[scope] == nil then
        self.counters[scope] = current
    end
end

function AGFIdService:observeId(id)
    if type(id) ~= "string" then
        return
    end

    local scope, value = string.match(id, "^AGF%-([A-Z0-9_]+)%-(%d+)$")
    if scope ~= nil and value ~= nil then
        local numericValue = tonumber(value)
        if numericValue ~= nil and numericValue == numericValue and numericValue ~= math.huge and numericValue ~= -math.huge then
            self:ensureAtLeast(scope, numericValue)
        end
    end
end

function AGFIdService:getCounters()
    local copy = {}
    for scope, value in pairs(self.counters) do
        copy[scope] = normalizeCounterValue(value)
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
        setXMLInt(xmlFile, counterKey .. "#value", normalizeCounterValue(self.counters[scope]))
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
