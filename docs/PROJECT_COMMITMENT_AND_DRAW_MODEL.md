# AgForward Project Commitment and Draw Model

## Purpose

Project/facility finance must not behave like a fully advanced equipment loan on the day the project is approved.

AgForward now separates:

1. the **approved commitment**;
2. **advanced principal**;
3. the **undrawn commitment**;
4. the eventual amortizing conversion terms.

## Origination

A project approval produces `projectCommitmentOrigination`.

At commitment opening:

- principal is 0;
- original funded principal is 0;
- approved commitment is stored separately;
- no loan proceeds are posted;
- no cash moves;
- the collateral/security plan can be established against the project economic asset;
- the quoted term schedule remains a **conversion preview**, not a live payment schedule.

This prevents the full construction commitment from being reported as debt before funds are actually advanced.

## Draw transaction

`AGFProjectDrawPlanService` plans one staged use.

Example:

- current project use: $100,000;
- AgForward draw: $80,000;
- cash contribution: $20,000.

The semantic ledger group is:

- +$80,000 project-finance proceeds;
- -$100,000 project/asset use;
- net FS cash movement: -$20,000.

Advanced principal increases by $80,000 and undrawn commitment decreases by $80,000.

## Interest

The draw planner does not calculate period interest itself.

Every accepted draw changes the principal timeline, so the existing `ProjectDrawAccrualService` must recalculate time-weighted construction interest using actual draw timing.

## Runtime gate

Future execution must atomically coordinate:

- authoritative construction/use context;
- cash contribution;
- commitment availability;
- FS cash/purchase movement;
- project principal mutation;
- economic asset/link state;
- ledger posting;
- state revision/persistence.

No staged project module is currently enabled in `modDesc.xml`.
