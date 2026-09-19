# Agricultural Lending Realism Research

**Status:** design reference, not a copied product specification  
**Date:** 2026-09-16  
**Purpose:** identify common Canadian agricultural lending structures that make AgForward feel like a specialized farm lender rather than a generic bank mod.

## Reference approach

This document uses public lender information as market research only. AgForward remains an original fictional institution and must not copy lender branding, proprietary UI, text, assets, or code.

Public references reviewed:

- Farm Credit Canada agriculture financing overview: https://www.fcc-fac.ca/en/financing/agriculture
- FCC Input Financing: https://www.fcc-fac.ca/en/financing/agriculture/inputs
- FCC Equipment Financing: https://www.fcc-fac.ca/en/financing/agriculture/finance-equipment
- FCC Land and Buildings: https://www.fcc-fac.ca/en/financing/agriculture/land-buildings
- FCC borrowing basics: https://www.fcc-fac.ca/en/knowledge/borrowing-basics
- FCC livestock financing: https://www.fcc-fac.ca/en/financing/agriculture/livestock
- FCC transition financing: https://www.fcc-fac.ca/en/financing/agriculture/transition
- RBC agriculture loans/lines: https://www.rbcroyalbank.com/business/loans/agriculture-loans-credit-lines.html
- RBC Canadian Agricultural Loans Act loan information: https://www.rbcroyalbank.com/business/loans/canadian-agricultural-loans.html

## Market patterns relevant to AgForward

### 1. Farm debt is not necessarily paid monthly

Agricultural lenders commonly structure payments around farm cash flow. Public Canadian examples describe customized repayment schedules and monthly, quarterly, semi-annual, or annual payments.

**AgForward implication:** payment frequency must be a contract attribute rather than a global monthly assumption.

Implemented offline foundation:

- `paymentsPerYear` is now optional in the common amortization/quote engine;
- monthly remains the backward-compatible default;
- the pure payment-frequency service maps monthly/quarterly/semi-annual/annual structures onto the 12 FS financial periods;
- first-payment deferral can be represented independently from the recurring cadence.

No live settlement behavior has changed.

### 2. Payment season matters

Land/building lending is commonly described as allowing payments to match growing cycles, construction, or other income timing. Dedicated crop-input financing can also be structured so repayment occurs after the crop-marketing window rather than immediately after purchase.

**AgForward implication:** a loan needs both:

- payment frequency; and
- payment anchor/first-due timing.

An annual payment should be able to fall after harvest rather than simply 12 periods after an arbitrary menu action if the borrower chooses a seasonal due month.

### 3. Interest-only and deferred-principal periods are legitimate farm structures

Public agricultural lending material includes interest-only periods, deferred payments, and temporary principal deferrals as cash-flow tools.

**AgForward implication:** future term/project/land contracts should support explicit payment phases such as:

1. construction/disbursement;
2. interest-only;
3. regular amortization;
4. optional balloon/maturity.

This should be modeled as contract phases, not by pretending a missed principal payment is delinquent.

### 4. Equipment finance should reflect asset life

Public lender guidance commonly matches loan length to the useful life/age of equipment, with longer structures for newer machinery and shorter structures for used equipment. Dealer finance also commonly takes security over the financed equipment and offers fixed/variable rates.

**AgForward implication:** equipment underwriting should eventually consider:

- new versus used equipment;
- asset age/useful life;
- requested amortization;
- down payment/equity;
- equipment collateral value;
- fixed/variable pricing;
- dealer-point-of-purchase workflow.

Do not hard-code one real lender's term/down-payment table as AgForward policy. Calibrate AgForward's fictional policy against FS25 economics.

### 5. Input finance is seasonal and purpose-specific

Public agricultural lending includes dedicated financing for fuel, fertilizer, and crop protection, sometimes with pre-approved limits and repayment aligned with crop marketing.

**AgForward implication:** the existing CILOC direction is appropriate, but it should retain:

- pre-approved seasonal capacity;
- exact eligible-purpose classification;
- farm/season borrowing base;
- purchase-time funding authorization;
- optional harvest/grain-sale sweep;
- configurable seasonal maturity/cleanup rule;
- ability to finance eligible inputs without losing their operating-expense classification.

A future policy can offer both revolving-line behavior and a more seasonal input-loan structure without creating a second accounting authority.

### 6. Reusable pre-approved credit is common

Agricultural operating and equipment credit products frequently emphasize re-use of approved borrowing capacity as balances are repaid.

**AgForward implication:** revolving facilities should distinguish:

- approved limit;
- drawn balance;
- temporary reservations;
- available credit;
- suspended/frozen capacity;
- borrowing-base constrained capacity where applicable.

The current CILOC reservation and borrowing-base models already move in this direction.

### 7. Prepayment flexibility belongs in the contract

Public lender material shows both penalty-free prepayment products and loans whose prepayment provisions depend on the selected interest structure.

**AgForward implication:** future liability terms should explicitly represent a prepayment policy rather than assuming either unlimited free prepayment or universal penalties.

Suggested fictional policy types:

- `OPEN` — principal can be prepaid without charge;
- `ANNUAL_ALLOWANCE` — a defined annual portion is free, excess may incur a charge;
- `CLOSED` — early payoff can carry a calculated charge;
- `NONE` — special/internal structures only.

No production prepayment-charge formula should be locked until game-balance testing is available.

### 8. Project finance needs staged funding, not only a single purchase loan

Agricultural land/building/project lending commonly supports extended disbursements and construction-oriented payment flexibility.

**AgForward implication:** `ProjectSourcesUsesService` should eventually feed a draw schedule so project debt can be advanced as construction costs occur. Interest should accrue on funds actually advanced rather than the entire approved commitment from day one.

This remains an offline design requirement; no live construction hook is enabled.

### 9. Specialized products can come later without compromising the core

Canadian lenders also offer livestock, transition/succession, young-producer, environmental, and government-supported structures.

These demonstrate why the shared architecture should be extensible, but AgForward should not add every specialty product before the common ledger/credit/settlement system is runtime proven.

Potential later modules:

- livestock feeder/breeder finance;
- transition/vendor-style scheduled disbursement finance;
- young-producer policy overlays;
- environmental/project incentives via Red Tape/grant integration.

## Recommended implementation order from this research

1. Preserve current monthly behavior while adding flexible payment-frequency math and due-period scheduling. **Offline implementation started.**
2. Add pure payment-phase modeling for interest-only/deferred-principal periods.
3. Add payment-anchor/season selection to the future contract/quote model.
4. Add open/closed prepayment policy representation without locking penalty amounts.
5. Add staged project draw modeling.
6. Calibrate term/down-payment/credit thresholds only after observing actual FS25 farm cash flows.
7. Defer specialty livestock/transition products until the core runtime is proven.

## Design guardrail

Real-lender observations should inform *economic behavior*, not make AgForward a replica. The finished mod should use its own product names, policy values, UI, wording, assets, and implementation while reproducing the broad financial concepts needed for believable agricultural lending.
