# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0.2] - 2026-07-12 — Critical fix: spec table + join crash

### Fixed
- **Specialization was registered under a mod-prefixed name**, so the per-vehicle
  spec table `self.spec_ironHorseRealism` was never created — every update tick
  threw `attempt to index nil with 'modules'`, and the same nil access in
  `onWriteStream` **broke multiplayer client joins**. Now the spec is inserted
  under its plain name directly into the vehicle type (mirroring the proven ADS
  approach), so the spec table exists and the accessor resolves.
- Added nil-guards to every specialization handler as a safety net so a missing
  spec table can never crash the update loop or a client join again.

## [0.1.0.1] - 2026-07-11 — Foundation hotfix

### Fixed
- **Duplicate specialization registration.** `TypeManager.finalizeTypes` can run
  more than once (base types + map); the per-type guard now matches the
  mod-prefixed specialization name, so the spec is added exactly once instead of
  spamming "Specialization already exists" errors for every vehicle type.
- Removed the unused HUD-toggle action binding (it was not wired yet and only
  produced a missing-l10n warning).

## [0.1.0.0] - 2026-07-11 — Foundation

### Added
- **Modular core (the extensible backbone).** One vehicle specialization
  (`ironHorseRealism`) dispatches all lifecycle events to a registry of feature
  modules. Adding a feature = registering a module; the core never changes.
  - `IronHorseModule` — module contract with safe-default lifecycle hooks.
  - `IronHorseModuleRegistry` — ordered, deduped module registry.
  - `IronHorseSpecialization` — the dispatch seam (load/update/read+write stream/
    save/draw), injected into every motorized vehicle type.
- `IronHorseSyncEvent` — one generic server-authoritative state-sync event for
  modules whose state the engine does not replicate.
- `IronHorseRealData` — single source of real-world values (battery, engine
  temperatures, tire pressure), grounded in real data.
- `IronHorseHud` — one unified HUD; modules push lines/warnings into a shared frame.
- `IronHorseConfig` — deliberately minimal, operation-locked settings.
- **First feature module — `engineStall`:** soft-stall under overload. Sustained
  full engine load or lugging (low rpm + high load) stalls the engine
  (server-authoritative via `stopMotor`, engine-synced to all clients), with a
  brief no-restart cooldown and a live HUD load indicator.
- **Coexistence detector:** takes technical precedence over the mods it
  replaces (ADS / EnhancedVehicle / VariableTirePressure) when present, and
  flags them loudly — not just a readme note.
- Gold-standard harness: `.luacheckrc`, busted unit tests, `build.sh`
  (root-`modDesc` zip), proprietary source-available `LICENSE`.

### Notes
- Foundation release — the core + one vertical-slice feature. Further modules
  (engineHealth, drivetrain, tires, electrical, visualDirt, toolbox) plug into
  this backbone.
- Core pure-logic verified 13/13 via a real Lua runtime; in-game behaviour to be
  verified on a live MP server.
