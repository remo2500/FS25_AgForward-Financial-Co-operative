# Phase 0 Foundation Hardening

**Branch:** `phase0-foundation-hardening`  
**Target build:** `0.0.4.0`  
**Status:** CODE IMPLEMENTED / RUNTIME VALIDATION PENDING

This pass addresses the pre-runtime audit findings before AgForward is permitted to move real FS25 money.

## Implemented safeguards

### Financial state safety

- Added central runtime state service.
- Distinguishes legitimate `NEW_STATE` from failed/corrupt load.
- Added `READ_ONLY_SAFE_MODE` that blocks mutation and saving.
- Newer unknown save schemas are never overwritten by an older AgForward build.

### Persistence

- Save schema advanced to v3.
- Added monotonic `saveGeneration`.
- Added `agForwardFinance.backup.xml` recovery copy.
- Recovery copy is written/verified before primary.
- Load selects the newest compatible validated copy.
- Record-load failures no longer silently count as a successful load.
- Full integrity reconciliation runs after load and before save.

### Ledger integrity

- Posted transactions are sealed.
- Public ledger reads return cloned transaction records.
- Batch posting performs whole-batch prevalidation.
- Batch rollback support exists for synchronous multi-record operations.
- Currency operations normalize to cents through one shared helper.

### Liability integrity

- Liability mutations require writable server authority.
- Draw validation uses integer-cent comparisons at the limit boundary.
- Revolving credit still treats accrued interest/fees separately from principal utilization.

### Financial operation coordination

- Added a financial operation coordinator.
- A revolving input purchase now commits its linked draw/purchase ledger records and liability draw as one coordinated operation.
- If liability application fails after ledger posting, the just-posted batch is rolled back.

This is still an in-memory atomicity boundary. Actual FS25 cash movement has intentionally not been added yet; that later boundary must be included in the same operation coordinator.

### Settlement idempotency

- Settlement completion key is persisted.
- Key includes a settlement-engine version plus year/period.
- Duplicate period-change callbacks for the same engine/year/period do not rerun settlement.
- Phase 0 uses engine version `0`; a future money-moving engine must increment the version.

### Crop-input classification foundation

- Added a purchase classification service.
- Recognizes seed, fertilizer/liquid fertilizer, lime, herbicide/crop protection, and fuel from available MoneyType/fill-type context.
- Generic `BOUGHT_MATERIALS` is not guessed when fill-type context is missing.
- Added cent-based high-frequency purchase accumulator for AI/helper seed/fertilizer/fuel charges.

No live purchase hook is installed yet. The classifier/accumulator are preparation for the future FS25 money-movement boundary.

### Compatibility

- Added warnings for known overlapping finance mods:
  - Bank & Credit;
  - Finance Your Fleet;
  - AgriCredit Solutions;
  - Field Leasing;
  - Economic History;
  - Trade In Menu.
- Red Tape remains an intentional optional integration and is not flagged as a conflict.

## Still intentionally not implemented

- Actual `g_currentMission:addMoney` funding/settlement boundary.
- MoneyType/FinanceStats registration for AgForward transactions.
- Multiplayer request/state-sync events.
- Farm lifecycle migration/remapping.
- Vanilla `farm.loan` migration/disable/import policy.
- Live purchase hooks for buying stations, helper purchases, vehicle dealer, construction, or farmland.
- UI/dashboard.
- Production Red Tape classification bridge.

## Required runtime validation before main-branch promotion

1. New save starts as `NEW_STATE`.
2. First save creates both primary and backup copies with matching schema/generation.
3. Normal reload chooses primary and reaches `NORMAL`.
4. Corrupt primary while leaving backup intact; reload must reach `RECOVERED` from backup.
5. Corrupt both copies; AgForward must enter `READ_ONLY_SAFE_MODE` and must not overwrite them.
6. Artificially set schema above supported version; AgForward must enter safe mode and preserve the files.
7. Repeated save/reload must never reuse TX/GRP/LIAB IDs.
8. CILOC linked test group must survive save/reload exactly.
9. Duplicate/invalid saved records must fail the integrity gate rather than silently disappearing.
10. Red Tape installed/not-installed paths must both save normally.
11. Multiplayer client must not write local AgForward financial state.

## Promotion rule

Do not merge this hardening branch to `main` as runtime-proven authority until the above validation is completed. Documentation and source on the branch represent the intended design; `main` remains the last reviewed baseline until promotion.
