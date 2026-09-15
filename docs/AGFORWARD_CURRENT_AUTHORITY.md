# AgForward Current Project Authority

**Project:** AgForward Financial Cooperative  
**Public brand:** AgForward  
**Repository:** `remo2500/FS25_AgForward-Financial-Co-operative`  
**Authority revision:** A004-HARDENING  
**Date:** 2026-09-15  
**Branch:** `phase0-foundation-hardening`  
**Status:** ACTIVE DEVELOPMENT AUTHORITY — Phase 0 hardening implemented; runtime validation pending

This document governs the hardening branch. `main` remains the last reviewed baseline until this branch is runtime validated and deliberately merged.

## 1. Locked identity

- Formal institution name: **AgForward Financial Cooperative**.
- Public-facing brand: **AgForward**.
- Mod package target: `FS25_AgForwardFinance`.
- Primary Lua namespace: `AgForwardFinance`.
- Internal prefix: `AGF`.
- Native primary save file: `agForwardFinance.xml`.
- Native recovery save file: `agForwardFinance.backup.xml`.
- Localization prefix: `agf_`.

## 2. Locked product direction

AgForward is a native, original FS25 financial ecosystem. It will ultimately replace the core purposes of:

- Bank & Credit;
- Finance Your Fleet;
- AgriCredit Solutions;
- Field Leasing;
- Economic History.

Trade-in/dealer replacement functionality is deferred and may be added later.

**Red Tape remains the primary optional external integration.** AgForward must function normally without Red Tape installed.

## 3. Locked architecture principles

1. One authoritative financial ledger.
2. One liability registry across all loans and financed obligations.
3. One asset/right/lien registry across equipment, placeables, farmland, ownership, operating rights, and collateral.
4. One amortization/payoff engine.
5. One whole-farm credit engine.
6. One rate/pricing engine.
7. One monthly settlement coordinator.
8. One delinquency/collections state model.
9. Contextual finance actions remain available where purchases occur.
10. The AgForward menu shows the complete farm financial position.
11. Consequential financial mutations are server-authoritative.
12. Red Tape integration is isolated behind an adapter.
13. Third-party protected code/assets/UI are not copied.
14. Financing source and economic purpose are separate accounting dimensions.
15. Native AgForward IDs remain stable across save/load and are never silently reused.
16. Posted ledger entries are immutable journal history.
17. A failed/corrupt load is never treated as a legitimate empty/new save.
18. An older AgForward build never overwrites a newer unknown save schema.
19. Multi-record financial changes must pass through a coordinated commit boundary.
20. Financial state is validated after load and before save.

## 4. Locked product families

### Operating Credit
- General revolving operating line.
- **Crop Input Line of Credit (CILOC).**

### General Term Lending
- Amortizing term loans.
- Bullet structures.
- Fixed/variable rates.

### Equipment Finance
- Dealer-context financing.
- Down payment/equity.
- Asset lien.
- Balloon/residual where appropriate.
- Early payoff.
- Delinquency/recovery.

### Project & Facility Finance
- Construction/placeable finance.
- Cash contribution.
- Optional Red Tape grant contribution.
- Placeable lien.
- Cure/collections.

### Land Finance
- Farmland mortgages.
- Lien settlement before sale.

### Land Leasing
- Economic owner, operator, tenant, and collateral owner are separate concepts.
- Rent, term, expiry, renewal, and default.
- Leased ground is excluded from owned collateral.

### Reporting
- Balance sheet.
- Cash flow/expense reporting.
- Debt schedules.
- Principal/interest history.
- Assets, liens, equity, leases, and credit metrics.

## 5. Crop Input Line of Credit — locked model

The CILOC is a dedicated revolving agricultural operating facility.

**Financing source and expense purpose are separate.**

A $30,000 fertilizer purchase funded by the CILOC records:

- CILOC draw +$30,000 increasing the liability; and
- fertilizer purchase -$30,000 categorized as fertilizer expense.

The draw is not income. Principal repayment is not expense. Interest and fees remain separate.

Minimum eligible categories:

- seed;
- fertilizer;
- lime/soil amendments;
- crop protection;
- fuel;
- compatible custom crop-input categories where safely identifiable.

Each funded purchase uses a shared transaction-group ID so reporting can answer both what was purchased and how it was funded.

Target CILOC usage policies:

- Off;
- cash-shortfall only;
- prefer CILOC;
- always use CILOC for eligible inputs.

Potential later features:

- seasonal borrowing base based on acres/costs;
- harvest-proceeds sweep.

## 6. Purchase classification — locked direction

MoneyType alone is not sufficient to classify every crop input transaction.

AgForward's purchase classification boundary must accept available context including:

- farm ID;
- amount;
- MoneyType/statistic;
- fill type when available;
- source object/purchase path;
- explicit caller context where AgForward initiated the transaction.

Examples:

- `PURCHASE_SEEDS` -> seed;
- `PURCHASE_FUEL` -> fuel;
- fertilizer-type purchase plus `HERBICIDE` fill type -> crop protection;
- fertilizer-type purchase plus `LIME` -> lime/soil amendment;
- generic `BOUGHT_MATERIALS` without fill-type context -> **do not guess**.

High-frequency helper purchases must be accumulated in exact cent-based buckets before ledger posting so AgForward does not create thousands of trivial journal records.

## 7. Native ledger conventions

- inflows are positive;
- outflows are negative;
- loan/revolver proceeds are financing entries, not operating income;
- principal repayments reduce liabilities and are not operating expense;
- interest and fees are separate;
- expense category describes purpose, not source of funds;
- linked multi-entry events use a group ID;
- grouped records are prevalidated before posting;
- posted records are sealed;
- public queries return copies, not live mutable journal objects;
- monetary operations normalize to cents through `AGFCurrency`.

Canonical taxonomy: `src/ledger/FinancialTaxonomy.lua`.

## 8. Native liability conventions

All AgForward lending products use the native liability registry.

Current record supports:

- stable liability ID;
- farm ownership;
- product type/status;
- original/current principal;
- revolving credit limit;
- accrued interest/fees;
- rate/term/payment/balloon fields;
- payment timing;
- linked asset reference;
- metadata.

Revolving availability:

`available credit = max(0, credit limit - principal balance)`

Accrued interest/fees remain separate from principal utilization unless a product policy later states otherwise.

## 9. Persistence authority — schema v3

Schema v3 introduces fail-safe dual-copy persistence.

Runtime states:

- `NEW_STATE`;
- `NORMAL`;
- `RECOVERED`;
- `READ_ONLY_SAFE_MODE`;
- `CLIENT_WAITING_FOR_SYNC`.

Rules:

- recovery copy is written and validated before primary;
- each save generation is monotonic;
- loader selects the newest compatible validated copy;
- failed record/integrity load can fall back to another valid copy;
- no valid copy -> read-only safe mode;
- newer unknown schema -> read-only safe mode and overwrite blocked;
- post-load and pre-save integrity checks are mandatory.

Detailed schema: `docs/SAVE_SCHEMA_V3.md`.

## 10. Financial operation coordination

Multi-record financial state changes must go through a coordinated operation boundary.

Current proof case: financed crop-input purchase.

1. validate runtime/server authority;
2. validate liability/farm/product/limit;
3. construct linked financing + expense records;
4. post the ledger batch;
5. apply liability principal change;
6. roll back the just-posted ledger batch if liability application fails.

When actual FS25 money movement is added, it must join this same commit boundary rather than being performed independently by product modules.

## 11. Settlement authority

Only one AgForward component reacts to period changes for financial settlement.

The completion key is persisted and includes:

`settlement engine version : year : period`

Phase 0 engine version is `0` and performs no money movement. Any future money-moving settlement implementation must increment the engine version.

## 12. Red Tape boundary

Red Tape owns:

- taxation;
- grants;
- government schemes;
- policy/regulation;
- regulatory fines/consequences.

AgForward owns lending/accounting truth.

Required treatment:

- loan proceeds/draws -> financing, not income;
- principal -> liability movement, not deductible expense;
- interest -> finance expense;
- rent -> lease/rent expense;
- fees -> separately classified;
- asset purchases/sales -> asset transactions;
- grants -> external program funding.

No production Red Tape bridge may be enabled until duplicate-recording behavior is tested transaction by transaction.

## 13. Compatibility policy during development

Known overlapping finance mods are detected and warned about:

- Bank & Credit;
- Finance Your Fleet;
- AgriCredit Solutions;
- Field Leasing;
- Economic History;
- Trade In Menu.

Use a dedicated test save while these systems overlap. Red Tape is the intended exception.

## 14. Vanilla/base-game debt boundary — unresolved

Before whole-farm underwriting is activated, AgForward must deliberately decide how to handle:

- vanilla `farm.loan`;
- base-game vehicle leases;
- external/mod liabilities not owned by AgForward.

They may be imported, represented as external obligations, or disabled/replaced, but they may not be silently ignored in whole-farm credit metrics.

## 15. Trade-in status

**DEFERRED.**

Architecture must preserve later calculation:

`gross trade value - lien payoff - accrued charges = net trade equity`.

## 16. Current Phase 0 status

Implemented on the hardening branch:

- bootstrap/service container;
- runtime safety state;
- cent-normalization service;
- persistent IDs;
- canonical taxonomy;
- sealed transaction model;
- ordered central ledger with batch rollback;
- native liability model/registry;
- financial operation coordinator;
- purpose-aware accounting;
- context-aware input classifier;
- high-frequency input accumulator;
- settlement idempotency persistence;
- compatibility detector;
- Red Tape detection adapter;
- integrity/reconciliation service;
- schema v3 dual-copy save/load;
- save-hook coexistence strategy.

Not runtime validated yet:

- XML API behavior under schema v3;
- dual-copy recovery;
- save-hook coexistence;
- safe-mode write blocking;
- CILOC linked accounting after reload;
- multiplayer behavior;
- Red Tape coexistence.

## 17. Immediate next gates

1. Complete donor/reference re-audit and record implementation-neutral findings.
2. Re-audit this hardening branch against those findings.
3. Correct any pre-runtime defects found.
4. Review branch diff.
5. Package a disposable-save runtime candidate only after the code audit passes.
6. Validate schema v3/recovery first.
7. Only then add the FS25 cash/MoneyType boundary, multiplayer synchronization, and minimal UI.

## 18. Change control

Experimental work belongs on development branches. `main` becomes project-wide authority only after deliberate review/promotion. Any change to a locked item above requires an explicit authority revision.
