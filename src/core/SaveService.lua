-- AgForward Financial Cooperative
-- Versioned native save/load service for AgForward state.

AGFSaveService = {}
AGFSaveService_mt = Class(AGFSaveService)

AGFSaveService.FILE_NAME = "agForwardFinance.xml"
AGFSaveService.ROOT_KEY = "agForwardFinance"
AGFSaveService.SCHEMA_VERSION = 2
AGFSaveService.saveHookInstalled = false

function AGFSaveService.new(services)
    local self = setmetatable({}, AGFSaveService_mt)
    self.services = services
    self.lastLoadStatus = "NOT_LOADED"
    self.lastSaveStatus = "NOT_SAVED"
    self.loadedSchemaVersion = 0
    return self
end

function AGFSaveService:isServer()
    if g_currentMission == nil then
        return false
    end

    if g_currentMission.getIsServer ~= nil then
        return g_currentMission:getIsServer()
    end

    return true
end

function AGFSaveService:getSaveFilePath()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end

    local savegameDirectory = g_currentMission.missionInfo.savegameDirectory
    if savegameDirectory == nil or savegameDirectory == "" then
        return nil
    end

    return savegameDirectory .. "/" .. AGFSaveService.FILE_NAME
end

function AGFSaveService:load()
    if not self:isServer() then
        self.lastLoadStatus = "CLIENT_WAITING_FOR_SYNC"
        return false
    end

    local filePath = self:getSaveFilePath()
    if filePath == nil then
        self.lastLoadStatus = "NO_SAVE_DIRECTORY"
        print("AgForward: save load deferred; no savegame directory is available")
        return false
    end

    if not fileExists(filePath) then
        self.lastLoadStatus = "NEW_SAVE"
        self.loadedSchemaVersion = AGFSaveService.SCHEMA_VERSION
        print("AgForward: no existing agForwardFinance.xml; starting with empty financial state")
        return true
    end

    local xmlFile = loadXMLFile("AgForwardFinance", filePath)
    if xmlFile == nil or xmlFile == 0 then
        self.lastLoadStatus = "LOAD_FAILED"
        print("Warning: AgForward could not load " .. tostring(filePath))
        return false
    end

    local rootKey = AGFSaveService.ROOT_KEY
    local schemaVersion = getXMLInt(xmlFile, rootKey .. "#schemaVersion") or 0
    self.loadedSchemaVersion = schemaVersion

    if schemaVersion > AGFSaveService.SCHEMA_VERSION then
        print(string.format(
            "Warning: AgForward save schema %d is newer than supported schema %d; attempting best-effort load",
            schemaVersion,
            AGFSaveService.SCHEMA_VERSION
        ))
    end

    local idService = self.services:get("idService")
    if idService ~= nil then
        idService:loadFromXMLFile(xmlFile, rootKey .. ".idCounters")
    end

    -- Schema v2 introduced the native liability registry. Older saves simply
    -- have no liability nodes and therefore migrate to an empty registry.
    local liabilities = self.services:get("liabilities")
    if liabilities ~= nil then
        liabilities:loadFromXMLFile(xmlFile, rootKey .. ".liabilities")
    end

    local ledger = self.services:get("ledger")
    if ledger ~= nil then
        ledger:loadFromXMLFile(xmlFile, rootKey .. ".ledger")
    end

    delete(xmlFile)

    self.lastLoadStatus = "LOADED"
    print(string.format("AgForward: loaded native financial state (schema %d)", schemaVersion))
    return true
end

function AGFSaveService:save()
    if not self:isServer() then
        self.lastSaveStatus = "CLIENT_SKIPPED"
        return false
    end

    local filePath = self:getSaveFilePath()
    if filePath == nil then
        self.lastSaveStatus = "NO_SAVE_DIRECTORY"
        print("Warning: AgForward could not save; no savegame directory is available")
        return false
    end

    local rootKey = AGFSaveService.ROOT_KEY
    local xmlFile = createXMLFile("AgForwardFinance", filePath, rootKey)
    if xmlFile == nil or xmlFile == 0 then
        self.lastSaveStatus = "CREATE_FAILED"
        print("Warning: AgForward could not create " .. tostring(filePath))
        return false
    end

    setXMLInt(xmlFile, rootKey .. "#schemaVersion", AGFSaveService.SCHEMA_VERSION)

    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        local environment = g_currentMission.environment
        if environment.currentPeriod ~= nil then
            setXMLInt(xmlFile, rootKey .. "#savedPeriod", environment.currentPeriod)
        end
        if environment.currentYear ~= nil then
            setXMLInt(xmlFile, rootKey .. "#savedYear", environment.currentYear)
        end
    end

    local idService = self.services:get("idService")
    if idService ~= nil then
        idService:saveToXMLFile(xmlFile, rootKey .. ".idCounters")
    end

    local liabilities = self.services:get("liabilities")
    if liabilities ~= nil then
        liabilities:saveToXMLFile(xmlFile, rootKey .. ".liabilities")
    end

    local ledger = self.services:get("ledger")
    if ledger ~= nil then
        ledger:saveToXMLFile(xmlFile, rootKey .. ".ledger")
    end

    saveXMLFile(xmlFile)
    delete(xmlFile)

    self.lastSaveStatus = "SAVED"
    return true
end

function AGFSaveService:getStatus()
    return {
        load = self.lastLoadStatus,
        save = self.lastSaveStatus,
        schemaVersion = self.loadedSchemaVersion
    }
end

function AGFSaveService:installSaveHook()
    if AGFSaveService.saveHookInstalled then
        return true
    end

    local target = FSBaseMission
    if Mission00 ~= nil and rawget(Mission00, "saveSavegame") ~= nil then
        target = Mission00
    end

    if target == nil or target.saveSavegame == nil or Utils == nil or Utils.appendedFunction == nil then
        print("Warning: AgForward could not install savegame hook")
        return false
    end

    target.saveSavegame = Utils.appendedFunction(target.saveSavegame, AGFSaveService.onMissionSave)
    AGFSaveService.saveHookInstalled = true
    return true
end

function AGFSaveService.onMissionSave(mission, ...)
    if AgForwardFinance == nil or AgForwardFinance.services == nil then
        return
    end

    local saveService = AgForwardFinance.services:get("save")
    if saveService ~= nil then
        saveService:save()
    end
end
