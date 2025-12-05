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
import ../gamestate, ../fleet, ../squadron, ../spacelift, ../logger
import ../economy/types as econ_types
import ./types as res_types

# Import config access
import ../config/ground_units_config

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
  ## Calculate total construction dock capacity
  result = 0
  for sp in colony.spaceports:
    result += sp.docks
  for sy in colony.shipyards:
    if not sy.isCrippled:
      result += sy.docks

proc hasSpaceport*(colony: Colony): bool =
  ## Check if colony has at least one operational spaceport
  result = colony.spaceports.len > 0

proc commissionCompletedProjects*(
  state: var GameState,
  completedProjects: seq[econ_types.CompletedProject],
  events: var seq[res_types.GameEvent]
) =
  ## Commission all completed construction projects from Maintenance Phase
  ##
  ## This function runs at the START of Command Phase, before new build orders.
  ## It converts completed construction projects into operational units:
  ## - Fighters → colony.fighterSquadrons
  ## - Facilities → colony.spaceports/shipyards/starbases
  ## - Ground units → colony.marines/armies/groundBatteries
  ## - Capital ships → squadrons → fleets (auto-assigned)
  ## - Spacelift ships → fleets (auto-assigned with cargo)
  ##
  ## **Pure Commissioning:** This function only handles commissioning.
  ## Auto-loading fighters to carriers is a separate step.
  ## Auto-balancing squadrons to fleets happens at end of Command Phase.
  ##
  ## **Called From:** resolveCommandPhase() in resolve.nim
  ## **Called After:** Maintenance Phase (queue advancement)
  ## **Called Before:** resolveBuildOrders() (new construction)

  for completed in completedProjects:
    logDebug(LogCategory.lcEconomy, &"Commissioning: {completed.projectType} at system-{completed.colonyId}")

    # Special handling for fighter squadrons
    # Fighters can come through as either:
    # 1. ConstructionType.Building with itemId="FighterSquadron" (legacy/planned)
    # 2. ConstructionType.Ship with itemId="Fighter" (current system via budget.nim)
    if (completed.projectType == econ_types.ConstructionType.Building and
        completed.itemId == "FighterSquadron") or
       (completed.projectType == econ_types.ConstructionType.Ship and
        completed.itemId == "Fighter"):
      # Commission fighter squadron at colony
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new fighter squadron
        let fighterSq = FighterSquadron(
          id: $completed.colonyId & "-FS-" & $(colony.fighterSquadrons.len + 1),
          commissionedTurn: state.turn
        )

        colony.fighterSquadrons.add(fighterSq)

        logInfo(LogCategory.lcEconomy, &"Commissioned fighter squadron {fighterSq.id} at {completed.colonyId}")

        # Fighters remain at colony by default - auto-loading happens in separate step
        # Per assets.md:2.4.1 - fighters are colony-owned until explicitly transferred

        state.colonies[completed.colonyId] = colony

        # Generate event
        events.add(res_types.GameEvent(
          eventType: res_types.GameEventType.ShipCommissioned,
          houseId: colony.owner,
          description: "Fighter Squadron commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for starbases
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Starbase":
      # Commission starbase at colony
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new starbase
        let starbase = Starbase(
          id: $completed.colonyId & "-SB-" & $(colony.starbases.len + 1),
          commissionedTurn: state.turn,
          isCrippled: false
        )

        colony.starbases.add(starbase)
        state.colonies[completed.colonyId] = colony

        logInfo(LogCategory.lcEconomy,
          &"Commissioned starbase {starbase.id} at {completed.colonyId} " &
          &"(Total operational: {getOperationalStarbaseCount(colony)}, " &
          &"Growth bonus: {int(getStarbaseGrowthBonus(colony) * 100.0)}%)")

        # Generate event
        events.add(res_types.GameEvent(
          eventType: res_types.GameEventType.ShipCommissioned,
          houseId: colony.owner,
          description: "Starbase commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for spaceports
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Spaceport":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Create new spaceport (5 docks per facilities_config.toml)
        let spaceport = Spaceport(
          id: $completed.colonyId & "-SP-" & $(colony.spaceports.len + 1),
          commissionedTurn: state.turn,
          docks: 5  # From facilities_config: spaceport.docks
        )

        colony.spaceports.add(spaceport)
        state.colonies[completed.colonyId] = colony

        logInfo(LogCategory.lcEconomy,
          &"Commissioned spaceport {spaceport.id} at {completed.colonyId} " &
          &"(Total construction docks: {getTotalConstructionDocks(colony)})")

        events.add(res_types.GameEvent(
          eventType: res_types.GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Spaceport commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for shipyards
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Shipyard":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Validate spaceport prerequisite
        if not hasSpaceport(colony):
          logError(LogCategory.lcEconomy, &"Shipyard construction failed - no spaceport at {completed.colonyId}")
          # This shouldn't happen if build validation worked correctly
          continue

        # Create new shipyard (10 docks per facilities_config.toml)
        let shipyard = Shipyard(
          id: $completed.colonyId & "-SY-" & $(colony.shipyards.len + 1),
          commissionedTurn: state.turn,
          docks: 10,  # From facilities_config: shipyard.docks
          isCrippled: false
        )

        colony.shipyards.add(shipyard)
        state.colonies[completed.colonyId] = colony

        logInfo(LogCategory.lcEconomy,
          &"Commissioned shipyard {shipyard.id} at {completed.colonyId} " &
          &"(Total construction docks: {getTotalConstructionDocks(colony)})")

        events.add(res_types.GameEvent(
          eventType: res_types.GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Shipyard commissioned at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for ground batteries
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "GroundBattery":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Add ground battery (instant construction, 1 turn)
        colony.groundBatteries += 1
        state.colonies[completed.colonyId] = colony

        logInfo(LogCategory.lcEconomy,
          &"Deployed ground battery at {completed.colonyId} " &
          &"(Total ground defenses: {getTotalGroundDefense(colony)})")

        events.add(res_types.GameEvent(
          eventType: res_types.GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Ground battery deployed at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for planetary shields (replacement, not upgrade)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId.startsWith("PlanetaryShield"):
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Extract shield level from itemId (e.g., "PlanetaryShield-3" -> 3)
        # For now, assume sequential upgrades
        let newLevel = colony.planetaryShieldLevel + 1
        colony.planetaryShieldLevel = min(newLevel, 6)  # Max SLD6
        state.colonies[completed.colonyId] = colony

        logInfo(LogCategory.lcEconomy,
          &"Deployed planetary shield SLD{colony.planetaryShieldLevel} at {completed.colonyId} " &
          &"(Block chance: {int(getShieldBlockChance(colony.planetaryShieldLevel) * 100.0)}%)")

        events.add(res_types.GameEvent(
          eventType: res_types.GameEventType.BuildingCompleted,
          houseId: colony.owner,
          description: "Planetary Shield SLD" & $colony.planetaryShieldLevel & " deployed at " & $completed.colonyId,
          systemId: some(completed.colonyId)
        ))

    # Special handling for Marines (MD)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Marine":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Get population cost from config
        let marinePopCost = globalGroundUnitsConfig.marine_division.population_cost
        const minViablePopulation = 1_000_000  # 1 PU minimum for colony viability

        if colony.souls < marinePopCost:
          logWarn(LogCategory.lcEconomy,
            &"Colony {completed.colonyId} lacks population to recruit Marines " &
            &"({colony.souls} souls < {marinePopCost})")
        elif colony.souls - marinePopCost < minViablePopulation:
          logWarn(LogCategory.lcEconomy,
            &"Colony {completed.colonyId} cannot recruit Marines - would leave colony below minimum viable size " &
            &"({colony.souls - marinePopCost} < {minViablePopulation} souls)")
        else:
          colony.marines += 1  # Add 1 Marine Division
          colony.souls -= marinePopCost  # Deduct recruited souls
          colony.population = colony.souls div 1_000_000  # Update display population
          state.colonies[completed.colonyId] = colony

          logInfo(LogCategory.lcEconomy,
            &"Recruited Marine Division at {completed.colonyId} " &
            &"(Total Marines: {colony.marines} MD, {colony.souls} souls remaining)")

          events.add(res_types.GameEvent(
            eventType: res_types.GameEventType.UnitRecruited,
            houseId: colony.owner,
            description: "Marine Division recruited at " & $completed.colonyId & " (total: " & $colony.marines & " MD)",
            systemId: some(completed.colonyId)
          ))

    # Special handling for Armies (AA)
    elif completed.projectType == econ_types.ConstructionType.Building and
         completed.itemId == "Army":
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]

        # Get population cost from config
        let armyPopCost = globalGroundUnitsConfig.army.population_cost
        const minViablePopulation = 1_000_000  # 1 PU minimum for colony viability

        if colony.souls < armyPopCost:
          logWarn(LogCategory.lcEconomy,
            &"Colony {completed.colonyId} lacks population to muster Army " &
            &"({colony.souls} souls < {armyPopCost})")
        elif colony.souls - armyPopCost < minViablePopulation:
          logWarn(LogCategory.lcEconomy,
            &"Colony {completed.colonyId} cannot muster Army - would leave colony below minimum viable size " &
            &"({colony.souls - armyPopCost} < {minViablePopulation} souls)")
        else:
          colony.armies += 1  # Add 1 Army Division
          colony.souls -= armyPopCost  # Deduct recruited souls
          colony.population = colony.souls div 1_000_000  # Update display population
          state.colonies[completed.colonyId] = colony

          logInfo(LogCategory.lcEconomy,
            &"Mustered Army Division at {completed.colonyId} " &
            &"(Total Armies: {colony.armies} AA, {colony.souls} souls remaining)")

          events.add(res_types.GameEvent(
            eventType: res_types.GameEventType.UnitRecruited,
            houseId: colony.owner,
            description: "Army Division mustered at " & $completed.colonyId & " (total: " & $colony.armies & " AA)",
            systemId: some(completed.colonyId)
          ))

    # Handle ship construction
    elif completed.projectType == econ_types.ConstructionType.Ship:
      if completed.colonyId in state.colonies:
        var colony = state.colonies[completed.colonyId]
        let owner = colony.owner

        # Parse ship class from itemId
        try:
          let shipClass = parseEnum[ShipClass](completed.itemId)

          # Handle special ship types first
          # 1. Fighter squadrons → colony.fighterSquadrons
          if shipClass == ShipClass.Fighter:
            let fighterSq = FighterSquadron(
              id: $completed.colonyId & "-FS-" & $(colony.fighterSquadrons.len + 1),
              commissionedTurn: state.turn
            )
            colony.fighterSquadrons.add(fighterSq)
            state.colonies[completed.colonyId] = colony
            logInfo(LogCategory.lcEconomy, &"Commissioned fighter squadron {fighterSq.id} at {completed.colonyId}")

            events.add(res_types.GameEvent(
              eventType: res_types.GameEventType.ShipCommissioned,
              houseId: owner,
              description: "Fighter squadron commissioned at " & $completed.colonyId,
              systemId: some(completed.colonyId)
            ))
            continue

          # 2. Starbases → colony.starbases
          elif shipClass == ShipClass.Starbase:
            let starbase = Starbase(
              id: $completed.colonyId & "-SB-" & $(colony.starbases.len + 1),
              commissionedTurn: state.turn,
              isCrippled: false
            )
            colony.starbases.add(starbase)
            state.colonies[completed.colonyId] = colony
            logInfo(LogCategory.lcEconomy, &"Commissioned starbase {starbase.id} at {completed.colonyId} (operational: {getOperationalStarbaseCount(colony)})")

            events.add(res_types.GameEvent(
              eventType: res_types.GameEventType.ShipCommissioned,
              houseId: owner,
              description: "Starbase commissioned at " & $completed.colonyId,
              systemId: some(completed.colonyId)
            ))
            continue

          # 3. Check if this is a spacelift ship (ETAC or TroopTransport)
          let isSpaceLift = shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]

          if isSpaceLift:
            # Commission spacelift ship and auto-assign to fleet
            let shipId = owner & "_" & $shipClass & "_" & $completed.colonyId & "_" & $state.turn
            var spaceLiftShip = newSpaceLiftShip(shipId, shipClass, owner, completed.colonyId)

            # Auto-load PTU onto ETAC at commissioning
            if shipClass == ShipClass.ETAC and colony.population > 1:
              let extractionCost = 1.0 / (1.0 + 0.00657 * colony.population.float)
              let newPopulation = colony.population.float - extractionCost
              colony.population = max(1, newPopulation.int)
              spaceLiftShip.cargo.cargoType = CargoType.Colonists
              spaceLiftShip.cargo.quantity = 1
              logInfo(LogCategory.lcEconomy, &"Loaded 1 PTU onto {shipId} (extraction: {extractionCost:.2f} PU from {completed.colonyId})")

            colony.unassignedSpaceLiftShips.add(spaceLiftShip)
            state.colonies[completed.colonyId] = colony
            logInfo(LogCategory.lcEconomy, &"Commissioned {shipClass} spacelift ship at {completed.colonyId}")

            # Auto-assign to fleets (create new fleet if needed)
            if colony.unassignedSpaceLiftShips.len > 0:
              let shipToAssign = colony.unassignedSpaceLiftShips[colony.unassignedSpaceLiftShips.len - 1]

              var targetFleetId = ""
              for fleetId, fleet in state.fleets:
                if fleet.location == completed.colonyId and fleet.owner == owner:
                  targetFleetId = fleetId
                  break

              if targetFleetId == "":
                # Create new fleet for spacelift ship
                targetFleetId = $owner & "_fleet" & $(state.fleets.len + 1)
                state.fleets[targetFleetId] = Fleet(
                  id: targetFleetId,
                  owner: owner,
                  location: completed.colonyId,
                  squadrons: @[],
                  spaceLiftShips: @[shipToAssign],
                  status: FleetStatus.Active,
                  autoBalanceSquadrons: true
                )
                logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} in new fleet {targetFleetId}")
              else:
                # Add to existing fleet
                state.fleets[targetFleetId].spaceLiftShips.add(shipToAssign)
                logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} in fleet {targetFleetId}")

              # Remove from unassigned pool (it's now in fleet)
              colony.unassignedSpaceLiftShips.delete(colony.unassignedSpaceLiftShips.len - 1)
              state.colonies[completed.colonyId] = colony

              logInfo(LogCategory.lcFleet, &"Auto-assigned {shipClass} to fleet {targetFleetId}")

            # Skip rest of combat ship logic
            continue

          # Combat ships - existing logic
          let techLevel = state.houses[owner].techTree.levels.weaponsTech

          # Create the ship
          let ship = newEnhancedShip(shipClass, techLevel)

          # Find squadrons at this system belonging to this house
          var assignedSquadron: SquadronId = ""
          for fleetId, fleet in state.fleets:
            if fleet.owner == owner and fleet.location == completed.colonyId:
              for squadron in fleet.squadrons:
                if canAddShip(squadron, ship):
                  # Found a squadron with capacity
                  assignedSquadron = squadron.id
                  break
              if assignedSquadron != "":
                break

          # Add ship to existing squadron or create new one
          if assignedSquadron != "":
            # Add to existing squadron
            for fleetId, fleet in state.fleets.mpairs:
              if fleet.owner == owner:
                for squadron in fleet.squadrons.mitems:
                  if squadron.id == assignedSquadron:
                    discard addShip(squadron, ship)
                    logInfo(LogCategory.lcFleet, &"Commissioned {shipClass} and assigned to squadron {squadron.id}")
                    break

          else:
            # Create new squadron with this ship as flagship
            let newSquadronId = $owner & "_sq_" & $state.fleets.len & "_" & $state.turn
            let newSq = newSquadron(ship, newSquadronId, owner, completed.colonyId)

            # Find or create fleet at this location
            var targetFleetId = ""
            for fleetId, fleet in state.fleets:
              if fleet.owner == owner and fleet.location == completed.colonyId:
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
                spaceLiftShips: @[],
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
          events.add(res_types.GameEvent(
            eventType: res_types.GameEventType.ShipCommissioned,
            houseId: owner,
            description: $shipClass & " commissioned at " & $completed.colonyId,
            systemId: some(completed.colonyId)
          ))

        except ValueError:
          logError(LogCategory.lcEconomy, &"Invalid ship class: {completed.itemId}")
