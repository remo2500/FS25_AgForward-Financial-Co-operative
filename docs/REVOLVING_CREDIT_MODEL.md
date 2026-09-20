# AgForward Revolving Credit Model

**Status:** offline financial-design baseline  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

This document covers the common mechanics shared by the General Operating Line and Crop Input Line of Credit. Product eligibility and spending restrictions can differ, but they should not maintain separate balance/interest engines.

## 1. Common revolving balance

For a revolving facility:

`available credit = credit limit - principal balance - active reservations`

Accrued interest and fees remain separate from principal utilization unless a future contract explicitly capitalizes them.

A facility may be suspended from additional draws due to delinquency/covenant policy without losing its existing outstanding balance.

## 2. Why simple period-end interest is insufficient

Crop-input lines can receive many draws throughout a month/financial period. Charging interest for a full period on a draw made at the end would overstate interest; ignoring it until the next period would understate interest.

AgForward therefore has a pure time-weighted balance model.

## 3. Time-weighted average balance

Each balance-changing event is represented by a normalized fraction of the financial period from `0.0` through `1.0`.

Example:

- opening principal: 20,000;
- at 50% of the period, draw 10,000;
- ending principal: 30,000.

Weighted average balance:

`20,000 x 0.50 + 30,000 x 0.50 = 25,000`

At 12% nominal annual rate:

- monthly periodic rate = 1%;
- interest = 25,000 x 1% = **250**.

The implementation is `src/finance/RevolvingInterestService.lua`.

## 4. Independence from FS days-per-month setting

The weight is a **fraction of the AgForward financial period**, not a raw count of configured gameplay days.

This prevents a player choosing 1 day/month versus 28 days/month from changing the economic amount of monthly credit interest solely because of gameplay pacing.

A runtime adapter should convert the point in the current financial period to a normalized fraction consistently.

## 5. Draw and repayment events

Balance-change events are signed:

- positive = draw / principal increase;
- negative = principal repayment.

A repayment that would drive principal below zero is rejected by the pure model rather than producing negative loan principal.

For identical timestamps, an explicit sequence preserves deterministic event order.

## 6. Interest posting

At period end the common settlement/accrual engine should:

1. reconstruct/consume authoritative opening balance and in-period principal changes;
2. calculate time-weighted average balance;
3. calculate rounded period interest;
4. accrue interest separately from principal;
5. post an interest-accrual ledger event where required by reporting design;
6. include due interest in the next settlement obligation according to product policy.

Interest does not silently increase principal.

## 7. Capitalized interest

The initial AgForward products do not automatically capitalize unpaid interest into principal.

If a later restructuring or special product capitalizes interest, it must be a deliberate transaction:

- reduce accrued interest;
- increase principal;
- record the capitalization transaction;
- respect credit-limit/covenant/product rules;
- preserve tax/accounting history.

## 8. CILOC spending restrictions

The CILOC uses the same revolving balance/interest math but applies purchase-purpose eligibility and reservation checks.

Supported minimum purposes remain:

- seed;
- fertilizer;
- lime/soil amendments;
- crop protection;
- fuel;
- deliberately mapped compatible custom inputs.

Generic material transactions without reliable context are not guessed.

## 9. General Operating Line

The General Operating Line is a broader working-capital facility. It may allow:

- manual draws;
- cash-shortfall funding;
- settlement support when explicitly enabled;
- broader operating expense categories than the CILOC.

The general line should still preserve purchase/expense purpose in the ledger rather than categorizing every funded expense as a loan transaction.

## 10. Credit reservations

Before a purchase that may depend on credit passes its affordability check, AgForward can reserve the required draw amount.

`CreditReservationService.lua` ensures active reservations reduce available capacity before principal is actually committed.

This prevents two simultaneous/near-simultaneous purchases from both observing the same undrawn balance.

## 11. Future seasonal CILOC borrowing base

A later CILOC limit may be constrained by a seasonal borrowing base such as:

`eligible acres x approved input cost/acre x financing percentage`

Potential adjustments may include:

- crop mix/input intensity;
- borrower risk grade;
- existing working capital;
- prior season repayment performance;
- other operating credit exposure.

This borrowing-base policy is not yet calibrated and should remain separate from the common revolving balance engine.
