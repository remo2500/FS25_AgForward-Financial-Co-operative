# AgForward Server-Authoritative Origination Pipeline

**Status:** offline architecture / future runtime contract  
**Runtime enabled:** NO  
**Branch:** `offline-foundations`

## Purpose

AgForward needs one secure path from a player's financing request to an authoritative liability. The path must prevent a multiplayer client from supplying its own farm identity, interest rate, approval status, payment amount, collateral value, or credit limit.

This document joins the existing credit, quote, offer, collateral, and protocol foundations into one origination sequence.

## Governing principle

The client expresses **intent and preferences**. The server supplies **facts and authority**.

Client-controlled examples:

- requested product;
- requested amount or line limit;
- desired term/payment frequency;
- preferred fixed/variable structure;
- desired down payment;
- optional balloon/interest-only preferences where the product permits them.

Server-authoritative examples:

- borrower farm identity and permissions;
- current financial-state revision;
- purchase/asset price;
- asset/context identity;
- collateral value;
- credit metrics and underwriting decision;
- base rate, spreads, contract rate, payment, and total interest;
- approved principal/limit;
- lien/security requirement;
- resulting liability, ledger, cash movement, and state revision.

## Stage 1 — application intent sanitization

`src/network/FinancialApplicationIntentService.lua`

The sanitizer:

1. derives farm identity from server context;
2. validates that the requested product exists;
3. rejects client-supplied authoritative fields such as `farmId`, `annualRate`, `quote`, `decisionStatus`, `creditLimit`, and `collateralValue`;
4. validates product capabilities;
5. normalizes borrower preferences;
6. injects server-resolved purchase price/context for asset financing.

Asset-finance applications therefore cannot replace the server's equipment/building/land price with a client-supplied value.

## Stage 2 — current borrower profile

Server builds the farm's current credit profile from authoritative state:

- AgForward liabilities;
- external/base-game obligations;
- assets and eligible collateral;
- liens;
- lease/fixed-charge obligations;
- liquidity and working capital;
- historical/forecast operating information when available.

Relevant modules:

- `CreditProfileBuilder.lua`
- `CreditMetrics.lua`
- `ExternalObligationRegistry.lua`
- asset/right/lien registries.

## Stage 3 — pricing and quote

The server applies current pricing policy and borrower risk to produce a quote.

Relevant modules:

- `RatePricingService.lua`
- `LoanQuoteService.lua`
- `AmortizationService.lua`
- `StructuredAmortizationService.lua`
- `PaymentFrequencyService.lua`
- `RateTermRenewalService.lua`.

The quote is a calculation snapshot, not yet a liability.

## Stage 4 — pro-forma underwriting

The proposal is added to current farm obligations/assets in a non-mutating projection.

Relevant modules:

- `ProFormaUnderwritingService.lua`
- `CreditPolicyService.lua`
- `LiquidityProjectionService.lua` for seasonal liquidity analysis where used.

Possible outcomes:

- `approve`;
- `approveWithConditions`;
- `refer`;
- `decline`.

A referred application cannot silently become a loan. Future runtime code must require an explicit server/manual-approval state before origination.

## Stage 5 — server financial offer

Approved/conditionally approved/manual-approved terms are placed in a short-lived server offer.

`FinancialOfferService.lua` binds the offer to:

- server-resolved farm;
- connection;
- state revision;
- product;
- quote;
- underwriting status;
- policy/pricing versions;
- context fingerprint;
- optional expiry period.

The client receives a read-only offer and later sends only an `offerId` plus idempotent request metadata when accepting.

## Stage 6 — deterministic origination plan

`src/finance/OriginationPlanService.lua`

Before any runtime mutation, the server converts the accepted offer into a deterministic plan.

For term/asset products the plan includes:

- liability terms;
- dated payment schedule;
- rate term and maturity;
- interest-only/balloon terms where applicable;
- down payment and financed amount;
- security mode;
- specific lien attachment where required;
- credit decision and unresolved conditions.

For revolving products the plan includes:

- approved line limit;
- starting undrawn balance;
- effective borrowing-base constrained limit;
- rate;
- general security mode;
- optional CILOC season/cleanup state.

The plan remains pure. It does not create authoritative records.

## Stage 7 — runtime revalidation

Immediately before closing, future server runtime code must revalidate facts that may have changed since offer creation:

- player/farm permission;
- state revision;
- asset/store/farmland availability;
- server purchase price;
- context fingerprint;
- cash required for down payment/fees;
- collateral ownership and prior liens;
- approved credit still available;
- offer has not expired/been consumed.

Any mismatch returns a structured failure/new-quote result. The server must not accept corrected APR/payment/price values from the client.

## Stage 8 — coordinated close

Only after all gates pass does the future live operation coordinator atomically perform the required authoritative changes:

1. FS25 cash/purchase action;
2. AgForward liability creation;
3. asset record/right creation or update;
4. lien creation where required;
5. principal/fee/expense ledger entries;
6. settlement schedule state;
7. offer consumption;
8. state revision increment;
9. multiplayer result/delta publication.

Failure must either leave all authoritative state unchanged or run a tested compensating rollback. A partial close is unacceptable.

## Product-specific security modes

Current offline catalog intent:

- Operating Line — general farm security;
- Crop Input Line — general farm security + purpose restrictions/seasonal policy;
- General Term Loan — general farm security;
- Equipment Finance — specific vehicle/equipment lien;
- Project Finance — specific placeable/project lien;
- Land Finance — specific farmland lien;
- Land Lease — separate lease workflow, not debt origination.

These are fictional AgForward product rules and can be recalibrated later without changing the shared origination architecture.

## Offline validation

Current tests include:

- `offline_application_intent_tests.lua` — rejects authoritative client inputs and validates product-specific request shapes;
- `offline_origination_plan_tests.lua` — validates loan/revolver plans, security modes, manual-review gating, CILOC borrowing-base limits, and closing-source reconciliation;
- existing offer/protocol tests — offer binding, state revision, request idempotency, and stale-state behavior.

## Runtime gate

No code in this pipeline currently:

- moves FS25 money;
- creates real liabilities from client requests;
- intercepts dealer/construction/land purchases;
- serializes multiplayer finance events;
- creates live liens;
- consumes Red Tape data.

Those actions remain blocked until the Phase-0 persistence/recovery and multiplayer/runtime boundaries are proven in FS25.
