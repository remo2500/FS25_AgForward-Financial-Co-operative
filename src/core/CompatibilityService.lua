-- AgForward Financial Cooperative
-- Detects known overlapping finance mods during development. Red Tape is an
-- intentional optional integration and therefore is not treated as a conflict.

AGFCompatibilityService = {}
AGFCompatibilityService_mt = Class(AGFCompatibilityService)

AGFCompatibilityService.KNOWN_OVERLAPS = {
    "FS25_BankCredit",
    "FS25_FinanceYourFleet",
    "FS25_AgriCreditSolutions",
    "FS25_FieldLeasing",
    "FS25_EconomicHistory",
    "FS25_TradeInMenu"
}

function AGFCompatibilityService.new(runtimeState)
    local self = setmetatable({}, AGFCompatibilityService_mt)
    self.runtimeState = runtimeState
    self.detectedOverlaps = {}
    return self
end

function AGFCompatibilityService:detect()
    self.detectedOverlaps = {}
    if g_modIsLoaded == nil then
        return self.detectedOverlaps
    end

    for _, modName in ipairs(AGFCompatibilityService.KNOWN_OVERLAPS) do
        if g_modIsLoaded[modName] == true then
            table.insert(self.detectedOverlaps, modName)
            if self.runtimeState ~= nil then
                self.runtimeState:addIssue(
                    "OVERLAPPING_FINANCE_MOD",
                    "Overlapping finance mod detected: " .. modName,
                    "warning"
                )
            end
            print("Warning: AgForward detected overlapping finance mod " .. modName .. ". Use a dedicated test save while AgForward is under development.")
        end
    end

    return self.detectedOverlaps
end

function AGFCompatibilityService:getDetectedOverlaps()
    local copy = {}
    for _, modName in ipairs(self.detectedOverlaps) do
        table.insert(copy, modName)
    end
    return copy
end
