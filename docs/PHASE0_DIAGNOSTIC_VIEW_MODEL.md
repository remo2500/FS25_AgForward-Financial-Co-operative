# Phase 0 Read-Only Diagnostic View Model

**Status:** offline UI foundation  
**Runtime GUI enabled:** NO

## Purpose

Before AgForward moves real FS25 money, the first in-game screen should make the financial runtime state visible and auditable. It should help diagnose persistence, safe-mode, compatibility, Red Tape, liability, ledger, and settlement issues without allowing financial mutations.

`src/reporting/DiagnosticSnapshotService.lua` now provides the pure read-only view model for that screen.

## Proposed first diagnostic screen

The initial runtime UI can be intentionally simple and display:

### Runtime

- AgForward build version;
- save schema version;
- save generation;
- runtime state (`NEW_STATE`, `NORMAL`, `RECOVERED`, `READ_ONLY_SAFE_MODE`, etc.);
- persistence source (primary/recovery/new);
- server authority status;
- safe-mode reason when applicable.

### Integrity / compatibility

- current warning/error list;
- known overlapping finance mods;
- Red Tape status;
- overall health indicator (`normal`, `warning`, `error`).

### Financial state

- liability count;
- total represented AgForward outstanding balance;
- per-liability product/status/principal/accrued interest/accrued fees/outstanding balance;
- total ledger transaction count;
- recent transaction summary.

### Settlement

- settlement engine version;
- last completed settlement key;
- in-progress key if one exists.

## Authority rule

The diagnostic model is derived from existing services and registries. It owns no balances and is not persisted.

The GUI must never allow a player to edit a diagnostic snapshot and send it back as authoritative state.

## Safe-mode behavior

In `READ_ONLY_SAFE_MODE` the screen should remain accessible where practical so the player can see:

- why AgForward refused to mutate/save;
- which financial copy/source was involved;
- detected integrity issues;
- whether Red Tape or another finance mod is present;
- the last readable financial information.

Safe mode should visually disable future mutation actions rather than hiding the diagnosis.

## Runtime integration still required

The following remain in-game work:

- create/register the actual FS25 GUI frame/menu page;
- obtain the active farm ID from the player/server context;
- pass actual build/schema/generation/persistence-source values;
- refresh the snapshot when authoritative state revision changes;
- ensure dedicated-server/client display behavior is correct;
- localize all labels and statuses.

The view model itself can now be tested independently from GUI XML and FS25 rendering.
