-- AgForward Financial Cooperative
-- Pure server-side state revision / request-idempotency model. No network event
-- serialization is implemented here.

AGFFinancialProtocolState = {}
AGFFinancialProtocolState_mt = Class(AGFFinancialProtocolState)

local function isFiniteNumber(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function normalizeRevision(value)
    local number = tonumber(value)
    if number == nil or not isFiniteNumber(number) or number < 0 or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function normalizeCacheLimit(value)
    local number = tonumber(value)
    if number == nil or not isFiniteNumber(number) then return 256 end
    number = math.floor(number)
    if number < 16 then return 16 end
    return number
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(item, seen)
    end
    return copy
end

function AGFFinancialProtocolState.new(idService, cacheLimit)
    local self = setmetatable({}, AGFFinancialProtocolState_mt)
    self.idService = idService
    self.stateRevision = 0
    self.cacheLimit = normalizeCacheLimit(cacheLimit)
    self.requestResults = {}
    self.requestOrder = {}
    return self
end

function AGFFinancialProtocolState:getRevision()
    return self.stateRevision
end

function AGFFinancialProtocolState:setRevision(revision)
    local value = normalizeRevision(revision)
    if value == nil then return false, "INVALID_REVISION" end
    if value < self.stateRevision then
        return false, "REVISION_REGRESSION"
    end
    self.stateRevision = value
    return true, self.stateRevision
end

function AGFFinancialProtocolState:nextOperationId()
    if self.idService == nil then return nil, "ID_SERVICE_UNAVAILABLE" end
    return self.idService:next("OP"), nil
end

function AGFFinancialProtocolState:checkClientRevision(clientKnownRevision)
    local known = normalizeRevision(clientKnownRevision)
    if known == nil then
        return false, "INVALID_CLIENT_REVISION", self.stateRevision
    end
    if known ~= self.stateRevision then
        return false, "STALE_STATE_REVISION", self.stateRevision
    end
    return true, nil, self.stateRevision
end

function AGFFinancialProtocolState:getCachedRequest(requestId)
    if requestId == nil then return nil end
    local result = self.requestResults[tostring(requestId)]
    if result == nil then return nil end
    return deepCopy(result)
end

function AGFFinancialProtocolState:beginRequest(requestId, connectionKey, operationType, clientKnownRevision)
    if requestId == nil or requestId == "" then return false, "REQUEST_ID_REQUIRED" end
    if connectionKey == nil or connectionKey == "" then return false, "REQUEST_CONNECTION_REQUIRED" end
    if operationType == nil or operationType == "" then return false, "OPERATION_TYPE_REQUIRED" end

    local key = tostring(requestId)
    local cached = self:getCachedRequest(key)
    if cached ~= nil then
        if tostring(cached.connectionKey) ~= tostring(connectionKey) or cached.operationType ~= operationType then
            return false, "REQUEST_ID_COLLISION"
        end
        return true, {
            duplicate = true,
            cachedResult = cached
        }
    end

    local revisionOk, revisionError, currentRevision = self:checkClientRevision(clientKnownRevision)
    if not revisionOk then
        return false, revisionError, currentRevision
    end

    return true, {
        duplicate = false,
        requestId = key,
        connectionKey = connectionKey,
        operationType = operationType,
        previousRevision = self.stateRevision
    }
end

function AGFFinancialProtocolState:commitRequest(requestContext, resultCode, resultData)
    if requestContext == nil or requestContext.requestId == nil or requestContext.duplicate then
        return false, "INVALID_REQUEST_CONTEXT"
    end
    if requestContext.connectionKey == nil or requestContext.operationType == nil then
        return false, "INVALID_REQUEST_CONTEXT"
    end

    local expectedRevision = normalizeRevision(requestContext.previousRevision)
    if expectedRevision == nil then return false, "INVALID_REQUEST_CONTEXT_REVISION" end
    if expectedRevision ~= self.stateRevision then
        return false, "REQUEST_CONTEXT_STALE", self.stateRevision
    end

    if self.requestResults[tostring(requestContext.requestId)] ~= nil then
        return false, "REQUEST_ALREADY_COMMITTED"
    end

    local operationId, operationError = self:nextOperationId()
    if operationId == nil then return false, operationError end

    local previousRevision = self.stateRevision
    self.stateRevision = self.stateRevision + 1

    local record = {
        requestId = tostring(requestContext.requestId),
        connectionKey = requestContext.connectionKey,
        operationType = requestContext.operationType,
        operationId = operationId,
        resultCode = resultCode or "SUCCESS",
        previousRevision = previousRevision,
        newRevision = self.stateRevision,
        resultData = deepCopy(resultData)
    }

    self.requestResults[record.requestId] = record
    table.insert(self.requestOrder, record.requestId)
    self:trimCache()

    return true, self:getCachedRequest(record.requestId)
end

function AGFFinancialProtocolState:recordRejectedRequest(requestId, connectionKey, operationType, errorCode, currentRevision)
    if requestId == nil or requestId == "" then return false, "REQUEST_ID_REQUIRED" end
    if connectionKey == nil or connectionKey == "" then return false, "REQUEST_CONNECTION_REQUIRED" end
    if operationType == nil or operationType == "" then return false, "OPERATION_TYPE_REQUIRED" end

    local key = tostring(requestId)
    local existing = self.requestResults[key]
    if existing ~= nil then
        if tostring(existing.connectionKey) ~= tostring(connectionKey) or existing.operationType ~= operationType then
            return false, "REQUEST_ID_COLLISION"
        end
        return true, self:getCachedRequest(key)
    end

    local reportedRevision = currentRevision == nil and self.stateRevision or normalizeRevision(currentRevision)
    if reportedRevision == nil then return false, "INVALID_REVISION" end

    local record = {
        requestId = key,
        connectionKey = connectionKey,
        operationType = operationType,
        operationId = nil,
        resultCode = errorCode or "REJECTED",
        previousRevision = self.stateRevision,
        newRevision = reportedRevision,
        resultData = nil
    }
    self.requestResults[key] = record
    table.insert(self.requestOrder, key)
    self:trimCache()
    return true, self:getCachedRequest(key)
end

function AGFFinancialProtocolState:trimCache()
    while #self.requestOrder > self.cacheLimit do
        local oldest = table.remove(self.requestOrder, 1)
        self.requestResults[oldest] = nil
    end
end

function AGFFinancialProtocolState:needsResync(clientRevision)
    local revision = normalizeRevision(clientRevision)
    if revision == nil then return true end
    return revision ~= self.stateRevision
end
