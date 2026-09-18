# AgForward Liability Payoff and Secured Disposition

## Payoff quote

`AGFLiabilityPayoffQuoteService` separates a full payoff into:

- principal;
- accrued interest;
- accrued fees;
- contractual early-prepayment charge;
- total cash required.

At contractual maturity, early-prepayment restrictions do not apply.

The service never moves money or edits the liability.

## Secured asset sale

`AGFSecuredDispositionExecutionPlanService` joins:

- the existing ownership/lien sale preflight;
- current liability balances;
- explicit prepayment policy;
- componentized liability payment planning;
- asset-sale proceeds;
- lien release intent.

The resulting semantic ledger group includes the full asset sale, principal reduction, interest, accrued fees, and any prepayment charge separately.

## Conservative release rules

The execution planner refuses to guess in two important cases.

### Unknown prepayment policy

A secured sale must know the contract's payoff/prepayment policy. The caller may explicitly mark a product as open-prepay, but silence is not treated as permission.

### Capped lien below full obligation

If a lien's secured amount cap is below the liability's total outstanding balance, selling that collateral may leave residual unsecured debt or require a specific partial-release agreement.

AgForward currently returns:

`CAPPED_LIEN_DISPOSITION_POLICY_REQUIRED`

rather than automatically releasing the lien or paying an arbitrary amount.

## Atomic runtime boundary

Future live execution must coordinate:

1. validate ownership and stable asset identity;
2. obtain authoritative sale proceeds;
3. lock current liability/payoff terms;
4. perform the sale/cash movement;
5. apply principal/interest/fee payoff;
6. apply any prepayment charge;
7. release liens only after required payoff succeeds;
8. mark the economic asset disposed and release ownership rights;
9. post the linked ledger group;
10. advance state revision and persist.

This same foundation can later support dealer trade-in by replacing gross sale proceeds with gross dealer trade value before calculating net equity.
