# Phase 0 Persistence QA

**Target build:** 0.0.3.0  
**Scope:** save/load, persistent IDs, liability persistence, ledger ordering, linked accounting groups, server authority.

This document defines the first in-game validation pass for the AgForward foundation. A test is not considered passed until it has been run in Farming Simulator 25 against a real savegame.

## 1. New-save initialization

1. Install `FS25_AgForwardFinance` with no prior `agForwardFinance.xml` in the savegame.
2. Load the save.
3. Confirm the log contains an AgForward initialization line and reports `save: NEW_SAVE`.
4. Confirm the game reaches normal gameplay with no Lua error.

Expected result: AgForward starts with zero liabilities and zero ledger transactions and does not create or move money during load.

## 2. Save-file creation

1. Save the game normally.
2. Inspect the savegame folder.
3. Confirm `agForwardFinance.xml` exists.
4. Confirm root `agForwardFinance` contains `schemaVersion="2"`.
5. Confirm ID-counter, liability, and ledger sections are structurally valid even when empty.

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

- before save: `AGF-TX-000001` / `AGF-LIAB-000001`;
- after reload: next IDs `AGF-TX-000002` / `AGF-LIAB-000002`.

No ID may be reused.

## 5. Liability persistence

Create a development CILOC liability with:

- product type `cropInputLine`;
- farm ID matching the test farm;
- credit limit 100,000;
- principal balance 0;
- active status.

Save and reload.

Expected result:

- liability ID is unchanged;
- product type, farm ID, status, limit, balance, rate, term/payment fields, and metadata survive reload;
- available credit remains 100,000.

## 6. Credit-limit validation

Using the saved CILOC above:

1. Attempt a 30,000 eligible draw.
2. Confirm available credit becomes 70,000.
3. Attempt an additional 80,000 draw.
4. Confirm the registry rejects it with `CREDIT_LIMIT_EXCEEDED`.
5. Confirm principal remains 30,000 after the rejected request.

Also verify that a different farm cannot use the liability and a general term loan cannot be used as a revolving CILOC.

## 7. Ledger persistence

After posting several test transactions:

1. Save.
2. Reload.
3. Confirm transaction count is unchanged.
4. Confirm posting order is unchanged.
5. Confirm farm ID, transaction type, amount, principal, interest, fees, group ID, funding source, expense category, asset/liability references, period/year, description, and metadata survive the cycle.

Expected result: no transaction is silently dropped or overwritten.

## 8. CILOC linked-accounting proof

Using the real liability registry and accounting service, post a development-only crop-input example:

- farm: test farm;
- amount: 30,000;
- category: `fertilizer`;
- funding source: `cropInputLine`;
- liability: the active CILOC created above.

Expected result:

- one `creditDraw` transaction for +30,000;
- one `inputPurchase` transaction for -30,000;
- both share the same `groupId`;
- both reference the same CILOC liability;
- the purchase retains `fertilizer` as its expense category;
- the financing transaction is not categorized as income;
- the CILOC principal increases by exactly 30,000;
- available credit falls by exactly 30,000;
- save/reload preserves the liability balance, pair, and shared group.

This test proves AgForward can answer both:

- what was purchased? fertilizer;
- how was it funded? Crop Input Line of Credit.

## 9. Ineligible CILOC purchase

Attempt to finance a category not on the crop-input eligibility list.

Expected result:

- `INELIGIBLE_CROP_INPUT_CATEGORY`;
- no ledger entries posted;
- no liability balance change.

## 10. Duplicate-ID defense

Development test only:

1. Attempt to post a second transaction using an already-posted transaction ID.
2. Confirm the ledger rejects the transaction with `DUPLICATE_TRANSACTION_ID`.
3. Confirm the original transaction remains unchanged.

Repeat for a liability ID and confirm `DUPLICATE_LIABILITY_ID`.

## 11. Batch-posting validation

1. Create a two-entry linked transaction batch.
2. Deliberately introduce a duplicate ID inside the batch.
3. Confirm `postBatch()` rejects the batch before any entry is posted.

Expected result: linked economic events do not partially enter the ledger during pre-validation failure.

## 12. Schema v1 -> v2 compatibility

Using a copy of a schema-v1 AgForward file containing only ID counters and ledger transactions:

1. Load with build 0.0.3.0.
2. Confirm the ledger and IDs load.
3. Confirm liabilities initialize empty.
4. Save.
5. Confirm the file is rewritten as schema v2 without losing v1 ledger records.

## 13. Server/client authority

Multiplayer validation:

1. Start a server-hosted save.
2. Join with at least one client.
3. Confirm only the server loads/writes `agForwardFinance.xml`.
4. Confirm client reports `CLIENT_WAITING_FOR_SYNC` rather than attempting local save-file authority.

Note: full client synchronization is a later Phase 0 task; this test currently verifies that clients do not independently write financial state.

## 14. Red Tape coexistence

Run the new-save, save, reload, and settlement-trigger tests both with and without Red Tape installed.

Expected result:

- AgForward initializes without Red Tape;
- with Red Tape installed, detection reports the adapter state without injecting duplicate tax items;
- saving through both mods' appended save hooks completes without one orphaning the other.

## Exit criteria

Persistence/liability foundation may be marked `RUNTIME_VALIDATED` only after:

- all single-player save/load tests pass;
- schema v1 -> v2 migration test passes;
- no duplicate IDs occur;
- liabilities and ledger content survive reload exactly;
- CILOC limit and category controls behave correctly;
- no money movement occurs from Phase 0 settlement;
- Red Tape coexistence does not produce save-hook errors;
- multiplayer confirms server-only file authority.
