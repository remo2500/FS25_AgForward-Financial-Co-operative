# AgForward Debt Service Window Model

**Status:** offline underwriting foundation  
**Runtime enabled:** NO

## Purpose

Annualizing a loan by multiplying one scheduled payment can be wrong when a farm has:

- annual, semi-annual, or quarterly payments;
- an interest-only phase;
- a maturity balloon;
- scheduled financing fees;
- a loan whose maturity occurs inside the next year.

`src/credit/DebtServiceWindowService.lua` calculates debt service from the exact dated contract rows that fall inside an underwriting horizon.

## Default underwriting window

The intended default is the next **12 FS financial periods** starting with the current/as-of financial period.

For every payment actually due inside that window, the service aggregates:

- interest;
- regular principal;
- balloon/maturity principal;
- scheduled fees;
- total cash debt service.

It also returns per-contract totals and chronological payment rows.

## Why this improves the credit model

A quarterly $15,000 payment is four annual payments, not twelve.

An annual loan with no payment due in the next six periods should not be treated as though a monthly payment is due.

A balloon maturing in the underwriting window must be visible as a real liquidity/debt-service burden.

An interest-only payment contributes interest but no scheduled principal.

This makes future DSCR/pro-forma analysis more faithful to the actual AgForward contract schedule.

## Validation rule

When a schedule row contains `totalPayment`, it must reconcile to:

`interest + regular principal + balloon principal`

Scheduled fees are tracked separately and added to total cash due. A mismatched row is rejected rather than silently incorporated into underwriting.

## Relationship to the current credit-profile builder

The current profile builder still needs a compatibility path for schema-v3 liabilities, which store a monthly-style `scheduledPayment` and `remainingTermMonths` structure.

It has now been made payment-frequency aware when explicit contract metadata is available. After future contract persistence is promoted, exact schedule-window debt service should become the preferred source and the legacy annualization fallback should remain only for older/migrated obligations.

## External debt

External obligations may not expose a full payment schedule. Their verified/estimated annual debt-service figures can remain a separate input until a reliable dated schedule is available.

Data quality should reflect that distinction rather than inventing payment dates.

## Runtime gate

This service performs no payment collection and no settlement. It is an underwriting/reporting calculation only.
