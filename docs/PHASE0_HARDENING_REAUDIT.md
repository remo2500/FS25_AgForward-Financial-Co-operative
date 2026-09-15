# Phase 0 Hardening Re-Audit

**Date:** 2026-09-15  
**Branch:** `phase0-foundation-hardening`  
**Target build:** `0.0.4.0`  
**Authority:** `A004-HARDENING`  
**Status:** CODE REVIEW PASS WITH RUNTIME GATES REMAINING

This document re-audits the AgForward hardening branch after the donor/reference re-audit and records which prior risks are resolved in code, which are intentionally deferred, and which require Farming Simulator 25 runtime proof.

## 1. Executive result

The hardening pass materially improves the Phase 0 foundation and no donor finding requires a redesign of the AgForward architecture.

**Code-review conclusion:** suitable to advance to a disposable-save runtime-validation candidate after branch/CI review.  
**Not yet authorized:** real FS25 money movement, production-save use, main-branch runtime promotion, or release packaging.

The branch now has a fail-safe persistence model, write-blocking safe mode, cent normalization, immutable posted journal records, protected liability mutation, a coordinated multi-record operation boundary, persisted settlement idempotency, context-aware crop-input classification, high-frequency input accumulation, overlap warnings, static repository validation, and a comprehensive donor/reference research record.

## 2. Pre-hardening critical findings and disposition

| Prior finding | Current disposition | Evidence / remaining gate |
|---|---|---|
| Failed financial-state load could initialize writable empty state | **Resolved in design/code** | Failed/corrupt loads enter `READ_ONLY_SAFE_MODE`; legitimate absence alone creates `NEW_STATE`. Runtime corruption test still required. |
| Newer unknown schema could be rewritten by older build | **Resolved in design/code** | Candidate ordering prefers newest generation/schema; newer unsupported schema blocks mutation/save. Runtime newer-schema test required. |
| Single live save copy had weak recovery | **Resolved with dual-copy recovery** | Schema v3 writes/validates recovery then primary using monotonic generation. This is not claimed to be filesystem-transactional. Power-loss/recovery runtime testing required. |
| Financial mutations not server-gated | **Resolved for current Phase 0 mutation services** | Runtime state requires server authority; accounting/ledger/liability paths use it. Future events must preserve the rule. |
| Settlement idempotency existed only in memory | **Resolved in schema v3** | Versioned last-completed settlement key persists. Phase 0 remains no-op. Runtime duplicate period callback test required. |
| Posted ledger records remained mutable | **Resolved** | Transactions seal at posting; public getters return clones. Runtime/dev immutability test remains. |
| Liability records could be mutated through shared object handles | **Resolved after re-audit correction** | Registry clones drafts on registration; public getters return clones; direct public balance mutation requires operation coordinator. |
| Ledger and liability draw were separate mutations | **Resolved for current CILOC proof operation** | `AGFFinancialOperationCoordinator` posts linked ledger records and applies liability balance with rollback on failure. Actual FS cash movement must later join the same boundary. |
| Corrupt records could be silently skipped and writable state accepted | **Resolved** | Load functions return errors; integrity gate rejects the copy and attempts another; no compatible copy -> safe mode. |
| No post-load reconciliation | **Resolved for current Phase 0 data model** | Integrity service checks taxonomies, values, limits, references, group balance, IDs. Asset/link checks await asset registry. |
| Floating money comparison policy undefined | **Resolved for currency amounts** | `AGFCurrency` normalizes operations to cents. Interest-rate/amortization convention remains intentionally unresolved before Phase 1. |
| CILOC depended too heavily on MoneyType | **Resolved at classification-service level** | Classifier accepts fill type/caller context and refuses to guess generic material purchases without context. Live hooks are not installed yet. |
| High-frequency helper inputs could flood ledger | **Resolved at accumulator-foundation level** | Cent-based accumulator exists. Flush policy and live hooks are future money-boundary work. |
| Overlapping donor finance mods could silently coexist | **Resolved as development warning** | Compatibility service warns on known overlapping finance mods. This is not a compatibility guarantee. |
| Technical specification drifted from code | **Resolved** | Technical specification updated to 0.2 and canonical `creditDraw` + generic `inputPurchase`/expense-category model. |
| No automated repository validation | **Partially resolved** | Python static validator + GitHub Actions added. GIANTS TestRunner remains an external/runtime packaging gate. |

## 3. Donor findings checked against current architecture

### Bank & Credit

**Research lesson:** connection-derived farm authorization, server-side term validation, full-state snapshot sync, and late-join duplicate defense are strong patterns.

**Current AgForward status:**
- server-only mutation core exists;
- client request/snapshot events are **not implemented yet**;
- state revision/operation ID must be designed with the first multiplayer events;
- central settlement architecture already avoids donor-style product-local collection;
- base-game `farm.loan` policy is explicitly unresolved before whole-farm underwriting.

**Action:** keep multiplayer initial sync as a remaining Phase 0 deliverable, but do not add it before persistence runtime proof unless required to validate dedicated-server save authority.

### Finance Your Fleet

**Research lesson:** stable vehicle unique IDs, delayed disappearance confirmation, unresolved-link retry, and save-slot identity checks are valuable. Client-supplied authoritative agreements are not.

**Current AgForward status:**
- no asset registry exists yet, so no premature vehicle-link implementation is present;
- persistence recovery is now centralized rather than product-specific;
- future asset registry must add save identity + stable asset ID + quarantine/retry before equipment finance goes live.

**Action:** create `AssetRegistry`/`AssetLinkQuarantine` in Phase 2 foundation work, before equipment purchase integration.

### AgriCredit Solutions

**Research lesson:** server-originated finance creation and lien-aware sale preflight are strong; unresolved placeables should not cause automatic debt deletion.

**Current AgForward status:**
- server mutation boundary is ready;
- no secured-disposition service yet because assets/liens are not implemented;
- design remains locked for a common service across vehicles/placeables/land.

**Action:** implement a generic `SecuredAssetDispositionService` with the asset/lien registry, not one copy per finance product.

### Field Leasing

**Research lesson:** engine farmland ownership may be useful for gameplay access but is unsafe as economic/collateral truth; client-provided rent/farm data must not be authoritative.

**Current AgForward status:**
- authority already locks economic owner/operator/tenant/lienholder as separate concepts;
- no land-access workaround is implemented yet;
- central settlement will own rent obligations.

**Action:** keep engine-access mechanics behind a future farmland-rights adapter and exclude them from owned collateral.

### Economic History

**Research lesson:** `farm.loan` and FinanceStats alone cannot represent AgForward debt; server-generated read-only snapshots are useful.

**Current AgForward status:**
- ledger + liability registry are authoritative;
- reporting module not yet implemented;
- external/vanilla obligations still need an explicit representation policy.

**Action:** use FinanceStats as supplemental operating-history inputs only; reporting and credit consume AgForward registry plus intentionally modeled external obligations.

### Red Tape

**Research lesson:** `rawget(Mission00, "saveSavegame")` target selection is important; hook installation timing must still be proven; Red Tape filters unknown `statistic="other"`; it already observes Farm.changeBalance, creating double-count risk.

**Current AgForward status:**
- save-hook target selection follows the safe pattern;
- adapter remains detection-only;
- no production tax bridge exists yet;
- Phase 0 QA now explicitly tests save-hook timing/coexistence.

**Action:** do not introduce Red Tape line-item injection until the real AgForward MoneyType/cash boundary exists and each transaction class is reconciled against Red Tape behavior.

### Vehicle Trade In

**Research lesson:** server revalidation of client-selected financing terms and asset attachment is strong; duplicate vehicle-finance authority is not acceptable.

**Current AgForward status:**
- trade-in remains deferred;
- future gross trade value will be treated as an input to AgForward lien/payoff/equity logic.

**Action:** no Phase 0 code needed.

## 4. Current-source design audit

### Persistence

**Pass at design/code-review level.**

Key strengths:
- legitimate new state is distinct from failed load;
- incompatible newer schema is write-protected;
- primary/recovery copies use a common generation;
- highest generation, then highest schema, is preferred;
- record/integrity failure can fall back to another copy;
- pre-save integrity gate prevents knowingly corrupt state from being persisted.

Runtime unknowns:
- exact GIANTS XML API behavior while overwriting both files;
- behavior if game/process stops between recovery and primary writes;
- save-hook order/timing with Red Tape and other appended hooks.

### Ledger

**Pass at current Phase 0 scope.**

- posted entries are sealed;
- public query results are copies;
- batch is prevalidated;
- synchronous tail rollback exists;
- purpose/funding dimensions remain independent;
- linked funded-input groups reconcile to zero.

Future requirement:
- actual FS cash mutation must be represented as an operation boundary outcome, not as an independently issued side effect.

### Liabilities

**Pass after hardening correction.**

- authoritative registry does not retain caller's mutable draft object;
- public reads are copies;
- direct public balance changes are blocked;
- committed balance mutations are internal coordinator functions;
- cent precision applies to principal/limit/payment amounts.

Future requirement:
- loan/rate/amortization services must never mutate stored liability fields directly; add explicit registry/coordinator operations for every balance/status transition.

### CILOC

**Pass as accounting/classification foundation; not yet live.**

Proven by design:
- draw and expense are separately classified and linked;
- facility/farm/product/limit are validated;
- eligible expense purpose survives financing;
- generic material purchase is not guessed without context;
- helper-scale charges can be aggregated in cents.

Not yet implemented:
- pre-purchase affordability/authorization hook;
- live fill-type capture at all buying paths;
- actual credit-funded cash movement;
- flush policy for accumulator;
- Red Tape/FinanceStats bridge.

### Settlement

**Pass as idempotency foundation; no money movement yet.**

Future settlement engine must increment engine version and persist operation-level results in addition to the period completion key.

### Multiplayer

**Core authority gate passes; synchronization remains incomplete.**

Current protection prevents a client from becoming local file authority or invoking writable core mutations through ordinary calls. However, AgForward still needs:
- request events;
- connection-derived farm/permission validation;
- state revision;
- initial snapshot event;
- join-in-progress synchronization;
- delta operation IDs;
- explicit result/error events.

This remains a Phase 0 exit requirement before multiplayer is declared supported in practice.

### Red Tape

**Pass as non-invasive Phase 0 integration.**

Detection-only behavior is appropriate until money classification is real. Save-chain timing is a runtime gate.

## 5. Findings intentionally deferred

These are not defects in the current Phase 0 foundation; they are dependencies for later work and are explicitly tracked:

1. **Interest-rate convention** — decimal storage, compounding, variable reset timing, amortization rounding; lock before Phase 1 loan math.
2. **Vanilla/base-game debt policy** — import, external-obligation representation, or deliberate replacement; lock before whole-farm credit metrics.
3. **Asset/right/lien registry** — required before equipment/project/land finance.
4. **Asset-link quarantine and save identity** — required before secured assets can recover/relink.
5. **Secured disposition service** — required before financed asset sale/trade.
6. **Live FS money boundary / MoneyTypes / FinanceStats** — next major integration after persistence runtime proof.
7. **Red Tape transaction bridge** — only after live money classification is observable and tested.
8. **Multiplayer state sync/events** — remaining Phase 0 work.
9. **Minimal read-only UI** — remaining Phase 0 work.
10. **Farm lifecycle handling** — create/delete/merge/ownership transitions must be handled before production multiplayer finance.

## 6. Runtime-candidate gate

The branch may be packaged for a **disposable-save persistence test** only if:

- static repository validation passes;
- branch diff contains no unexpected donor code/assets;
- `modDesc.xml` source order is valid;
- CI passes;
- no new code-review blocker appears in the pull-request diff.

The first runtime candidate must **not**:

- touch a primary user save;
- move real AgForward money;
- be described as multiplayer-complete;
- be merged to `main` as runtime proven.

## 7. Promotion gate to main

Promote/merge the hardening branch only after the Phase 0 persistence QA proves at minimum:

- new save / normal reload;
- schema-v3 primary + recovery writes;
- recovery from corrupt primary;
- safe mode with both copies invalid;
- newer-schema overwrite protection;
- deterministic IDs/ledger/liabilities;
- CILOC linked-operation persistence and rollback behavior;
- settlement idempotency;
- Red Tape save-hook coexistence;
- server-only file/mutation authority.

Multiplayer initial-state sync may be merged in the same Phase 0 PR or a follow-up Phase 0 PR, but multiplayer must not be called runtime complete until it is implemented and tested.

## 8. Final re-audit conclusion

**No architecture reversal is required.** The donor re-audit reinforces the common-service design already chosen for AgForward.

The hardening branch has addressed the data-loss, mutation-integrity, accounting-classification, and settlement-idempotency concerns that should be fixed before first runtime persistence testing. The remaining high-risk areas—real FS money movement, multiplayer synchronization, asset/link identity, secured disposition, and Red Tape accounting—are now explicitly gated behind later implementation stages rather than being allowed to leak into the foundation prematurely.
