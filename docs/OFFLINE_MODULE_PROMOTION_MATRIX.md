# AgForward Offline Module Promotion Matrix

**Branch:** `offline-foundations`  
**Purpose:** prevent mature pure-model code from being confused with runtime-authorized FS25 code.

## Promotion states

- **RUNTIME-CANDIDATE** — already referenced by runtime `modDesc.xml`; pending/subject to FS25 validation.
- **PURE-READY** — deterministic offline behavior/tests exist; can be considered for later promotion after dependencies/runtime gates.
- **DESIGN-READY** — architecture/documentation exists but runtime integration or persistence design remains incomplete.
- **RUNTIME-BLOCKED** — depends directly on an FS25 hook/API/identity behavior that must be proven in game first.

No entry in this matrix overrides `AGFORWARD_CURRENT_AUTHORITY.md` or the runtime promotion rules.

## Phase-0 runtime candidate

| Area | Main files | State | Remaining gate |
|---|---|---|---|
| Runtime states | `core/RuntimeStateService.lua` | RUNTIME-CANDIDATE | FS25 load/safe-mode proof |
| Currency / IDs | `core/Currency.lua`, `core/IdService.lua` | RUNTIME-CANDIDATE | save/reload ID proof |
| Ledger | `ledger/Transaction.lua`, `ledger/Ledger.lua` | RUNTIME-CANDIDATE | persistence + live accounting boundary |
| Native liabilities | `liabilities/Liability*.lua` | RUNTIME-CANDIDATE | schema-v3 save/reload proof |
| Coordinated operations | `ledger/FinancialOperationCoordinator.lua` | RUNTIME-CANDIDATE | later FS cash atomicity proof |
| Purpose-aware accounting proof | `ledger/AccountingService.lua` | RUNTIME-CANDIDATE | later live MoneyType boundary |
| Purchase classification | `input/PurchaseClassificationService.lua` | RUNTIME-CANDIDATE | actual caller/fill-type hook proof |
| Input accumulator | `input/InputPurchaseAccumulator.lua` | RUNTIME-CANDIDATE | helper/live charge capture proof |
| Save/recovery | `core/SaveService.lua`, `core/IntegrityService.lua` | RUNTIME-CANDIDATE | GIANTS XML primary/recovery tests |
| Settlement idempotency shell | `settlement/SettlementCoordinator.lua` | RUNTIME-CANDIDATE | duplicate callback/runtime proof |
| Red Tape detection | `integrations/RedTapeAdapter.lua` | RUNTIME-CANDIDATE | save-hook/coexistence proof |
| Compatibility warning | `core/CompatibilityService.lua` | RUNTIME-CANDIDATE | actual mod-name detection check |

## Shared finance mathematics

| Area | Main files | State | Remaining gate |
|---|---|---|---|
| Rate convention/pricing | `finance/RateConvention.lua`, `RatePricingService.lua` | PURE-READY | policy calibration only |
| Amortization/balloon/bullet | `finance/AmortizationService.lua` | PURE-READY | contract persistence/version convention |
| Interest-only structures | `finance/StructuredAmortizationService.lua` | PURE-READY | UI/persistence promotion |
| Payment frequency / dates | `finance/PaymentFrequencyService.lua`, `LoanContractScheduleService.lua` | PURE-READY | FS calendar mapping confirmation |
| Rate-term renewal | `finance/RateTermRenewalService.lua`, `LoanRenewalQuoteService.lua` | PURE-READY | renewal UI/server transaction |
| Revolving interest | `finance/RevolvingInterestService.lua` | PURE-READY | live utilization timestamps |
| Payment allocation | `finance/PaymentAllocationService.lua`, `LiabilityPaymentPlanService.lua` | PURE-READY | coordinated live cash/liability commit |
| Prepayment | `finance/PrepaymentPolicyService.lua` | PURE-READY | product policy calibration |
| Variable-rate recast | `finance/VariableRateService.lua` | PURE-READY | runtime rate-reset event/persistence |

## Credit / underwriting

| Area | Main files | State | Remaining gate |
|---|---|---|---|
| Credit metrics/profile | `credit/CreditMetrics.lua`, `FarmCreditProfile.lua`, `CreditProfileBuilder.lua` | PURE-READY | complete runtime data sources |
| Exact debt-service window | `credit/DebtServiceWindowService.lua` | PURE-READY | persistent dated contract schedules |
| Pro-forma underwriting | `credit/ProFormaUnderwritingService.lua` | PURE-READY | approved product policies/data inputs |
| Credit policy | `credit/CreditPolicyService.lua` | PURE-READY | FS25-calibrated thresholds |
| Covenant monitoring | `credit/CovenantMonitoringService.lua` | PURE-READY | choose product monitoring policies + history/persistence |
| Seasonal liquidity | `credit/LiquidityProjectionService.lua` | PURE-READY | forecast input sources/calibration |
| Credit stress | `credit/CreditStressService.lua` | PURE-READY | scenario policy calibration |
| External obligations | `credit/ExternalObligation*.lua` | DESIGN-READY | discovery/reconciliation with vanilla/other mods |
| Collateral lending value | `credit/CollateralValuationService.lua` | PURE-READY | asset values/prior claims from runtime authority |

## Crop Input Line of Credit

| Area | Main files | State | Remaining gate |
|---|---|---|---|
| Borrowing base | `credit/CILOCBorrowingBaseService.lua` | PURE-READY | crop/acres/budget source + policy calibration |
| Seasonal/cleanup status | `credit/CILOCSeasonService.lua` | PURE-READY | persistence + financial calendar runtime proof |
| Harvest sweep | `credit/HarvestSweepService.lua` | PURE-READY | crop-sale interception/authorization policy |
| Funding decision | `input/FundingDecisionService.lua` | PURE-READY | pre-affordability purchase hook |
| Credit reservation | `input/CreditReservationService.lua` | PURE-READY | server concurrency/event integration |
| Category budget tracking | `credit/CILOCBudgetService.lua` | PURE-READY | choose soft/hard production policy + persistence |
| Integrated facility review | `credit/CILOCFacilityReviewService.lua` | PURE-READY | authoritative budget/base/facility data + UI/persistence |
| Purchase preflight planner | `input/CILOCPurchasePreflightService.lua` | PURE-READY | live pre-affordability hook + real server reservation/atomic commit |
| Actual eligible purchase finance | Phase-0 classifier/accounting + future hook | RUNTIME-BLOCKED | intercept before FS affordability decision |

## Assets / liens / rights

| Area | Main files | State | Remaining gate |
|---|---|---|---|
| Economic asset records | `assets/AssetRecord.lua`, `AssetRegistry.lua` | PURE-READY | stable FS identity/relink proof + schema promotion |
| Economic/operator/tenant rights | `assets/AssetRight*.lua` | PURE-READY | runtime access adapters + persistence |
| Liens | `assets/Lien*.lua` | PURE-READY | persistent asset identity + sale guards |
| Missing-link quarantine | `assets/AssetLinkQuarantine.lua` | PURE-READY | vehicle/placeable relink runtime proof |
| Secured disposition | `assets/SecuredDispositionService.lua` | PURE-READY | live sale interception + atomic payoff/transfer |

## Equipment / project / land

| Area | Main files | State | Remaining gate |
|---|---|---|---|
| Unified quote engine | `finance/LoanQuoteService.lua` | PURE-READY | server runtime UI/context |
| Origination plan | `finance/OriginationPlanService.lua` | PURE-READY | authoritative close transaction |
| Project sources/uses | `finance/ProjectSourcesUsesService.lua` | PURE-READY | construction price/event integration |
| Project draws | `finance/ProjectDrawAccrualService.lua` | PURE-READY | staged construction/runtime triggers |
| Land finance | shared quote/origination/asset/lien stack | DESIGN-READY | farmland purchase hook + stable identity |
| Equipment finance | shared quote/origination/asset/lien stack | DESIGN-READY | dealer purchase hook + stable vehicle identity |

## Leasing

| Area | Main files | State | Remaining gate |
|---|---|---|---|
| Lease model/registry | `leasing/Lease.lua`, `LeaseRegistry.lua` | PURE-READY | schema promotion + coordinated rent payments |
| Lease due schedule | `leasing/LeaseScheduleService.lua` | PURE-READY | FS period integration |
| Farmland operating access | future adapter | RUNTIME-BLOCKED | prove access mechanism without economic-ownership corruption |

## Multiplayer / offers

| Area | Main files | State | Remaining gate |
|---|---|---|---|
| Protocol revision/idempotency model | `network/FinancialProtocolState.lua` | PURE-READY | actual GIANTS Event serialization |
| Server financial offers | `network/FinancialOfferService.lua` | PURE-READY | live server lifecycle/events |
| Client application sanitizer | `network/FinancialApplicationIntentService.lua` | PURE-READY | derive actual farm/permissions from connection |
| Initial state snapshot/deltas | design/protocol foundations | DESIGN-READY | dedicated-server runtime testing |

## Reporting / UI

| Area | Main files | State | Remaining gate |
|---|---|---|---|
| Overview | `reporting/OverviewSnapshotService.lua` | PURE-READY | runtime data feed/UI |
| Ledger/source-of-funds | `reporting/LedgerReportService.lua` | PURE-READY | UI/export |
| Debt schedule | `reporting/DebtScheduleReportService.lua` | PURE-READY | persistent contract schedules |
| Diagnostic snapshot | `reporting/DiagnosticSnapshotService.lua` | PURE-READY | actual FS25 GUI frame/menu integration |
| CSV/history | design roadmap | DESIGN-READY | period snapshot persistence + filesystem export |

## Persistence roadmap

- **Current runtime:** schema v3 only.
- **Future design:** `docs/SAVE_SCHEMA_V4_DESIGN.md`.
- Assets, rights, liens, leases, external obligations, and richer contract state are intentionally **not** persisted yet.
- No offline module should be added to `modDesc.xml` merely because it has green unit tests.

## Promotion order after Phase-0 runtime validation

Recommended promotion sequence:

1. diagnostic snapshot + read-only diagnostic GUI;
2. shared finance math/contract schedule modules;
3. network revision/request-result infrastructure;
4. whole-farm credit/profile read path;
5. first real operating/term lending boundary;
6. CILOC pre-purchase funding/classification;
7. asset/right/lien persistence and equipment finance;
8. project finance;
9. land finance/leasing;
10. expanded reporting/history and deeper Red Tape reconciliation.

Each step should be promoted independently, with its own modDesc/persistence/integrity/runtime test gate.
