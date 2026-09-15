# AgForward Development Roadmap

## Phase 0 — Foundation

Goal: establish the native core that every later product uses.

Deliverables:
- package/bootstrap structure;
- mission lifecycle manager;
- service container;
- stable ID generation;
- versioned save/load to `agForwardFinance.xml`;
- transaction and transaction-group models;
- central ledger/journal;
- transaction taxonomy;
- MoneyType/FinanceStats registration strategy;
- multiplayer initial-state synchronization;
- one period-change settlement coordinator;
- Red Tape detection and adapter shell;
- minimal AgForward menu/diagnostic screen;
- single-player and dedicated-server save/reload QA.

Exit criteria:
- AgForward loads without errors in a clean FS25 save;
- save data persists and reloads deterministically;
- a server-created test transaction reaches clients exactly once;
- one test obligation can be settled without double-posting;
- Red Tape installed/not-installed paths both load cleanly.

## Phase 1 — Banking & Operating Credit

Deliverables:
- whole-farm credit profile;
- standard amortizing term loan;
- bullet loan;
- revolving operating line;
- Crop Input Line of Credit;
- fixed/variable pricing framework;
- draw/repayment workflow;
- principal/interest split;
- automatic settlement draw policy;
- borrower limits and initial DSCR/LTV rules.

CILOC acceptance criteria:
- fertilizer funded by the line remains fertilizer expense;
- seed funded by the line remains seed expense;
- fuel funded by the line remains fuel expense;
- credit draws are not income;
- principal repayments are not expense;
- linked draw/purchase transaction groups reconcile exactly.

## Phase 2 — Equipment Finance

Deliverables:
- dealer finance entry point;
- down payment/equity;
- amortization and balloons;
- vehicle asset registry/linking;
- equipment liens;
- early payoff;
- financed-asset sale guard;
- delinquency/cure/recovery states;
- multiplayer validation.

## Phase 3 — Project & Facility Finance

Deliverables:
- construction/placeable finance entry point;
- sources-and-uses model;
- cash contribution;
- project loans;
- placeable liens;
- sale settlement;
- cure/collections;
- optional Red Tape grant contribution.

## Phase 4 — Land Finance & Leasing

Deliverables:
- farmland mortgage;
- land lien and sale settlement;
- economic ownership registry;
- tenant/operator rights separated from ownership;
- lease creation, rent, expiry, renewal, default;
- leased land excluded from net owned collateral;
- lease commitments included in fixed-charge coverage.

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
- CSV export.

## Phase 6 — Deep Red Tape Integration

Deliverables:
- validated transaction classification bridge;
- no double-counting of finance transactions;
- interest/rent/fees exposed consistently;
- project grant linkage;
- tax estimate/obligation display in AgForward where safely available.

## Phase 7 — Refinement

Deliverables:
- rate calibration;
- UI/UX polish;
- localization expansion;
- performance and large-save testing;
- multiplayer stress testing;
- migration support from early AgForward save schema versions.

## Deferred — Trade / Used Equipment

A native trade/dealer module is not required for initial release. The core asset and lien architecture must support later calculation of:

`gross trade value - payoff - accrued charges = net trade equity`.
