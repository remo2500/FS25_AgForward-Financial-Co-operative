# AgForward Whole-Farm Credit & Underwriting Model

**Status:** offline design baseline; no live approvals enabled  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

AgForward underwriting is deliberately whole-farm. A product may have specialized collateral and terms, but no product is permitted to calculate borrower risk from only its own agreement list.

## 1. Authority inputs

The future credit engine should consume deliberately modeled information from common services:

- AgForward native liabilities;
- external/base-game obligations that AgForward intentionally represents;
- owned assets and collateral values;
- active liens and lien priority;
- leased/fixed-charge commitments;
- cash and liquid working capital;
- operating-history inputs from FinanceStats/ledger reporting;
- payment/delinquency history;
- requested new credit exposure.

Leased land and leased equipment are not owned collateral merely because the player can operate them.

## 2. Core metrics

The pure metric implementation is `src/credit/CreditMetrics.lua`.

### Debt Service Coverage Ratio (DSCR)

`DSCR = cash available for debt service / annual debt service`

Debt service is scheduled principal + interest + scheduled finance charges due during the next 12 financial periods. Balloon amounts are included when due within the measurement horizon.

A borrower with no debt service returns an undefined/not-applicable DSCR rather than an artificial infinite score.

### Fixed-Charge Coverage

`FCCR = cash available for fixed charges / (annual debt service + annual lease/fixed charges)`

This ensures land rent and other genuine fixed commitments affect underwriting even though they are not loan principal.

### Debt-to-Assets

`Debt-to-Assets = total liabilities / total owned assets`

Only economically owned assets enter the asset denominator. Leased operating rights do not.

### Loan-to-Value (LTV)

`LTV = secured debt / eligible collateral value`

Future lien logic must ensure collateral value is net of prior liens when appropriate. Product rules may apply advance-rate haircuts before LTV.

### Working Capital

`Working Capital = current assets - current liabilities`

### Current Ratio

`Current Ratio = current assets / current liabilities`

### Revolver Utilization

`Utilization = drawn principal / approved credit limit`

High utilization may influence pricing and approval policy but is not inherently delinquency.

### Liquidity Coverage

`Liquidity Coverage = (cash/liquid assets + undrawn committed credit) / next-12-month obligations`

Undrawn credit is included only when the facility is active and not suspended by covenant/default policy.

### Equity Ratio

`Equity Ratio = (assets - liabilities) / assets`

## 3. Credit profile vs approval policy

Metric calculation and lending policy are separate layers.

The metric layer answers: "What is the borrower position?"

The policy layer answers: "Given this product, requested amount, collateral, and risk appetite, is the request approved and at what price?"

Do not hard-code approval cutoffs inside `CreditMetrics.lua`.

## 4. Initial risk-grade direction

A later `CreditPolicyService` may map metrics into a risk grade such as:

- A — strong;
- B — acceptable;
- C — elevated risk / conditions;
- D — weak / restricted;
- E — default/collections.

The exact thresholds are not locked yet. They should be calibrated after the economic model and typical FS25 farm cash flows are observed.

Risk grade should influence:

- maximum exposure;
- product availability;
- collateral/advance-rate requirements;
- borrower risk spread;
- term/balloon flexibility;
- covenant/default controls.

## 5. Pro-forma underwriting

New credit should be underwritten both **before** and **after** the proposed transaction.

Example equipment finance approval should compare:

- current DSCR;
- projected DSCR after the new payment;
- current debt-to-assets;
- projected debt-to-assets;
- equipment LTV;
- liquidity after down payment;
- total AgForward + represented external debt.

This prevents a loan from appearing affordable solely because its own local agreement list ignores existing obligations.

## 6. Crop Input Line considerations

The Crop Input Line of Credit has a different risk pattern from long-term equipment debt.

Future CILOC policy may consider:

- eligible seeded/cropped acres;
- expected crop input cost per acre;
- approved financing percentage;
- existing line utilization;
- projected harvest timing;
- prior-season repayment history;
- working capital;
- overall leverage.

The CILOC credit limit may therefore be a borrowing-base style amount rather than a generic unsecured limit.

## 7. Data-quality states

A credit profile should report data quality as well as metric values.

Examples:

- `COMPLETE` — required native/external obligations and assets are represented;
- `PARTIAL_EXTERNAL_DEBT` — known base-game/external obligations not fully modeled;
- `ASSET_LINK_UNRESOLVED` — secured collateral cannot currently be linked;
- `INSUFFICIENT_HISTORY` — not enough operating history for a stable cash-flow metric.

AgForward should lower confidence or restrict approvals rather than silently treat missing information as zero.

## 8. No duplicated financial truth

Credit metrics are derived views. They do not maintain independent debt balances or asset values. Their sources remain the common ledger, liability registry, asset/right/lien registry, lease registry, and explicitly modeled external obligations.
