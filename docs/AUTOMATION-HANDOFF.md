# Automation handoff

From an initiative, **Generate handoff package** writes:

- `automation.json` — process, steps, strategic bet, KPI, values, saving and guardrails
- `README.md` — owner and scope
- `test-plan.md` — validation and rollback checks
- `agent.py` — a minimal skeleton with `requires_human: True`

The package is a scaffold. ProcessLink does not deploy code, hold production
credentials or monitor an automation. The handoff status is tracked as Draft →
Ready → In review → Deployed → Retired.
