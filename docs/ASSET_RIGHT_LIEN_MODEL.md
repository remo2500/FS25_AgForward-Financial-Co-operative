# AgForward Asset / Right / Lien Model

**Status:** offline foundation; not yet registered into live Phase 0 save state  
**Branch:** `offline-foundations`  
**Date:** 2026-09-15

This model implements the donor-audit requirement that physical/gameplay possession must not be confused with economic ownership or collateral rights.

## 1. Asset identity

An AgForward asset has its own stable AgForward ID and a separate stable external key used to relink the underlying FS25 object.

Asset classes:

- vehicle/equipment;
- placeable/facility;
- farmland;
- other future secured asset.

Transient FS25 object/network IDs are runtime handles only. They are never the sole persisted collateral identity.

Current offline model:

- `src/assets/AssetRecord.lua`
- `src/assets/AssetRegistry.lua`

## 2. Runtime link state

Every secured asset can be in one of the following link states:

- `resolved` — current FS25 runtime object has been safely linked;
- `unresolved` — relink has not yet succeeded;
- `quarantined` — link conflict/missing object requires investigation/retry;
- `notRequired` — asset class does not need a live object link.

An unresolved/quarantined asset is **not** automatically treated as sold, destroyed, or paid off.

`AssetLinkQuarantine` tracks unresolved collateral separately so retries can occur without corrupting debt.

## 3. Economic and operating rights

Rights are independent records rather than properties inferred from an engine ownership flag.

Initial right types:

- `economicOwner` — who economically owns the asset;
- `operator` — who is authorized to operate/use it;
- `tenant` — who holds a lease/tenancy interest.

Initial holder types:

- farm;
- external party;
- system/world.

This allows a farmland parcel to have, for example:

- external economic owner;
- player farm as tenant;
- player farm as operator;
- AgForward mortgage/lien on a separately owned parcel when applicable.

Leased land therefore cannot accidentally enter owned collateral merely because the player has operational access.

Current offline model:

- `src/assets/AssetRight.lua`
- `src/assets/AssetRightRegistry.lua`

## 4. Liens

A lien is a separate secured claim linking:

- AgForward lien ID;
- asset ID;
- liability ID;
- priority;
- optional secured-amount cap;
- active/released/satisfied status.

A lien does not replace the liability balance. The liability registry remains debt authority; the lien describes what asset secures that debt.

Current offline model:

- `src/assets/Lien.lua`
- `src/assets/LienRegistry.lua`

## 5. Secured disposition

Equipment sale, placeable sale, land sale, and a future trade-in should all use one generic lien-aware preflight.

Current read-only preflight service:

`src/assets/SecuredDispositionService.lua`

For a proposed sale/trade:

1. verify the asset exists and is active;
2. reject quarantined collateral;
3. verify acting farm is economic owner when required;
4. gather active liens by priority;
5. resolve current linked liability payoff amounts;
6. calculate gross value less required lien payoff;
7. determine whether additional farm cash is needed to clear negative equity;
8. approve/deny the disposition preflight.

Core relationship:

`gross proceeds - lien payoff = gross equity`

If gross equity is negative:

`required cash contribution = abs(gross equity)`

A disposition cannot proceed unless available cash or an explicitly approved refinance source can cover the shortfall.

## 6. Future execution boundary

The current service performs only a read-only preflight. Live execution must later be a single coordinated operation that can atomically/recoverably:

- receive sale proceeds;
- collect any required cash shortfall;
- pay accrued interest/fees/principal in the correct order;
- release liens;
- close/satisfy liabilities when appropriate;
- transfer/dispose the FS25 asset;
- mark economic rights ended;
- post ledger entries;
- emit multiplayer state changes.

No product should implement its own private sale-payoff logic.

## 7. Asset valuation

`currentValue` is a financial/reporting value, not automatically the sale quote.

Future valuation sources may include:

- FS25 current store/resale value;
- appraised farmland value;
- project/facility valuation;
- dealer/trade quote;
- product-specific advance-rate value.

Credit/LTV calculations should record which valuation basis was used rather than assuming all values are interchangeable.

## 8. Persistence staging

These asset/right/lien classes are intentionally being developed on `offline-foundations` without changing the current schema-v3 runtime candidate.

They should enter a later save schema only after:

- current schema-v3 persistence is runtime validated;
- stable vehicle/placeable/farmland key strategy is tested;
- unresolved-link recovery is proven;
- migration rules are documented.
