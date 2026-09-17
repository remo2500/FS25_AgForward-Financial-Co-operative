# AgForward Offline Development Update — 2026-09-17

**Branch:** `offline-foundations`  
**Base runtime candidate:** `phase0-foundation-hardening`  
**Runtime validation:** still pending

## Purpose of this pass

Continue useful development without weakening the runtime gate. This pass focused on the missing seam between borrower intent, server underwriting/quotes, accepted offers, and eventual liability creation, plus seasonal farm liquidity analysis.

No live FS25 money movement, purchase interception, save-schema expansion, multiplayer event serialization, land-access mutation, or Red Tape tax injection was enabled.

## 1. Client application intent is now explicitly non-authoritative

Added:

- `src/network/FinancialApplicationIntentService.lua`
- `tests/offline_application_intent_tests.lua`

The service defines exactly what a future client may request versus what the server must derive.

Client-supplied fields such as the following are rejected:

- `farmId`;
- `annualRate` / APR / quote;
- approval/decision status;
- state revision;
- credit limit;
- principal balance;
- scheduled payment/total interest;
- collateral/appraised value.

Farm identity comes from the server connection context. Asset-finance purchase price and context fingerprints also come from server-resolved purchase context.

Borrower preferences remain requestable where the product allows them, including requested amount/limit, term, payment frequency, fixed/variable preference, down-payment preference, balloon percentage, and interest-only period preference.

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

## 4. Finance stress coverage expanded

`tests/offline_finance_stress_tests.lua` was cleaned and added to the CI plan.

It runs deterministic matrices across:

- standard amortization;
- annual/semi-annual/quarterly/monthly frequencies;
- zero through high positive rates;
- balloons;
- interest-only then amortizing structures;
- rate-term renewal balances;
- unified quote/down-payment combinations.

Core invariants include exact cent-level principal reconciliation, zero ending balance at maturity, non-negative components, row totals matching schedule totals, and correct renewal principal at shorter rate terms.

## 5. Security path now forms a coherent future runtime sequence

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
