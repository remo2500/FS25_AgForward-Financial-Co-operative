-- AgForward Financial Cooperative
-- Pure CSV serializer for derived reports. No filesystem writes are performed.

AGFCSVReportService = {}

local function escape(value)
    if value == nil then return "" end
    local text = tostring(value)
    if string.find(text, "[,\"\r\n]") ~= nil then
        text = string.gsub(text, "\"", "\"\"")
        return "\"" .. text .. "\""
    end
    return text
end

local function line(values)
    local escaped = {}
    for index, value in ipairs(values) do escaped[index] = escape(value) end
    return table.concat(escaped, ",")
end

function AGFCSVReportService.encodeRows(headers, rows)
    if type(headers) ~= "table" or #headers == 0 then return false, "CSV_HEADERS_REQUIRED" end
    local output = {line(headers)}

    for _, row in ipairs(rows or {}) do
        local values = {}
        for index, header in ipairs(headers) do
            if type(row) == "table" then
                values[index] = row[header]
            else
                values[index] = nil
            end
        end
        table.insert(output, line(values))
    end

    return true, table.concat(output, "\r\n") .. "\r\n"
end

local function formatMoney(value)
    return string.format("%.2f", AGFCurrency.round(value or 0))
end

local function sortedKeys(map)
    local keys = {}
    for key, _ in pairs(map or {}) do table.insert(keys, key) end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    return keys
end

function AGFCSVReportService.buildHistory(historyRange)
    if historyRange == nil or type(historyRange.periods) ~= "table" then
        return false, "HISTORY_RANGE_REQUIRED"
    end

    local periodRows = {}
    local expenseRows = {}
    local fundingRows = {}

    for _, period in ipairs(historyRange.periods) do
        table.insert(periodRows, {
            year = period.year,
            period = period.period,
            transactionCount = period.transactionCount or 0,
            inflows = formatMoney(period.cashFlow and period.cashFlow.inflows or 0),
            outflows = formatMoney(period.cashFlow and period.cashFlow.outflows or 0),
            net = formatMoney(period.cashFlow and period.cashFlow.net or 0),
            principal = formatMoney(period.components and period.components.principal or 0),
            interest = formatMoney(period.components and period.components.interest or 0),
            fees = formatMoney(period.components and period.components.fees or 0),
            inputTotal = formatMoney(period.inputPurchases and period.inputPurchases.total or 0),
            inputCash = formatMoney(period.inputPurchases and period.inputPurchases.cash or 0),
            inputFinanced = formatMoney(period.inputPurchases and period.inputPurchases.financed or 0)
        })

        for _, category in ipairs(sortedKeys(period.byExpenseCategory)) do
            table.insert(expenseRows, {
                year = period.year,
                period = period.period,
                category = category,
                amount = formatMoney(period.byExpenseCategory[category] or 0)
            })
        end

        for _, fundingSource in ipairs(sortedKeys(period.byFundingSource)) do
            table.insert(fundingRows, {
                year = period.year,
                period = period.period,
                fundingSource = fundingSource,
                amount = formatMoney(period.byFundingSource[fundingSource] or 0)
            })
        end
    end

    local periodOk, periodCSV = AGFCSVReportService.encodeRows({
        "year", "period", "transactionCount", "inflows", "outflows", "net",
        "principal", "interest", "fees", "inputTotal", "inputCash", "inputFinanced"
    }, periodRows)
    if not periodOk then return false, periodCSV end

    local expenseOk, expenseCSV = AGFCSVReportService.encodeRows({
        "year", "period", "category", "amount"
    }, expenseRows)
    if not expenseOk then return false, expenseCSV end

    local fundingOk, fundingCSV = AGFCSVReportService.encodeRows({
        "year", "period", "fundingSource", "amount"
    }, fundingRows)
    if not fundingOk then return false, fundingCSV end

    return true, {
        periodSummaryCSV = periodCSV,
        expenseCategoryCSV = expenseCSV,
        fundingSourceCSV = fundingCSV,
        periodRowCount = #periodRows,
        expenseRowCount = #expenseRows,
        fundingRowCount = #fundingRows
    }
end
