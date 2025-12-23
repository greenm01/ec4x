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
import ../../types/core
import ../../types/ship
import ../../types/colony
import ../../types/fleet
import ../../types/squadron
import ../../types/game_state
import ../../types/production
import ../../types/facilities
import ../../types/event
import ../../state/game_state as gs_helpers
import ../../state/entity_manager
import ../../state/id_gen
import ../../event_factory/init as event_factory
import ../../../common/logger
import ../ship/entity as ship_entity  # Ship construction and helpers

# Import config access
import ../../config/ground_units_config
import ../../config/facilities_config
import ../../config/military_config
import ../../config/population_config  # For minViablePopulation

# Temporary inline version until research/effects is fixed
proc calculateEffectiveDocks(baseDocks: int, cstLevel: int): int =
  ## Calculate effective dock capacity with CST multiplier
  ## CST provides +10% capacity per level above 1
  let multiplier = 1.0 + (float(cstLevel - 1) * 0.10)
  result = int(float(baseDocks) * multiplier)

# Helper functions using DoD patterns
proc getOperationalStarbaseCount*(state: GameState, colonyId: ColonyId): int =
  ## Count non-crippled starbases for a colony using DoD entity manager
  result = 0
  if colonyId notin state.starbases.byColony:
    return 0

  for starbaseId in state.starbases.byColony[colonyId]:
    let starbaseOpt = state.starbases.entities.getEntity(starbaseId)
    if starbaseOpt.isSome:
      let starbase = starbaseOpt.get()
      if not starbase.isCrippled:
        result += 1

proc getStarbaseGrowthBonus*(state: GameState, colonyId: ColonyId): float =
  ## Calculate growth bonus from operational starbases
  ## Per specs: Each operational starbase provides growth bonus
  let operationalCount = getOperationalStarbaseCount(state, colonyId)
  result = operationalCount.float * 0.05  # 5% per starbase

proc hasSpaceport*(state: GameState, colonyId: ColonyId): bool =
  ## Check if colony has at least one spaceport using DoD
  colonyId in state.spaceports.byColony and
    state.spaceports.byColony[colonyId].len > 0

proc getShieldBlockChance*(shieldLevel: int): float =
  ## Calculate block chance for planetary shield level
  ## SLD1=10%, SLD2=20%, ..., SLD6=60%
  result = shieldLevel.float * 0.10

# Note: getTotalGroundDefense removed - groundBatteries is still a simple counter on Colony
# getTotalConstructionDocks and hasSpaceport moved to DoD versions above

proc commissionPlanetaryDefense*(
  state: var GameState,
  completedProjects: seq[CompletedProject],
  events: var seq[GameEvent]
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
  var modifiedColonies = initTable[ColonyId, Colony]()

  template getColony(colId: ColonyId): Colony =
    if colId in modifiedColonies:
      modifiedColonies[colId]
    else:
      let opt = gs_helpers.getColony(state, colId)
      if opt.isSome:
        opt.get()
      else:
        # Return default colony if not found (shouldn't happen)
        Colony()

  template saveColony(colId: ColonyId, col: Colony) =
    modifiedColonies[colId] = col

  for completed in completedProjects:
    logInfo("Economy", &"Commissioning planetary defense: {completed.projectType} itemId={completed.itemId} at system-{completed.colonyId}")

    # TODO: Fighter squadron commissioning needs DoD refactoring
    # Fighter squadrons are no longer embedded in Colony, they use entity managers
    # This section needs to be rewritten to:
    # 1. Use state.squadrons entity manager
    # 2. Link squadrons to colonies via indexes
    # 3. Manage ships through ship entity manager
    # For now, fighter construction is disabled.
    if (completed.projectType == BuildType.Facility and
        completed.itemId == "FighterSquadron") or
       (completed.projectType == BuildType.Ship and
        completed.itemId == "Fighter"):
      logWarn("Economy", "Fighter commissioning not yet implemented in DoD refactor")
      discard  # Skip for now

    # Special handling for starbases
    elif completed.projectType == BuildType.Facility and
         completed.itemId == "Starbase":
      # Commission starbase at colony using DoD
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Generate starbase ID and create starbase using DoD
        let starbaseId = generateStarbaseId(state)
        let starbase = Starbase(
          id: starbaseId,
          colonyId: completed.colonyId,
          commissionedTurn: state.turn,
          isCrippled: false
        )

        # Add to entity manager and update indexes
        state.starbases.entities.addEntity(starbaseId, starbase)
        state.starbases.byColony.mgetOrPut(completed.colonyId, @[]).add(starbaseId)

        # Update colony's starbase list
        var updatedColony = colony
        updatedColony.starbaseIds.add(starbaseId)
        state.colonies.entities.updateEntity(completed.colonyId, updatedColony)

        logInfo("Economy",
          &"Commissioned starbase {starbaseId} at {completed.colonyId} " &
          &"(Total operational: {getOperationalStarbaseCount(state, completed.colonyId)}, " &
          &"Growth bonus: {int(getStarbaseGrowthBonus(state, completed.colonyId) * 100.0)}%)")

        # Generate event
        events.add(event_factory.buildingCompleted(
          colony.owner,
          "Starbase",
          colony.systemId
        ))

    # Special handling for spaceports
    elif completed.projectType == BuildType.Facility and
         completed.itemId == "Spaceport":
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Create new spaceport (docks from facilities_config.toml, scaled by CST)
        let baseDocks = globalFacilitiesConfig.spaceport.docks
        let houseOpt = gs_helpers.getHouse(state, colony.owner)
        if houseOpt.isNone:
          continue
        let house = houseOpt.get()
        let cstLevel = house.techTree.levels.constructionTech
        let effectiveDocks = calculateEffectiveDocks(baseDocks, cstLevel)

        # Generate spaceport ID and create using DoD
        let spaceportId = generateSpaceportId(state)
        let spaceport = Spaceport(
          id: spaceportId,
          colonyId: completed.colonyId,
          commissionedTurn: state.turn,
          baseDocks: int32(baseDocks),
          effectiveDocks: int32(effectiveDocks),
          constructionQueue: @[],
          activeConstructions: @[]
        )

        # Add to entity manager and update indexes
        state.spaceports.entities.addEntity(spaceportId, spaceport)
        state.spaceports.byColony.mgetOrPut(completed.colonyId, @[]).add(spaceportId)

        # Update colony's spaceport list
        var updatedColony = colony
        updatedColony.spaceportIds.add(spaceportId)
        state.colonies.entities.updateEntity(completed.colonyId, updatedColony)

        logInfo("Economy",
          &"Commissioned spaceport {spaceportId} at {completed.colonyId}")

        events.add(event_factory.buildingCompleted(
          colony.owner,
          "Spaceport",
          colony.systemId
        ))

    # Special handling for shipyards
    elif completed.projectType == BuildType.Facility and
         completed.itemId == "Shipyard":
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Validate spaceport prerequisite
        if not hasSpaceport(state, completed.colonyId):
          logError("Economy", &"Shipyard construction failed - no spaceport at {completed.colonyId}")
          # This shouldn't happen if build validation worked correctly
          continue

        # Create new shipyard (docks from facilities_config.toml, scaled by CST)
        let baseDocks = globalFacilitiesConfig.shipyard.docks
        let houseOpt = gs_helpers.getHouse(state, colony.owner)
        if houseOpt.isNone:
          continue
        let house = houseOpt.get()
        let cstLevel = house.techTree.levels.constructionTech
        let effectiveDocks = calculateEffectiveDocks(baseDocks, cstLevel)

        # Generate shipyard ID and create using DoD
        let shipyardId = generateShipyardId(state)
        let shipyard = Shipyard(
          id: shipyardId,
          colonyId: completed.colonyId,
          commissionedTurn: state.turn,
          baseDocks: int32(baseDocks),
          effectiveDocks: int32(effectiveDocks),
          isCrippled: false,
          constructionQueue: @[],
          activeConstructions: @[]
        )

        # Add to entity manager and update indexes
        state.shipyards.entities.addEntity(shipyardId, shipyard)
        state.shipyards.byColony.mgetOrPut(completed.colonyId, @[]).add(shipyardId)

        # Update colony's shipyard list
        var updatedColony = colony
        updatedColony.shipyardIds.add(shipyardId)
        state.colonies.entities.updateEntity(completed.colonyId, updatedColony)

        logInfo("Economy",
          &"Commissioned shipyard {shipyardId} at {completed.colonyId}")

        events.add(event_factory.buildingCompleted(
          colony.owner,
          "Shipyard",
          colony.systemId
        ))

    # Special handling for drydocks
    elif completed.projectType == BuildType.Facility and
         completed.itemId == "Drydock":
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Validate spaceport prerequisite
        if not hasSpaceport(state, completed.colonyId):
          logError("Economy",
                  &"Drydock construction failed - no spaceport at {completed.colonyId}")
          # This shouldn't happen if build validation worked correctly
          continue

        # Create new drydock (docks from facilities_config.toml, scaled by CST)
        let baseDocks = globalFacilitiesConfig.drydock.docks
        let houseOpt = gs_helpers.getHouse(state, colony.owner)
        if houseOpt.isNone:
          continue
        let house = houseOpt.get()
        let cstLevel = house.techTree.levels.constructionTech
        let effectiveDocks = calculateEffectiveDocks(baseDocks, cstLevel)

        # Generate drydock ID and create using DoD
        let drydockId = generateDrydockId(state)
        let drydock = Drydock(
          id: drydockId,
          colonyId: completed.colonyId,
          commissionedTurn: state.turn,
          baseDocks: int32(baseDocks),
          effectiveDocks: int32(effectiveDocks),
          isCrippled: false,
          repairQueue: @[],
          activeRepairs: @[]
        )

        # Add to entity manager and update indexes
        state.drydocks.entities.addEntity(drydockId, drydock)
        state.drydocks.byColony.mgetOrPut(completed.colonyId, @[]).add(drydockId)

        # Update colony's drydock list
        var updatedColony = colony
        updatedColony.drydockIds.add(drydockId)
        state.colonies.entities.updateEntity(completed.colonyId, updatedColony)

        logInfo("Economy",
          &"Commissioned drydock {drydockId} at {completed.colonyId}")

        events.add(event_factory.buildingCompleted(
          colony.owner,
          "Drydock",
          colony.systemId
        ))

    # TODO: Ground battery commissioning needs DoD refactoring
    # Ground batteries are no longer embedded in Colony (colony.groundBatteries doesn't exist)
    # Ground defenses now use entity managers or colony fields managed via updateEntity
    # For now, ground battery construction is disabled.
    elif completed.projectType == BuildType.Facility and
         completed.itemId == "GroundBattery":
      logWarn("Economy", "Ground battery construction not yet implemented in DoD refactor")
      discard  # Skip for now

    # Special handling for planetary shields (replacement, not upgrade)
    elif completed.projectType == BuildType.Facility and
         completed.itemId.startsWith("PlanetaryShield"):
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Extract shield level from itemId (e.g., "PlanetaryShield-3" -> 3)
        # For now, assume sequential upgrades
        let newLevel = colony.planetaryShieldLevel + 1
        colony.planetaryShieldLevel = min(newLevel, 6)  # Max SLD6
        saveColony(completed.colonyId, colony)

        logInfo("Economy",
          &"Deployed planetary shield SLD{colony.planetaryShieldLevel} at {completed.colonyId} " &
          &"(Block chance: {int(getShieldBlockChance(colony.planetaryShieldLevel) * 100.0)}%)")

        events.add(event_factory.buildingCompleted(
          colony.owner,
          &"Planetary Shield SLD{colony.planetaryShieldLevel}",
          colony.systemId
        ))

    # TODO: Marine recruitment needs DoD refactoring
    # Marines are no longer embedded in Colony (colony.marines doesn't exist)
    # Ground units now use entity managers:
    # - Create Marine via state.groundUnits entity manager
    # - Link to colony via indexes
    # - Deduct souls from colony and update via updateEntity
    # For now, marine recruitment is disabled.
    elif completed.projectType == BuildType.Facility and
         (completed.itemId == "Marine" or completed.itemId == "marine_division"):
      logWarn("Economy", "Marine recruitment not yet implemented in DoD refactor")
      discard  # Skip for now

    # TODO: Army recruitment needs DoD refactoring
    # Armies are no longer embedded in Colony (colony.armies doesn't exist)
    # Ground units now use entity managers - same pattern as Marines above.
    # For now, army recruitment is disabled.
    elif completed.projectType == BuildType.Facility and
         (completed.itemId == "Army" or completed.itemId == "army"):
      logWarn("Economy", "Army recruitment not yet implemented in DoD refactor")
      discard  # Skip for now

  # Write all modified colonies back to state
  # This ensures multiple units completing at same colony see accumulated changes
  logDebug("Economy", &"Writing {modifiedColonies.len} modified colonies back to state")
  for colonyId, colony in modifiedColonies:
    state.colonies.entities.updateEntity(colonyId, colony)
    logDebug("Economy", &"  Colony {colonyId} updated")

  # TODO: Auto-loading fighters onto carriers disabled pending DoD refactor
  # This section needs to be rewritten to use squadron and ship entity managers
  discard

proc commissionShips*(
  state: var GameState,
  completedProjects: seq[CompletedProject],
  events: var seq[GameEvent]
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

  # TODO: Ship commissioning needs complete DoD refactoring
  # This 367-line proc extensively accesses embedded objects that don't exist in DoD:
  # - fleet.squadrons (should use Fleet.squadronIds + entity manager lookups)
  # - squadron.flagship (should use Squadron.flagshipId + entity manager lookups)
  # - squadron.ships (should use Squadron.ships: seq[ShipId] + entity manager lookups)
  # - state.fleets[id] (should use state.fleets.entities.getEntity(id))
  #
  # Required refactoring:
  # 1. Scout commissioning (lines 538-599) - create Ship via entity manager,
  #    create Squadron via entity manager with ShipId reference, create/update
  #    Fleet via entity manager with SquadronId references
  # 2. Spacelift (ETAC/TroopTransport) commissioning (lines 601-720) - same pattern
  # 3. Capital ship commissioning (lines 722+) - same pattern with auto-assignment logic
  # 4. Fleet auto-balancing logic - needs to work with entity managers and ID references
  # 5. Fighter squadron loading to carriers - needs DoD refactor (separate task)
  #
  # For now, ship construction is disabled. Facilities (starbases, spaceports, etc.)
  # still commission correctly via commissionPlanetaryDefense proc.
  logWarn("Economy", "Ship commissioning not yet implemented in DoD refactor")
  discard  # Skip all ship commissioning for now

  # Original code disabled - full refactoring needed

