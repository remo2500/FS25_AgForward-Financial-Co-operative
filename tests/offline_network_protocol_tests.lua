-- Offline validation for server financial request revision/idempotency behavior.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/IdService.lua")
dofile("src/network/FinancialProtocolState.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local function assertFalse(value, message)
    if value ~= false then error(message or "expected false") end
end

local ids = AGFIdService.new()
local protocol = AGFFinancialProtocolState.new(ids, 2)
assertEqual(protocol.cacheLimit, 16, "cache minimum prevents tiny replay window")
assertEqual(protocol:getRevision(), 0, "initial revision")
assertFalse(protocol:needsResync(0), "matching revision needs no resync")
assertTrue(protocol:needsResync(nil), "invalid/missing revision resyncs")
assertTrue(protocol:needsResync(0 / 0), "NaN revision resyncs")

-- Revision setters are monotonic finite whole numbers.
local invalidRevisionOk, invalidRevisionError = protocol:setRevision(0 / 0)
assertFalse(invalidRevisionOk, "NaN revision rejected")
assertEqual(invalidRevisionError, "INVALID_REVISION", "NaN revision error")
local fractionalRevisionOk, fractionalRevisionError = protocol:setRevision(1.5)
assertFalse(fractionalRevisionOk, "fractional revision rejected")
assertEqual(fractionalRevisionError, "INVALID_REVISION", "fractional revision error")
assertTrue(protocol:setRevision(2), "revision can advance explicitly")
local regressOk, regressError = protocol:setRevision(1)
assertFalse(regressOk, "revision regression rejected")
assertEqual(regressError, "REVISION_REGRESSION", "revision regression error")

-- Required request identity fields are fail-closed.
local noRequestOk, noRequestError = protocol:beginRequest(nil, "conn-1", "CREATE_LOAN", 2)
assertFalse(noRequestOk, "missing request ID rejected")
assertEqual(noRequestError, "REQUEST_ID_REQUIRED", "missing request ID error")
local noConnectionOk, noConnectionError = protocol:beginRequest("REQ-A", nil, "CREATE_LOAN", 2)
assertFalse(noConnectionOk, "missing connection rejected")
assertEqual(noConnectionError, "REQUEST_CONNECTION_REQUIRED", "missing connection error")
local noOperationOk, noOperationError = protocol:beginRequest("REQ-A", "conn-1", nil, 2)
assertFalse(noOperationOk, "missing operation type rejected")
assertEqual(noOperationError, "OPERATION_TYPE_REQUIRED", "missing operation type error")

-- Invalid and stale client revisions are distinguishable and return server revision.
local invalidClientOk, invalidClientError, invalidExpected = protocol:beginRequest("REQ-B", "conn-1", "CREATE_LOAN", "not-a-number")
assertFalse(invalidClientOk, "invalid client revision rejected")
assertEqual(invalidClientError, "INVALID_CLIENT_REVISION", "invalid client revision error")
assertEqual(invalidExpected, 2, "invalid revision returns current server revision")
local staleOk, staleError, staleExpected = protocol:beginRequest("REQ-C", "conn-1", "CREATE_LOAN", 1)
assertFalse(staleOk, "stale client revision rejected")
assertEqual(staleError, "STALE_STATE_REVISION", "stale client revision error")
assertEqual(staleExpected, 2, "stale request gets server revision")

-- Normal request commits once and advances the authoritative revision.
local beginOk, request = protocol:beginRequest("REQ-1", "conn-1", "CREATE_LOAN", 2)
assertTrue(beginOk, "request begins")
assertFalse(request.duplicate, "first request is not duplicate")
assertEqual(request.previousRevision, 2, "request captures revision")
local resultData = {liabilityId = "AGF-LIAB-000100", nested = {approved = true}}
local commitOk, committed = protocol:commitRequest(request, "SUCCESS", resultData)
assertTrue(commitOk, "request commits")
assertEqual(committed.previousRevision, 2, "commit previous revision")
assertEqual(committed.newRevision, 3, "commit new revision")
assertEqual(protocol:getRevision(), 3, "server revision advanced")
assertTrue(committed.operationId ~= nil, "committed request gets operation ID")

-- Caller mutation cannot alter the cached authoritative request result, including nested data.
resultData.liabilityId = "MUTATED-CALLER"
resultData.nested.approved = false
committed.resultData.liabilityId = "MUTATED-RETURN"
committed.resultData.nested.approved = false
local cached = protocol:getCachedRequest("REQ-1")
assertEqual(cached.resultData.liabilityId, "AGF-LIAB-000100", "cached result data defensively copied")
assertTrue(cached.resultData.nested.approved, "nested cached data defensively copied")
cached.resultData.nested.approved = false
assertTrue(protocol:getCachedRequest("REQ-1").resultData.nested.approved, "cached query returns deep copy")

-- Duplicate retry from same connection/operation returns the same result and never advances revision.
local duplicateOk, duplicate = protocol:beginRequest("REQ-1", "conn-1", "CREATE_LOAN", 2)
assertTrue(duplicateOk, "duplicate retry recognized even with old client revision")
assertTrue(duplicate.duplicate, "duplicate flag")
assertEqual(duplicate.cachedResult.operationId, protocol:getCachedRequest("REQ-1").operationId, "duplicate returns original operation")
assertEqual(protocol:getRevision(), 3, "duplicate retry does not advance revision")

-- Reusing a request ID across connection or operation boundaries is a collision, not a cache hit.
local connectionCollisionOk, connectionCollisionError = protocol:beginRequest("REQ-1", "conn-2", "CREATE_LOAN", 3)
assertFalse(connectionCollisionOk, "cross-connection request ID collision rejected")
assertEqual(connectionCollisionError, "REQUEST_ID_COLLISION", "cross-connection collision error")
local operationCollisionOk, operationCollisionError = protocol:beginRequest("REQ-1", "conn-1", "DRAW_CREDIT", 3)
assertFalse(operationCollisionOk, "cross-operation request ID collision rejected")
assertEqual(operationCollisionError, "REQUEST_ID_COLLISION", "cross-operation collision error")

-- Concurrency guard: two requests may begin at one revision, but after one commits the other context is stale.
local firstConcurrentOk, firstConcurrent = protocol:beginRequest("REQ-2", "conn-1", "DRAW_CREDIT", 3)
assertTrue(firstConcurrentOk, "first concurrent request begins")
local secondConcurrentOk, secondConcurrent = protocol:beginRequest("REQ-3", "conn-2", "CREATE_LOAN", 3)
assertTrue(secondConcurrentOk, "second concurrent request begins")
local firstConcurrentCommitOk = protocol:commitRequest(firstConcurrent, "SUCCESS", {amount = 1000})
assertTrue(firstConcurrentCommitOk, "first concurrent request commits")
assertEqual(protocol:getRevision(), 4, "first concurrent commit advances revision")
local secondConcurrentCommitOk, secondConcurrentCommitError, secondConcurrentRevision = protocol:commitRequest(secondConcurrent, "SUCCESS", {liabilityId = "AGF-LIAB-000200"})
assertFalse(secondConcurrentCommitOk, "second stale context cannot commit")
assertEqual(secondConcurrentCommitError, "REQUEST_CONTEXT_STALE", "stale context commit error")
assertEqual(secondConcurrentRevision, 4, "stale context receives current revision")
assertEqual(protocol:getRevision(), 4, "stale context does not advance revision")

-- A request context cannot be committed twice even if manually reused after the first commit.
local twiceBeginOk, twiceContext = protocol:beginRequest("REQ-4", "conn-1", "PAY_LOAN", 4)
assertTrue(twiceBeginOk, "twice test request begins")
assertTrue(protocol:commitRequest(twiceContext, "SUCCESS", {amount = 500}), "twice test first commit")
local twiceOk, twiceError = protocol:commitRequest(twiceContext, "SUCCESS", {amount = 500})
assertFalse(twiceOk, "request context cannot commit twice")
-- Revision changed on the first commit, so stale-context protection triggers before cache check.
assertEqual(twiceError, "REQUEST_CONTEXT_STALE", "second commit rejected by revision guard")

-- Rejected-request cache is also bound to connection+operation and never leaks another client's result.
local rejectedOk, rejected = protocol:recordRejectedRequest("REQ-REJECT", "conn-1", "CREATE_LOAN", "CREDIT_DECLINED", protocol:getRevision())
assertTrue(rejectedOk, "rejected request cached")
assertEqual(rejected.resultCode, "CREDIT_DECLINED", "rejection code retained")
assertEqual(rejected.operationId, nil, "rejected request has no operation ID")
local rejectedDuplicateOk, rejectedDuplicate = protocol:recordRejectedRequest("REQ-REJECT", "conn-1", "CREATE_LOAN", "OTHER", protocol:getRevision())
assertTrue(rejectedDuplicateOk, "same rejection retry returns cache")
assertEqual(rejectedDuplicate.resultCode, "CREDIT_DECLINED", "same rejection returns original result")
local rejectedCollisionOk, rejectedCollisionError = protocol:recordRejectedRequest("REQ-REJECT", "conn-2", "CREATE_LOAN", "OTHER", protocol:getRevision())
assertFalse(rejectedCollisionOk, "rejected cache cross-connection collision blocked")
assertEqual(rejectedCollisionError, "REQUEST_ID_COLLISION", "rejected cache collision error")

local badRejectedRevisionOk, badRejectedRevisionError = protocol:recordRejectedRequest("REQ-BADREV", "conn-1", "CREATE_LOAN", "REJECTED", -1)
assertFalse(badRejectedRevisionOk, "invalid rejection revision rejected")
assertEqual(badRejectedRevisionError, "INVALID_REVISION", "invalid rejection revision error")

-- Cache trimming removes oldest request results when capacity is exceeded.
local trimProtocol = AGFFinancialProtocolState.new(ids, 16)
for index = 1, 17 do
    local requestId = "TRIM-" .. tostring(index)
    local okBegin, context = trimProtocol:beginRequest(requestId, "conn-trim", "PING", trimProtocol:getRevision())
    assertTrue(okBegin, "trim request begins")
    assertTrue(trimProtocol:commitRequest(context, "SUCCESS", {index = index}), "trim request commits")
end
assertEqual(trimProtocol:getCachedRequest("TRIM-1"), nil, "oldest cache entry trimmed")
assertTrue(trimProtocol:getCachedRequest("TRIM-2") ~= nil, "second cache entry remains")
assertTrue(trimProtocol:getCachedRequest("TRIM-17") ~= nil, "latest cache entry remains")

print("offline_network_protocol_tests: PASS")
