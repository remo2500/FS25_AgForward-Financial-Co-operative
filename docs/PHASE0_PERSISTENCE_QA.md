# Phase 0 Persistence / Integrity QA

**Target build:** 0.0.4.0  
**Schema:** v3  
**Scope:** dual-copy recovery, safe mode, persistent IDs, liabilities, immutable ledger, coordinated operations, settlement idempotency, server authority, Red Tape coexistence.

A test is not passed until it has been run in Farming Simulator 25 against a disposable test save. This document does not authorize testing on the user's primary savegame.

## 1. Static validation first

Before packaging:

1. Run `python tools/validate_repository.py`.
2. Confirm repository static validation passes.
3. Package with `modDesc.xml` at the root of `FS25_AgForwardFinance.zip`.
4. Run the current GIANTS FS25 TestRunner on the packaged ZIP.

Expected result: no missing source registrations/XML parse problems; TestRunner reports no blocking mod-package issue.

## 2. New-save initialization

Start with neither:

- `agForwardFinance.xml`; nor
- `agForwardFinance.backup.xml`.

Load the save.

Expected:

- runtime state `NEW_STATE`;
- zero liabilities;
- zero ledger transactions;
- no money movement;
- normal gameplay reached without Lua error.

## 3. First save creates two matching copies

Save normally.

Expected:

- primary `agForwardFinance.xml` exists;
- recovery `agForwardFinance.backup.xml` exists;
- both have `schemaVersion="3"`;
- both have the same positive `saveGeneration`;
- ID, liability, ledger, and settlement sections are structurally valid;
- farm cash is unchanged by Phase 0.

## 4. Normal reload

Exit and reload without modifying either copy.

Expected:

- primary is selected;
- runtime state `NORMAL`;
- load status `LOADED`;
- generation is preserved;
- no duplicate initialization or duplicate save-hook effect.

Save again and confirm generation advances by exactly one.

## 5. Recovery-copy test

After a successful save:

1. Back up both AgForward files externally.
2. Corrupt only the primary XML so it cannot be parsed.
3. Reload.

Expected:

- recovery copy is selected;
- runtime state `RECOVERED`;
- load status indicates recovery;
- financial state equals the last valid generation;
- next successful save recreates two valid copies.

## 6. Both copies invalid -> safe mode

Corrupt both financial files.

Expected:

- runtime state `READ_ONLY_SAFE_MODE`;
- financial mutations are rejected;
- AgForward save writes are rejected;
- the corrupt source files are **not** overwritten as if this were a new save;
- game should remain loadable unless an unrelated FS error occurs.

Restore the externally backed-up copies after the test.

## 7. Newer-schema protection

On a disposable copy, change the newest valid AgForward copy to a schema number higher than the current supported schema while keeping the XML parseable.

Expected:

- AgForward enters `READ_ONLY_SAFE_MODE`;
- log reports newer schema / overwrite blocked;
- saving the game does not downgrade that AgForward financial file.

## 8. Persistent ID validation

After creating development records:

1. Record `TX`, `GRP`, and `LIAB` IDs.
2. Save/reload.
3. Create another ID in each used scope.

Expected example:

- prior: `AGF-TX-000001`, `AGF-GRP-000001`, `AGF-LIAB-000001`;
- next: `...000002`.

No saved/observed ID may ever be reused.

## 9. Liability draft/registry isolation

Create a development CILOC liability draft, configure it, and register it.

After registration, mutate the original draft object in test/debug code.

Expected:

- authoritative registry copy does **not** change;
- `get()`/`getAll()` return copies, not writable authoritative records;
- direct public `applyDraw()` and `applyPrincipalPayment()` return `OPERATION_COORDINATOR_REQUIRED`.

This proves liability balance changes cannot bypass accounting coordination.

## 10. Liability persistence

Create/register an active CILOC with:

- test farm ID;
- product `cropInputLine`;
- limit 100,000.00;
- principal 0.00;
- an interest rate/metadata test value.

Save/reload.

Expected:

- ID and all configured fields survive;
- available credit = 100,000.00;
- values remain cent-normalized.

## 11. CILOC linked-accounting proof

Through `AGFAccountingService`, post a development-only financed input purchase:

- amount: 30,000.00;
- category: `fertilizer`;
- active test CILOC.

Expected coordinated result:

- `creditDraw` +30,000.00;
- `inputPurchase` -30,000.00;
- same `groupId`;
- same liability ID;
- purchase category remains `fertilizer`;
- CILOC principal becomes exactly 30,000.00;
- available credit becomes 70,000.00;
- group reconciles to zero;
- save/reload preserves all values exactly to cent precision.

## 12. Credit-limit/farm/product rejection

With CILOC balance 30,000 on a 100,000 limit:

- attempt financed input of 80,000 -> `CREDIT_LIMIT_EXCEEDED`;
- try the liability from another farm -> farm mismatch rejection;
- use a term-loan liability as CILOC -> wrong product rejection;
- use a non-active CILOC -> not-active rejection.

Expected for every rejection:

- no ledger entries;
- no principal change;
- no FS money movement.

## 13. Ineligible CILOC category

Attempt an unapproved expense category.

Expected:

- `INELIGIBLE_CROP_INPUT_CATEGORY`;
- zero state mutation.

## 14. Ledger immutability

Post a development transaction, retrieve it through the public ledger API, and mutate the returned object's fields.

Expected:

- authoritative posted record is unchanged.

Also attempt setter calls on a posted/sealed internal test record.

Expected:

- setters do not alter sealed history.

## 15. Duplicate-ID defense

Attempt duplicate transaction and liability IDs.

Expected:

- duplicate transaction rejected;
- duplicate liability rejected;
- original records unchanged;
- integrity check remains clean.

## 16. Batch rollback proof

### Prevalidation failure

Create a two-entry batch with a duplicate ID.

Expected: whole batch rejected before either entry posts.

### Post-ledger operation failure (development fault injection)

Force the coordinated liability-apply step to fail after a test ledger batch is posted.

Expected:

- just-posted tail batch rolls back;
- no orphan financing/expense records remain;
- if rollback itself is forced to fail, runtime enters `READ_ONLY_SAFE_MODE`.

## 17. Integrity-load failure

On disposable copies, introduce individually:

- orphan liability reference;
- revolving principal above its limit;
- unknown transaction type;
- non-zero linked financing/expense group imbalance.

Expected:

- invalid copy is not silently accepted;
- another valid copy is tried if available;
- otherwise safe mode is entered;
- no partially loaded writable books remain.

## 18. Settlement idempotency

Trigger the same period-change condition more than once.

Expected for Phase 0 engine version `0`:

- settlement completes/no-ops once per `engineVersion:year:period` key;
- completion key persists through save/reload;
- duplicate callbacks do not rerun it;
- no money moves.

Future money-moving settlement must increment the engine version before testing.

## 19. Purchase classifier unit/console checks

Test representative contexts:

- PURCHASE_SEEDS -> `seed`;
- PURCHASE_FUEL -> `fuel`;
- fertilizer + FERTILIZER/LIQUIDFERTILIZER -> `fertilizer`;
- fertilizer/material + LIME -> `limeSoilAmendment`;
- fertilizer/material + HERBICIDE -> `cropProtection`;
- BOUGHT_MATERIALS with known fill type -> mapped category;
- BOUGHT_MATERIALS with no fill type -> unresolved/low confidence, **not guessed**.

## 20. High-frequency accumulator

Add many small values that mathematically equal a known cent total to one bucket.

Expected:

- no floating-point drift at cent boundary;
- pending/drained amount equals exact expected cents;
- farm/category/funding/liability keys remain separate;
- drain clears pending buckets.

No live helper hook is enabled in Phase 0.

## 21. Schema migration

### v1 -> v3

Load a valid schema-v1 development file containing legacy IDs/ledger.

Expected:

- compatible legacy data loads;
- liabilities and settlement state initialize appropriately;
- next successful save writes schema v3 primary + recovery copies;
- no legacy transaction is lost.

### v2 -> v3

Load a valid v2 file with liabilities and ledger.

Expected:

- all records retained;
- `saveGeneration` defaults safely;
- settlement marker initializes empty;
- next save upgrades to v3 dual-copy format.

## 22. Server/client authority

Multiplayer validation:

1. host/dedicated server loads the save;
2. client joins;
3. client reports `CLIENT_WAITING_FOR_SYNC` at the local-file layer;
4. client does not create/write either AgForward XML file;
5. direct client-side calls to mutation services are rejected.

Full initial-state synchronization is a remaining Phase 0 deliverable and must be tested separately when implemented.

## 23. Overlap warning test

Load disposable sessions with one known donor finance mod present at a time.

Expected:

- AgForward warns that overlapping financial authority is active;
- no false conflict warning for Red Tape.

The warning does not imply compatibility is safe for production saves.

## 24. Red Tape coexistence / save-hook test

Run new-save, save, reload, recovery, and period-change tests:

- without Red Tape;
- with Red Tape.

Expected:

- both load/save chains remain functional;
- neither save hook orphans the other;
- Red Tape detection works;
- AgForward injects no duplicate tax line items in Phase 0.

Also verify hook timing after mission startup; target selection alone is not sufficient proof.

## Exit criteria

The hardening branch may be marked `RUNTIME_VALIDATED` only after:

- static validator passes;
- current GIANTS TestRunner passes the packaged candidate;
- dual-copy save/recovery tests pass;
- corrupt/newer files are never overwritten;
- v1/v2 migrations pass;
- IDs/liabilities/ledger remain deterministic;
- immutable journal and coordinated rollback tests pass;
- CILOC accounting/limit controls pass;
- Phase 0 settlement remains idempotent and moves no money;
- Red Tape coexistence passes;
- server-only file/mutation authority passes.

Do **not** merge the hardening branch to `main` as runtime-proven authority before these exit criteria are satisfied.
