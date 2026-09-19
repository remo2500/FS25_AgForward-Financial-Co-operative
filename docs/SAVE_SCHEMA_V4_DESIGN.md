# AgForward Save Schema v4 — Design Only

**Status:** DESIGN ONLY / NOT IMPLEMENTED  
**Current runtime schema:** v3  
**Promotion gate:** Phase-0 schema-v3 persistence/recovery must pass in FS25 first.

## Purpose

Schema v3 intentionally persists only the minimum hardened Phase-0 authority needed to prove AgForward's financial-state boundary. The offline branch now contains additional asset, rights, liens, leases, external obligations, and credit/network models that will eventually need persistence.

This document designs that next persistence generation without changing the runtime candidate.

## Non-negotiable inheritance from schema v3

Schema v4 must retain:

- primary + recovery-copy architecture;
- monotonic `saveGeneration`;
- choose-newest-valid-copy behavior;
- integrity validation before accepting a copy;
- integrity validation before writing;
- unsupported-newer-schema write protection;
- `READ_ONLY_SAFE_MODE` on unrecoverable ambiguity/corruption;
- server-only authoritative save/write behavior;
- persistent ID counters sufficient to prevent ID reuse.

No v4 implementation may weaken those guarantees.

## Proposed root

```xml
<agForwardFinance schemaVersion="4" saveGeneration="42">
    <idCounters ... />
    <settings ... />
    <state ... />
    <liabilities>...</liabilities>
    <transactions>...</transactions>
    <settlement ... />
    <assets>...</assets>
    <assetRights>...</assetRights>
    <liens>...</liens>
    <leases>...</leases>
    <externalObligations>...</externalObligations>
    <creditState>...</creditState>
    <periodSnapshots>...</periodSnapshots>
    <integrations>...</integrations>
</agForwardFinance>
```

Exact XML names are provisional until implementation review.

## 1. Assets

Persist economic asset authority, not transient engine objects.

Proposed required fields:

- AgForward asset ID;
- asset type (`vehicle`, `placeable`, `farmland`, future types);
- economic-owner farm ID where applicable;
- stable external/engine identity metadata;
- display/reference metadata sufficient for relinking diagnostics;
- acquisition basis/value metadata where AgForward owns that information;
- lifecycle state;
- unresolved/quarantine state and relink metadata.

Do **not** persist a transient network/object ID as the primary identity.

On load, an unresolved engine link must leave the economic asset record intact and enter quarantine/retry handling. It must not be treated as a sale, deletion, or debt payoff merely because the game object is not immediately available.

## 2. Asset rights

Rights must remain separate from ownership.

Proposed fields:

- right ID;
- asset ID;
- farm/party ID;
- right type (`economicOwner`, `operator`, `tenant`, etc.);
- effective start/end financial period;
- status;
- source/reference (lease, purchase, administrator action, etc.).

This is especially important for farmland leasing so engine access workarounds never become balance-sheet ownership authority.

## 3. Liens

Proposed fields:

- lien ID;
- asset ID;
- liability ID;
- lienholder/source type;
- priority;
- secured amount/basis where needed;
- status;
- creation/release period;
- metadata for external prior claims where represented.

Integrity rules should reject:

- lien to unknown asset;
- AgForward lien to unknown liability;
- duplicate active lien identity;
- invalid priority;
- released lien represented as active security.

Lien priority must remain distinct from asset market value and lending-value policy.

## 4. Leases

Persist economic lease records rather than relying on engine land ownership.

Proposed fields:

- lease ID;
- asset ID;
- lease type;
- lessee farm ID;
- lessor identity/reference;
- lifecycle status;
- periodic rent;
- payment frequency;
- term/remaining term;
- start/next-due/end periods;
- accrued rent/fees;
- renewal policy metadata.

Lease payment history itself should remain in the central ledger; do not duplicate transaction history inside the lease record.

## 5. External obligations

External/base-game debt represented for underwriting should be persistable when AgForward cannot deterministically rediscover the obligation every load.

Proposed fields:

- external obligation ID;
- farm ID;
- source type/source key;
- product/category;
- represented principal;
- scheduled debt service/frequency;
- secured/unsecured status;
- known collateral/security reference;
- last observed period;
- lifecycle/status;
- authoritative-source marker.

An external obligation is not converted into an AgForward liability merely by being represented in underwriting.

## 6. Credit state

Do **not** persist a credit score/decision as if it were permanent truth when it can be recomputed from authoritative data.

Persist only state that cannot safely be derived, such as:

- explicit policy/manual-review flags that form part of an active agreement;
- approved revolving commitment limits/borrowing-base state already contained in contract authority;
- CILOC season/cleanup state if it affects contractual availability;
- possibly last completed underwriting snapshot reference for audit/history.

Derived metrics such as DSCR, LTV, debt-to-assets, and liquidity should normally be recomputed.

## 7. Offers and multiplayer protocol state

**Financial offers should remain ephemeral by default.**

On reload/reconnect, the client can request a fresh server quote against current state. Persisting stale offers introduces avoidable pricing/context risk.

State revision needs separate design:

- authoritative saved financial state should load at a deterministic baseline revision;
- runtime mutations increment the server revision;
- operation/request IDs must remain collision-safe;
- idempotency required across the intended retry window;
- not every ephemeral request cache entry needs savegame persistence.

If future testing proves cross-save request replay is a real risk, persist only the minimum bounded idempotency record, not the full network cache.

## 8. Contract details and payment schedules

Prefer persisting **contractual inputs/state** rather than every mathematically derivable future schedule row.

Persist enough to reproduce the contract exactly:

- original principal/approved limit;
- current principal/accruals;
- product type;
- rate type/current rate;
- rate history or reset authority where necessary;
- payment frequency;
- original/remaining contractual periods;
- interest-only periods/state;
- rate-term/renewal state;
- balloon/residual amount;
- start/next due/maturity period;
- scheduled payment or contract payment rule;
- delinquency status and exact arrears.

On load, a pure schedule engine may regenerate future rows and integrity-check them against persisted contract markers.

If runtime testing shows a schedule cannot be regenerated deterministically across future mod versions, introduce a versioned contract-math convention and/or persist immutable schedule authority for agreements created under older conventions.

## 9. Period snapshots/history

Period snapshots should be append-only reporting history, not an alternative balance authority.

Potential snapshot fields:

- farm ID;
- year/period;
- cash;
- represented assets/liabilities/net worth;
- debt by product;
- interest/fees/principal paid;
- line limits/utilization;
- lease fixed charges;
- selected credit metrics.

If snapshot history is corrupt but core balance authority is valid, the recovery policy may eventually allow reporting-history quarantine rather than invalidating the entire financial book. That policy must be explicit and tested before implementation.

## 10. Migration v3 -> v4

Initial migration concept:

1. load and fully validate v3 using existing code;
2. initialize all new registries empty;
3. retain all v3 liabilities, ledger entries, settlement marker, and ID counters exactly;
4. observe/reconcile new ID scopes;
5. create no synthetic asset/lien/lease records unless a separate deterministic migration rule has been approved;
6. first successful post-migration save writes v4 primary + recovery copies at the same new generation;
7. never overwrite the only valid v3 source until a complete v4 write has succeeded under the recovery-copy strategy.

## 11. Integrity order for v4

Suggested validation sequence:

1. schema/header/generation;
2. ID counters;
3. farms/basic scalar fields;
4. assets;
5. liabilities;
6. asset rights;
7. liens and cross-references;
8. leases and asset/farm references;
9. external obligations;
10. ledger transactions/groups;
11. settlement/idempotency state;
12. optional reporting snapshots/integration metadata.

Cross-reference validation should happen only after the referenced registries are loaded into a temporary candidate state.

## 12. Atomic load rule

Never partially mutate the live service container while testing a candidate v4 copy.

Preferred implementation approach:

- parse candidate copy into temporary registries/state;
- run complete structural + cross-reference integrity validation;
- only then swap/commit the entire candidate state into live services.

This extends the same principle already established for atomic ledger and financial operations to savegame loading.

## Promotion checklist

Do not begin v4 code until:

- schema-v3 clean/new-save test passes in FS25;
- primary/recovery generation behavior passes;
- corrupt-primary recovery passes;
- both-invalid safe mode passes;
- newer-schema protection passes;
- Red Tape save-hook coexistence passes;
- multiplayer local-file authority behavior passes;
- stable collateral identity research is verified in actual FS25 runtime.

Until then, this document is planning authority only and `schemaVersion="3"` remains the runtime truth.
