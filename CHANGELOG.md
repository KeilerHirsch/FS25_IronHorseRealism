# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [0.2.1.0] - 2026-07-12 — field-repair action (early access)

### Added
- **toolbox field-repair action (the first working input).** A "field repair"
  key (Shift+R by default) lets you patch a damaged machine in the field. It is
  server-authoritative: the client press sends a `ToolboxRepairEvent`, and the
  server reads the damage + price from the vehicle itself (never a client value),
  charges the owner farm FS25-style (`MoneyType.VEHICLE_REPAIR`), and lowers the
  damage to the field-repair floor — a partial, cheaper alternative to the
  workshop. Adds the first input layer to the backbone (`onRegisterActionEvents`
  dispatch + a per-module hook).

### Changed
- **Repair costs now reuse FS25's own repair curve** (`price × damage^1.5 × 0.09`,
  from `Wearable.calculateRepairPrice`) so they feel native to the economy; a
  field repair is a 45 % discount on the workshop's marginal cost for the damage
  chunk it fixes. That 9 % also matches real German ag-workshop data (€70–130/h,
  lifetime repair ~25 % of price). See `docs/REPAIR_ECONOMICS.md`.

## [0.2.0.0] - 2026-07-12 — the seven-module chain (early access)

Early access. Every module is built on the backbone with its cockpit readout in
the one shared HUD, server-authoritative multiplayer sync and savegame
persistence. The physics/consequence layer (diff & tyre forces, dirt & repair
effects) is deliberately deferred and calibrated in-game — see
`docs/INGAME_PHYSICS_PLAN.md`. License unchanged (GPL-3.0).

### Added
- **drivetrain module — differential locks & power split (physics layer).** Front
  / rear diff locks and a 2WD / 4WD / FWD drive mode, plus the front/rear power
  split. Pure diff resolution (locked binds an axle, open runs free) and the
  drive-mode/split maths are grounded in the GIANTS `updateDifferential` contract
  (mechanic re-built clean-room from the engine API + real driveline behaviour;
  EnhancedVehicle referenced for the HOW only, never copied — it is GPL-3.0).
  Three cockpit indicators (DIFF V / DIFF H / ANTRIEB), server-authoritative with
  MP sync, state persists across saves. Locks are stored numerically (0/1) so the
  float-only sync channel can't misfire the Lua "0 is truthy" trap. The physics
  apply (`applyDifferentials`) + input toggles are the deferred in-game hook —
  see `docs/INGAME_PHYSICS_PLAN.md`.
- **tire module — tyre pressure & traction (physics layer).** Per-axle radial
  ag-tyre pressure (bar) and the traction/contact-patch it buys: low pressure =
  bigger footprint = field grip, high pressure = road efficiency. The pure
  pressure→traction curve interpolates real ag-tyre tractive-efficiency endpoints
  (Michelin/Trelleborg field-vs-road, in `IronHorseRealData.tire`) — a permissive-
  code search found nothing that fits this axis, so the curve is hand-rolled on
  real data. Two cockpit indicators (REIFEN V / REIFEN H bar + grip%),
  server-authoritative with throttled MP sync, pressures persist across saves. The
  `WheelPhysics.updateTireFriction` override + inflate/deflate input are the
  deferred in-game hook — see `docs/INGAME_PHYSICS_PLAN.md`.
- **visualDirt module — dirt & dust readout + realism rate.** Rather than
  re-model dirt, it REUSES the engine's own Washable dirt system (getDirtAmount,
  already replicated + saved by the engine) as the source of truth, adds a cockpit
  indicator (SCHMUTZ %) that warns only when the machine is filthy, and supplies
  the realism layer vanilla lacks: a pure, tested condition-based accumulation
  rate (mud cakes on fast in the wet field, dust when dry and moving). A pure
  reader with no state/sync/save of its own. Applying that rate to the engine dirt
  and coupling heavy dirt into cooling → engineHealth are the deferred consequence.
- **toolbox module — field repair.** A makeshift in-field repair that keeps the
  machine going between workshop visits: cheaper and quicker than the workshop but
  only partial (a full repair still needs the workshop). Reuses the engine's own
  Wearable damage (getDamageAmount, replicated + saved by the engine) for the
  cockpit indicator (SCHADEN % + a "Feldrep." cue when worth it) and supplies the
  pure, tested field-repair maths — how much a makeshift fix restores (capped at a
  floor), whether it's worth doing, and what it costs. A pure reader with no
  state/sync/save of its own. The repair ACTION (input) and the cost calibration
  against real workshop prices are the deferred consequence/tuning.
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
- **electrical module — battery & alternator.** A 12 V lead-acid starter battery
  (150 Ah): parasitic drain when off, alternator recharge (~14.4 V) while running,
  terminal voltage that tracks state of charge at rest. Two cockpit indicators
  (BATT voltage + LADUNG %), server-authoritative with throttled MP sync, SOC
  persists across saves. Grounded in `IronHorseRealData.battery`. The no-crank
  consequence (flat battery won't start the engine) is deferred to the tuning pass.

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
