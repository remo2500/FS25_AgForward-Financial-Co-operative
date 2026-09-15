AGFRedTapeAdapter = {}
AGFRedTapeAdapter_mt = Class(AGFRedTapeAdapter)

AGFRedTapeAdapter.STATUS_NOT_INSTALLED = "NOT_INSTALLED"
AGFRedTapeAdapter.STATUS_SUPPORTED = "SUPPORTED"
AGFRedTapeAdapter.STATUS_DEGRADED = "DEGRADED"
AGFRedTapeAdapter.STATUS_DISABLED = "DISABLED"

function AGFRedTapeAdapter.new()
    local self = setmetatable({}, AGFRedTapeAdapter_mt)
    self.status = AGFRedTapeAdapter.STATUS_NOT_INSTALLED
    self.detected = false
    return self
end

function AGFRedTapeAdapter:detect()
    self.detected = g_modIsLoaded ~= nil and g_modIsLoaded["FS25_RedTape"] == true
    if self.detected then
        self.status = AGFRedTapeAdapter.STATUS_DEGRADED
    else
        self.status = AGFRedTapeAdapter.STATUS_NOT_INSTALLED
    end
    return self.status
end

function AGFRedTapeAdapter:getStatus()
    return self.status
end

function AGFRedTapeAdapter:isInstalled()
    return self.detected
end

-- Phase 0 deliberately does not inject tax line items. Production integration
-- must first verify what Red Tape already records through native money events so
-- AgForward never double-counts a transaction.
