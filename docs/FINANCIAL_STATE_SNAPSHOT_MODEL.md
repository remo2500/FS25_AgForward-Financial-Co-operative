# AgForward Financial State Snapshot / Delta Model

## Purpose

`AGFFinancialStateSnapshotService` defines a farm-scoped, server-authoritative plain-table model for eventual multiplayer state synchronization.

No GIANTS Event serialization or network transport is implemented here.

## Snapshot scope

A farm snapshot can include:

- native AgForward liabilities;
- farm-relevant economic assets;
- active economic/operator/tenant rights for those assets;
- active liens;
- native leases;
- represented external obligations;
- a bounded tail of immutable ledger transactions;
- the authoritative financial state revision.

Ephemeral FS runtime object IDs are deliberately excluded from the synchronized economic asset representation.

## Relevant asset rule

An asset is included when it is:

- referenced by a farm liability;
- referenced by a farm lease; or
- connected to the farm by an active economic-owner, operator, or tenant right.

This allows leased farmland to appear in the operational snapshot without being misrepresented as economically owned.

## Delta rules

Entity collections are compared by stable AgForward ID.

A delta identifies:

- additions;
- updates;
- removals.

Ledger history is stricter:

- an overlapping transaction ID must be byte-for-byte equivalent in the canonical plain-table model;
- changed historical journal content is rejected;
- if bounded ledger windows no longer overlap, the model requests a full resync instead of assuming continuity.

Any state change without an incremented revision is rejected.

## Runtime gate

Promotion still requires actual GIANTS Event serialization, connection/farm permission derivation, dedicated-server testing, packet sizing, and resync/retry behavior.
