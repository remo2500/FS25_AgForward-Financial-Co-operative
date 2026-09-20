-- AgForward Financial Cooperative
-- Pure view-model builder for the native-style in-game finance frame.
-- It owns no balances and performs no financial mutation.

AGFNativeUIViewModelService = {}

local PRODUCT_KEYS = {
    [AGFProductType.OPERATING_LINE] = "agf_ui_product_operatingLine",
    [AGFProductType.CROP_INPUT_LINE] = "agf_ui_product_cropInputLine",
    [AGFProductType.TERM_LOAN] = "agf_ui_product_termLoan",
    [AGFProductType.EQUIPMENT_FINANCE] = "agf_ui_product_equipmentFinance",
    [AGFProductType.PROJECT_FINANCE] = "agf_ui_product_projectFinance",
    [AGFProductType.LAND_FINANCE] = "agf_ui_product_landFinance",
    [AGFProductType.LAND_LEASE] = "agf_ui_product_landLease"
}

local REPORTS = {
    {id = "financialPosition", titleKey = "agf_ui_report_financialPosition", description = "Assets, liabilities, equity, liquidity and leverage."},
    {id = "debtSchedule", titleKey = "agf_ui_report_debtSchedule", description = "Principal, interest, fees, payments and maturities."},
    {id = "history", titleKey = "agf_ui_report_history", description = "Period and annual financial history from the AgForward ledger."},
    {id = "cropInputs", titleKey = "agf_ui_report_cropInputs", description = "Seed, fertilizer, crop protection, lime and fuel by funding source."},
    {id = "assetsLiens", titleKey = "agf_ui_report_assetsLiens", description = "Economically owned assets, collateral values and active liens."},
    {id = "leases", titleKey = "agf_ui_report_leases", description = "Lease commitments, rent schedule and fixed-charge exposure."}
}

local function money(value)
    return AGFCurrency.round(tonumber(value) or 0)
end

local function ratio(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

local function productKey(productType)
    return PRODUCT_KEYS[productType] or "agf_ui_product_termLoan"
end

local function copyReports()
    local rows = {}
    for _, report in ipairs(REPORTS) do
        local row = {}
        for key, value in pairs(report) do row[key] = value end
        table.insert(rows, row)
    end
    return rows
end

local function assetMap(rows)
    local map = {}
    for _, asset in ipairs(rows or {}) do
        if asset.id ~= nil then map[tostring(asset.id)] = asset end
    end
    return map
end

local function reviewMap(rows)
    local map = {}
    for _, review in ipairs(rows or {}) do
        if review.liabilityId ~= nil then map[tostring(review.liabilityId)] = review end
    end
    return map
end

local function dateLabel(year, period)
    if year == nil or period == nil then return nil end
    return string.format("%s / P%s", tostring(year), tostring(period))
end

function AGFNativeUIViewModelService.build(context)
    context = context or {}
    local overview = context.overview or {}
    local credit = context.creditProfile or {}
    local diagnostic = context.diagnostic or {}
    local liabilities = context.liabilities or diagnostic.liabilities or {}
    local obligations = context.obligations or {}
    local assetsById = assetMap(context.assets)
    local servicingByLiabilityId = reviewMap(context.servicingReviews)

    local facilities = {}
    for _, liability in ipairs(liabilities) do
        local isRevolving = liability.productType == AGFProductType.OPERATING_LINE
            or liability.productType == AGFProductType.CROP_INPUT_LINE
        if isRevolving then
            local balance = money(liability.principalBalance)
            local limit = money(liability.creditLimit)
            if limit <= 0 and liability.productType == AGFProductType.OPERATING_LINE then
                limit = money(context.operatingLineLimit)
            elseif limit <= 0 and liability.productType == AGFProductType.CROP_INPUT_LINE then
                limit = money(context.cropInputLineLimit)
            end

            local review = nil
            if context.facilityReviews ~= nil then review = context.facilityReviews[tostring(liability.id)] end
            if review == nil and liability.productType == AGFProductType.CROP_INPUT_LINE then
                review = context.cilocReview
            end

            local effectiveLimit = review ~= nil and money(review.effectiveLimit) or limit
            local reserved = review ~= nil and money(review.reservedAmount) or 0
            local available = review ~= nil and money(review.availableCapacity)
                or math.max(0, money(limit - balance - reserved))

            table.insert(facilities, {
                id = liability.id,
                productType = liability.productType,
                productKey = productKey(liability.productType),
                balance = balance,
                limit = limit,
                effectiveLimit = effectiveLimit,
                reservedAmount = reserved,
                available = available,
                interestRate = tonumber(liability.interestRate) or 0,
                utilization = review ~= nil and ratio(review.utilization)
                    or (effectiveLimit > 0 and (balance + reserved) / effectiveLimit or nil),
                borrowingBase = review ~= nil and review.borrowingBase or nil,
                seasonState = review ~= nil and review.season ~= nil and review.season.state or nil,
                cleanupRequired = review ~= nil and review.flags ~= nil and review.flags.cleanupRequired == true or false,
                attentionCount = review ~= nil and #(review.attentionItems or {}) or 0,
                status = liability.status or "active",
                outstanding = money(
                    (liability.principalBalance or 0)
                    + (liability.accruedInterest or 0)
                    + (liability.accruedFees or 0)
                )
            })
        end
    end

    table.sort(facilities, function(left, right)
        if left.productType == right.productType then return tostring(left.id) < tostring(right.id) end
        return tostring(left.productType) < tostring(right.productType)
    end)

    local normalizedObligations = {}
    for _, obligation in ipairs(obligations) do
        table.insert(normalizedObligations, {
            id = obligation.id,
            dueYear = obligation.dueYear,
            duePeriod = obligation.duePeriod,
            label = obligation.label or obligation.obligationType or obligation.productType or "obligation",
            amountDue = money(obligation.amountDue),
            status = obligation.status or "scheduled",
            sourceType = obligation.sourceType
        })
    end

    table.sort(normalizedObligations, function(left, right)
        local ly = tonumber(left.dueYear) or 0
        local ry = tonumber(right.dueYear) or 0
        if ly ~= ry then return ly < ry end
        local lp = tonumber(left.duePeriod) or 0
        local rp = tonumber(right.duePeriod) or 0
        if lp ~= rp then return lp < rp end
        return tostring(left.id) < tostring(right.id)
    end)

    local assetFinance = {}
    for _, liability in ipairs(liabilities) do
        if liability.productType == AGFProductType.EQUIPMENT_FINANCE
            or liability.productType == AGFProductType.PROJECT_FINANCE then
            local asset = liability.assetId ~= nil and assetsById[tostring(liability.assetId)] or nil
            local liens = context.liensByAsset ~= nil and context.liensByAsset[tostring(liability.assetId)] or {}
            table.insert(assetFinance, {
                liabilityId = liability.id,
                assetId = liability.assetId,
                displayName = asset ~= nil and (asset.displayName or asset.stableKey) or liability.displayName or tostring(liability.assetId or liability.id),
                assetType = asset ~= nil and asset.assetType or "unknown",
                productType = liability.productType,
                productKey = productKey(liability.productType),
                outstanding = money(
                    (liability.principalBalance or 0)
                    + (liability.accruedInterest or 0)
                    + (liability.accruedFees or 0)
                ),
                scheduledPayment = money(liability.scheduledPayment),
                interestRate = tonumber(liability.interestRate) or 0,
                status = liability.status or "active",
                assetValue = asset ~= nil and money(asset.currentValue) or 0,
                linkState = asset ~= nil and asset.linkState or "unknown",
                lienCount = #liens
            })
        end
    end
    table.sort(assetFinance, function(left, right)
        return tostring(left.displayName) < tostring(right.displayName)
    end)

    local landLeaseRows = {}
    for _, liability in ipairs(liabilities) do
        if liability.productType == AGFProductType.LAND_FINANCE then
            local asset = liability.assetId ~= nil and assetsById[tostring(liability.assetId)] or nil
            table.insert(landLeaseRows, {
                id = liability.id,
                arrangement = "finance",
                arrangementKey = "agf_ui_arrangement_finance",
                assetId = liability.assetId,
                displayName = asset ~= nil and (asset.displayName or asset.stableKey) or liability.displayName or tostring(liability.assetId or liability.id),
                amount = money(
                    (liability.principalBalance or 0)
                    + (liability.accruedInterest or 0)
                    + (liability.accruedFees or 0)
                ),
                nextPayment = dateLabel(liability.nextPaymentYear, liability.nextPaymentPeriod),
                remaining = tonumber(liability.remainingTermMonths) or 0,
                status = liability.status or "active",
                ownershipKey = "agf_ui_ownership_owned"
            })
        end
    end
    for _, lease in ipairs(context.leases or {}) do
        local asset = lease.assetId ~= nil and assetsById[tostring(lease.assetId)] or nil
        table.insert(landLeaseRows, {
            id = lease.id,
            arrangement = "lease",
            arrangementKey = "agf_ui_arrangement_lease",
            assetId = lease.assetId,
            displayName = asset ~= nil and (asset.displayName or asset.stableKey) or lease.displayName or tostring(lease.assetId or lease.id),
            amount = money(lease.periodicRent),
            nextPayment = dateLabel(lease.nextPaymentYear, lease.nextPaymentPeriod),
            remaining = tonumber(lease.remainingPeriods) or 0,
            status = lease.status or "pending",
            ownershipKey = "agf_ui_ownership_leased"
        })
    end
    table.sort(landLeaseRows, function(left, right)
        if left.arrangement == right.arrangement then return tostring(left.displayName) < tostring(right.displayName) end
        return tostring(left.arrangement) < tostring(right.arrangement)
    end)

    local servicing = {}
    for _, liability in ipairs(liabilities) do
        local review = servicingByLiabilityId[tostring(liability.id)]
        if review ~= nil then
            local nextPaymentText = nil
            if review.nextPayment ~= nil then
                nextPaymentText = dateLabel(review.nextPayment.dueYear, review.nextPayment.duePeriod)
            end
            local pastDue = review.delinquency ~= nil and money(review.delinquency.pastDueAmount) or 0
            table.insert(servicing, {
                liabilityId = liability.id,
                accountName = liability.displayName or productKey(liability.productType),
                accountKey = liability.displayName == nil and productKey(liability.productType) or nil,
                status = review.status or liability.status or "current",
                nextPayment = nextPaymentText,
                nextPaymentAmount = review.nextPayment ~= nil and money(review.nextPayment.amount) or 0,
                pastDue = pastDue,
                reviewRequired = review.requiresReview == true,
                reviewCount = #(review.reviewReasons or {}),
                highestSeverity = tonumber(review.highestSeverity) or 0
            })
        elseif liability.status ~= "closed" then
            table.insert(servicing, {
                liabilityId = liability.id,
                accountName = liability.displayName or productKey(liability.productType),
                accountKey = liability.displayName == nil and productKey(liability.productType) or nil,
                status = liability.status or "active",
                nextPayment = dateLabel(liability.nextPaymentYear, liability.nextPaymentPeriod),
                nextPaymentAmount = money(liability.scheduledPayment),
                pastDue = 0,
                reviewRequired = false,
                reviewCount = 0,
                highestSeverity = 0
            })
        end
    end
    table.sort(servicing, function(left, right)
        if left.highestSeverity ~= right.highestSeverity then return left.highestSeverity > right.highestSeverity end
        return tostring(left.accountName) < tostring(right.accountName)
    end)

    return {
        farmId = context.farmId or overview.farmId or diagnostic.farmId,
        currentBalance = money(context.currentBalance or overview.cashBalance),
        overview = {
            cash = money(overview.cashBalance),
            equity = money(overview.representedEquity),
            totalDebt = money(overview.representedLiabilities),
            workingCapital = money(credit.workingCapital),
            dscr = ratio(credit.dscr),
            fixedChargeCoverage = ratio(credit.fixedChargeCoverage),
            debtToAssets = ratio(credit.debtToAssets),
            dataQuality = overview.dataQuality or diagnostic.health or "unknown"
        },
        facilities = facilities,
        obligations = normalizedObligations,
        assetFinance = assetFinance,
        landLeases = landLeaseRows,
        servicing = servicing,
        reports = copyReports(),
        runtime = {
            state = diagnostic.runtimeState,
            health = diagnostic.health,
            writable = diagnostic.writable == true,
            redTapeStatus = diagnostic.redTapeStatus,
            persistenceSource = diagnostic.persistenceSource
        }
    }
end
