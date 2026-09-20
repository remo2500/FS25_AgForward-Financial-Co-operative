# AgForward Collateral Lending Value Model

**Status:** offline underwriting foundation  
**Runtime enabled:** NO

## Principle

An asset's economic/market value is not automatically the amount AgForward should lend against.

AgForward keeps four concepts separate:

1. **Market value** — economic value of the asset.
2. **Eligibility percentage** — portion of market value the policy is willing to recognize.
3. **Advance rate** — percentage of eligible value that counts as lending value.
4. **Prior claims** — higher-priority debt/liens that reduce the lending value available to AgForward.

This prevents the credit engine from treating every owned asset as fully available, unencumbered collateral.

## Pure service

`src/credit/CollateralValuationService.lua`

For each proposed collateral asset:

`eligible market value = market value × eligibility percentage`

`gross lending value = eligible market value × advance rate`

`net lending value = max(0, gross lending value - prior claims)`

The service then aggregates the collateral pool and compares it to proposed secured debt.

## Returned measures

The service reports:

- gross market value;
- eligible market value;
- gross lending value;
- prior claims;
- net lending value;
- proposed secured debt;
- gross LTV against eligible market value;
- lending-value LTV;
- net collateral coverage;
- collateral surplus/shortfall;
- whether the proposed debt is fully covered by policy lending value.

## Why this matters

Examples:

- A $500,000 older machine can remain a $500,000 economic asset while AgForward recognizes only part of that value for lending.
- Leased assets can remain visible operationally while receiving 0% collateral eligibility because the borrower does not economically own them.
- A parcel with an existing first mortgage can contribute only the lending value remaining after the prior claim.
- Specialized collateral can use a lower policy advance rate without altering its displayed market value.

## Policy calibration

No production advance-rate table is locked yet.

Equipment, farmland, facilities, and other asset classes can eventually receive fictional AgForward policy defaults after FS25 economic testing. The math service intentionally requires policy inputs rather than embedding real-lender percentages.

## Relationship to liens

The current service accepts prior claims as an underwriting input. The future live collateral builder should derive those claims from:

- AgForward lien registry;
- represented external obligations where their security is known;
- any supported base-game/external security source.

A client must never supply authoritative prior-lien balances or collateral values.

## Runtime gate

The service performs no asset appraisal, FS25 object lookup, lien creation, purchase authorization, or repossession. Those remain separate runtime integrations.
