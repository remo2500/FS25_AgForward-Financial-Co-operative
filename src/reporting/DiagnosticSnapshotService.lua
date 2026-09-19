-- AgForward Financial Cooperative
-- Read-only diagnostic projection for the future Phase-0 finance/status screen.
-- It derives state from authoritative services and never stores financial truth.

AGFDiagnosticSnapshotService = {}
AGFDiagnosticSnapshotService_mt = Class(AGFDiagnosticSnapshotService)

function AGFDiagnosticSnapshotService.new(runtimeState, compatibilityService, redTapeAdapter, liabilityRegistry, ledger, settlementCoordinator)
    local self = setmetatable({}, AGFDiagnosticSnapshotService_mt)
    self.runtimeState = runtimeState
    self.compatibilityService = compatibilityService
    self.redTapeAdapter = redTapeAdapter
    self.liabilityRegistry = liabilityRegistry
    self.ledger = ledger
    self.settlementCoordinator = settlementCoordinator
    return self
end

local function copyIssues(issues)
    local result = {}
    for _, issue in ipairs(issues or {}) do
        table.insert(result, {
            code = issue.code,
            message = issue.message,
            severity = issue.severity
        })
    end
    return result
end

local function severityRank(severity)
    if severity == "error" then return 2 end
    if severity == "warning" then return 1 end
    return 0
end

local function liabilityOutstanding(liability)
    if liability == nil then return 0 end
    if liability.getOutstandingBalance ~= nil then
        return AGFCurrency.round(liability:getOutstandingBalance())
    end
    return AGFCurrency.round((liability.principalBalance or 0) + (liability.accruedInterest or 0) + (liability.accruedFees or 0))
end

function AGFDiagnosticSnapshotService:build(farmId, context)
    context = context or {}

    local state = self.runtimeState ~= nil and self.runtimeState:getState() or "UNAVAILABLE"
    local reason = self.runtimeState ~= nil and self.runtimeState.reason or nil
    local issues = self.runtimeState ~= nil and copyIssues(self.runtimeState:getIssues()) or {}
    local overlaps = self.compatibilityService ~= nil and self.compatibilityService:getDetectedOverlaps() or {}
    local redTapeStatus = self.redTapeAdapter ~= nil and self.redTapeAdapter:getStatus() or "UNAVAILABLE"

    local highestSeverity = 0
    for _, issue in ipairs(issues) do highestSeverity = math.max(highestSeverity, severityRank(issue.severity)) end
    if #overlaps > 0 then highestSeverity = math.max(highestSeverity, 1) end
    if state == AGFRuntimeState.READ_ONLY_SAFE_MODE then highestSeverity = 2 end

    local liabilities = {}
    local totalOutstanding = 0
    if self.liabilityRegistry ~= nil and farmId ~= nil then
        for _, liability in ipairs(self.liabilityRegistry:getFarmLiabilities(farmId, true)) do
            local outstanding = liabilityOutstanding(liability)
            totalOutstanding = AGFCurrency.round(totalOutstanding + outstanding)
            table.insert(liabilities, {
                id = liability.id,
                productType = liability.productType,
                status = liability.status,
                principalBalance = AGFCurrency.round(liability.principalBalance or 0),
                accruedInterest = AGFCurrency.round(liability.accruedInterest or 0),
                accruedFees = AGFCurrency.round(liability.accruedFees or 0),
                outstandingBalance = outstanding
            })
        end
    end

    table.sort(liabilities, function(left, right) return tostring(left.id) < tostring(right.id) end)

    local recentTransactions = {}
    local transactionCount = 0
    if self.ledger ~= nil and farmId ~= nil then
        local transactions = self.ledger:getFarmTransactions(farmId)
        transactionCount = #transactions
        local limit = math.max(0, math.floor(tonumber(context.recentTransactionLimit) or 10))
        local first = math.max(1, #transactions - limit + 1)
        for index = #transactions, first, -1 do
            local tx = transactions[index]
            table.insert(recentTransactions, {
                id = tx.id,
                groupId = tx.groupId,
                transactionType = tx.transactionType,
                amount = tx.amount,
                liabilityId = tx.liabilityId,
                expenseCategory = tx.expenseCategory,
                year = tx.year,
                period = tx.period
            })
        end
    end

    local settlement = {
        engineVersion = AGFSettlementCoordinator ~= nil and AGFSettlementCoordinator.ENGINE_VERSION or nil,
        lastCompletedKey = self.settlementCoordinator ~= nil and self.settlementCoordinator.lastCompletedSettlementKey or nil,
        inProgressKey = self.settlementCoordinator ~= nil and self.settlementCoordinator.inProgressSettlementKey or nil
    }

    local health = "normal"
    if highestSeverity >= 2 then health = "error"
    elseif highestSeverity == 1 or redTapeStatus == AGFRedTapeAdapter.STATUS_DEGRADED then health = "warning" end

    return {
        farmId = farmId,
        buildVersion = context.buildVersion,
        schemaVersion = context.schemaVersion,
        saveGeneration = context.saveGeneration,
        runtimeState = state,
        runtimeReason = reason,
        health = health,
        issues = issues,
        overlappingFinanceMods = overlaps,
        redTapeStatus = redTapeStatus,
        liabilityCount = #liabilities,
        totalOutstanding = totalOutstanding,
        liabilities = liabilities,
        transactionCount = transactionCount,
        recentTransactions = recentTransactions,
        settlement = settlement,
        serverAuthority = context.serverAuthority,
        persistenceSource = context.persistenceSource,
        writable = state == AGFRuntimeState.NEW_STATE or state == AGFRuntimeState.NORMAL or state == AGFRuntimeState.RECOVERED
    }
end
