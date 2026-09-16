-- AgForward Financial Cooperative
-- Economic lease registry. Gameplay access mechanics live behind future adapters.

AGFLeaseRegistry = {}
AGFLeaseRegistry_mt = Class(AGFLeaseRegistry)

local function isFiniteNumber(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

local function normalizePaymentsPerYear(value)
    local number = tonumber(value == nil and 12 or value)
    if number == nil or not isFiniteNumber(number) or number <= 0 or number ~= math.floor(number) then
        return nil
    end
    -- Lease due dates must land on whole FS financial periods.
    if 12 % number ~= 0 then return nil end
    return number
end

local function normalizePositiveInteger(value)
    local number = tonumber(value)
    if number == nil or not isFiniteNumber(number) or number <= 0 or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function normalizeNonNegativeMoney(value)
    local number = tonumber(value)
    if number == nil or not isFiniteNumber(number) then return nil end
    number = AGFCurrency.round(number)
    if number < 0 then return nil end
    return number
end

function AGFLeaseRegistry.new(idService, runtimeState, assetRegistry)
    local self = setmetatable({}, AGFLeaseRegistry_mt)
    self.idService = idService
    self.runtimeState = runtimeState
    self.assetRegistry = assetRegistry
    self.leases = {}
    self.order = {}
    self.byFarm = {}
    self.byAsset = {}
    return self
end

function AGFLeaseRegistry:checkMutationAllowed(internal)
    if internal then return true, nil end
    if self.runtimeState == nil then return true, nil end
    return self.runtimeState:canMutate()
end

function AGFLeaseRegistry:create(assetId, leaseType, lesseeFarmId, periodicRent, termPeriods, displayName, paymentsPerYear)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return nil, errorCode end
    if assetId == nil or leaseType == nil or lesseeFarmId == nil then
        return nil, "INVALID_LEASE_ARGUMENTS"
    end
    if self.assetRegistry ~= nil and self.assetRegistry:get(assetId) == nil then
        return nil, "UNKNOWN_ASSET"
    end
    if self:getActiveAssetLease(assetId) ~= nil then
        return nil, "ACTIVE_ASSET_LEASE_ALREADY_EXISTS"
    end

    local rent = normalizeNonNegativeMoney(periodicRent)
    if rent == nil then return nil, "INVALID_RENT" end

    local term = normalizePositiveInteger(termPeriods)
    if term == nil then return nil, "INVALID_LEASE_TERM" end

    local frequency = normalizePaymentsPerYear(paymentsPerYear)
    if frequency == nil then return nil, "INVALID_LEASE_PAYMENT_FREQUENCY" end

    local lease = AGFLease.new(self.idService:next("LEASE"), assetId, leaseType, lesseeFarmId)
    lease.displayName = displayName
    lease.periodicRent = rent
    lease.paymentsPerYear = frequency
    lease.termPeriods = term
    lease.remainingPeriods = term
    return lease, nil
end

function AGFLeaseRegistry:register(lease, internal)
    local allowed, errorCode = self:checkMutationAllowed(internal)
    if not allowed then return false, errorCode end
    if lease == nil or lease.id == nil or lease.assetId == nil or lease.leaseType == nil or lease.lesseeFarmId == nil then
        return false, "INVALID_LEASE"
    end
    if self.leases[lease.id] ~= nil then return false, "DUPLICATE_LEASE_ID" end
    if lease:isOpen() and self:getActiveAssetLease(lease.assetId) ~= nil then
        return false, "ACTIVE_ASSET_LEASE_ALREADY_EXISTS"
    end

    local rent = normalizeNonNegativeMoney(lease.periodicRent)
    if rent == nil then return false, "INVALID_RENT" end
    local term = normalizePositiveInteger(lease.termPeriods)
    if term == nil then return false, "INVALID_LEASE_TERM" end
    local remaining = normalizePositiveInteger(lease.remainingPeriods)
    if remaining == nil or remaining > term then return false, "INVALID_LEASE_REMAINING_TERM" end
    local frequency = normalizePaymentsPerYear(lease.paymentsPerYear)
    if frequency == nil then return false, "INVALID_LEASE_PAYMENT_FREQUENCY" end

    local stored = lease:clone()
    stored.periodicRent = rent
    stored.paymentsPerYear = frequency
    stored.termPeriods = term
    stored.remainingPeriods = remaining
    stored.accruedRent = AGFCurrency.round(stored.accruedRent or 0)
    stored.accruedFees = AGFCurrency.round(stored.accruedFees or 0)

    self.leases[stored.id] = stored
    table.insert(self.order, stored.id)
    self.byFarm[stored.lesseeFarmId] = self.byFarm[stored.lesseeFarmId] or {}
    table.insert(self.byFarm[stored.lesseeFarmId], stored.id)
    self.byAsset[stored.assetId] = self.byAsset[stored.assetId] or {}
    table.insert(self.byAsset[stored.assetId], stored.id)
    if self.idService ~= nil then self.idService:observeId(stored.id) end
    return true, self:get(stored.id)
end

function AGFLeaseRegistry:getInternal(id)
    return self.leases[id]
end

function AGFLeaseRegistry:get(id)
    local lease = self.leases[id]
    return lease ~= nil and lease:clone() or nil
end

function AGFLeaseRegistry:getFarmLeases(farmId, includeClosed)
    local result = {}
    for _, id in ipairs(self.byFarm[farmId] or {}) do
        local lease = self.leases[id]
        if lease ~= nil and (includeClosed or lease:isOpen()) then
            table.insert(result, lease:clone())
        end
    end
    return result
end

function AGFLeaseRegistry:getAssetLeases(assetId, includeClosed)
    local result = {}
    for _, id in ipairs(self.byAsset[assetId] or {}) do
        local lease = self.leases[id]
        if lease ~= nil and (includeClosed or lease:isOpen()) then
            table.insert(result, lease:clone())
        end
    end
    return result
end

function AGFLeaseRegistry:getActiveAssetLease(assetId)
    for _, id in ipairs(self.byAsset[assetId] or {}) do
        local lease = self.leases[id]
        if lease ~= nil and lease:isOpen() then return lease:clone() end
    end
    return nil
end

function AGFLeaseRegistry:activate(id, startYear, startPeriod)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local lease = self.leases[id]
    if lease == nil then return false, "UNKNOWN_LEASE" end
    if lease.status ~= AGFLeaseStatus.PENDING then return false, "LEASE_NOT_PENDING" end

    lease.status = AGFLeaseStatus.ACTIVE
    lease.startYear = startYear
    lease.startPeriod = startPeriod
    -- These legacy fields remain activation-period markers until the live lease
    -- scheduler is promoted. LeaseScheduleService is the pure due-date authority
    -- for non-monthly future contract planning.
    lease.nextPaymentYear = startYear
    lease.nextPaymentPeriod = startPeriod
    return true, lease:clone()
end

function AGFLeaseRegistry:accruePeriodicRent(id)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local lease = self.leases[id]
    if lease == nil then return false, "UNKNOWN_LEASE" end
    if lease.status ~= AGFLeaseStatus.ACTIVE and lease.status ~= AGFLeaseStatus.PAST_DUE then
        return false, "LEASE_NOT_ACCRUABLE"
    end
    lease.accruedRent = AGFCurrency.round((lease.accruedRent or 0) + (lease.periodicRent or 0))
    return true, lease:clone()
end

function AGFLeaseRegistry:applyRentPayment(id, amount)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local lease = self.leases[id]
    if lease == nil then return false, "UNKNOWN_LEASE" end

    local payment = math.abs(AGFCurrency.round(tonumber(amount) or 0))
    if payment <= 0 then return false, "INVALID_PAYMENT_AMOUNT" end

    local outstandingFees = math.max(0, AGFCurrency.round(lease.accruedFees or 0))
    local appliedFees = math.min(payment, outstandingFees)
    lease.accruedFees = AGFCurrency.round(outstandingFees - appliedFees)
    local remaining = AGFCurrency.round(payment - appliedFees)

    local outstandingRent = math.max(0, AGFCurrency.round(lease.accruedRent or 0))
    local appliedRent = math.min(remaining, outstandingRent)
    lease.accruedRent = AGFCurrency.round(outstandingRent - appliedRent)
    remaining = AGFCurrency.round(remaining - appliedRent)

    return true, {
        lease = lease:clone(),
        appliedFees = appliedFees,
        appliedRent = appliedRent,
        unappliedAmount = remaining
    }
end

function AGFLeaseRegistry:getAnnualFixedCharges(farmId)
    local total = 0
    for _, lease in ipairs(self:getFarmLeases(farmId, false)) do
        total = AGFCurrency.round(total + lease:getAnnualizedFixedCharge())
    end
    return total
end

function AGFLeaseRegistry:close(id, status, endYear, endPeriod)
    local allowed, errorCode = self:checkMutationAllowed(false)
    if not allowed then return false, errorCode end
    local lease = self.leases[id]
    if lease == nil then return false, "UNKNOWN_LEASE" end
    if not lease:isOpen() then return false, "LEASE_ALREADY_CLOSED" end

    lease.status = status or AGFLeaseStatus.COMPLETED
    lease.endYear = endYear
    lease.endPeriod = endPeriod
    lease.remainingPeriods = 0
    return true, lease:clone()
end
