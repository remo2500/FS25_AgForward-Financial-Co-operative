# AgForward Settlement Execution Plan

## Purpose

`AGFSettlementExecutionPlanService` is the pure bridge from deterministic liquidity allocation to the eventual atomic month/period settlement transaction.

It performs no live mutation.

## Liquidity sequence

If the settlement planner authorizes use of a general operating line:

1. the operating-line draw is a financing inflow;
2. all obligations are then paid from the common cash pool;
3. debt payments are split into fees, interest, and principal;
4. lease rent remains a lease expense;
5. unpaid amounts become servicing-review candidates.

A CILOC is not accepted as generic settlement liquidity because it is purpose-restricted.

## Accounting reconciliation

If a settlement uses:

- $4,000 existing cash;
- $1,000 operating-line draw;
- $5,000 debt payment,

the semantic ledger is:

- +$1,000 credit draw;
- -$5,000 payment components;
- net -$4,000.

That net equals the actual reduction in pre-existing FS cash.

This structure avoids incorrectly tagging the entire debt payment as being directly funded by the operating line while preserving the financing inflow in the same atomic group.

## Current-balance authority

Scheduled contract rows are not enough to determine principal/interest/fee application.

The execution planner uses `LiabilityPaymentPlanService` against the current liability balances. If the scheduled allocation exceeds the current outstanding amount, the transaction must be replanned rather than silently creating an unapplied payment.

## Runtime gate

The future coordinator must execute or compensate the whole group:

- optional operating-line principal draw;
- FS cash movement;
- liability component reductions;
- lease rent application;
- ledger entries;
- servicing/delinquency updates;
- state revision and persistence.

No independent module may debit cash at period change outside this boundary.
