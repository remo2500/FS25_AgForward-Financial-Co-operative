# AgForward Seasonal Liquidity Projection Model

**Status:** offline underwriting/reporting foundation  
**Runtime enabled:** NO

## Why AgForward needs this

Farm cash flow is seasonal. A farm can be economically viable while spending heavily on inputs before receiving crop-sale revenue months later. A generic current-cash test can therefore reject realistic farm financing or hide a predictable seasonal liquidity shortage.

AgForward should distinguish:

- profitability/repayment capacity;
- current liquidity;
- seasonal working-capital need;
- available revolving credit;
- peak line utilization;
- line cleanup after major receipts.

## Offline service

`src/credit/LiquidityProjectionService.lua`

The service projects sequential financial periods using:

- opening cash;
- a required minimum cash reserve;
- operating inflows/outflows;
- capital inflows/outflows;
- scheduled debt service;
- lease payments;
- taxes;
- other inflows/outflows;
- an optional operating-credit limit and opening utilization.

It can optionally model two explicit forecast policies:

- draw authorized operating credit when projected cash falls below the minimum;
- use projected excess cash to repay the modeled operating line.

These are **forecast assumptions only**. They do not authorize live FS25 draws or settlement behavior.

## Period result

Each projected period records:

- opening cash;
- opening operating-line principal;
- total inflows/outflows;
- net cash before financing;
- modeled line draw;
- modeled line repayment;
- unmet liquidity shortfall;
- ending cash;
- ending line principal;
- remaining available line capacity.

## Summary metrics

The projection returns:

- total operating/capital/other cash movement aggregate;
- total modeled draws and repayments;
- peak operating-line utilization;
- ending line balance;
- ending available capacity;
- ending cash;
- lowest projected cash;
- number/value of periods with an unmet liquidity shortfall;
- overall liquidity-adequacy flag.

## Underwriting use

A future AgForward credit decision can use the projection to answer questions such as:

- Does the farm require an operating line even though annual cash flow is positive?
- Is the requested line large enough to cover spring input requirements?
- When is peak utilization expected?
- Does projected harvest revenue clean the line down?
- Would a new equipment/land/project payment create a seasonal cash deficit?
- Is a proposed CILOC/operating limit adequate under the selected minimum-cash policy?

The projection should complement, not replace, DSCR, leverage, collateral, and working-capital metrics.

## Relationship to Crop Input LOC

A CILOC and a general operating line remain separate products, but both affect farm liquidity.

The eventual farm forecast may model multiple facilities in order of policy eligibility. For example:

1. eligible seed/fertilizer/fuel purchases may use CILOC capacity;
2. general farm cash deficits may use the broader Operating Line if authorized;
3. any remaining deficit becomes an explicit liquidity shortfall.

The current service intentionally models only one general backstop at a time so the math remains transparent. A future multi-facility allocator should reuse the existing CILOC funding policy/reservation services instead of embedding product rules in the projection engine.

## Example seasonal pattern

A grain farm might project:

- winter cash reserve;
- spring seed/fertilizer/fuel outflows;
- early-summer crop-protection expense;
- mid-season equipment/debt obligations;
- harvest/marketing crop-sale inflows;
- line repayment/cleanup after receipts.

A temporary line balance during spring therefore does not by itself imply distress. The important outputs are whether the farm stays within approved capacity, whether scheduled obligations remain serviceable, and whether the line follows its expected cleanup/renewal policy.

## Runtime/data caution

Real FS25 calibration remains pending. We should not lock fictional dollar-per-acre budgets or lender thresholds until we observe representative savegame cash-flow patterns.

The service presently performs no:

- game event interception;
- automatic credit draw;
- automatic repayment;
- rate/interest accrual on projected line use;
- tax estimation;
- crop-yield/price forecasting.

Those inputs can be layered in later while keeping this projection as a deterministic cash-flow engine.
