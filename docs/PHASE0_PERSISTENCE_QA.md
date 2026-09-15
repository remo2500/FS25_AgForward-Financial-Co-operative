# Phase 0 Persistence QA

**Target build:** 0.0.2.1  
**Scope:** save/load, persistent IDs, ledger ordering, linked accounting groups, server authority.

This document defines the first in-game validation pass for the AgForward foundation. A test is not considered passed until it has been run in Farming Simulator 25 against a real savegame.

## 1. New-save initialization

1. Install `FS25_AgForwardFinance` with no prior `agForwardFinance.xml` in the savegame.
2. Load the save.
3. Confirm the log contains an AgForward initialization line and reports `save: NEW_SAVE`.
4. Confirm the game reaches normal gameplay with no Lua error.

Expected result: AgForward starts with zero ledger transactions and does not create or move money during load.

## 2. Save-file creation

1. Save the game normally.
2. Inspect the savegame folder.
3. Confirm `agForwardFinance.xml` exists.
4. Confirm root `agForwardFinance` contains `schemaVersion="1"`.
5. Confirm ID-counter and ledger sections are structurally valid even when empty.

Expected result: saving the game does not alter farm cash and does not interfere with the normal FS25 save.

## 3. Reload stability

1. Exit to menu after saving.
2. Reload the same savegame.
3. Confirm the log reports `save: LOADED`.
4. Confirm no duplicate AgForward initialization and no duplicate save hook behavior.
5. Save again and reload a second time.

Expected result: repeated save/load cycles remain stable.

## 4. Persistent ID validation

After a development test transaction or liability has been created:

1. Record its AgForward ID.
2. Save and reload.
3. Create another ID in the same scope.
4. Confirm the new ID sequence is greater than every previously saved ID.

Example expected sequence:

- before save: `AGF-TX-000001`
- after reload: next ID `AGF-TX-000002`

No ID may be reused.

## 5. Ledger persistence

After posting several test transactions:

1. Save.
2. Reload.
3. Confirm transaction count is unchanged.
4. Confirm posting order is unchanged.
5. Confirm farm ID, transaction type, amount, principal, interest, fees, group ID, funding source, expense category, asset/liability references, period/year, description, and metadata survive the cycle.

Expected result: no transaction is silently dropped or overwritten.

## 6. CILOC linked-accounting proof

Using the accounting service, post a development-only crop-input example:

- farm: test farm;
- amount: 30,000;
- category: `fertilizer`;
- funding source: `cropInputLine`;
- liability: a development test liability ID.

Expected ledger result:

- one `creditDraw` transaction for +30,000;
- one `inputPurchase` transaction for -30,000;
- both share the same `groupId`;
- the purchase retains `fertilizer` as its expense category;
- the financing transaction is not categorized as income;
- save/reload preserves the pair and their shared group.

This test proves AgForward can answer both:

- what was purchased? fertilizer;
- how was it funded? Crop Input Line of Credit.

## 7. Duplicate-ID defense

Development test only:

1. Attempt to post a second transaction using an already-posted transaction ID.
2. Confirm the ledger rejects the transaction with `DUPLICATE_TRANSACTION_ID`.
3. Confirm the original transaction remains unchanged.

## 8. Batch-posting validation

1. Create a two-entry linked transaction batch.
2. Deliberately introduce a duplicate ID inside the batch.
3. Confirm `postBatch()` rejects the batch before any entry is posted.

Expected result: linked economic events do not partially enter the ledger during pre-validation failure.

## 9. Server/client authority

Multiplayer validation:

1. Start a server-hosted save.
2. Join with at least one client.
3. Confirm only the server loads/writes `agForwardFinance.xml`.
4. Confirm client reports `CLIENT_WAITING_FOR_SYNC` rather than attempting local save-file authority.

Note: full client synchronization is a later Phase 0 task; this test currently verifies that clients do not independently write financial state.

## 10. Red Tape coexistence

Run the new-save, save, reload, and settlement-trigger tests both with and without Red Tape installed.

Expected result:

- AgForward initializes without Red Tape.
- With Red Tape installed, detection reports the adapter state without injecting duplicate tax items.
- Saving through both mods' appended save hooks completes without one orphaning the other.

## Exit criteria

Persistence foundation may be marked `RUNTIME_VALIDATED` only after:

- all single-player save/load tests pass;
- no duplicate IDs occur;
- ledger content survives reload exactly;
- no money movement occurs from Phase 0 settlement;
- Red Tape coexistence does not produce save-hook errors;
- multiplayer confirms server-only file authority.
