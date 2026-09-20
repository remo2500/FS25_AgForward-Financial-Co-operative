-- AgForward Financial Cooperative
-- Whole-farm borrower profile. This is a derived underwriting view, not a debt ledger.

AGFCreditDataQuality = {
    COMPLETE = "complete",
    PARTIAL_EXTERNAL_DEBT = "partialExternalDebt",
    UNKNOWN_EXTERNAL_DEBT = "unknownExternalDebt",
    ASSET_LINK_UNRESOLVED = "assetLinkUnresolved",
    INSUFFICIENT_HISTORY = "insufficientHistory"
}

AGFFarmCreditProfile = {}
AGFFarmCreditProfile_mt = Class(AGFFarmCreditProfile)

function AGFFarmCreditProfile.new(farmId)
    local self = setmetatable({}, AGFFarmCreditProfile_mt)
    self.farmId = farmId
    self.asOfYear = nil
    self.asOfPeriod = nil
    self.metrics = nil
    self.dataQuality = AGFCreditDataQuality.COMPLETE
    self.dataQualityIssues = {}
    self.paymentHistory = {
        onTimeCount = 0,
        lateCount = 0,
        delinquencyCount = 0,
        collectionCount = 0
    }
    self.nativeLiabilityCount = 0
    self.externalObligationCount = 0
    self.activeLienCount = 0
    self.unresolvedAssetCount = 0
    self.metadata = {}
    return self
end

function AGFFarmCreditProfile:addQualityIssue(code, detail)
    table.insert(self.dataQualityIssues, {
        code = tostring(code),
        detail = detail ~= nil and tostring(detail) or nil
    })
    return self
end

function AGFFarmCreditProfile:setDataQuality(quality)
    self.dataQuality = quality or AGFCreditDataQuality.COMPLETE
    return self
end

function AGFFarmCreditProfile:setMetrics(metrics)
    self.metrics = metrics
    return self
end

function AGFFarmCreditProfile:setMetadata(key, value)
    if key ~= nil then
        if value == nil then
            self.metadata[tostring(key)] = nil
        else
            self.metadata[tostring(key)] = tostring(value)
        end
    end
    return self
end

function AGFFarmCreditProfile:clone()
    local copy = AGFFarmCreditProfile.new(self.farmId)
    copy.asOfYear = self.asOfYear
    copy.asOfPeriod = self.asOfPeriod
    copy.dataQuality = self.dataQuality
    copy.nativeLiabilityCount = self.nativeLiabilityCount
    copy.externalObligationCount = self.externalObligationCount
    copy.activeLienCount = self.activeLienCount
    copy.unresolvedAssetCount = self.unresolvedAssetCount
    copy.metrics = {}
    for key, value in pairs(self.metrics or {}) do copy.metrics[key] = value end
    copy.paymentHistory = {}
    for key, value in pairs(self.paymentHistory or {}) do copy.paymentHistory[key] = value end
    copy.dataQualityIssues = {}
    for _, issue in ipairs(self.dataQualityIssues or {}) do
        table.insert(copy.dataQualityIssues, {code = issue.code, detail = issue.detail})
    end
    copy.metadata = {}
    for key, value in pairs(self.metadata or {}) do copy.metadata[key] = value end
    return copy
end
