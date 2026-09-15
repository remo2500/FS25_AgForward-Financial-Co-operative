# AgForward Action Audit — Functional Lessons from Reference Mods

This document records implementation-neutral lessons from auditing the supplied FS25 finance-related mods. It is not source code documentation for reuse.

## Bank & Credit

Useful purposes observed:
- bank-level loan products;
- amortizing, bullet, and revolving structures;
- interest-rate model;
- whole-farm style credit metrics;
- annual reporting;
- principal and interest as distinct finance statistics;
- server-authoritative collection/synchronization patterns.

AgForward improvement target:
- underwriting must see **all** AgForward debt and fixed obligations, not only bank-originated loans;
- collateral must be net of liens;
- leased land cannot be counted as owned collateral;
- one settlement engine replaces product-local collection.

## Finance Your Fleet

Useful purposes observed:
- financing integrated into the vehicle-purchase experience;
- asset-specific agreements;
- down-payment and term configuration;
- balloon/residual structures;
- vehicle linking and payoff/recovery concepts.

AgForward improvement target:
- one common liability/amortization engine;
- deterministic cash validation before collection;
- exact principal/interest/fee accounting;
- whole-farm credit pricing;
- server-authoritative validation;
- sale/transfer through a generic lien-settlement service.

## AgriCredit Solutions

Useful purposes observed:
- financing integrated into construction/placeable purchase;
- financed-building liens;
- delinquency, cure, and collections concepts;
- strong concept for settling a secured liability when a financed asset is sold.

AgForward improvement target:
- use the same finance engine as equipment and bank loans;
- separate principal/interest/fees consistently;
- connect grants/project equity as distinct sources of funds;
- generalize secured-sale settlement for equipment, facilities, and land.

## Field Leasing

Useful purposes observed:
- farmland-map lease workflow;
- rent and term handling;
- granting the player practical operating access.

Critical issue to avoid:
- engine-level farmland ownership used to provide access can be mistaken for economic ownership/collateral.

AgForward requirement:
- explicitly distinguish economic owner, operator, tenant, and collateral owner;
- leased land is excluded from owned assets and collateral;
- lease obligations enter fixed-charge/credit calculations.

## Economic History

Useful purposes observed:
- multi-period financial history;
- finance-stat based reporting;
- export/reporting value.

AgForward improvement target:
- report from AgForward's complete liabilities and ledger, not vanilla `farm.loan` alone;
- retain source-of-funds and expense-category information;
- include net equity, liens, leases, arrears, and debt service.

## Vehicle Trade In

Useful purposes observed:
- vehicle valuation and trade workflow;
- dealer/used-equipment concepts;
- potential financing interaction point.

Status:
- native trade-in feature is deferred.

Architecture requirement retained now:
- assets and liens must support future `gross value - payoff - accrued charges = net trade equity`.

## Red Tape

Useful purposes retained externally:
- tax system;
- loss carryforward;
- grants;
- policies;
- schemes;
- fines/regulatory consequences.

AgForward requirement:
- preserve transaction meaning so Red Tape can receive correct categories;
- do not treat credit draws as income;
- do not treat principal repayment as expense;
- separate interest, rent, and fees;
- avoid double-counting events Red Tape already observes through native FS money changes.

## Whole-system conclusions

The reference stack's biggest systemic weakness is independent financial authority. Each mod can maintain its own debt, payment timing, and classification.

AgForward therefore adopts:

1. one ledger;
2. one liability registry;
3. one asset/right/lien registry;
4. one credit engine;
5. one settlement coordinator;
6. one accounting taxonomy;
7. contextual purchase interfaces backed by the same core services.

The goal is to reproduce the **purposes** that work well while removing cross-mod inconsistency and independently implementing all AgForward code and UI.
