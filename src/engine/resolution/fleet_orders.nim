## Fleet movement, colonization, and seek home operations
##
## This module handles all fleet order resolution including:
## - Fleet movement with pathfinding and lane traversal rules
## - Colonization orders and new colony establishment
## - Automated Seek Home behavior for stranded fleets
## - Helper functions for path finding and hostility detection

import std/[tables, options, sequtils]
import ../../common/[hex, types/core, types/combat, types/units]
import ../gamestate, ../orders, ../fleet, ../starmap, ../spacelift
import ../colonization/engine as col_engine
import ../diplomacy/[types as dip_types]
import ../config/[prestige_config, population_config]
import ../prestige
import ./types  # Common resolution types

proc findClosestOwnedColony*(state: GameState, fromSystem: SystemId, houseId: HouseId): Option[SystemId] =
  ## Find the closest owned colony for a house, excluding the fromSystem
  ## Returns None if house has no colonies
  ## Used by Space Guild to find alternative delivery destination
  ## Also used for automated Seek Home behavior for stranded fleets

  var closestColony: Option[SystemId] = none(SystemId)
  var shortestDistance = int.high

  # Iterate through all colonies owned by this house
  for systemId, colony in state.colonies:
    if colony.owner == houseId and systemId != fromSystem:
      # Calculate distance (jump count) to this colony
      # Create dummy fleet for pathfinding
      let dummyFleet = Fleet(
        id: "temp",
        owner: houseId,
        location: fromSystem,
        squadrons: @[],
        spaceLiftShips: @[],
        status: FleetStatus.Active
      )

      let pathResult = state.starMap.findPath(fromSystem, systemId, dummyFleet)
      if pathResult.path.len > 0:
        let distance = pathResult.path.len - 1  # Number of jumps
        if distance < shortestDistance:
          shortestDistance = distance
          closestColony = some(systemId)

  return closestColony

proc isSystemHostile*(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a system is hostile to a house
  ## System is hostile if:
  ## 1. Colonized by an enemy house (diplomatic status: Enemy)
  ## 2. Enemy fleets are present

  # Check if system has enemy colony
  if systemId in state.colonies:
    let colony = state.colonies[systemId]
    if colony.owner != houseId:
      # Check diplomatic status
      let house = state.houses[houseId]
      if house.diplomaticRelations.isEnemy(colony.owner):
        return true

  # Check for enemy fleets at system
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId and fleet.owner != houseId:
      let house = state.houses[houseId]
      if house.diplomaticRelations.isEnemy(fleet.owner):
        return true

  return false

proc shouldAutoSeekHome*(state: GameState, fleet: Fleet, order: FleetOrder): bool =
  ## Determine if a fleet should automatically seek home due to dangerous situation
  ## Triggers for:
  ## - ETAC/colonization missions where target becomes hostile
  ## - Guard/blockade orders where system becomes hostile
  ## - Fleets stranded in now-hostile territory

  # Check if fleet is executing an order that becomes invalid due to hostility
  case order.orderType
  of FleetOrderType.Colonize:
    # ETAC missions abort if destination becomes enemy-controlled
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if isSystemHostile(state, targetId, fleet.owner):
        return true

  of FleetOrderType.GuardStarbase, FleetOrderType.GuardPlanet, FleetOrderType.BlockadePlanet:
    # Guard/blockade orders abort if system lost to enemy
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if targetId in state.colonies:
        let colony = state.colonies[targetId]
        # If colony ownership changed to enemy, abort
        if colony.owner != fleet.owner:
          let house = state.houses[fleet.owner]
          if house.diplomaticRelations.isEnemy(colony.owner):
            return true
      else:
        # Colony destroyed - abort
        return true

  of FleetOrderType.Patrol:
    # Patrols abort if their patrol zone becomes enemy territory
    # Check if current location is hostile
    if fleet.location in state.colonies:
      let colony = state.colonies[fleet.location]
      if colony.owner != fleet.owner:
        let house = state.houses[fleet.owner]
        if house.diplomaticRelations.isEnemy(colony.owner):
          return true

    # Also check if patrol target destination is hostile
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if isSystemHostile(state, targetId, fleet.owner):
        return true

  else:
    discard

  return false

proc resolveMovementOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent]) =
  ## Execute a fleet movement order with pathfinding and lane traversal rules
  ## Per operations.md:6.1 - Lane traversal rules:
  ##   - Major lanes: 2 jumps per turn if all systems owned by player
  ##   - Major lanes: 1 jump per turn if jumping into unexplored/rival system
  ##   - Minor/Restricted lanes: 1 jump per turn maximum
  ##   - Crippled ships or Spacelift ships cannot cross Restricted lanes

  if order.targetSystem.isNone:
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  var fleet = fleetOpt.get()
  let targetId = order.targetSystem.get()
  let startId = fleet.location

  # Already at destination
  if startId == targetId:
    echo "    Fleet ", order.fleetId, " already at destination"
    return

  echo "    Fleet ", order.fleetId, " moving from ", startId, " to ", targetId

  # Find path to destination (operations.md:6.1)
  let pathResult = state.starMap.findPath(startId, targetId, fleet)

  if not pathResult.found:
    echo "      No valid path found (blocked by restricted lanes or terrain)"
    return

  if pathResult.path.len < 2:
    echo "      Invalid path"
    return

  # Determine how many jumps the fleet can make this turn
  var jumpsAllowed = 1  # Default: 1 jump per turn

  # Check if we can do 2 major lane jumps (operations.md:6.1)
  if pathResult.path.len >= 3:
    # Check if all systems along path are owned by this house
    var allSystemsOwned = true
    for systemId in pathResult.path:
      if systemId notin state.colonies or state.colonies[systemId].owner != houseId:
        allSystemsOwned = false
        break

    # Check if next two jumps are both major lanes
    var nextTwoAreMajor = true
    if allSystemsOwned:
      for i in 0..<min(2, pathResult.path.len - 1):
        let fromSys = pathResult.path[i]
        let toSys = pathResult.path[i + 1]

        # Find lane type between these systems
        var laneIsMajor = false
        for lane in state.starMap.lanes:
          if (lane.source == fromSys and lane.destination == toSys) or
             (lane.source == toSys and lane.destination == fromSys):
            if lane.laneType == LaneType.Major:
              laneIsMajor = true
            break

        if not laneIsMajor:
          nextTwoAreMajor = false
          break

    # Apply 2-jump rule for major lanes in friendly territory
    if allSystemsOwned and nextTwoAreMajor:
      jumpsAllowed = 2

  # Execute movement (up to jumpsAllowed systems)
  let actualJumps = min(jumpsAllowed, pathResult.path.len - 1)
  let newLocation = pathResult.path[actualJumps]

  fleet.location = newLocation
  state.fleets[order.fleetId] = fleet

  echo "      Moved ", actualJumps, " jump(s) to system ", newLocation

  # Check for fleet encounters at destination
  # Find other fleets at the same location
  for otherFleetId, otherFleet in state.fleets:
    if otherFleetId != order.fleetId and otherFleet.location == newLocation:
      if otherFleet.owner != houseId:
        echo "      Encountered fleet ", otherFleetId, " (", otherFleet.owner, ") at ", newLocation
        # Combat will be resolved in conflict phase next turn
        # This just logs the encounter

proc resolveColonizationOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
                              events: var seq[GameEvent]) =
  ## Establish a new colony with prestige rewards
  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Check if system already colonized
  if targetId in state.colonies:
    echo "    System ", targetId, " already colonized"
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  # Check system exists
  if targetId notin state.starMap.systems:
    echo "    System ", targetId, " not found in starMap"
    return

  let fleet = fleetOpt.get()

  # Check fleet at target location
  if fleet.location != targetId:
    echo "    Fleet not at target system"
    return

  # Check fleet has colonists
  var hasColonists = false
  for ship in fleet.spaceLiftShips:
    if ship.cargo.cargoType == CargoType.Colonists and ship.cargo.quantity > 0:
      hasColonists = true
      break

  if not hasColonists:
    echo "    No colonists in fleet"
    return

  # Establish colony
  # TODO: Planet class and resources should be pre-generated or determined by system properties
  # For now, assume ETAC scouts found a benign world with abundant resources
  let planetClass = PlanetClass.Benign
  let resources = ResourceRating.Abundant

  # Create ETAC colony with 1 PTU (50k souls)
  let colony = createETACColony(targetId, houseId, planetClass, resources)

  # Use colonization engine to establish with prestige
  let result = col_engine.establishColony(
    houseId,
    targetId,
    colony.planetClass,
    colony.resources,
    1  # ETAC carries exactly 1 PTU
  )

  if not result.success:
    echo "    Failed to establish colony at ", targetId
    return

  state.colonies[targetId] = colony

  # Unload colonists from fleet
  var updatedFleet = fleet
  for ship in updatedFleet.spaceLiftShips.mitems:
    if ship.cargo.cargoType == CargoType.Colonists:
      discard ship.unloadCargo()

  state.fleets[order.fleetId] = updatedFleet

  # Apply prestige award
  if result.prestigeEvent.isSome:
    let prestigeEvent = result.prestigeEvent.get()
    state.houses[houseId].prestige += prestigeEvent.amount
    echo "    ", state.houses[houseId].name, " colonized system ", targetId,
         " (+", prestigeEvent.amount, " prestige)"

  # Generate event
  events.add(GameEvent(
    eventType: GameEventType.ColonyEstablished,
    houseId: houseId,
    description: "Established colony at system " & $targetId,
    systemId: some(targetId)
  ))

proc autoLoadCargo*(state: var GameState, orders: Table[HouseId, OrderPacket], events: var seq[GameEvent]) =
  ## Automatically load available marines/colonists onto empty transports at colonies
  ## Only auto-load if no manual cargo order exists for that fleet

  # Build set of fleets with manual cargo orders
  var manualCargoFleets: seq[FleetId] = @[]
  for houseId, packet in orders:
    for order in packet.cargoManagement:
      manualCargoFleets.add(order.fleetId)

  # Process each colony
  for systemId, colony in state.colonies:
    # Find fleets at this colony
    for fleetId, fleet in state.fleets:
      if fleet.location != systemId or fleet.owner != colony.owner:
        continue

      # Skip if fleet has manual cargo orders
      if fleetId in manualCargoFleets:
        continue

      # Auto-load empty transports if colony has inventory
      var colony = state.colonies[systemId]
      var fleet = state.fleets[fleetId]
      var modifiedShips: seq[SpaceLiftShip] = @[]
      var modified = false

      for ship in fleet.spaceLiftShips:
        var mutableShip = ship

        if ship.isCrippled or ship.cargo.cargoType != CargoType.None:
          modifiedShips.add(mutableShip)
          continue  # Skip crippled ships or ships already loaded

        # Determine what cargo this ship can carry
        case ship.shipClass
        of ShipClass.TroopTransport:
          # Auto-load marines if available
          if colony.marines > 0:
            let loadAmount = min(1, colony.marines)  # TroopTransport capacity = 1 MD
            if mutableShip.loadCargo(CargoType.Marines, loadAmount):
              colony.marines -= loadAmount
              modified = true
              echo "    [Auto] Loaded ", loadAmount, " Marines onto ", ship.id, " at ", systemId

        of ShipClass.ETAC:
          # Auto-load colonists if available (1 PTU commitment)
          # ETACs carry exactly 1 PTU for colonization missions
          # Per config/population.toml [transfer_limits] min_source_pu_remaining = 1
          let minSoulsToKeep = 1_000_000  # 1 PU minimum
          if colony.souls > minSoulsToKeep + soulsPerPtu():
            if mutableShip.loadCargo(CargoType.Colonists, 1):
              colony.souls -= soulsPerPtu()
              colony.population = colony.souls div 1_000_000
              modified = true
              echo "    [Auto] Loaded 1 PTU onto ", ship.id, " at ", systemId

        else:
          discard  # Other ship classes don't have spacelift capability

        modifiedShips.add(mutableShip)

      # Write back modified state if any cargo was loaded
      if modified:
        fleet.spaceLiftShips = modifiedShips
        state.fleets[fleetId] = fleet
        state.colonies[systemId] = colony
