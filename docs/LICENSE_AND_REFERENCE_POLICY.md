# License and Reference Policy

AgForward is intended to be an original implementation.

## Third-party reference mods

The project team may study third-party mods to understand:

- observable player-facing behavior;
- compatibility constraints;
- savegame/interoperability requirements;
- Farming Simulator extension points;
- failure modes and design lessons.

## Prohibited reuse without explicit permission/license

Do not copy or adapt protected third-party:

- Lua source code;
- class/file architecture when it is distinctive rather than required by FS25 APIs;
- GUI XML/layouts;
- localization strings/descriptions;
- icons, textures, sounds, or other assets;
- documentation prose;
- unique branding.

## Reference-mod license posture

Where a reference archive has no clear redistribution license, treat it as **reference-only**. Where it states All Rights Reserved, do not incorporate its code or assets. If a permissive/open-source license is later identified, any reuse decision must be documented before code is imported.

## AgForward design process

Requirements should be expressed in implementation-neutral language, for example:

- "support a revolving credit facility with interest charged on outstanding balance";
- "block or settle a lien before an encumbered asset is sold";
- "separate principal from interest in accounting".

AgForward code should then implement those requirements independently under AgForward naming, data models, interfaces, and UI.

## Compatibility adapters

Adapters may detect and interoperate with external mods through available globals, events, APIs, or observable FS25 integration points, but should not embed third-party code.

## Project license

A final license for AgForward itself has not yet been selected. Until that decision is made, do not add a third-party-derived LICENSE file or state redistribution terms that have not been explicitly approved by the project owner.
