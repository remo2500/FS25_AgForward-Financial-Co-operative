# AgForward External / Base-Game Obligation Policy

**Status:** design baseline for underwriting/reporting; no live import yet  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

AgForward cannot claim whole-farm underwriting if it only sees debt created inside AgForward. At the same time, silently converting or deleting base-game/third-party obligations would be unsafe. This document defines the intended boundary.

## 1. Native AgForward debt

AgForward's liability registry is authoritative for obligations created by AgForward, including:

- operating lines;
- Crop Input Lines of Credit;
- term loans;
- equipment finance;
- project/facility finance;
- land finance.

Native balances are never reconstructed from `farm.loan` or from UI summaries.

## 2. Base-game `farm.loan`

Base-game loan debt should initially be represented as an **external obligation**, not silently imported as a native AgForward agreement and not forcibly cleared merely because AgForward is installed.

The future external-obligation adapter should capture at minimum:

- borrower farm;
- current outstanding balance;
- known/assumed interest or debt-service treatment;
- source = base game;
- whether it can be modified by AgForward;
- whether the amount is fully known or estimated.

Until AgForward explicitly owns the base-game loan workflow, it should treat this debt as externally managed but still include it in whole-farm leverage/debt-service metrics where sufficient data exists.

## 3. Base-game equipment leases

A leased vehicle is not an owned asset and should not contribute owned collateral merely because the player can operate it.

Where practical, AgForward reporting/underwriting should represent:

- lease/fixed-charge payment commitment;
- operating right/use;
- no owned-equity value unless a separate ownership interest exists.

Base-game lease mechanics remain externally managed until AgForward deliberately replaces/integrates them.

## 4. Third-party finance mods

Bank & Credit, Finance Your Fleet, AgriCredit Solutions, Field Leasing, Economic History, and similar overlapping systems are not intended to remain part of the final AgForward stack.

During development:

- detect/warn when known overlapping finance mods are active;
- do not silently combine unverified balances;
- do not claim complete whole-farm credit metrics while external debt is unknown;
- avoid automatic migration without an explicit migration/import design.

Red Tape is the intended exception because it is a government/tax integration rather than a competing debt authority.

## 5. External obligation data quality

Every represented external obligation should have a confidence/source state, for example:

- `VERIFIED` — balance and required payment known from a stable source;
- `PARTIAL` — balance known but debt-service terms incomplete;
- `ESTIMATED` — underwriting uses a deliberate conservative estimate;
- `UNKNOWN` — known debt source exists but cannot yet be quantified.

The credit profile should surface partial/unknown external debt rather than treating missing values as zero.

## 6. Underwriting treatment

Whole-farm metrics should include external obligations when they are sufficiently known.

At minimum:

- total liabilities include verified external principal;
- annual debt service includes verified or deliberately stressed required payments;
- fixed-charge coverage includes externally managed lease/rent commitments;
- collateral is not credited to the borrower if the corresponding asset is not economically owned;
- unknown material obligations reduce data-quality confidence and may restrict new approvals.

## 7. Future migration option

A later migration wizard may allow a user to convert eligible external obligations into AgForward records, but only when:

- source balance is unambiguous;
- duplicate authority can be disabled/closed safely;
- original obligation is not left active after import;
- opening principal and historical source are documented;
- rollback/recovery is possible.

Migration is not required for the first AgForward release.

## 8. Reporting

Reports should distinguish:

- AgForward native debt;
- base-game/external debt;
- total represented debt;
- known but unquantified obligations.

This keeps AgForward transparent about what it knows instead of presenting an artificially precise balance sheet.
