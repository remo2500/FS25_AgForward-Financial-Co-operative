AgForwardFinance = {}
AgForwardFinance.modDirectory = g_currentModDirectory
AgForwardFinance.modName = g_currentModName
AgForwardFinance.services = nil
AgForwardFinance.initialized = false

local AgForwardFinance_mt = Class(AgForwardFinance)

function AgForwardFinance.new()
    return setmetatable({}, AgForwardFinance_mt)
end

function AgForwardFinance:loadMap(mapName)
    if AgForwardFinance.initialized then return end

    local services = AGFServiceContainer.new()
    local runtimeState = AGFRuntimeStateService.new()
    local idService = AGFIdService.new()
    local ledger = AGFLedger.new(idService, runtimeState)
    local liabilities = AGFLiabilityRegistry.new(idService, runtimeState)
    local operations = AGFFinancialOperationCoordinator.new(ledger, liabilities, runtimeState)
    local accounting = AGFAccountingService.new(ledger, liabilities, operations, runtimeState)
    local classifier = AGFPurchaseClassificationService.new()
    local accumulator = AGFInputPurchaseAccumulator.new()
    local compatibility = AGFCompatibilityService.new(runtimeState)
    local redTapeAdapter = AGFRedTapeAdapter.new()
    local settlement = AGFSettlementCoordinator.new(services)
    local integrity = AGFIntegrityService.new(services)
    local saveService = AGFSaveService.new(services)

    services:register("runtimeState", runtimeState)
    services:register("idService", idService)
    services:register("ledger", ledger)
    services:register("liabilities", liabilities)
    services:register("operations", operations)
    services:register("accounting", accounting)
    services:register("purchaseClassifier", classifier)
    services:register("inputAccumulator", accumulator)
    services:register("compatibility", compatibility)
    services:register("redTape", redTapeAdapter)
    services:register("settlement", settlement)
    services:register("integrity", integrity)
    services:register("save", saveService)

    compatibility:detect()
    redTapeAdapter:detect()

    -- Expose services before save-hook installation so appended save callbacks
    -- can always resolve the active mission-scoped AgForward services.
    AgForwardFinance.services = services

    saveService:installSaveHook()
    saveService:load()

    AgForwardFinance.initialized = true

    if g_messageCenter ~= nil then
        g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    end

    print(string.format(
        "AgForward: initialized (state: %s, Red Tape: %s, liabilities: %d, ledger transactions: %d, save: %s)",
        tostring(runtimeState:getState()),
        tostring(redTapeAdapter:getStatus()),
        #liabilities:getAll(),
        ledger:getTransactionCount(),
        tostring(saveService.lastLoadStatus)
    ))
end

function AgForwardFinance:onPeriodChanged()
    if AgForwardFinance.services == nil then return end
    local settlement = AgForwardFinance.services:get("settlement")
    if settlement ~= nil then settlement:runPeriodSettlement() end
end

function AgForwardFinance:deleteMap()
    if g_messageCenter ~= nil then g_messageCenter:unsubscribeAll(self) end

    if AgForwardFinance.services ~= nil then
        local runtimeState = AgForwardFinance.services:get("runtimeState")
        if runtimeState ~= nil then runtimeState:setState(AGFRuntimeState.SHUTDOWN, "MISSION_UNLOAD") end
        AgForwardFinance.services:clear()
    end

    AgForwardFinance.services = nil
    AgForwardFinance.initialized = false
end

function AgForwardFinance:update(dt)
end

function AgForwardFinance:draw()
end

function AgForwardFinance.getService(name)
    if AgForwardFinance.services == nil then return nil end
    return AgForwardFinance.services:get(name)
end

local agForwardFinanceListener = AgForwardFinance.new()
addModEventListener(agForwardFinanceListener)
