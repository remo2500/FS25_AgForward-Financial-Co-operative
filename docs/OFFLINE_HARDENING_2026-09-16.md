# AgForward Offline Hardening Update — 2026-09-16

**Branch:** `offline-foundations`  
**Base/runtime candidate:** `phase0-foundation-hardening`  
**Draft PR:** #2  
**Runtime status:** FS25 in-game validation still pending

## Purpose

This pass used the period when an FS25 runtime test was unavailable to reduce uncertainty in the parts of AgForward that can be checked deterministically under stock Lua/Python CI.

The runtime candidate branch was intentionally left unchanged. No live money movement, purchase interception, multiplayer mutation event, land-access change, Red Tape tax injection, or schema expansion was enabled.

## Hardened Phase-0 boundaries

### Save/recovery state machine

`tests/offline_save_service_tests.lua` now exercises the real `SaveService.lua` against an in-memory stand-in for the GIANTS XML/file API.

Covered cases:

- legitimate new financial state;
- recovery copy written before primary;
- identical generation on both successful copies;
- primary preferred when equivalent;
- newer recovery copy selected after an interrupted primary write;
- header-valid primary with record-load failure falls back to the older validated copy;
- unreadable primary falls back to recovery;
- no usable copy enters read-only safe mode;
- newer unknown schema blocks overwrite;
- pre-save integrity failure writes neither copy;
- multiplayer clients do not load local financial files.

These tests validate AgForward's state machine, not GIANTS filesystem/XML runtime behavior.

### Ledger mutation boundary

`Ledger.lua` was hardened so a new transaction cannot enter authority with:

- an invalid/non-positive/non-integral farm ID;
- a missing transaction type;
- non-finite amount/principal/interest/fee values;
- negative principal/interest/fee breakdown components.

Compensating batch rollback now preflights the **entire requested ledger suffix before removing anything**. A stale or incorrectly ordered rollback request therefore cannot partially delete journal history before failing.

`tests/offline_core_state_tests.lua` validates transaction sealing, defensive copies, batch prevalidation, atomic rollback, runtime authority, and ID behavior.

### Liability mutation boundary

`LiabilityRegistry.lua` now rechecks revolver lifecycle/capacity at committed draw time, not only during preflight.

Additional compensation/payment safeguards now include:

- exact draw reversion;
- rejection when a draw reversion exceeds principal instead of silently clamping debt to zero;
- rejection of normal principal payments on closed/charged-off liabilities;
- continued clipping of an oversized requested principal payment to the actual outstanding principal;
- public balance mutators remain blocked behind the operation coordinator.

`tests/offline_liability_tests.lua` covers draft/register ownership, defensive copies, farm/product indexes, draw preflight, committed draw/reversion, payment/payoff behavior, closed-state handling, and runtime authority.

### Coordinated operations and high-level accounting

`tests/offline_operation_tests.lua` now proves the Phase-0 CILOC operation boundary:

- one liability draw;
- one separately classified input expense;
- common group ID;
- economic group nets to zero;
- caller-returned records are copies;
- wrong farm/product/over-limit requests post nothing;
- debt-apply failure rolls back the journal batch;
- rollback failure enters safe mode.

`tests/offline_accounting_tests.lua` validates the higher-level API for:

- cash input purchases;
- CILOC-funded input purchases;
- operating-line-funded input purchases;
- economic purpose remaining separate from funding source;
- CILOC input-category eligibility;
- funding/product mismatch rejection;
- authority and amount validation.

### Purchase classification and high-frequency aggregation

`tests/offline_input_tests.lua` validates:

- explicit purchase context;
- seed/fuel/fertilizer MoneyType classification;
- lime/herbicide fill-type refinement;
- refusal to guess generic bought-material purpose without fill-type context;
- safe behavior when fill-type context is unavailable;
- cent-exact aggregation of high-frequency helper charges;
- separation by farm/category/funding source/liability;
- drain/reset behavior.

### Integrity gate

`IntegrityService.lua` now validates additional structural invariants before a loaded state is accepted or a save is written:

- known liability lifecycle status;
- finite/non-negative liability financial values;
- non-negative whole terms;
- remaining term not above original term where original term is known;
- valid year/financial-period markers;
- revolver balance not above limit;
- authoritative ledger records are sealed;
- non-negative transaction component breakdowns;
- valid transaction year/period markers;
- existing orphan-liability and linked-group reconciliation rules.

Unknown funding-source/expense-category labels remain warnings rather than fatal errors so descriptive taxonomy can be forward-compatible while structural financial truth stays strict.

### Runtime foundation behavior

`tests/offline_runtime_foundation_tests.lua` validates:

- Phase-0 settlement key/idempotency behavior;
- re-entrant settlement blocking;
- persisted completion marker but non-persisted in-progress marker;
- runtime authority checks;
- detection of known overlapping finance mods as warnings;
- Red Tape is not treated as a finance conflict;
- Red Tape remains `DEGRADED`/non-invasive in Phase 0 rather than injecting tax data prematurely.

### Persistent IDs

`IdService.lua` now normalizes non-finite/invalid counter values instead of allowing corrupt numeric counter state to propagate into future IDs.

## New payment-posting bridge

`src/finance/LiabilityPaymentPlanService.lua` is a pure, non-mutating bridge from payment allocation to future coordinated posting.

Given a liability and requested payment it derives:

- accepted payment;
- explicit unapplied overpayment;
- fees/interest/principal allocation;
- before/after component balances;
- exact journal intents for finance fees, interest, and principal;
- expense classification only where economically appropriate;
- payoff/remaining balance state.

It deliberately performs no FS cash movement and no liability mutation.

`tests/offline_payment_plan_tests.lua` validates default/alternate allocation orders, exact payoff, overpayment handling, pure/non-mutating behavior, journal intent classification, and lifecycle/zero-balance rejection.

## CI status

GitHub Actions run `35088434435` completed successfully after this hardening pass.

Every configured step passed, including:

- repository/XML validation;
- Python runtime-analysis-tool unit tests;
- Lua 5.1 syntax validation;
- core state/ledger tests;
- Phase-0 runtime-foundation tests;
- SaveService state-machine tests;
- native liability tests;
- coordinated operation tests;
- accounting tests;
- input classification/aggregation tests;
- integrity tests;
- finance/invariant tests;
- liability payment-plan tests;
- CILOC, credit-policy/profile, project/rate, asset/right/lien, protocol/delinquency, contract, and reporting suites.

This result is **offline validation only**. It must not be described as an FS25 runtime pass.

## What remains deliberately blocked pending runtime testing

1. Verify schema-v3 primary/recovery behavior using actual GIANTS XML/file functions.
2. Verify AgForward/Red Tape save-hook coexistence and callback order.
3. Verify actual FS MoneyType/FinanceStats behavior and Red Tape observation before enabling any adapter classification.
4. Prove purchase interception/authorization before cash affordability finalization.
5. Prove stable vehicle/placeable/farmland relinking across save/load/reset/customization.
6. Prove multiplayer initial snapshot, request validation, revision handling, reconnect, and dedicated-server behavior.
7. Only after those gates: promote additional asset/lease/credit state into persistence and begin real settlement/money movement.

## Promotion rule

Do not merge this branch wholesale simply because CI is green. Promote/select pure modules only after the Phase-0 runtime candidate has passed its persistence/recovery/coexistence tests, then advance the save schema deliberately when new authoritative registries are ready to persist.
