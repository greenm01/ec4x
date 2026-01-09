# Engine Architecture

Technical implementation details for the EC4X game engine.

**Audience:** Developers implementing or modifying engine systems.

## Documents

| Document | Purpose |
|----------|---------|
| [ec4x_canonical_turn_cycle.md](ec4x_canonical_turn_cycle.md) | **Authoritative turn cycle reference** - phase ordering, step timing, state transitions |
| [combat.md](combat.md) | Combat resolution - space, orbital, ground theaters |
| [construction-repair-commissioning.md](construction-repair-commissioning.md) | Ship/facility construction, repair queues, commissioning |
| [orders.md](orders.md) | Command system - submission, validation, storage, execution |
| [command_events.md](command_events.md) | Game events generated during command processing |

## Relationship to Specs

- **Specs (`docs/specs/`)**: Player-facing game rules and mechanics
- **Engine (`docs/engine/`)**: Implementation details, phase timing, data flow

When specs and engine docs conflict, update the engine doc to match specs.

## Phase Reference Notation

Cross-references use prefixes:
- **CMD1-6**: Command Phase steps
- **PRD1-9**: Production Phase steps
- **CON1-9**: Conflict Phase steps
- **INC1-9**: Income Phase steps

Example: "Commissioning occurs at CMD2" or "Combat resolves at CON1-CON5"
