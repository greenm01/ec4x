## Commissioning System - Converting completed construction into operational units
##
## This module handles the commissioning of completed construction projects into
## operational military units and facilities. It runs as the FIRST step in the
## Command Phase, before new build commands are processed.
##
## **Design Rationale:**
## Commissioning must occur before build commands to ensure clean capacity calculations.
## When a shipyard completes a destroyer, that dock space becomes available for new
## construction commands submitted the same turn. By commissioning first, we eliminate
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
##   3. Process new build commands
##   4. ... rest of Command Phase ...
## ```
##
## **Handles:**
## - Fighters → colony.fighterIds (colony-based fighters)
## - Starbases → colony.starbases
## - Spaceports/Shipyards → colony facilities
## - Ground units (Marines/Armies) → colony forces
## - Ground defenses (batteries/shields) → colony defenses
## - Capital ships → fleets (auto-assigned)
## - Spacelift ships (ETAC/Transports) → fleets
##
## **Does NOT Handle:**
## - Auto-loading fighters to carriers (separate function)
## - Construction queue advancement (happens in Maintenance Phase)

import std/[tables, options, strformat, strutils, sequtils]
import ../../types/[core, game_state, production, event, ground_unit, combat]
import ../../types/[ship, colony, fleet, facilities]
import ../../state/[engine, id_gen, iterators]
import ../../entities/[neoria_ops, kastra_ops, ship_ops, fleet_ops]
import ../../globals
import ../../utils
import ../../../common/logger
import ../capacity/carrier_hangar
import ../../event_factory/init as event_factory

# Helper functions using DoD patterns
proc getOperationalStarbaseCount*(state: GameState, colonyId: ColonyId): int =
  ## Count non-crippled kastra (starbases) for a colony using DoD entity manager
  result = 0
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return 0

  let colony = colonyOpt.get()
  for kastraId in colony.kastraIds:
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isSome:
      let kastra = kastraOpt.get()
      if kastra.state != CombatState.Crippled:
        result += 1

proc getStarbaseGrowthBonus*(state: GameState, colonyId: ColonyId): float =
  ## Calculate growth bonus from operational starbases
  ## Per specs: Each operational starbase provides growth bonus
  let operationalCount = getOperationalStarbaseCount(state, colonyId)
  result = operationalCount.float * 0.05 # 5% per starbase

proc hasSpaceport*(state: GameState, colonyId: ColonyId): bool =
  ## Check if colony has at least one spaceport using DoD
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return false

  let colony = colonyOpt.get()
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome and neoriaOpt.get().neoriaClass == NeoriaClass.Spaceport:
      return true

  return false

proc getShieldBlockChance*(shieldLevel: int): float =
  ## Calculate block chance for planetary shield level
  ## SLD1=10%, SLD2=20%, ..., SLD6=60%
  result = shieldLevel.float * 0.10

proc countGroundUnits(state: GameState, colony: Colony, unitType: GroundClass): int =
  ## Count ground units of specific type in colony
  var count = 0
  for unitId in colony.groundUnitIds:
    let unitOpt = state.groundUnit(unitId)
    if unitOpt.isSome and unitOpt.get().stats.unitType == unitType:
      count += 1
  return count

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
  ## - Runs before new build commands processed
  ## - Per commissioning.nim:22-24 phas commanding

  logDebug("Economy", "Starting auto-load fighters to carriers")

  for colonyId in modifiedColonies.keys:
    # Re-fetch colony from state to get current fighterIds
    # (they may have been modified by previous auto-loading operations)
    let colonyOpt = state.colony(colonyId)
    if colonyOpt.isNone:
      continue

    let colony = colonyOpt.get()

    # Skip colonies without auto-loading enabled
    if not colony.autoLoadingEnabled:
      continue

    # Skip colonies with no fighters
    if colony.fighterIds.len == 0:
      continue

    let systemId = colony.systemId

    # Get all carriers in fleets at this system with available space
    var carriersWithSpace: seq[tuple[carrierId: ShipId, availableSpace: int32]] = @[]

    for fleet in state.fleetsAtSystem(systemId):
      # Only load onto friendly fleets
      if fleet.houseId != colony.owner:
        continue

      # Check each ship in fleet for carriers
      for shipId in fleet.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isNone:
          continue

        let ship = shipOpt.get()
        if not isCarrier(ship.shipClass):
          continue

        # Check available hangar space
        let availableSpace = getAvailableHangarSpace(state, shipId)
        if availableSpace > 0:
          carriersWithSpace.add((shipId, availableSpace))

    # Skip if no carriers with space
    if carriersWithSpace.len == 0:
      continue

    # Load fighters onto carriers (FIFO - oldest fighters first)
    var fightersToLoad = colony.fighterIds
    var carrierIdx = 0
    var loadedCount = 0

    while fightersToLoad.len > 0 and carrierIdx < carriersWithSpace.len:
      let (carrierId, availableSpace) = carriersWithSpace[carrierIdx]

      # Load as many fighters as fit in this carrier
      var loadedToThisCarrier = 0
      while loadedToThisCarrier < availableSpace and fightersToLoad.len > 0:
        let fighterId = fightersToLoad[0]
        fightersToLoad.delete(0)

        # Assign fighter to carrier using ship_ops
        ship_ops.assignFighterToCarrier(state, fighterId, carrierId)

        # Remove fighter from colony
        let colonyOpt = state.colony(colonyId)
        if colonyOpt.isSome:
          var updatedColony = colonyOpt.get()
          updatedColony.fighterIds = updatedColony.fighterIds.filterIt(it != fighterId)
          state.updateColony(colonyId, updatedColony)

        loadedToThisCarrier += 1
        loadedCount += 1

        logDebug(
          "Economy",
          &"Auto-loaded fighter {fighterId} to carrier {carrierId} at {systemId}",
        )

      # Move to next carrier
      carrierIdx += 1

    if loadedCount > 0:
      logInfo("Economy", &"Auto-loaded {loadedCount} fighter(s) at {systemId}")

      # Emit event for tracking
      events.add(
        event_factory.unitRecruited(
          colony.owner, "Fighters (auto-loaded)", systemId, loadedCount
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
  ## - Fighters → colony.fighterIds (planetside construction)
  ## - Starbases → colony.starbases (orbital defense)
  ## - Facilities → colony.spaceports/shipyards/drydocks
  ## - Ground defenses → colony.groundUnitIds (GroundBattery, PlanetaryShield units)
  ## - Ground forces → colony.marines/armies
  ##
  ## **Strategic Rationale:** Planetary assets commission immediately so defenders
  ## can respond to threats arriving next turn's Conflict Phase.
  ##
  ## **Called From:** resolveProductionPhase() in turn_cycle/production_phase.nim
  ## **Called After:** Construction queue advancement
  ## **Called Before:** Turn boundary (military units commission next turn)

  # Use same modified colonies pattern as original function
  var modifiedColonies = initTable[ColonyId, Colony]()

  for completed in completedProjects:
    logInfo(
      "Economy",
      &"Commissioning planetary defense: {completed.projectType} itemId={completed.itemId} at system-{completed.colonyId}",
    )

    # Special handling for Fighters (planetary defense, colony-based)
    if (
      completed.projectType == BuildType.Facility and
      completed.itemId == "FighterSquadron"
    ) or (completed.projectType == BuildType.Ship and completed.itemId == "Fighter"):
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Get house tech level
        let houseOpt = state.house(colony.owner)
        if houseOpt.isNone:
          continue
        let house = houseOpt.get()
        let techLevel = house.techTree.levels.wep

        # Create 12 individual fighter ships (squadron strength)
        # Fighters are unassigned (fleetId = 0) and colony-based
        var fighterShipIds: seq[ShipId] = @[]
        for i in 0 ..< 12:
          let shipId = state.generateShipId()
          let ship =
            ship_ops.newShip(ShipClass.Fighter, techLevel, shipId, FleetId(0), colony.owner)
          state.addShip(shipId, ship)
          ship_ops.registerShipIndexes(state, shipId)
          fighterShipIds.add(shipId)
          colony.fighterIds.add(shipId)

        state.updateColony(completed.colonyId, colony)

        logInfo(
          "Economy",
          &"Commissioned 12 Fighter ships at {completed.colonyId} " &
            &"(planetary defense, colony-based)",
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
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Get house WEP level for tech-modified stats
        let houseOpt = state.house(colony.owner)
        if houseOpt.isNone:
          continue
        let house = houseOpt.get()
        let wepLevel = house.techTree.levels.wep

        # Create Kastra with WEP-modified stats
        var updatedColony = colony
        let kastra = createKastra(state, completed.colonyId, KastraClass.Starbase, wepLevel)
        updatedColony.kastraIds.add(kastra.id)

        state.updateColony(completed.colonyId, updatedColony)

        logInfo(
          "Economy",
          &"Commissioned kastra {kastra.id} at {completed.colonyId} " &
            &"(Total operational: {getOperationalStarbaseCount(state, completed.colonyId)}, " &
            &"Growth bonus: {int(getStarbaseGrowthBonus(state, completed.colonyId) * 100.0)}%)",
        )

        # Generate event
        events.add(
          event_factory.buildingCompleted(colony.owner, "Starbase", colony.systemId)
        )

    # Special handling for spaceports
    elif completed.projectType == BuildType.Facility and completed.itemId == "Spaceport":
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Create new spaceport (docks from facilities_config.toml, scaled by CST)
        let houseOpt = state.house(colony.owner)
        if houseOpt.isNone:
          continue

        # Create Neoria (production facility)
        var updatedColony = colony
        let neoria = createNeoria(state, completed.colonyId, NeoriaClass.Spaceport)
        updatedColony.neoriaIds.add(neoria.id)

        state.updateColony(completed.colonyId, updatedColony)

        logInfo(
          "Economy", &"Commissioned spaceport (neoria {neoria.id}) at {completed.colonyId}"
        )

        events.add(
          event_factory.buildingCompleted(colony.owner, "Spaceport", colony.systemId)
        )

    # Special handling for shipyards
    elif completed.projectType == BuildType.Facility and completed.itemId == "Shipyard":
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
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
        let houseOpt = state.house(colony.owner)
        if houseOpt.isNone:
          continue

        # Create Neoria (production facility)
        var updatedColony = colony
        let neoria = createNeoria(state, completed.colonyId, NeoriaClass.Shipyard)
        updatedColony.neoriaIds.add(neoria.id)

        state.updateColony(completed.colonyId, updatedColony)

        logInfo(
          "Economy", &"Commissioned shipyard (neoria {neoria.id}) at {completed.colonyId}"
        )

        events.add(
          event_factory.buildingCompleted(colony.owner, "Shipyard", colony.systemId)
        )

    # Special handling for drydocks
    elif completed.projectType == BuildType.Facility and completed.itemId == "Drydock":
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
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
        let houseOpt = state.house(colony.owner)
        if houseOpt.isNone:
          continue

        # Create Neoria (production facility)
        var updatedColony = colony
        let neoria = createNeoria(state, completed.colonyId, NeoriaClass.Drydock)
        updatedColony.neoriaIds.add(neoria.id)

        state.updateColony(completed.colonyId, updatedColony)

        logInfo("Economy", &"Commissioned drydock (neoria {neoria.id}) at {completed.colonyId}")

        events.add(
          event_factory.buildingCompleted(colony.owner, "Drydock", colony.systemId)
        )

    # Special handling for ground batteries
    elif completed.projectType == BuildType.Facility and
        completed.itemId == "GroundBattery":
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Get updated colony for count
        let updatedColonyOpt = state.colony(completed.colonyId)
        if updatedColonyOpt.isSome:
          let updatedColony = updatedColonyOpt.get()
          let batteryCount = countGroundUnits(state, updatedColony, GroundClass.GroundBattery)

          logInfo(
            "Economy",
            &"Deployed ground battery at {completed.colonyId} " &
              &"(Total ground defenses: {batteryCount} batteries)",
          )

        events.add(
          event_factory.buildingCompleted(
            colony.owner, "Ground Battery", colony.systemId
          )
        )

    # Special handling for planetary shields (replacement, not upgrade)
    elif completed.projectType == BuildType.Facility and
        completed.itemId.startsWith("PlanetaryShield"):
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Get house SLD tech level for logging
        let houseOpt = state.house(colony.owner)
        let sldLevel = if houseOpt.isSome: houseOpt.get().techTree.levels.sld else: 1

        logInfo(
          "Economy",
          &"Deployed planetary shield SLD{sldLevel} at {completed.colonyId} " &
            &"(Block chance: {int(getShieldBlockChance(sldLevel) * 100.0)}%)",
        )

        events.add(
          event_factory.buildingCompleted(
            colony.owner,
            &"Planetary Shield SLD{sldLevel}",
            colony.systemId,
          )
        )

    # Special handling for Marines (MD)
    elif completed.projectType == BuildType.Facility and
        (completed.itemId == "Marine" or completed.itemId == "marine_division"):
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Get population cost from config
        let marinePopCost = gameConfig.groundUnits.units[GroundClass.Marine].populationCost
        let minViablePop = minViablePopulation()

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
          # Get colony again to deduct population (createGroundUnit updated it)
          let colonyOpt2 = state.colony(completed.colonyId)
          if colonyOpt2.isSome:
            var updatedColony = colonyOpt2.get()

            # Deduct recruited souls
            updatedColony.souls -= int32(marinePopCost)
            updatedColony.population = updatedColony.souls div 1_000_000
            state.updateColony(completed.colonyId, updatedColony)

            let marineCount = countGroundUnits(state, updatedColony, GroundClass.Marine)

            logInfo(
              "Economy",
              &"Recruited Marine Division at {completed.colonyId} " &
                &"(Total Marines: {marineCount} MD, {updatedColony.souls} souls remaining)",
            )

            events.add(
              event_factory.unitRecruited(
                updatedColony.owner, "Marine Division", updatedColony.systemId, 1
              )
            )

    # Special handling for Armies (AA)
    elif completed.projectType == BuildType.Facility and
        (completed.itemId == "Army" or completed.itemId == "army"):
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Get population cost from config
        let armyPopCost = gameConfig.groundUnits.units[GroundClass.Army].populationCost
        let minViablePop = minViablePopulation()

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
          # Get colony again to deduct population (createGroundUnit updated it)
          let colonyOpt2 = state.colony(completed.colonyId)
          if colonyOpt2.isSome:
            var updatedColony = colonyOpt2.get()

            # Deduct recruited souls
            updatedColony.souls -= int32(armyPopCost)
            updatedColony.population = updatedColony.souls div 1_000_000
            state.updateColony(completed.colonyId, updatedColony)

            let armyCount = countGroundUnits(state, updatedColony, GroundClass.Army)

            logInfo(
              "Economy",
              &"Mustered Army Division at {completed.colonyId} " &
                &"(Total Armies: {armyCount} AA, {updatedColony.souls} souls remaining)",
            )

            events.add(
              event_factory.unitRecruited(
                updatedColony.owner, "Army Division", updatedColony.systemId, 1
              )
            )

  # Write all modified colonies back to state
  # This ensures multiple units completing at same colony see accumulated changes
  logDebug("Economy", &"Writing {modifiedColonies.len} modified colonies back to state")
  for colonyId, colony in modifiedColonies:
    state.updateColony(colonyId, colony)
    logDebug("Economy", &"  Colony {colonyId} updated")

  # Auto-load fighters onto carriers with available hangar space
  # Per phas commanding (commissioning.nim:22-24), this happens after
  # commissioning but before new build commands
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

  # 1. Find existing scout fleet at this location, or create new one
  var scoutFleetId: FleetId = FleetId(0)

  for fleet in state.fleetsAtSystem(systemId):
    if fleet.houseId != owner:
      continue

    # Check if this is a pure scout fleet (only scout ships)
    var isPureScoutFleet = fleet.ships.len > 0
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isNone:
        isPureScoutFleet = false
        break
      let ship = shipOpt.get()
      if ship.shipClass != ShipClass.Scout:
        isPureScoutFleet = false
        break

    if isPureScoutFleet:
      scoutFleetId = fleet.id
      break

  # 2. Create fleet if needed
  if scoutFleetId == FleetId(0):
    let fleet = fleet_ops.createFleet(state, owner, systemId)
    scoutFleetId = fleet.id
    logInfo(
      "Fleet", &"Created new scout fleet {scoutFleetId} at {systemId}"
    )

  # 3. Create and add the scout ship to the fleet
  let ship = ship_ops.createShip(state, owner, scoutFleetId, ShipClass.Scout)

  logInfo(
    "Fleet",
    &"Commissioned Scout {ship.id} in fleet {scoutFleetId} at {systemId}",
  )

  # 4. Generate event
  events.add(event_factory.shipCommissioned(owner, ShipClass.Scout, systemId))

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

  # 1. Find existing combat fleet at this location, or create new one
  var combatFleetId: FleetId = FleetId(0)

  for fleet in state.fleetsAtSystem(systemId):
    if fleet.houseId != owner:
      continue

    # Check if this is a combat fleet (not pure scout/auxiliary)
    # Combat fleets contain capital ships (not just scouts/ETAC/transports)
    var isCombatFleet = false
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isNone:
        continue
      let ship = shipOpt.get()

      # Combat fleet contains capital ships (not just auxiliary ships)
      if ship.shipClass notin [ShipClass.Scout, ShipClass.ETAC, ShipClass.TroopTransport]:
        isCombatFleet = true
        break

    if isCombatFleet:
      combatFleetId = fleet.id
      break

  # 2. Create fleet if needed
  if combatFleetId == FleetId(0):
    let fleet = fleet_ops.createFleet(state, owner, systemId)
    combatFleetId = fleet.id
    logInfo(
      "Fleet", &"Created new combat fleet {combatFleetId} at {systemId}"
    )

  # 3. Create and add the capital ship to the fleet
  let ship = ship_ops.createShip(state, owner, combatFleetId, shipClass)

  let fleetShipCount = state.fleet(combatFleetId).get().ships.len
  logInfo(
    "Fleet",
    &"Commissioned {shipClass} {ship.id} in fleet {combatFleetId} " &
      &"at {systemId} ({fleetShipCount} ships)",
  )

  # 4. Generate event
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
  ## - Capital ships → fleets (auto-assigned)
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

    # CRITICAL: Validate facility survived combat
    # Ships built in facilities may be destroyed if facility was crippled/destroyed
    # during the Conflict Phase before commissioning
    if completed.neoriaId.isSome:
      let neoriaId = completed.neoriaId.get()
      let neoriaOpt = state.neoria(neoriaId)
      if neoriaOpt.isNone or neoriaOpt.get().state in {CombatState.Crippled, CombatState.Destroyed}:
        logInfo(
          "Economy",
          &"Ship construction lost - facility {neoriaId} was damaged in combat",
        )
        events.add(event_factory.constructionLostToCombat(
          state.turn,
          completed.colonyId,
          neoriaId,
          neoriaOpt.get().neoriaClass,
          completed.itemId,
        ))
        continue # Skip commissioning - ship destroyed with facility

    logInfo(
      "Economy",
      &"Commissioning ship: {completed.itemId} at system-{completed.colonyId}",
    )

    # Get colony and owner
    let colonyOpt = state.colony(completed.colonyId)
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
      let houseOpt = state.house(owner)
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
      else:
        # All other ships (capital ships, ETAC, TroopTransport, etc.)
        commissionCapitalShip(
          state, owner, colony.systemId, shipClass, techLevel, events
        )
    except ValueError:
      logError("Economy", &"Invalid ship class: {completed.itemId}")

proc clearDamagedFacilityQueues*(state: var GameState, events: var seq[GameEvent]) =
  ## Clear construction and repair queues for crippled/destroyed facilities
  ## Called during Command Phase Part A (before ship commissioning)
  ## Ensures ships don't commission from facilities that were destroyed in combat
  ##
  ## **Timing:** Command Phase Part A (before Step 1: Ship Commissioning)
  ## **Why:** Facilities may have been crippled/destroyed during previous Conflict Phase
  ##
  ## **Clears:**
  ## - Construction projects at crippled/destroyed Neorias (Spaceport, Shipyard, Drydock)
  ## - Repair projects at crippled/destroyed Neorias (Drydock only handles ship repairs)
  ## - Construction projects at crippled/destroyed Kastras (Starbases)
  
  # Check all Neorias for damage
  for (neoriaId, neoria) in state.allNeoriasWithId():
    if neoria.state in {CombatState.Crippled, CombatState.Destroyed}:
      # Clear active constructions
      for projectId in neoria.activeConstructions:
        let projectOpt = state.constructionProject(projectId)
        if projectOpt.isSome:
          let project = projectOpt.get()
          events.add(event_factory.constructionLostToCombat(
            state.turn,
            project.colonyId,
            neoriaId,
            neoria.neoriaClass,
            project.itemId,
          ))
          logInfo(
            "Commissioning", "Construction lost to combat - facility damaged",
            " neoriaId=", neoriaId, " facilityType=", neoria.neoriaClass,
            " projectId=", projectId, " state=", neoria.state,
          )
      
      # Clear construction queue
      for projectId in neoria.constructionQueue:
        let projectOpt = state.constructionProject(projectId)
        if projectOpt.isSome:
          let project = projectOpt.get()
          events.add(event_factory.constructionLostToCombat(
            state.turn,
            project.colonyId,
            neoriaId,
            neoria.neoriaClass,
            project.itemId,
          ))
      
      # Clear active repairs (drydock only - ship repairs)
      for projectId in neoria.activeRepairs:
        let projectOpt = state.repairProject(projectId)
        if projectOpt.isSome:
          let project = projectOpt.get()
          events.add(event_factory.repairLostToCombat(
            state.turn,
            project.colonyId,
            neoriaId,
            project.targetType,
            project.shipClass,
          ))
          logInfo(
            "Commissioning", "Repair lost to combat - drydock damaged",
            " neoriaId=", neoriaId, " projectId=", projectId,
            " state=", neoria.state,
          )
      
      # Clear repair queue
      for projectId in neoria.repairQueue:
        let projectOpt = state.repairProject(projectId)
        if projectOpt.isSome:
          let project = projectOpt.get()
          events.add(event_factory.repairLostToCombat(
            state.turn,
            project.colonyId,
            neoriaId,
            project.targetType,
            project.shipClass,
          ))
      
      # Actually clear the queues
      var updatedNeoria = neoria
      updatedNeoria.activeConstructions = @[]
      updatedNeoria.constructionQueue = @[]
      updatedNeoria.activeRepairs = @[]
      updatedNeoria.repairQueue = @[]

proc commissionRepairedShips*(
    state: var GameState, completedRepairs: seq[RepairProject], events: var seq[GameEvent]
) =
  ## Commission repaired ships back to fleets
  ## Called during Production Phase Step 2c (after repair advancement)
  ## Repaired ships are immediately operational (no delay)
  ##
  ## **Process:**
  ## 1. Restore ship to Undamaged state
  ## 2. Group ships by colony and add to single fleet per colony
  ## 3. Generate ShipCommissioned event
  ## 4. Dock space already freed by completeRepairProject()
  
  # Group repaired ships by colony
  var shipsByColony: Table[ColonyId, seq[ShipId]]
  
  for repair in completedRepairs:
    # Only process ship repairs (not ground units, facilities, or starbases)
    if repair.targetType != RepairTargetType.Ship:
      continue
    
    # Skip if ship doesn't exist (edge case - shouldn't happen)
    if repair.shipId.isNone:
      logWarn(
        "Commissioning", "Ship repair has no shipId",
        " repairId=", repair.id,
      )
      continue
    
    let shipId = repair.shipId.get()
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      logWarn(
        "Commissioning", "Repaired ship not found",
        " shipId=", shipId, " repairId=", repair.id,
      )
      continue
    
    var ship = shipOpt.get()
    
    # Restore ship to operational state
    ship.state = CombatState.Undamaged
    state.updateShip(shipId, ship)
    
    # Add to colony group
    if not shipsByColony.hasKey(repair.colonyId):
      shipsByColony[repair.colonyId] = @[]
    shipsByColony[repair.colonyId].add(shipId)
  
  # Create one fleet per colony with all repaired ships
  for colonyId, shipIds in shipsByColony.pairs:
    let colonyOpt = state.colony(colonyId)
    if colonyOpt.isNone:
      logWarn(
        "Commissioning", "Colony not found for repaired ships",
        " colonyId=", colonyId,
      )
      continue
    
    let colony = colonyOpt.get()
    let systemId = colony.systemId
    
    # Create fleet with all repaired ships from this colony
    var newFleet = fleet_ops.createFleet(
      state,
      colony.owner,
      systemId,
    )
    
    # Add all ships to the fleet
    newFleet.ships = shipIds
    state.updateFleet(newFleet.id, newFleet)
    
    logInfo(
      "Commissioning", "Commissioned repaired ships to single fleet",
      " shipCount=", shipIds.len,
      " fleetId=", newFleet.id, " systemId=", systemId,
    )
    
    # Generate events for each ship
    for shipId in shipIds:
      let shipOpt = state.ship(shipId)
      if shipOpt.isSome:
        let ship = shipOpt.get()
        events.add(event_factory.shipCommissioned(
          colony.owner,
          ship.shipClass,
          systemId,
        ))
