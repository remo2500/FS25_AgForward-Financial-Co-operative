-- AgForward Financial Cooperative
-- Read-only debt summary derived from native and represented external obligations.

AGFDebtScheduleReportService = {}
AGFDebtScheduleReportService_mt = Class(AGFDebtScheduleReportService)

function AGFDebtScheduleReportService.new(liabilityRegistry, externalObligationRegistry)
    local self = setmetatable({}, AGFDebtScheduleReportService_mt)
    self.liabilityRegistry = liabilityRegistry
    self.externalObligationRegistry = externalObligationRegistry
    return self
end

function AGFDebtScheduleReportService:build(farmId)
    local report = {
        farmId = farmId,
        native = {},
        external = {},
        totals = {
            nativePrincipal = 0,
            nativeAccruedInterest = 0,
            nativeAccruedFees = 0,
            nativeOutstanding = 0,
            externalPrincipal = 0,
            externalAnnualDebtService = 0,
            externalAnnualFixedCharge = 0,
            representedDebt = 0
        },
        byProduct = {},
        dataQuality = {
            verifiedExternal = 0,
            partialExternal = 0,
            estimatedExternal = 0,
            unknownExternal = 0
        }
    }

    if self.liabilityRegistry ~= nil then
        for _, liability in ipairs(self.liabilityRegistry:getFarmLiabilities(farmId, false)) do
            local row = {
                id = liability.id,
                displayName = liability.displayName,
                productType = liability.productType,
                status = liability.status,
                principalBalance = AGFCurrency.round(liability.principalBalance or 0),
                accruedInterest = AGFCurrency.round(liability.accruedInterest or 0),
                accruedFees = AGFCurrency.round(liability.accruedFees or 0),
                outstandingBalance = AGFCurrency.round(liability:getOutstandingBalance()),
                creditLimit = AGFCurrency.round(liability.creditLimit or 0),
                availableCredit = AGFCurrency.round(liability:getAvailableCredit()),
                interestRate = liability.interestRate or 0,
                remainingTermMonths = liability.remainingTermMonths or 0,
                scheduledPayment = AGFCurrency.round(liability.scheduledPayment or 0),
                balloonAmount = AGFCurrency.round(liability.balloonAmount or 0),
                nextPaymentYear = liability.nextPaymentYear,
                nextPaymentPeriod = liability.nextPaymentPeriod,
                assetId = liability.assetId
            }
            table.insert(report.native, row)

            report.totals.nativePrincipal = AGFCurrency.round(report.totals.nativePrincipal + row.principalBalance)
            report.totals.nativeAccruedInterest = AGFCurrency.round(report.totals.nativeAccruedInterest + row.accruedInterest)
            report.totals.nativeAccruedFees = AGFCurrency.round(report.totals.nativeAccruedFees + row.accruedFees)
            report.totals.nativeOutstanding = AGFCurrency.round(report.totals.nativeOutstanding + row.outstandingBalance)

            local product = row.productType or "unknown"
            report.byProduct[product] = report.byProduct[product] or {
                count = 0,
                principal = 0,
                outstanding = 0,
                creditLimit = 0,
                availableCredit = 0
            }
            local bucket = report.byProduct[product]
            bucket.count = bucket.count + 1
            bucket.principal = AGFCurrency.round(bucket.principal + row.principalBalance)
            bucket.outstanding = AGFCurrency.round(bucket.outstanding + row.outstandingBalance)
            bucket.creditLimit = AGFCurrency.round(bucket.creditLimit + row.creditLimit)
            bucket.availableCredit = AGFCurrency.round(bucket.availableCredit + row.availableCredit)
        end
    end

    if self.externalObligationRegistry ~= nil then
        for _, obligation in ipairs(self.externalObligationRegistry:getFarmObligations(farmId, false)) do
            local row = {
                id = obligation.id,
                displayName = obligation.displayName,
                obligationType = obligation.obligationType,
                source = obligation.source,
                principalBalance = AGFCurrency.round(obligation.principalBalance or 0),
                annualDebtService = AGFCurrency.round(obligation.annualDebtService or 0),
                annualFixedCharge = AGFCurrency.round(obligation.annualFixedCharge or 0),
                dataQuality = obligation.dataQuality,
                modifiableByAgForward = obligation.modifiableByAgForward == true
            }
            table.insert(report.external, row)
            report.totals.externalPrincipal = AGFCurrency.round(report.totals.externalPrincipal + row.principalBalance)
            report.totals.externalAnnualDebtService = AGFCurrency.round(report.totals.externalAnnualDebtService + row.annualDebtService)
            report.totals.externalAnnualFixedCharge = AGFCurrency.round(report.totals.externalAnnualFixedCharge + row.annualFixedCharge)

            if row.dataQuality == AGFExternalObligationQuality.VERIFIED then
                report.dataQuality.verifiedExternal = report.dataQuality.verifiedExternal + 1
            elseif row.dataQuality == AGFExternalObligationQuality.PARTIAL then
                report.dataQuality.partialExternal = report.dataQuality.partialExternal + 1
            elseif row.dataQuality == AGFExternalObligationQuality.ESTIMATED then
                report.dataQuality.estimatedExternal = report.dataQuality.estimatedExternal + 1
            else
                report.dataQuality.unknownExternal = report.dataQuality.unknownExternal + 1
            end
        end
    end

    report.totals.representedDebt = AGFCurrency.round(report.totals.nativeOutstanding + report.totals.externalPrincipal)

    table.sort(report.native, function(left, right) return tostring(left.id) < tostring(right.id) end)
    table.sort(report.external, function(left, right) return tostring(left.id) < tostring(right.id) end)
    return report
end
