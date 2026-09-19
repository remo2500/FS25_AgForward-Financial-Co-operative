# AgForward Crop Input LOC Facility Review

**Status:** offline underwriting/reporting foundation  
**Runtime enabled:** NO

## Purpose

A Crop Input Line of Credit cannot be understood from a single balance number. AgForward needs to see the relationship among:

- contractual line limit;
- seasonal borrowing base;
- current principal;
- temporarily reserved capacity;
- input budget and actual spend;
- category-level financed caps;
- cleanup/maturity state.

`src/credit/CILOCFacilityReviewService.lua` combines those existing pure models into one read-only facility review.

## Effective line capacity

The contractual limit and borrowing base remain distinct.

When a borrowing base is present:

`effective limit = min(contractual limit, borrowing base)`

Used capacity is:

`principal + active reservations`

The seasonal service then determines numerical capacity, whether draws are frozen by cleanup/maturity policy, and the resulting available capacity.

The review never treats a management budget as the legal credit limit.

## Input-budget view

When a `CILOCBudgetService` state is supplied, the review reports:

- total planned crop-input budget;
- actual input spend;
- CILOC-financed spend;
- cash/other-funded spend;
- remaining or over-budget amount;
- budget utilization;
- financed share of actual spend;
- explicit per-category financed caps and remaining cap;
- number of unbudgeted categories used;
- number of categories over budget.

This provides an agricultural operating view without altering the underlying seed/fertilizer/fuel/etc. ledger categories.

## Borrowing-base view

The review may accept either:

- an already-authoritative borrowing-base amount; or
- crop/acres/budget rows plus a policy, in which case `CILOCBorrowingBaseService` calculates the projected base.

The second path is useful for underwriting/renewal. A future live facility should use only server-derived authoritative inputs.

## Season / cleanup view

The integrated result includes the full `CILOCSeasonService` output:

- active season / cleanup window / matured;
- periods to maturity;
- effective limit;
- over-limit amount;
- base available capacity;
- draw freeze;
- cleanup target;
- required cleanup paydown;
- cleanup satisfaction;
- renewal requirement.

A line can therefore show unused numerical capacity but **zero available capacity** if the facility is in a policy-defined cleanup window with new draws frozen.

## Attention items

The pure review emits transparent flags/items instead of making a lending decision:

- over effective limit;
- cleanup paydown required;
- maturity renewal/paydown required;
- overall input-budget overrun;
- financed-category cap overrun;
- eligible but unbudgeted input spending.

Approval/waiver decisions belong to credit policy/server authority, not this calculation service.

## Relationship to live purchase authorization

The review is not sufficient to approve a transaction. A future live CILOC-funded purchase still needs:

1. eligible economic-purpose classification;
2. current server farm/permission check;
3. category-budget policy check if configured;
4. borrowing-base / facility-capacity check;
5. reservation against concurrent requests;
6. season/cleanup eligibility;
7. pre-affordability FS25 purchase integration;
8. atomic liability + ledger + FS cash/purchase commit.

A report showing available capacity is therefore informational until the actual server operation revalidates all conditions at commitment time.

## Runtime gate

The facility review does not persist state, authorize draws, create reservations, or move money. It remains an offline/read-only model until the Phase-0 runtime foundation is proven.
