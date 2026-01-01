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
import ../../types/[core, game_state, production, event, ground_unit]
import ../../types/[ship, colony, fleet, squadron, facilities]
import ../../state/[game_state as gs_helpers, entity_manager, id_gen]
import ../../config/[ground_units_config, facilities_config]
import ../../config/[military_config, population_config]
import ../../../common/logger
import ../ship/entity as ship_entity
import ../squadron/entity as squadron_entity
import ../capacity/carrier_hangar
import ../../event_factory/init as event_factory

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
    let starbaseOpt = state.starbases.entities.entity(starbaseId)
    if starbaseOpt.isSome:
      let starbase = starbaseOpt.get()
      if not starbase.isCrippled:
        result += 1

proc getStarbaseGrowthBonus*(state: GameState, colonyId: ColonyId): float =
  ## Calculate growth bonus from operational starbases
  ## Per specs: Each operational starbase provides growth bonus
  let operationalCount = getOperationalStarbaseCount(state, colonyId)
  result = operationalCount.float * 0.05 # 5% per starbase

proc hasSpaceport*(state: GameState, colonyId: ColonyId): bool =
  ## Check if colony has at least one spaceport using DoD
  colonyId in state.spaceports.byColony and state.spaceports.byColony[colonyId].len > 0

proc getShieldBlockChance*(shieldLevel: int): float =
  ## Calculate block chance for planetary shield level
  ## SLD1=10%, SLD2=20%, ..., SLD6=60%
  result = shieldLevel.float * 0.10

# Note: getTotalGroundDefense removed - groundBatteries is still a simple counter on Colony
# getTotalConstructionDocks and hasSpaceport moved to DoD versions above

proc autoLoadFightersToCarriers(
    state: var GameState,
    modifiedColonies: Table[ColonyId, Colony],
    events: var seq[GameEvent],
) =
  ## Auto-load newly commissioned fighters onto carriers with available hangar
  ## space. Only processes colonies with autoLoadingEnabled = true.
  ##
  ## **Design:**
  ## - Follows DoD pattern: uses entity managers for all state access
  ## - Uses carrier_hangar capacity functions for space checks
  ## - Loads fighters FIFO (oldest commissioned first)
  ## - Logs all loading operations for debugging
  ##
  ## **Integration:**
  ## - Called after all units commissioned and colonies updated
  ## - Runs before new build orders processed
  ## - Per commissioning.nim:22-24 phase ordering

  logDebug("Economy", "Starting auto-load fighters to carriers")

  for colonyId in modifiedColonies.keys:
    # Re-fetch colony from state to get current fighterSquadronIds
    # (they may have been modified by previous auto-loading operations)
    let colonyOpt = state.colonies.entities.entity(colonyId)
    if colonyOpt.isNone:
      continue

    let colony = colonyOpt.get()

    # Skip colonies without auto-loading enabled
    if not colony.autoLoadingEnabled:
      continue

    # Skip colonies with no fighters
    if colony.fighterSquadronIds.len == 0:
      continue

    let systemId = colony.systemId

    # Find fleets at this system
    if systemId notin state.fleets.bySystem:
      continue

    # Get all carrier squadrons in fleets at this system
    var carriersWithSpace: seq[tuple[squadronId: SquadronId, availableSpace: int]] = @[]

    for fleetId in state.fleets.bySystem[systemId]:
      let fleetOpt = gs_helpers.getFleet(state, fleetId)
      if fleetOpt.isNone:
        continue

      let fleet = fleetOpt.get()

      # Only load onto friendly fleets
      if fleet.houseId != colony.owner:
        continue

      # Check each squadron in fleet for carriers
      for squadronId in fleet.squadrons:
        let squadronOpt = gs_helpers.getSquadrons(state, squadronId)
        if squadronOpt.isNone:
          continue

        let squadron = squadronOpt.get()

        # Check if carrier using entity manager for flagship
        let flagshipOpt = gs_helpers.getShip(state, squadron.flagshipId)
        if flagshipOpt.isNone:
          continue

        let flagship = flagshipOpt.get()
        if not isCarrier(flagship.shipClass):
          continue

        # Check available hangar space
        let availableSpace = getAvailableHangarSpace(state, squadronId)
        if availableSpace > 0:
          carriersWithSpace.add((squadronId, availableSpace))

    # Skip if no carriers with space
    if carriersWithSpace.len == 0:
      continue

    # Load fighters onto carriers (FIFO - oldest fighters first)
    var fightersToLoad = colony.fighterSquadronIds
    var carrierIdx = 0
    var loadedCount = 0

    while fightersToLoad.len > 0 and carrierIdx < carriersWithSpace.len:
      let (carrierSquadronId, availableSpace) = carriersWithSpace[carrierIdx]

      # Load as many fighters as fit in this carrier
      var loadedToThisCarrier = 0
      while loadedToThisCarrier < availableSpace and fightersToLoad.len > 0:
        let fighterSquadronId = fightersToLoad[0]
        fightersToLoad.delete(0)

        # Get carrier squadron for updating
        let carrierSquadronOpt = state.squadrons[].entities.entity(carrierSquadronId)
        if carrierSquadronOpt.isNone:
          break

        var carrierSquadron = carrierSquadronOpt.get()

        # Add fighter to carrier's embarked fighters
        carrierSquadron.embarkedFighters.add(fighterSquadronId)
        state.squadrons.entities.updateEntity(carrierSquadronId, carrierSquadron)

        # Remove fighter from colony
        # Note: We need to re-fetch colony from state since it may have been
        # updated by previous iterations
        let colonyOpt = state.colonies.entities.entity(colonyId)
        if colonyOpt.isSome:
          var updatedColony = colonyOpt.get()
          # Filter out the loaded fighter squadron
          var newFighterIds: seq[SquadronId] = @[]
          for fId in updatedColony.fighterSquadronIds:
            if fId != fighterSquadronId:
              newFighterIds.add(fId)
          updatedColony.fighterSquadronIds = newFighterIds
          state.colonies.entities.updateEntity(colonyId, updatedColony)

        loadedToThisCarrier += 1
        loadedCount += 1

        logDebug(
          "Economy",
          &"Auto-loaded fighter {fighterSquadronId} to carrier " &
            &"{carrierSquadronId} at {systemId}",
        )

      # Move to next carrier
      carrierIdx += 1

    if loadedCount > 0:
      logInfo("Economy", &"Auto-loaded {loadedCount} fighter squadron(s) at {systemId}")

      # Emit event for tracking
      events.add(
        event_factory.unitRecruited(
          colony.owner, "Fighter Squadron (auto-loaded)", systemId, loadedCount
        )
      )

proc commissionPlanetaryDefense*(
    state: var GameState,
    completedProjects: seq[CompletedProject],
    events: var seq[GameEvent],
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
    logInfo(
      "Economy",
      &"Commissioning planetary defense: {completed.projectType} itemId={completed.itemId} at system-{completed.colonyId}",
    )

    # Special handling for Fighters (planetary defense squadrons)
    if (
      completed.projectType == BuildType.Facility and
      completed.itemId == "FighterSquadron"
    ) or (completed.projectType == BuildType.Ship and completed.itemId == "Fighter"):
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Get house tech level
        let houseOpt = gs_helpers.getHouse(state, colony.owner)
        if houseOpt.isNone:
          continue
        let house = houseOpt.get()
        let techLevel = house.techTree.levels.wep

        # Create 12 fighter ships (squadron strength)
        var fighterShipIds: seq[ShipId] = @[]
        for i in 0 ..< 12:
          let shipId = generateShipId(state)
          let ship =
            ship_entity.newShip(ShipClass.Fighter, techLevel, "", shipId, SquadronId(0))
          state.ships.entities.addEntity(shipId, ship)
          fighterShipIds.add(shipId)

        # Create fighter squadron (use first fighter as "flagship" reference)
        let squadronId = generateSquadronId(state)
        let squadron = squadron_entity.newSquadron(
          fighterShipIds[0],
          ShipClass.Fighter,
          squadronId,
          colony.owner,
          colony.systemId,
        )
        state.squadrons.entities.addEntity(squadronId, squadron)

        # Update all fighter ships with squadronId
        for shipId in fighterShipIds:
          var ship = state.ships.entities.entity(shipId).get()
          ship.squadronId = squadronId
          state.ships.entities.updateEntity(shipId, ship)

        # Link squadron to colony
        colony.fighterSquadronIds.add(squadronId)
        state.colonies.entities.updateEntity(completed.colonyId, colony)

        logInfo(
          "Economy",
          &"Commissioned Fighter Squadron {squadronId} at {completed.colonyId} " &
            &"(12 fighters, planetary defense)",
        )

        # Generate event
        events.add(
          event_factory.buildingCompleted(
            colony.owner, "Fighter Squadron", colony.systemId
          )
        )

    # Special handling for starbases
    elif completed.projectType == BuildType.Facility and completed.itemId == "Starbase":
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
          isCrippled: false,
        )

        # Add to entity manager and update indexes
        state.starbases.entities.addEntity(starbaseId, starbase)
        state.starbases.byColony.mgetOrPut(completed.colonyId, @[]).add(starbaseId)

        # Update colony's starbase list
        var updatedColony = colony
        updatedColony.starbaseIds.add(starbaseId)
        state.colonies.entities.updateEntity(completed.colonyId, updatedColony)

        logInfo(
          "Economy",
          &"Commissioned starbase {starbaseId} at {completed.colonyId} " &
            &"(Total operational: {getOperationalStarbaseCount(state, completed.colonyId)}, " &
            &"Growth bonus: {int(getStarbaseGrowthBonus(state, completed.colonyId) * 100.0)}%)",
        )

        # Generate event
        events.add(
          event_factory.buildingCompleted(colony.owner, "Starbase", colony.systemId)
        )

    # Special handling for spaceports
    elif completed.projectType == BuildType.Facility and completed.itemId == "Spaceport":
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Create new spaceport (docks from facilities_config.toml, scaled by CST)
        let baseDocks = globalFacilitiesConfig.facilities[FacilityClass.Spaceport].docks
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
          activeConstructions: @[],
        )

        # Add to entity manager and update indexes
        state.spaceports.entities.addEntity(spaceportId, spaceport)
        state.spaceports.byColony.mgetOrPut(completed.colonyId, @[]).add(spaceportId)

        # Update colony's spaceport list
        var updatedColony = colony
        updatedColony.spaceportIds.add(spaceportId)
        state.colonies.entities.updateEntity(completed.colonyId, updatedColony)

        logInfo(
          "Economy", &"Commissioned spaceport {spaceportId} at {completed.colonyId}"
        )

        events.add(
          event_factory.buildingCompleted(colony.owner, "Spaceport", colony.systemId)
        )

    # Special handling for shipyards
    elif completed.projectType == BuildType.Facility and completed.itemId == "Shipyard":
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Validate spaceport prerequisite
        if not hasSpaceport(state, completed.colonyId):
          logError(
            "Economy",
            &"Shipyard construction failed - no spaceport at {completed.colonyId}",
          )
          # This shouldn't happen if build validation worked correctly
          continue

        # Create new shipyard (docks from facilities_config.toml, scaled by CST)
        let baseDocks = globalFacilitiesConfig.facilities[FacilityClass.Shipyard].docks
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
          activeConstructions: @[],
        )

        # Add to entity manager and update indexes
        state.shipyards.entities.addEntity(shipyardId, shipyard)
        state.shipyards.byColony.mgetOrPut(completed.colonyId, @[]).add(shipyardId)

        # Update colony's shipyard list
        var updatedColony = colony
        updatedColony.shipyardIds.add(shipyardId)
        state.colonies.entities.updateEntity(completed.colonyId, updatedColony)

        logInfo(
          "Economy", &"Commissioned shipyard {shipyardId} at {completed.colonyId}"
        )

        events.add(
          event_factory.buildingCompleted(colony.owner, "Shipyard", colony.systemId)
        )

    # Special handling for drydocks
    elif completed.projectType == BuildType.Facility and completed.itemId == "Drydock":
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Validate spaceport prerequisite
        if not hasSpaceport(state, completed.colonyId):
          logError(
            "Economy",
            &"Drydock construction failed - no spaceport at {completed.colonyId}",
          )
          # This shouldn't happen if build validation worked correctly
          continue

        # Create new drydock (docks from facilities_config.toml, scaled by CST)
        let baseDocks = globalFacilitiesConfig.facilities[FacilityClass.Drydock].docks
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
          activeRepairs: @[],
        )

        # Add to entity manager and update indexes
        state.drydocks.entities.addEntity(drydockId, drydock)
        state.drydocks.byColony.mgetOrPut(completed.colonyId, @[]).add(drydockId)

        # Update colony's drydock list
        var updatedColony = colony
        updatedColony.drydockIds.add(drydockId)
        state.colonies.entities.updateEntity(completed.colonyId, updatedColony)

        logInfo("Economy", &"Commissioned drydock {drydockId} at {completed.colonyId}")

        events.add(
          event_factory.buildingCompleted(colony.owner, "Drydock", colony.systemId)
        )

    # Special handling for ground batteries
    elif completed.projectType == BuildType.Facility and
        completed.itemId == "GroundBattery":
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Create ground battery
        let unitId = generateGroundUnitId(state)
        let battery = GroundUnit(
          id: unitId,
          unitType: GroundClass.GroundBattery,
          owner: colony.owner,
          attackStrength: int32(globalGroundUnitsConfig.units[GroundClass.GroundBattery].attack_strength),
          defenseStrength:
            int32(globalGroundUnitsConfig.units[GroundClass.GroundBattery].defense_strength),
          state: CombatState.Undamaged,
        )
        state.groundUnits.entities.addEntity(unitId, battery)

        # Link to colony
        colony.groundBatteryIds.add(unitId)
        state.colonies.entities.updateEntity(completed.colonyId, colony)

        logInfo(
          "Economy",
          &"Deployed ground battery at {completed.colonyId} " &
            &"(Total ground defenses: {colony.groundBatteryIds.len} batteries)",
        )

        events.add(
          event_factory.buildingCompleted(
            colony.owner, "Ground Battery", colony.systemId
          )
        )

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
        colony.planetaryShieldLevel = min(newLevel, 6) # Max SLD6
        saveColony(completed.colonyId, colony)

        logInfo(
          "Economy",
          &"Deployed planetary shield SLD{colony.planetaryShieldLevel} at {completed.colonyId} " &
            &"(Block chance: {int(getShieldBlockChance(colony.planetaryShieldLevel) * 100.0)}%)",
        )

        events.add(
          event_factory.buildingCompleted(
            colony.owner,
            &"Planetary Shield SLD{colony.planetaryShieldLevel}",
            colony.systemId,
          )
        )

    # Special handling for Marines (MD)
    elif completed.projectType == BuildType.Facility and
        (completed.itemId == "Marine" or completed.itemId == "marine_division"):
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Get population cost from config
        let marinePopCost = globalGroundUnitsConfig.units[GroundClass.Marine].population_cost
        let minViablePop = population_config.minViablePopulation()

        if colony.souls < marinePopCost:
          logWarn(
            "Economy",
            &"Colony {completed.colonyId} lacks population to recruit Marines " &
              &"({colony.souls} souls < {marinePopCost})",
          )
        elif colony.souls - marinePopCost < minViablePop:
          logWarn(
            "Economy",
            &"Colony {completed.colonyId} cannot recruit Marines - would leave colony below minimum viable size " &
              &"({colony.souls - marinePopCost} < {minViablePop} souls)",
          )
        else:
          # Create marine ground unit
          let unitId = generateGroundUnitId(state)
          let marine = GroundUnit(
            id: unitId,
            unitType: GroundClass.Marine,
            owner: colony.owner,
            attackStrength:
              int32(globalGroundUnitsConfig.units[GroundClass.Marine].attack_strength),
            defenseStrength:
              int32(globalGroundUnitsConfig.units[GroundClass.Marine].defense_strength),
            state: CombatState.Undamaged,
          )
          state.groundUnits.entities.addEntity(unitId, marine)

          # Link to colony
          colony.marineIds.add(unitId)

          # Deduct recruited souls
          colony.souls -= int32(marinePopCost)
          colony.population = colony.souls div 1_000_000
          state.colonies.entities.updateEntity(completed.colonyId, colony)

          logInfo(
            "Economy",
            &"Recruited Marine Division at {completed.colonyId} " &
              &"(Total Marines: {colony.marineIds.len} MD, {colony.souls} souls remaining)",
          )

          events.add(
            event_factory.unitRecruited(
              colony.owner, "Marine Division", colony.systemId, 1
            )
          )

    # Special handling for Armies (AA)
    elif completed.projectType == BuildType.Facility and
        (completed.itemId == "Army" or completed.itemId == "army"):
      if completed.colonyId in state.colonies.entities.index:
        let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Get population cost from config
        let armyPopCost = globalGroundUnitsConfig.units[GroundClass.Army].population_cost
        let minViablePop = population_config.minViablePopulation()

        if colony.souls < armyPopCost:
          logWarn(
            "Economy",
            &"Colony {completed.colonyId} lacks population to muster Army " &
              &"({colony.souls} souls < {armyPopCost})",
          )
        elif colony.souls - armyPopCost < minViablePop:
          logWarn(
            "Economy",
            &"Colony {completed.colonyId} cannot muster Army - would leave colony below minimum viable size " &
              &"({colony.souls - armyPopCost} < {minViablePop} souls)",
          )
        else:
          # Create army ground unit
          let unitId = generateGroundUnitId(state)
          let army = GroundUnit(
            id: unitId,
            unitType: GroundClass.Army,
            owner: colony.owner,
            attackStrength: int32(globalGroundUnitsConfig.units[GroundClass.Army].attack_strength),
            defenseStrength: int32(globalGroundUnitsConfig.units[GroundClass.Army].defense_strength),
            state: CombatState.Undamaged,
          )
          state.groundUnits.entities.addEntity(unitId, army)

          # Link to colony
          colony.armyIds.add(unitId)

          # Deduct recruited souls
          colony.souls -= int32(armyPopCost)
          colony.population = colony.souls div 1_000_000
          state.colonies.entities.updateEntity(completed.colonyId, colony)

          logInfo(
            "Economy",
            &"Mustered Army Division at {completed.colonyId} " &
              &"(Total Armies: {colony.armyIds.len} AA, {colony.souls} souls remaining)",
          )

          events.add(
            event_factory.unitRecruited(
              colony.owner, "Army Division", colony.systemId, 1
            )
          )

  # Write all modified colonies back to state
  # This ensures multiple units completing at same colony see accumulated changes
  logDebug("Economy", &"Writing {modifiedColonies.len} modified colonies back to state")
  for colonyId, colony in modifiedColonies:
    state.colonies.entities.updateEntity(colonyId, colony)
    logDebug("Economy", &"  Colony {colonyId} updated")

  # Auto-load fighters onto carriers with available hangar space
  # Per phase ordering (commissioning.nim:22-24), this happens after
  # commissioning but before new build orders
  autoLoadFightersToCarriers(state, modifiedColonies, events)

proc commissionScout(
    state: var GameState,
    owner: HouseId,
    systemId: SystemId,
    techLevel: int32,
    events: var seq[GameEvent],
) =
  ## Commission a Scout ship in a dedicated scout fleet
  ## Scouts at the same system join the same fleet for mesh network bonuses

  # 1. Create the scout ship
  let shipId = generateShipId(state)
  let ship = ship_entity.newShip(ShipClass.Scout, techLevel, "", shipId, SquadronId(0))
  state.ships.entities.addEntity(shipId, ship)

  # 2. Create squadron with scout as flagship
  let squadronId = generateSquadronId(state)
  let squadron =
    squadron_entity.newSquadron(shipId, ShipClass.Scout, squadronId, owner, systemId)
  state.squadrons.entities.addEntity(squadronId, squadron)

  # Update ship with correct squadronId
  var updatedShip = ship
  updatedShip.squadronId = squadronId
  state.ships.entities.updateEntity(shipId, updatedShip)

  # 3. Find existing scout fleet at this location, or create new one
  var scoutFleetId: FleetId = FleetId(0)

  if systemId in state.fleets.bySystem:
    for fleetId in state.fleets.bySystem[systemId]:
      let fleetOpt = gs_helpers.getFleet(state, fleetId)
      if fleetOpt.isNone:
        continue
      let fleet = fleetOpt.get()

      if fleet.houseId != owner:
        continue

      # Check if this is a pure scout fleet (only scout squadrons)
      var isPureScoutFleet = fleet.squadrons.len > 0
      for sqId in fleet.squadrons:
        let sqOpt = gs_helpers.getSquadrons(state, sqId)
        if sqOpt.isNone:
          isPureScoutFleet = false
          break
        let sq = sqOpt.get()
        if sq.squadronType != SquadronClass.Intel:
          isPureScoutFleet = false
          break

      if isPureScoutFleet:
        scoutFleetId = fleetId
        break

  # 4. Add squadron to fleet (existing or new)
  if scoutFleetId != FleetId(0):
    # Add to existing scout fleet
    var fleet = gs_helpers.getFleet(state, scoutFleetId).get()
    fleet.squadrons.add(squadronId)
    state.fleets.entities.updateEntity(scoutFleetId, fleet)

    logInfo(
      "Fleet",
      &"Commissioned Scout in existing fleet {scoutFleetId} at {systemId} " &
        &"({fleet.squadrons.len} scouts, mesh network bonus)",
    )
  else:
    # Create new scout fleet
    scoutFleetId = generateFleetId(state)
    let fleet = Fleet(
      id: scoutFleetId, houseId: owner, location: systemId, squadrons: @[squadronId]
    )
    state.fleets.entities.addEntity(scoutFleetId, fleet)
    state.fleets.bySystem.mgetOrPut(systemId, @[]).add(scoutFleetId)
    state.fleets.byOwner.mgetOrPut(owner, @[]).add(scoutFleetId)

    logInfo(
      "Fleet", &"Commissioned Scout in new dedicated fleet {scoutFleetId} at {systemId}"
    )

  # 5. Update squadron.byFleet index
  state.squadrons.byFleet.mgetOrPut(scoutFleetId, @[]).add(squadronId)

  # 6. Generate event
  events.add(event_factory.shipCommissioned(owner, ShipClass.Scout, systemId))

proc commissionSpaceLift(
    state: var GameState,
    owner: HouseId,
    systemId: SystemId,
    shipClass: ShipClass,
    techLevel: int32,
    events: var seq[GameEvent],
) =
  ## Commission a spacelift ship (ETAC or TroopTransport)
  ## These form single-ship squadrons in dedicated fleets

  # 1. Create the ship
  let shipId = generateShipId(state)
  var ship = ship_entity.newShip(shipClass, techLevel, "", shipId, SquadronId(0))

  # Initialize cargo for spacelift ships
  if shipClass == ShipClass.ETAC:
    # ETACs commission with full cargo (cryostasis colonists)
    let cargoCapacity = ship.baseCarryLimit()
    ship.initCargo(CargoClass.Colonists, cargoCapacity)
    discard ship.loadCargo(cargoCapacity)
    logInfo(
      "Economy",
      &"Commissioned ETAC with {cargoCapacity} PTU (cryostasis generation ship)",
    )
  elif shipClass == ShipClass.TroopTransport:
    # TroopTransports start empty (marines loaded later)
    let cargoCapacity = ship.baseCarryLimit()
    ship.initCargo(CargoClass.Marines, cargoCapacity)

  state.ships.entities.addEntity(shipId, ship)

  # 2. Create squadron with spacelift ship as flagship
  let squadronId = generateSquadronId(state)
  let squadron =
    squadron_entity.newSquadron(shipId, shipClass, squadronId, owner, systemId)
  state.squadrons.entities.addEntity(squadronId, squadron)

  # Update ship with correct squadronId
  var updatedShip = ship
  updatedShip.squadronId = squadronId
  state.ships.entities.updateEntity(shipId, updatedShip)

  # 3. Create new fleet for this spacelift ship
  let fleetId = generateFleetId(state)
  let fleet =
    Fleet(id: fleetId, houseId: owner, location: systemId, squadrons: @[squadronId])
  state.fleets.entities.addEntity(fleetId, fleet)
  state.fleets.bySystem.mgetOrPut(systemId, @[]).add(fleetId)
  state.fleets.byOwner.mgetOrPut(owner, @[]).add(fleetId)

  # 4. Update squadron.byFleet index
  state.squadrons.byFleet.mgetOrPut(fleetId, @[]).add(squadronId)

  logInfo("Fleet", &"Commissioned {shipClass} in new fleet {fleetId} at {systemId}")

  # 5. Generate event
  events.add(event_factory.shipCommissioned(owner, shipClass, systemId))

proc commissionCapitalShip(
    state: var GameState,
    owner: HouseId,
    systemId: SystemId,
    shipClass: ShipClass,
    techLevel: int32,
    events: var seq[GameEvent],
) =
  ## Commission a capital ship (Corvette, Frigate, Destroyer, Cruiser, etc.)
  ## Capital ships join existing combat fleets or form new fleets

  # 1. Create the capital ship
  let shipId = generateShipId(state)
  let ship = ship_entity.newShip(shipClass, techLevel, "", shipId, SquadronId(0))
  state.ships.entities.addEntity(shipId, ship)

  # 2. Create squadron with capital ship as flagship
  let squadronId = generateSquadronId(state)
  let squadron =
    squadron_entity.newSquadron(shipId, shipClass, squadronId, owner, systemId)
  state.squadrons.entities.addEntity(squadronId, squadron)

  # Update ship with correct squadronId
  var updatedShip = ship
  updatedShip.squadronId = squadronId
  state.ships.entities.updateEntity(shipId, updatedShip)

  # 3. Find existing combat fleet at this location, or create new one
  var combatFleetId: FleetId = FleetId(0)

  if systemId in state.fleets.bySystem:
    for fleetId in state.fleets.bySystem[systemId]:
      let fleetOpt = gs_helpers.getFleet(state, fleetId)
      if fleetOpt.isNone:
        continue
      let fleet = fleetOpt.get()

      if fleet.houseId != owner:
        continue

      # Check if this is a combat fleet (not pure scout/spacelift)
      # Combat fleets contain capital ships and/or fighters
      var isCombatFleet = false
      for sqId in fleet.squadrons:
        let sqOpt = gs_helpers.getSquadrons(state, sqId)
        if sqOpt.isNone:
          continue
        let sq = sqOpt.get()

        # Combat fleet types: Combat (capital ships), Fighter
        if sq.squadronType in [SquadronClass.Combat, SquadronClass.Fighter]:
          isCombatFleet = true
          break

      if isCombatFleet:
        combatFleetId = fleetId
        break

  # 4. Add squadron to fleet (existing or new)
  if combatFleetId != FleetId(0):
    # Add to existing combat fleet
    var fleet = gs_helpers.getFleet(state, combatFleetId).get()
    fleet.squadrons.add(squadronId)
    state.fleets.entities.updateEntity(combatFleetId, fleet)

    logInfo(
      "Fleet",
      &"Commissioned {shipClass} in existing fleet {combatFleetId} " &
        &"at {systemId} ({fleet.squadrons.len} squadrons)",
    )
  else:
    # Create new combat fleet
    combatFleetId = generateFleetId(state)
    let fleet = Fleet(
      id: combatFleetId, houseId: owner, location: systemId, squadrons: @[squadronId]
    )
    state.fleets.entities.addEntity(combatFleetId, fleet)
    state.fleets.bySystem.mgetOrPut(systemId, @[]).add(combatFleetId)
    state.fleets.byOwner.mgetOrPut(owner, @[]).add(combatFleetId)

    logInfo(
      "Fleet", &"Commissioned {shipClass} in new fleet {combatFleetId} at {systemId}"
    )

  # 5. Update squadron.byFleet index
  state.squadrons.byFleet.mgetOrPut(combatFleetId, @[]).add(squadronId)

  # 6. Generate event
  events.add(event_factory.shipCommissioned(owner, shipClass, systemId))

proc commissionShips*(
    state: var GameState,
    completedProjects: seq[CompletedProject],
    events: var seq[GameEvent],
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

  # Process each completed ship construction project
  for completed in completedProjects:
    if completed.projectType != BuildType.Ship:
      continue # Only handle ship construction here

    logInfo(
      "Economy",
      &"Commissioning ship: {completed.itemId} at system-{completed.colonyId}",
    )

    # Get colony and owner
    let colonyOpt = gs_helpers.getColony(state, completed.colonyId)
    if colonyOpt.isNone:
      logWarn(
        "Economy", &"Cannot commission ship - colony {completed.colonyId} not found"
      )
      continue
    let colony = colonyOpt.get()
    let owner = colony.owner

    # Parse ship class from itemId
    try:
      let shipClass = parseEnum[ShipClass](completed.itemId)

      # Get house tech level for ship stats
      let houseOpt = gs_helpers.getHouse(state, owner)
      if houseOpt.isNone:
        logWarn("Economy", &"Cannot commission ship - house {owner} not found")
        continue
      let house = houseOpt.get()
      let techLevel = house.techTree.levels.wep

      # Commission ship based on type
      case shipClass
      of ShipClass.Scout:
        # Scouts form dedicated single-ship fleets
        # Multiple scouts at same colony join same fleet for mesh network bonuses
        commissionScout(state, owner, colony.systemId, techLevel, events)
      of ShipClass.ETAC, ShipClass.TroopTransport:
        # Spacelift ships form single-ship squadrons
        commissionSpaceLift(state, owner, colony.systemId, shipClass, techLevel, events)
      else:
        # Capital ships and other combat vessels
        commissionCapitalShip(
          state, owner, colony.systemId, shipClass, techLevel, events
        )
    except ValueError:
      logError("Economy", &"Invalid ship class: {completed.itemId}")
