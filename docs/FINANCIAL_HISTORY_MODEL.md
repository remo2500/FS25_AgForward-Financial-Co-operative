# AgForward Financial History Model

## Purpose

`AGFFinancialHistoryService` provides the native history foundation intended to replace the useful reporting role of Economic History without becoming a second accounting authority.

All period and annual rows are derived from the canonical AgForward ledger.

## Period history

For one farm and FS financial period the service derives:

- transaction count;
- cash inflows, outflows, and net movement;
- principal, interest, and fee components;
- totals by transaction type;
- totals by expense category;
- totals by funding source;
- cash/financed/unknown-source crop-input purchases;
- source-of-funds detail by input expense category;
- broad cash-movement classes: operating, financing, investing, government, and other.

The movement classes are reporting groupings, **not tax classifications**. Red Tape remains authoritative for taxation and government-policy consequences.

## Range and annual history

The service can build an inclusive period range and a complete financial year while retaining each underlying period row.

The range result aggregates:

- cash flow;
- debt-service components;
- input purchase funding;
- movement classes;
- transaction, expense, and funding-source totals.

## Accounting boundary

History never stores independent balances and never repairs or changes ledger entries.

Future persistent snapshots may cache expensive derived values for UI performance, but the canonical journal remains the authority and snapshots must be rebuildable from it.

## Future work

After runtime validation this model can support:

- in-game monthly/annual history screens;
- CSV export;
- year-over-year comparisons;
- lender review packages;
- Red Tape reconciliation reports;
- period-end balance-sheet snapshots once the asset/right/lien schema is promoted.
