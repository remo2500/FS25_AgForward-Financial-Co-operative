# AgForward FS MoneyType / FinanceStats / Red Tape Mapping Plan

**Status:** pre-runtime mapping authority; exact live registration remains unproven  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

This document defines the **economic intent** of AgForward cash movements before any live FS25 MoneyTypes are registered. Exact engine registration names and Red Tape behavior remain a runtime validation gate.

## 1. Design rule

Three concepts are separate:

1. **AgForward ledger classification** — authoritative economic meaning.
2. **FS25 MoneyType / FinanceStats statistic** — how the cash movement appears to Farming Simulator finance statistics.
3. **Red Tape tax classification** — government/tax treatment.

No one of these layers is allowed to overwrite the other two.

## 2. Donor/research constraints

The donor re-audit established:

- Red Tape observes server `Farm.changeBalance` money movements;
- Red Tape ignores most MoneyTypes whose statistic is `other` unless specifically allowlisted;
- Red Tape currently recognizes expense statistics including `purchaseSeeds`, `purchaseFertilizer`, `purchaseFuel`, `loanInterest`, `bankLoanInterest`, `vehicleLeasingCost`, and other operating statistics;
- blindly adding supplemental Red Tape line items creates double-count risk when Red Tape already observes the native cash movement;
- generic material purchases can use `BOUGHT_MATERIALS`, so post-hoc MoneyType alone may not identify fertilizer/lime/herbicide purpose.

## 3. Mapping intent table

| AgForward economic event | FS cash movement intent | Preferred FinanceStats role | Red Tape intent | Runtime proof required |
|---|---|---|---|---|
| Loan / term proceeds | cash inflow | financing/non-operating | not taxable income | Yes |
| Revolver/CILOC draw | cash inflow | financing/non-operating | not taxable income | Yes |
| Principal repayment | cash outflow | liability reduction/non-operating | not deductible expense | Yes |
| Interest payment | cash outflow | interest expense | deductible finance expense when Red Tape policy permits | Yes |
| Finance fee | cash outflow | finance fee | separately classified; policy-dependent | Yes |
| Late fee | cash outflow | late/finance fee | separately classified; policy-dependent | Yes |
| Land lease rent | cash outflow | rent/fixed charge | lease/rent expense | Yes |
| Seed purchase | normal underlying FS purchase | `purchaseSeeds` where native path supplies it | seed/input expense | Reconcile only |
| Fertilizer purchase | normal underlying FS purchase | `purchaseFertilizer` where native path supplies it | fertilizer/input expense | Reconcile only |
| Fuel purchase | normal underlying FS purchase | `purchaseFuel` where native path supplies it | fuel expense | Reconcile only |
| Lime / crop protection via generic material path | normal underlying FS purchase plus retained fill-type context | may appear as generic material statistic | correct input-purpose expense | Yes; likely supplemental classification |
| Equipment/placeable/land purchase | normal purchase/context integration | asset acquisition statistic where native path provides it | asset acquisition, not ordinary operating expense unless Red Tape policy says otherwise | Yes |
| Asset sale | normal disposal proceeds | asset-sale statistic | disposal proceeds | Yes |
| Grant receipt | Red Tape/external program should remain authority when originating there | grant/program statistic | grant treatment owned by Red Tape | Yes |

## 4. Candidate AgForward MoneyTypes

AgForward will likely need dedicated cash-movement types for events that FS25 does not naturally represent with the correct economic meaning.

Candidate semantic names (not yet runtime-locked engine registration strings):

- `AGF_FINANCE_PROCEEDS`
- `AGF_REVOLVER_DRAW`
- `AGF_PRINCIPAL_REPAYMENT`
- `AGF_INTEREST_PAYMENT`
- `AGF_FINANCE_FEE`
- `AGF_LATE_FEE`
- `AGF_LEASE_RENT`
- `AGF_LIEN_PAYOFF`

The actual MoneyType registration must be verified against current FS25 API behavior before these become active.

## 5. Financing proceeds and principal

The safest tax behavior is for financing proceeds and principal repayment to **not enter operating taxable income/expense**.

A custom statistic that Red Tape ignores may be desirable for these two categories, provided:

- FS FinanceStats remain stable;
- AgForward's own ledger/reporting still captures them;
- no other game system incorrectly treats the custom statistic as operating income/expense;
- multiplayer/save behavior is proven.

Do not force these through an operating-income or operating-expense statistic merely to make them visible in vanilla FinanceStats.

## 6. Interest

Interest must remain separately visible from principal.

Candidate approach:

- register/use a MoneyType whose statistic resolves to an interest statistic Red Tape already recognizes (`loanInterest` or `bankLoanInterest`), **if** current FS25 MoneyType registration safely supports it;
- otherwise use an AgForward finance statistic and let the Red Tape adapter provide a single supplemental classification only after proving the native movement is not already counted.

Runtime reconciliation must confirm:

`AgForward interest ledger amount == FS interest statistic amount == Red Tape interest/tax line amount`

with no duplicate.

## 7. Finance and late fees

Fees are deliberately not folded into interest.

Until Red Tape tax treatment is agreed/tested:

- keep them distinct in the AgForward ledger;
- use a dedicated FS statistic or non-operating `other` movement rather than misclassifying them as principal or lease cost;
- adapter may expose a supplemental tax classification if the fee should be deductible and Red Tape cannot otherwise see it.

## 8. Lease rent

Land rent is a fixed operating charge for AgForward credit analysis but is not loan principal.

The runtime mapping must avoid reusing `vehicleLeasingCost` for farmland merely because Red Tape recognizes it; that would lose economic purpose. Prefer a dedicated lease/rent statistic plus an explicit Red Tape bridge if necessary.

## 9. Input purchases funded by credit

Do **not** replace the underlying purchase MoneyType with a financing MoneyType.

For a $30,000 fertilizer purchase fully funded by CILOC:

1. AgForward adds $30,000 financing cash using a non-income financing movement.
2. The normal fertilizer purchase removes $30,000 using its ordinary purchase path/MoneyType.
3. AgForward ledger links financing and fertilizer purchase through a group/operation ID.

This preserves both affordability and tax/expense classification.

If the native material path is generic (`BOUGHT_MATERIALS`), AgForward must retain fill-type context and later determine whether a supplemental Red Tape classification is required.

## 10. Transaction-by-transaction reconciliation gate

Before any mapping is called production-safe, test each supported transaction with and without Red Tape and capture:

- starting farm cash;
- ending farm cash;
- AgForward ledger entries/components;
- FS FinanceStats values before/after;
- Red Tape recorded line items/statements before/after;
- tax-category result;
- duplicate/missing amount check.

Required invariant:

`one economic event -> one correct cash effect -> one AgForward accounting representation -> no duplicate tax effect`

## 11. Unsupported/unknown Red Tape versions

When Red Tape is present but its observed behavior/version is not validated:

- AgForward lending still works;
- core ledger remains authoritative;
- enhanced tax bridge enters `DEGRADED` state;
- no speculative supplemental tax line is injected.

## 12. Implementation staging

Current offline code may model **cash movement intent** without registering live MoneyTypes. Live registration belongs after the Phase 0 persistence candidate is runtime proven.

Recommended implementation order:

1. semantic movement-intent table;
2. runtime MoneyType registration experiment;
3. FinanceStats reconciliation without Red Tape;
4. Red Tape reconciliation matrix;
5. adapter capability/version guards;
6. only then activate production mappings.
