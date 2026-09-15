# AgForward Variable-Rate Model

**Status:** offline financial-model baseline  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

Variable-rate products share the same rate-history/recast engine rather than each product inventing its own reset behavior.

## Rate history

Every reset record identifies:

- effective financial year and period;
- resulting annual nominal contract rate;
- optional base rate, product spread, borrower risk spread, term adjustment, and structure adjustment;
- reset reason/source.

Rate-history effective periods must be strictly increasing. A rate applies from its effective period until the next reset; resets never change interest already accrued in prior periods.

Pure implementation: `src/finance/VariableRateService.lua`.

## Initial recast policies

### Recast payment

At the reset date, keep:

- current principal;
- remaining term;
- contractual balloon.

Recalculate the regular payment at the new contract rate using the common amortization engine.

This is the preferred initial variable-rate policy because it is deterministic and preserves maturity/balloon structure.

### Keep payment

Keep the existing periodic payment and project the remaining balance at contractual maturity.

The pure model rejects a rate reset when the existing payment would not even cover current-period interest (`KEEP_PAYMENT_CAUSES_NEGATIVE_AMORTIZATION`).

If the unchanged payment leaves more principal at maturity than the contractual balloon, the model reports a `projectedAdditionalBalloon`. Production use of this policy requires an explicit contract rule deciding whether that increased maturity balance is allowed.

## No retroactive resets

A live agreement must calculate accrued interest using the rate that was effective during the applicable financial period. Editing the current base rate cannot rewrite historic interest.

## Rate component transparency

Where available, retain the component breakdown used to arrive at the contract rate:

`base rate + product spread + borrower risk spread + term adjustment + structure adjustment`

This lets reports explain why the contract rate changed rather than storing only an unexplained final percentage.

## Revolving credit

Operating/Crop Input Lines may use the same rate-history records, but period interest is calculated through `RevolvingInterestService` using the time-weighted principal balance within the period.

## Runtime/persistence requirements

Before variable rates become live:

- persist rate history with each agreement or a stable shared rate-history reference;
- define base-rate source and reset schedule;
- ensure server alone applies resets;
- include rate reset/recast in multiplayer deltas;
- ensure a save/reload cannot apply the same reset twice;
- test boundary ordering when a payment and rate reset occur in the same period transition;
- show current rate and next reset terms in UI.

No variable-rate product should be enabled solely from a mutable global rate without persisted history.
