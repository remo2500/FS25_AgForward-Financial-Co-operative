# AgForward Runtime Package Promotion Boundary

**Status:** governing development-process rule  
**Applies to:** `offline-foundations` and future development branches

## Why this boundary exists

The AgForward repository deliberately contains more code than the current FS25 runtime candidate is authorized to load. Pure finance, underwriting, collateral, leasing, reporting, and network models can be developed and tested offline before their persistence and GIANTS integration are proven.

A repository ZIP is therefore **not** a valid runtime candidate.

The test mod must contain only code/resources that have been explicitly promoted into the current runtime surface.

## Package builder

Use:

```text
python tools/build_mod_package.py --output dist/FS25_AgForwardFinance.zip --list
```

The builder packages only:

1. root `modDesc.xml`;
2. Lua files referenced by `modDesc.xml` under `extraSourceFiles`;
3. localization files matching the configured `l10n filenamePrefix`;
4. direct supported modDesc resources such as `iconFilename` when present;
5. root `LICENSE` when present;
6. explicitly promoted non-modDesc resources listed in `runtime_package_manifest.txt`.

It does **not** sweep the whole `src/` directory.

## Optional runtime resource manifest

When future promoted code requires GUI XML, textures, or other files not directly referenced by modDesc, add explicit repository-relative paths/globs to:

`runtime_package_manifest.txt`

Example:

```text
# Promoted Phase-0 diagnostic GUI
gui/AgForwardDiagnosticFrame.xml
gui/profiles/*.xml
images/agforward_menu.dds
```

Development directories are blocked from this manifest:

- `.git/`
- `.github/`
- `docs/`
- `tests/`
- `tools/`

## Promotion rule for an offline Lua module

An offline module becomes runtime code only through an intentional change that:

1. confirms its dependencies are runtime-ready;
2. registers it in the correct dependency order in `modDesc.xml`;
3. adds any required persistence migration deliberately;
4. adds any required multiplayer authority/event contract;
5. updates integrity validation;
6. passes offline CI;
7. passes current GIANTS TestRunner on the built ZIP;
8. passes the relevant in-game disposable-save tests.

Merely existing under `src/` does not promote a module.

## CI contract

GitHub Actions now:

- unit-tests the package builder;
- builds the explicit runtime ZIP;
- lists the selected manifest;
- continues with Lua syntax and offline behavioral suites.

This provides a mechanical check that experimental/offline-only files are not accidentally shipped in the runtime test candidate.

## Current consequence

The large `offline-foundations` branch can continue to accumulate pure models without silently changing the actual FS25 runtime surface. Until a module is deliberately added to `modDesc.xml`, it remains research/offline authority only.

This boundary does not imply the packaged runtime candidate has passed FS25. GIANTS TestRunner and in-game validation remain separate gates.
