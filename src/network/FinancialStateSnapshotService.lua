-- AgForward Financial Cooperative
-- Pure farm-scoped multiplayer snapshot/delta model. This creates plain tables
-- only; GIANTS Event serialization and transport remain runtime-gated.

AGFFinancialStateSnapshotService = {}
AGFFinancialStateSnapshotService_mt = Class(AGFFinancialStateSnapshotService)

local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function nonNegativeInteger(value)
    local number = tonumber(value)
    if number == nil or not isFinite(number) or number < 0 or number ~= math.floor(number) then return nil end
    return number
end

local function positiveInteger(value)
    local number = nonNegativeInteger(value)
    if number == nil or number < 1 then return nil end
    return number
end

local function copyMetadata(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function canonical(value)
    local valueType = type(value)
    if valueType == "nil" then return "n:" end
    if valueType == "boolean" then return value and "b:1" or "b:0" end
    if valueType == "number" then return "d:" .. string.format("%.17g", value) end
    if valueType == "string" then return "s:" .. tostring(#value) .. ":" .. value end
    if valueType ~= "table" then return "x:" .. valueType end

    local keys = {}
    for key, _ in pairs(value) do table.insert(keys, key) end
    table.sort(keys, function(left, right)
        local leftKey = type(left) .. ":" .. tostring(left)
        local rightKey = type(right) .. ":" .. tostring(right)
        return leftKey < rightKey
    end)

    local parts = {"t:{"}
    for _, key in ipairs(keys) do
        table.insert(parts, canonical(key))
        table.insert(parts, "=")
        table.insert(parts, canonical(value[key]))
        table.insert(parts, ";")
    end
    table.insert(parts, "}")
    return table.concat(parts)
end

local function sanitizeLiability(row)
    return {
        id = row.id,
        farmId = row.farmId,
        productType = row.productType,
        status = row.status,
        displayName = row.displayName,
        originalPrincipal = AGFCurrency.round(row.originalPrincipal or 0),
        principalBalance = AGFCurrency.round(row.principalBalance or 0),
        creditLimit = AGFCurrency.round(row.creditLimit or 0),
        accruedInterest = AGFCurrency.round(row.accruedInterest or 0),
        accruedFees = AGFCurrency.round(row.accruedFees or 0),
        interestRate = tonumber(row.interestRate) or 0,
        termMonths = row.termMonths,
        remainingTermMonths = row.remainingTermMonths,
        scheduledPayment = AGFCurrency.round(row.scheduledPayment or 0),
        balloonAmount = AGFCurrency.round(row.balloonAmount or 0),
        startYear = row.startYear,
        startPeriod = row.startPeriod,
        nextPaymentYear = row.nextPaymentYear,
        nextPaymentPeriod = row.nextPaymentPeriod,
        assetId = row.assetId,
        metadata = copyMetadata(row.metadata)
    }
end

local function sanitizeAsset(row)
    return {
        id = row.id,
        assetType = row.assetType,
        stableKey = row.stableKey,
        displayName = row.displayName,
        status = row.status,
        linkState = row.linkState,
        acquisitionCost = AGFCurrency.round(row.acquisitionCost or 0),
        currentValue = AGFCurrency.round(row.currentValue or 0),
        acquisitionYear = row.acquisitionYear,
        acquisitionPeriod = row.acquisitionPeriod,
        disposalYear = row.disposalYear,
        disposalPeriod = row.disposalPeriod,
        metadata = copyMetadata(row.metadata)
    }
end

local function sanitizeRight(row)
    return {
        id = row.id,
        assetId = row.assetId,
        rightType = row.rightType,
        holderType = row.holderType,
        holderId = row.holderId,
        status = row.status,
        startYear = row.startYear,
        startPeriod = row.startPeriod,
        endYear = row.endYear,
        endPeriod = row.endPeriod,
        metadata = copyMetadata(row.metadata)
    }
end

local function sanitizeLien(row)
    return {
        id = row.id,
        assetId = row.assetId,
        liabilityId = row.liabilityId,
        status = row.status,
        priority = row.priority,
        securedAmountCap = AGFCurrency.round(row.securedAmountCap or 0),
        startYear = row.startYear,
        startPeriod = row.startPeriod,
        releaseYear = row.releaseYear,
        releasePeriod = row.releasePeriod,
        metadata = copyMetadata(row.metadata)
    }
end

local function sanitizeLease(row)
    return {
        id = row.id,
        assetId = row.assetId,
        leaseType = row.leaseType,
        lesseeFarmId = row.lesseeFarmId,
        status = row.status,
        displayName = row.displayName,
        lessorType = row.lessorType,
        lessorId = row.lessorId,
        periodicRent = AGFCurrency.round(row.periodicRent or 0),
        paymentsPerYear = row.paymentsPerYear,
        termPeriods = row.termPeriods,
        remainingPeriods = row.remainingPeriods,
        nextPaymentYear = row.nextPaymentYear,
        nextPaymentPeriod = row.nextPaymentPeriod,
        accruedRent = AGFCurrency.round(row.accruedRent or 0),
        accruedFees = AGFCurrency.round(row.accruedFees or 0),
        autoRenew = row.autoRenew == true,
        metadata = copyMetadata(row.metadata)
    }
end

local function sanitizeExternal(row)
    return {
        id = row.id,
        farmId = row.farmId,
        obligationType = row.obligationType,
        source = row.source,
        displayName = row.displayName,
        principalBalance = AGFCurrency.round(row.principalBalance or 0),
        annualDebtService = AGFCurrency.round(row.annualDebtService or 0),
        annualFixedCharge = AGFCurrency.round(row.annualFixedCharge or 0),
        dataQuality = row.dataQuality,
        modifiableByAgForward = row.modifiableByAgForward == true,
        active = row.active ~= false,
        metadata = copyMetadata(row.metadata)
    }
end

local function sanitizeTransaction(row)
    return {
        id = row.id,
        groupId = row.groupId,
        farmId = row.farmId,
        transactionType = row.transactionType,
        amount = AGFCurrency.round(row.amount or 0),
        principal = AGFCurrency.round(row.principal or 0),
        interest = AGFCurrency.round(row.interest or 0),
        fees = AGFCurrency.round(row.fees or 0),
        expenseCategory = row.expenseCategory,
        fundingSource = row.fundingSource,
        assetId = row.assetId,
        liabilityId = row.liabilityId,
        year = row.year,
        period = row.period,
        description = row.description,
        metadata = copyMetadata(row.metadata)
    }
end

local function sortById(rows)
    table.sort(rows, function(left, right) return tostring(left.id) < tostring(right.id) end)
end

function AGFFinancialStateSnapshotService.new(liabilityRegistry, assetRegistry, rightRegistry, lienRegistry, leaseRegistry, externalObligationRegistry, ledger, protocolState)
    local self = setmetatable({}, AGFFinancialStateSnapshotService_mt)
    self.liabilityRegistry = liabilityRegistry
    self.assetRegistry = assetRegistry
    self.rightRegistry = rightRegistry
    self.lienRegistry = lienRegistry
    self.leaseRegistry = leaseRegistry
    self.externalObligationRegistry = externalObligationRegistry
    self.ledger = ledger
    self.protocolState = protocolState
    return self
end

function AGFFinancialStateSnapshotService:build(farmId, context)
    context = context or {}
    local normalizedFarmId = positiveInteger(farmId)
    if normalizedFarmId == nil then return false, "INVALID_FARM_ID" end

    local revision = context.revision
    if revision == nil and self.protocolState ~= nil and self.protocolState.getRevision ~= nil then
        revision = self.protocolState:getRevision()
    end
    revision = nonNegativeInteger(revision or 0)
    if revision == nil then return false, "INVALID_STATE_REVISION" end

    local relevantAssetIds = {}
    local snapshot = {
        farmId = normalizedFarmId,
        revision = revision,
        liabilities = {},
        assets = {},
        rights = {},
        liens = {},
        leases = {},
        externalObligations = {},
        transactions = {},
        ledgerWindow = {
            limit = math.max(0, math.floor(tonumber(context.ledgerLimit) or 50)),
            totalFarmTransactions = 0,
            truncated = false,
            firstIncludedTransactionId = nil,
            lastIncludedTransactionId = nil
        }
    }

    if self.liabilityRegistry ~= nil then
        for _, liability in ipairs(self.liabilityRegistry:getFarmLiabilities(normalizedFarmId, true)) do
            local clean = sanitizeLiability(liability)
            table.insert(snapshot.liabilities, clean)
            if clean.assetId ~= nil then relevantAssetIds[tostring(clean.assetId)] = true end
        end
    end

    if self.leaseRegistry ~= nil then
        for _, lease in ipairs(self.leaseRegistry:getFarmLeases(normalizedFarmId, true)) do
            local clean = sanitizeLease(lease)
            table.insert(snapshot.leases, clean)
            if clean.assetId ~= nil then relevantAssetIds[tostring(clean.assetId)] = true end
        end
    end

    if self.assetRegistry ~= nil and self.rightRegistry ~= nil then
        for _, asset in ipairs(self.assetRegistry:getAll()) do
            for _, right in ipairs(self.rightRegistry:getAssetRights(asset.id, false)) do
                if right.holderType == "farm" and tostring(right.holderId) == tostring(normalizedFarmId) then
                    relevantAssetIds[tostring(asset.id)] = true
                    break
                end
            end
        end
    end

    if self.assetRegistry ~= nil then
        for _, asset in ipairs(self.assetRegistry:getAll()) do
            if relevantAssetIds[tostring(asset.id)] then
                table.insert(snapshot.assets, sanitizeAsset(asset))

                if self.rightRegistry ~= nil then
                    for _, right in ipairs(self.rightRegistry:getAssetRights(asset.id, false)) do
                        table.insert(snapshot.rights, sanitizeRight(right))
                    end
                end
                if self.lienRegistry ~= nil then
                    for _, lien in ipairs(self.lienRegistry:getAssetLiens(asset.id, false)) do
                        table.insert(snapshot.liens, sanitizeLien(lien))
                    end
                end
            end
        end
    end

    if self.externalObligationRegistry ~= nil then
        for _, obligation in ipairs(self.externalObligationRegistry:getFarmObligations(normalizedFarmId, true)) do
            table.insert(snapshot.externalObligations, sanitizeExternal(obligation))
        end
    end

    if self.ledger ~= nil then
        local farmTransactions = self.ledger:getFarmTransactions(normalizedFarmId)
        snapshot.ledgerWindow.totalFarmTransactions = #farmTransactions
        local limit = snapshot.ledgerWindow.limit
        local firstIndex = limit > 0 and math.max(1, #farmTransactions - limit + 1) or (#farmTransactions + 1)
        snapshot.ledgerWindow.truncated = firstIndex > 1

        for index = firstIndex, #farmTransactions do
            table.insert(snapshot.transactions, sanitizeTransaction(farmTransactions[index]))
        end
        if #snapshot.transactions > 0 then
            snapshot.ledgerWindow.firstIncludedTransactionId = snapshot.transactions[1].id
            snapshot.ledgerWindow.lastIncludedTransactionId = snapshot.transactions[#snapshot.transactions].id
        end
    end

    sortById(snapshot.liabilities)
    sortById(snapshot.assets)
    sortById(snapshot.rights)
    sortById(snapshot.liens)
    sortById(snapshot.leases)
    sortById(snapshot.externalObligations)

    snapshot.counts = {
        liabilities = #snapshot.liabilities,
        assets = #snapshot.assets,
        rights = #snapshot.rights,
        liens = #snapshot.liens,
        leases = #snapshot.leases,
        externalObligations = #snapshot.externalObligations,
        transactions = #snapshot.transactions
    }

    return true, snapshot
end

local function indexRows(rows)
    local byId = {}
    for _, row in ipairs(rows or {}) do
        if row.id == nil then return nil, "SNAPSHOT_ROW_ID_REQUIRED" end
        local id = tostring(row.id)
        if byId[id] ~= nil then return nil, "DUPLICATE_SNAPSHOT_ROW_ID:" .. id end
        byId[id] = row
    end
    return byId, nil
end

local function diffCollection(previousRows, currentRows)
    local previousById, previousError = indexRows(previousRows)
    if previousById == nil then return nil, previousError end
    local currentById, currentError = indexRows(currentRows)
    if currentById == nil then return nil, currentError end

    local result = {additions = {}, updates = {}, removals = {}}
    for id, current in pairs(currentById) do
        local previous = previousById[id]
        if previous == nil then
            table.insert(result.additions, current)
        elseif canonical(previous) ~= canonical(current) then
            table.insert(result.updates, {id = current.id, before = previous, after = current})
        end
    end
    for id, previous in pairs(previousById) do
        if currentById[id] == nil then table.insert(result.removals, previous) end
    end

    sortById(result.additions)
    table.sort(result.updates, function(left, right) return tostring(left.id) < tostring(right.id) end)
    sortById(result.removals)
    result.changeCount = #result.additions + #result.updates + #result.removals
    return result, nil
end

local function diffLedger(previousRows, currentRows)
    local previousById, previousError = indexRows(previousRows)
    if previousById == nil then return nil, previousError end
    local currentById, currentError = indexRows(currentRows)
    if currentById == nil then return nil, currentError end

    local overlap = 0
    local additions = {}
    for id, current in pairs(currentById) do
        local previous = previousById[id]
        if previous ~= nil then
            overlap = overlap + 1
            if canonical(previous) ~= canonical(current) then
                return nil, "LEDGER_HISTORY_CHANGED:" .. id
            end
        else
            table.insert(additions, current)
        end
    end
    table.sort(additions, function(left, right)
        local leftYear = tonumber(left.year) or 0
        local rightYear = tonumber(right.year) or 0
        if leftYear ~= rightYear then return leftYear < rightYear end
        local leftPeriod = tonumber(left.period) or 0
        local rightPeriod = tonumber(right.period) or 0
        if leftPeriod ~= rightPeriod then return leftPeriod < rightPeriod end
        return tostring(left.id) < tostring(right.id)
    end)

    local requiresLedgerResync = #previousRows > 0 and #currentRows > 0 and overlap == 0
    return {
        additions = additions,
        overlapCount = overlap,
        requiresLedgerResync = requiresLedgerResync,
        continuity = requiresLedgerResync and "unknown" or "overlapVerified",
        changeCount = #additions
    }, nil
end

function AGFFinancialStateSnapshotService.diff(previousSnapshot, currentSnapshot)
    if previousSnapshot == nil or currentSnapshot == nil then return false, "SNAPSHOTS_REQUIRED" end
    if tostring(previousSnapshot.farmId) ~= tostring(currentSnapshot.farmId) then
        return false, "SNAPSHOT_FARM_MISMATCH"
    end

    local previousRevision = nonNegativeInteger(previousSnapshot.revision)
    local currentRevision = nonNegativeInteger(currentSnapshot.revision)
    if previousRevision == nil or currentRevision == nil then return false, "INVALID_STATE_REVISION" end
    if currentRevision < previousRevision then return false, "STATE_REVISION_REGRESSION" end

    local collections = {
        "liabilities",
        "assets",
        "rights",
        "liens",
        "leases",
        "externalObligations"
    }
    local delta = {
        farmId = currentSnapshot.farmId,
        fromRevision = previousRevision,
        toRevision = currentRevision,
        collections = {},
        totalEntityChanges = 0
    }

    for _, name in ipairs(collections) do
        local collectionDelta, errorCode = diffCollection(previousSnapshot[name], currentSnapshot[name])
        if collectionDelta == nil then return false, errorCode end
        delta.collections[name] = collectionDelta
        delta.totalEntityChanges = delta.totalEntityChanges + collectionDelta.changeCount
    end

    local ledgerDelta, ledgerError = diffLedger(previousSnapshot.transactions or {}, currentSnapshot.transactions or {})
    if ledgerDelta == nil then return false, ledgerError end
    delta.ledger = ledgerDelta

    local hasChanges = delta.totalEntityChanges > 0 or ledgerDelta.changeCount > 0
    if currentRevision == previousRevision and hasChanges then
        return false, "STATE_CHANGED_WITHOUT_REVISION"
    end

    delta.hasChanges = hasChanges
    delta.requiresFullSnapshot = ledgerDelta.requiresLedgerResync
    return true, delta
end
