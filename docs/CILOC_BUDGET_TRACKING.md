# AgForward Crop Input Line Budget Tracking

**Status:** offline underwriting/reporting foundation  
**Runtime enabled:** NO

## Purpose

The Crop Input Line of Credit (CILOC) is intended to finance eligible crop-production costs while preserving each purchase's real economic purpose in the AgForward ledger.

Budget tracking adds a second, separate control layer:

- the **facility limit / borrowing base** answers how much credit may be outstanding;
- the **crop-input budget** answers what the farm expected to spend by input category and how actual/financed use compares with that plan.

A category budget must never be mistaken for the legal/authoritative credit limit.

## Offline service

`src/credit/CILOCBudgetService.lua`

The service tracks approved/planned budget rows for eligible crop-input categories:

- seed;
- fertilizer;
- lime / soil amendment;
- crop protection;
- fuel;
- other crop input.

Each category can contain:

- planned total spend;
- optional maximum financed spend;
- actual spend to date;
- CILOC-financed spend to date;
- remaining/over budget;
- remaining/over financed-category budget;
- purchase count;
- budget utilization;
- financed share.

## Purchase treatment

For a fertilizer purchase of $30,000 where $25,000 is funded through the CILOC and $5,000 from cash/another source, the budget layer records:

- fertilizer actual spend: +$30,000;
- fertilizer CILOC-financed spend: +$25,000;
- fertilizer other funding: $5,000.

This does not change the ledger principle:

- economic purpose = fertilizer;
- funding source = CILOC and/or cash;
- credit draw is not income;
- principal repayment is not expense.

## Soft versus hard budget policy

The pure service supports both approaches without locking a production rule yet.

### Soft management budget

An eligible purchase can exceed the planned category budget, but the overage is explicitly reported.

This is useful if the budget is primarily an underwriting/management forecast and the facility still has authorized capacity.

### Hard approved-category budget

A policy can reject a purchase allocation when the category budget would be exceeded.

A separate optional financed-category cap can also be enforced. For example, the farm might plan $100,000 of fertilizer but only $80,000 of that category may be CILOC-funded.

Production behavior must be chosen deliberately after runtime testing. The service currently exposes both outcomes rather than assuming one.

## Unbudgeted eligible categories

An otherwise eligible crop input that was not in the original budget can either:

- be accepted and flagged as an unbudgeted variance; or
- be rejected under a strict approved-budget policy.

This is intentionally different from an **ineligible** expense. Interest, taxes, land purchases, equipment, and other non-crop-input expenses do not become CILOC-eligible merely because credit is available.

## Relationship to other CILOC services

Budget tracking complements, but does not replace:

- `CILOCBorrowingBaseService` — calculates a policy borrowing-base limit;
- `CILOCSeasonService` — tracks seasonal/cleanup state;
- `FundingDecisionService` — future funding-source decision support;
- `CreditReservationService` — protects concurrent line capacity;
- `PurchaseClassificationService` — determines actual seed/fertilizer/fuel/etc. purpose;
- `InputPurchaseAccumulator` — aggregates high-frequency runtime charges;
- the liability registry — authoritative principal/available credit;
- the ledger — authoritative transaction history.

A future live purchase must satisfy **all** applicable controls. Passing a category budget check does not guarantee that facility capacity, seasonal policy, farm cash, or server authorization also pass.

## Immutability / preflight behavior

`applyPurchase()` returns a new projected budget state. Rejected requests leave the supplied state unchanged.

This makes the service suitable for:

- purchase preflight;
- quote/application scenarios;
- underwriting sensitivity checks;
- reporting;
- later server-authoritative commit planning.

The eventual authoritative budget state, if persisted, should only change through a coordinated server operation tied to the actual purchase/ledger group.

## Runtime gate

The current service does not:

- intercept an FS25 purchase;
- authorize a CILOC draw;
- reserve facility capacity;
- move cash;
- increase liability principal;
- post ledger transactions;
- persist the budget in schema v3.

Those remain gated behind the Phase-0 runtime tests and future persistence promotion.
