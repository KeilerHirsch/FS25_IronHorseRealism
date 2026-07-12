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

The active cost formula **reuses FS25's own repair curve** so costs feel native to
the game economy — and the game's 9 % coincidentally sits inside the real-world
band, so the native number is also the realistic one:

> FS25 `Wearable.calculateRepairPrice(price, damage) = price × damage^1.5 × 0.09`

`IronHorseRealData.repair`:

| Constant | Value | Basis |
|----------|-------|-------|
| `workshopLaborEURperH` | 100 | real DE ag-workshop midpoint (70–130) — context/sanity |
| `lifetimeRepairFraction` | 0.25 | real: lifetime repair ≈ 25 % of list price — context |
| `fullRepairFraction` | 0.09 | FS25's own: up to 9 % of price at full damage |
| `repairExponent` | 1.5 | FS25's own: rewards frequent low-damage repairs |
| `fieldRepairCostRatio` | 0.45 | a field repair ≈ 45 % of the workshop's marginal cost |

- `workshopRepairCost(damage) = price × damage^1.5 × 0.09` (= FS25's own price).
- `fieldRepairCost(damage) = 0.45 × [workshopRepairCost(damage) − workshopRepairCost(afterRepair)]`
  — a discount on the marginal cost of just the chunk the field repair removes.

## Worked example (a €150 000 tractor at 90 % damage)

- Field repair removes 0.35 damage: 0.90 → 0.55.
- Workshop cost at 0.90 = `150 000 × 0.90^1.5 × 0.09 ≈ €11 530`; at 0.55 ≈ €5 510.
- Marginal (the 0.90→0.55 chunk) ≈ €6 020; **field cost = 0.45 × 6 020 ≈ €2 710**.
- A full workshop repair (0.90→0) would be ≈ €11 530. The field repair is the
  cheaper, partial "limp it along" option — priced in the game's own currency of
  repair, exactly the intended trade-off.

## Still to tune in-game (the feel, not the prices)

The action is **wired** (Shift+R → a server-authoritative repair + charge; the
server reads damage + price itself, never a client value). The **prices** are
grounded in FS25's own curve. What remains is feel: the key choice, the cost
against FS25's economy in practice, and the gameplay settings — how much one field
repair removes (`FIELD_REPAIR_AMOUNT` 0.35) and the floor it can't beat
(`FIELD_REPAIR_FLOOR` 0.15 = 85 % condition). MP correctness (client press → server
applies → every client sees the lower damage + the charge) is Michael's
dedicated-server test. The money-path security rules are enforced in code and
noted in `docs/INGAME_PHYSICS_PLAN.md`.
