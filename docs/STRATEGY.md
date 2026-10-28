# Strategy layer

ProcessLink uses four records so improvement work can be traced to the function
strategy rather than to a local hunch.

| Record | What it answers |
|---|---|
| `StrategyRecord` | What is the function vision, for which horizon, owned by whom? |
| `StrategicBetRecord` | Which few choices matter, each with one primary KPI? |
| `KPIRecord` | What is the definition, baseline, current value, target, direction, cadence and source? |
| `ValueRecord` | Which behaviours must a countermeasure respect? |

## Mandatory initiative link

Every `InitiativeRecord` carries:

- `strategicBetID`
- `kpiID`
- `valueIDs` (one or more)
- `expectedKPIChange`
- `visionContribution`

`hasStrategyLink` requires the bet, KPI, at least one value **and** a non-empty
vision contribution. Existing records are repaired once at launch with the
default rules below; new opportunities and meeting actions receive a default
link at creation.

Stage advancement, saving commitment and validation are blocked when the link
is missing. The button help says so, and the action returns to Strategy.

## Default linking rules

| Process / waste | Bet | KPI | Values |
|---|---|---|---|
| Invoice exceptions | Frictionless finance | Invoice exception rework | Right first time · Customer first |
| Case triage | Digital operations at the desk | Case handling minutes | People in the loop · Simplify before automate |
| Order intake with handoffs/context switching | Digital operations at the desk | Manual touches per order | Simplify before automate · People in the loop |
| Other order intake | Order-to-cash velocity | Order-to-cash lead time | Simplify before automate · Right first time |
| Anything else | Standard work that sticks | Standard-work adherence | Right first time · People in the loop |

A human can replace any default in **Strategy → Initiative alignment → Edit
link** or **Improvements → Strategy alignment**. A human link is never
overwritten by the repair.

## What linking does not mean

A link is traceability, not attribution. It does not prove the initiative
caused KPI movement, and it does not turn an estimate into a validated saving.
The KPI needs its own definition and measurement; the saving still needs a
named validator and before/after evidence.
