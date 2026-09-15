# AgForward Product Requirements

## Purpose

AgForward Financial Cooperative is an agriculture-first financial institution for Farming Simulator 25. The player should experience one coherent lender across operating credit, equipment, facilities, land, leasing, and financial reporting.

## Product families

### 1. Operating Credit

#### General Operating Line
- Revolving facility with approved limit and available balance.
- Manual draws and repayments.
- Interest charged only on drawn balance.
- Optional automatic settlement draw when enabled.
- Delinquency/covenant controls can suspend further draws.

#### Crop Input Line of Credit
- Dedicated revolving facility for eligible crop-input purchases.
- Purchase category must remain visible in the ledger even when financed.
- Financing draw and purchase are linked but separately classified.
- Minimum recognized categories: seed, fertilizer, lime/soil amendments, crop protection, and fuel.
- Usage policies: Off; cash-shortfall only; prefer line; always use line.
- Principal repayment is not an expense.
- Interest and fees are separate finance expenses.
- Future option: seasonal borrowing base based on acres and expected input cost.
- Future option: automatic harvest-proceeds sweep.

### 2. General Term Lending
- Standard amortizing term loan.
- Bullet loan.
- Fixed or variable rate.
- Early principal payment and full payoff.
- Whole-farm underwriting.

### 3. Equipment Finance
- Finance from normal vehicle purchase context.
- Down payment/equity contribution.
- Term/rate selection.
- Optional balloon/residual.
- Vehicle-specific lien.
- Exact principal/payoff tracking.
- Sale/transfer requires lien settlement.
- Delinquency, cure, recovery, and closed-agreement history.

### 4. Project & Facility Finance
- Finance eligible construction/placeable purchases.
- Separate project sources and uses.
- Cash contribution.
- Loan contribution.
- Optional Red Tape grant contribution.
- Placeable-specific lien.
- Cure/collections workflow.
- Sale settlement before asset disposal.

### 5. Land Finance
- Farmland mortgage secured by economically owned land.
- Prior liens reflected in collateral value.
- Sale requires lien settlement.
- Leased land is never treated as owned collateral.

### 6. Land Leasing
- Lease from farmland-map context.
- Economic owner, operator, tenant, and collateral owner are separate concepts.
- Fixed/indexed rent.
- Minimum term, renewal, expiry, and default.
- Lease payment included in fixed-charge coverage.

## Unified underwriting

All products use one farm credit profile. Target metrics include:

- DSCR;
- fixed-charge coverage;
- debt-to-assets;
- loan-to-value;
- working capital/liquidity;
- revolver utilization;
- arrears/delinquency history;
- encumbered vs free collateral.

Borrower risk should influence rates and product availability.

## Unified settlement

No product independently takes money at period change. The settlement engine must:

1. Gather all due obligations.
2. Calculate available cash/liquidity.
3. Apply authorized revolving-credit rules.
4. Settle obligations in deterministic order.
5. Post principal, interest, fees, and rent separately.
6. Record unpaid amounts exactly.
7. Advance delinquency state.
8. Produce ledger entries and reporting snapshots.

## Unified interface

Main AgForward pages:

- Overview.
- Banking & Credit.
- Asset Finance.
- Land & Leases.
- Payments & Obligations.
- Reports.
- Government/Red Tape summary when available.
- Settings.

Contextual entry points must remain available in the vehicle dealer, construction mode, and farmland map.

## Reporting requirements

Reports must be derivable from the ledger and registries, not duplicated balances. Target outputs include:

- cash and working capital;
- total assets/liabilities/net worth;
- debt by product;
- principal vs interest paid;
- upcoming obligations;
- arrears;
- collateral and lien balances;
- lease commitments;
- expense categories;
- source-of-funds reporting (cash vs financed);
- multi-period history;
- CSV export later.

## Multiplayer requirements

- Server authoritative for every consequential finance action.
- Client requests are validated server-side.
- State synchronization cannot rely on client calculations.
- Reconnect and dedicated-server joins must receive authoritative state.

## Compatibility requirements

- AgForward must work without Red Tape.
- Red Tape integration must be adapter-based and avoid double counting.
- Trade-in integration is deferred but future lien-aware net-equity support must be possible.
