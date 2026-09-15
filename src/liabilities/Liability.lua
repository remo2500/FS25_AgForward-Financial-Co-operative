-- AgForward Financial Cooperative
-- Canonical persistent liability record.

AGFLiability = {}
AGFLiability_mt = Class(AGFLiability)

AGFLiabilityStatus = {
    ACTIVE = "active",
    PAST_DUE = "pastDue",
    DELINQUENT = "delinquent",
    COLLECTIONS = "collections",
    CLOSED = "closed",
    CHARGED_OFF = "chargedOff"
}

local function setOptionalString(xmlFile, key, value)
    if value ~= nil and value ~= "" then
        setXMLString(xmlFile, key, tostring(value))
    end
end

function AGFLiability.new(id, farmId, productType)
    local self = setmetatable({}, AGFLiability_mt)
    self.id = id
    self.farmId = farmId
    self.productType = productType
    self.status = AGFLiabilityStatus.ACTIVE
    self.displayName = nil

    self.originalPrincipal = 0
    self.principalBalance = 0
    self.creditLimit = 0
    self.accruedInterest = 0
    self.accruedFees = 0
    self.interestRate = 0

    self.termMonths = 0
    self.remainingTermMonths = 0
    self.scheduledPayment = 0
    self.balloonAmount = 0

    self.startYear = nil
    self.startPeriod = nil
    self.nextPaymentYear = nil
    self.nextPaymentPeriod = nil

    self.assetId = nil
    self.metadata = {}
    return self
end

function AGFLiability:isOpen()
    return self.status ~= AGFLiabilityStatus.CLOSED and self.status ~= AGFLiabilityStatus.CHARGED_OFF
end

function AGFLiability:isRevolving()
    return self.productType == AGFProductType.OPERATING_LINE or self.productType == AGFProductType.CROP_INPUT_LINE
end

function AGFLiability:getOutstandingBalance()
    return (self.principalBalance or 0) + (self.accruedInterest or 0) + (self.accruedFees or 0)
end

function AGFLiability:getAvailableCredit()
    if not self:isRevolving() then
        return 0
    end
    return math.max(0, AGFCurrency.round((self.creditLimit or 0) - (self.principalBalance or 0)))
end

function AGFLiability:setMetadata(key, value)
    if key ~= nil then
        if value == nil then
            self.metadata[tostring(key)] = nil
        else
            self.metadata[tostring(key)] = tostring(value)
        end
    end
    return self
end

function AGFLiability:clone()
    local copy = AGFLiability.new(self.id, self.farmId, self.productType)
    copy.status = self.status
    copy.displayName = self.displayName
    copy.originalPrincipal = self.originalPrincipal
    copy.principalBalance = self.principalBalance
    copy.creditLimit = self.creditLimit
    copy.accruedInterest = self.accruedInterest
    copy.accruedFees = self.accruedFees
    copy.interestRate = self.interestRate
    copy.termMonths = self.termMonths
    copy.remainingTermMonths = self.remainingTermMonths
    copy.scheduledPayment = self.scheduledPayment
    copy.balloonAmount = self.balloonAmount
    copy.startYear = self.startYear
    copy.startPeriod = self.startPeriod
    copy.nextPaymentYear = self.nextPaymentYear
    copy.nextPaymentPeriod = self.nextPaymentPeriod
    copy.assetId = self.assetId
    copy.metadata = {}
    for key, value in pairs(self.metadata or {}) do
        copy.metadata[key] = value
    end
    return copy
end

function AGFLiability:saveToXMLFile(xmlFile, key)
    setXMLString(xmlFile, key .. "#id", tostring(self.id))
    setXMLInt(xmlFile, key .. "#farmId", tonumber(self.farmId) or 0)
    setXMLString(xmlFile, key .. "#productType", tostring(self.productType or AGFProductType.TERM_LOAN))
    setXMLString(xmlFile, key .. "#status", tostring(self.status or AGFLiabilityStatus.ACTIVE))

    setOptionalString(xmlFile, key .. "#displayName", self.displayName)
    setOptionalString(xmlFile, key .. "#assetId", self.assetId)

    setXMLFloat(xmlFile, key .. "#originalPrincipal", AGFCurrency.round(self.originalPrincipal or 0))
    setXMLFloat(xmlFile, key .. "#principalBalance", AGFCurrency.round(self.principalBalance or 0))
    setXMLFloat(xmlFile, key .. "#creditLimit", AGFCurrency.round(self.creditLimit or 0))
    setXMLFloat(xmlFile, key .. "#accruedInterest", AGFCurrency.round(self.accruedInterest or 0))
    setXMLFloat(xmlFile, key .. "#accruedFees", AGFCurrency.round(self.accruedFees or 0))
    setXMLFloat(xmlFile, key .. "#interestRate", tonumber(self.interestRate) or 0)
    setXMLInt(xmlFile, key .. "#termMonths", math.max(0, math.floor(tonumber(self.termMonths) or 0)))
    setXMLInt(xmlFile, key .. "#remainingTermMonths", math.max(0, math.floor(tonumber(self.remainingTermMonths) or 0)))
    setXMLFloat(xmlFile, key .. "#scheduledPayment", AGFCurrency.round(self.scheduledPayment or 0))
    setXMLFloat(xmlFile, key .. "#balloonAmount", AGFCurrency.round(self.balloonAmount or 0))

    if self.startYear ~= nil then setXMLInt(xmlFile, key .. "#startYear", tonumber(self.startYear) or 0) end
    if self.startPeriod ~= nil then setXMLInt(xmlFile, key .. "#startPeriod", tonumber(self.startPeriod) or 0) end
    if self.nextPaymentYear ~= nil then setXMLInt(xmlFile, key .. "#nextPaymentYear", tonumber(self.nextPaymentYear) or 0) end
    if self.nextPaymentPeriod ~= nil then setXMLInt(xmlFile, key .. "#nextPaymentPeriod", tonumber(self.nextPaymentPeriod) or 0) end

    local metadataKeys = {}
    for metadataKey, _ in pairs(self.metadata or {}) do
        table.insert(metadataKeys, metadataKey)
    end
    table.sort(metadataKeys)

    for index, metadataKey in ipairs(metadataKeys) do
        local metadataNode = string.format("%s.metadata.entry(%d)", key, index - 1)
        setXMLString(xmlFile, metadataNode .. "#key", metadataKey)
        setXMLString(xmlFile, metadataNode .. "#value", tostring(self.metadata[metadataKey]))
    end
end

function AGFLiability.loadFromXMLFile(xmlFile, key)
    if not hasXMLProperty(xmlFile, key .. "#id") then
        return nil
    end

    local liability = AGFLiability.new(
        getXMLString(xmlFile, key .. "#id"),
        getXMLInt(xmlFile, key .. "#farmId"),
        getXMLString(xmlFile, key .. "#productType") or AGFProductType.TERM_LOAN
    )

    liability.status = getXMLString(xmlFile, key .. "#status") or AGFLiabilityStatus.ACTIVE
    liability.displayName = getXMLString(xmlFile, key .. "#displayName")
    liability.assetId = getXMLString(xmlFile, key .. "#assetId")

    liability.originalPrincipal = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#originalPrincipal") or 0)
    liability.principalBalance = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#principalBalance") or 0)
    liability.creditLimit = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#creditLimit") or 0)
    liability.accruedInterest = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#accruedInterest") or 0)
    liability.accruedFees = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#accruedFees") or 0)
    liability.interestRate = getXMLFloat(xmlFile, key .. "#interestRate") or 0
    liability.termMonths = getXMLInt(xmlFile, key .. "#termMonths") or 0
    liability.remainingTermMonths = getXMLInt(xmlFile, key .. "#remainingTermMonths") or 0
    liability.scheduledPayment = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#scheduledPayment") or 0)
    liability.balloonAmount = AGFCurrency.round(getXMLFloat(xmlFile, key .. "#balloonAmount") or 0)

    liability.startYear = getXMLInt(xmlFile, key .. "#startYear")
    liability.startPeriod = getXMLInt(xmlFile, key .. "#startPeriod")
    liability.nextPaymentYear = getXMLInt(xmlFile, key .. "#nextPaymentYear")
    liability.nextPaymentPeriod = getXMLInt(xmlFile, key .. "#nextPaymentPeriod")

    local metadataIndex = 0
    while true do
        local metadataNode = string.format("%s.metadata.entry(%d)", key, metadataIndex)
        if not hasXMLProperty(xmlFile, metadataNode .. "#key") then
            break
        end

        local metadataKey = getXMLString(xmlFile, metadataNode .. "#key")
        local metadataValue = getXMLString(xmlFile, metadataNode .. "#value")
        if metadataKey ~= nil then
            liability.metadata[metadataKey] = metadataValue or ""
        end

        metadataIndex = metadataIndex + 1
    end

    return liability
end
