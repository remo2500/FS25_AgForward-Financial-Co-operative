# AgForward External Obligation Reconciliation

## Purpose

Whole-farm underwriting cannot silently ignore debt and fixed charges that live outside AgForward.

`AGFExternalObligationReconciliationService` provides a pure snapshot-diff layer for future base-game and third-party obligation adapters.

## Stable external keys

Each discovered obligation requires a stable source-specific key, for example:

- `farm.loan`;
- `vehicleLease:<stable vehicle key>`;
- another adapter-defined persistent identifier.

The key is stored as `metadata.externalKey` on represented external obligations.

## Reconciliation output

Given the currently represented source snapshot and a newly observed source snapshot, the service identifies:

- additions;
- updates;
- unchanged obligations;
- retirements;
- existing rows that cannot yet be matched because they lack a stable external key.

Duplicate source keys are rejected rather than guessed.

## Runtime boundary

This service performs no discovery and no registry mutation.

A future FS25 adapter must first prove how to obtain authoritative base-game loan/lease identifiers and balances. Only then should the proposed reconciliation plan be applied to the external-obligation registry.

This separates uncertain runtime discovery from deterministic financial reconciliation.
