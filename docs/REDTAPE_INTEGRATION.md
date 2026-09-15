# AgForward ↔ Red Tape Integration Boundary

## Status

Red Tape is an **optional external authority**. AgForward must fully function when Red Tape is absent.

## Authority split

### AgForward owns
- loan and lease liabilities;
- collateral and liens;
- amortization/payoff;
- cash settlement;
- principal/interest/fee separation;
- financial transaction purpose;
- credit and lending decisions;
- financial reports.

### Red Tape owns
- tax calculation and payment;
- grants;
- government schemes;
- policy/regulatory systems;
- regulatory warnings/fines/consequences.

## Accounting contract

AgForward must preserve the economic meaning of each transaction.

| AgForward transaction | Red Tape-facing treatment |
|---|---|
| Loan proceeds / revolver draw | Financing source; not operating income |
| Principal repayment | Liability reduction; not deductible expense |
| Interest payment | Finance/interest expense |
| Financing/late fee | Separately classified fee; treatment defined intentionally |
| Land lease rent | Rent/lease expense |
| Equipment/building/land purchase | Asset acquisition |
| Asset sale | Asset disposal proceeds |
| Grant receipt | External grant/program funding |

## Crop Input Line of Credit

A financed input purchase must not lose its purchase category.

Example:

- CILOC draw: $20,000 → financing/liability event.
- Fertilizer purchase: $20,000 → fertilizer/input expense event.

Both entries share a transaction-group ID but have independent classifications.

## Adapter rule

Red Tape-specific logic must live under `src/integrations/redTape/` (or equivalent) and communicate with AgForward through stable internal services/events. Core lending classes must not directly depend on Red Tape globals.

## Double-count prevention

Before enabling a production bridge, validate whether Red Tape independently observes the same underlying Farming Simulator money movement. The adapter must not post a second tax line for an event Red Tape already records correctly.

The preferred integration strategy is:

1. preserve correct native FS MoneyType/FinanceStats where possible;
2. expose supplemental classification only where Red Tape cannot determine the event correctly;
3. use explicit adapter guards/version checks;
4. validate each transaction type with ledger-to-tax reconciliation tests.

## Compatibility states

- `NOT_INSTALLED` — no Red Tape globals found; AgForward continues normally.
- `SUPPORTED` — compatible Red Tape version/capabilities detected.
- `DEGRADED` — Red Tape present but adapter cannot safely provide some enhanced classifications.
- `DISABLED` — user/admin disables integration.

No unsupported adapter state may prevent the AgForward save from loading.
