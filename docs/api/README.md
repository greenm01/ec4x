# EC4X API Documentation

Complete API reference documentation generated from source code using Nim's nimdoc tool.

## Structure

```
docs/api/
├── engine/           # Engine module documentation
│   ├── index.html   # Main navigation page
│   ├── core.html    # Core types (HouseId, SystemId, etc.)
│   ├── units.html   # Ship classes and weapon systems
│   ├── planets.html # Planet classification and resources
│   ├── combat.html  # Combat mechanics and TaskForce
│   ├── ship.html    # Individual ship representation
│   ├── squadron.html # Combat squadrons with CR/CC
│   ├── spacelift.html # Spacelift ships (ETAC, TroopTransport)
│   ├── fleet.html   # Fleet management
│   ├── gamestate.html # Game state and colonies
│   ├── starmap.html # Star systems and jump lanes
│   └── theindex.html # Full symbol index
└── generate_docs.sh # Documentation generation script
```

## Viewing Documentation

Open `docs/api/engine/index.html` in your web browser:

```bash
firefox docs/api/engine/index.html
# or
xdg-open docs/api/engine/index.html
```

## Regenerating Documentation

To regenerate all documentation:

```bash
cd docs/api
./generate_docs.sh
```

To regenerate a specific module:

```bash
./generate_docs.sh /path/to/module.nim
```

## Key Architecture Concepts

### Construction and Commissioning

**Ship Construction Pipeline:**

1. **BuildOrder** → Submit via OrderPacket with:
   - `buildType: BuildType.Ship` (Ship, Building, or Infrastructure)
   - `quantity: int` - Number of units to build
   - `shipClass: Option[ShipClass]` - For ships
   - `buildingType: Option[string]` - For buildings ("Spaceport", "Shipyard", "Starbase", "GroundBattery", "FighterSquadron")
   - `industrialUnits: int` - For infrastructure

2. **ConstructionProject** → Created in colony:
   - `projectType: ConstructionType` (Ship, Building, Infrastructure)
   - `itemId: string` - Ship type or building name
   - `costTotal: int` - Total PP cost
   - `costPaid: int` - PP already invested
   - `turnsRemaining: int` - Estimated completion

3. **Commissioning** → Ship completion:
   - Ships go to `colony.unassignedSquadrons[]`
   - Spacelift ships go to `colony.unassignedSpaceLiftShips[]`
   - Can be manually assigned to fleets or auto-assigned

**Construction Functions:**
- `createShipProject(shipClass: ShipClass): ConstructionProject`
- `createBuildingProject(buildingType: string): ConstructionProject`
- `getShipConstructionCost(shipClass: ShipClass): int`
- `getShipBuildTime(shipClass: ShipClass, cstLevel: int): int`
- `getBuildingCost(buildingType: string): int`
- `getBuildingTime(buildingType: string): int`

### Squadron Management

**Squadron Management Actions:**

Via `SquadronManagementOrder` in OrderPacket:

1. **TransferShip** - Move ship between squadrons at colony:
   - `sourceSquadronId: Option[string]`
   - `targetSquadronId: Option[string]`
   - `shipIndex: Option[int]` - Index in source squadron's ships array

2. **AssignToFleet** - Assign squadron to fleet:
   - `squadronId: Option[string]` - Squadron to assign
   - `targetFleetId: Option[FleetId]` - none() creates new fleet

**Squadron API:**
- `newSquadron(flagship: EnhancedShip, id, owner, location): Squadron`
- `addShip(sq: var Squadron, ship: EnhancedShip): bool`
- `removeShip(sq: var Squadron, index: int): Option[EnhancedShip]`
- `combatStrength(sq: Squadron): int` - Total AS (flagship + all ships)
- `defenseStrength(sq: Squadron): int` - Total DS (flagship + all ships)
- `allShips(sq: Squadron): seq[EnhancedShip]` - Flagship + escorts

**Fleet Organization:**
- Fleet contains `squadrons: seq[Squadron]` and `spaceLiftShips: seq[SpaceLiftShip]`
- Fleet status: Active, Reserve, Mothballed
- Squadrons can be moved between fleets via squadron management orders
- Auto-assignment: colonies with `autoAssignFleets: true` automatically create fleets for unassigned squadrons

**OrderPacket Structure:**

All orders require proper initialization:
```nim
OrderPacket(
  houseId: "house1",
  turn: 1,
  buildOrders: @[...],
  fleetOrders: @[...],
  researchAllocation: initResearchAllocation(),  # NOT default()
  diplomaticActions: @[...],
  populationTransfers: @[...],
  squadronManagement: @[...],
  cargoManagement: @[...],
  terraformOrders: @[...],
  espionageAction: none(esp_types.EspionageAttempt),  # NOT none(type(...))
  ebpInvestment: 0,
  cipInvestment: 0
)
```

### Spacelift Command Ships

**CRITICAL:** Spacelift ships (ETAC, TroopTransport) are **individual units** NOT squadrons.

- Per operations.md:1036, spacelift ships are "individual units within the fleet"
- They travel with fleets but are separate from combat squadrons
- Screened during space combat (phase 1) and starbase assault (phase 2)
- Participate in ground combat (phase 3) where they can be destroyed

**Architecture:**
```
Fleet → Squadrons (combat) + SpaceLiftShips (transport/colonization)
```

See `spacelift.html` for complete API reference.

### Combat Squadrons

Tactical units with Command Rating (CR) and Command Cost (CC):

- Squadron = Flagship + Escorts (0-11 ships)
- CR determines tactical effectiveness
- Squadrons fight as cohesive units during combat

See `squadron.html` for complete API reference.

### Task Forces

Temporary combat formations created when fleets converge:

- All house fleets in a system disband into squadrons
- Squadrons fight individually (not as fleets)
- Spacelift ships are screened behind the task force
- Per operations.md:281-288

See `combat.html` for TaskForce API reference.

## Documentation Quality

All documentation is generated directly from source code comments using:

```nim
## Module-level documentation (double ##)
## Explains purpose and architecture

proc functionName*(...): ReturnType =
  ## Function documentation
  ## Explains parameters and return values
```

The documentation reflects the actual implementation and is automatically kept in sync with code changes.

## Adding Documentation for New Modules

1. Ensure module has proper doc comments (`##` for exports)
2. Add module to `generate_docs.sh` in appropriate section
3. Update `engine/index.html` with new module card
4. Regenerate documentation

## Benefits for Development

1. **Reduced Context Switching**: API reference available without reading source
2. **Type Discovery**: Find correct enum values (PlanetClass, ResourceRating, etc.)
3. **Architecture Clarity**: Understand module relationships and data flow
4. **Compilation Error Prevention**: Verify types before writing code
5. **Onboarding**: New developers can quickly understand the codebase

## Related Documentation

- `/docs/specs/` - Game specification and rules
- `/docs/design/` - Design documents and architecture
- `/balance_results/` - AI testing results and gap analysis
