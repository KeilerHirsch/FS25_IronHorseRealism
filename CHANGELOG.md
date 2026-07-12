# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- **engineHealth module — engine wear & temperature.** Second feature on the
  backbone and the first with persistent, synced state. A diesel thermal model
  (temperature integrates toward a load-based target — idles warm, climbs into the
  overheat band under sustained heavy load, cools to ambient; ambient taken from
  the in-game weather) plus an engine condition (0..1) that degrades from
  overheating, cold-shock (load on a cold engine), and sustained overload. Two
  cockpit indicators (TEMP + ZUSTAND), server-authoritative with throttled MP
  sync, and condition PERSISTS across saves (first use of the backbone's savegame
  hooks). Numbers grounded in `IronHorseRealData.engine`. Consequences (power
  derate / stall-risk coupling, cold-start limit) are deferred to the tuning pass.

## [0.1.3.0] - 2026-07-12 — HUD dashboard framework + multiplayer fix

### Added
- **Cockpit-style HUD dashboard framework.** The unified HUD is now a
  severity-coloured indicator cluster (mirrors the clean ADS dashboard look, own
  code): it anchors to the game's speed gauge when available, with a fixed
  fallback. Each module now DECLARES its indicators via the new
  `getHudIndicators` contract — the HUD owns all layout, colour
  (INFO / WARNING / CRITICAL / COOL) and rendering. This is the shared surface
  every future module (engineHealth, drivetrain, tires, electrical, ...) drops
  its warning symbol into. Icons are placeholder chips for now; a hand-drawn
  IronHorse icon atlas is a later art pass that swaps only the chip renderer.

### Fixed
- **Multiplayer: the "engine labors" cue never reached dedicated-server clients.**
  The struggle phase is computed server-side only, but on a dedicated server no
  player is the server, so the driving client never saw `PHASE_STRUGGLE` and the
  "!! Motor quaelt sich" HUD warning never appeared — the core feature was broken
  on its own target platform. The phase is now replicated to clients: initial
  sync on join (`onWriteStream`/`onReadStream`) and a live sync on every phase
  change (`IronHorseSyncEvent`, server → clients).

### Security
- **`IronHorseSyncEvent` no longer applies unauthenticated client writes.** The
  server now rejects any client-originated sync unless its `(module, key)` is on
  an explicit client-writable whitelist (empty today — all state is
  server-authoritative). Closes a trust-boundary gap in the shared sync infra.

### Changed
- `engineStall` phase is now a compact numeric enum (was a string) so it
  serialises directly over the network. No gameplay change.
- Module HUD contract: `drawHud` (pushed raw text lines) → `getHudIndicators`
  (declares structured indicators). engineStall now reports a MOTOR indicator
  whose severity comes from a pure, unit-tested `indicatorSeverity`
  (struggle → CRITICAL, heavy load → WARNING, else INFO) plus a live load-% readout.

### Removed
- Dead `IronHorseSpecialization.prerequisitesPresent` (never consulted — the spec
  is injected after `validateTypes`; the real "must be motorized" gate is the
  injection filter). Replaced with a comment at the seam.

### Notes
- `STALL_COOLDOWN_S` clarified: it is a post-stall re-stall debounce that, at the
  current thresholds, never actually bites (acc-rebuild time already exceeds it).
  A true no-restart lockout is a fine-tuning TODO for the power-drop pass.
- **Early access.** Pure logic + syntax verified (12/12 via lupa) plus a full
  ECC multi-agent review (0 CRITICAL/HIGH; all MEDIUM/LOW findings fixed). Still
  to confirm live on a dedicated server: the phase MP-sync (struggle cue reaches
  the client) and the HUD cluster (renders next to the speed gauge, MOTOR chip
  colours by severity) — a hotfix follows if the playtest finds anything.
  Fine-tuning is deliberately last: active power drop during struggle
  (`setAccelerationLimit`), exhaust smoke, threshold calibration, and a
  hand-drawn icon atlas to replace the placeholder chips.

## [0.1.2.0] - 2026-07-12

### Changed
- Relicensed to **GPLv3** (was proprietary source-available). IronHorse is now the
  open masterpiece — forks and PRs welcome, keep the attribution and the same license.
  The KeilerHirsch default is GPLv3; the prior v0.1.1.0 release stays under its old license.

## [0.1.1.0] - 2026-07-12 — engineStall: struggle-then-stall

### Changed
- The engine no longer dies instantly under overload. It now runs in **two
  phases**: it first **audibly labors** (bogs down under sustained overload for
  ~1.5 s+) and only **stalls** if the overload continues past a grace window
  (~2.5 s of struggling). Feels like a real diesel fighting the load, not a
  hard cut. Overload threshold lowered to 0.90 so heavy pulls register.
- HUD now shows the phase: normal load → overload warning → "Motor quaelt sich".

### Notes
- Rough tuning pass (thresholds are first estimates, fine-tuning to follow).
- Fine-tuning TODO: actively drop power during the struggle phase for a louder
  bog-down (`Motorized:getMotor():setAccelerationLimit`) and optional exhaust
  smoke; left out here until in-game calibration.

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
