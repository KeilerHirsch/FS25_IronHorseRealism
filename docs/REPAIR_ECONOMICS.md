# Repair economics — the real-data basis

The toolbox module's repair costs follow the mod's core principle: **real numbers,
not invented ones.** This is the research that grounds them, so the constants are
auditable and Michael can feel-tune from a real baseline in-game.

## Real-world anchors (2025)

**German ag-machinery workshop labour rates** — €70–130 / hour:
- Deutz workshops ~€75/h, BayWa Technik ~€110/h, John Deere dealers >€130/h.
- Independent shops sit lower, brand dealers higher; Verrechnungssätze often
  exceed €100/h once building, cleaning, equipment and standby surcharges are in.
- **Midpoint used: €100/h** (`IronHorseRealData.repair.workshopLaborEURperH`).

**Repair cost vs machine value:**
- Annual maintenance + repair ≈ **5–10 % of the machine's value per year**.
- **Lifetime accumulated repair cost ≈ 25 % of the new list price.**
- Labour time ≈ operating time + ~10 %.

**Field vs workshop:** a makeshift field repair is mostly the operator's own
labour + basic parts with no dealer margin, so it is cheaper per unit of damage
fixed — but only partial (it cannot fully restore the machine; the workshop does).

Sources: agrarheute (Traktor-Werkstatt Reparaturkosten), Maschinenring
Verrechnungssätze 2025, Landtreff workshop-rate threads; farmdoc/MSU/UW-Extension
tractor machinery-cost estimates.

## Derivation of the mod constants

`IronHorseRealData.repair`:

| Constant | Value | Basis |
|----------|-------|-------|
| `workshopLaborEURperH` | 100 | DE ag-workshop midpoint (70–130) |
| `workshopRepairFraction` | 0.06 | a full 0→1 workshop repair ≈ 6 % of price — a heavy repair event inside the 5–10 %/yr band; lifetime ~25 % ≈ four such events |
| `fieldRepairCostRatio` | 0.45 | a field repair ≈ 45 % of the workshop cost for the same damage delta (own labour, basic parts, no margin) |

`ToolboxModule.CFG` derives from these (no magic numbers):
- `WORKSHOP_REPAIR_FRACTION = 0.06`
- `FIELD_COST_FACTOR = 0.06 × 0.45 = 0.027`

## Worked example (a €150 000 tractor at 90 % damage)

- Field repair removes 0.35 damage (→ 0.55), cost = `0.35 × 150 000 × 0.027 ≈ €1 420`.
- Full workshop repair of that same 0.35 chunk = `0.35 × 150 000 × 0.06 ≈ €3 150`.
- Field ≈ 45 % of the workshop cost — meaningful money, but the cheaper "limp it
  along" option, exactly the intended trade-off.

## Still to tune in-game (the settings, not the prices)

The **prices** are now grounded. The **gameplay settings** — how much damage one
field repair removes (`FIELD_REPAIR_AMOUNT` 0.35), the floor it can't beat
(`FIELD_REPAIR_FLOOR` 0.15 = 85 % condition), and whether the numbers *feel* right
against FS25's own economy — are Michael's in-game calibration, together with
wiring the actual repair action (input → `setDamageAmount` + `addMoney`). See
`docs/INGAME_PHYSICS_PLAN.md` for the action-wiring + the security rules on never
trusting a client-sent damage/price.
