# AgForward Development Roadmap

## Phase 0 — Foundation & Financial Integrity

Goal: establish the native core that every later product uses and prove it cannot silently corrupt financial state before real money movement is enabled.

### Implemented on `phase0-foundation-hardening`

- package/bootstrap structure;
- mission lifecycle/service container;
- runtime safety states and write-blocking safe mode;
- cent-normalization service;
- stable ID generation;
- versioned schema-v3 dual-copy save/recovery;
- immutable transaction model and central ledger;
- transaction taxonomy;
- native liability registry;
- coordinated multi-record financial operation boundary;
- purpose-aware Crop Input LOC accounting proof;
- purchase classification foundation using MoneyType + fill-type context;
- high-frequency crop-input accumulator;
- versioned/persisted settlement idempotency marker;
- integrity/reconciliation service;
- overlapping-finance-mod detector;
- Red Tape detection/adapter shell;
- static repository validation + GitHub workflow;
- donor/reference re-audit and implementation research.

### Remaining Phase 0 implementation

- runtime validation of schema-v3 primary/recovery behavior;
- runtime save-hook coexistence with Red Tape;
- MoneyType/FinanceStats strategy finalized for the first live money boundary;
- server state revision/operation IDs;
- multiplayer initial-state snapshot and join-in-progress sync;
- explicit server request/result event framework;
- minimal read-only AgForward finance/diagnostic screen;
- dedicated-server save/reload QA.

### Phase 0 exit criteria

- static validation and current GIANTS TestRunner pass packaged candidate;
- AgForward loads without errors in a clean disposable FS25 save;
- primary/recovery financial files persist and recover deterministically;
- corrupt/unsupported newer financial state is never overwritten;
- IDs, liabilities, and ledger survive repeated save/load exactly;
- one development CILOC operation reconciles and survives reload without moving real FS money;
- duplicate period callbacks cannot double-run settlement;
- a server-generated state snapshot reaches joining clients exactly once using state revision/operation IDs;
- client cannot write the AgForward save or authoritatively mutate finance state;
- Red Tape installed/not-installed paths both load/save cleanly;
- minimal read-only diagnostics show server state, liabilities, and recent ledger activity.

## Phase 1 — Banking & Operating Credit

Goal: introduce real AgForward lending only after the Phase 0 financial-state boundary is proven.

### Required policy locks before loan math

- interest-rate storage convention;
- nominal/effective and compounding convention;
- variable-rate reset timing;
- amortization/payment rounding;
- base-game `farm.loan` / existing external-debt representation policy;
- initial settlement priority policy.

### Deliverables

- whole-farm credit profile;
- standard amortizing term loan;
- bullet loan;
- revolving operating line;
- Crop Input Line of Credit;
- fixed/variable pricing framework;
- draw/repayment workflow;
- principal/interest/fee split;
- actual FS cash/MoneyType/FinanceStats boundary inside the operation coordinator;
- pre-purchase funding/affordability path for CILOC;
- live crop-input purchase context capture;
- accumulator flush/reconciliation policy;
- automatic settlement draw policy;
- borrower limits and initial DSCR/LTV/liquidity rules;
- transaction-by-transaction Red Tape reconciliation before enabling any production bridge.

### CILOC acceptance criteria

- fertilizer funded by the line remains fertilizer expense;
- seed funded by the line remains seed expense;
- lime remains lime/soil-amendment expense;
- crop protection remains crop-protection expense;
- fuel remains fuel expense;
- generic bought-material transactions are not guessed without fill-type/caller context;
- credit draws are not income;
- principal repayments are not expense;
- interest/fees remain separate;
- linked draw/purchase groups reconcile exactly;
- a line can authorize an eligible purchase that cash alone could not afford when policy permits;
- helper-scale charges aggregate without cent drift or ledger flooding.

## Phase 2 — Asset / Lien Foundation & Equipment Finance

### Foundation required before equipment lending

- common asset/right/lien registry;
- stable vehicle unique-ID link as primary collateral identity;
- transient object/network IDs as runtime handles only;
- save identity metadata for recovered asset links;
- asset-link quarantine/retry state;
- delayed disappearance confirmation after reset/customization/reload;
- generic secured-asset disposition/payoff service.

### Equipment-finance deliverables

- dealer finance entry point;
- server-priced/validated quote selection;
- down payment/equity;
- amortization and balloons;
- equipment lien;
- early payoff;
- lien-aware sale/transfer guard;
- delinquency/cure/recovery states;
- multiplayer validation and explicit operation-result events.

## Phase 3 — Project & Facility Finance

Deliverables:
- construction/placeable finance entry point;
- server-originated agreement from authoritative purchase result;
- placeable stable unique-ID linking/quarantine;
- sources-and-uses model;
- cash contribution;
- project loans;
- placeable liens;
- common secured-disposition settlement;
- cure/collections;
- optional Red Tape grant contribution.

## Phase 4 — Land Finance & Leasing

Deliverables:
- farmland mortgage;
- land lien and sale settlement;
- economic ownership registry;
- operator/access rights separated from legal/economic ownership;
- tenant/leaseholder and lienholder represented separately;
- lease creation, rent, expiry, renewal, default;
- server-authoritative rent/term calculation;
- leased land excluded from owned assets/collateral;
- lease commitments included in fixed-charge coverage;
- any FS engine ownership/access workaround isolated behind an adapter and never used as economic truth.

## Phase 5 — Reporting & History

Deliverables:
- balance sheet;
- debt schedules;
- cash-flow and expense history;
- principal/interest history;
- collateral/liens/equity reports;
- lease obligations;
- source-of-funds reports;
- multi-period snapshots;
- server-generated read-only report snapshots for clients;
- supplemental vanilla FinanceStats ingestion for external operating activity where useful;
- CSV export.

Reporting authority remains AgForward ledger + registries; vanilla `farm.loan` is never treated as total debt by itself.

## Phase 6 — Deep Red Tape Integration

Deliverables:
- validated transaction classification bridge;
- no double-counting of money movements Red Tape already observes;
- intentional treatment for custom/`other` MoneyTypes;
- interest/rent/fees exposed consistently;
- project grant linkage;
- tax estimate/obligation display in AgForward where safely available;
- optional expected-tax obligation interface for liquidity forecasting without taking ownership of Red Tape tax calculation.

## Phase 7 — Refinement / Release Hardening

Deliverables:
- rate calibration;
- UI/UX polish;
- localization expansion;
- performance and large-save testing;
- multiplayer stress testing;
- migration support from supported AgForward schema versions;
- farm create/delete/merge lifecycle handling;
- packaged-mod TestRunner gate;
- release/recovery documentation.

## Deferred — Trade / Used Equipment

A native trade/dealer module is not required for initial release. Future trade valuation may be supplied by a dedicated module, while AgForward owns lien/payoff/equity treatment:

`gross trade value - payoff - accrued charges = net trade equity`.

Any future client-selected finance terms/trade attachment must be repriced and validated by the server before commitment.
