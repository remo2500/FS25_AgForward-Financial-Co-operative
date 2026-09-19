# AgForward Native Menu Icon Specification

## Goal

The AgForward icon must look like it belongs beside the existing FS25 in-game menu icons.

## Visual rules

- monochrome source artwork;
- transparent background;
- no gradients;
- no tiny text;
- no photographic detail;
- no shield/seal treatment that reads like a corporate logo;
- no copy of a GIANTS base-game icon;
- no imitation of another lender's trademark;
- similar optical weight and internal padding to neighboring FS25 menu symbols;
- works when native UI tinting applies focused/selected/disabled states.

## Preferred concept

A compact **agriculture + finance** symbol.

Primary concept to prototype:

- two or three field/furrow lines forming the lower portion;
- a simple ledger/document or upward financial mark integrated above;
- strong silhouette at small tab size;
- no dollar sign required.

Alternative concept:

- grain/leaf element combined with a minimal ledger line.

Avoid generic bank columns/building imagery unless the agricultural concept fails at small size.

## Technical gate

Final pixel dimensions, texture format, atlas/slice choice and UV bounds must be verified against the actual FS25 menu registration path before the icon is promoted.

Until then the offline frame reserves an icon control but does not ship a guessed final asset.
