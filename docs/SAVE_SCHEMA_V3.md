# AgForward Native Save Schema v3

**File:** `agForwardFinance.xml`  
**Recovery copy:** `agForwardFinance.backup.xml`  
**Root:** `agForwardFinance`  
**Schema version:** `3`

Schema v3 hardens the persistence layer before AgForward is allowed to move real FS25 money.

## Root attributes

- `schemaVersion`
- `saveGeneration`
- `savedPeriod`
- `savedYear`

`saveGeneration` is monotonic. Primary and backup copies written by one successful save attempt receive the same generation.

## Dual-copy persistence rule

AgForward writes the recovery copy first and verifies that it can be opened with the expected schema/generation before writing the primary copy.

On load:

1. inspect primary and backup copies;
2. select the valid copy with the highest generation;
3. prefer primary only when generation/schema are equivalent;
4. run full record load and integrity reconciliation;
5. fall back to another compatible valid copy if the selected copy fails record/integrity validation;
6. enter read-only safe mode if no compatible validated copy can be loaded.

If the newest valid copy has a schema newer than the installed AgForward build, AgForward **must not downgrade or overwrite it**.

## Runtime safety states

- `NEW_STATE` — no AgForward file existed; empty state is legitimate and writable.
- `NORMAL` — compatible state loaded and validated.
- `RECOVERED` — backup/recovery copy loaded and validated; writable with warning.
- `READ_ONLY_SAFE_MODE` — state cannot be safely interpreted; mutation and save are blocked.
- `CLIENT_WAITING_FOR_SYNC` — multiplayer client has no local file authority.

A corrupt/unsupported state is never treated as equivalent to a new save.

## Persisted services

### ID counters

`agForwardFinance.idCounters.counter(i)`

Current scopes:

- `TX`
- `GRP`
- `LIAB`

### Liability registry

`agForwardFinance.liabilities.liability(i)`

Carries the v2 liability record fields.

### Ledger

`agForwardFinance.ledger.transactions.transaction(i)`

Posted transactions are immutable journal records. Public ledger queries return copies rather than the live authoritative record.

### Settlement

`agForwardFinance.settlement`

Fields:

- `engineVersion`
- `lastCompletedKey`

The settlement key includes the settlement-engine version plus year/period. This makes period handling idempotent without allowing Phase 0's no-op marker to suppress a later settlement-engine version.

## Integrity gate

After load and before save, the integrity service validates at minimum:

- supported transaction/product types;
- finite monetary values;
- non-negative liability balances/limits;
- revolving balance not above limit;
- farm IDs structurally valid;
- liability references resolve for schema v2+;
- linked funding/expense groups reconcile to zero;
- observed IDs advance persistent counters.

A serious integrity failure blocks writes.

## Migration

### v1 -> v3

- load legacy ID counters and ledger;
- liability registry may initialize empty;
- settlement marker initializes empty;
- `saveGeneration` defaults to `0`;
- successful next save writes schema v3.

### v2 -> v3

- preserve IDs, liabilities, and ledger;
- initialize settlement marker empty;
- `saveGeneration` defaults to `0`;
- successful next save writes both v3 primary and recovery copies.

Future migrations must preserve the rule that a newer unknown schema is never overwritten by an older build.
