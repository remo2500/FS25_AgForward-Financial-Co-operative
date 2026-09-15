# AgForward Current Project Authority

**Project:** AgForward Financial Cooperative  
**Public brand:** AgForward  
**Repository:** `remo2500/FS25_AgForward-Financial-Co-operative`  
**Authority revision:** A001  
**Date:** 2026-09-15  
**Status:** ACTIVE — Phase 0 foundation

This document is the governing coordination file for AgForward. When another project document conflicts with this file, this file controls until deliberately revised.

## 1. Locked identity

- Formal institution name: **AgForward Financial Cooperative**.
- Public-facing brand: **AgForward**.
- Mod package target: `FS25_AgForwardFinance`.
- Primary Lua namespace: `AgForwardFinance`.
- Internal short prefix: `AGF`.
- Native save file target: `agForwardFinance.xml`.
- Localization key prefix: `agf_`.

## 2. Locked product direction

AgForward is a native, original FS25 financial ecosystem. It is **not** intended to remain a permanent compatibility shell around multiple third-party lending mods.

AgForward will ultimately replace the core purposes of:

- Bank & Credit;
- Finance Your Fleet;
- AgriCredit Solutions;
- Field Leasing;
- Economic History.

Trade-in/dealer replacement functionality is **deferred** and may be added later.

**Red Tape remains the primary optional third-party integration.** AgForward must function normally without Red Tape installed.

## 3. Locked architecture principles

1. One authoritative financial ledger.
2. One liability registry across all loans and financed obligations.
3. One asset/right registry across vehicles, placeables, farmland, liens, ownership, and operating rights.
4. One amortization/payoff engine.
5. One whole-farm credit engine.
6. One rate/pricing engine.
7. One monthly settlement coordinator.
8. One delinquency/collections state model.
9. Contextual finance actions remain available where the purchase occurs.
10. The AgForward menu shows the complete farm financial position.
11. Consequential multiplayer actions are server-authoritative.
12. Red Tape integration is isolated behind an adapter.
13. Third-party protected source, assets, UI text, icons, or distinctive implementations are not copied.

## 4. Locked native product families

### Operating Credit
- Revolving operating line.
- General working-capital lending.
- **Crop Input Line of Credit (CILOC).**

### General Term Lending
- Amortizing term loans.
- Bullet structures.
- Fixed and variable rates.

### Equipment Finance
- Dealer-integrated financing.
- Down payment/equity.
- Asset lien.
- Balloon/residual where appropriate.
- Early payoff.
- Delinquency/recovery.

### Project & Facility Finance
- Construction/placeable finance.
- Cash contribution.
- Optional Red Tape grant contribution.
- Facility/placeable lien.
- Cure/collections.

### Land Finance
- Farmland mortgages.
- Lien settlement before sale.

### Land Leasing
- Tenant/operator rights separated from economic ownership.
- Rent, term, expiry, renewal, and default.
- Leased ground excluded from owned collateral.

### Reporting
- Balance sheet.
- Cash-flow and expense reporting.
- Debt schedules.
- Interest/principal history.
- Assets, liens, equity, leases, and credit metrics.

## 5. Crop Input Line of Credit — locked accounting model

The CILOC is a dedicated revolving agricultural operating facility.

**Financing source and expense purpose are separate dimensions.**

Example: a $30,000 fertilizer purchase funded by the CILOC records:

- a $30,000 CILOC draw increasing the liability; and
- a $30,000 fertilizer purchase in the fertilizer expense category.

The credit draw is **not income**. The purchase remains an input expense. Principal repayment is **not an expense**. Interest and fees are separate classifications.

Eligible categories are expected to include at minimum:

- seed;
- fertilizer;
- lime / soil amendments;
- crop protection products;
- fuel;
- compatible custom crop-input categories where safely identifiable.

Each funded purchase must be linked to its financing draw through a transaction-group identifier so reporting can answer both "what was purchased?" and "how was it funded?"

CILOC usage modes targeted for design:

- Off.
- Use when cash is insufficient.
- Prefer CILOC for eligible inputs.
- Always use CILOC for eligible inputs.

Potential later features include seasonal limits based on acres/costs and harvest-proceeds sweeps.

## 6. Red Tape boundary

Red Tape owns:

- taxation;
- grants;
- government schemes;
- policy/regulation;
- regulatory fines and consequences.

AgForward owns economic truth for its finance system and must preserve transaction purpose. At minimum:

- loan proceeds/draws: financing, not income;
- principal repayments: balance-sheet movement, not expense;
- interest: finance expense;
- rent: lease/rent expense;
- fees: separately classified;
- asset purchases/sales: asset transactions;
- grants: external funding source when provided by Red Tape.

## 7. Trade-in status

**DEFERRED.**

The asset/lien model must nevertheless preserve enough information to support a future transaction:

`gross trade value - lien payoff - accrued charges = net trade equity`.

No first-phase dependency on Trade In is permitted.

## 8. Current development phase

### Phase 0 — Foundation

Required foundation work:

- source/package structure;
- bootstrap and mission lifecycle;
- service container;
- stable ID service;
- versioned save/load infrastructure;
- transaction model;
- journal/ledger;
- transaction taxonomy;
- MoneyType/FinanceStats planning and registration;
- initial multiplayer state model;
- single period-change settlement coordinator;
- Red Tape presence/version detection;
- accounting bridge proof without double counting;
- minimal AgForward finance UI;
- save/load/reload QA in single-player and multiplayer.

## 9. Non-goals for Phase 0

Do not implement yet:

- trade-in/dealer used-equipment market;
- full equipment recovery gameplay;
- full construction finance UI;
- full land-leasing rights replacement;
- cosmetic branding polish beyond what is needed for functional UI;
- copied or ported third-party code.

## 10. Change-control rule

Any change to a locked item above must be explicitly promoted into a new revision of this authority document. Experimental code may exist on branches, but it does not become project-wide authority until this file is deliberately updated.
