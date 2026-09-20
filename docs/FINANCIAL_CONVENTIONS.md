# AgForward Financial Conventions

**Status:** offline design authority for future Phase 1 loan math  
**Branch:** `offline-foundations`  
**Updated:** 2026-09-17

This document locks the mathematical conventions AgForward will use unless a later authority revision explicitly changes them. The goal is to remove ambiguity before term lending, operating credit, equipment finance, project finance, and land finance begin sharing the same amortization engine.

## 1. Currency

AgForward uses Farming Simulator-compatible numeric currency values, but every authoritative financial mutation is normalized to the nearest cent through `AGFCurrency`.

- Internal comparison boundary: integer minor units (cents).
- Persisted monetary amounts: numeric major-unit values rounded to cents.
- Rounding rule: half away from zero, matching `AGFCurrency.toMinorUnits()`.
- No product may introduce its own money tolerance such as `0.005`; use cent conversion/equality instead.

## 2. Interest-rate storage

Contract rates are stored as **annual nominal decimal rates**.

Examples:

- `0.0725` = 7.25% per year.
- `0.10` = 10.00% per year.
- `0` = interest-free.

Player-facing UI displays percentage values, but internal calculations use decimal rates.

Negative contract rates are not supported by the initial AgForward lending engine. No arbitrary maximum rate is imposed by the math layer; product/credit policy may impose limits separately.

## 3. FS financial periods and contractual payment frequency

AgForward uses the game's **12 financial periods per year** as its calendar. One FS monthly period is one AgForward calendar period regardless of how many gameplay days are configured inside that month.

A loan does **not** have to make a payment every FS financial period. Current pure models support these contractual payment frequencies:

- annual: `1` payment/year;
- semi-annual: `2` payments/year;
- quarterly: `4` payments/year;
- monthly: `12` payments/year.

Due dates are mapped onto the 12-period FS calendar. For example, quarterly payments are spaced every three financial periods.

For a scheduled term loan whose contract rate is an annual nominal rate and whose payment frequency is `m` payments/year:

`paymentPeriodicRate = annualNominalRate / m`

Therefore a 7.2% nominal annual rate uses:

- 7.2% per annual payment period;
- 3.6% per semi-annual payment period;
- 1.8% per quarterly payment period;
- 0.6% per monthly payment period.

This is the convention used by `AmortizationService` and the contract schedule services.

Revolving operating credit/CILOC is different: its current model accrues against utilization through each **monthly FS financial period** using `annualNominalRate / 12` and time-weighted balance changes within that period. A future daily-accrual convention must be introduced explicitly and must not silently alter existing agreements.

## 4. Amortizing payment convention

For:

- principal `P`;
- payment-period rate `r`;
- number of contractual payments `n`;
- contractual balloon balance `B` due at maturity;

AgForward quotes the regular payment by discounting the balloon and amortizing the remainder.

For `r > 0`:

`payment = (P - B / (1+r)^n) * r / (1 - (1+r)^(-n))`

For `r = 0`:

`payment = (P - B) / n`

The quoted regular payment is rounded to cents.

The balloon must be between zero and original principal for the initial engine. A bullet loan is represented by `balloon = principal`, which produces interest-only regular payments when the rate is positive and the full principal due at maturity.

## 5. Payment-period accrual and schedule rounding

For each contractual payment period:

1. Interest is calculated on the opening principal balance using the payment-period rate.
2. Interest is rounded to cents.
3. Regular principal is regular payment minus interest and is rounded to cents.
4. Principal may not fall below the contractual balloon before maturity.
5. In the final payment period, regular principal is adjusted to leave exactly the contractual balloon before the maturity balloon payment.
6. The balloon is then paid as a separate maturity principal component.
7. The final ending principal balance is exactly zero after the balloon payment.

This final-period adjustment prevents accumulated cent rounding from creating a residual or overpayment.

Negative amortization is not permitted by default. Any future product that deliberately allows capitalized interest must opt into a separate policy.

## 6. Interest-only phase

An interest-only phase is part of the stated total contractual payment count; it is not silently added to the end of the term.

Example:

- 60 total monthly payments;
- 12 interest-only payments;
- 48 remaining amortizing payments.

During the interest-only phase, scheduled principal is zero and the opening principal remains unchanged unless an explicit voluntary principal/prepayment event occurs.

## 7. Rate term versus amortization/maturity

AgForward distinguishes a **rate term** from a loan's **amortization/maturity structure**.

A farm mortgage can, for example, have:

- 20-year amortization;
- annual payments;
- 5-year rate term.

At the end of the rate term, remaining principal is a renewal/repricing balance. It is **not** automatically a contractual balloon payoff.

The rate-term service records the remaining balance and periods so a future server-authoritative renewal can re-underwrite/reprice the obligation without confusing renewal with maturity.

## 8. Variable-rate convention

The initial variable-rate convention is:

- rate changes occur only at defined financial/payment-period boundaries;
- a newly reset rate applies prospectively to the next accrual interval;
- rate changes are never retroactive;
- the agreement retains rate-history records sufficient to explain each accrued interest amount;
- payment recast policy is product-specific and explicit (payment may be recalculated, term may change, or balloon may absorb changes).

No variable-rate product should be released until its recast policy is separately tested in FS25.

## 9. Payoff convention

Base payoff amount:

`payoff = principal balance + accrued interest + accrued fees + explicit payoff charges`

Principal, interest, fees, and payoff charges remain separate ledger/accounting components. Paying principal is not an expense.

A future secured-disposition transaction uses the same payoff service rather than maintaining a separate sale-specific debt calculation.

## 10. APR terminology

AgForward will not label the contract nominal rate as legal/regulatory "APR" by default.

Until the project implements a defined fee-inclusive effective-rate calculation, UI should use terms such as:

- Contract Rate
- Fixed Rate
- Variable Rate
- Effective Financing Cost (only when mathematically defined)

This avoids implying a jurisdiction-specific regulatory APR calculation that the game does not actually perform.

## 11. Debt-service measurement

Credit analysis derives debt service from scheduled obligations, not simply current principal balances.

For underwriting:

- annual debt service is the principal + interest + scheduled fees actually due over the next 12 FS financial periods;
- payment frequency matters — four quarterly payments are not treated as twelve monthly payments;
- balloon obligations are included when maturity falls inside the 12-period measurement window;
- lease/fixed-charge commitments are tracked separately and included in fixed-charge coverage;
- revolving lines use a product policy for required payment/debt-service stress rather than assuming the full line limit is immediately due.

The credit-profile builder maintains a monthly fallback for legacy schema-v3 liabilities but can interpret an explicit payment frequency/remaining-payment count for newer offline contract models.

## 12. Pure-math implementation

The core offline implementation includes:

- `src/finance/RateConvention.lua`
- `src/finance/AmortizationService.lua`
- `src/finance/StructuredAmortizationService.lua`
- `src/finance/PaymentFrequencyService.lua`
- `src/finance/LoanContractScheduleService.lua`
- `src/finance/RateTermRenewalService.lua`
- `src/finance/RevolvingInterestService.lua`

These modules are intentionally independent from Farming Simulator money movement. They can be statically checked and unit-tested before any loan product is enabled in game.
