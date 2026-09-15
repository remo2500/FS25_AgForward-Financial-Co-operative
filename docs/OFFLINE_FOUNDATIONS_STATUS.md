# AgForward Offline Foundations Status

**Branch:** `offline-foundations`  
**Parent:** `phase0-foundation-hardening`  
**Date:** 2026-09-15  
**Purpose:** continue useful development while FS25 runtime testing is unavailable without destabilizing the Phase 0 persistence candidate.

## Workstream rule

This branch may develop and test pure models, math, contracts, and read-only projections that do **not** require live Farming Simulator hooks.

It must not silently change the schema-v3 runtime candidate, activate real money movement, or merge into the hardening branch until its CI is green and the work is reviewed for runtime scope.

## Implemented offline foundations

### Financial math

- cent-normalized money convention;
- annual nominal rate convention;
- 12 financial periods/year;
- componentized rate pricing;
- amortizing, balloon, bullet, and zero-rate schedule math;
- componentized payoff calculation;
- shared loan quote engine.

Files:

- `docs/FINANCIAL_CONVENTIONS.md`
- `src/finance/RateConvention.lua`
- `src/finance/RatePricingService.lua`
- `src/finance/AmortizationService.lua`
- `src/finance/LoanQuoteService.lua`

### Whole-farm credit

- DSCR;
- fixed-charge coverage;
- debt-to-assets;
- LTV;
- working capital/current ratio;
- revolver utilization;
- liquidity coverage;
- equity/equity ratio;
- derived farm credit profile model;
- before/after pro-forma underwriting projection.

Files:

- `docs/CREDIT_UNDERWRITING_MODEL.md`
- `src/credit/CreditMetrics.lua`
- `src/credit/FarmCreditProfile.lua`
- `src/credit/ProFormaUnderwritingService.lua`

No approval/risk-grade thresholds are locked yet; metric calculation remains separate from policy.

### External obligations

Base-game/other externally managed debt can be represented without pretending AgForward owns or modifies it. Records include source, principal, debt service/fixed charges, and data quality.

Files:

- `docs/EXTERNAL_OBLIGATION_POLICY.md`
- `src/credit/ExternalObligation.lua`
- `src/credit/ExternalObligationRegistry.lua`

### Asset / right / lien architecture

Common economic asset model now separates:

- stable asset identity;
- runtime object link state;
- economic ownership;
- operator rights;
- tenancy;
- liens;
- unresolved collateral quarantine.

A generic secured-disposition preflight calculates lien payoff, equity, negative-equity shortfall, and owner authorization without performing any real sale.

Files:

- `docs/ASSET_RIGHT_LIEN_MODEL.md`
- `src/assets/AssetRecord.lua`
- `src/assets/AssetRegistry.lua`
- `src/assets/AssetRight.lua`
- `src/assets/AssetRightRegistry.lua`
- `src/assets/Lien.lua`
- `src/assets/LienRegistry.lua`
- `src/assets/AssetLinkQuarantine.lua`
- `src/assets/SecuredDispositionService.lua`

### Crop Input Line funding

Pure funding allocation implements:

- Off;
- cash-shortfall only;
- prefer line;
- always line.

A reservation model prevents multiple concurrent purchases from double-spending the same remaining line availability before underlying FS transactions commit.

Files:

- `docs/CILOC_PURCHASE_INTERCEPTION_DESIGN.md`
- `src/input/FundingDecisionService.lua`
- `src/input/CreditReservationService.lua`

### Leasing

A common economic lease model/registry now provides:

- asset-linked lease identity;
- farmland/equipment/facility lease types;
- lessor/lessee representation;
- periodic rent and fixed-charge reporting;
- rent accrual/payment allocation;
- lifecycle states.

Files:

- `src/leasing/Lease.lua`
- `src/leasing/LeaseRegistry.lua`

This does not yet grant/revoke FS25 gameplay access; the future land adapter must coordinate lease rights with the asset-right registry.

### Delinquency

A pure shared state machine provides:

`Current -> Past Due -> Delinquent -> Final Notice -> Collections -> Recovery`

with cure support and explicit resolved/charged-off states.

File:

- `src/delinquency/DelinquencyStateMachine.lua`

The thresholds are policy inputs rather than being embedded independently in each product.

### Multiplayer protocol model

A pure server-side protocol-state model provides:

- monotonic state revision;
- request IDs;
- operation IDs;
- idempotent duplicate request handling;
- stale-revision detection;
- bounded request-result cache.

Design contract:

- `docs/MULTIPLAYER_PROTOCOL.md`

Pure model:

- `src/network/FinancialProtocolState.lua`

No live FS25 network events are enabled yet.

### Reporting read model

A read-only overview projection derives:

- native/external debt;
- registered owned assets;
- represented equity;
- active liens;
- operating line/CILOC availability;
- external fixed charges;
- recent ledger activity;
- data-quality state.

File:

- `src/reporting/OverviewSnapshotService.lua`

This is explicitly a derived view and does not become a second balance authority.

## Automated offline validation

CI now performs:

1. repository/XML/package validation;
2. Lua 5.1 syntax checks across `src/`;
3. pure finance tests;
4. asset/right/lien/external-obligation tests;
5. reservation/underwriting/lease/delinquency/protocol tests.

Files:

- `.github/workflows/static-validation.yml`
- `tests/offline_finance_tests.lua`
- `tests/offline_asset_tests.lua`
- `tests/offline_policy_tests.lua`

These tests are valuable for math/model correctness but do **not** replace GIANTS TestRunner or in-game validation.

## Deliberately not activated

The branch does not yet:

- move real FS25 money;
- register live AgForward MoneyTypes/FinanceStats;
- intercept purchases;
- persist offline asset/lease/network models into schema v3;
- create live multiplayer events;
- grant/revoke farmland operating access;
- execute lien-aware sales/repossessions;
- calculate real asset stable keys from FS25 objects;
- bridge external/base-game debt live;
- apply Red Tape tax classifications;
- present live GUI screens.

## Runtime gates that remain

When testing becomes available, priority remains:

1. Phase 0 schema-v3 persistence/recovery/safe-mode QA;
2. Red Tape save-hook coexistence;
3. authoritative MoneyType/FinanceStats cash boundary;
4. CILOC purchase interception/reservation proof;
5. stable vehicle/placeable/farmland relinking;
6. multiplayer snapshot/delta protocol proof;
7. asset/right/lien persistence schema promotion;
8. read-only UI integration;
9. only then enable live lending/settlement money movement.

## Promotion rule

Pure modules from this branch may be selectively promoted after CI/review, but `phase0-foundation-hardening` remains the runtime-test candidate until its existing persistence foundation is proven in FS25. Avoid bundling unrelated offline expansion into the first runtime persistence test.
