# Crop Input Line of Credit — Purchase Interception & Funding Design

**Status:** offline implementation design; live hooks intentionally not installed  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

This document turns the CILOC accounting concept into a runtime integration design without yet touching Farming Simulator money movement.

## 1. Objective

A crop-input purchase funded by the CILOC must preserve both facts:

- **what was purchased** — seed, fertilizer, lime, crop protection, fuel, etc.;
- **how it was funded** — cash, CILOC, or a split.

The funding decision must occur early enough that credit can satisfy an affordability check. Observing `Farm.changeBalance` only after a purchase is charged is not sufficient when cash alone is inadequate.

## 2. Purchase context

The funding/classification layer should receive the richest available context before commitment:

```text
farm / acting connection
amount
MoneyType / statistic
fillType
purchase source / object
purchase mode (store fill, silo material, helper consumption, etc.)
explicit AgForward caller context if present
```

The existing `PurchaseClassificationService` should remain conservative:

- precise MoneyType may classify seed/fuel directly;
- fill type may distinguish fertilizer/lime/herbicide from generic material purchasing;
- generic `BOUGHT_MATERIALS` without fill-type/context is not guessed.

## 3. Funding policies

Pure allocation logic is implemented in `src/input/FundingDecisionService.lua`.

### Off

No CILOC funding. Full purchase must be supported by cash.

### Cash shortfall only

Use available cash first; draw only the amount needed to complete the eligible purchase.

Example:

- purchase = 30,000;
- cash = 12,000;
- line available = 100,000;
- cash contribution = 12,000;
- CILOC draw = 18,000.

### Prefer line

Use CILOC first, then cash if the line cannot cover the full eligible purchase.

Example:

- purchase = 30,000;
- line available = 20,000;
- cash available = 15,000;
- line = 20,000;
- cash = 10,000.

### Always line

Eligible purchase must be fully funded from the CILOC. If sufficient line availability does not exist, the transaction is rejected rather than silently using cash.

This makes the policy predictable and avoids hidden funding-source changes.

## 4. Pre-authorization / reservation

Before an eligible financed purchase reaches the final FS affordability/money step, AgForward should reserve the required line amount.

A reservation should contain:

```text
reservationId
farmId
liabilityId
purchase context fingerprint
reserved amount
created revision/period
expiry/consumption state
```

Reservation behavior:

1. validate CILOC active/borrower/limit;
2. classify purchase purpose;
3. calculate funding split;
4. reserve required line capacity;
5. permit the purchase path to continue;
6. on successful purchase, convert reservation into committed draw + purchase accounting;
7. on cancelled/failed purchase, release reservation;
8. expire abandoned reservations safely.

Available line for new requests should be:

`credit limit - principal balance - active reservations`

This prevents two concurrent purchases from both passing the same remaining-credit check.

## 5. Actual cash movement model

The cleanest full-line example is:

1. AgForward CILOC draw increases farm cash by 30,000 using a financing-classified MoneyType/statistic that is not operating income.
2. The normal FS purchase decreases farm cash by 30,000 using the purchase's normal material/input classification.
3. Net immediate cash change is zero.
4. AgForward liability principal increases by 30,000.
5. AgForward ledger records linked financing and fertilizer/seed/etc. expense-purpose entries.

For split funding, AgForward adds only the line contribution to cash; the normal purchase then spends the full amount, reducing the farm's own cash by the cash-contribution portion.

This preserves both game affordability and accounting meaning.

## 6. Operation ordering

Live execution must be coordinated so a partial failure cannot leave free cash or orphan debt.

Target operation stages:

1. server permission + state-revision validation;
2. classify purchase;
3. calculate funding split;
4. reserve line capacity;
5. stage AgForward draw transaction/liability mutation;
6. add only required financing cash to the farm;
7. allow/perform underlying FS purchase debit;
8. confirm purchase succeeded;
9. commit linked ledger group and liability principal;
10. consume reservation;
11. emit authoritative multiplayer operation result.

If the underlying purchase fails after financing cash is staged, AgForward must reverse the financing cash and release the reservation rather than committing debt.

The exact hook sequence must be proven in FS25 before enabling this path.

## 7. High-frequency helper purchases

Helper consumption can generate many small seed/fertilizer/fuel charges. AgForward should not create two durable journal entries for every tiny charge.

The current `InputPurchaseAccumulator` provides a cent-exact aggregation foundation.

Recommended runtime behavior:

- classify and fund each underlying charge accurately;
- aggregate journal reporting by farm + category + funding source + liability + bounded time/session bucket;
- flush on defined boundaries such as helper stop, material-type change, period change, save, or monetary threshold;
- never allow aggregation to change the exact total cents drawn/spent.

The liability/cash position may need to update more frequently than durable reporting aggregation. The runtime design should distinguish **financial balance authority** from **reporting row granularity**.

## 8. Red Tape interaction

CILOC draw must not become taxable operating income.

Input purchase should retain the normal deductible/input category when Red Tape already observes it correctly.

Before production integration:

- define AgForward financing MoneyType/FinanceStats semantics;
- observe Red Tape handling of that MoneyType;
- reconcile seed/fertilizer/lime/crop-protection/fuel purchase paths;
- supplement Red Tape only when it cannot classify an event correctly;
- verify no duplicate tax line appears when Red Tape already observes the native purchase debit.

## 9. Multiplayer

CILOC funding decisions are server authoritative.

Client may request/select policy or display a quote, but server must derive acting farm and recheck:

- purchase eligibility;
- live CILOC availability including reservations;
- current cash;
- permissions;
- current purchase amount/context;
- current state revision.

Reservation and commit IDs should participate in the common multiplayer idempotency model.

## 10. Runtime research checklist

When testing becomes available, inspect each relevant purchase path and record:

- function/callback immediately before affordability validation;
- function/callback performing balance change;
- MoneyType/statistic passed;
- fill type/context available at that point;
- whether a purchase can be cancelled cleanly;
- whether a pre-credit balance change changes purchase behavior as expected;
- helper purchase cadence;
- Red Tape line-item result;
- dedicated-server behavior.

Do not activate automatic CILOC funding globally until each supported purchase path is individually proven.
