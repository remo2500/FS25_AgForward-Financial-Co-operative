# AgForward Offline Foundations Status

**Branch:** `offline-foundations`  
**Parent:** `phase0-foundation-hardening`  
**Date:** 2026-09-15  
**Purpose:** continue useful development while FS25 runtime testing is unavailable without destabilizing the Phase 0 persistence candidate.

## Workstream rule

This branch develops and tests pure models, math, contracts, read-only projections, and future integration semantics that do **not** require live Farming Simulator hooks.

It must not silently change the schema-v3 runtime candidate, activate real money movement, or merge into the hardening branch until the work is reviewed for runtime scope. `phase0-foundation-hardening` remains the first runtime persistence candidate.

## Implemented offline foundations

### Financial math and pricing

Implemented:

- cent-normalized money convention;
- annual nominal rate convention;
- 12 financial periods/year;
- componentized rate pricing;
- amortizing, balloon, bullet, and zero-rate schedule math;
- final-period cent reconciliation;
- componentized payoff calculation;
- shared loan quote engine;
- time-weighted revolving-credit interest;
- payment component allocation;
- variable-rate history and payment recast modeling.

Files:

- `docs/FINANCIAL_CONVENTIONS.md`
- `docs/REVOLVING_CREDIT_MODEL.md`
- `docs/VARIABLE_RATE_MODEL.md`
- `src/finance/RateConvention.lua`
- `src/finance/RatePricingService.lua`
- `src/finance/AmortizationService.lua`
- `src/finance/LoanQuoteService.lua`
- `src/finance/RevolvingInterestService.lua`
- `src/finance/PaymentAllocationService.lua`
- `src/finance/VariableRateService.lua`

### Whole-farm credit and underwriting

Implemented pure metrics/models:

- DSCR;
- fixed-charge coverage;
- debt-to-assets;
- LTV;
- working capital/current ratio;
- revolver utilization;
- liquidity coverage;
- equity/equity ratio;
- derived farm credit profile;
- whole-farm profile builder from common registries;
- before/after pro-forma underwriting projection;
- configurable policy-rule evaluator producing approve / approve-with-conditions / refer / decline outcomes.

Files:

- `docs/CREDIT_UNDERWRITING_MODEL.md`
- `src/credit/CreditMetrics.lua`
- `src/credit/FarmCreditProfile.lua`
- `src/credit/CreditProfileBuilder.lua`
- `src/credit/ProFormaUnderwritingService.lua`
- `src/credit/CreditPolicyService.lua`

Production approval thresholds/risk grades are **not** locked. Metrics remain separate from lending policy so calibration can occur after real FS25 farm economics are observed.

### External/base-game obligations

Base-game/other externally managed debt can be represented without pretending AgForward owns or modifies it. Records include source, principal, debt service/fixed charges, and data quality.

Files:

- `docs/EXTERNAL_OBLIGATION_POLICY.md`
- `src/credit/ExternalObligation.lua`
- `src/credit/ExternalObligationRegistry.lua`

### Crop Input Line of Credit

Offline CILOC foundation now includes:

- four funding policies: Off, cash-shortfall only, prefer line, always line;
- pre-authorization credit reservations so concurrent purchases cannot double-spend undrawn capacity;
- seasonal borrowing-base calculation from eligible acres/input cost/advance rate;
- optional harvest/grain-sale proceeds sweep calculation;
- purchase-interception/funding design preserving purchase purpose and funding source separately.

Files:

- `docs/CILOC_PURCHASE_INTERCEPTION_DESIGN.md`
- `docs/REVOLVING_CREDIT_MODEL.md`
- `src/input/FundingDecisionService.lua`
- `src/input/CreditReservationService.lua`
- `src/credit/CILOCBorrowingBaseService.lua`
- `src/credit/HarvestSweepService.lua`

### Project & facility finance

A common sources-and-uses model now separates:

- construction/project uses;
- groundwork;
- project equipment;
- professional/finance fees;
- farm cash/equity;
- external/Red Tape grant funding;
- other non-debt sources;
- AgForward financing;
- other debt.

The model calculates financing need, funding gaps, loan-to-cost, and collateral-eligible uses without performing construction or money movement.

Files:

- `docs/PROJECT_FINANCE_MODEL.md`
- `src/finance/ProjectSourcesUsesService.lua`

### Product capability catalog

All locked AgForward product families now have a common capability definition rather than product modules independently deciding whether they are revolving, balloon-capable, purchase-integrated, or collateralized.

File:

- `src/products/ProductCatalog.lua`

This catalog deliberately excludes approval/pricing thresholds.

### Asset / right / lien architecture

Common economic asset model separates:

- stable asset identity;
- runtime object-link state;
- economic ownership;
- operator rights;
- tenancy;
- liens;
- unresolved collateral quarantine.

A generic secured-disposition preflight calculates lien payoff, equity, negative-equity shortfall, and owner authorization without performing a real sale.

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

### Leasing

Common economic lease model/registry supports:

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

### Settlement and delinquency

Pure common models now provide:

- deterministic obligation planning;
- optional authorized settlement-credit use;
- partial/minimum-payment rules;
- fees/interest/principal allocation;
- exact unpaid balances;
- common delinquency lifecycle:

`Current -> Past Due -> Delinquent -> Final Notice -> Collections -> Recovery`

with cure support plus resolved/charged-off states.

Files:

- `docs/SETTLEMENT_AND_DELINQUENCY_MODEL.md`
- `src/settlement/SettlementPlanner.lua`
- `src/finance/PaymentAllocationService.lua`
- `src/delinquency/DelinquencyStateMachine.lua`

Default missed-payment thresholds are modeling defaults, not calibrated production policy.

### Multiplayer protocol model

Pure server-side protocol state provides:

- monotonic state revision;
- request IDs;
- operation IDs;
- idempotent duplicate-request handling;
- stale-revision detection;
- bounded request-result cache.

Design contract:

- `docs/MULTIPLAYER_PROTOCOL.md`

Pure model:

- `src/network/FinancialProtocolState.lua`

No live FS25 network events are enabled yet.

### MoneyType / FinanceStats / Red Tape semantics

AgForward now has a pre-runtime mapping contract distinguishing:

- financing proceeds/draws;
- principal repayment;
- interest;
- finance/late fees;
- lease rent;
- underlying operating purchases;
- asset acquisitions/disposals;
- grants.

The contract explicitly keeps AgForward ledger meaning separate from FS FinanceStats and Red Tape tax treatment.

Files:

- `docs/MONEYTYPE_FINANCESTATS_MAPPING.md`
- `src/integrations/MoneyMovementIntent.lua`

No live MoneyType registration is enabled; exact FS/Red Tape behavior remains a runtime gate.

### Reporting read models

Derived reporting now covers:

- overview/native/external debt;
- represented assets/equity;
- active liens;
- operating-line/CILOC balance and availability;
- source-of-funds by expense purpose;
- cash-funded vs financed crop inputs;
- transaction-group reconciliation;
- debt schedules by product;
- principal vs interest vs fees;
- external-debt data quality.

Files:

- `docs/REPORTING_ARCHITECTURE.md`
- `src/reporting/OverviewSnapshotService.lua`
- `src/reporting/LedgerReportService.lua`
- `src/reporting/DebtScheduleReportService.lua`

Reports remain derived views and never become separate balance authority.

## Automated offline validation

CI currently performs:

1. repository/XML/package validation;
2. Lua 5.1 syntax checks across `src/`;
3. finance/rate/amortization/revolver/funding tests;
4. deterministic financial-invariant matrix;
5. CILOC borrowing-base/sweep tests;
6. configurable credit-policy tests;
7. whole-farm credit-profile tests;
8. variable-rate/project-finance tests;
9. product/accounting semantic-contract tests;
10. asset/right/lien/external-obligation tests;
11. reservation/pro-forma/lease/delinquency/settlement/protocol tests;
12. derived-reporting tests.

Files include:

- `.github/workflows/static-validation.yml`
- `tests/offline_finance_tests.lua`
- `tests/offline_invariant_tests.lua`
- `tests/offline_ciloc_policy_tests.lua`
- `tests/offline_credit_policy_tests.lua`
- `tests/offline_credit_profile_tests.lua`
- `tests/offline_project_rate_tests.lua`
- `tests/offline_contract_tests.lua`
- `tests/offline_asset_tests.lua`
- `tests/offline_policy_tests.lua`
- `tests/offline_reporting_tests.lua`

The latest comprehensive run after adding these suites completed successfully. These tests validate math/model contracts but do **not** replace GIANTS TestRunner or in-game validation.

## Deliberately not activated

This branch does not yet:

- move real FS25 money;
- register live AgForward MoneyTypes/FinanceStats;
- intercept purchases/construction/vehicle/land transactions;
- persist the offline asset/lease/credit/network models into schema v3;
- create live multiplayer events;
- grant/revoke farmland operating access;
- execute lien-aware sales/repossessions;
- calculate/test real stable keys from FS25 objects;
- bridge external/base-game debt live;
- inject Red Tape tax classifications;
- present live GUI screens;
- activate variable-rate resets in live agreements.

## Runtime gates that remain

When testing becomes available, priority remains:

1. Phase 0 schema-v3 persistence/recovery/safe-mode QA;
2. Red Tape save-hook coexistence;
3. authoritative MoneyType/FinanceStats cash boundary;
4. CILOC purchase interception/reservation proof;
5. stable vehicle/placeable/farmland relinking;
6. multiplayer snapshot/delta protocol proof;
7. asset/right/lien and additional product-state persistence schema promotion;
8. read-only UI integration;
9. only then enable live lending/settlement money movement.

## Promotion rule

Pure modules from this branch may be selectively promoted after CI/review, but `phase0-foundation-hardening` remains the runtime-test candidate until its existing persistence foundation is proven in FS25. Avoid bundling unrelated offline expansion into the first runtime persistence test.
