# Server-Authoritative Financial Offer Protocol

**Status:** offline architecture / future multiplayer contract  
**Runtime enabled:** NO

## Purpose

Vehicle dealer, construction, farmland, and finance-menu workflows need a way to show a player a quote and later accept it without trusting client-calculated financial terms.

The server must remain the authority for:

- farm identity and permissions;
- current financial-state revision;
- credit profile and underwriting result;
- pricing/rate components;
- down-payment and collateral requirements;
- payment/amortization structure;
- purchase/project/land context;
- resulting liability and ledger mutation.

The client may display an offer and request acceptance. It does not become authoritative by sending APR, payment, price, credit limit, or approval fields back to the server.

## Offer lifecycle

`ACTIVE -> CONSUMED`

or

`ACTIVE -> CANCELLED`

or

`ACTIVE -> EXPIRED`

An offer is session/interaction state, not a financial balance. It is therefore intentionally not part of the savegame authority.

## Server offer record

The offline `AGFFinancialOfferService` models:

- `id` — server-generated offer ID;
- `connectionKey` — connection that requested/owns the offer;
- `farmId` — server-resolved borrower farm;
- `productType`;
- `stateRevision` — financial state used to create the quote;
- immutable/deep-copied `quote` snapshot;
- underwriting `decisionStatus`;
- policy/pricing versions;
- optional purchase/project context fingerprint;
- optional valid-through financial period;
- status and non-authoritative metadata.

## Acceptance rules

Before consumption, the server validates all of the following:

1. offer exists;
2. offer is still `ACTIVE`;
3. accepting connection matches the offer connection;
4. server-resolved farm matches the offer farm;
5. current financial-state revision exactly matches the offer revision;
6. expected product matches when supplied by the contextual action;
7. a bound context fingerprint is present and exactly matches;
8. the offer is still inside its valid-through period.

Failure requires a new/repriced offer rather than accepting client-provided corrections.

## Why state revision is strict

A quote can depend on:

- outstanding debt;
- available revolving capacity;
- cash/liquidity;
- liens/collateral;
- other newly accepted finance;
- policy/rate state.

If any authoritative financial operation changes state after the quote was created, the original quote is treated as stale. This is conservative but prevents simultaneous requests from spending the same liquidity/collateral/credit capacity.

A later optimization may introduce narrower dependency revisions, but correctness comes first.

## Context fingerprints

A context fingerprint is a server-derived identity for the economic object that was quoted. Examples:

### Vehicle/equipment

Conceptually include:

- store item identity;
- server-priced configuration set;
- owner farm;
- relevant purchase option/condition.

### Placeable/project

Conceptually include:

- placeable/store identity;
- configuration;
- quoted project uses;
- relevant terrain/groundwork context where stable and appropriate.

### Farmland

Conceptually include:

- farmland ID/stable identity;
- server price/value used by the offer;
- borrower farm;
- transaction type (purchase/finance/lease).

The fingerprint is not intended as a cryptographic security primitive. It is a deterministic server-side consistency check so an offer for one asset/configuration cannot be reused for another.

## Relationship to request idempotency

The offer protocol and `AGFFinancialProtocolState` solve different problems:

- **Offer ID:** identifies the server-priced terms the player is accepting.
- **Request ID:** makes the acceptance network request idempotent if packets/retries repeat.
- **Operation ID:** identifies the one authoritative financial mutation that was actually committed.
- **State revision:** ensures the accepted offer was based on current financial state.

Expected future flow:

1. Client asks server for finance options for a server-resolved context.
2. Server builds credit profile, reprices, underwrites, and creates offer(s).
3. Server sends read-only offer snapshot(s) to client.
4. Client selects an `offerId` and sends an acceptance `requestId`.
5. Server begins request against current state revision.
6. Server validates offer + connection + farm + context + current revision.
7. Server revalidates any live purchase facts that can change independently (ownership, availability, store item, price where required).
8. One coordinated operation commits cash/liability/ledger/asset-link state.
9. Offer becomes `CONSUMED` only as part of successful server workflow.
10. Server returns operation ID/result/new revision.

## Important runtime integration rule

The current pure service's `consume()` is only a protocol-model primitive. When real FS25 purchase integration is implemented, **do not mark an offer consumed before the coordinated purchase/financial operation commits successfully**.

The live transaction coordinator should either:

- validate offer, commit transaction, then consume offer; or
- provide a wider server transaction boundary that can compensate both states safely.

A failed FS purchase must not leave an otherwise usable offer marked consumed unless the server intentionally cancels it.

## Reconnect/reload behavior

Offers are intentionally ephemeral. After reload/reconnect:

- authoritative liabilities/ledger/assets come from the server save state;
- old offers are discarded;
- the player requests a new current quote.

This avoids persisting stale UI/approval artifacts as financial truth.

## Security/correctness rules

- Never accept client APR/payment/credit-limit values as authority.
- Never trust a client farm ID without deriving/validating it from connection permissions.
- Never let an offer for another connection/farm/context be consumed.
- Never accept a quote created against an older financial state revision.
- Never silently evict an active offer solely to make room in a cache.
- Never use offer state as the source of liability balances after commitment.

## Current offline implementation

- `src/network/FinancialOfferService.lua`
- `src/network/FinancialProtocolState.lua`
- `tests/offline_financial_offer_tests.lua`
- `tests/offline_network_protocol_tests.lua`

Live FS25 event serialization and contextual quote creation remain runtime-gated.
