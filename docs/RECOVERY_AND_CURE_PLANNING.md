# AgForward Recovery and Cure Planning

## Cure payment

`AGFCurePaymentPlanService` creates a non-mutating plan that joins:

- current liability principal/interest/fees;
- the requested cash payment;
- normal debt-payment allocation;
- the copied delinquency account;
- the amount that actually cures arrears.

A payment larger than the arrears may still be valid: the excess accepted amount remains ordinary debt service after the arrears are cured.

The source liability and source delinquency account are never mutated by the planner.

## Recovery liquidation

`AGFRecoveryLiquidationPlanService` is intentionally different from a voluntary secured sale.

A voluntary sale normally must clear required liens before the borrower can transfer the asset.

In an authorized recovery, collateral can be liquidated even when net proceeds are insufficient to satisfy the debt. The difference becomes a **deficiency**.

Example:

- outstanding debt: $61,500;
- gross collateral proceeds: $50,000;
- recovery costs: $2,000;
- net proceeds applied to debt: $48,000;
- deficiency: $13,500;
- ordinary farm cash received: $0.

If proceeds exceed debt after recovery costs, only the surplus reaches the borrower.

## Safety conditions

The recovery planner requires:

- explicit server/workflow recovery authorization;
- delinquency state already at `recovery`;
- an identified asset and lien;
- an open liability.

It does not treat `collections` alone as authorization to seize collateral.

Recovery costs greater than sale proceeds are rejected until AgForward has an explicit policy for cost capitalization or deficiency treatment.

## Lien and deficiency treatment

The lien against the disposed collateral is released because the collateral no longer exists in the borrower's estate.

If a deficiency remains:

- the liability is **not** silently charged off;
- the recommended liability status remains collections;
- delinquency remains in recovery;
- the residual debt stays visible for later collection/settlement policy.

If the debt is fully satisfied:

- the liability becomes eligible to close;
- delinquency becomes eligible to resolve.

## Accounting

The semantic recovery group preserves:

- gross asset-sale proceeds;
- recovery costs as a separate finance-cost row pending runtime tax-treatment proof;
- fees/interest/principal debt application;
- borrower surplus, if any, as the net cash effect.

No prepayment penalty is automatically applied to forced recovery.

## Runtime gate

Neither service moves FS cash, sells assets, releases liens, changes liability status, or transitions delinquency.

Live execution must remain inside the common server-authoritative operation/revision/persistence boundary.
