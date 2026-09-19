-- AgForward Financial Cooperative
-- Native FS25-style menu frame controller.
-- This file is intentionally NOT registered in modDesc.xml yet.

AGFNativeMenuFrame = {}
AGFNativeMenuFrame_mt = Class(AGFNativeMenuFrame, TabbedMenuFrameElement)

AGFNativeMenuFrame.CONTROLS = {
    "currentBalanceText",
    "subCategoryPaging",
    "subCategoryTabs",
    "subCategoryPages",
    "overviewCashValue",
    "overviewEquityValue",
    "overviewDebtValue",
    "overviewWorkingCapitalValue",
    "overviewDSCRValue",
    "overviewFCCRValue",
    "overviewDebtAssetsValue",
    "overviewDataQualityValue",
    "obligationList",
    "noObligationsText",
    "facilityList",
    "noFacilitiesText",
    "facilityDetailProduct",
    "facilityDetailBalance",
    "facilityDetailAvailable",
    "facilityDetailRate",
    "reportList"
}

local function setText(element, value)
    if element ~= nil then element:setText(tostring(value or "")) end
end

function AGFNativeMenuFrame.new(i18n, messageCenter)
    local self = TabbedMenuFrameElement.new(nil, AGFNativeMenuFrame_mt)
    self:registerControls(AGFNativeMenuFrame.CONTROLS)
    self.i18n = i18n
    self.messageCenter = messageCenter
    self.viewModel = nil
    self.currentSubPage = 1
    self.selectedFacilityIndex = 1
    return self
end

function AGFNativeMenuFrame:initialize()
    AGFNativeMenuFrame:superClass().initialize(self)

    if self.obligationList ~= nil then
        self.obligationList:setDataSource(self)
        self.obligationList:setDelegate(self)
    end
    if self.facilityList ~= nil then
        self.facilityList:setDataSource(self)
        self.facilityList:setDelegate(self)
    end
    if self.reportList ~= nil then
        self.reportList:setDataSource(self)
        self.reportList:setDelegate(self)
    end

    self:setSubPage(1)
end

function AGFNativeMenuFrame:setViewModel(viewModel)
    self.viewModel = viewModel
    self:refresh()
end

function AGFNativeMenuFrame:onFrameOpen()
    AGFNativeMenuFrame:superClass().onFrameOpen(self)
    self:refresh()
end

function AGFNativeMenuFrame:formatMoney(value)
    local amount = tonumber(value) or 0
    if self.i18n ~= nil and self.i18n.formatMoney ~= nil then
        return self.i18n:formatMoney(amount, 0, true, false)
    end
    return string.format("%.2f", amount)
end

function AGFNativeMenuFrame:formatRate(rate)
    local value = tonumber(rate)
    if value == nil then return "—" end
    if math.abs(value) <= 1 then value = value * 100 end
    return string.format("%.2f%%", value)
end

function AGFNativeMenuFrame:formatRatio(value)
    local number = tonumber(value)
    if number == nil then return "—" end
    return string.format("%.2fx", number)
end

function AGFNativeMenuFrame:formatPercent(value)
    local number = tonumber(value)
    if number == nil then return "—" end
    return string.format("%.1f%%", number * 100)
end

function AGFNativeMenuFrame:localize(key, fallback)
    if key ~= nil and self.i18n ~= nil and self.i18n.getText ~= nil then
        local text = self.i18n:getText(key)
        if text ~= nil and text ~= key then return text end
    end
    return fallback or key or ""
end

function AGFNativeMenuFrame:setSubPage(index)
    local pageIndex = math.max(1, math.min(8, math.floor(tonumber(index) or 1)))
    self.currentSubPage = pageIndex

    for i, page in ipairs(self.subCategoryPages or {}) do
        page:setVisible(i == pageIndex)
    end

    if self.subCategoryPaging ~= nil and self.subCategoryPaging.setState ~= nil then
        self.subCategoryPaging:setState(pageIndex, true)
    end
end

function AGFNativeMenuFrame:updateSubCategoryPages(state)
    self:setSubPage(state)
end

function AGFNativeMenuFrame:onClickOverview() self:setSubPage(1) end
function AGFNativeMenuFrame:onClickBanking() self:setSubPage(2) end
function AGFNativeMenuFrame:onClickAssetFinance() self:setSubPage(3) end
function AGFNativeMenuFrame:onClickLandLeases() self:setSubPage(4) end
function AGFNativeMenuFrame:onClickPayments() self:setSubPage(5) end
function AGFNativeMenuFrame:onClickReports() self:setSubPage(6) end
function AGFNativeMenuFrame:onClickGovernment() self:setSubPage(7) end
function AGFNativeMenuFrame:onClickSettings() self:setSubPage(8) end

function AGFNativeMenuFrame:refresh()
    local vm = self.viewModel
    if vm == nil then return end

    setText(self.currentBalanceText, self:formatMoney(vm.currentBalance))

    local overview = vm.overview or {}
    setText(self.overviewCashValue, self:formatMoney(overview.cash))
    setText(self.overviewEquityValue, self:formatMoney(overview.equity))
    setText(self.overviewDebtValue, self:formatMoney(overview.totalDebt))
    setText(self.overviewWorkingCapitalValue, self:formatMoney(overview.workingCapital))
    setText(self.overviewDSCRValue, self:formatRatio(overview.dscr))
    setText(self.overviewFCCRValue, self:formatRatio(overview.fixedChargeCoverage))
    setText(self.overviewDebtAssetsValue, self:formatPercent(overview.debtToAssets))
    setText(self.overviewDataQualityValue, overview.dataQuality or "—")

    local facilities = vm.facilities or {}
    local obligations = vm.obligations or {}

    if self.noFacilitiesText ~= nil then self.noFacilitiesText:setVisible(#facilities == 0) end
    if self.facilityList ~= nil then
        self.facilityList:setVisible(#facilities > 0)
        self.facilityList:reloadData()
    end

    if self.noObligationsText ~= nil then self.noObligationsText:setVisible(#obligations == 0) end
    if self.obligationList ~= nil then
        self.obligationList:setVisible(#obligations > 0)
        self.obligationList:reloadData()
    end

    if self.reportList ~= nil then self.reportList:reloadData() end

    if #facilities == 0 then
        self.selectedFacilityIndex = 0
    elseif self.selectedFacilityIndex < 1 or self.selectedFacilityIndex > #facilities then
        self.selectedFacilityIndex = 1
    end
    self:updateSelectedFacility()
end

function AGFNativeMenuFrame:getNumberOfItemsInSection(list, section)
    if self.viewModel == nil then return 0 end
    if list == self.facilityList then return #(self.viewModel.facilities or {}) end
    if list == self.obligationList then return #(self.viewModel.obligations or {}) end
    if list == self.reportList then return #(self.viewModel.reports or {}) end
    return 0
end

function AGFNativeMenuFrame:populateCellForItemInSection(list, section, index, cell)
    if self.viewModel == nil or cell == nil then return end

    if list == self.facilityList then
        local row = (self.viewModel.facilities or {})[index]
        if row == nil then return end
        setText(cell:getDescendantByName("productText"), self:localize(row.productKey, row.productType))
        setText(cell:getDescendantByName("balanceText"), self:formatMoney(row.balance))
        setText(cell:getDescendantByName("limitText"), self:formatMoney(row.limit))
        setText(cell:getDescendantByName("availableText"), self:formatMoney(row.available))
        setText(cell:getDescendantByName("rateText"), self:formatRate(row.interestRate))
        setText(cell:getDescendantByName("statusText"), tostring(row.status or ""))
        return
    end

    if list == self.obligationList then
        local row = (self.viewModel.obligations or {})[index]
        if row == nil then return end
        local due = "—"
        if row.dueYear ~= nil and row.duePeriod ~= nil then
            due = string.format("%s / P%s", tostring(row.dueYear), tostring(row.duePeriod))
        end
        setText(cell:getDescendantByName("dueText"), due)
        setText(cell:getDescendantByName("typeText"), row.label)
        setText(cell:getDescendantByName("amountText"), self:formatMoney(row.amountDue))
        setText(cell:getDescendantByName("statusText"), row.status)
        return
    end

    if list == self.reportList then
        local row = (self.viewModel.reports or {})[index]
        if row == nil then return end
        setText(cell:getDescendantByName("reportText"), self:localize(row.titleKey, row.id))
        setText(cell:getDescendantByName("descriptionText"), row.description)
    end
end

function AGFNativeMenuFrame:onListSelectionChanged(list, section, index)
    if list == self.facilityList then
        self.selectedFacilityIndex = index
        self:updateSelectedFacility()
    end
end

function AGFNativeMenuFrame:updateSelectedFacility()
    local facilities = self.viewModel ~= nil and self.viewModel.facilities or {}
    local row = facilities ~= nil and facilities[self.selectedFacilityIndex] or nil
    if row == nil then
        setText(self.facilityDetailProduct, "—")
        setText(self.facilityDetailBalance, "—")
        setText(self.facilityDetailAvailable, "—")
        setText(self.facilityDetailRate, "—")
        return
    end

    setText(self.facilityDetailProduct, self:localize(row.productKey, row.productType))
    setText(self.facilityDetailBalance, self:formatMoney(row.balance))
    setText(self.facilityDetailAvailable, self:formatMoney(row.available))
    setText(self.facilityDetailRate, self:formatRate(row.interestRate))
end
