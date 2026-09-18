# AgForward Servicing Review Model

## Purpose

`AGFServicingReviewService` is a pure, read-only review layer for existing liabilities.

It does **not**:

- collect a payment;
- change a loan status;
- approve a renewal;
- accelerate a loan;
- start collections or repossession;
- mutate covenant state.

Its job is to combine contractual dates and existing monitoring state into one deterministic review packet.

## Inputs

The service accepts:

- the current liability record;
- an optional dated contract schedule;
- an optional delinquency account state;
- an optional covenant review;
- the current FS financial year/period;
- configurable payment, renewal, and maturity look-ahead windows.

## Output

The result includes:

- current principal, accrued interest, fees, and total outstanding;
- next scheduled payment date/amount;
- rate-term renewal date and renewal principal;
- maturity date and balloon amount;
- delinquency summary;
- covenant summary;
- deterministic review reasons;
- `current`, `upcoming`, `review`, `urgent`, or `closed` servicing-view status.

The status is a workflow signal only. It is not a credit decision or automatic enforcement action.

## Important boundary

A covenant exception and a delinquency event remain separate concepts.

Examples:

- a farm may be fully current on payments while a DSCR covenant requires review;
- a farm may be past due with all financial covenants otherwise satisfied;
- a rate renewal can be approaching while the facility remains current.

This separation is intentional so later UI and server workflows do not turn informational monitoring into automatic default or denial.

## Runtime gate

The service is offline-only until AgForward has persistent dated contract schedules and authoritative runtime delinquency/covenant state.
