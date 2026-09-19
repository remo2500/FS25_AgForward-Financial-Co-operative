-- AgForward Financial Cooperative
-- Pure seasonal Crop Input Line of Credit cycle assessment. This service does
-- not draw/repay credit or move FS25 money; it provides state for future
-- authorization, settlement, and renewal workflows.

AGFCILOCSeasonState = {
    ACTIVE_SEASON = "activeSeason",
    CLEANUP_WINDOW = "cleanupWindow",
    MATURED = "matured"
}

AGFCILOCSeasonService = {}

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function money(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

local function positiveInteger(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number <= 0 or number ~= math.floor(number) then return nil end
    return number
end

local function nonNegativeInteger(value)
    local number = tonumber(value or 0)
    if number == nil or not isFinite(number) or number < 0 or number ~= math.floor(number) then return nil end
    return number
end

local function ordinal(year, period)
    local y = positiveInteger(year)
    local p = positiveInteger(period)
    if y == nil or p == nil or p > 12 then return nil end
    return y * 12 + (p - 1)
end

function AGFCILOCSeasonService.assess(parameters)
    parameters = parameters or {}

    local creditLimit = money(parameters.creditLimit)
    local principal = money(parameters.principalBalance)
    local reserved = money(parameters.reservedAmount or 0)
    local cleanupTarget = money(parameters.cleanupTargetBalance or 0)
    if creditLimit == nil or creditLimit <= 0 then return false, "INVALID_CREDIT_LIMIT" end
    if principal == nil then return false, "INVALID_PRINCIPAL_BALANCE" end
    if reserved == nil then return false, "INVALID_RESERVED_AMOUNT" end
    if cleanupTarget == nil then return false, "INVALID_CLEANUP_TARGET" end

    local borrowingBase = nil
    if parameters.borrowingBase ~= nil then
        borrowingBase = money(parameters.borrowingBase)
        if borrowingBase == nil then return false, "INVALID_BORROWING_BASE" end
    end

    local currentOrdinal = ordinal(parameters.currentYear, parameters.currentPeriod)
    local maturityOrdinal = ordinal(parameters.maturityYear, parameters.maturityPeriod)
    if currentOrdinal == nil then return false, "INVALID_CURRENT_PERIOD" end
    if maturityOrdinal == nil then return false, "INVALID_MATURITY_PERIOD" end

    local startOrdinal = nil
    if parameters.startYear ~= nil or parameters.startPeriod ~= nil then
        startOrdinal = ordinal(parameters.startYear, parameters.startPeriod)
        if startOrdinal == nil then return false, "INVALID_START_PERIOD" end
        if maturityOrdinal <= startOrdinal then return false, "MATURITY_MUST_FOLLOW_START" end
        if currentOrdinal < startOrdinal then return false, "CURRENT_PERIOD_BEFORE_SEASON_START" end
    end

    local cleanupWindow = nonNegativeInteger(parameters.cleanupWindowPeriods or 0)
    if cleanupWindow == nil then return false, "INVALID_CLEANUP_WINDOW" end

    local effectiveLimit = creditLimit
    if borrowingBase ~= nil then effectiveLimit = math.min(effectiveLimit, borrowingBase) end
    effectiveLimit = AGFCurrency.round(effectiveLimit)

    local usedCapacity = AGFCurrency.round(principal + reserved)
    local baseAvailable = math.max(0, AGFCurrency.round(effectiveLimit - usedCapacity))

    local cleanupStart = maturityOrdinal - cleanupWindow
    local state
    if currentOrdinal >= maturityOrdinal then
        state = AGFCILOCSeasonState.MATURED
    elseif cleanupWindow > 0 and currentOrdinal >= cleanupStart then
        state = AGFCILOCSeasonState.CLEANUP_WINDOW
    else
        state = AGFCILOCSeasonState.ACTIVE_SEASON
    end

    local freezeDuringCleanup = parameters.freezeNewDrawsDuringCleanup == true
    local freezeAtMaturity = parameters.freezeNewDrawsAtMaturity ~= false
    local drawsFrozen = (state == AGFCILOCSeasonState.CLEANUP_WINDOW and freezeDuringCleanup)
        or (state == AGFCILOCSeasonState.MATURED and freezeAtMaturity)

    local availableCapacity = drawsFrozen and 0 or baseAvailable
    local requiredCleanupPaydown = math.max(0, AGFCurrency.round(principal - cleanupTarget))
    local cleanupSatisfied = AGFCurrency.toMinorUnits(principal) <= AGFCurrency.toMinorUnits(cleanupTarget)
    local periodsUntilMaturity = maturityOrdinal - currentOrdinal
    if periodsUntilMaturity < 0 then periodsUntilMaturity = 0 end

    local overEffectiveLimit = math.max(0, AGFCurrency.round(usedCapacity - effectiveLimit))

    return true, {
        state = state,
        currentYear = parameters.currentYear,
        currentPeriod = parameters.currentPeriod,
        maturityYear = parameters.maturityYear,
        maturityPeriod = parameters.maturityPeriod,
        periodsUntilMaturity = periodsUntilMaturity,
        cleanupWindowPeriods = cleanupWindow,
        cleanupWindowStarted = state ~= AGFCILOCSeasonState.ACTIVE_SEASON,
        creditLimit = creditLimit,
        borrowingBase = borrowingBase,
        effectiveLimit = effectiveLimit,
        principalBalance = principal,
        reservedAmount = reserved,
        usedCapacity = usedCapacity,
        overEffectiveLimit = overEffectiveLimit,
        baseAvailableCapacity = baseAvailable,
        drawsFrozen = drawsFrozen,
        availableCapacity = availableCapacity,
        cleanupTargetBalance = cleanupTarget,
        requiredCleanupPaydown = requiredCleanupPaydown,
        cleanupSatisfied = cleanupSatisfied,
        renewalRequired = state == AGFCILOCSeasonState.MATURED and not cleanupSatisfied,
        canAcceptNewDraw = state ~= AGFCILOCSeasonState.MATURED and not drawsFrozen and availableCapacity > 0
    }
end
