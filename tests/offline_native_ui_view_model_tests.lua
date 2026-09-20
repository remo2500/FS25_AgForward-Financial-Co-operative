-- Offline native UI view-model validation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/ledger/FinancialTaxonomy.lua")
dofile("src/ui/NativeUIViewModelService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local vm = AGFNativeUIViewModelService.build({
    farmId = 1,
    currentBalance = 125000,
    overview = {
        cashBalance = 125000,
        representedEquity = 1200000,
        representedLiabilities = 450000,
        dataQuality = "COMPLETE_NATIVE_VIEW"
    },
    creditProfile = {
        workingCapital = 210000,
        dscr = 1.42,
        fixedChargeCoverage = 1.31,
        debtToAssets = 0.272
    },
    liabilities = {
        {
            id = "AGF-LIAB-LOC",
            productType = AGFProductType.OPERATING_LINE,
            principalBalance = 40000,
            creditLimit = 150000,
            interestRate = 0.071,
            accruedInterest = 250,
            accruedFees = 0,
            status = "active"
        },
        {
            id = "AGF-LIAB-CILOC",
            productType = AGFProductType.CROP_INPUT_LINE,
            principalBalance = 126400,
            creditLimit = 300000,
            interestRate = 0.0725,
            accruedInterest = 900,
            accruedFees = 0,
            status = "active"
        },
        {
            id = "AGF-LIAB-EQ",
            productType = AGFProductType.EQUIPMENT_FINANCE,
            principalBalance = 200000,
            status = "active"
        }
    },
    obligations = {
        {id = "O2", dueYear = 2026, duePeriod = 11, obligationType = "land payment", amountDue = 9000, status = "scheduled"},
        {id = "O1", dueYear = 2026, duePeriod = 10, obligationType = "equipment payment", amountDue = 18000, status = "scheduled"}
    },
    assets = {
        {id = "ASSET-EQ", assetType = "vehicle", displayName = "X9 Combine", currentValue = 420000, linkState = "resolved"},
        {id = "ASSET-LAND", assetType = "farmland", displayName = "North Quarter", currentValue = 350000, linkState = "resolved"},
        {id = "ASSET-LEASE", assetType = "farmland", displayName = "West Quarter", currentValue = 300000, linkState = "resolved"}
    },
    liensByAsset = {
        ["ASSET-EQ"] = {{id = "LIEN-1"}}
    },
    leases = {
        {
            id = "LEASE-1",
            assetId = "ASSET-LEASE",
            displayName = "West Quarter lease",
            periodicRent = 7500,
            nextPaymentYear = 2026,
            nextPaymentPeriod = 12,
            remainingPeriods = 8,
            status = "active"
        }
    },
    servicingReviews = {
        {
            liabilityId = "AGF-LIAB-EQ",
            status = "review",
            requiresReview = true,
            highestSeverity = 1,
            nextPayment = {dueYear = 2026, duePeriod = 10, amount = 18000},
            delinquency = {pastDueAmount = 0},
            reviewReasons = {{code = "PAYMENT_DUE_SOON"}}
        }
    },
    cilocReview = {
        effectiveLimit = 264000,
        reservedAmount = 10000,
        availableCapacity = 127600,
        utilization = 0.5166666667,
        season = {state = "activeSeason"},
        flags = {cleanupRequired = false},
        attentionItems = {}
    }
})

assertEqual(vm.currentBalance, 125000, "current balance")
assertEqual(vm.overview.cash, 125000, "overview cash")
assertEqual(vm.overview.equity, 1200000, "overview equity")
assertEqual(vm.overview.totalDebt, 450000, "overview debt")
assertEqual(vm.overview.workingCapital, 210000, "working capital")
assertEqual(vm.overview.dscr, 1.42, "dscr")
assertEqual(vm.overview.fixedChargeCoverage, 1.31, "fixed charge coverage")
assertEqual(vm.overview.debtToAssets, 0.272, "debt/assets")
assertEqual(vm.overview.dataQuality, "COMPLETE_NATIVE_VIEW", "data quality")

assertEqual(#vm.facilities, 2, "only revolving facilities shown in credit facility list")
assertEqual(vm.facilities[1].productType, AGFProductType.CROP_INPUT_LINE, "facilities sorted by product type")
assertEqual(vm.facilities[1].balance, 126400, "CILOC balance")
assertEqual(vm.facilities[1].effectiveLimit, 264000, "CILOC effective limit")
assertEqual(vm.facilities[1].reservedAmount, 10000, "CILOC reservations")
assertEqual(vm.facilities[1].available, 127600, "CILOC available")
assertEqual(vm.facilities[1].seasonState, "activeSeason", "CILOC season")
assertEqual(vm.facilities[1].productKey, "agf_ui_product_cropInputLine", "CILOC localized product key")
assertEqual(vm.facilities[2].productType, AGFProductType.OPERATING_LINE, "operating line second")
assertEqual(vm.facilities[2].available, 110000, "operating availability")

assertEqual(#vm.obligations, 2, "obligation count")
assertEqual(vm.obligations[1].id, "O1", "obligations sorted chronologically")
assertEqual(vm.obligations[1].amountDue, 18000, "obligation amount")

assertEqual(#vm.assetFinance, 1, "equipment/project finance row count")
assertEqual(vm.assetFinance[1].displayName, "X9 Combine", "asset finance display name")
assertEqual(vm.assetFinance[1].assetValue, 420000, "asset finance value")
assertEqual(vm.assetFinance[1].lienCount, 1, "asset finance lien count")

assertEqual(#vm.landLeases, 1, "lease row count without land-finance liability")
assertEqual(vm.landLeases[1].displayName, "West Quarter", "lease asset name")
assertEqual(vm.landLeases[1].arrangement, "lease", "lease arrangement")
assertEqual(vm.landLeases[1].amount, 7500, "lease periodic rent")
assertEqual(vm.landLeases[1].nextPayment, "2026 / P12", "lease next payment")

assertEqual(#vm.servicing, 3, "all open liabilities appear in servicing")
assertEqual(vm.servicing[1].liabilityId, "AGF-LIAB-EQ", "review row sorted first")
assertEqual(vm.servicing[1].reviewRequired, true, "servicing review flag")
assertEqual(vm.servicing[1].nextPaymentAmount, 18000, "servicing next payment")

assertEqual(#vm.reports, 6, "report menu row count")
assertEqual(vm.reports[1].id, "financialPosition", "financial position report first")
assertTrue(vm.runtime ~= nil, "runtime view model exists")

print("offline_native_ui_view_model_tests: PASS")
