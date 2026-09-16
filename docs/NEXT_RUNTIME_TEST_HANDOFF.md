# AgForward — Next Runtime Test Handoff

**Prepared:** 2026-09-16  
**First runtime candidate:** `phase0-foundation-hardening`  
**Do not use first:** `offline-foundations`

## Why the first test still uses the hardening branch

The offline branch now contains a large amount of pure financial-model work, but the immediate runtime question is narrower: prove that the schema-v3 persistence/recovery foundation behaves correctly inside Farming Simulator 25 before adding more authoritative state.

Keeping the first test candidate small makes failures attributable. A clean Phase-0 pass gives us a stable base for selectively promoting the already-tested offline modules.

## Minimum first-session sequence

Use a disposable save and retain both `log.txt` and the resulting savegame folder after each milestone.

### Test A — clean initialization

1. Install a package built from `phase0-foundation-hardening` only.
2. Temporarily remove/disable overlapping finance mods:
   - Bank & Credit;
   - Finance Your Fleet;
   - AgriCredit Solutions;
   - Field Leasing;
   - other mods that take independent finance authority.
3. Red Tape may initially remain disabled for this first isolation test.
4. Start a new disposable career save.
5. Let the game fully load, then save normally and exit.
6. Preserve:
   - `log.txt`;
   - `agForwardFinance.xml`;
   - `agForwardFinance.backup.xml`.

Expected Phase-0 behavior:

- one AgForward initialization;
- no Lua call stack/error;
- new financial state is accepted as legitimate;
- primary and recovery copies are created;
- both copies use schema v3 and the same save generation;
- no real lending/payment money is moved.

### Test B — normal reload and generation advance

1. Reload the exact save from Test A.
2. Save once more normally.
3. Exit and retain the files/log.

Expected:

- compatible state loads normally;
- no read-only safe mode;
- save generation advances monotonically;
- primary/recovery copies agree after the completed save.

### Test C — interrupted/latest-primary recovery simulation

Do this only on the disposable copy.

1. Keep the known-good Test B save folder backed up externally.
2. Arrange the primary/recovery copies so recovery represents the newest valid generation and primary is older or unreadable.
3. Load the save.
4. Do not overwrite the external backup.

Expected:

- AgForward chooses the newest compatible validated copy;
- recovery is reported rather than treating the state as a new save;
- no silent liability/ledger reset occurs.

The exact corruption/replacement step can be prepared from the files you send back; there is no need to improvise destructive edits during the first session.

### Test D — Red Tape coexistence

After A/B are clean:

1. Restore the known-good disposable save.
2. Enable Red Tape with AgForward.
3. Load, save, exit, reload, save again.
4. Retain both logs and financial-state files.

Expected:

- both mods initialize once;
- AgForward detects Red Tape but keeps its Phase-0 adapter non-invasive;
- neither save hook prevents the other mod from saving;
- no duplicate save callbacks or Lua errors;
- AgForward's financial state remains valid across reload.

## Do not test yet

The current first runtime candidate is not intended to prove:

- real AgForward loan proceeds/payments;
- CILOC purchase interception;
- vehicle/placeable/land finance;
- live MoneyType/FinanceStats mapping;
- multiplayer financial requests;
- lien-aware asset sales;
- land lease access;
- recovery/repossession;
- GUI lending workflows.

Those are later gates after persistence/coexistence is proven.

## Files to return after the first session

The most useful handoff is:

1. FS25 `log.txt`;
2. `agForwardFinance.xml`;
3. `agForwardFinance.backup.xml`;
4. a note identifying which test (A/B/C/D) produced the files;
5. if a save failed to load, the savegame folder state from **before** another save attempt.

No screenshots are necessary unless the game itself presents an unexpected warning/UI condition.

## Offline analysis already prepared

The repository contains:

- `tools/analyze_runtime_log.py` — extracts AgForward initialization, recovery/safe-mode, compatibility, Red Tape, save-failure, and Lua-error markers;
- `tools/validate_agforward_save.py` — independently inspects schema-v3 XML/generation/IDs/liabilities/ledger/references;
- `tools/build_mod_package.py` — creates a deterministic correctly rooted mod ZIP for packaging checks.

These tools reduce the amount of manual interpretation required after you can test again.

## Promotion after Phase-0 pass

Once Phase-0 runtime persistence/recovery and Red Tape coexistence pass, promote offline work in small controlled increments rather than merging the whole offline branch at once. Recommended order:

1. shared finance math/rate/payment-frequency code;
2. read-only reporting/credit-profile models;
3. asset/right/lien model plus persistence schema promotion;
4. server offer/revision protocol and read-only UI quote flow;
5. CILOC purchase authorization/reservation;
6. real MoneyType/cash boundary;
7. equipment/project/land finance;
8. settlement/delinquency/recovery.

Each increment should preserve the rule that the server ledger/liability state is the financial authority and that Red Tape remains the external tax/regulatory authority.
