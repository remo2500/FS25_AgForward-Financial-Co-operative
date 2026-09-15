# AgForward Financial Conventions

**Status:** offline design authority for future Phase 1 loan math  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

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

## 3. Financial periods

AgForward uses **12 financial periods per year** for ordinary lending products. One FS monthly period therefore corresponds to one financial accrual/payment period regardless of the number of gameplay days configured inside that month.

Periodic rate:

`periodicRate = annualNominalRate / 12`

The initial engine intentionally does not use daily accrual or day-count conventions. If a future product requires daily interest, it must be introduced as a separate, explicitly versioned convention rather than silently changing existing agreements.

## 4. Amortizing payment convention

For:

- principal `P`;
- periodic rate `r`;
- number of periods `n`;
- contractual balloon balance `B` due at maturity;

AgForward quotes the regular periodic payment by discounting the balloon and amortizing the remainder.

For `r > 0`:

`payment = (P - B / (1+r)^n) * r / (1 - (1+r)^(-n))`

For `r = 0`:

`payment = (P - B) / n`

The quoted regular payment is rounded to cents.

The balloon must be between zero and original principal for the initial engine. A bullet loan is represented by `balloon = principal`, which produces interest-only regular payments when the rate is positive and the full principal due at maturity.

## 5. Period accrual and schedule rounding

For each period:

1. Interest is calculated on the opening principal balance using the current periodic rate.
2. Interest is rounded to cents.
3. Regular principal is regular payment minus interest and is rounded to cents.
4. Principal may not fall below the contractual balloon before maturity.
5. In the final period, regular principal is adjusted to leave exactly the contractual balloon before the maturity balloon payment.
6. The balloon is then paid as a separate maturity principal component.
7. The final ending principal balance is exactly zero after the balloon payment.

This final-period adjustment prevents accumulated cent rounding from creating a residual or overpayment.

Negative amortization is not permitted by default. Any future product that deliberately allows capitalized interest must opt into a separate policy.

## 6. Variable-rate convention

The initial variable-rate convention is:

- rate changes occur only at financial-period boundaries;
- a newly reset rate applies to the next accrual period;
- rate changes are never retroactive;
- the agreement retains rate-history records sufficient to explain each accrued interest amount;
- payment recast policy is product-specific and must be explicit (payment may be recalculated, term may change, or balloon may absorb changes).

No variable-rate product should be released until its recast policy is separately tested.

## 7. Payoff convention

Base payoff amount:

`payoff = principal balance + accrued interest + accrued fees + explicit payoff charges`

Principal, interest, fees, and payoff charges remain separate ledger/accounting components. Paying principal is not an expense.

A future secured-disposition transaction uses the same payoff service rather than maintaining a separate sale-specific debt calculation.

## 8. APR terminology

AgForward will not label the contract nominal rate as legal/regulatory "APR" by default.

Until the project implements a defined fee-inclusive effective-rate calculation, UI should use terms such as:

- Contract Rate
- Fixed Rate
- Variable Rate
- Effective Financing Cost (only when mathematically defined)

This avoids implying a jurisdiction-specific regulatory APR calculation that the game does not actually perform.

## 9. Debt-service measurement

Credit analysis should derive debt service from scheduled obligations, not simply current principal balances.

For underwriting:

- annual debt service = principal + interest + scheduled fees due over the next 12 financial periods;
- balloon obligations within the measurement window are included when they become due;
- lease/fixed-charge commitments are tracked separately and included in fixed-charge coverage;
- revolving lines use a product policy for required payment/debt-service stress rather than assuming the full limit is immediately due.

## 10. Pure-math implementation

The offline implementation lives in:

- `src/finance/RateConvention.lua`
- `src/finance/AmortizationService.lua`

These modules are intentionally independent from Farming Simulator money movement. They can be statically checked and unit-tested before any loan product is enabled in game.
