# AgForward Reporting Architecture

**Status:** offline read-model baseline  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

AgForward reporting must be derived from authoritative registries and the ledger. Reports are projections, not competing stores of financial truth.

## 1. Authoritative sources

Reporting consumes:

- native ledger transactions;
- native liability registry;
- represented external obligations;
- asset/right/lien registry;
- lease registry;
- credit profile/history;
- period snapshots once implemented.

A report must not write back calculated balances into the core financial records.

## 2. Overview

`OverviewSnapshotService.lua` provides a read-only projection for a future dashboard:

- cash supplied by the FS/financial boundary;
- native debt;
- external represented debt;
- registered economically owned assets;
- represented equity;
- operating-line balance/availability;
- CILOC balance/availability;
- active liens;
- unresolved collateral count;
- recent ledger transactions;
- external data-quality indicators.

The snapshot explicitly reports data-quality limitations when the complete farm asset/debt position is not yet modeled.

## 3. Ledger reporting

`LedgerReportService.lua` derives:

- transaction counts;
- net transaction amounts;
- principal/interest/fee totals;
- activity by transaction type;
- activity by expense purpose;
- activity by funding source;
- cash-funded vs financed input purchases;
- source-of-funds breakdown for each input category;
- linked transaction-group reconciliation.

This directly supports the Crop Input Line requirement to answer both:

- "How much fertilizer did I buy?"
- "How much of that fertilizer was financed?"

## 4. Debt reporting

`DebtScheduleReportService.lua` separately presents:

- native AgForward liabilities;
- externally managed obligations;
- total represented debt;
- principal vs accrued interest vs fees;
- revolving limits/available credit;
- term/payment/balloon information;
- product aggregates;
- external-debt data quality.

Base-game/external debt therefore does not disappear simply because AgForward does not own its mutation authority.

## 5. Expense sign/display convention

The ledger stores economic outflows as negative amounts. Reports may present user-facing expense magnitude as positive values, but the underlying journal sign must remain unchanged.

Reporting code should make display transformation explicit rather than rewriting the original transaction.

## 6. Source-of-funds reporting

For operating inputs, expense purpose and funding source are independent dimensions.

Example report shape:

| Input purpose | Purchased | Cash | CILOC | Operating line |
|---|---:|---:|---:|---:|
| Seed | 45,000 | 10,000 | 35,000 | 0 |
| Fertilizer | 90,000 | 15,000 | 75,000 | 0 |
| Fuel | 30,000 | 5,000 | 10,000 | 15,000 |

The totals must reconcile to ledger transaction groups rather than being separately maintained counters.

## 7. Balance sheet direction

Future balance-sheet reporting should group:

### Assets

- cash/liquid assets;
- equipment/vehicles economically owned;
- facilities/placeables economically owned;
- farmland economically owned;
- other modeled current assets.

### Liabilities

- AgForward native principal/accruals;
- represented base-game/external obligations;
- accrued lease/fixed-charge liabilities where appropriate;
- other modeled liabilities.

### Equity

`represented assets - represented liabilities`

Leased assets/land are excluded from owned assets unless an actual economic ownership interest exists.

## 8. Cash-flow direction

Cash-flow reporting should distinguish:

- operating inflows/outflows;
- financing draws/proceeds;
- principal repayments;
- interest/fees;
- asset acquisition/disposal;
- lease payments;
- grant/government flows.

Loan proceeds should not inflate operating income; principal repayment should not inflate operating expense.

## 9. Period snapshots

A later snapshot service may persist period-end summaries for efficient multi-year reporting. Snapshots are caches of derived state, not independent authority.

Every persisted snapshot should include:

- source save/schema version;
- year/period;
- source state revision;
- enough provenance to invalidate/rebuild when incompatible.

The native ledger and registries remain recoverable truth.

## 10. Export

CSV/export can be added after the internal reporting contracts stabilize. Export should include stable IDs/group IDs where useful so advanced users can reconcile detailed transactions externally.

## 11. Offline implementation files

- `src/reporting/OverviewSnapshotService.lua`
- `src/reporting/LedgerReportService.lua`
- `src/reporting/DebtScheduleReportService.lua`
- `tests/offline_reporting_tests.lua`
