# AgForward Native Save Schema v1

**File:** `agForwardFinance.xml`  
**Root:** `agForwardFinance`  
**Schema version:** `1`

This schema is the first persistent-state contract for AgForward. It is intentionally small: persistent IDs and the financial ledger are established before loans, assets, leases, or credit profiles are added.

## Root attributes

- `schemaVersion` — native AgForward save schema version.
- `savedPeriod` — FS25 period at the time of save when available.
- `savedYear` — FS25 year at the time of save when available.

## ID counters

`agForwardFinance.idCounters.counter(i)`

Each counter contains:

- `scope` — uppercase ID scope, e.g. `TX`, `GRP`, later `LIAB`, `ASSET`, `LEASE`.
- `value` — greatest issued integer in that scope.

IDs use the format:

`AGF-<SCOPE>-<6-digit sequence>`

Example: `AGF-TX-000042`.

When loading transactions, the ID service also observes saved IDs and advances counters if necessary. This protects older or partially populated save files from issuing duplicate IDs.

## Ledger

`agForwardFinance.ledger.transactions.transaction(i)`

Persisted transaction fields:

- `id`
- `farmId`
- `type`
- `amount`
- `principal`
- `interest`
- `fees`
- optional `groupId`
- optional `expenseCategory`
- optional `fundingSource`
- optional `assetId`
- optional `liabilityId`
- optional `description`
- optional `period`
- optional `year`
- optional metadata key/value entries

The ledger preserves posting order. Transaction IDs are unique. Duplicate transaction IDs found during load are rejected rather than silently overwritten.

## Accounting principle

Funding source and economic purpose are independent dimensions.

A Crop Input Line of Credit-funded fertilizer purchase will eventually use a shared `groupId` across at least two linked economic records:

1. credit draw / liability increase;
2. fertilizer purchase / fertilizer expense.

The draw is not income. The fertilizer remains fertilizer expense. Principal repayment is not expense; interest and fees are separately classified.

## Compatibility rules

- A missing AgForward file means a new/empty AgForward financial state, not an error.
- A save schema newer than the running mod produces a warning and a best-effort read; it must never silently be rewritten as an older schema without deliberate migration handling.
- Client instances do not load or write the file; server authority loads/saves and later phases will synchronize state to clients.
- New schema revisions must preserve an explicit migration path.
