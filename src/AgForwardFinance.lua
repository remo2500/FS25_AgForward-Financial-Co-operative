AgForwardFinance = {}
AgForwardFinance.modDirectory = g_currentModDirectory
AgForwardFinance.modName = g_currentModName
AgForwardFinance.services = nil
AgForwardFinance.initialized = false

local AgForwardFinance_mt = Class(AgForwardFinance)

function AgForwardFinance.new()
    local self = setmetatable({}, AgForwardFinance_mt)
    return self
end

function AgForwardFinance:loadMap(mapName)
    if AgForwardFinance.initialized then
        return
    end

    local services = AGFServiceContainer.new()
    local idService = AGFIdService.new()
    local ledger = AGFLedger.new(idService)
    local redTapeAdapter = AGFRedTapeAdapter.new()
    local settlement = AGFSettlementCoordinator.new(services)
    local saveService = AGFSaveService.new(services)

    services:register("idService", idService)
    services:register("ledger", ledger)
    services:register("redTape", redTapeAdapter)
    services:register("settlement", settlement)
    services:register("save", saveService)

    redTapeAdapter:detect()
    saveService:installSaveHook()
    saveService:load()

    AgForwardFinance.services = services
    AgForwardFinance.initialized = true

    if g_messageCenter ~= nil then
        g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    end

    print(string.format(
        "AgForward: initialized (Red Tape: %s, ledger transactions: %d, save: %s)",
        tostring(redTapeAdapter:getStatus()),
        ledger:getTransactionCount(),
        tostring(saveService.lastLoadStatus)
    ))
end

function AgForwardFinance:onPeriodChanged()
    if AgForwardFinance.services == nil then
        return
    end

    local settlement = AgForwardFinance.services:get("settlement")
    if settlement ~= nil then
        settlement:runPeriodSettlement()
    end
end

function AgForwardFinance:deleteMap()
    if g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(self)
    end

    if AgForwardFinance.services ~= nil then
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
    if AgForwardFinance.services == nil then
        return nil
    end
    return AgForwardFinance.services:get(name)
end

local agForwardFinanceListener = AgForwardFinance.new()
addModEventListener(agForwardFinanceListener)
