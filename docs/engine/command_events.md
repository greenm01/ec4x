# Fleet Command Game Events Reference

**Purpose**: Reference for fleet command lifecycle events and their generation points.

**Last Updated**: 2026-01-09

---

## Event Factory Functions

**Location**: `src/engine/resolution/event_factory/orders.nim`

**Functions**:
- `commandIssued()` - Command submitted and stored
- `commandFailed()` - Validation failure
- `commandAborted()` - Mid-execution cancellation (conditions changed)
- `commandCompleted()` - Command successfully completed

---

## Fleet Command Event Matrix

| Cmd | Command Name   | Event Type       | Phase      | Code Module                     |
|-----|----------------|------------------|------------|---------------------------------|
| 00  | Hold           | CommandIssued    | Command    | fleet_order_execution:193       |
| 01  | Move           | CommandIssued    | Command    | fleet_order_execution:193       |
| 01  | Move           | CommandCompleted | Production | fleet_orders:276                |
| 02  | SeekHome       | CommandIssued    | Command    | fleet_order_execution:193       |
| 02  | SeekHome       | CommandAborted   | Production | executor:194                    |
| 02  | SeekHome       | CommandCompleted | Production | executor:217                    |
| 03  | Patrol         | CommandIssued    | Command    | fleet_order_execution:193       |
| 03  | Patrol         | CommandFailed    | Production | executor:257                    |
| 03  | Patrol         | CommandAborted   | Production | executor:272                    |
| 04  | GuardStarbase  | CommandIssued    | Command    | fleet_order_execution:193       |
| 04  | GuardStarbase  | CommandFailed    | Production | executor:300,317                |
| 04  | GuardStarbase  | CommandAborted   | Production | executor:330,341,351            |
| 05  | GuardColony    | CommandIssued    | Command    | fleet_order_execution:193       |
| 05  | GuardColony    | CommandFailed    | Production | executor:378,397                |
| 05  | GuardColony    | CommandAborted   | Production | executor:410                    |
| 06  | Blockade       | CommandIssued    | Command    | fleet_order_execution:193       |
| 06  | Blockade       | CommandFailed    | Production | executor:434,453                |
| 06  | Blockade       | CommandAborted   | Production | executor:464,475,488            |
| 07  | Bombard        | CommandIssued    | Command    | fleet_order_execution:193       |
| 07  | Bombard        | CommandFailed    | Conflict   | combat_resolution:893+          |
| 07  | Bombard        | CommandAborted   | Production | fleet_order_execution:248       |
| 07  | Bombard        | CommandCompleted | Conflict   | combat_resolution:1072          |
| 08  | Invade         | CommandIssued    | Command    | fleet_order_execution:193       |
| 08  | Invade         | CommandFailed    | Conflict   | combat_resolution:1121+         |
| 08  | Invade         | CommandAborted   | Production | fleet_order_execution:248       |
| 08  | Invade         | CommandCompleted | Conflict   | combat_resolution:1327          |
| 09  | Blitz          | CommandIssued    | Command    | fleet_order_execution:193       |
| 09  | Blitz          | CommandFailed    | Conflict   | combat_resolution:1413+         |
| 09  | Blitz          | CommandAborted   | Production | fleet_order_execution:248       |
| 09  | Blitz          | CommandCompleted | Conflict   | combat_resolution:1615          |
| 10  | Colonize       | CommandIssued    | Command    | fleet_order_execution:193       |
| 10  | Colonize       | CommandFailed    | Conflict   | simultaneous:382,448,492        |
| 10  | Colonize       | CommandAborted   | Production | fleet_order_execution:248       |
| 10  | Colonize       | CommandCompleted | Conflict   | simultaneous:184                |
| 11  | ScoutColony    | CommandIssued    | Command    | fleet_order_execution:193       |
| 11  | ScoutColony    | CommandFailed    | Production | executor:670,687,711            |
| 11  | ScoutColony    | CommandAborted   | Conflict   | spy_travel:147                  |
| 11  | ScoutColony    | CommandCompleted | Production | executor:745                    |
| 12  | ScoutSystem    | CommandIssued    | Command    | fleet_order_execution:193       |
| 12  | ScoutSystem    | CommandFailed    | Production | executor:912,929,951            |
| 12  | ScoutSystem    | CommandAborted   | Conflict   | spy_travel:147                  |
| 12  | ScoutSystem    | CommandCompleted | Production | executor:986                    |
| 13  | HackStarbase   | CommandIssued    | Command    | fleet_order_execution:193       |
| 13  | HackStarbase   | CommandFailed    | Production | executor:782,795,806,819,841    |
| 13  | HackStarbase   | CommandAborted   | Conflict   | spy_travel:164                  |
| 13  | HackStarbase   | CommandCompleted | Production | executor:878                    |
| 14  | JoinFleet      | CommandIssued    | Command    | fleet_order_execution:193       |
| 14  | JoinFleet      | CommandFailed    | Production | executor:986,1004,1015,1069     |
| 14  | JoinFleet      | CommandAborted   | Production | executor:1055,1100              |
| 14  | JoinFleet      | CommandCompleted | Production | executor:1224                   |
| 15  | Rendezvous     | CommandIssued    | Command    | fleet_order_execution:193       |
| 15  | Rendezvous     | CommandFailed    | Production | executor:1257                   |
| 15  | Rendezvous     | CommandAborted   | Production | executor:1276,1292              |
| 15  | Rendezvous     | CommandCompleted | Production | executor:1387                   |
| 16  | Salvage        | CommandIssued    | Command    | fleet_order_execution:193       |
| 16  | Salvage        | CommandFailed    | Income     | executor:1456                   |
| 16  | Salvage        | CommandCompleted | Income     | executor:1506                   |
| 17  | Reserve        | CommandIssued    | Command    | fleet_order_execution:193       |
| 17  | Reserve        | CommandFailed    | Production | executor:1571                   |
| 17  | Reserve        | CommandCompleted | Production | executor:1592                   |
| 18  | Mothball       | CommandIssued    | Command    | fleet_order_execution:193       |
| 18  | Mothball       | CommandFailed    | Production | executor:1630                   |
| 18  | Mothball       | CommandCompleted | Production | executor:1688                   |
| 19  | Reactivate     | CommandIssued    | Command    | fleet_order_execution:193       |
| 19  | Reactivate     | CommandFailed    | Production | executor:1722                   |
| 19  | Reactivate     | CommandCompleted | Production | executor:1751                   |
| 20  | View           | CommandIssued    | Command    | fleet_order_execution:193       |
| 20  | View           | CommandFailed    | Production | executor:1705                   |
| 20  | View           | CommandCompleted | Production | fleet_orders:599                |

---

## Event Summary

**By Event Type**:
- CommandIssued: 21 (all commands)
- CommandFailed: 21 (validation failures)
- CommandAborted: 19 (condition changes, targets lost)
- CommandCompleted: 23 (successful completion)

---

## Command Categories

### Persistent Commands
Execute every turn until overridden:
- Hold, Patrol, GuardStarbase, GuardColony, Blockade

CommandCompleted fires only on FIRST successful execution (prevents event spam).

### One-Shot Commands
Execute once, then clear:
- Move, SeekHome, Colonize, Salvage, JoinFleet, Rendezvous

CommandCompleted fires when effect occurs.

### Immediate Commands
Take effect instantly during Command Phase:
- Reserve, Mothball, Reactivate

CommandCompleted fires immediately on status change.

---

## CommandAborted Triggers

Commands abort when conditions change:
- Target system changes ownership (combat commands)
- Target fleet destroyed/moved (JoinFleet, Rendezvous)
- Target colony lost (GuardColony, Blockade, scout commands)
- Target starbase destroyed (GuardStarbase, HackStarbase)
- Colonization capability lost (ships crippled/destroyed)
- Hostile forces present at rendezvous point
- Target house eliminated (scout commands)

---

## Related Documentation

- **Event Factory**: `src/engine/resolution/event_factory/orders.nim`
- **Turn Cycle**: `docs/engine/ec4x_canonical_turn_cycle.md`
- **Fleet Commands**: `docs/specs/06-operations.md`
