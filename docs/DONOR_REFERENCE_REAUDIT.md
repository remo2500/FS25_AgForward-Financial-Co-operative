# AgForward Donor / Reference Re-Audit

**Date:** 2026-09-15  
**Branch:** `phase0-foundation-hardening`  
**Purpose:** implementation-neutral research for AgForward Financial Cooperative  
**Status:** COMPLETE FOR PHASE 0 / revisit individual donors when their feature area enters implementation

This document records a second source-level audit of the supplied finance-related FS25 mods after AgForward's Phase 0 architecture was established. It exists to capture useful patterns, failure modes, FS25 integration points, and interoperability constraints without copying third-party implementation.

## 1. Use and licensing rule

AgForward is an original MIT-licensed project. The donor archives are **research inputs**, not source libraries.

Observed donor metadata:

| Reference | Version | Author | License posture used by AgForward |
|---|---:|---|---|
| Bank & Credit | 1.0.1.0 | Squallqt | Source headers explicitly state Copyright 2026 / All Rights Reserved; reference only |
| Finance Your Fleet | 1.0.0.1 | JerseyShoreModding | No standalone reuse license found in supplied archive; reference only |
| AgriCredit Solutions | 1.0.0.0 | JerseyShoreModding | No standalone reuse license found in supplied archive; reference only |
| Field Leasing | 1.0.0.1 | Chissel | No standalone reuse license found in supplied archive; reference only |
| Economic History | 1.0.0.1 | Chris1969 | No standalone reuse license found in supplied archive; reference only |
| Red Tape | 1.0.3.0 | Ozz | No standalone reuse license found in supplied archive; external interoperability target/reference only |
| Vehicle Trade In | 1.0.0.1 | Pat95 | No standalone reuse license found in supplied archive; reference only; feature deferred |

Absence of a license file is **not** permission to copy. All findings below are expressed as requirements/patterns to implement independently.

---

# 2. Cross-reference conclusions

The second audit strengthens the original architecture decision: **AgForward must own one economic truth and one mutation pipeline.**

The donor stack repeatedly exhibits four systemic risks:

1. **Independent period collection.** Bank & Credit, Field Leasing, FYF, ACS, and Red Tape each react to period changes independently. If several are installed, load/subscription order can influence which obligation consumes cash first.
2. **Product-local debt authority.** Each finance donor knows its own agreements, but not all other secured/unsecured obligations.
3. **Ownership is not the same as economic/collateral rights.** Field Leasing demonstrates why assigning engine farmland ownership to a tenant can corrupt collateral and net-worth assumptions in another mod.
4. **Client payload trust varies greatly.** Some donor events correctly derive the acting farm from the network connection; others accept farm/agreement data too directly.

AgForward therefore retains these locked rules:

- one ledger;
- one liability registry;
- one asset/right/lien registry;
- one financial operation coordinator;
- one settlement coordinator;
- server-authoritative requests;
- connection-derived farm identity;
- stable asset identifiers;
- explicit recovery/quarantine when an asset link is unresolved;
- Red Tape as optional external government/tax authority.

---

# 3. Bank & Credit re-audit

**Primary research value:** general banking, underwriting, rate products, server request validation, full-state multiplayer sync.

## 3.1 Period settlement confirms need for central coordinator

`FS25_BankCredit/scripts/Main.lua:113-133` subscribes directly to `PERIOD_CHANGED` and calls `loanService:collectAll()` before its rate update.

`FS25_BankCredit/scripts/LoanService.lua:300-307` loops every active loan and collects it independently.

**AgForward requirement:** product modules must never independently debit at period change. They create obligations; `AGFSettlementCoordinator` gathers and settles them in one deterministic run.

## 3.2 Monthly collection can mutate debt/cash without liquidity preflight

`LoanService.lua:198-298` calculates and advances loan state, broadcasts payment state, and charges interest/principal with `addMoney`. There is no whole-farm insufficient-cash allocation stage in that collection path.

**AgForward requirement:** do not mutate agreement status/principal until the settlement coordinator has established how much cash/authorized revolver liquidity is available and what amount is actually paid.

## 3.3 Revolving-credit design ideas worth retaining

`LoanService.lua:207-246` charges interest on the drawn amount and a commitment fee on the undrawn portion. `LoanService.lua:390-421` limits draws to the approved facility.

**Adopt conceptually:**

- interest only on utilized balance;
- optional commitment fee on unused availability;
- explicit approved limit and available credit;
- separate principal and interest/fee accounting.

**Do not lock the donor's exact rates/fees.** AgForward will have its own product/pricing policy.

## 3.4 Collateral calculation shows exactly what AgForward must avoid

`CreditService.lua:55-107` derives liquidated assets directly from engine vehicle ownership, farmland ownership, placeable ownership, livestock, inventory, and cash. It reduces cash by Bank & Credit's own outstanding only.

Consequences when combined with other mods:

- land assigned to a tenant by Field Leasing can look owned;
- a vehicle/placeable financed elsewhere can look unencumbered;
- external debt may not reduce collateral/net worth;
- ownership and lien priority are not represented.

**AgForward requirement:** credit calculations must use the native asset/right/lien registry and calculate **net collateral value**, not simply scan engine ownership.

## 3.5 Vanilla loan replacement requires deliberate synchronization

`Main.lua:191-215` sets `farm.loan` to zero, creates a principal money entry, and broadcasts a separate sync because a direct `farm.loan` assignment is not automatically synchronized.

**AgForward research consequence:** before underwriting goes live, define a formal base-game debt policy:

- import vanilla debt into AgForward;
- represent it as an external obligation; or
- deliberately replace/clear it with a server/client migration event.

It may not simply be ignored.

## 3.6 Strong multiplayer authorization pattern

`events/LoanRequestEvent.lua:51-74`:

- handles action on server;
- checks farm-manager permission;
- resolves the requesting player/farm from the connection;
- explicitly does not trust the client-supplied farm ID.

`RevolvingDrawEvent.lua` and `LoanRepayEvent.lua` follow the same general pattern and verify agreement farm ownership.

**AgForward requirement:** every money-changing client request must derive acting user/farm from the connection and compare it against the target liability/asset. A payload farm ID is informational at most.

## 3.7 Full-state sync and late-join race lesson

`BankSyncEvent.lua:22-72` reads an entire snapshot before applying it, preserves shared service objects by updating them in place, and rebuilds the loan repository.

`LoanCreateEvent.lua:37-43` guards against double application when a late-join snapshot already contained a loan before a delta event arrived.

**AgForward requirement:** multiplayer state must carry a **server state revision / operation ID** so snapshot + subsequent delta events are idempotent. A join-in-progress client must never double-post a financial operation.

## 3.8 Income tracking is useful only as a secondary FS observation layer

`IncomeTracker.lua` hooks `Farm.changeBalance` and keys categorization from MoneyType statistics.

**AgForward decision:** use the AgForward ledger/registries as financial truth. FS money observation can be used to identify external transactions and reconcile with the game, but must not become a competing debt ledger.

---

# 4. Finance Your Fleet re-audit

**Primary research value:** vehicle purchase integration, stable financed-asset identity, recovery/persistence behavior, failure modes in multiplayer/accounting.

## 4.1 Stable unique ID beats transient object/network ID

`FinanceManager.lua:313+` resolves financed vehicles from persistent unique IDs. It separately updates transient object IDs after customization/recreation.

`FinanceManager.lua:1230-1314` defers vehicle-removal settlement, waits, and checks whether the **same unique ID** was recreated before treating the financed asset as truly gone.

**AgForward requirement:**

- vehicle collateral link uses stable vehicle unique ID as primary identity;
- network/object IDs are runtime references only;
- asset disappearance must be rechecked after reload/reset/customization before triggering recovery or payoff.

## 4.2 Durable mirror recovery gives a valuable all-or-nothing rule

`FinanceManager.lua:657-753` checks savegame identity and stages mirror recovery. Lines 677-680 explicitly require every active financed vehicle's unique ID to resolve before active mirror agreements are admitted.

`FinanceManager.lua:923-940` waits for the live vehicle system before attempting mirror recovery.

**Adopt conceptually:** an external/recovery copy must not inject stale liens into a different/reused save slot. Future AgForward asset-linked recovery should verify save identity plus exact collateral identity before promoting recovered records.

## 4.3 Unresolved legacy links are preserved, not silently deleted

`FinanceManager.lua:355-381` and `457-492` preserve unresolved agreements in a pending-link list and retry them. They are not assumed paid or deleted just because the asset was not immediately available.

**AgForward requirement:** create an **Asset Link Quarantine** state for unresolved vehicle/placeable links. Debt remains legally/economically outstanding while asset resolution is pending; destructive asset actions and automated recovery are suspended until the link is resolved or explicitly adjudicated.

## 4.4 Save-hook timing is a live interoperability issue

`FinanceManager.lua:509-527` deliberately installs after `CURRENT_MISSION_START` to hook the live save chain after other mods had a chance to alter it.

Red Tape uses a slightly different method based on `rawget` (see Section 8).

**AgForward action:** current rawget target selection is correct in principle, but runtime QA must test whether installation timing in `loadMap` catches the final chain when Red Tape/FYF-style mods are present. If not, defer AgForward's hook installation to mission start while preserving idempotence.

## 4.5 Vehicle dealer integration points remain useful

`FinancePurchaseDataExtension.lua` extends vehicle purchase data so the normal dealer flow can carry finance metadata/deposit behavior, and the buy callback links the resulting asset.

**AgForward requirement:** equipment finance should appear inside the normal dealer purchase context and use the resulting live vehicle's stable identity. Implementation must be original and routed into the common AgForward quote/operation engines.

## 4.6 Create-agreement event is a pattern to avoid

`events/CreateFinanceAgreementEvent.lua:26-36` accepts/deserializes an agreement, broadcasts it when received from a client, then registers it. The shown handler does not independently derive/validate the farm, agreement terms, purchase amount, or asset authority from the requesting connection.

**Do not emulate.** AgForward clients submit a **request**, not an authoritative agreement object. Server constructs the agreement from validated inputs.

## 4.7 Manual payment handler is only partially protected

`SubmitFinancePaymentEvent.lua:34-67` performs a server-side balance test and finds the agreement by ID, but the shown path does not explicitly demonstrate connection-farm authorization before servicing the agreement.

**AgForward requirement:** use Bank & Credit / ACS-style farm-from-connection checks for all payment/payoff requests.

## 4.8 Accounting classification problem remains relevant

FYF uses vehicle-leasing finance categories for finance servicing/recovery in places. Red Tape currently treats `vehicleLeasingCost` as an expense.

**AgForward requirement:** a finance payment must never be posted as a monolithic lease expense. Principal, interest, fees, and asset disposition/recovery components remain separate.

---

# 5. AgriCredit Solutions re-audit

**Primary research value:** placeable/project purchase flow, connection authorization, unresolved secured-asset handling, secured sale/payoff sequence.

## 5.1 Strong farm-from-connection authorization

`AgriCreditManager.lua:52-84` resolves the user/farm from the network connection and exposes `isConnectionAuthorizedForFarm`.

`events/SubmitAgriCreditPaymentEvent.lua:33-68` verifies the agreement belongs to the requesting farm before servicing it and returns an explicit result event.

**AgForward requirement:** this is the correct conceptual security model. Return explicit operation-result codes to the requesting client rather than silently failing.

## 5.2 Agreement creation is server-originated

`events/CreateAgriCreditAgreementEvent.lua:25-38` documents/implements the event as **server-to-client synchronization only**; actual agreement creation happens from the authoritative placeable purchase callback.

**AgForward requirement:** project-finance agreements must originate from a server-validated purchase transaction, not from arbitrary client-supplied agreement state.

## 5.3 Placeable identity and relinking

`AgriCreditManager.lua:149-175` prefers permanent placeable unique ID and only uses runtime object ID as fallback. `184-199` retries attaching sale hooks to unresolved financed placeables.

**AgForward requirement:** placeable asset registry follows the same stable-ID principle as vehicle collateral.

## 5.4 Unresolved financed assets should freeze destructive servicing assumptions

`AgriCreditManager.lua:396+` checks whether the financed placeable is resolved; the monthly servicing path logs/skips unresolved assets and preserves the agreement instead of treating the building as sold/missing.

**AgForward requirement:** unresolved collateral puts only **asset-dependent actions** into quarantine. The debt record remains; automatic repossession/sale conclusions are paused.

## 5.5 Secured placeable sale is the strongest donor pattern

`AgriCreditSaleExtension.lua:470-524` provides the most useful implementation-neutral sale workflow found in the donors:

1. server remains final authority;
2. existing GIANTS `canBeSold` restrictions still apply;
3. owner farm must match agreement farm;
4. calculate gross sale value and payoff;
5. require `farm cash + gross sale proceeds >= payoff`;
6. block the sale if settlement is impossible;
7. preserve the normal GIANTS sale transaction;
8. settle/close the secured agreement before final asset removal;
9. synchronize updated finance state.

**AgForward requirement:** implement one generic `SecuredAssetDispositionService` that can later support equipment, placeables, and farmland. It should return a disposition quote:

`gross proceeds - principal - accrued interest - fees = net equity`

and reject disposal when required settlement cannot be funded.

## 5.6 Durable mirror is useful but AgForward's schema-v3 design is safer

`AgriCreditManager.lua:339-386` can restore from a durable mirror when the normal save copy is absent and writes the durable copy on material state changes.

**AgForward position:** retain the recovery principle, but use the v3 primary/recovery generation and integrity gates rather than product-local mirror files.

## 5.7 State sync applies authoritative snapshot only on clients

`AgriCreditStateSyncEvent.lua:21-47` fully parses the payload but refuses to replace server state unless the event came from the server connection.

**AgForward requirement:** server snapshots may update client mirrors only. Never allow a client-originated full-state payload to replace authoritative server registries.

---

# 6. Field Leasing re-audit

**Primary research value:** farmland-map workflow and a clear example of why legal/economic rights must be separated from engine access ownership.

## 6.1 Engine ownership is reassigned to the tenant

`FieldLeasingManager.lua:19-42` calls `setLandOwnership(farmlandId, farmId)` when a lease begins. Critically, that ownership change occurs **before** its server guard at lines 29-31.

Termination also directly reassigns engine ownership (`44-57`).

**Critical AgForward rule:** leased land must never automatically become an owned farm asset in AgForward's balance sheet/collateral model. Maintain separate:

- economic/legal owner;
- operator/access holder;
- tenant/leaseholder;
- lienholder.

If FS25 gameplay requires an engine ownership/access workaround, isolate that in an access adapter and never interpret that field as economic truth.

## 6.2 Client event trusts economic fields too directly

`events/LeaseFarmlandEvent.lua:10-47` streams lease flag, farmland ID, farm ID, and price and invokes lease/termination. The server-side path shown does not independently derive the requester's farm or recompute/validate the price.

**Do not emulate.** AgForward server determines tenant farm from connection, validates farmland state, and calculates authoritative rent/term.

## 6.3 Independent monthly rent confirms central settlement need

`FieldLeasingManager.lua:60-68` directly debits every lease on `PERIOD_CHANGED`.

**AgForward requirement:** lease rent becomes another obligation in the common settlement queue and enters fixed-charge coverage.

## 6.4 MoneyType/FinanceStats integration concept is useful

Field Leasing registers its own lease MoneyType/statistic and finance-stat support.

**AgForward requirement:** when FS money movements are introduced, map them deliberately to finance statistics where useful—but preserve AgForward's richer ledger classification as the authority.

---

# 7. Economic History re-audit

**Primary research value:** historical reporting and lightweight server-request/client-snapshot patterns.

## 7.1 Vanilla debt is not sufficient

`EconomicHistoryDataCollect.lua:501, 511, 788, 995` records `farm.loan` as loan balance.

This becomes incomplete once Bank & Credit clears vanilla debt or AgForward carries native facilities.

**AgForward requirement:** reports derive total liabilities from AgForward's registry plus deliberately represented external/base-game obligations, never `farm.loan` alone.

## 7.2 FinanceStats are useful for external-game activity, not enough for internal financial truth

`EconomicHistoryDataCollect.lua:62-138` maps a large set of vanilla finance-stat fields/MoneyTypes and synchronizes them into period history.

**AgForward approach:**

- native AgForward lending/reporting comes from ledger + registries;
- vanilla FinanceStats may supply external farm operating transactions not generated by AgForward;
- period snapshots should be derived/rebuildable rather than maintaining separate debt balances.

## 7.3 Read-only request/response sync is a useful reporting pattern

`EconomicHistoryRequestEvent.lua:112-132` has clients send a request with no authoritative financial payload; server refreshes data and responds to that connection.

`EconomicHistorySyncEvent.lua:216+` applies synchronized data only on clients.

**AgForward requirement:** read-only dashboard/report refresh can use a similar request/current-snapshot model. It should include an AgForward state revision and not allow client-side financial calculations to become authoritative.

## 7.4 Do not copy fixed network widths blindly

`EconomicHistorySyncEvent.lua:94-119` serializes farm IDs with `UInt8`.

**AgForward requirement:** use GIANTS-provided bit-width constants (`FarmManager.FARM_ID_SEND_NUM_BITS`, farmland manager bit counts, etc.) where the API exposes them instead of assuming a fixed width.

---

# 8. Red Tape re-audit

**Primary research value:** required external interoperability, save-hook coexistence, tax categorization, initial client-state pattern.

## 8.1 Save-hook chain research directly validates AgForward's target-selection rule

`RedTape.lua:555-574` explains that `Mission00.saveSavegame` may merely be inherited through its metatable. It therefore uses `rawget(Mission00, "saveSavegame")` before deciding whether to hook `Mission00` or `FSBaseMission`.

**AgForward status:** hardening branch follows this target-selection rule. Runtime timing still needs coexistence testing.

## 8.2 Red Tape observes Farm.changeBalance and filters `other`

`extensions/FarmExtension.lua:10-28` records server money changes. At lines 16-17 it ignores `moneyType.statistic == "other"` unless the MoneyType name is in an allowlist.

Current allowlist includes `finance_purchaseFuel` (`lines 2-8`).

**AgForward requirement:** do not assume a custom `other` MoneyType will be visible to Red Tape. Prefer known/intentional finance statistics or an explicit adapter handshake where needed.

## 8.3 Tax categorization proves why principal must remain separate

`TaxSystem.lua:357-428` classifies operating expenses. Current expense statistics include:

- `purchaseSeeds`;
- `purchaseFertilizer`;
- `purchaseFuel`;
- `fieldPurchase`;
- `vehicleLeasingCost`;
- `loanInterest`;
- `bankLoanInterest`;
- other operating costs.

It does **not** need principal to be an expense.

**AgForward rule remains locked:**

- draw/proceeds = financing, not income;
- principal = balance-sheet liability movement, not tax expense;
- interest = finance expense;
- rent = rent/lease expense;
- finance fees = separately classified according to intentional tax policy.

## 8.4 Double-count risk is real

Red Tape merges recorded line items by statistic/month (`TaxSystem.lua:308-332`). If AgForward causes a normal FS money movement that Red Tape already observes **and** separately injects a Red Tape line item, the same economic event can be counted twice.

**AgForward requirement:** production adapter activation is transaction-type-by-transaction-type. First observe what Red Tape records naturally; add supplemental information only where native classification loses meaning.

## 8.5 Initial client state is a useful structural pattern

`events/InitialClientStateEvent.lua:14-39` serializes multiple subsystem sections plus settings in one server initial-state event. `RedTape.lua:576-577` hooks `FSBaseMission.sendInitialClientState`.

**AgForward requirement:** implement a single initial snapshot event containing version/revision plus service sections (settings, liabilities, asset rights, current reporting state). Clients apply it as a mirror only.

## 8.6 Keep Red Tape settlement authority separate

Red Tape independently reacts to period changes for tax/government behavior. AgForward should not replace government logic.

**Future design question:** determine whether tax obligations participate in AgForward's liquidity priority display/forecast without AgForward taking ownership of Red Tape's tax calculation. Prefer an adapter exposing expected/due tax obligations rather than duplicating the tax system.

---

# 9. Vehicle Trade In re-audit

**Primary research value:** future lien-aware sale/trade integration and additional multiplayer validation examples. Native trade-in remains deferred.

## 9.1 Stable asset identity lesson repeats

`TradeInFinance.lua:121+` evolved toward persistent unique vehicle keys rather than only model/display-name matching.

**AgForward requirement:** stable asset IDs are a common cross-product contract and must be designed once in the asset registry.

## 9.2 Client financing terms must not be trusted

`TradeInMultiplayer.lua:386-447` derives the farm from the connection and rejects client-provided term/rate combinations unless they exactly match a server-defined financing option.

**AgForward requirement:** client quote selection sends an offer/quote ID or requested structure; server reprices/revalidates it against current policy before commitment. Never accept a client-calculated APR/payment as authority.

## 9.3 Asset attachment request is validated server-side

`TradeInMultiplayer.lua:564-584` resolves the requesting farm, finds an agreement by ID/farm, checks that the vehicle belongs to that farm, and checks expected store item before attaching finance to it.

**AgForward requirement:** asset-link events must verify agreement farm, asset owner, expected asset/purchase identity, and server-visible object identity.

## 9.4 Payment request/explicit response pattern is useful

`TradeInMultiplayer.lua:621-631` derives farm from the connection, applies payment server-side, and sends a result including success, amount, remaining balance, completion, and error code.

**AgForward requirement:** all consequential UI actions should receive structured server result codes plus new server state revision.

## 9.5 Future valuation should remain modular

`TradeInCalculator.lua` uses staged value adjustments for hours, damage, dirt, age, minimum value, brand bonus, dealer multiplier, and a payout cap.

AgForward does **not** need to own every used-equipment valuation rule. Future design should accept a dealer/gross trade value from a trade module and apply AgForward's lien/equity calculation:

`gross trade value - payoff - accrued charges = net trade equity`

## 9.6 Duplicate finance authority remains unacceptable

Trade In includes its own financing system. Running it as a second authoritative vehicle lender alongside AgForward would recreate the exact multi-authority problem AgForward is intended to solve.

**Status:** trade/dealer feature remains deferred; compatibility warning remains appropriate during development.

---

# 10. Current GIANTS FS25 API research

This donor re-audit was checked against the current GIANTS Developer Network FS25 Lua documentation (Script/Engine documentation shown as v1.20.0.0 during this review) and the current GDN downloads page.

## 10.1 Generic material purchases prove that MoneyType alone is insufficient

Current `PlaceableSilo:refillAmount(fillTypeIndex, amount, price)` retains the actual `fillTypeIndex`, but charges the farm using `MoneyType.BOUGHT_MATERIALS`.

**AgForward consequence:** for CILOC classification, intercept/observe enough purchase-path context to retain fill type. A post-hoc `Farm.changeBalance` observer cannot always distinguish seed/fertilizer/lime/herbicide when all it receives is a generic material MoneyType.

## 10.2 Helper fuel/seed purchases are high-frequency direct money changes

Current motorized/helper code uses `MoneyType.PURCHASE_FUEL`; current seeding/planting helper paths use `MoneyType.PURCHASE_SEEDS` and can issue repeated charges while AI work continues.

**AgForward consequence:** the new `AGFInputPurchaseAccumulator` is warranted. Preserve exact cents in buckets and post meaningful aggregated journal records instead of one pair per tiny helper charge.

## 10.3 Dealer/construction data objects are still valid contextual entry points

Current GDN documents `BuyVehicleData` with owner farm, price, configurations, lease flag, serialization, and buy callback. `BuyPlaceableData` likewise carries owner farm, price, configurations, displacement costs, terrain settings, and a buy callback.

**AgForward consequence:** equipment/project finance should integrate at purchase context before affordability/payment finalization, then link the resulting asset after the authoritative buy completes.

## 10.4 TestRunner should become a release gate

The GDN downloads page currently provides **Farming Simulator 25 Test Runner v0.9.20** for FS25 1.23.0+ (dated 2026-09-09 in the reviewed listing).

**AgForward requirement:** add repository static checks now and run GIANTS TestRunner on packaged candidates before calling a build runtime validated or release-ready.

---

# 11. New requirements produced by the re-audit

The following requirements are now promoted for AgForward implementation planning.

## Phase 0 / immediate

1. Keep `main` as reviewed/runtime-proven authority; continue hardening on branch/PR.
2. Add server state revision/version to future multiplayer snapshots and deltas.
3. Add a single initial-client-state snapshot event; no client file loading/writing.
4. Add explicit operation result events/codes for financial requests.
5. Add asset-link quarantine/retry design before equipment/project finance.
6. Add save identity metadata before external/recovery state can relink secured assets.
7. Validate save-hook **timing**, not just target-selection, with Red Tape present.
8. Add static repository validation and GIANTS TestRunner as packaging gates.

## Money movement boundary

9. Do not rely only on `Farm.changeBalance` to classify CILOC purchases.
10. Capture purchase context before/at the transaction path where fill type and asset/store item are known.
11. Make credit availability part of purchase authorization so a CILOC can fund a purchase that cash alone could not afford.
12. Include actual FS cash movement inside `AGFFinancialOperationCoordinator` so cash, liability, and ledger either reconcile or enter explicit recovery state.
13. Aggregate high-frequency helper input charges in cents.
14. Map principal/interest/fees/rent to intentional FS MoneyTypes/FinanceStats without losing AgForward ledger purpose.
15. Test every AgForward MoneyType against Red Tape to prove no omission or duplicate tax entry.

## Multiplayer

16. Derive acting farm/user from `connection`; never trust client farm IDs.
17. Validate farm-manager/appropriate permissions on server.
18. Clients request actions; server constructs authoritative financial records.
19. Price/rate/payment/credit terms are revalidated on server.
20. Asset attachment is validated against farm ownership + expected purchase identity.
21. Snapshot/delta races are idempotent using state revision/operation IDs.

## Secured assets

22. Stable unique asset identity is primary; transient object IDs are secondary runtime handles.
23. Asset disappearance after reset/load/customization must be rechecked before settlement/recovery.
24. Unresolved collateral is quarantined/retried, never silently deleted or assumed sold.
25. Secured disposal is preflighted server-side and cannot complete without lien settlement.
26. Build one generic secured-disposition service for equipment, facilities, and land.

## Credit/ownership

27. Never derive collateral solely from engine ownership.
28. Land leasing must keep economic owner/operator/tenant/lienholder distinct.
29. Leased land is excluded from owned assets/collateral.
30. Whole-farm underwriting must include known base-game/external obligations by explicit policy.

## Reporting

31. AgForward ledger + registries are authoritative for native finance.
32. FinanceStats may augment operating/external-game history but do not define AgForward debt.
33. Historical snapshots are derived/reconcilable from authoritative state.
34. Read-only reporting requests can use server-generated client snapshots.

---

# 12. Patterns explicitly rejected

Do not reproduce these donor behaviors:

- client-supplied authoritative finance agreements;
- trusting client farm ID, rate, term, price, or agreement ownership;
- independent product-local `PERIOD_CHANGED` cash collection;
- treating a loan payment as vehicle leasing expense;
- assigning tenant engine farmland ownership and then treating it as economic ownership;
- assuming engine-owned assets are unencumbered collateral;
- deleting/settling debt merely because an asset failed to link during load;
- using transient network object IDs as the sole collateral identity;
- using `farm.loan` as total debt;
- injecting Red Tape tax lines for money movements Red Tape already observes;
- silently skipping corrupt financial records and continuing writable;
- overwriting an unknown newer save schema.

---

# 13. Reference map for future work

When implementing a feature, re-open only the relevant research area and translate behavior into AgForward requirements before coding.

| AgForward feature | Primary references to consult |
|---|---|
| Operating line / general lending | Bank & Credit LoanService, CreditService, request events |
| CILOC purchase classification | GIANTS PlaceableSilo/helper purchase paths, Red Tape classification |
| Equipment finance purchase/link | FYF purchase-data extension, unique-ID recovery; TradeIn validation patterns |
| Project/placeable finance | ACS purchase/construction extension, manager relinking |
| Secured sale/payoff | ACS sale extension |
| Native leasing | Field Leasing UI flow only; do **not** copy ownership model |
| Reporting/history | Economic History request/sync and FinanceStats mapping |
| Red Tape compatibility | Red Tape FarmExtension, TaxSystem, InitialClientState, save hook |
| Multiplayer security | Bank & Credit request events, ACS authorization/results, TradeIn request validation |
| Recovery/save integrity | FYF/ACS durable-mirror ideas plus AgForward schema-v3 integrity design |

---

# 14. Final re-audit conclusion

No donor finding changes AgForward's fundamental architecture. The second audit instead provides strong evidence that the chosen architecture is necessary.

The highest-value concepts retained are:

- Bank & Credit's connection-derived authorization and banking product breadth;
- FYF's stable vehicle identity, delayed deletion confirmation, and stale-save recovery defenses;
- ACS's server-originated secured finance and lien-aware sale settlement;
- Field Leasing's farmland-map workflow **without** its ownership conflation;
- Economic History's server-generated reporting snapshots;
- Red Tape's save-hook coexistence reasoning and tax classification constraints;
- Trade In's server revalidation and future gross-value input for net trade equity.

The next AgForward work must continue to implement these as **original common services**, not as donor-specific subsystems.
