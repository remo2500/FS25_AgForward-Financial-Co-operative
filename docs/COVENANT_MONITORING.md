# AgForward Credit Covenant Monitoring

**Status:** offline servicing / annual-review foundation  
**Runtime enabled:** NO

## Purpose

Origination underwriting and ongoing loan monitoring are different activities.

An existing borrower can temporarily fall outside a financial condition without that automatically meaning the loan is cancelled, accelerated, or repossessed. AgForward therefore keeps covenant/condition monitoring separate from the origination approval engine and from delinquency/recovery.

`src/credit/CovenantMonitoringService.lua` provides a pure configurable monitor.

## Supported rule structure

A covenant/monitoring rule identifies:

- metric name;
- comparator (`min`, `max`, `gt`, `lt`, `eq`, `ne`);
- threshold/value;
- severity (`warning` or `breach`);
- missing-data behavior (`warning`, `breach`, or `ignore`);
- optional message/metadata.

The service contains no fixed AgForward thresholds. Product policy supplies the rules.

## Example metrics

Future policy may monitor values such as:

- DSCR;
- fixed-charge coverage;
- debt-to-assets;
- LTV;
- working capital;
- liquidity coverage;
- revolving-line utilization;
- CILOC cleanup satisfaction;
- required insurance/asset-link status where represented by an authoritative boolean/value.

These are examples only; the current service accepts any supplied named value.

## Review outcomes

The monitor reports:

- passed rules;
- warnings;
- breaches;
- missing values;
- overall status (`compliant`, `warning`, `breach`, `incomplete`);
- whether human/policy review is required.

A `breach` result is **not** an automatic default/recovery event. A later servicing policy must determine whether the appropriate consequence is a waiver, condition, repricing, reduced availability, renewal review, cure period, or another action.

## Review-to-review comparison

`compareReviews()` identifies:

- new exceptions;
- cured exceptions;
- continuing exceptions.

That supports a future annual-review/history screen without requiring AgForward to treat a metric threshold as a missed payment.

## Missing data

AgForward does not invent covenant metrics when underlying data is unavailable.

A covenant can explicitly treat missing data as:

- warning;
- breach/required information;
- ignored for consequence purposes while still documenting the review as incomplete.

This is important while external debt, historical operating data, and runtime asset links may be only partially represented.

## Relationship to other AgForward systems

- **CreditPolicyService** — origination/renewal decision rules.
- **CovenantMonitoringService** — ongoing compliance/exception monitoring.
- **DelinquencyStateMachine** — payment delinquency lifecycle.
- **CILOCSeasonService** — seasonal cleanup/maturity behavior.
- **CreditStressService** — hypothetical downside scenarios.

These should remain distinct so one type of issue does not silently trigger another system's consequences.

## Runtime gate

No covenant rule currently:

- changes a credit limit;
- freezes a line;
- charges a fee;
- changes an interest rate;
- marks a loan delinquent/defaulted;
- starts collections/recovery.

Any future automated consequence must be a separately authorized, server-side policy with clear audit history and runtime tests.
