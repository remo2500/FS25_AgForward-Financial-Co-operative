# AgForward Credit Stress Testing Model

**Status:** offline underwriting foundation  
**Runtime enabled:** NO

## Purpose

AgForward should not evaluate a farm only at a single point estimate. Agricultural income, input costs, asset values, and working-capital availability can all change materially across a season.

`src/credit/CreditStressService.lua` provides a deterministic way to apply configurable shocks without embedding any approval thresholds.

## Whole-farm credit shocks

Supported stress assumptions include:

- total asset-value factor;
- collateral-value factor;
- current-asset factor;
- cash-available-for-debt-service factor;
- debt-service factor;
- fixed-charge factor;
- liquid-asset factor;
- undrawn-credit factor;
- next-12-month-obligation factor;
- additional revolving utilization;
- additional liabilities.

The service rebuilds the standard AgForward credit snapshot after the shock and reports changes in:

- equity;
- working capital;
- DSCR;
- fixed-charge coverage;
- debt-to-assets;
- LTV;
- liquidity coverage.

## Seasonal liquidity shocks

The same service can stress a `LiquidityProjectionService` forecast by changing:

- operating inflows;
- capital inflows;
- operating outflows;
- capital outflows;
- debt service;
- lease payments;
- tax payments;
- available operating-credit limit.

This can show whether a farm that is liquid in the base forecast would exceed line capacity or create an unmet cash deficit under a downside scenario.

## No embedded lender policy

The stress engine does **not** decide what constitutes an acceptable scenario. It only calculates the stressed results.

Future AgForward credit policy may specify which scenarios must be evaluated and how their metrics influence approve/condition/refer/decline decisions. Those policy values should be calibrated against FS25 economics rather than copied from a real lender.

## Example use cases

- lower crop-sale receipts with higher input costs;
- increased debt service after a rate reset;
- lower machinery/land collateral value;
- reduced available operating-line capacity;
- additional seasonal line utilization;
- a proposed asset purchase layered onto an already tight working-capital position.

## Runtime/data gate

The stress model does not predict crop yield, commodity price, taxes, or asset appraisal on its own. Runtime/data adapters will provide baseline values later. The stress service only transforms explicit inputs and remains fully deterministic for auditability.
