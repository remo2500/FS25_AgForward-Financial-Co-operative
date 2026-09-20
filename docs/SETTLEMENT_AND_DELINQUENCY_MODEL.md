# AgForward Settlement & Delinquency Model

**Status:** offline design/pure-model baseline  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

AgForward intentionally separates **planning**, **execution**, **payment allocation**, and **delinquency** so no product independently debits farm cash or maintains a private default system.

## 1. Settlement stages

Target period settlement:

1. gather all due obligations;
2. validate obligation records and current lifecycle state;
3. determine currently available cash;
4. determine any explicitly authorized settlement credit availability;
5. build a deterministic payment plan;
6. execute that plan through the common financial operation coordinator;
7. allocate each actual payment into fees/interest/principal/rent as applicable;
8. post ledger entries;
9. record exact unpaid balances;
10. advance/cure delinquency;
11. persist settlement idempotency marker;
12. emit authoritative multiplayer deltas.

`SettlementPlanner.lua` implements only step 5. It performs no mutation.

## 2. Obligation contract

A settlement obligation should expose at minimum:

```text
id
obligationType
priority
amountDue
minimumPayment
allowPartial
allowCreditDraw
dueYear
duePeriod
source entity/reference
```

Products may add metadata, but all products enter the same planner.

## 3. Priority policy

The planner intentionally does **not** hard-code that a specific product always outranks another. It sorts by explicit numeric priority, then due date, then stable ID.

This lets AgForward define and later calibrate a policy centrally without embedding inconsistent payment order inside product modules.

Potential categories that policy may distinguish later include:

- government/tax obligations exposed by Red Tape;
- secured debt;
- lease/fixed-charge obligations;
- revolving credit;
- unsecured term debt;
- fees/other contractual obligations.

The exact production priority table remains a policy decision and must be documented before live settlement is enabled.

## 4. Optional credit draws

An obligation may explicitly allow use of an approved revolving facility during settlement.

Rules:

- credit is never assumed available merely because a line exists;
- the line must be active/authorized and not suspended;
- the settlement planner sees only the amount explicitly made available to the settlement run;
- an obligation can opt out of credit funding;
- the actual draw must be committed by the common operation coordinator, not by the planner.

This prevents one product from silently borrowing to pay another outside the farm's selected policy.

## 5. Partial payments

Each obligation states whether partial payment is permitted and, if so, its minimum payment.

The planner never proposes a positive payment smaller than the minimum.

Unpaid amounts remain exact. They are not discarded, rounded away, or replaced with a generic "late" flag.

## 6. Component allocation

`PaymentAllocationService.lua` separates an actual payment from the obligation balance components.

Initial supported orderings:

- fees -> interest -> principal;
- interest -> fees -> principal;
- principal only.

The default common ordering is fees, then interest, then principal, but product/contract policy may explicitly select another ordering.

Principal, interest, and fees remain distinct ledger/accounting records even if paid in one settlement operation.

## 7. Delinquency lifecycle

The shared pure state machine is:

`Current -> Past Due -> Delinquent -> Final Notice -> Collections -> Recovery`

Additional terminal/administrative states:

- Resolved;
- Charged Off.

The initial default missed-payment thresholds are one step per missed required payment:

- 1 missed: Past Due;
- 2 missed: Delinquent;
- 3 missed: Final Notice;
- 4 missed: Collections;
- 5 missed: Recovery.

These are defaults for modeling/testing, **not yet calibrated production credit policy**. A product/credit policy may supply different ordered thresholds.

## 8. Cure

A cure payment reduces exact past-due amount. Delinquency returns to Current only when the past-due balance is fully cured under the initial model.

A partial cure does not falsely erase delinquency history.

The historical transition log remains available for future credit scoring/reporting.

## 9. Recovery

The state machine entering `Recovery` does not itself repossess/sell collateral.

A future recovery service must use:

- asset/right/lien registry;
- secured-disposition preflight/execution;
- borrower permissions/server authority;
- exact payoff;
- sale/recovery proceeds;
- deficiency/surplus handling;
- ledger and Red Tape classifications.

This keeps default state separate from asset-disposition mechanics.

## 10. Idempotency

The live settlement coordinator already has a persisted period completion marker in the hardening branch. Future execution must combine that with operation/request IDs so reloading, reconnecting, or duplicate network events cannot pay the same obligation twice.

## 11. Offline implementations

- `src/finance/PaymentAllocationService.lua`
- `src/settlement/SettlementPlanner.lua`
- `src/delinquency/DelinquencyStateMachine.lua`

These are pure models. The real FS25 money movement boundary remains blocked until persistence and runtime hooks are validated.
