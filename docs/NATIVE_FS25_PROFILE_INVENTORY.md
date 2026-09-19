# AgForward Native FS25 GUI Profile Inventory

**Status:** offline compatibility research  
**Runtime authority:** not yet proven in game

## Purpose

AgForward should reuse native FS25 GUI behavior and visual profiles rather than approximate the base game with a separate theme.

The initial offline frame uses only a conservative set of profiles that were observed in current FS25 finance/menu mods and are consistent with GIANTS' documented GUI/profile inheritance model.

## Profiles currently used by the offline frame

Menu/header:

- `baseReference`
- `emptyPanel`
- `fs25_menuContainer`
- `fs25_menuHeaderPanel`
- `fs25_menuHeaderIconBg`
- `fs25_menuHeaderIcon`
- `fs25_menuHeaderTitle`
- `fs25_shopMoneyBoxBg`
- `fs25_shopMoneyBox`
- `fs25_shopBalance`
- `fs25_shopMoney`

Secondary navigation:

- `fs25_subCategorySelectorTabbedBox`
- `fs25_subCategorySelectorTabbedTab`
- `fs25_subCategorySelectorTabbedTabBg`
- `fs25_subCategorySelectorTabbed`
- `fs25_subCategorySelectorTabbedContainer`
- `fs25_lineSeparatorTopHighlighted`

Financial lists/text:

- `fs25_statisticsHeaderBox`
- `fs25_textDefault`
- `fs25_financesList`
- `fs25_financesListItem`
- `fs25_financesListItemBg`

## Color rule

AgForward native-derived profiles may adjust layout dimensions, alignment, text size, and anchoring.

They may **not** introduce a separate application palette.

When a color override is necessary it must use an FS25 semantic preset such as:

- `$preset_fs25_colorMainHighlight`
- `$preset_fs25_colorMainLight`
- `$preset_fs25_colorMainDark`
- `$preset_fs25_colorGreyListItem`

Literal custom RGBA colors are rejected by the offline UI validator.

## Why profile inheritance matters

GIANTS documents that GUI XML properties can come from inheritable profiles, and direct XML settings override those profile values. That makes unnecessary direct color/style overrides a risk to native appearance.

AgForward therefore keeps custom profiles shallow and layout-focused.

## Menu registration research

GIANTS' FS25 `TabbedMenu` supports runtime page registration with a `FrameElement`, position, tab icon, UVs and optional enabling predicate.

`TabbedMenuFrameElement` is the intended base class for in-game menu frames and supports native menu-button information and frame open/close lifecycle.

The future AgForward runtime path is therefore:

1. construct `AGFNativeMenuFrame`;
2. load `gui/AgForwardFrame.xml` as a frame;
3. register one AgForward page in the native `InGameMenu`;
4. use one native tab icon;
5. keep AgForward's eight internal areas as native secondary navigation.

## Existing base-game finance screen

FS25 already has an `InGameMenuFinancesFrame` and a loan trigger that opens the finances screen.

That gives AgForward two plausible runtime integration strategies:

1. add a dedicated AgForward top-level page adjacent to existing financial/statistics pages; or
2. integrate more deeply with the existing finance route.

The first runtime UI test should prefer the less invasive dedicated page. Redirecting or replacing the base-game finances screen should only be considered after compatibility testing.

## Current gate

The profile names above are treated as **offline candidates**, not guaranteed runtime authority.

Before promotion we must verify:

- the profiles exist in the installed FS25 build;
- their dimensions/anchors are compatible with the AgForward frame;
- UI scaling behaves correctly;
- controller focus is correct;
- list row selection/focus colors are inherited correctly;
- header icon rendering/UVs match surrounding tabs.
