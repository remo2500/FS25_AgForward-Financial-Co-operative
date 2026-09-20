-- Offline behavioral tests for the schema-v3 SaveService state machine.
-- These tests use an in-memory stand-in for the GIANTS XML/file API. They do
-- not prove engine API compatibility, but they validate recovery selection,
-- safe-mode behavior, generation handling, and write ordering logic.

function Class(classTable)
    return {__index = classTable}
end

AGFRuntimeState = {
    NEW_STATE = "NEW_STATE",
    NORMAL = "NORMAL",
    RECOVERED = "RECOVERED",
    READ_ONLY_SAFE_MODE = "READ_ONLY_SAFE_MODE",
    CLIENT_WAITING_FOR_SYNC = "CLIENT_WAITING_FOR_SYNC"
}

local FakeFS = {
    files = {},
    pending = {},
    writes = {},
    nextHandle = 0
}

local function cloneTable(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = cloneTable(item) end
    return result
end

local function resetFakeFS()
    FakeFS.files = {}
    FakeFS.pending = {}
    FakeFS.writes = {}
    FakeFS.nextHandle = 0
end

function fileExists(path)
    return FakeFS.files[path] ~= nil
end

function loadXMLFile(name, path)
    local stored = FakeFS.files[path]
    if stored == nil or stored.unreadable then return 0 end
    FakeFS.nextHandle = FakeFS.nextHandle + 1
    return {
        id = FakeFS.nextHandle,
        path = path,
        data = cloneTable(stored.data or {})
    }
end

function createXMLFile(name, path, rootKey)
    FakeFS.nextHandle = FakeFS.nextHandle + 1
    local handle = {
        id = FakeFS.nextHandle,
        path = path,
        data = {},
        rootKey = rootKey
    }
    FakeFS.pending[handle.id] = handle
    return handle
end

function setXMLInt(xmlFile, key, value)
    xmlFile.data[key] = math.floor(value)
end

function getXMLInt(xmlFile, key)
    return xmlFile.data[key]
end

function saveXMLFile(xmlFile)
    FakeFS.files[xmlFile.path] = {data = cloneTable(xmlFile.data)}
    table.insert(FakeFS.writes, xmlFile.path)
end

function delete(xmlFile)
    if type(xmlFile) == "table" then FakeFS.pending[xmlFile.id] = nil end
end

local function putCandidate(path, schemaVersion, generation, options)
    options = options or {}
    FakeFS.files[path] = {
        unreadable = options.unreadable == true,
        data = {
            ["agForwardFinance#schemaVersion"] = schemaVersion,
            ["agForwardFinance#saveGeneration"] = generation,
            forceLoadError = options.forceLoadError == true,
            integrityFail = options.integrityFail == true,
            marker = options.marker
        }
    }
end

g_currentMission = {
    missionInfo = {savegameDirectory = "/save"},
    environment = {currentPeriod = 7, currentYear = 2026},
    getIsServer = function() return true end
}

FSBaseMission = nil
Mission00 = nil
Utils = nil

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

local function newRuntimeState()
    local runtime = {
        state = "BOOT",
        reason = nil,
        detail = nil,
        issues = {}
    }

    function runtime:setState(state, reason)
        self.state = state
        self.reason = reason
    end

    function runtime:enterSafeMode(reason, detail)
        self.state = AGFRuntimeState.READ_ONLY_SAFE_MODE
        self.reason = reason
        self.detail = detail
    end

    function runtime:addIssue(code, detail, severity)
        table.insert(self.issues, {code = code, detail = detail, severity = severity})
    end

    function runtime:canSave()
        if self.state == AGFRuntimeState.READ_ONLY_SAFE_MODE then return false, "READ_ONLY_SAFE_MODE" end
        if self.state == AGFRuntimeState.CLIENT_WAITING_FOR_SYNC then return false, "CLIENT_WAITING_FOR_SYNC" end
        return true, nil
    end

    return runtime
end

local function newStatefulService()
    local service = {resetCount = 0, loadCount = 0, saveCount = 0, lastMarker = nil}

    function service:reset()
        self.resetCount = self.resetCount + 1
        self.lastMarker = nil
    end

    function service:loadFromXMLFile(xmlFile, key)
        self.loadCount = self.loadCount + 1
        self.lastMarker = xmlFile.data.marker
        if xmlFile.data.forceLoadError then
            return 0, {"FORCED_LOAD_ERROR"}
        end
        return 1, {}
    end

    function service:saveToXMLFile(xmlFile, key)
        self.saveCount = self.saveCount + 1
        xmlFile.data.marker = "saved"
    end

    return service
end

local function newIdService()
    local service = newStatefulService()
    return service
end

local function newIntegrity()
    local integrity = {forceFailure = false, runCount = 0}
    function integrity:run(schemaVersion)
        self.runCount = self.runCount + 1
        if self.forceFailure then
            return false, {errors = {{code = "FORCED_INTEGRITY_FAILURE"}}}
        end
        return true, {errors = {}}
    end
    return integrity
end

local function newServices()
    local map = {
        runtimeState = newRuntimeState(),
        idService = newIdService(),
        liabilities = newStatefulService(),
        ledger = newStatefulService(),
        settlement = newStatefulService(),
        integrity = newIntegrity()
    }
    return {
        map = map,
        get = function(self, name) return self.map[name] end
    }
end

dofile("src/core/SaveService.lua")

local function newSaveService()
    local services = newServices()
    return AGFSaveService.new(services), services
end

-- No copies is a legitimate new state, not a corruption recovery case.
resetFakeFS()
local saveService, services = newSaveService()
local loaded = saveService:load()
assertTrue(loaded, "new save loads")
assertEqual(saveService.lastLoadStatus, "NEW_SAVE", "new save status")
assertEqual(saveService.saveGeneration, 0, "new save generation")
assertEqual(services.map.runtimeState.state, AGFRuntimeState.NEW_STATE, "new save runtime state")

-- First save must write the recovery copy before primary and advance once.
local saved = saveService:save()
assertTrue(saved, "first save succeeds")
assertEqual(saveService.saveGeneration, 1, "first save generation")
assertEqual(FakeFS.writes[1], "/save/agForwardFinance.backup.xml", "backup written first")
assertEqual(FakeFS.writes[2], "/save/agForwardFinance.xml", "primary written second")
assertEqual(FakeFS.files["/save/agForwardFinance.backup.xml"].data["agForwardFinance#saveGeneration"], 1, "backup generation")
assertEqual(FakeFS.files["/save/agForwardFinance.xml"].data["agForwardFinance#saveGeneration"], 1, "primary generation")

-- Equal valid copies prefer primary and report NORMAL.
local reloadService, reloadServices = newSaveService()
local reloaded = reloadService:load()
assertTrue(reloaded, "saved state reloads")
assertEqual(reloadService.loadedFrom, "primary", "equal generation prefers primary")
assertEqual(reloadService.saveGeneration, 1, "reloaded generation")
assertEqual(reloadServices.map.runtimeState.state, AGFRuntimeState.NORMAL, "normal runtime state")

-- A newer backup (e.g. interruption between recovery and primary writes) wins.
resetFakeFS()
putCandidate("/save/agForwardFinance.xml", 3, 4, {marker = "primary-old"})
putCandidate("/save/agForwardFinance.backup.xml", 3, 5, {marker = "backup-new"})
local interruptedService, interruptedServices = newSaveService()
assertTrue(interruptedService:load(), "newer backup loads")
assertEqual(interruptedService.loadedFrom, "backup", "newer backup selected")
assertEqual(interruptedService.saveGeneration, 5, "newer backup generation retained")
assertEqual(interruptedServices.map.runtimeState.state, AGFRuntimeState.RECOVERED, "backup selection reports recovered")
assertEqual(interruptedServices.map.liabilities.lastMarker, "backup-new", "backup content loaded")

-- Header-valid primary with a record-load failure must fall back to backup.
resetFakeFS()
putCandidate("/save/agForwardFinance.xml", 3, 8, {forceLoadError = true, marker = "bad-primary"})
putCandidate("/save/agForwardFinance.backup.xml", 3, 7, {marker = "good-backup"})
local fallbackService, fallbackServices = newSaveService()
assertTrue(fallbackService:load(), "record failure falls back")
assertEqual(fallbackService.loadedFrom, "backup", "fallback copy selected")
assertEqual(fallbackService.saveGeneration, 7, "fallback adopts validated generation")
assertEqual(fallbackServices.map.runtimeState.state, AGFRuntimeState.RECOVERED, "fallback reports recovered")
assertEqual(fallbackServices.map.liabilities.lastMarker, "good-backup", "fallback content loaded")

-- Unreadable primary with a valid backup is recoverable.
resetFakeFS()
putCandidate("/save/agForwardFinance.xml", 3, 9, {unreadable = true})
putCandidate("/save/agForwardFinance.backup.xml", 3, 8, {marker = "backup-only"})
local unreadableService, unreadableServices = newSaveService()
assertTrue(unreadableService:load(), "unreadable primary uses backup")
assertEqual(unreadableService.loadedFrom, "backup", "backup chosen for unreadable primary")
assertEqual(unreadableServices.map.runtimeState.state, AGFRuntimeState.RECOVERED, "unreadable primary recovery state")

-- If no candidate can even provide a schema/generation header, mutation must stop.
resetFakeFS()
putCandidate("/save/agForwardFinance.xml", 0, 0)
putCandidate("/save/agForwardFinance.backup.xml", 0, 0)
local invalidService, invalidServices = newSaveService()
assertFalse(invalidService:load(), "invalid copies rejected")
assertEqual(invalidService.lastLoadStatus, "NO_VALID_FINANCIAL_COPY", "invalid copy status")
assertEqual(invalidServices.map.runtimeState.state, AGFRuntimeState.READ_ONLY_SAFE_MODE, "invalid copies enter safe mode")
assertFalse(invalidService:save(), "safe mode blocks overwrite")

-- A newer schema is intentionally not bypassed by an older compatible backup.
resetFakeFS()
putCandidate("/save/agForwardFinance.xml", 4, 12, {marker = "future-primary"})
putCandidate("/save/agForwardFinance.backup.xml", 3, 11, {marker = "old-backup"})
local futureService, futureServices = newSaveService()
assertFalse(futureService:load(), "newer schema blocks load")
assertEqual(futureService.lastLoadStatus, "READ_ONLY_NEWER_SCHEMA", "newer schema status")
assertEqual(futureService.loadedSchemaVersion, 4, "newer schema retained in status")
assertEqual(futureService.saveGeneration, 12, "newer generation retained in status")
assertEqual(futureServices.map.runtimeState.state, AGFRuntimeState.READ_ONLY_SAFE_MODE, "newer schema safe mode")
assertFalse(futureService:save(), "older build cannot overwrite newer schema")

-- Pre-save integrity failure must block both writes and enter safe mode.
resetFakeFS()
local integrityService, integrityServices = newSaveService()
assertTrue(integrityService:load(), "integrity case starts as new save")
integrityServices.map.integrity.forceFailure = true
local integritySaved = integrityService:save()
assertFalse(integritySaved, "integrity failure blocks save")
assertEqual(#FakeFS.writes, 0, "integrity failure writes no copies")
assertEqual(integrityService.lastSaveStatus, "PRE_SAVE_INTEGRITY_FAILED", "integrity failure status")
assertEqual(integrityServices.map.runtimeState.state, AGFRuntimeState.READ_ONLY_SAFE_MODE, "integrity failure enters safe mode")

-- Multiplayer clients must never read local save files as authority.
resetFakeFS()
putCandidate("/save/agForwardFinance.xml", 3, 20, {marker = "server-only"})
g_currentMission.getIsServer = function() return false end
local clientService, clientServices = newSaveService()
assertFalse(clientService:load(), "client local load blocked")
assertEqual(clientService.lastLoadStatus, "CLIENT_WAITING_FOR_SYNC", "client load status")
assertEqual(clientServices.map.runtimeState.state, AGFRuntimeState.CLIENT_WAITING_FOR_SYNC, "client runtime state")
assertEqual(clientServices.map.liabilities.loadCount, 0, "client did not load liability state")
g_currentMission.getIsServer = function() return true end

print("offline_save_service_tests: PASS")
