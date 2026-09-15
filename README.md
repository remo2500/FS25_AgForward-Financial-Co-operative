# AgForward Financial Cooperative

**Public brand:** AgForward  
**Project type:** Farming Simulator 25 financial-system mod  
**Repository:** `remo2500/FS25_AgForward-Financial-Co-operative`

AgForward is an original, agriculture-focused financial framework for Farming Simulator 25. The project is designed as one coherent financial institution rather than a collection of disconnected loan mods.

## Target scope

AgForward is intended to natively provide:

- revolving operating credit;
- Crop Input Lines of Credit;
- short- and long-term farm loans;
- equipment financing and liens;
- project/facility financing and liens;
- farmland mortgages;
- farmland leasing and operating-rights tracking;
- one whole-farm credit model;
- one rate/pricing model;
- one central monthly settlement engine;
- delinquency, arrears, collections, and recovery;
- one financial ledger with principal, interest, fees, and expense-purpose separation;
- balance-sheet, cash-flow, debt, collateral, and historical reporting;
- multiplayer-safe, server-authoritative financial actions;
- optional Red Tape integration for taxes, grants, policy, and regulation.

Trade-in/dealer functionality is intentionally deferred until the native financial core is mature.

## Governing / research documents

- `docs/AGFORWARD_CURRENT_AUTHORITY.md` — current branch authority and locked decisions.
- `docs/AGFORWARD_TECHNICAL_SPECIFICATION.md` — current system architecture and technical contracts.
- `docs/PRODUCT_REQUIREMENTS.md` — player-facing product requirements.
- `docs/DEVELOPMENT_ROADMAP.md` — staged implementation plan.
- `docs/DONOR_REFERENCE_REAUDIT.md` — comprehensive implementation-neutral donor/reference re-audit.
- `docs/PHASE0_HARDENING_REAUDIT.md` — post-hardening code/design re-audit and remaining gates.
- `docs/PHASE0_PERSISTENCE_QA.md` — disposable-save runtime validation plan.
- `docs/SAVE_SCHEMA_V3.md` — fail-safe financial persistence schema.
- `docs/REDTAPE_INTEGRATION.md` — optional Red Tape accounting/integration boundary.
- `docs/LICENSE_AND_REFERENCE_POLICY.md` — rules for independent implementation and third-party references.

## Current status

Development is currently on **Phase 0 — Foundation & Financial Integrity**.

The `phase0-foundation-hardening` branch contains build target `0.0.4.0` and authority `A004-HARDENING`. It adds:

- read-only safe mode and newer-schema write protection;
- dual-copy financial persistence with recovery generations;
- post-load/pre-save integrity validation;
- cent-normalized money handling;
- immutable posted ledger records;
- protected native liability balances;
- coordinated linked financial operations;
- persisted settlement idempotency;
- Crop Input LOC purchase classification/accumulation foundations;
- known overlapping-finance-mod warnings;
- static repository validation and CI;
- a full donor/reference re-audit.

**Runtime validation is still pending.** The hardening branch intentionally does not move real AgForward money yet and is not considered production-save ready.

## Naming

Formal institution name: **AgForward Financial Cooperative**  
Player-facing brand: **AgForward**  
Target mod package: **`FS25_AgForwardFinance`**  
Primary namespace: **`AgForwardFinance`**  
Internal prefix: **`AGF`**

## Original implementation policy

AgForward is independently implemented under the repository's MIT license. Third-party mods may be studied for player-facing behavior, compatibility requirements, FS25 extension points, and failure modes, but their protected source code, assets, strings, icons, UI, or distinctive implementation details are not copied into AgForward.
