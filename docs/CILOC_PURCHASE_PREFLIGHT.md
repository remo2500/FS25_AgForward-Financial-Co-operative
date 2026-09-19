# AgForward Crop Input LOC Purchase Preflight

**Status:** offline purchase-integration foundation  
**Runtime enabled:** NO

## Purpose

The user's core CILOC requirement is that an eligible crop input can be financed at the point of purchase while still being recorded by its true economic purpose — seed, fertilizer, lime, crop protection, fuel, etc.

That requires more than a generic post-purchase loan draw. AgForward must decide funding **before** FS25 makes its final affordability/commit decision.

`src/input/CILOCPurchasePreflightService.lua` now joins the existing pure components into one non-mutating purchase plan.

## Inputs

The preflight can receive:

- authoritative farm ID;
- purchase amount;
- currently available cash;
- requested funding policy;
- MoneyType;
- fill-type/caller purchase context;
- authoritative Crop Input LOC liability;
- current integrated facility review;
- optional crop-input budget state/policy;
- context fingerprint for the exact purchase session/object.

## Sequence

1. Classify economic purchase purpose through `PurchaseClassificationService`.
2. Determine whether that category is CILOC-eligible.
3. Allocate cash vs line contribution through `FundingDecisionService`.
4. If credit is required, revalidate the liability is the correct farm's active revolving CILOC.
5. Revalidate current facility availability and cleanup/draw-freeze state.
6. Project category-budget impact if a budget is supplied.
7. Project facility utilization after the requested reservation.
8. Produce a **reservation intent**, not a real reservation.
9. Produce expected ledger intents for the future coordinated transaction.

No state is committed by this service.

## Example — fully financed fertilizer

Purchase:

- fertilizer = $30,000;
- cash contribution = $0;
- CILOC contribution = $30,000.

Preflight output concept:

- category = `fertilizer`;
- reservation intent = $30,000 against the CILOC;
- ledger intent 1 = `creditDraw +30,000`;
- ledger intent 2 = `inputPurchase -30,000`, category `fertilizer`;
- immediate net cash effect = $0;
- linked transaction-group economic net = $0;
- budget actual spend += $30,000;
- budget financed spend += $30,000.

## Example — partial funding

Purchase = $30,000 with `CASH_SHORTFALL_ONLY`, $10,000 available cash:

- cash contribution = $10,000;
- CILOC contribution = $20,000;
- expense remains fertilizer = $30,000;
- immediate cash effect = -$10,000;
- liability draw = +$20,000.

The funding source therefore never replaces the expense category.

## Unclassified or ineligible materials

A generic `BOUGHT_MATERIALS` transaction with no usable fill-type/caller context is not guessed into a CILOC category.

If enough cash exists, the preflight may allow the transaction to remain cash-funded with no CILOC draw/reservation.

If the purchase cannot be afforded with cash and its economic purpose cannot be proven eligible, AgForward does not use CILOC capacity to rescue the transaction.

## Cleanup / maturity

Raw numerical headroom is not sufficient by itself. If the facility review reports new draws frozen during a seasonal cleanup/maturity window, a line-funded purchase is rejected by preflight even if the contractual/effective limit has unused numerical capacity.

## Budget behavior

If a crop-input budget is active:

- the full purchase amount increases actual category spend;
- only the line-funded portion increases financed category spend;
- cash-funded eligible purchases still count against the operating budget;
- configured hard category or financed caps can reject the preflight before any reservation is made;
- soft policies can allow the purchase while reporting the variance.

## Future live runtime sequence

The eventual live server path should be:

`FS purchase context captured`
→ `CILOC purchase preflight`
→ `create short-lived credit reservation`
→ `revalidate exact purchase price/context before commit`
→ `allow/perform FS purchase`
→ `coordinated credit draw + ledger expense + budget update`
→ `consume reservation`
→ `publish authoritative state delta`

Failure before commit releases/avoids the reservation. Failure during the coordinated close must either roll everything back or place the financial system into the appropriate safe state; partial debt/expense/purchase state is unacceptable.

## Runtime gate

This module currently does **not**:

- intercept FS25 purchase code;
- create a live reservation;
- change farm cash;
- increase CILOC principal;
- post ledger entries;
- persist crop-input budgets;
- send multiplayer events.

Those remain blocked until the Phase-0 runtime/persistence and purchase-hook behavior are verified in game.
