# AgForward Financial Statement Model

## Purpose

`AGFFinancialStatementService` builds a read-only whole-farm financial statement from the shared AgForward registries.

It is intended to support the future Overview, lender-review, and reporting screens without becoming a second accounting authority.

## Asset treatment

Only assets with an active **economic owner** right held by the farm are included as registered owned assets.

Operating or tenant rights do not create balance-sheet ownership.

Therefore leased farmland can be operated by the farm while remaining excluded from owned assets and collateral/net worth unless a separate ownership right exists.

Registered assets are grouped by:

- vehicle;
- placeable;
- farmland;
- other.

Cash and caller-supplied non-registered owned assets are shown separately.

## Liability treatment

The statement includes:

- native AgForward principal;
- accrued interest;
- accrued fees;
- total native outstanding;
- represented external principal;
- optional caller-supplied other liabilities;
- totals by AgForward product.

External debt quality remains visible rather than being silently treated as fully verified.

## Fixed charges

Annual fixed charges combine:

- native lease fixed charges; and
- represented external fixed charges.

They remain separate from principal balances.

## Equity and data quality

`equity = represented assets - represented liabilities`

The statement reports data-quality issues for missing cash context, unavailable ownership rights, unresolved owned-asset links, and incomplete external obligations.

The ratio outputs are descriptive calculations only; lending thresholds belong in the credit-policy layer.
