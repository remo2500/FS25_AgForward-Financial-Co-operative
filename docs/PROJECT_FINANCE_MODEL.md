# AgForward Project & Facility Finance Model

**Status:** offline product-model baseline  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

Project finance uses the same liability, rate, amortization, credit, lien, settlement, and delinquency engines as other AgForward lending. The specialized layer is **project sources and uses** plus the construction/placeable purchase context.

## 1. Sources and uses

Project cost is decomposed into explicit uses such as:

- construction/placeable cost;
- groundwork/site preparation;
- project equipment;
- engineering/professional fees;
- finance fees;
- other supported project costs.

Funding sources remain separate:

- farm cash/equity;
- Red Tape/external grant/program funding;
- other non-debt contributions;
- AgForward loan;
- other represented debt.

Pure reconciliation is implemented in `src/finance/ProjectSourcesUsesService.lua`.

## 2. Financing need

Base relationship:

`financing need = total project uses - verified non-debt sources`

Example:

- construction/site/fees = 500,000;
- farm cash = 100,000;
- approved external grant = 50,000;
- AgForward financing need = **350,000**.

The grant reduces financing need but is not AgForward loan proceeds and is not silently combined with farm cash.

## 3. Funding gap

A credit-policy or collateral limit may cap the amount AgForward will finance.

Example:

- financing need = 400,000;
- approved maximum loan = 300,000;
- funding gap = **100,000**.

The project cannot be considered fully funded until that gap has a validated source. AgForward should not silently reduce project uses or assume undocumented cash.

## 4. Collateral-eligible uses

Project uses can indicate whether they are expected to contribute to secured collateral value. This is not the same as automatically assigning dollar-for-dollar collateral value.

Example:

- permanent bin structure may be collateral-eligible;
- certain engineering/financing fees may not be;
- appraisal/advance-rate policy may further haircut eligible value.

The asset/right/lien registry remains collateral authority after the placeable exists.

## 5. Construction integration target

The future runtime flow should occur before final construction affordability/payment:

1. player configures eligible placeable/project;
2. AgForward captures project purchase context and total uses;
3. verified grant/program contributions are included when available;
4. farm cash/equity contribution is selected;
5. remaining financing need is quoted/underwritten;
6. server authorizes funding;
7. financial operation stages required loan proceeds/equity;
8. normal construction purchase completes;
9. resulting placeable is linked to a stable asset record;
10. lien is created only after authoritative asset identity is known;
11. all sources/uses and purchase entries reconcile.

If construction fails after financing is staged, staged cash/debt must be reversed rather than leaving an orphan loan.

## 6. Groundwork

Groundwork/displacement costs need explicit treatment because construction purchase paths may expose them separately from the placeable price.

AgForward should preserve them as project uses and decide through policy whether they are:

- eligible to finance;
- eligible collateral cost basis;
- grant eligible;
- immediately expensed or capitalized for reporting/tax integration.

Do not assume groundwork can always be recovered in a later asset sale value.

## 7. Grant integration boundary

Red Tape remains grant/government-program authority.

AgForward may consume an approved/paid grant as a verified project source, but must not independently recreate Red Tape grant eligibility or tax treatment.

Runtime adapter must distinguish:

- approved but not yet funded grant;
- funded/available grant;
- conditional grant;
- grant later revoked/clawed back, if Red Tape exposes such behavior.

Only a source that is sufficiently certain under the selected policy should reduce the amount AgForward must fund at closing.

## 8. Secured disposal

A financed placeable/facility sale must use the common `SecuredDispositionService` rather than a project-finance-specific payoff implementation.

The sale preflight verifies:

- asset identity/ownership;
- active liens;
- payoff;
- sale proceeds;
- negative-equity cash shortfall;
- ability to clear liens before disposal.

## 9. Underwriting

Project finance should use whole-farm before/after metrics plus project-specific measures such as:

- loan-to-cost;
- loan-to-value/appraised value;
- post-closing liquidity;
- DSCR/fixed-charge coverage after new debt service;
- total leverage;
- project equity contribution;
- grant certainty/source quality.

Product thresholds belong in configurable credit policy, not in the sources/uses math.

## 10. Offline implementation

Current pure components:

- `src/finance/ProjectSourcesUsesService.lua`
- common `LoanQuoteService.lua`;
- common `ProFormaUnderwritingService.lua`;
- common asset/right/lien models;
- common secured-disposition preflight.

No live construction hooks, grant bridge, money movement, or placeable linking have been enabled yet.
