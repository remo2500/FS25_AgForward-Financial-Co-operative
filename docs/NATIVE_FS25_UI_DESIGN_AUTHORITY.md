# AgForward Native FS25 UI Design Authority

**Status:** LOCKED design direction  
**Branch:** `offline-foundations`  
**Runtime GUI enabled:** NO

## Goal

AgForward must look and behave as though its financial interface shipped with Farming Simulator 25.

The target is **not** "a modern banking app inside FS25." The target is **FS25's own interface language applied to agricultural finance**.

This supersedes earlier exploratory ideas that proposed a distinct navy/green banking skin.

## Native-first rule

When a native FS25 visual or interaction pattern exists, AgForward should use it before inventing a custom one.

That includes:

- menu frame structure;
- tab/page navigation;
- title placement;
- button bars;
- list rows;
- selectors;
- dialogs;
- confirmation flows;
- focus/hover/selected states;
- warning and disabled states;
- controller navigation;
- keyboard/mouse navigation;
- action glyph presentation;
- typography;
- text sizing;
- margins/padding;
- panel backgrounds;
- separators and row highlighting.

## Technical direction

FS25's GUI architecture provides `GuiElement`, `FrameElement`, and tabbed in-game menu frame/menu classes. AgForward should integrate into those systems rather than drawing a separate full-screen overlay.

Target runtime approach:

1. create AgForward page controllers as descendants of the native frame classes;
2. load page layouts from GUI XML;
3. register a top-level AgForward page/tab with the in-game menu through the supported tabbed-menu page mechanism;
4. use native focus management and menu-button information;
5. bind controller IDs through the normal `FrameElement` control-ID mechanism;
6. expose financial state through read-only view models first;
7. enable mutations only after server-authoritative runtime actions are proven.

Exact profile names and XML attributes must be verified against the installed FS25 GUI resources/runtime before promotion. Do not guess profile names into a release candidate.

## Color authority

AgForward does **not** get a separate application-wide color theme.

Default rule:

- backgrounds: native FS25;
- primary text: native FS25;
- secondary text: native FS25;
- selected/focused controls: native FS25;
- disabled controls: native FS25;
- warning/error/success states: native FS25 semantic treatment;
- buttons/action bar: native FS25.

AgForward branding can appear through:

- the AgForward name;
- a restrained wordmark if a suitable location exists;
- the AgForward menu icon;
- possibly one small brand accent if it can be applied without making the screen look third-party.

A visually obvious green/navy banking theme is out of scope.

## Icon authority

The AgForward main-menu icon should look like a GIANTS first-party UI symbol:

- simple silhouette/line construction;
- monochrome source;
- transparent background;
- no photographic detail;
- no gradient branding;
- no tiny text;
- similar stroke/visual weight to surrounding FS25 menu icons;
- similar internal padding and optical centering;
- compatible with native normal/focused/disabled tinting.

Preferred concept direction:

**agricultural finance symbol**, not a commercial bank logo.

Candidate motif:

- a simple field/furrow or grain form;
- combined with a restrained finance/ledger/credit element;
- readable at small tab-icon size.

The icon should not imitate another company's trademark or reuse protected base-game artwork.

## Navigation

AgForward should feel like one native FS25 subsystem.

Top-level AgForward area:

1. Overview
2. Banking & Credit
3. Asset Finance
4. Land & Leases
5. Payments & Obligations
6. Reports
7. Government — only when the integration is available/useful
8. Settings

Implementation may use one top-level FS25 menu tab that opens an AgForward frame with native secondary page selectors, rather than consuming eight global FS25 tabs. Final structure should be chosen after runtime evaluation of the native menu.

## Overview page

The Overview should prioritize the same information-density philosophy as native FS25 menus:

- a few strong summary values;
- clear rows/panels;
- no decorative dashboard widgets merely for appearance;
- no tiny dense spreadsheet;
- controller-readable grouping.

Target information:

- cash;
- represented net worth/equity;
- total debt;
- working capital;
- DSCR;
- fixed-charge coverage;
- debt-to-assets;
- operating-line utilization;
- CILOC utilization;
- upcoming obligations;
- arrears/servicing warnings;
- rate renewal/maturity notices.

The exact number of simultaneous KPIs should be tuned after observing the screen at common FS25 resolutions and UI scales.

## Banking & Credit

Native list/detail structure:

Left/list or row area:
- General Operating Line;
- Crop Input Line;
- term loans;
- current applications/offers where appropriate.

Detail area:
- limit/original amount;
- current balance;
- available credit;
- rate;
- next payment;
- maturity/renewal;
- status;
- product-specific information.

Actions belong in the native action-button bar, not as oversized custom web-style buttons.

## Crop Input Line

Must expose:

- approved limit;
- borrowing-base constrained limit;
- outstanding;
- reservations;
- available credit;
- rate;
- funding policy;
- seasonal cleanup/maturity state;
- category spend/budget;
- source-of-funds split.

Funding-policy selection should use a native selector/list pattern.

## Asset Finance

Use familiar FS25 list/detail behavior:

- financed equipment/projects;
- asset name/type;
- principal/outstanding;
- payment;
- lien/security;
- payoff;
- servicing status.

Contextual vehicle/construction finance entry points should lead into the same common quote/detail controllers.

## Land & Leases

Clearly separate:

- owned/economically owned land;
- financed land;
- leased/tenant land;
- rent obligations;
- land liens.

The UI must never imply that lease access equals ownership.

## Payments & Obligations

Primary uses:

- upcoming scheduled obligations;
- overdue amounts;
- cure amounts;
- payoff requests;
- payment history;
- settlement results.

Use native warning treatments for arrears and recovery states.

## Reports

Initial read-only reports:

- financial position;
- debt schedule;
- cash-flow/history;
- principal/interest/fees;
- crop-input source of funds;
- assets/liens;
- lease commitments.

Charts are optional. Tables/list views take priority when they are more consistent with FS25.

## Government

This page is conditional.

When Red Tape is unavailable, do not create a fake government system merely to fill the page.

When available, AgForward may summarize supported Red Tape information while leaving taxation/grants/policy authority with Red Tape.

## Settings

Only real player choices belong here.

Examples:

- CILOC funding policy;
- optional authorized settlement use of an operating line;
- notification preferences;
- future display/reporting options.

Developer/debug controls belong in a development-only diagnostic area, not the production settings screen.

## First runtime GUI

The first promoted GUI should be deliberately small and read-only.

Recommended first page:

**AgForward Diagnostics / Overview**

Show:

- runtime state;
- persistence source/generation;
- server/client authority;
- Red Tape detection;
- compatibility warnings;
- liability count/outstanding;
- recent ledger records;
- last settlement key.

This allows the native frame, tab registration, focus/navigation, localization, and resizing behavior to be tested before financial actions become clickable.

## Accessibility / input

Required:

- controller-first focus graph;
- keyboard/mouse support;
- no hover-only information;
- readable at base-game UI scaling;
- no reliance on color alone for status;
- clear focus state;
- sensible text truncation/scroll behavior;
- confirmation dialog for destructive financial actions.

## Do not do

- separate HTML/web-dashboard styling;
- glossy bank-app cards;
- custom nav rail unrelated to FS25;
- branded gradients;
- excessive green/red KPI tiles;
- tiny financial spreadsheet text;
- non-native modal designs;
- mouse-only controls;
- custom fonts;
- base-game icon copying/recoloring as AgForward branding;
- hard-coded profile/color assumptions before runtime verification.

## Promotion gate

No GUI XML/controller is added to the runtime candidate until:

1. exact FS25 frame/page registration is verified;
2. the required native profiles are confirmed;
3. menu icon dimensions/UV behavior are confirmed;
4. controller focus/navigation is tested;
5. common resolutions/UI scaling are checked;
6. read-only diagnostic page works in SP and MP;
7. safe mode can still open the diagnostic UI without enabling mutation actions.
