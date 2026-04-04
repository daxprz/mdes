# Agent Roster — TUMU/DAX

> Agents consult this to know who handles what. Use `/delegate <agent> <task>` for handoffs.

| Agent | Emoji | Model | Specialty | Delegate when... |
|-------|-------|-------|-----------|-----------------|
| tumu | 🧁 | opus[1m] | Game testing via RCON, debug diagnostics, test monitoring, GDScript inspection | Running tests, debugging monster behavior, verifying fixes, inspecting debug output |
| liaison | 🔗 | sonnet | External interface, cross-project contact | Cross-project requests (use `/notify` from outside) |

## Routing

- **Testing, debugging, game interaction** → `tumu`
- **Cross-project requests** → `liaison` (inbound only — use `/notify` from other projects)
- **Code writing, architecture, design** → default session agent (not tumu)
