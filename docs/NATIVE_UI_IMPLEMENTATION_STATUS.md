# AgForward Native UI Implementation Status

**Branch:** `offline-foundations`  
**Runtime UI enabled:** NO

## Implemented offline

The first actual AgForward GUI layout now exists as:

- `gui/AgForwardFrame.xml`

Controller foundation:

- `src/ui/AgForwardNativeMenuFrame.lua`

Pure view-model projection:

- `src/ui/NativeUIViewModelService.lua`

Static native-style guard:

- `tools/validate_native_ui.py`

## Current page shell

One future top-level AgForward menu page contains native secondary navigation for:

1. Overview
2. Credit
3. Assets
4. Land
5. Payments
6. Reports
7. Government
8. Settings

### Overview

The first layout contains:

- native menu header and farm balance box;
- represented cash;
- represented equity;
- total debt;
- working capital;
- DSCR;
- fixed-charge coverage;
- debt/assets;
- data-quality status;
- upcoming obligations list.

### Credit

The first layout contains:

- revolving credit facility list;
- balance;
- limit;
- available credit;
- rate;
- status;
- selected-facility summary.

This is the natural home for the General Operating Line and Crop Input Line.

### Asset Finance

The read-only asset-finance page now contains:

- financed equipment/project list;
- asset name;
- finance product;
- outstanding balance;
- scheduled payment;
- interest rate;
- servicing status;
- selected-asset value;
- lien count;
- stable-link state.

### Land

The land page now combines:

- land-finance arrangements;
- economic leases;
- periodic rent or outstanding finance amount;
- next payment;
- remaining term/periods;
- status.

This representation intentionally keeps financed ownership and lease access distinct.

### Payments

The payment/servicing page now contains:

- every represented open liability;
- account status;
- next scheduled payment;
- past-due amount;
- servicing-review count.

Rows with higher servicing severity sort first in the pure view model.

### Reports

The first layout contains native-style rows for:

- Financial Position;
- Debt Schedule;
- Financial History;
- Crop Input Source of Funds;
- Assets & Liens;
- Lease Commitments.

### Remaining areas

Government and Settings remain placeholder containers. Report rows are present but report-drilldown frames are not yet built.

The Credit page now also exposes CILOC-specific effective limit, reservations, utilization and seasonal state in the selected-facility detail area when the integrated CILOC review is available.

## Native-style enforcement

The offline GUI validator currently enforces:

- no custom profile names that shadow `fs25_*`;
- all used profiles must be on the approved native list or inherit from an approved/custom native-derived profile;
- custom colors must use FS25 preset variables;
- eight secondary-navigation tabs/pages must exist;
- core frame control IDs must exist;
- the GUI/controller must remain absent from `modDesc.xml` until runtime promotion.

## Runtime work still required

The frame has not yet been rendered in FS25.

Before promotion:

- confirm exact GUI profile availability;
- confirm frame reference/loading pattern;
- confirm top-level tab position;
- confirm icon atlas/slice or texture/UV behavior;
- test focus graph with gamepad;
- test mouse/keyboard;
- test common resolutions and UI scaling;
- verify long localization strings;
- bind active farm/server state;
- verify list reload/selection behavior;
- ensure safe mode disables future mutation actions;
- confirm dedicated-server clients display synchronized state only.

## Design rule

If the screen looks like a separate banking program pasted into FS25, it is wrong.

The goal is that a player unfamiliar with the mod could reasonably assume the AgForward page was part of the base game's finance system.
