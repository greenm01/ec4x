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
import ../../entities/[neoria_ops, kastra_ops, ship_ops, fleet_ops, ground_unit_ops]
import ../../globals
import ../../utils
import ../../../common/logger
import ../capacity/carrier_hangar
import ../../event_factory/init

proc projectDesc*(p: ConstructionProject): string =
  ## Format project description from typed fields for logging
  if p.shipClass.isSome: return $p.shipClass.get()
  if p.facilityClass.isSome: return $p.facilityClass.get()
  if p.groundClass.isSome: return $p.groundClass.get()
  if p.industrialUnits > 0: return $p.industrialUnits & " IU"
  return "unknown"

proc completedProjectDesc*(p: CompletedProject): string =
  ## Format completed project description from typed fields for logging
  if p.shipClass.isSome: return $p.shipClass.get()
  if p.facilityClass.isSome: return $p.facilityClass.get()
  if p.groundClass.isSome: return $p.groundClass.get()
  if p.industrialUnits > 0: return $p.industrialUnits & " IU"
  return "unknown"

# Helper functions using DoD patterns
proc operationalStarbaseCount*(state: GameState, colonyId: ColonyId): int =
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

proc starbaseGrowthBonus*(state: GameState, colonyId: ColonyId): float =
  ## Calculate growth bonus from operational starbases
  ## Per specs: Each operational starbase provides growth bonus
  let operationalCount = operationalStarbaseCount(state, colonyId)
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

proc shieldBlockChance*(shieldLevel: int): float =
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
    state: GameState,
    modifiedColonies: Table[ColonyId, Colony],
    events: var seq[GameEvent],
) =
  ## Auto-load newly commissioned fighters onto carriers with available hangar
  ## space. Only processes colonies with autoLoadFighters = true.
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
    if not colony.autoLoadFighters:
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
        let availableSpace = availableHangarSpace(state, shipId)
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
        state.assignFighterToCarrier(fighterId, carrierId)

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
        unitRecruited(
          colony.owner, "Fighters (auto-loaded)", systemId, loadedCount
        )
      )

proc commissionPlanetaryDefense*(
    state: GameState,
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
      &"Commissioning planetary defense: {completed.projectType} {completed.completedProjectDesc} at system-{completed.colonyId}",
    )

    # Special handling for Fighters (planetary defense, colony-based)
    if completed.shipClass == some(ShipClass.Fighter):
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
          state.registerShipIndexes(shipId)
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
          buildingCompleted(
            colony.owner, "Fighter Squadron", colony.systemId
          )
        )

    # Special handling for starbases
    elif completed.facilityClass == some(FacilityClass.Starbase):
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
            &"(Total operational: {operationalStarbaseCount(state, completed.colonyId)}, " &
            &"Growth bonus: {int(starbaseGrowthBonus(state, completed.colonyId) * 100.0)}%)",
        )

        # Generate event
        events.add(
          buildingCompleted(colony.owner, "Starbase", colony.systemId)
        )

    # Special handling for spaceports
    elif completed.facilityClass == some(FacilityClass.Spaceport):
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
          buildingCompleted(colony.owner, "Spaceport", colony.systemId)
        )

    # Special handling for shipyards
    elif completed.facilityClass == some(FacilityClass.Shipyard):
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
          buildingCompleted(colony.owner, "Shipyard", colony.systemId)
        )

    # Special handling for drydocks
    elif completed.facilityClass == some(FacilityClass.Drydock):
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
          buildingCompleted(colony.owner, "Drydock", colony.systemId)
        )

    # Special handling for ground batteries
    elif completed.groundClass == some(GroundClass.GroundBattery):
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
        if colonyOpt.isNone:
          continue
        let colony = colonyOpt.get()

        # Create the ground battery unit
        discard ground_unit_ops.createGroundUnit(
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
          buildingCompleted(
            colony.owner, "Ground Battery", colony.systemId
          )
        )

    # Special handling for planetary shields (replacement, not upgrade)
    elif completed.groundClass == some(GroundClass.PlanetaryShield):
      if state.hasColony(completed.colonyId):
        let colonyOpt = state.colony(completed.colonyId)
        if colonyOpt.isNone:
          continue
        var colony = colonyOpt.get()

        # Create the planetary shield unit
        discard ground_unit_ops.createGroundUnit(
          state, colony.owner, completed.colonyId, GroundClass.PlanetaryShield
        )

        # Get house SLD tech level for logging
        let houseOpt = state.house(colony.owner)
        let sldLevel = if houseOpt.isSome: houseOpt.get().techTree.levels.sld else: 1

        logInfo(
          "Economy",
          &"Deployed planetary shield SLD{sldLevel} at {completed.colonyId} " &
            &"(Block chance: {int(shieldBlockChance(sldLevel) * 100.0)}%)",
        )

        events.add(
          buildingCompleted(
            colony.owner,
            &"Planetary Shield SLD{sldLevel}",
            colony.systemId,
          )
        )

    # Special handling for Marines (MD)
    elif completed.groundClass == some(GroundClass.Marine):
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
          # Create the marine unit
          discard ground_unit_ops.createGroundUnit(
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
              unitRecruited(
                updatedColony.owner, "Marine Division", updatedColony.systemId, 1
              )
            )

    # Special handling for Armies (AA)
    elif completed.groundClass == some(GroundClass.Army):
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
          # Create the army unit
          discard ground_unit_ops.createGroundUnit(
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
              unitRecruited(
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

# =============================================================================
# Fleet Classification Helpers
# =============================================================================

proc isPureScoutFleet(state: GameState, fleet: Fleet): bool =
  ## Check if fleet contains only Scout ships
  ## Used to find appropriate fleet for newly commissioned scouts
  if fleet.ships.len == 0:
    return false
  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      return false
    if shipOpt.get().shipClass != ShipClass.Scout:
      return false
  return true

proc isCombatFleet(state: GameState, fleet: Fleet): bool =
  ## Check if fleet contains at least one combat ship (not scout/auxiliary)
  ## Used to find appropriate fleet for newly commissioned combat ships
  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue
    let ship = shipOpt.get()
    # Combat fleet contains capital ships (not just scouts/ETAC/transports)
    if ship.shipClass notin [ShipClass.Scout, ShipClass.ETAC,
                              ShipClass.TroopTransport]:
      return true
  return false

# =============================================================================
# Ship Commissioning (implements CMD4a "Auto-assign ships to fleets")
# =============================================================================

proc commissionShip(
    state: GameState,
    owner: HouseId,
    systemId: SystemId,
    shipClass: ShipClass,
    techLevel: int32,
    events: var seq[GameEvent],
) =
  ## Commission a ship into an appropriate fleet
  ##
  ## This proc implements CMD4a "Auto-assign ships to fleets" from the
  ## canonical turn cycle. Ships are always auto-assigned to fleets.
  ##
  ## Fleet selection logic:
  ## - Scouts -> Join existing pure scout fleet, or create new fleet
  ##   (scouts grouped for mesh network bonuses)
  ## - All other ships -> Join existing combat fleet, or create new fleet

  var targetFleetId: FleetId = FleetId(0)

  # Find appropriate existing fleet
  for fleet in state.fleetsAtSystem(systemId):
    if fleet.houseId != owner:
      continue

    if shipClass == ShipClass.Scout:
      # Scouts join pure scout fleets (for mesh network bonuses)
      if isPureScoutFleet(state, fleet):
        targetFleetId = fleet.id
        break
    else:
      # All other ships join combat fleets
      if isCombatFleet(state, fleet):
        targetFleetId = fleet.id
        break

  # Create new fleet if no suitable fleet found
  if targetFleetId == FleetId(0):
    let fleet = state.createFleet(owner, systemId)
    targetFleetId = fleet.id
    let fleetType = if shipClass == ShipClass.Scout: "scout" else: "combat"
    logInfo("Fleet", &"Created new {fleetType} fleet {targetFleetId} at {systemId}")

  # Create and add ship to fleet
  let ship = state.createShip(owner, targetFleetId, shipClass)

  let fleetShipCount = state.fleet(targetFleetId).get().ships.len
  logInfo("Fleet",
    &"Commissioned {shipClass} {ship.id} in fleet {targetFleetId} " &
    &"at {systemId} ({fleetShipCount} ships)")

  events.add(shipCommissioned(owner, shipClass, systemId))

proc commissionShips*(
    state: GameState,
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
        events.add(constructionLostToCombat(
          state.turn,
          completed.colonyId,
          neoriaId,
          neoriaOpt.get().neoriaClass,
          completed.completedProjectDesc,
        ))
        continue # Skip commissioning - ship destroyed with facility

    logInfo(
      "Economy",
      &"Commissioning ship: {completed.completedProjectDesc} at system-{completed.colonyId}",
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

    # Get ship class from typed field
    if completed.shipClass.isNone:
      logError("Economy", &"Cannot commission ship - no shipClass in project")
      continue
    let shipClass = completed.shipClass.get()

    # Get house tech level for ship stats
    let houseOpt = state.house(owner)
    if houseOpt.isNone:
      logWarn("Economy", &"Cannot commission ship - house {owner} not found")
      continue
    let house = houseOpt.get()
    let techLevel = house.techTree.levels.wep

    # Commission ship (auto-assigns to appropriate fleet)
    # Scouts -> pure scout fleets; others -> combat fleets
    commissionShip(state, owner, colony.systemId, shipClass, techLevel, events)

proc clearDamagedFacilityQueues*(state: GameState, events: var seq[GameEvent]) =
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
          events.add(constructionLostToCombat(
            state.turn,
            project.colonyId,
            neoriaId,
            neoria.neoriaClass,
            project.projectDesc,
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
          events.add(constructionLostToCombat(
            state.turn,
            project.colonyId,
            neoriaId,
            neoria.neoriaClass,
            project.projectDesc,
          ))
      
      # Clear active repairs (drydock only - ship repairs)
      for projectId in neoria.activeRepairs:
        let projectOpt = state.repairProject(projectId)
        if projectOpt.isSome:
          let project = projectOpt.get()
          events.add(repairLostToCombat(
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
          events.add(repairLostToCombat(
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
    state: GameState, completedRepairs: seq[RepairProject], events: var seq[GameEvent]
) =
  ## Commission repaired ships back to fleets (CMD2b)
  ## Per ec4x_canonical_turn_cycle.md CMD2b (lines 122-128):
  ## - Check treasury (once per turn, here at commissioning)
  ## - If sufficient: Pay repair cost, commission ship, free dock
  ## - If insufficient: Mark repair Stalled (stays in queue, occupies dock)
  ##
  ## **Process:**
  ## 1. Check house treasury for repair cost
  ## 2. If sufficient: Deduct cost, restore ship to Nominal state
  ## 3. If insufficient: Mark repair Stalled (ship stays crippled in queue)
  ## 4. Group commissioned ships by colony and add to fleets
  ## 5. Generate ShipCommissioned or RepairStalled events
  
  # Group repaired ships by colony (only successfully paid repairs)
  var shipsByColony: Table[ColonyId, seq[ShipId]]
  
  for repair in completedRepairs:
    # Get colony for owner/system info
    let colonyOpt = state.colony(repair.colonyId)
    if colonyOpt.isNone:
      logWarn(
        "Commissioning", "Colony not found for repair",
        " colonyId=", repair.colonyId, " repairId=", repair.id,
      )
      continue
    
    let colony = colonyOpt.get()
    let houseId = colony.owner
    
    # Handle non-ship repairs (facilities, starbases, ground units)
    if repair.targetType != RepairTargetType.Ship:
      # Get house to check treasury
      var house = state.house(houseId).get()
      
      if house.treasury < repair.cost:
        # Insufficient funds - mark repair as Stalled
        logWarn(
          "Commissioning", "Insufficient funds for repair - marked Stalled",
          " houseId=", houseId,
          " targetType=", repair.targetType,
          " cost=", repair.cost, " PP",
          " treasury=", house.treasury, " PP",
        )
        
        # Generate RepairStalled event (we need a generic version for non-ships)
        events.add(GameEvent(
          eventType: GameEventType.RepairStalled,
          houseId: some(houseId),
          description: &"{repair.targetType} repair stalled - insufficient funds ({repair.cost} PP required)",
          systemId: some(colony.systemId),
          details: some(&"TargetType: {repair.targetType}, Cost: {repair.cost} PP, Reason: insufficient_funds"),
        ))
        continue
      
      # Sufficient funds - deduct cost and restore
      house.treasury -= repair.cost
      state.updateHouse(houseId, house)
      
      # Restore the entity to operational state based on type
      case repair.targetType
      of RepairTargetType.Starbase:
        if repair.kastraId.isSome:
          var kastra = state.kastra(repair.kastraId.get()).get()
          kastra.state = CombatState.Nominal
          state.updateKastra(repair.kastraId.get(), kastra)
      of RepairTargetType.GroundUnit:
        if repair.groundUnitId.isSome:
          var unit = state.groundUnit(repair.groundUnitId.get()).get()
          unit.state = CombatState.Nominal
          state.updateGroundUnit(repair.groundUnitId.get(), unit)
      of RepairTargetType.Facility:
        if repair.neoriaId.isSome:
          var neoria = state.neoria(repair.neoriaId.get()).get()
          neoria.state = CombatState.Nominal
          state.updateNeoria(repair.neoriaId.get(), neoria)
      else:
        discard
      
      # Generate RepairCompleted event
      events.add(GameEvent(
        eventType: GameEventType.RepairCompleted,
        houseId: some(houseId),
        description: &"{repair.targetType} repair completed at system {colony.systemId}",
        systemId: some(colony.systemId),
        details: some(&"TargetType: {repair.targetType}, Cost: {repair.cost} PP"),
      ))
      
      logInfo(
        "Commissioning", "Repaired non-ship entity",
        " houseId=", houseId,
        " targetType=", repair.targetType,
        " cost=", repair.cost, " PP",
      )
      continue
    
    # === Ship repairs below (existing code) ===
    
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
    
    # Reuse colony and houseId from outer scope (already fetched above)
    # Check treasury for repair cost
    var house = state.house(houseId).get()
    
    if house.treasury < repair.cost:
      # Insufficient funds - mark repair as Stalled
      # Ship stays crippled in queue, occupies dock
      logWarn(
        "Commissioning", "Insufficient funds for ship repair - marked Stalled",
        " houseId=", houseId,
        " shipId=", shipId,
        " cost=", repair.cost, " PP",
        " treasury=", house.treasury, " PP",
      )
      
      # Generate RepairStalled event
      events.add(repairStalled(
        houseId,
        ship.shipClass,
        repair.colonyId,
        repair.cost,
      ))
      
      # Ship stays in repair queue (not commissioned)
      continue
    
    # Sufficient funds - deduct cost and commission ship
    house.treasury -= repair.cost
    state.updateHouse(houseId, house)
    
    logInfo(
      "Commissioning", "Paid repair cost",
      " houseId=", houseId,
      " shipId=", shipId,
      " cost=", repair.cost, " PP",
      " treasury_after=", house.treasury, " PP",
    )
    
    # Restore ship to operational state
    ship.state = CombatState.Nominal
    state.updateShip(shipId, ship)
    
    # Generate RepairCompleted event
    events.add(repairCompleted(
      houseId,
      ship.shipClass,
      colony.systemId,
      repair.cost,
    ))
    
    # Add to colony group for fleet assignment
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
        events.add(shipCommissioned(
          colony.owner,
          ship.shipClass,
          systemId,
        ))
