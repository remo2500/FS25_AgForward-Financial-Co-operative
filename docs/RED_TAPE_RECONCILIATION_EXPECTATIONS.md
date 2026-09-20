# AgForward Red Tape Reconciliation Expectations

## Purpose

`AGFRedTapeReconciliationExpectationService` converts AgForward ledger movements into an auditable expectation list using the existing semantic `MoneyMovementIntent` contract.

It does **not** call Red Tape, register a MoneyType, create a tax line item, or decide tax deductibility.

## Treatment classes

Each mapped movement is assigned one of the existing integration treatments:

- `ignoreTax` — financing movements such as loan proceeds and principal repayment must not become operating income/expense;
- `nativeReconcile` — AgForward expects the native FS purchase/interest movement to be observed and later reconciled against Red Tape;
- `supplementIfMissing` — candidate for a future adapter only if runtime proof shows the movement is otherwise omitted;
- `externalAuthority` — Red Tape or another external government-policy system remains authoritative.

Unknown transaction types remain explicit unresolved rows. They are never guessed into a tax treatment.

## Why this matters

The donor-mod audit showed that full finance payments can be misclassified if principal, interest, and fees are collapsed into one MoneyType. This expectation layer makes those reconciliation requirements visible before any production Red Tape bridge is enabled.

`safeToAutoInject` is intentionally always false in the offline model.
