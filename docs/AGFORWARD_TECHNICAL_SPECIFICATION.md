# AgForward Technical Specification

**Revision:** 0.2 hardening baseline  
**Date:** 2026-09-15  
**Authority:** subordinate to `AGFORWARD_CURRENT_AUTHORITY.md`

## Objective

Build one original FS25 financial ecosystem for operating credit, equipment, facilities, land, leasing, and financial reporting. Red Tape remains optional and external.

## Core service contracts

### Runtime state

`AGFRuntimeStateService` gates every consequential mutation/save.

Writable server states:
- `NEW_STATE`
- `NORMAL`
- `RECOVERED`

Non-writable states:
- `BOOTSTRAPPING`
- `READ_ONLY_SAFE_MODE`
- `CLIENT_WAITING_FOR_SYNC`
- `SHUTDOWN`

### Service container

Mission-scoped service registry. Product modules resolve shared engines from the container rather than constructing private debt/accounting systems.

### Currency

`AGFCurrency` is the common cent-normalization boundary. Persisted amounts remain FS-compatible numeric values, but new financial operations compare/round at integer-cent precision.

### ID service

Persistent ID scopes currently include:
- `TX`
- `GRP`
- `LIAB`

Future scopes include assets, liens, leases, applications, and snapshots.

### Ledger

One authoritative journal.

Every record may carry both:
- economic purpose (`expenseCategory` / transaction type); and
- funding source.

Posted records are sealed. Public reads return clones.

Canonical transaction types currently include:
- `creditDraw`
- `creditRepayment`
- `loanProceeds`
- `loanPayment`
- `principalPayment`
- `interestPayment`
- `financeFee`
- `lateFee`
- `inputPurchase`
- `assetPurchase`
- `assetSale`
- `leaseRent`
- `grantReceipt`
- `taxPayment`
- `adjustment`

Input purpose is represented by `expenseCategory`, not a different transaction class for every material.

### Liability registry

One registry for all AgForward debt.

Required common fields:
- farm ID;
- product type/status;
- principal/original principal;
- revolving credit limit;
- interest/fees;
- rate/term/payment/balloon;
- payment timing;
- linked asset;
- metadata.

### Financial operation coordinator

All multi-record changes must pass through a common commit boundary.

Current proof operation: revolving-funded input purchase. It validates the facility, posts a linked ledger batch, applies liability principal, and rolls back the new ledger batch if liability mutation fails.

Actual FS25 cash movement will later be added inside this coordinator.

### Integrity service

Runs after load and before save. Severe errors block writes.

Checks currently include:
- IDs/references;
- transaction/product taxonomies;
- finite monetary values;
- liability limits/balances;
- grouped financing/expense reconciliation;
- farm reference warnings;
- persistent ID observation.

### Save service

Schema v3 uses:
- `agForwardFinance.xml`
- `agForwardFinance.backup.xml`
- monotonic save generation;
- newest-valid-compatible-copy selection;
- backup fallback;
- newer-schema write protection;
- read-only safe mode.

See `SAVE_SCHEMA_V3.md`.

### Settlement coordinator

Only one service responds to `PERIOD_CHANGED` for AgForward settlement. Completion markers are persistent and versioned.

Phase 0 settlement engine version `0` performs no money movement.

### Purchase classification

`AGFPurchaseClassificationService` combines MoneyType and fill-type context.

Rules include:
- purchase seeds -> seed;
- purchase fuel -> fuel;
- fertilizer purchase plus fertilizer/liquid fertilizer -> fertilizer;
- fertilizer purchase plus herbicide -> crop protection;
- fertilizer purchase plus lime -> lime/soil amendment;
- generic bought-materials requires fill-type/caller context; no guessing.

### Input purchase accumulator

High-frequency helper input costs accumulate in integer cents by farm/category/funding/liability before future ledger posting.

### Compatibility service

Warns when overlapping donor/reference finance mods are active. It does not flag Red Tape.

### Red Tape adapter

Red Tape-specific behavior remains isolated under integration code. Core lending classes must not depend directly on Red Tape globals.

## Crop Input LOC accounting pattern

Example: $25,000 seed purchase funded by CILOC.

Shared group contains:

1. `creditDraw`, amount `+25000`, funding source `cropInputLine`, liability ID set, economic role `financing`.
2. `inputPurchase`, amount `-25000`, expense category `seed`, funding source `cropInputLine`, same liability/group, economic role `expense`.

Result:
- seed expense = $25,000;
- CILOC principal = +$25,000;
- group nets to $0 before the future actual-cash boundary;
- draw is not income.

## Asset/right registry target

Future native registry must distinguish:
- economic owner;
- operator;
- tenant/leaseholder;
- lienholder/collateral interest.

Asset classes:
- vehicle/equipment;
- placeable/facility;
- farmland;
- future secured assets.

Unresolved links are quarantined/retried, never silently treated as paid or deleted.

## Credit engine target

Whole-farm underwriting target metrics:
- DSCR;
- fixed-charge coverage;
- LTV;
- debt/assets;
- working capital/liquidity;
- revolving utilization;
- payment history;
- free vs encumbered collateral.

Credit calculations must include all known AgForward obligations plus deliberately represented vanilla/external obligations.

## Rate engine target

Pricing framework:

`base rate + product spread + borrower risk spread + optional term/structure adjustment`

Before implementation, lock:
- rate storage convention (decimal vs percent);
- nominal/effective convention;
- compounding frequency;
- variable-rate reset timing;
- amortization rounding.

## Multiplayer target

- server owns mutations;
- clients send requests only;
- requesting farm/permissions are verified from the connection, not trusted payload IDs;
- server validates product/amount/asset identity;
- state is synchronized to join-in-progress clients;
- clients never load/write the local AgForward save file.

## UI target

Main pages:
- Overview;
- Banking & Credit;
- Asset Finance;
- Land & Leases;
- Payments & Obligations;
- Reports;
- Government/Red Tape when supported;
- Settings.

Contextual entry points:
- vehicle dealer -> Finance with AgForward;
- construction -> Finance Project;
- farmland map -> Buy / Finance / Lease.

## Current source layout

```text
src/
  AgForwardFinance.lua
  core/
    ServiceContainer.lua
    RuntimeStateService.lua
    Currency.lua
    IdService.lua
    IntegrityService.lua
    CompatibilityService.lua
    SaveService.lua
  ledger/
    FinancialTaxonomy.lua
    Transaction.lua
    Ledger.lua
    FinancialOperationCoordinator.lua
    AccountingService.lua
  liabilities/
    Liability.lua
    LiabilityRegistry.lua
  input/
    PurchaseClassificationService.lua
    InputPurchaseAccumulator.lua
  settlement/
    SettlementCoordinator.lua
  integrations/
    RedTapeAdapter.lua
```

## Phase 0 exit criteria

- clean load with no Lua error;
- v3 dual-copy save/reload proven;
- corrupt/newer save protection proven;
- ID and ledger persistence deterministic;
- CILOC linked test operation reconciles exactly;
- server-only mutation proven;
- initial server-to-client state sync implemented and tested;
- no-op settlement cannot duplicate;
- Red Tape present/absent both load/save cleanly;
- minimal read-only finance diagnostics UI available.
