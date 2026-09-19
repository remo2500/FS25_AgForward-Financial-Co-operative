# AgForward Offline Development Update — 2026-09-17

**Branch:** `offline-foundations`  
**Base runtime candidate:** `phase0-foundation-hardening`  
**Runtime validation:** still pending

## Purpose of this pass

Continue useful development without weakening the runtime gate. This pass focused on the seam between borrower intent, underwriting/quotes, accepted offers, eventual liability creation, seasonal liquidity, collateral policy, exact debt-service measurement, CILOC management, and safe packaging of the actual runtime candidate.

No live FS25 money movement, purchase interception, save-schema expansion, multiplayer event serialization, land-access mutation, or Red Tape tax injection was enabled.

## 1. Client application intent is explicitly non-authoritative

Added/hardened:

- `src/network/FinancialApplicationIntentService.lua`
- `tests/offline_application_intent_tests.lua`

The service defines exactly what a future client may request versus what the server must derive.

Client-supplied authoritative fields are rejected, including:

- farm and connection identity;
- rate/APR/pricing/quote;
- approval/manual-review status;
- state revision;
- credit limit/principal/scheduled payment;
- collateral/appraised/market value and prior claims;
- borrowing base;
- asset ID/lien priority;
- asset purchase price and context fingerprint.

Farm identity comes from the server connection context. Asset-finance purchase price and context fingerprints also come from server-resolved purchase context. Asset-finance principal is derived from authoritative purchase price and equity rather than accepted from the client.

Borrower preferences remain requestable only where the product allows them, including requested amount/limit, term, payment frequency, fixed/variable preference, down-payment preference, balloon percentage, and interest-only preference. Lease requests reject credit-only fields.

## 2. Deterministic origination plan

Added:

- `src/finance/OriginationPlanService.lua`
- `tests/offline_origination_plan_tests.lua`
- `docs/ORIGINATION_PIPELINE.md`

The pure origination planner converts a server-approved quote/facility decision into a deterministic plan before any authoritative mutation.

Term/asset-finance plans include:

- proposed liability terms;
- dated contract schedule;
- rate term and maturity;
- interest-only/balloon fields;
- cash equity vs financed amount;
- security mode;
- specific lien plan for vehicle/placeable/farmland collateral;
- retained underwriting conditions/manual-review status.

Revolving plans include:

- approved limit;
- zero starting principal;
- rate;
- general-security plan;
- borrowing-base constrained effective limit;
- optional CILOC season/cleanup assessment.

Credit outcomes are gated:

- `decline` cannot originate;
- `refer` requires an explicit manual/server approval flag;
- approve-with-conditions carries its conditions into the close plan.

## 3. Seasonal farm liquidity projection

Added:

- `src/credit/LiquidityProjectionService.lua`
- `tests/offline_liquidity_projection_tests.lua`
- `docs/SEASONAL_LIQUIDITY_MODEL.md`

The service models period-by-period agricultural cash flow and can optionally forecast use of a defined operating-credit backstop.

It reports:

- cash before/after financing;
- modeled line draws/repayments;
- peak line utilization;
- ending line balance/availability;
- lowest projected cash;
- periods/value of unmet liquidity shortfall;
- overall liquidity adequacy.

This allows future underwriting to distinguish a normal seasonal working-capital need from an operation that remains underfunded even after available credit.

Any modeled auto-draw/repayment behavior is a forecast assumption only; runtime settlement authorization remains separately gated.

## 4. Collateral lending value separated from market value

Added:

- `src/credit/CollateralValuationService.lua`
- `tests/offline_collateral_valuation_tests.lua`
- `docs/COLLATERAL_LENDING_VALUE.md`

The underwriting model now keeps market value, policy eligibility, advance rate, and prior claims separate.

This prevents AgForward from repeating the donor-mod mistake of treating every apparently owned asset as fully available/unencumbered collateral.

No real-lender advance rates are hardcoded; policy inputs remain fictional/configurable until FS25 economics can be calibrated.

## 5. Whole-farm stress testing

Added:

- `src/credit/CreditStressService.lua`
- `tests/offline_credit_stress_tests.lua`
- `docs/CREDIT_STRESS_TESTING_MODEL.md`

The service can apply configurable shocks to asset/collateral value, cash available for debt service, obligations, liquid assets, undrawn credit, and revolving utilization. It can also stress seasonal liquidity assumptions such as crop receipts, input costs, debt service, and available operating-line capacity.

The engine calculates stressed results but does not embed approval thresholds.

## 6. Payment frequency and exact debt-service measurement

Updated:

- `src/credit/CreditProfileBuilder.lua`
- `tests/offline_credit_profile_tests.lua`
- `docs/FINANCIAL_CONVENTIONS.md`

The profile builder no longer assumes every scheduled payment is monthly when explicit contract frequency exists. Annual, semi-annual, quarterly, and monthly schedules are now distinguished.

Added:

- `src/credit/DebtServiceWindowService.lua`
- `tests/offline_debt_service_window_tests.lua`
- `docs/DEBT_SERVICE_WINDOW_MODEL.md`

The exact window service measures the principal, interest, balloon, fees, and total cash debt service actually due in the next selected FS financial periods. This is a better eventual DSCR/pro-forma source than multiplying one generic payment.

## 7. CILOC crop-input budget tracking

Added:

- `src/credit/CILOCBudgetService.lua`
- `tests/offline_ciloc_budget_tests.lua`
- `docs/CILOC_BUDGET_TRACKING.md`

The service tracks planned vs actual crop-input spending and the financed share by category while retaining the underlying expense purpose.

It supports:

- seed/fertilizer/lime/crop-protection/fuel/other-input budgets;
- optional per-category financed caps;
- soft over-budget variance reporting;
- optional hard category/financed-budget enforcement;
- explicit handling of eligible but unbudgeted categories;
- immutable preflight projections.

Budget capacity remains distinct from the authoritative facility limit/borrowing base.

## 8. Read-only Phase-0 diagnostic view model

Added:

- `src/reporting/DiagnosticSnapshotService.lua`
- `tests/offline_diagnostic_snapshot_tests.lua`
- `docs/PHASE0_DIAGNOSTIC_VIEW_MODEL.md`

The first future in-game finance/status page can now be backed by a pure snapshot containing runtime state, safe-mode reason, persistence/schema/generation information, overlaps, Red Tape status, liabilities, recent ledger activity, and settlement markers without owning any financial truth.

A test-only class stub problem was discovered by CI and corrected; the service itself remains offline/unpromoted.

## 9. Runtime package promotion is now explicit

Reworked:

- `tools/build_mod_package.py`
- `tests/test_package_builder.py`
- CI package-build step

Added:

- `docs/RUNTIME_PACKAGE_PROMOTION.md`

A repository ZIP is no longer treated as a runtime candidate. The builder packages only explicitly promoted `modDesc.xml` sources/localization/resources plus optional files in a controlled runtime manifest.

This lets the offline branch grow without silently shipping every experimental `src/` file to FS25.

## 10. Future save schema designed but not promoted

Added:

- `docs/SAVE_SCHEMA_V4_DESIGN.md`

The design covers eventual persistence for assets, rights, liens, leases, external obligations, contract details, snapshots, and minimal non-derived credit state while preserving schema-v3 dual-copy recovery/safe-mode guarantees.

Runtime schema remains **v3**. No v4 implementation is authorized until schema-v3 is proven in FS25.

## 11. Finance stress coverage expanded

`tests/offline_finance_stress_tests.lua` was cleaned and added to CI.

It runs deterministic matrices across:

- standard amortization;
- annual/semi-annual/quarterly/monthly frequencies;
- zero through high positive rates;
- balloons;
- interest-only then amortizing structures;
- rate-term renewal balances;
- unified quote/down-payment combinations.

Core invariants include exact cent-level principal reconciliation, zero ending balance at maturity, non-negative components, row totals matching schedule totals, and correct renewal principal at shorter rate terms.

## 12. Security path now forms a coherent future runtime sequence

The intended flow is now explicitly:

`Client intent`
→ `server farm/context resolution`
→ `credit profile`
→ `server pricing/quote`
→ `pro-forma underwriting`
→ `server offer`
→ `offer acceptance request`
→ `runtime revalidation`
→ `pure origination plan`
→ `one coordinated authoritative close`
→ `operation ID + new state revision`

This substantially reduces the amount of transaction design that will need to be invented while debugging live FS25 hooks.

## Current runtime boundary

Still blocked until in-game proof:

1. GIANTS XML/file persistence and recovery behavior;
2. Red Tape save-hook coexistence;
3. actual FS MoneyType/FinanceStats behavior;
4. purchase interception before affordability finalization;
5. stable collateral keys/relinking;
6. live server/client event serialization and dedicated-server behavior;
7. atomic close across FS purchase + AgForward liabilities/ledger/liens;
8. schema promotion for the newer offline registries.

The `phase0-foundation-hardening` branch remains the first runtime persistence candidate. The offline branch should not be merged wholesale merely because pure-model CI succeeds.
