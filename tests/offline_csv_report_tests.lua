-- Offline CSV report serialization validation.

function Class(classTable)
    return {__index = classTable}
end

dofile("src/core/Currency.lua")
dofile("src/reporting/CSVReportService.lua")

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "assertEqual", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if value ~= true then error(message or "expected true") end
end

local genericOk, generic = AGFCSVReportService.encodeRows({"name", "note"}, {
    {name = "Farm, One", note = "He said \"go\""},
    {name = "Plain", note = "Line1\nLine2"}
})
assertTrue(genericOk, "generic CSV encoding succeeds")
assertTrue(string.find(generic, "\"Farm, One\"") ~= nil, "comma field quoted")
assertTrue(string.find(generic, "\"He said \"\"go\"\"\"") ~= nil, "quotes doubled")
assertTrue(string.find(generic, "\"Line1\nLine2\"") ~= nil, "newline field quoted")

local history = {
    periods = {
        {
            year = 2026,
            period = 9,
            transactionCount = 3,
            cashFlow = {inflows = 30000, outflows = 35000, net = -5000},
            components = {principal = 0, interest = 0, fees = 0},
            inputPurchases = {total = 35000, cash = 5000, financed = 30000},
            byExpenseCategory = {fertilizer = -30000, seed = -5000},
            byFundingSource = {cash = -5000, cropInputLine = 0}
        },
        {
            year = 2026,
            period = 10,
            transactionCount = 1,
            cashFlow = {inflows = 0, outflows = 500, net = -500},
            components = {principal = 0, interest = 500, fees = 0},
            inputPurchases = {total = 0, cash = 0, financed = 0},
            byExpenseCategory = {interest = -500},
            byFundingSource = {cash = -500}
        }
    }
}

local ok, exports = AGFCSVReportService.buildHistory(history)
assertTrue(ok, "history CSV build succeeds")
assertEqual(exports.periodRowCount, 2, "period rows")
assertEqual(exports.expenseRowCount, 3, "expense rows")
assertEqual(exports.fundingRowCount, 3, "funding rows")
assertTrue(string.find(exports.periodSummaryCSV, "2026,9,3,30000.00,35000.00,-5000.00", 1, true) ~= nil, "period summary row")
assertTrue(string.find(exports.expenseCategoryCSV, "2026,9,fertilizer,-30000.00", 1, true) ~= nil, "expense category row")
assertTrue(string.find(exports.fundingSourceCSV, "2026,10,cash,-500.00", 1, true) ~= nil, "funding source row")

print("offline_csv_report_tests: PASS")
