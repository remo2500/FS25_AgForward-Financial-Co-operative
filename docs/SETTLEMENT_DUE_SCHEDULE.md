# AgForward Settlement Due Schedule

## Purpose

`AGFSettlementDueScheduleService` extracts contract rows that are scheduled in one FS financial period and converts them into inputs compatible with the existing pure `SettlementPlanner`.

It does not move cash, mutate an agreement, mark a payment missed, or decide final production policy.

## Loan rows

For each due loan row it preserves:

- scheduled principal;
- scheduled interest;
- balloon principal;
- total scheduled payment;
- payment number;
- rate-renewal marker.

The row must reconcile exactly:

`total payment = scheduled principal + scheduled interest`

## Lease rows

Lease schedules contribute the contracted rent due in the selected period.

Accrued fees, arrears, cures, and other live balances are deliberately not inferred from the contract schedule.

## Policy decoration

The service accepts configurable planner policy for:

- priority;
- partial-payment permission;
- minimum payment amount/percentage;
- optional-credit permission.

Defaults are conservative: full payment, no partial payment, and no optional-credit draw.

## Critical runtime boundary

Every produced row is marked as requiring authoritative balance reconciliation.

At runtime, scheduled contract values must be reconciled with actual accrued interest/fees, prepayments, delinquency, and current liability/lease state before the central settlement coordinator can execute money movement.
