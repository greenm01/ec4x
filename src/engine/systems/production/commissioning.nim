## Commissioning System - Converting completed construction into operational units
##
## This module handles the commissioning of completed construction projects into
## operational military units and facilities. It runs as the FIRST step in the
## Command Phase, before new build orders are processed.
##
## **Design Rationale:**
## Commissioning must occur before build orders to ensure clean capacity calculations.
## When a shipyard completes a destroyer, that dock space becomes available for new
## construction orders submitted the same turn. By commissioning first, we eliminate
## temporal paradoxes where dock availability is ambiguous.
##
## **Phase Ordering (Updated 2025-12-04):**
## ```
## Maintenance Phase:
##   - Advance construction queues (facility + colony)
##   - Return completed projects
##
## (Turn boundary - game state persisted)
##
## Command Phase:
##   1. Commission completed projects ← THIS MODULE
##   2. Auto-load fighters to carriers (if enabled)
##   3. Process new build orders
##   4. ... rest of Command Phase ...
## ```
##
## **Handles:**
## - Fighter squadrons → colony.fighterSquadrons
## - Starbases → colony.starbases
## - Spaceports/Shipyards → colony facilities
## - Ground units (Marines/Armies) → colony forces
## - Ground defenses (batteries/shields) → colony defenses
## - Capital ships → squadrons → fleets
## - Spacelift ships (ETAC/Transports) → fleets
##
## **Does NOT Handle:**
## - Auto-loading fighters to carriers (separate function)
## - Auto-balancing squadrons to fleets (happens at end of Command Phase)
## - Construction queue advancement (happens in Maintenance Phase)

import std/[tables, options, strformat, strutils]
import ../../common/types/[core, units]
import ../gamestate, ../fleet, ../squadron, ../logger
import ../economy/types as econ_types
import ./types as res_types
import ./event_factory/init as event_factory
import ../ship/entity as ship_entity  # Ship construction and helpers

# Import config access
import ../config/ground_units_config
import ../config/facilities_config
import ../config/military_config
import ../config/population_config  # For minViablePopulation
import ../research/effects  # CST dock capacity scaling

# Helper functions from gamestate
proc getOperationalStarbaseCount*(colony: Colony): int =
  ## Count non-crippled starbases
  result = 0
  for sb in colony.starbases:
    if not sb.isCrippled:
      result += 1

proc getStarbaseGrowthBonus*(colony: Colony): float =
  ## Calculate growth bonus from operational starbases
  ## Per specs: Each operational starbase provides growth bonus
  let operationalCount = getOperationalStarbaseCount(colony)
  result = operationalCount.float * 0.05  # 5% per starbase

proc getShieldBlockChance*(shieldLevel: int): float =
  ## Calculate block chance for planetary shield level
  ## SLD1=10%, SLD2=20%, ..., SLD6=60%
  result = shieldLevel.float * 0.10

proc getTotalGroundDefense*(colony: Colony): int =
  ## Calculate total ground defense strength
  result = colony.groundBatteries * 10  # Each battery = 10 defense

proc getTotalConstructionDocks*(colony: Colony): int =
  ## Calculate total construction dock capacity (uses pre-calculated effectiveDocks)
  result = 0
  for sp in colony.spaceports:
    result += sp.effectiveDocks
  for sy in colony.shipyards:
    if not sy.isCrippled:
      result += sy.effectiveDocks

proc hasSpaceport*(colony: Colony): bool =
  ## Check if colony has at least one operational spaceport
  result = colony.spaceports.len > 0

proc commissionPlanetaryDefense*(
  state: var GameState,
  completedProjects: seq[econ_types.CompletedProject],
  events: var seq[res_types.GameEvent]
) =
  ## Commission planetary defense assets in Maintenance Phase (same turn)
  ##
  ## This function runs during Maintenance Phase, BEFORE next turn's Conflict Phase.
  ## Converts completed planetary projects into operational defenses:
  ## - Fighters → colony.fighterSquadrons (planetside construction)
  ## - Starbases → colony.starbases (orbital defense)
  ## - Facilities → colony.spaceports/shipyards/drydocks
  ## - Ground defenses → colony.groundBatteries/planetaryShieldLevel
  ## - Ground forces → colony.marines/armies
  ##
  ## **Strategic Rationale:** Planetary assets commission immediately so defenders
  ## can respond to threats arriving next turn's Conflict Phase.
  ##
  ## **Called From:** resolveMaintenancePhase() in phases/maintenance_phase.nim
  ## **Called After:** Construction queue advancement
  ## **Called Before:** Turn boundary (military units commission next turn)

  # Use same modified colonies pattern as original function
  var modifiedColonies = initTable[SystemId, Colony]()

  template getColony(colId: SystemId): Colony =
    if colId in modifiedColonies:
      modifiedColonies[colId]
    else:
      state.colonies[colId]

  template saveColony(colId: SystemId, col: Colony) =
    modifiedColonies[colId] = col

  for completed in completedProjects:
    logInfo(LogCategory.lcEconomy, &"Commissioning planetary defense: {completed.projectType} itemId={completed.itemId} at system-{completed.colonyId}")

    # Special handling for fighter squadrons (12 fighters per squadron)
    if (completed.projectType == econ_types.ConstructionType.Building and
        completed.itemId == "FighterSquadron") or
       (completed.projectType == econ_types.ConstructionType.Ship and
        completed.itemId == "Fighter"):
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)
        let house = state.houses[colony.owner]

        # Create fighter ship using new DoD pattern
        let fighterShip = ship_entity.newShip(
          ShipClass.Fighter,
          house.techTree.levels.weaponsTech
        )

        # Find incomplete squadron (< 12 fighters) or create new squadron
        var incompleteSquadronIdx = -1
        for i in 0..<colony.fighterSquadrons.len:
          let sq = colony.fighterSquadrons[i]
          let totalFighters = 1 + sq.ships.len  # flagship + escorts
          if totalFighters < 12:
            incompleteSquadronIdx = i
            break

        if incompleteSquadronIdx >= 0:
          # Add to existing squadron
          colony.fighterSquadrons[incompleteSquadronIdx].ships.add(fighterShip)
          let totalNow = 1 + colony.fighterSquadrons[incompleteSquadronIdx].ships.len
          logInfo(LogCategory.lcEconomy,
            &"Added fighter to squadron {colony.fighterSquadrons[incompleteSquadronIdx].id} " &
            &"at {completed.colonyId} ({totalNow}/12)")
        else:
          # Create new squadron with this fighter as flagship
          let newSquadron = Squadron(
            id: $completed.colonyId & "-FS-" & $(colony.fighterSquadrons.len + 1),
            flagship: fighterShip,
            ships: @[],  # Will accumulate 11 more fighters
            owner: colony.owner,
            location: completed.colonyId,
            destroyed: false,
            squadronType: SquadronType.Fighter,
            embarkedFighters: @[]
          )
          colony.fighterSquadrons.add(newSquadron)
          logInfo(LogCategory.lcEconomy,
            &"Commissioned new Fighter squadron {newSquadron.id} at {completed.colonyId} (1/12)")

        saveColony(completed.colonyId, colony)

        # Generate event
        events.add(event_factory.shipCommissioned(
          colony.owner,
          ShipClass.Fighter,
          completed.colonyId
        ))

    # Special handling for starbases
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Starbase":
      # Commission starbase at colony
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)

        # Create new starbase
        let starbase = Starbase(
          id: $completed.colonyId & "-SB-" & $(colony.starbases.len + 1),
          commissionedTurn: state.turn,
          isCrippled: false
        )

        colony.starbases.add(starbase)
        saveColony(completed.colonyId, colony)

        logInfo(LogCategory.lcEconomy,
          &"Commissioned starbase {starbase.id} at {completed.colonyId} " &
          &"(Total operational: {getOperationalStarbaseCount(colony)}, " &
          &"Growth bonus: {int(getStarbaseGrowthBonus(colony) * 100.0)}%)")

        # Generate event
        events.add(event_factory.buildingCompleted(
          colony.owner,
          "Starbase",
          completed.colonyId
        ))

    # Special handling for spaceports
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Spaceport":
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)

        # Create new spaceport (docks from facilities_config.toml, scaled by CST)
        let baseDocks = globalFacilitiesConfig.spaceport.docks
        let cstLevel = state.houses[colony.owner].techTree.levels.constructionTech
        let effectiveDocks = effects.calculateEffectiveDocks(baseDocks, cstLevel)

        let spaceport = Spaceport(
          id: $completed.colonyId & "-SP-" & $(colony.spaceports.len + 1),
          commissionedTurn: state.turn,
          baseDocks: baseDocks,
          effectiveDocks: effectiveDocks,
          constructionQueue: @[],
          activeConstructions: @[]
        )

        colony.spaceports.add(spaceport)
        saveColony(completed.colonyId, colony)

        logInfo(LogCategory.lcEconomy,
          &"Commissioned spaceport {spaceport.id} at {completed.colonyId} " &
          &"(Total construction docks: {getTotalConstructionDocks(colony)})")

        events.add(event_factory.buildingCompleted(
          colony.owner,
          "Spaceport",
          completed.colonyId
        ))

    # Special handling for shipyards
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Shipyard":
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)

        # Validate spaceport prerequisite
        if not hasSpaceport(colony):
          logError(LogCategory.lcEconomy, &"Shipyard construction failed - no spaceport at {completed.colonyId}")
          # This shouldn't happen if build validation worked correctly
          continue

        # Create new shipyard (docks from facilities_config.toml, scaled by CST)
        let baseDocks = globalFacilitiesConfig.shipyard.docks
        let cstLevel = state.houses[colony.owner].techTree.levels.constructionTech
        let effectiveDocks = effects.calculateEffectiveDocks(baseDocks, cstLevel)

        let shipyard = Shipyard(
          id: $completed.colonyId & "-SY-" & $(colony.shipyards.len + 1),
          commissionedTurn: state.turn,
          baseDocks: baseDocks,
          effectiveDocks: effectiveDocks,
          isCrippled: false,
          constructionQueue: @[],
          activeConstructions: @[]
        )

        colony.shipyards.add(shipyard)
        saveColony(completed.colonyId, colony)

        logInfo(LogCategory.lcEconomy,
          &"Commissioned shipyard {shipyard.id} at {completed.colonyId} " &
          &"(Total construction docks: {getTotalConstructionDocks(colony)})")

        events.add(event_factory.buildingCompleted(
          colony.owner,
          "Shipyard",
          completed.colonyId
        ))

    # Special handling for drydocks
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Drydock":
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)

        # Validate spaceport prerequisite
        if not hasSpaceport(colony):
          logError(LogCategory.lcEconomy,
                  &"Drydock construction failed - no spaceport at {completed.colonyId}")
          # This shouldn't happen if build validation worked correctly
          continue

        # Create new drydock (docks from facilities_config.toml, scaled by CST)
        let baseDocks = globalFacilitiesConfig.drydock.docks
        let cstLevel = state.houses[colony.owner].techTree.levels.constructionTech
        let effectiveDocks = effects.calculateEffectiveDocks(baseDocks, cstLevel)

        let drydock = Drydock(
          id: $completed.colonyId & "-DD-" & $(colony.drydocks.len + 1),
          commissionedTurn: state.turn,
          baseDocks: baseDocks,
          effectiveDocks: effectiveDocks,
          isCrippled: false,
          repairQueue: @[],
          activeRepairs: @[]
        )

        colony.drydocks.add(drydock)
        saveColony(completed.colonyId, colony)

        logInfo(LogCategory.lcEconomy,
          &"Commissioned drydock {drydock.id} at {completed.colonyId} " &
          &"(Total repair docks: {getTotalRepairDocks(colony)})")

        events.add(event_factory.buildingCompleted(
          colony.owner,
          "Drydock",
          completed.colonyId
        ))

    # Special handling for ground batteries
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "GroundBattery":
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)

        # Add ground battery (instant construction, 1 turn)
        colony.groundBatteries += 1
        saveColony(completed.colonyId, colony)

        logInfo(LogCategory.lcEconomy,
          &"Deployed ground battery at {completed.colonyId} " &
          &"(Total ground defenses: {getTotalGroundDefense(colony)})")

        events.add(event_factory.buildingCompleted(
          colony.owner,
          "Ground Battery",
          completed.colonyId
        ))

    # Special handling for planetary shields (replacement, not upgrade)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId.startsWith("PlanetaryShield"):
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)

        # Extract shield level from itemId (e.g., "PlanetaryShield-3" -> 3)
        # For now, assume sequential upgrades
        let newLevel = colony.planetaryShieldLevel + 1
        colony.planetaryShieldLevel = min(newLevel, 6)  # Max SLD6
        saveColony(completed.colonyId, colony)

        logInfo(LogCategory.lcEconomy,
          &"Deployed planetary shield SLD{colony.planetaryShieldLevel} at {completed.colonyId} " &
          &"(Block chance: {int(getShieldBlockChance(colony.planetaryShieldLevel) * 100.0)}%)")

        events.add(event_factory.buildingCompleted(
          colony.owner,
          &"Planetary Shield SLD{colony.planetaryShieldLevel}",
          completed.colonyId
        ))

    # Special handling for Marines (MD)
    elif completed.projectType == econ_types.ConstructionType.Building and
         (completed.itemId == "Marine" or completed.itemId == "marine_division"):
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)

        # Get population cost from config
        let marinePopCost = globalGroundUnitsConfig.marine_division.population_cost
        let minViablePop = population_config.minViablePopulation()

        if colony.souls < marinePopCost:
          logWarn(LogCategory.lcEconomy,
            &"Colony {completed.colonyId} lacks population to recruit Marines " &
            &"({colony.souls} souls < {marinePopCost})")
        elif colony.souls - marinePopCost < minViablePop:
          logWarn(LogCategory.lcEconomy,
            &"Colony {completed.colonyId} cannot recruit Marines - would leave colony below minimum viable size " &
            &"({colony.souls - marinePopCost} < {minViablePop} souls)")
        else:
          colony.marines += 1  # Add 1 Marine Division
          colony.souls -= marinePopCost  # Deduct recruited souls
          colony.population = colony.souls div 1_000_000  # Update display population
          saveColony(completed.colonyId, colony)

          logInfo(LogCategory.lcEconomy,
            &"Recruited Marine Division at {completed.colonyId} " &
            &"(Total Marines: {colony.marines} MD, {colony.souls} souls remaining)")

          events.add(event_factory.unitRecruited(
            colony.owner,
            "Marine Division",
            completed.colonyId,
            1
          ))

    # Special handling for Armies (AA)
    elif completed.projectType == econ_types.ConstructionType.Building and
         (completed.itemId == "Army" or completed.itemId == "army"):
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)

        # Get population cost from config
        let armyPopCost = globalGroundUnitsConfig.army.population_cost
        let minViablePop = population_config.minViablePopulation()

        if colony.souls < armyPopCost:
          logWarn(LogCategory.lcEconomy,
            &"Colony {completed.colonyId} lacks population to muster Army " &
            &"({colony.souls} souls < {armyPopCost})")
        elif colony.souls - armyPopCost < minViablePop:
          logWarn(LogCategory.lcEconomy,
            &"Colony {completed.colonyId} cannot muster Army - would leave colony below minimum viable size " &
            &"({colony.souls - armyPopCost} < {minViablePop} souls)")
        else:
          colony.armies += 1  # Add 1 Army Division
          colony.souls -= armyPopCost  # Deduct recruited souls
          colony.population = colony.souls div 1_000_000  # Update display population
          saveColony(completed.colonyId, colony)

          logInfo(LogCategory.lcEconomy,
            &"Mustered Army Division at {completed.colonyId} " &
            &"(Total Armies: {colony.armies} AA, {colony.souls} souls remaining)")

          events.add(event_factory.unitRecruited(
            colony.owner,
            "Army Division",
            completed.colonyId,
            1
          ))

  # Write all modified colonies back to state
  # This ensures multiple units completing at same colony see accumulated changes
  logDebug(LogCategory.lcEconomy, &"Writing {modifiedColonies.len} modified colonies back to state")
  for systemId, colony in modifiedColonies:
    state.colonies[systemId] = colony
    logDebug(LogCategory.lcEconomy, &"  Colony {systemId}: marines={colony.marines}, armies={colony.armies}")

  # Auto-load complete fighter squadrons onto carriers at same colonies
  # Prefer complete squadrons (12 fighters) for maximum effectiveness
  for systemId, colony in modifiedColonies:
    if colony.fighterSquadrons.len > 0:
      var modifiedColony = state.colonies[systemId]
      let acoLevel = state.houses[colony.owner].techTree.levels.advancedCarrierOps

      var fightersLoaded = false
      for fleetId, fleet in state.fleets.mpairs:
        if fleet.location == systemId and fleet.owner == colony.owner:
          for squadron in fleet.squadrons.mitems:
            if squadron.flagship.shipClass in [ShipClass.Carrier, ShipClass.SuperCarrier]:
              let maxCapacity = squadron.getCarrierCapacity(acoLevel)

              while squadron.embarkedFighters.len < maxCapacity and
                    modifiedColony.fighterSquadrons.len > 0:
                # Find a complete squadron (12 fighters) to load first
                var squadronToLoadIdx = -1
                for i in 0..<modifiedColony.fighterSquadrons.len:
                  let totalFighters = 1 + modifiedColony.fighterSquadrons[i].ships.len
                  if totalFighters == 12:
                    squadronToLoadIdx = i
                    break

                # If no complete squadrons, load any available squadron
                if squadronToLoadIdx < 0 and modifiedColony.fighterSquadrons.len > 0:
                  squadronToLoadIdx = 0

                if squadronToLoadIdx >= 0:
                  # Transfer full Squadron object to carrier
                  let fighterSquadron = modifiedColony.fighterSquadrons[squadronToLoadIdx]
                  squadron.embarkedFighters.add(fighterSquadron)
                  modifiedColony.fighterSquadrons.delete(squadronToLoadIdx)
                  let totalFighters = 1 + fighterSquadron.ships.len
                  logInfo(LogCategory.lcFleet,
                    &"Auto-loaded Fighter squadron {fighterSquadron.id} ({totalFighters}/12) " &
                    &"onto carrier {squadron.id} in fleet {fleetId} ({squadron.embarkedFighters.len}/{maxCapacity})")
                  fightersLoaded = true
                else:
                  break

        if fightersLoaded:
          # Write back modified colony and fleet
          state.colonies[systemId] = modifiedColony
          break

proc commissionShips*(
  state: var GameState,
  completedProjects: seq[econ_types.CompletedProject],
  events: var seq[res_types.GameEvent]
) =
  ## Commission ships in Command Phase (next turn)
  ##
  ## This function runs at START of Command Phase, after Conflict Phase.
  ## Converts completed ship construction into operational units:
  ## - Capital ships → squadrons → fleets (auto-assigned)
  ## - Spacelift ships → fleets (auto-assigned with cargo)
  ##
  ## **Strategic Rationale:** Ships built in docks may be destroyed during
  ## Conflict Phase. Commission only if facilities survived combat.
  ##
  ## **Called From:** resolveCommandPhase() in phases/command_phase.nim
  ## **Called After:** Conflict Phase (combat resolution)
  ## **Called Before:** resolveBuildOrders() (new construction)

  # Use same modified colonies pattern
  var modifiedColonies = initTable[SystemId, Colony]()

  template getColony(colId: SystemId): Colony =
    if colId in modifiedColonies:
      modifiedColonies[colId]
    else:
      state.colonies[colId]

  template saveColony(colId: SystemId, col: Colony) =
    modifiedColonies[colId] = col

  for completed in completedProjects:
    logInfo(LogCategory.lcEconomy, &"Commissioning ship: {completed.projectType} itemId={completed.itemId} at system-{completed.colonyId}")

    # Handle ship construction (dock-built units only)
    if completed.projectType == econ_types.ConstructionType.Ship:
      if completed.colonyId in state.colonies:
        var colony = getColony(completed.colonyId)
        let owner = colony.owner

        # Parse ship class from itemId
        try:
          let shipClass = parseEnum[ShipClass](completed.itemId)

          # Skip fighters - they're handled by planetary defense
          if shipClass == ShipClass.Fighter:
            logDebug(LogCategory.lcEconomy, &"Skipping fighter - handled by planetary defense commissioning")
            continue

          # Check if this is a spacelift ship (ETAC or TroopTransport)
          # Note: Starbases are now handled as facilities (Building path above)
          let isSpaceLift = shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]

          # ARCHITECTURE FIX: Scouts form dedicated single-ship fleets (like ETACs)
          # This ensures scouts remain idle for Drungarius reconnaissance deployment
          let isScout = shipClass == ShipClass.Scout

          if isScout:
            # Commission scout in dedicated fleet (NEVER mix with combat ships)
            # Scouts commissioned at same colony join same fleet for mesh network bonuses
            # (2-3 scouts = +1 ELI, 4-5 = +2, 6+ = +3 ELI)
            let techLevel = state.houses[owner].techTree.levels.weaponsTech
            let ship = newShip(shipClass, techLevel)

            # Create squadron with single scout
            let squadronId = $owner & "_scout_sq_" & $completed.colonyId & "_" & $state.turn
            var scoutSquadron = newSquadron(ship, squadronId, owner, completed.colonyId)
            scoutSquadron.squadronType = getSquadronType(shipClass)  # Intel type

            # Find existing scout fleet at this location, or create new one
            # Use fleetsByLocation index for O(1) lookup instead of O(F) scan
            var scoutFleetId = ""
            if completed.colonyId in state.fleetsByLocation:
              for fleetId in state.fleetsByLocation[completed.colonyId]:
                if fleetId notin state.fleets:
                  continue  # Skip stale index entry
                let fleet = state.fleets[fleetId]
                if fleet.owner == owner:
                  # Check if this is a pure scout fleet (only scout squadrons)
                  var isPureScoutFleet = fleet.squadrons.len > 0
                  for squadron in fleet.squadrons:
                    if squadron.flagship.shipClass != ShipClass.Scout:
                      isPureScoutFleet = false
                      break

                  if isPureScoutFleet:
                    scoutFleetId = fleetId
                    break

            if scoutFleetId != "":
              # Add to existing scout fleet (mesh network bonus)
              state.fleets[scoutFleetId].squadrons.add(scoutSquadron)
              let scoutCount = state.fleets[scoutFleetId].squadrons.len
              logInfo(LogCategory.lcFleet,
                &"Commissioned Scout in existing fleet {scoutFleetId} at {completed.colonyId} " &
                &"({scoutCount} scouts, mesh network bonus)")
            else:
              # Create new scout fleet
              scoutFleetId = $owner & "_scout_fleet_" & $completed.colonyId & "_" & $state.turn
              state.fleets[scoutFleetId] = Fleet(
                id: scoutFleetId,
                owner: owner,
                location: completed.colonyId,
                squadrons: @[scoutSquadron],
                status: FleetStatus.Active,
                autoBalanceSquadrons: false  # CRITICAL: Don't merge scouts with combat fleets
              )
              logInfo(LogCategory.lcFleet,
                &"Commissioned Scout in new dedicated fleet {scoutFleetId} at {completed.colonyId}")

            # Generate event
            events.add(event_factory.shipCommissioned(
              owner,
              shipClass,
              completed.colonyId
            ))

            # Skip rest of combat ship logic
            continue

          elif isSpaceLift:
            # Commission spacelift ship as single-ship squadron
            # ETAC → SquadronType.Expansion, TroopTransport → SquadronType.Auxiliary
            let techLevel = state.houses[owner].techTree.levels.weaponsTech

            # Create the ship using new DoD pattern
            var ship = ship_entity.newShip(shipClass, techLevel)

            # Get cargo capacity from config via helper function
            let cargoCapacity = ship.baseCarryLimit()

            # Initialize cargo hold and set initial cargo
            # ETAC: full colonists, TroopTransport: empty
            if shipClass == ShipClass.ETAC:
              # ETACs commission with full cargo (3 PTU) at no extraction cost
              # Lore: Self-sufficient generation ships with cryostasis colonists
              ship.initCargo(CargoType.Colonists, cargoCapacity)
              discard ship.loadCargo(cargoCapacity)  # Fill to capacity
              logInfo(LogCategory.lcEconomy,
                &"Commissioned ETAC with {cargoCapacity} PTU (cryostasis generation ship)")
            elif shipClass == ShipClass.TroopTransport:
              # TroopTransports start empty (marines loaded later)
              ship.initCargo(CargoType.Marines, cargoCapacity)

            # Create single-ship squadron (flagship only, no escorts)
            let squadronId = $owner & "_" & $shipClass & "_" & $completed.colonyId & "_" & $state.turn
            var squadron = newSquadron(ship, squadronId, owner, completed.colonyId)
            squadron.squadronType = getSquadronType(shipClass)  # Expansion or Auxiliary

            # Add to unassignedSquadrons for auto-assignment to fleets
            colony.unassignedSquadrons.add(squadron)
            saveColony(completed.colonyId, colony)
            logInfo(LogCategory.lcEconomy,
              &"Commissioned {shipClass} squadron {squadronId} at {completed.colonyId}")

            # Auto-assign to fleets (create new fleet if needed)
            if colony.unassignedSquadrons.len > 0:
              # Find the squadron we just added (last in the list)
              var squadronToAssign: Squadron
              var foundIdx = -1
              for i in countdown(colony.unassignedSquadrons.len - 1, 0):
                if colony.unassignedSquadrons[i].squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
                  squadronToAssign = colony.unassignedSquadrons[i]
                  foundIdx = i
                  break

              if foundIdx >= 0:
                var targetFleetId = ""

                # ETACs ALWAYS get their own fleet for independent colonization
                # TroopTransports can share fleets (they're for invasions, need coordination)
                if shipClass == ShipClass.ETAC:
                  # Create new fleet for this ETAC (never share)
                  targetFleetId = $owner & "_fleet" & $(state.fleets.len + 1)
                  state.fleets[targetFleetId] = Fleet(
                    id: targetFleetId,
                    owner: owner,
                    location: completed.colonyId,
                    squadrons: @[squadronToAssign],  # Squadron, not spacelift
                    status: FleetStatus.Active,
                    autoBalanceSquadrons: true
                  )
                  logInfo(LogCategory.lcFleet,
                    &"Commissioned ETAC Expansion squadron in new independent fleet {targetFleetId}")
                else:
                  # TroopTransports: Find existing fleet or create new one
                  # Use fleetsByLocation index for O(1) lookup instead of O(F) scan
                  if completed.colonyId in state.fleetsByLocation:
                    for fleetId in state.fleetsByLocation[completed.colonyId]:
                      if fleetId notin state.fleets:
                        continue  # Skip stale index entry
                      let fleet = state.fleets[fleetId]
                      if fleet.owner == owner:
                        targetFleetId = fleetId
                        break

                  if targetFleetId == "":
                    # Create new fleet for squadron
                    targetFleetId = $owner & "_fleet" & $(state.fleets.len + 1)
                    state.fleets[targetFleetId] = Fleet(
                      id: targetFleetId,
                      owner: owner,
                      location: completed.colonyId,
                      squadrons: @[squadronToAssign],  # Squadron, not spacelift
                      status: FleetStatus.Active,
                      autoBalanceSquadrons: true
                    )
                    logInfo(LogCategory.lcFleet,
                      &"Commissioned {shipClass} Auxiliary squadron in new fleet {targetFleetId}")
                  else:
                    # Add squadron to existing fleet
                    state.fleets[targetFleetId].squadrons.add(squadronToAssign)
                    logInfo(LogCategory.lcFleet,
                      &"Commissioned {shipClass} Auxiliary squadron in fleet {targetFleetId}")

                # Remove from unassigned pool (it's now in fleet)
                colony.unassignedSquadrons.delete(foundIdx)
                saveColony(completed.colonyId, colony)

                logInfo(LogCategory.lcFleet, &"Auto-assigned {shipClass} squadron to fleet {targetFleetId}")

            # Skip rest of combat ship logic
            continue

          # Combat ships - existing logic
          let techLevel = state.houses[owner].techTree.levels.weaponsTech

          # Create the ship
          let ship = ship_entity.newShip(shipClass, techLevel)

          # Capital ships (CR >= 7) always create new squadrons as flagship
          # Escorts try to join existing squadrons first
          let isCapitalShip = ship.commandRating() >= globalMilitaryConfig.squadron_limits.capital_ship_cr_threshold

          var assignedSquadron: SquadronId = ""
          var squadronsChecked = 0

          if not isCapitalShip:
            # Escorts: try to join existing squadrons
            # IMPORTANT: Skip specialized squadrons (ETAC/Scout/Fighter)
            # Use fleetsByLocation index for O(1) lookup instead of O(F) scan
            if completed.colonyId in state.fleetsByLocation:
              for fleetId in state.fleetsByLocation[completed.colonyId]:
                if fleetId notin state.fleets:
                  continue  # Skip stale index entry
                let fleet = state.fleets[fleetId]
                if fleet.owner == owner:
                  for squadron in fleet.squadrons:
                    squadronsChecked += 1

                    # Skip ETAC squadrons - combat ships should not join colonization fleets
                    if squadron.squadronType == SquadronType.Expansion and
                       squadron.flagship.shipClass == ShipClass.ETAC:
                      continue

                    # Skip Scout squadrons - scouts operate independently for reconnaissance
                    if squadron.flagship.shipClass == ShipClass.Scout:
                      continue

                    # Skip Fighter squadrons - fighters are carrier-based, not fleet escorts
                    if squadron.flagship.shipClass == ShipClass.Fighter:
                      continue

                    if canAddShip(squadron, ship):
                      # Found a squadron with capacity
                      assignedSquadron = squadron.id
                      logDebug(LogCategory.lcFleet, &"Ship {shipClass} can join squadron {squadron.id} (CR={squadron.flagship.commandRating()}, avail={squadron.availableCommandCapacity()})")
                      break
                  if assignedSquadron != "":
                    break

          # Add ship to existing squadron or create new one
          if assignedSquadron != "":
            # Add to existing squadron (escorts only)
            for fleetId, fleet in state.fleets.mpairs:
              if fleet.owner == owner:
                for squadron in fleet.squadrons.mitems:
                  if squadron.id == assignedSquadron:
                    discard addShip(squadron, ship)
                    logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} and assigned to squadron {squadron.id}")
                    break

          else:
            # No existing squadron has capacity - create new one
            logInfo(LogCategory.lcFleet, &"No existing squadron can fit {shipClass} (checked {squadronsChecked} squadrons), creating new squadron")
            # Create new squadron with this ship as flagship
            # Use total squadron count across all fleets to ensure unique IDs
            # Use fleetsByOwner index for O(1) lookup instead of O(F) scan
            var totalSquadrons = 0
            if owner in state.fleetsByOwner:
              for fleetId in state.fleetsByOwner[owner]:
                if fleetId in state.fleets:
                  totalSquadrons += state.fleets[fleetId].squadrons.len
            let newSquadronId = $owner & "_sq_" & $totalSquadrons & "_" & $state.turn
            var newSq = newSquadron(ship, newSquadronId, owner, completed.colonyId)
            newSq.squadronType = getSquadronType(shipClass)  # Set appropriate type

            # Find or create fleet at this location
            # IMPORTANT: Skip specialized fleets (ETAC/Scout) - keep them pure for their missions
            # Use fleetsByLocation index for O(1) lookup instead of O(F) scan
            var targetFleetId = ""
            if completed.colonyId in state.fleetsByLocation:
              for fleetId in state.fleetsByLocation[completed.colonyId]:
                if fleetId notin state.fleets:
                  continue  # Skip stale index entry
                let fleet = state.fleets[fleetId]
                if fleet.owner == owner:
                  # Check if this fleet contains ETACs or Scouts - if so, skip it
                  var hasSpecializedShips = false
                  for squadron in fleet.squadrons:
                    # Skip ETAC fleets (colonization missions)
                    if squadron.squadronType == SquadronType.Expansion and
                       squadron.flagship.shipClass == ShipClass.ETAC:
                      hasSpecializedShips = true
                      break
                    # Skip Scout fleets (reconnaissance missions)
                    if squadron.flagship.shipClass == ShipClass.Scout:
                      hasSpecializedShips = true
                      break

                  if not hasSpecializedShips:
                    targetFleetId = fleetId
                    break

            if targetFleetId == "":
              # Create new fleet at colony
              targetFleetId = $owner & "_fleet" & $(state.fleets.len + 1)
              state.fleets[targetFleetId] = Fleet(
                id: targetFleetId,
                owner: owner,
                location: completed.colonyId,
                squadrons: @[newSq],
                status: FleetStatus.Active,
                autoBalanceSquadrons: true
              )
              logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} in new fleet {targetFleetId}")
            else:
              # Add squadron to existing fleet
              state.fleets[targetFleetId].squadrons.add(newSq)
              logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} in new squadron {newSq.id}")

          # Increment planet-breaker counter if applicable (assets.md:2.4.8)
          if shipClass == ShipClass.PlanetBreaker:
            state.houses[owner].planetBreakerCount += 1
            logInfo(LogCategory.lcEconomy,
                    &"Planet-Breaker commissioned for {owner} " &
                    &"(total: {state.houses[owner].planetBreakerCount})")

          # Generate event
          events.add(event_factory.shipCommissioned(
            owner,
            shipClass,
            completed.colonyId
          ))

        except ValueError:
          logError(LogCategory.lcEconomy, &"Invalid ship class: {completed.itemId}")

  # Write all modified colonies back to state
  # This ensures multiple units completing at same colony see accumulated changes
  logDebug(LogCategory.lcEconomy, &"Writing {modifiedColonies.len} modified colonies back to state")
  for systemId, colony in modifiedColonies:
    state.colonies[systemId] = colony
    logDebug(LogCategory.lcEconomy, &"  Colony {systemId}: unassignedSquadrons={colony.unassignedSquadrons.len}")

