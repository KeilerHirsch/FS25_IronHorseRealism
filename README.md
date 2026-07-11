# Iron Horse Realism (FS25)

> [!IMPORTANT]
> Enjoying the mod? You can support development on **[Ko-fi](https://ko-fi.com/keilerhirsch)** ☕ — please mention *Iron Horse Realism* so I know what to keep building.

An original, from-scratch **vehicle realism framework** for Farming Simulator 25.
It unifies what today needs several separate mods — engine health, drivetrain,
tire pressure, electrical, dirt/visuals and a field-repair toolbox — into **one
coherent drivetrain chain** with **one HUD**.

> **Foundation release (0.1.x):** the modular core only. Every feature is a
> self-contained module plugged into the core. This is the extensible base the
> rest of the mod grows on.

## Design principles

1. **Replacement, not addition** — IronHorse Realism *replaces* separate wear /
   drive-assist / tire-pressure mods and takes **technical precedence** over
   them when they are present (not just a readme warning).
2. **Real data** — all values (battery Ah/V, engine temperatures, tire pressure
   in bar, repair costs) come from real manufacturer / engineering sources, kept
   in one data module.
3. **Minimal settings** — as few knobs as possible, locked during operation, so
   players cannot misconfigure it live.
4. **Multiplayer-safe** — state is server-authoritative and synced via one
   generic event pattern.

## Architecture

```
IronHorseRealism (loader)
 └── IronHorseSpecialization  ← one vehicle specialization on all vehicle types
      └── IronHorseModuleRegistry  ← every feature is a module (init/update/save/hud/sync)
           ├── engineStall   soft-stall under overload (the 180hp-moped-vs-50t reality)
           ├── engineHealth  wear / temperature
           ├── drivetrain    diff locks, power delivery
           ├── tires         pressure → traction
           ├── electrical    battery / alternator (real Ah/V)
           ├── visualDirt    mud / dust / dirt
           └── toolbox       field repair to limp a dead vehicle to the workshop
      IronHorseRealData   single source of real values
      IronHorseHud        one unified HUD
      IronHorseSyncEvent  one server-authoritative sync pattern
      IronHorseConfig     minimal, operation-locked settings
```

Adding a feature later = **plugging in a new module**, never surgery on the core.

## Building

```
./build.sh
```

Produces a zip with `modDesc.xml` at the root (FS25 requirement).

## License

**Proprietary, source-available** — see [LICENSE](LICENSE). You may read the
source and use the released mod unmodified; you may not copy, modify, or
redistribute it. Only ModHub and this repository are valid sources.
