# AgForward Multiplayer Financial Protocol

**Status:** design contract; live events not implemented yet  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

AgForward multiplayer must treat the server as the only authority for consequential financial state. Clients request actions and display results; they never supply final balances or trusted agreement objects.

## 1. Core rules

1. Server owns authoritative ledgers, liabilities, assets, rights, liens, leases, credit decisions, and settlement.
2. Client sends **intent**, not final state.
3. Server derives the acting user/farm from the network connection and permission system rather than trusting a client-provided farm ID.
4. Server revalidates amount, asset identity, product eligibility, credit availability, price/rate, permissions, and current revision.
5. Server performs one coordinated financial operation.
6. Server assigns authoritative IDs.
7. Server increments a monotonically increasing state revision after each committed operation.
8. Server sends structured success/error results plus state deltas/snapshots.
9. Duplicate request IDs are idempotent: the same committed request must not execute twice.

## 2. Client request envelope

A future request event should contain only information necessary to express the user's requested action, for example:

```text
requestId
operationType
clientKnownRevision
contextId / asset key
requested product/structure selections
requested amount (when user-entered)
UI quote token/version (optional)
```

Do **not** trust client fields such as:

```text
final farm balance
final principal balance
approved interest rate
approved credit limit
final collateral value
final borrower risk grade
server farm/permission identity
```

The server recalculates those values.

## 3. Request identity and idempotency

Every client financial request uses a unique request ID.

Target form:

`AGF-REQ-######` or a connection/session-safe equivalent.

The server maintains a bounded idempotency cache containing:

- request ID;
- connection/user identity;
- operation type;
- resulting operation ID;
- success/error result;
- committed state revision.

If the same request is retransmitted due to networking/UI timing, the server returns the prior result instead of executing again.

## 4. Operation identity

Every successfully committed consequential financial action receives an AgForward operation ID separate from transaction IDs.

One operation may produce multiple records:

- ledger entries;
- liability balance mutation;
- lien creation/release;
- asset-right change;
- lease change;
- cash movement;
- delinquency status change.

The operation ID links the resulting state changes for synchronization/audit.

## 5. State revision

The server owns a monotonically increasing integer `stateRevision`.

Revision increments only after a committed authoritative operation.

Clients retain their last applied revision and reject/ignore stale deltas. A gap in revisions triggers a snapshot/resync rather than guessing.

## 6. Join-in-progress snapshot flow

Recommended flow:

1. Client joins and AgForward enters `CLIENT_WAITING_FOR_SYNC`.
2. Server captures a consistent snapshot at revision `R`.
3. Server sends snapshot header (`schema/protocol version`, `revision`, counts/capabilities).
4. Server sends serialized current state chunks.
5. Client validates and stages the snapshot.
6. Server sends snapshot-complete marker for revision `R`.
7. Client atomically promotes staged state and records `R`.
8. Any deltas committed after `R` are applied in revision order.
9. If a delta arrives before snapshot promotion, queue it; if revision continuity is lost, request resync.

No client should calculate balances locally from partial join data.

## 7. Delta event contract

A committed-operation delta should contain enough authoritative results for clients to update read-only mirrors without rerunning lending math.

Target fields:

```text
protocolVersion
operationId
requestId (if client initiated)
previousRevision
newRevision
changed entity records / compact mutations
result status
```

For early versions, sending full changed records is safer than highly compressed arithmetic deltas. Optimization can occur after correctness is proven.

## 8. Permission validation

Before any server mutation:

- derive connection/player/farm;
- confirm farm membership;
- confirm required farm-management permissions;
- verify object belongs to/relates to that farm through authoritative rights;
- verify finance product can be used in current lifecycle state.

A client-selected farm ID may be carried as UI context but is never sufficient authorization.

## 9. Quote validation

Client finance UI may display a quote, but accepting the quote must send its selections back to the server.

Server then:

1. rebuilds current borrower metrics;
2. refreshes collateral/value data;
3. recalculates current rate/pricing;
4. checks current limits and liquidity;
5. verifies quote has not expired/staled;
6. either commits the current valid structure or returns `QUOTE_CHANGED` with a refreshed quote.

This prevents stale UI or malicious clients from forcing outdated terms.

## 10. Error model

Errors should be machine-readable and user-displayable.

Examples:

- `NOT_AUTHORIZED`
- `STALE_STATE_REVISION`
- `QUOTE_CHANGED`
- `CREDIT_LIMIT_EXCEEDED`
- `ASSET_LINK_UNRESOLVED`
- `ASSET_NOT_OWNED`
- `INSUFFICIENT_CASH`
- `LIABILITY_NOT_ACTIVE`
- `READ_ONLY_SAFE_MODE`
- `SERVER_OPERATION_FAILED`

Clients do not infer success from local UI state; they wait for the authoritative result.

## 11. Persistence interaction

Server state revision and the latest durable operation marker should eventually be persisted with financial state.

On save/reload, revision must never regress in a way that allows stale network operations to be replayed as new mutations.

Persisting a bounded recent request/operation idempotency window may be appropriate for dedicated servers; exact retention policy is deferred until live networking tests.

## 12. Security posture from donor re-audit

The donor/reference audit reinforced these requirements:

- derive acting farm from connection;
- validate client-selected terms on server;
- do not let clients create authoritative finance agreements directly;
- protect late-join snapshot handling from duplicate application;
- revalidate asset attachment/ownership at the moment of commitment.

AgForward implements these as common protocol rules rather than copying any donor event classes or wire formats.
