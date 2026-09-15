-- AgForward Financial Cooperative
-- Pure server-side state revision / request-idempotency model. No network event
-- serialization is implemented here.

AGFFinancialProtocolState = {}
AGFFinancialProtocolState_mt = Class(AGFFinancialProtocolState)

function AGFFinancialProtocolState.new(idService, cacheLimit)
    local self = setmetatable({}, AGFFinancialProtocolState_mt)
    self.idService = idService
    self.stateRevision = 0
    self.cacheLimit = math.max(16, math.floor(tonumber(cacheLimit) or 256))
    self.requestResults = {}
    self.requestOrder = {}
    return self
end

function AGFFinancialProtocolState:getRevision()
    return self.stateRevision
end

function AGFFinancialProtocolState:setRevision(revision)
    local value = math.max(0, math.floor(tonumber(revision) or 0))
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
    local known = math.max(0, math.floor(tonumber(clientKnownRevision) or 0))
    if known ~= self.stateRevision then
        return false, "STALE_STATE_REVISION", self.stateRevision
    end
    return true, nil, self.stateRevision
end

function AGFFinancialProtocolState:getCachedRequest(requestId)
    if requestId == nil then return nil end
    local result = self.requestResults[tostring(requestId)]
    if result == nil then return nil end
    local copy = {}
    for key, value in pairs(result) do copy[key] = value end
    return copy
end

function AGFFinancialProtocolState:beginRequest(requestId, connectionKey, operationType, clientKnownRevision)
    if requestId == nil or requestId == "" then return false, "REQUEST_ID_REQUIRED" end
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

    local operationId, operationError = self:nextOperationId()
    if operationId == nil then return false, operationError end

    local previousRevision = self.stateRevision
    self.stateRevision = self.stateRevision + 1

    local record = {
        requestId = requestContext.requestId,
        connectionKey = requestContext.connectionKey,
        operationType = requestContext.operationType,
        operationId = operationId,
        resultCode = resultCode or "SUCCESS",
        previousRevision = previousRevision,
        newRevision = self.stateRevision,
        resultData = resultData
    }

    self.requestResults[record.requestId] = record
    table.insert(self.requestOrder, record.requestId)
    self:trimCache()

    return true, self:getCachedRequest(record.requestId)
end

function AGFFinancialProtocolState:recordRejectedRequest(requestId, connectionKey, operationType, errorCode, currentRevision)
    if requestId == nil or requestId == "" then return false, "REQUEST_ID_REQUIRED" end
    local key = tostring(requestId)
    if self.requestResults[key] ~= nil then return true, self:getCachedRequest(key) end

    local record = {
        requestId = key,
        connectionKey = connectionKey,
        operationType = operationType,
        operationId = nil,
        resultCode = errorCode or "REJECTED",
        previousRevision = self.stateRevision,
        newRevision = currentRevision or self.stateRevision,
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
    local revision = math.max(0, math.floor(tonumber(clientRevision) or 0))
    return revision ~= self.stateRevision
end
