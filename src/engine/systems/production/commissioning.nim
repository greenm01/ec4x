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

import std/[tables, options, strformat, strutils]
import ../../types/[core, game_state, production, event, ground_unit, combat]
import ../../types/[ship, colony, fleet, facilities]
import ../../state/[engine, id_gen]
import ../../config/[ground_units_config, facilities_config]
import ../../entities/[neoria_ops, kastra_ops, ground_unit_ops, ship_ops, fleet_ops]
import ../../globals
import ../../../common/logger
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

    # Find fleets at this system
    if systemId notin state.fleets.bySystem:
      continue

    # Get all carriers in fleets at this system with available space
    var carriersWithSpace: seq[tuple[carrierId: ShipId, availableSpace: int]] = @[]

    for fleet in state.fleetsInSystem(systemId):
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
          updatedColony.fighterIds.keepIf(proc(id: ShipId): bool = id != fighterId)
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

  template getColony(colId: ColonyId): Colony =
    if colId in modifiedColonies:
      modifiedColonies[colId]
    else:
      let opt = state.colony(colId)
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
        let baseDocks = globalFacilitiesConfig.facilities[FacilityClass.Spaceport].docks
        let houseOpt = state.house(colony.owner)
        if houseOpt.isNone:
          continue
        let house = houseOpt.get()
        let cstLevel = house.techTree.levels.constructionTech
        let effectiveDocks = calculateEffectiveDocks(baseDocks, cstLevel)

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
        let baseDocks = globalFacilitiesConfig.facilities[FacilityClass.Shipyard].docks
        let houseOpt = state.house(colony.owner)
        if houseOpt.isNone:
          continue
        let house = houseOpt.get()
        let cstLevel = house.techTree.levels.constructionTech
        let effectiveDocks = calculateEffectiveDocks(baseDocks, cstLevel)

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
        let baseDocks = globalFacilitiesConfig.facilities[FacilityClass.Drydock].docks
        let houseOpt = state.house(colony.owner)
        if houseOpt.isNone:
          continue
        let house = houseOpt.get()
        let cstLevel = house.techTree.levels.constructionTech
        let effectiveDocks = calculateEffectiveDocks(baseDocks, cstLevel)

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

        # Create ground battery using entity helper
        let battery = ground_unit_ops.createGroundUnit(
          state, colony.owner, completed.colonyId, GroundClass.GroundBattery
        )

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

        # Create PlanetaryShield ground unit (shield level from house SLD tech)
        let shieldUnit = ground_unit_ops.createGroundUnit(
          state, colony.owner, completed.colonyId, GroundClass.PlanetaryShield
        )

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
          # Create marine ground unit using entity helper
          let marine = ground_unit_ops.createGroundUnit(
            state, colony.owner, completed.colonyId, GroundClass.Marine
          )

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
          # Create army ground unit using entity helper
          let army = ground_unit_ops.createGroundUnit(
            state, colony.owner, completed.colonyId, GroundClass.Army
          )

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

  for fleet in state.fleetsInSystem(systemId):
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

  for fleet in state.fleetsInSystem(systemId):
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
