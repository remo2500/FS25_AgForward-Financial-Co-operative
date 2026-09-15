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

## Governing documents

- `docs/AGFORWARD_CURRENT_AUTHORITY.md` — current project authority and locked decisions.
- `docs/AGFORWARD_TECHNICAL_SPECIFICATION.md` — system architecture and technical requirements.
- `docs/AGFORWARD_ACTION_AUDIT.md` — lessons and functional requirements derived from reference-mod audits.
- `docs/PRODUCT_REQUIREMENTS.md` — player-facing financial products and behaviors.
- `docs/DEVELOPMENT_ROADMAP.md` — staged implementation plan.
- `docs/REDTAPE_INTEGRATION.md` — optional Red Tape accounting/integration boundary.
- `docs/LICENSE_AND_REFERENCE_POLICY.md` — rules for independent implementation and third-party references.

## Current status

**Phase 0 — Foundation / architecture baseline.**

The first implementation target is the shared core: service container, stable IDs, save/load, ledger, transaction classification, multiplayer state, settlement coordination, Red Tape detection, and a minimal AgForward finance screen.

## Naming

Formal institution name: **AgForward Financial Cooperative**  
Player-facing brand: **AgForward**  
Proposed mod package: **`FS25_AgForwardFinance`**  
Primary namespace: **`AgForwardFinance`**  
Internal prefix: **`AGF`**

## Original implementation policy

AgForward is intended to be independently implemented. Third-party mods may be studied for behavior, compatibility requirements, and interoperability, but their protected source code, assets, strings, icons, or distinctive implementation details are not to be copied into this repository.
