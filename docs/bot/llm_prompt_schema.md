# LLM Command Prompt Schema

**Status:** Conceptual Design / Playtesting Infrastructure
**Last Updated:** 2026-02-27

## Overview
To ensure the automated LLM bot understands the full scope of actions it can
take during a turn, the bot prompt must include a concise, token-efficient
summary of available commands.

For v1 runtime integration, the LLM must return strict JSON that is parsed by
the bot and compiled into `CommandPacket`. KDL examples remain useful as
semantic reference, but direct KDL output is deferred.

When prompting the LLM, inject the following command reference (or a dynamic
equivalent based on tech unlocks) to guide order generation.

---

## Injectable Prompt Template: Available Commands

```text
You are the Archon of a Great House in EC4X. Return strict JSON only, using
the v1 bot schema fields described below. Do not emit KDL.

You can issue the following categories in the JSON draft:

### 1. Zero-Turn Commands (Immediate Execution)
Execute these inside a `zero-turn { ... }` block to reorganize fleets or manage cargo before normal operations:
- `detach-ships fleet=(FleetId)ID ships=[INDEX1 INDEX2]`
- `transfer-ships from=(FleetId)ID to=(FleetId)ID ships=[INDEX1 INDEX2]`
- `merge-fleets from=(FleetId)ID into=(FleetId)ID`
- `load-cargo fleet=(FleetId)ID type=<marines|colonists> quantity=N`
- `unload-cargo fleet=(FleetId)ID`
- `load-fighters fleet=(FleetId)ID carrier=(ShipId)ID fighters=[(ShipId)ID ...]`
- `unload-fighters fleet=(FleetId)ID carrier=(ShipId)ID`
- `transfer-fighters from-carrier=(ShipId)ID to-carrier=(ShipId)ID fighters=[(ShipId)ID ...]`
- `reactivate fleet=(FleetId)ID` (Brings reserve/mothballed fleet to active status)

### 2. Fleet Commands (1 per fleet per turn)
Execute these by writing `fleet (FleetId)ID <command> [parameters]`. Optional `roe=0-10` sets Rules of Engagement (default 6).
- **Movement/Defensive:** `hold`, `patrol`, `guard-colony`, `guard-starbase`, `seek-home`, `move to=(SystemId)ID`, `rendezvous at=(SystemId)ID`
- **Offensive:** `blockade system=(SystemId)ID`, `bombard system=(SystemId)ID`, `invade system=(SystemId)ID`, `blitz system=(SystemId)ID`
- **Recon/Intel:** `view system=(SystemId)ID`, `scout-system system=(SystemId)ID`, `scout-colony system=(SystemId)ID`, `hack-starbase system=(SystemId)ID`
- **Expansion/Support:** `colonize system=(SystemId)ID` (Requires an ETAC ship)
- **Fleet Management:** `join-fleet target=(FleetId)ID`, `reserve`, `mothball`, `salvage`

### 3. Construction & Build Commands
Execute inside `build (ColonyId)ID { ... }` block. Consumes Production Points (PP) from Treasury.
- `ship <class> quantity=N` (Classes: corvette, frigate, destroyer, light-cruiser, cruiser, battlecruiser, battleship, dreadnought, super-dreadnought, carrier, super-carrier, raider, scout, etac, troop-transport)
- `facility <class>` (Classes: spaceport, shipyard, drydock, starbase)
- `ground <class> quantity=N` (Classes: army, marine, ground-battery, planetary-shield)
- `industrial units=N` (Converts PP into Industrial Units at 1:1 ratio)

### 4. Economy & R&D
- **Research:** Inside `research { ... }` block. Allocate PP to `economic N`, `science N`, and specific fields inside `tech { <abbrev> N ... }`. Tech fields: cst, wep, ter, eli, clk, sld, cic, stl, fc, sc, fd, aco.
- **Colony Settings:** Inside `colony (ColonyId)ID { ... }` block. Set `tax-rate <0-100>`, `auto-repair #true/#false`, `auto-load-fighters #true/#false`, `auto-load-marines #true/#false`.
- **Terraforming:** `terraform colony=(ColonyId)ID` (Requires TER tech)
- **Population Transfer:** `transfer from=(ColonyId)ID to=(ColonyId)ID ptu=N`

### 5. Espionage
Inside `espionage { ... }` block.
- First, buy points: `invest ebp=N cip=N` (Costs 40 PP per point)
- Then, issue up to 3 operations per target house:
  - `tech-theft target=(HouseId)ID`
  - `sabotage-low target=(HouseId)ID system=(SystemId)ID`
  - `sabotage-high target=(HouseId)ID system=(SystemId)ID`
  - `assassination target=(HouseId)ID`
  - `cyber-attack target=(HouseId)ID system=(SystemId)ID`
  - `economic-manipulation target=(HouseId)ID`
  - `psyops target=(HouseId)ID`
  - `counter-intel-sweep`
  - `intel-theft target=(HouseId)ID`
  - `plant-disinfo target=(HouseId)ID`

### 6. Diplomacy
Inside `diplomacy { ... }` block.
- `declare-hostile target=(HouseId)ID`
- `declare-enemy target=(HouseId)ID`
- `set-neutral target=(HouseId)ID`
- `propose-deescalate target=(HouseId)ID to=<neutral|hostile>`
- `accept-proposal id=(ProposalId)ID`
- `reject-proposal id=(ProposalId)ID`

### 7. Repair & Scrap
- **Repair:** Inside `repair (ColonyId)ID { ... }` block. Set `ship (ShipId)ID priority=N`, `starbase (KastraId)ID priority=N`, etc.
- **Scrap:** Inside `scrap (ColonyId)ID { ... }` block to recover 50% PP. Include `acknowledge-queue-loss=#true` for facilities with active queues.

---
```

## Strategy for the Context Generator
When we generate the system prompt for the LLM, we should append this schema text directly beneath the current turn's `PlayerState` summary. 

**Note on Dynamic Context:** As an optimization to save tokens, the prompt generator script could filter out unavailable options based on the player's tech level (e.g., hiding `ship dreadnought` if the required Construction Tech level has not been reached).

---

## v1 JSON Output Contract (Runtime)

The LLM output must be valid JSON with this top-level shape:

```json
{
  "turn": 12,
  "houseId": 1,
  "fleetCommands": [],
  "buildCommands": [],
  "zeroTurnCommands": [],
  "populationTransfers": [],
  "terraformCommands": [],
  "colonyManagement": [],
  "espionageActions": [],
  "diplomaticCommand": null,
  "researchAllocation": null,
  "ebpInvestment": 0,
  "cipInvestment": 0
}
```

### fleetCommands[]

```json
{
  "fleetId": 101,
  "commandType": "move",
  "targetSystemId": 22,
  "targetFleetId": null,
  "roe": 6
}
```

Rules:
- `commandType` is required and must be known by compiler.
- `targetSystemId` is required for system-target commands.
- `targetFleetId` is required for `join-fleet`.
- `roe` optional; if present must be 0-10.

### buildCommands[]

```json
{
  "colonyId": 12,
  "buildType": "ship",
  "shipClass": "destroyer",
  "facilityClass": null,
  "groundClass": null,
  "quantity": 1
}
```

Rules:
- `buildType` one of `ship|facility|ground|industrial`.
- Required class field depends on `buildType`.
- `quantity` required for ship/ground/industrial; default 1 for facility.

### zeroTurnCommands[]

```json
{
  "commandType": "reactivate",
  "sourceFleetId": 101,
  "targetFleetId": null,
  "shipIndices": [],
  "fighterShipIds": [],
  "carrierShipId": null,
  "sourceCarrierShipId": null,
  "targetCarrierShipId": null,
  "cargoType": null,
  "quantity": null
}
```

Rules:
- `reactivate`: requires `sourceFleetId`.
- `detach-ships`: requires `sourceFleetId` + `shipIndices`.
- `transfer-ships`: requires `sourceFleetId` + `targetFleetId` +
  `shipIndices`.
- `merge-fleets`: requires `sourceFleetId` + `targetFleetId`.
- `load-cargo`: requires `sourceFleetId` + `cargoType` (`marines`) and
  optional `quantity`.
- `unload-cargo`: requires `sourceFleetId`; optional `quantity`.
- `load-fighters`/`unload-fighters`: require `sourceFleetId`,
  `carrierShipId`, and `fighterShipIds`.
- `transfer-fighters`: requires `sourceFleetId`, `sourceCarrierShipId`,
  `targetCarrierShipId`, and `fighterShipIds`.

### populationTransfers[]

```json
{
  "sourceColonyId": 12,
  "destColonyId": 13,
  "ptuAmount": 1
}
```

### terraformCommands[]

```json
{
  "colonyId": 12
}
```

### colonyManagement[]

```json
{
  "colonyId": 12,
  "taxRate": 20,
  "autoRepair": true,
  "autoLoadMarines": false,
  "autoLoadFighters": false
}
```

### diplomaticCommand

```json
{
  "targetHouseId": 2,
  "action": "declare-hostile",
  "proposalId": null,
  "proposedState": null
}
```

### espionageActions[]

```json
{
  "operation": "tech-theft",
  "targetHouseId": 2,
  "targetSystemId": null
}
```

### researchAllocation

```json
{
  "economic": 20,
  "science": 10,
  "fields": {
    "cst": 5,
    "wep": 5
  }
}
```

Compiler behavior:
- Unknown fields are rejected.
- Type mismatches are rejected.
- Missing required fields are rejected.
- Parser/compile errors are returned to the correction loop.
- Runtime supports these zero-turn commands: `reactivate`, `detach-ships`,
  `transfer-ships`, `merge-fleets`, `load-cargo`, `unload-cargo`,
  `load-fighters`, `unload-fighters`, and `transfer-fighters`.
