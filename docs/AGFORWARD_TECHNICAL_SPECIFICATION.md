# AgForward Technical Specification

**Revision:** 0.1 repository baseline  
**Date:** 2026-09-15  
**Authority:** subordinate to `AGFORWARD_CURRENT_AUTHORITY.md`

## Objective

Build one native FS25 financial ecosystem that replaces the lending, asset-finance, leasing, and financial-history purposes of the audited reference mods while remaining an original implementation. Red Tape is optional and external.

## Core services

### Service container
A single mission-scoped registry provides stable access to AgForward services and prevents product modules from directly constructing duplicate financial engines.

### ID service
Generate persistent IDs for transactions, transaction groups, assets, liabilities, leases, credit applications, and snapshots. IDs must remain stable through save/load.

### Ledger
One authoritative journal records financial events. The ledger must preserve two separate dimensions:

1. **Economic purpose** — seed, fertilizer, fuel, interest, rent, asset purchase, etc.
2. **Funding source** — cash, operating line, Crop Input LOC, equipment loan, project loan, etc.

A financing draw never replaces the expense classification of the purchase it funds.

### Asset / rights registry
Target asset classes:
- vehicle/equipment;
- placeable/facility;
- farmland;
- future other secured assets.

Rights must distinguish:
- economic owner;
- operator;
- tenant/leaseholder;
- collateral owner/lienholder.

### Liability registry
Common liability model should support:
- product type;
- original principal/limit;
- outstanding principal;
- interest rate and rate type;
- term/maturity;
- scheduled payment;
- balloon;
- accrued interest/fees;
- collateral links;
- status/delinquency state;
- next payment period;
- payoff amount.

### Credit engine
Use whole-farm information rather than product-local debt. Initial metrics:
- DSCR;
- fixed-charge coverage;
- LTV;
- debt-to-assets;
- liquidity/working capital;
- revolver utilization;
- payment history;
- free vs encumbered collateral.

### Rate engine
Common pricing framework across products:
`base rate + product spread + borrower risk spread + optional term/structure adjustments`.

### Settlement coordinator
Only one AgForward component reacts to a period change for payments. It gathers due obligations, determines available liquidity, applies approved credit rules, settles deterministically, posts accounting components, and updates delinquency.

### Reporting
Reports are generated from ledger/registries, not maintained as competing balances.

## Transaction taxonomy

Minimum taxonomy target:
- LOAN_PROCEEDS;
- REVOLVER_DRAW;
- REVOLVER_REPAYMENT;
- PRINCIPAL_PAYMENT;
- INTEREST_PAYMENT;
- FINANCE_FEE;
- LATE_FEE;
- LEASE_RENT;
- ASSET_PURCHASE;
- ASSET_SALE;
- LIEN_PAYOFF;
- DOWN_PAYMENT;
- GRANT_RECEIPT;
- INPUT_PURCHASE_SEED;
- INPUT_PURCHASE_FERTILIZER;
- INPUT_PURCHASE_LIME;
- INPUT_PURCHASE_CROP_PROTECTION;
- INPUT_PURCHASE_FUEL.

## Crop Input LOC transaction pattern

Example: $25,000 seed purchase fully funded by CILOC.

Transaction group `AGF-GRP-xxxxxx` contains:

1. `REVOLVER_DRAW` / funding source `CROP_INPUT_LOC` / liability +25,000.
2. `INPUT_PURCHASE_SEED` / expense category `SEED` / cash outflow 25,000.

Result:
- seed expense = 25,000;
- CILOC debt = +25,000;
- financing draw is not income;
- reports can show both purpose and financing source.

## Save schema target

Native file: `agForwardFinance.xml`.

Top-level sections expected:
- schema/version metadata;
- settings and rate history;
- farm credit profiles;
- assets and rights;
- liabilities;
- leases;
- transactions;
- transaction groups/index metadata;
- period snapshots;
- integration metadata.

Unresolved asset links on load must be quarantined/retried rather than silently deleted or treated as satisfied debt.

## Multiplayer rules

- Server owns all authoritative mutation.
- Client sends requests, never final balances.
- Server validates farm permissions, product eligibility, values, and asset identity.
- Creation, payment, payoff, draw, repayment, lease, and recovery require synchronized events or authoritative state refresh.
- Join-in-progress clients receive current state.

## UI structure

Main AgForward menu pages:
- Overview;
- Banking & Credit;
- Asset Finance;
- Land & Leases;
- Payments & Obligations;
- Reports;
- Government (when Red Tape integration is supported);
- Settings.

Contextual actions:
- vehicle dealer → Finance with AgForward;
- construction → Finance Project;
- farmland map → Buy / Finance / Lease as applicable.

## Phase 0 source layout

```text
src/
  AgForwardFinance.lua
  core/
    ServiceContainer.lua
    IdService.lua
  ledger/
    Transaction.lua
    Ledger.lua
  settlement/
    SettlementCoordinator.lua
  integrations/
    RedTapeAdapter.lua
```

Later modules will be added only after core contracts are validated.
