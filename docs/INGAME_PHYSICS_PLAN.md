# In-Game Physics-Hook Plan — drivetrain + tire

The pure logic of the drivetrain and tire modules (diff resolution, power split,
pressure→traction curve, contact patch, severities) is built, grounded in real
data, and verified headless by the lupa battery. What is **deliberately NOT wired
yet** is the part that touches the running driveline physics — because Farming
Simulator physics cannot be verified headless, only felt in-game. This document
is the ready-to-execute plan for that step, to be done on the **Thüringen x4
dedicated server** (the real MP target), in the end-of-build debug pass.

Both modules are **inert-but-safe** as shipped on `main`: state holds its default
(diffs open / 4WD, tyres at field pressure), the physics-apply paths are not
called, so a vehicle behaves vanilla. Enabling each is a localised, reversible
change — nothing here can brick the other modules' in-game test.

---

## 1. Shared prerequisite — input plumbing (both modules need it)

Neither module can be *felt* in-game until the player can change its state. The
backbone now HAS an input layer (added for the toolbox field-repair action: an
`onRegisterActionEvents` dispatch + a per-module `onRegisterActionEvents` hook + a
server-authoritative `ToolboxRepairEvent` command — use that as the worked
example). The remaining diff/tyre actions plug into it the same way:

1. `modDesc.xml` → `<actions>` + `<inputBindingContexts>` entries:
   `IH_DIFF_FRONT`, `IH_DIFF_REAR`, `IH_DRIVE_MODE`, `IH_TIRE_INFLATE`, `IH_TIRE_DEFLATE`.
2. `l10n` entries for each action name (en + de).
3. Backbone: register `onRegisterActionEvents` in `IronHorseSpecialization`
   (like `onUpdateTick`), dispatch it to a new optional module hook
   `onRegisterActionEvents(vehicle, state, isActiveForInput)`. Each module binds
   its own actions there and flips its state on the event **server-side**
   (client sends an input-request event → server changes state → existing sync
   replicates it back). Keep it server-authoritative: the input handler must not
   change state directly on a client, only ask the server.

Watch: bindings only active for the entered vehicle; unbind on leave.

**Security (from the review — enforce when wiring input):** the input handler must
read the authoritative values ITSELF server-side and clamp them before they touch
state — never trust a client-sent value:
- clamp tyre pressure to `[CFG.MIN_BAR, CFG.MAX_BAR]` and `driveMode` to the 0..2
  enum in the handler, not only in a later sync validator;
- the field-repair action must read `damage` via `getDamageAmount()` and the
  vehicle price itself — never accept `damage`/`vehiclePrice` as event parameters,
  or a client could claim higher damage / a different price and be paid. The pure
  `fieldRepairCost(damage, vehiclePrice, cfg)` is safe for internally-consistent
  inputs, but the wiring is the trust boundary.
- If any (module,key) is ever added to `CLIENT_WRITABLE`, its validator
  `(vehicle, connection, value) -> bool` must confirm connection ownership of the
  vehicle AND range-check the value.

---

## 2. Drivetrain — apply the diff/mode state to the driveline

**Engine call:** `updateDifferential(rootNode, diffIndex, torqueRatio, maxSpeedRatio)`
(diffIndex 0 = front axle, 1 = rear axle, 2 = centre / front-to-back).

**Ready method (already written, currently UNCALLED):**
`DrivetrainModule.applyDifferentials(vehicle, state, cfg)` in
`scripts/modules/DrivetrainModule.lua`. It reads the per-vehicle factory ratios
cached in `state.base` (via `readBaseRatios` on load) and pushes:
- axle 0/1: `axleMaxSpeedRatio(locked, base, cfg)` — locked → 1 (bound), open → base×1000.
- centre 2: `resolveDriveMode(mode, baseCentre, cfg)`.

**Wire it:** in `DrivetrainModule:onUpdate`, on the SERVER, call
`applyDifferentials` whenever a state field changes (right where the sync fires).
Only on change — not every tick.

**In-game checklist (dedicated):**
- [ ] A tractor still drives normally at the default (open, 4WD).
- [ ] Locking a diff visibly helps in mud / on a slope; unlocking restores turning.
- [ ] 2WD / 4WD / FWD each change behaviour as expected; no stuck/spinning axle.
- [ ] Toggling on the host AND on a joining client both work; the HUD chip
      (DIFF V / DIFF H / ANTRIEB) matches the actual driveline on every client.
- [ ] Join mid-session: the new client sees the current lock/mode immediately.
- [ ] No driveline instability (vehicle launched/flipped) — a wrong diffIndex or
      ratio is the classic symptom; check `readBaseRatios` picked real values.

---

## 3. Tire — scale wheel friction by pressure

**Engine call:** `WheelPhysics.updateTireFriction` (the function VTP overrides).
This is a **global class-method override**, installed once at load via
`Utils.overwrittenFunction`, NOT a per-vehicle call — which is exactly why it is
not in the module file yet (it must be written against the real in-game signature
and felt before it ships).

**Plan:**
1. At mod load (in `TireModule` or the loader), install:
   `WheelPhysics.updateTireFriction = Utils.overwrittenFunction(WheelPhysics.updateTireFriction, TireModule.tireFrictionOverride)`.
2. In the override: call the original first, then find the wheel's vehicle + its
   IronHorse tire state, decide front/rear axle for that wheel, and scale the
   resulting friction by `TireModule.pressureToTraction(axlePressure, CFG)`
   (and optionally fold in `contactPatch`). Guard every lookup (nil → call original
   unchanged) so non-IronHorse wheels are untouched.
3. Map wheel→axle: use the wheel's position along the vehicle Z axis (front half
   vs rear half) or the wheel's configured axle; verify against a real tractor
   in-game (this is the fiddly part — confirm which wheels count as "front").

**Inflate/deflate (input, §1):** change `state.pressureFront/Rear` within
`[CFG.MIN_BAR, CFG.MAX_BAR]`; the throttled sync + save already handle the rest.
Optional realism: consume the vehicle's `AIR` fillUnit when inflating (the Xerion
carries `<unit fillType="AIR">`), like the vanilla air reserve.

**In-game checklist (dedicated):**
- [ ] Dropping pressure measurably improves field traction; raising it improves
      road feel — matches the HUD grip %.
- [ ] The override leaves non-IronHorse / unsupported wheels exactly as vanilla.
- [ ] Pressure change on host + client both reflected; HUD (REIFEN V / REIFEN H
      bar + grip%) matches on every client; persists across a save/reload.
- [ ] Soft tyres at road speed show the WARNING colour (tyre-overheat cue).

---

## 4. After it is felt-good

Calibrate the real numbers against Michelin/Trelleborg pressure charts + feel
(`IronHorseRealData.tire`, `DrivetrainModule.CFG`), fold `wheelSlipFactor`-style
feedback into engineHealth wear (the chain's closing loop — see
`FUSION_RESEARCH.md` §6.5), then the tuning pass + the icon-atlas art pass, then
cut the next release. Until then these two stay unreleased on `main` with the rest.
