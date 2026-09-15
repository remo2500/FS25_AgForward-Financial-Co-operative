-- AgForward Financial Cooperative
-- Versioned native save/load service with dual-copy recovery and read-only
-- protection against corrupt or newer financial state.

AGFSaveService = {}
AGFSaveService_mt = Class(AGFSaveService)

AGFSaveService.FILE_NAME = "agForwardFinance.xml"
AGFSaveService.BACKUP_FILE_NAME = "agForwardFinance.backup.xml"
AGFSaveService.ROOT_KEY = "agForwardFinance"
AGFSaveService.SCHEMA_VERSION = 3
AGFSaveService.saveHookInstalled = false

function AGFSaveService.new(services)
    local self = setmetatable({}, AGFSaveService_mt)
    self.services = services
    self.lastLoadStatus = "NOT_LOADED"
    self.lastSaveStatus = "NOT_SAVED"
    self.loadedSchemaVersion = 0
    self.saveGeneration = 0
    self.loadedFrom = nil
    return self
end

function AGFSaveService:isServer()
    if g_currentMission == nil then return false end
    if g_currentMission.getIsServer ~= nil then return g_currentMission:getIsServer() end
    return true
end

function AGFSaveService:getSaveDirectory()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return nil end
    local directory = g_currentMission.missionInfo.savegameDirectory
    if directory == nil or directory == "" then return nil end
    return directory
end

function AGFSaveService:getPath(fileName)
    local directory = self:getSaveDirectory()
    if directory == nil then return nil end
    return directory .. "/" .. fileName
end

function AGFSaveService:inspectCandidate(path, label)
    local info = {
        path = path,
        label = label,
        exists = false,
        valid = false,
        schemaVersion = 0,
        generation = 0
    }

    if path == nil or not fileExists(path) then return info end
    info.exists = true

    local xmlFile = loadXMLFile("AgForwardInspect_" .. tostring(label), path)
    if xmlFile == nil or xmlFile == 0 then return info end

    local rootKey = AGFSaveService.ROOT_KEY
    info.schemaVersion = getXMLInt(xmlFile, rootKey .. "#schemaVersion") or 0
    info.generation = getXMLInt(xmlFile, rootKey .. "#saveGeneration") or 0
    info.valid = info.schemaVersion > 0 and info.generation >= 0
    delete(xmlFile)
    return info
end

function AGFSaveService:resetFinancialState()
    local idService = self.services:get("idService")
    local liabilities = self.services:get("liabilities")
    local ledger = self.services:get("ledger")
    local settlement = self.services:get("settlement")
    if idService ~= nil then idService:reset() end
    if liabilities ~= nil then liabilities:reset() end
    if ledger ~= nil then ledger:reset() end
    if settlement ~= nil and settlement.reset ~= nil then settlement:reset() end
end

function AGFSaveService:tryLoadCandidate(info)
    local xmlFile = loadXMLFile("AgForwardFinanceLoad", info.path)
    if xmlFile == nil or xmlFile == 0 then
        return false, "XML_LOAD_FAILED"
    end

    self:resetFinancialState()
    local rootKey = AGFSaveService.ROOT_KEY
    local loadErrors = {}

    local idService = self.services:get("idService")
    if idService ~= nil then idService:loadFromXMLFile(xmlFile, rootKey .. ".idCounters") end

    local liabilities = self.services:get("liabilities")
    if liabilities ~= nil then
        local _, errors = liabilities:loadFromXMLFile(xmlFile, rootKey .. ".liabilities")
        for _, errorMessage in ipairs(errors or {}) do table.insert(loadErrors, "liability:" .. errorMessage) end
    end

    local ledger = self.services:get("ledger")
    if ledger ~= nil then
        local _, errors = ledger:loadFromXMLFile(xmlFile, rootKey .. ".ledger")
        for _, errorMessage in ipairs(errors or {}) do table.insert(loadErrors, "ledger:" .. errorMessage) end
    end

    local settlement = self.services:get("settlement")
    if settlement ~= nil and settlement.loadFromXMLFile ~= nil then
        settlement:loadFromXMLFile(xmlFile, rootKey .. ".settlement")
    end

    delete(xmlFile)

    if #loadErrors > 0 then
        self:resetFinancialState()
        return false, "RECORD_LOAD_ERRORS:" .. table.concat(loadErrors, ",")
    end

    local integrity = self.services:get("integrity")
    if integrity ~= nil then
        local valid, report = integrity:run(info.schemaVersion)
        if not valid then
            self:resetFinancialState()
            local codes = {}
            for _, item in ipairs(report.errors or {}) do table.insert(codes, item.code) end
            return false, "INTEGRITY_FAILED:" .. table.concat(codes, ",")
        end
    end

    self.loadedSchemaVersion = info.schemaVersion
    self.saveGeneration = info.generation
    self.loadedFrom = info.label
    return true, nil
end

function AGFSaveService:load()
    local runtimeState = self.services:get("runtimeState")

    if not self:isServer() then
        self.lastLoadStatus = "CLIENT_WAITING_FOR_SYNC"
        if runtimeState ~= nil then runtimeState:setState(AGFRuntimeState.CLIENT_WAITING_FOR_SYNC, self.lastLoadStatus) end
        return false
    end

    local primary = self:inspectCandidate(self:getPath(AGFSaveService.FILE_NAME), "primary")
    local backup = self:inspectCandidate(self:getPath(AGFSaveService.BACKUP_FILE_NAME), "backup")

    if not primary.exists and not backup.exists then
        self:resetFinancialState()
        self.loadedSchemaVersion = AGFSaveService.SCHEMA_VERSION
        self.saveGeneration = 0
        self.loadedFrom = "new"
        self.lastLoadStatus = "NEW_SAVE"
        if runtimeState ~= nil then runtimeState:setState(AGFRuntimeState.NEW_STATE, self.lastLoadStatus) end
        print("AgForward: no existing financial state; starting a new AgForward save")
        return true
    end

    local candidates = {}
    if primary.valid then table.insert(candidates, primary) end
    if backup.valid then table.insert(candidates, backup) end

    if #candidates == 0 then
        self:resetFinancialState()
        self.lastLoadStatus = "NO_VALID_FINANCIAL_COPY"
        if runtimeState ~= nil then runtimeState:enterSafeMode("NO_VALID_FINANCIAL_COPY", "Neither AgForward financial-state copy could be parsed") end
        return false
    end

    -- Prefer the highest save generation. When generations tie, a higher schema
    -- outranks a lower one so an older build can never select/overwrite a same-
    -- generation copy produced by a newer build. Primary is only the final tie-break.
    table.sort(candidates, function(left, right)
        if left.generation ~= right.generation then
            return left.generation > right.generation
        end
        if left.schemaVersion ~= right.schemaVersion then
            return left.schemaVersion > right.schemaVersion
        end
        return left.label == "primary"
    end)

    local newest = candidates[1]
    if newest.schemaVersion > AGFSaveService.SCHEMA_VERSION then
        self:resetFinancialState()
        self.loadedSchemaVersion = newest.schemaVersion
        self.saveGeneration = newest.generation
        self.lastLoadStatus = "READ_ONLY_NEWER_SCHEMA"
        if runtimeState ~= nil then
            runtimeState:enterSafeMode(
                "NEWER_SAVE_SCHEMA",
                string.format("Save schema %d is newer than supported schema %d; overwrite blocked", newest.schemaVersion, AGFSaveService.SCHEMA_VERSION)
            )
        end
        return false
    end

    local failures = {}
    for _, candidate in ipairs(candidates) do
        if candidate.schemaVersion <= AGFSaveService.SCHEMA_VERSION then
            local loaded, loadError = self:tryLoadCandidate(candidate)
            if loaded then
                local recovered = candidate.label == "backup"
                    or (primary.valid and candidate.generation > primary.generation)
                    or not primary.valid
                self.lastLoadStatus = recovered and "RECOVERED_FROM_BACKUP" or "LOADED"
                if runtimeState ~= nil then
                    runtimeState:setState(recovered and AGFRuntimeState.RECOVERED or AGFRuntimeState.NORMAL, self.lastLoadStatus)
                    if recovered then
                        runtimeState:addIssue("RECOVERED_FROM_BACKUP", "AgForward loaded the validated recovery copy", "warning")
                    end
                end
                print(string.format(
                    "AgForward: loaded financial state from %s (schema %d, generation %d)",
                    tostring(candidate.label), candidate.schemaVersion, candidate.generation
                ))
                return true
            end
            table.insert(failures, candidate.label .. ":" .. tostring(loadError))
        end
    end

    self:resetFinancialState()
    self.lastLoadStatus = "INTEGRITY_LOAD_FAILED"
    if runtimeState ~= nil then
        runtimeState:enterSafeMode("INTEGRITY_LOAD_FAILED", table.concat(failures, ";"))
    end
    return false
end

function AGFSaveService:writeStateToFile(path, generation)
    if path == nil then return false, "NO_PATH" end

    local rootKey = AGFSaveService.ROOT_KEY
    local xmlFile = createXMLFile("AgForwardFinance", path, rootKey)
    if xmlFile == nil or xmlFile == 0 then return false, "CREATE_FAILED" end

    setXMLInt(xmlFile, rootKey .. "#schemaVersion", AGFSaveService.SCHEMA_VERSION)
    setXMLInt(xmlFile, rootKey .. "#saveGeneration", generation)

    if g_currentMission ~= nil and g_currentMission.environment ~= nil then
        local environment = g_currentMission.environment
        if environment.currentPeriod ~= nil then setXMLInt(xmlFile, rootKey .. "#savedPeriod", environment.currentPeriod) end
        if environment.currentYear ~= nil then setXMLInt(xmlFile, rootKey .. "#savedYear", environment.currentYear) end
    end

    local idService = self.services:get("idService")
    local liabilities = self.services:get("liabilities")
    local ledger = self.services:get("ledger")
    local settlement = self.services:get("settlement")
    if idService ~= nil then idService:saveToXMLFile(xmlFile, rootKey .. ".idCounters") end
    if liabilities ~= nil then liabilities:saveToXMLFile(xmlFile, rootKey .. ".liabilities") end
    if ledger ~= nil then ledger:saveToXMLFile(xmlFile, rootKey .. ".ledger") end
    if settlement ~= nil and settlement.saveToXMLFile ~= nil then settlement:saveToXMLFile(xmlFile, rootKey .. ".settlement") end

    saveXMLFile(xmlFile)
    delete(xmlFile)
    return true, nil
end

function AGFSaveService:validateWrittenCopy(path, generation)
    local info = self:inspectCandidate(path, "validation")
    if not info.valid then return false, "WRITTEN_COPY_UNREADABLE" end
    if info.schemaVersion ~= AGFSaveService.SCHEMA_VERSION then return false, "WRITTEN_SCHEMA_MISMATCH" end
    if info.generation ~= generation then return false, "WRITTEN_GENERATION_MISMATCH" end
    return true, nil
end

function AGFSaveService:save()
    local runtimeState = self.services:get("runtimeState")
    if runtimeState == nil then return false end
    local allowed, authorityError = runtimeState:canSave()
    if not allowed then
        self.lastSaveStatus = "WRITE_BLOCKED_" .. tostring(authorityError)
        return false
    end

    local integrity = self.services:get("integrity")
    if integrity ~= nil then
        local valid, report = integrity:run(AGFSaveService.SCHEMA_VERSION)
        if not valid then
            self.lastSaveStatus = "PRE_SAVE_INTEGRITY_FAILED"
            local codes = {}
            for _, item in ipairs(report.errors or {}) do table.insert(codes, item.code) end
            runtimeState:enterSafeMode("PRE_SAVE_INTEGRITY_FAILED", table.concat(codes, ","))
            return false
        end
    end

    local generation = self.saveGeneration + 1
    local backupPath = self:getPath(AGFSaveService.BACKUP_FILE_NAME)
    local primaryPath = self:getPath(AGFSaveService.FILE_NAME)
    if backupPath == nil or primaryPath == nil then
        self.lastSaveStatus = "NO_SAVE_DIRECTORY"
        return false
    end

    -- Write and validate the recovery copy first. If the game terminates while
    -- the primary is subsequently written, the next load can select the newer
    -- validated backup generation.
    local backupWritten, backupError = self:writeStateToFile(backupPath, generation)
    if not backupWritten then
        self.lastSaveStatus = "BACKUP_WRITE_FAILED"
        runtimeState:enterSafeMode("BACKUP_WRITE_FAILED", tostring(backupError))
        return false
    end

    local backupValid, backupValidationError = self:validateWrittenCopy(backupPath, generation)
    if not backupValid then
        self.lastSaveStatus = "BACKUP_VALIDATION_FAILED"
        runtimeState:enterSafeMode("BACKUP_VALIDATION_FAILED", tostring(backupValidationError))
        return false
    end

    local primaryWritten, primaryError = self:writeStateToFile(primaryPath, generation)
    if not primaryWritten then
        self.lastSaveStatus = "PRIMARY_WRITE_FAILED_BACKUP_VALID"
        runtimeState:enterSafeMode("PRIMARY_WRITE_FAILED", tostring(primaryError))
        return false
    end

    local primaryValid, primaryValidationError = self:validateWrittenCopy(primaryPath, generation)
    if not primaryValid then
        self.lastSaveStatus = "PRIMARY_VALIDATION_FAILED_BACKUP_VALID"
        runtimeState:enterSafeMode("PRIMARY_VALIDATION_FAILED", tostring(primaryValidationError))
        return false
    end

    self.saveGeneration = generation
    self.loadedSchemaVersion = AGFSaveService.SCHEMA_VERSION
    self.loadedFrom = "primary"
    self.lastSaveStatus = "SAVED"
    return true
end

function AGFSaveService:getStatus()
    return {
        load = self.lastLoadStatus,
        save = self.lastSaveStatus,
        schemaVersion = self.loadedSchemaVersion,
        saveGeneration = self.saveGeneration,
        loadedFrom = self.loadedFrom
    }
end

function AGFSaveService:installSaveHook()
    if AGFSaveService.saveHookInstalled then return true end

    local target = FSBaseMission
    if Mission00 ~= nil and rawget(Mission00, "saveSavegame") ~= nil then target = Mission00 end

    if target == nil or target.saveSavegame == nil or Utils == nil or Utils.appendedFunction == nil then
        print("Warning: AgForward could not install savegame hook")
        return false
    end

    target.saveSavegame = Utils.appendedFunction(target.saveSavegame, AGFSaveService.onMissionSave)
    AGFSaveService.saveHookInstalled = true
    return true
end

function AGFSaveService.onMissionSave(mission, ...)
    if AgForwardFinance == nil or AgForwardFinance.services == nil then return end
    local saveService = AgForwardFinance.services:get("save")
    if saveService ~= nil then saveService:save() end
end
