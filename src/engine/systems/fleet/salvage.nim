## Salvage and Repair System for EC4X
##
## Salvage mechanics (military.toml):
## - Destroyed ships can be salvaged for resources
## - Normal salvage: 50% of build cost returned
## - Emergency/combat salvage: 25% of build cost returned
##
## Repair mechanics (construction.toml):
## - Crippled ships can be repaired at shipyards
## - Ship repair: 1 turn + 25% of build cost
## - Starbase repair: 1 turn + 25% of build cost
## - Requires shipyard with available docks

import std/[tables, options, sequtils]
import ../../types/[core, game_state, fleet, ship]
import ../economy/types as econ_types
import
  ../../config/[
    engine as config_engine, construction_config, ships_config,
    facilities_config,
  ]

export HouseId, SystemId, FleetId, ShipClass

type
  SalvageType* {.pure.} = enum
    Normal # Planned salvage at friendly colony (50% value)
    Emergency # Combat/field salvage (25% value)

  SalvageResult* = object ## Result of salvaging destroyed ships
    shipClass*: ShipClass
    salvageType*: SalvageType
    resourcesRecovered*: int
    success*: bool
    message*: string

  RepairProject* = object ## Ship or starbase repair project
    targetType*: RepairTargetType
    fleetId*: Option[FleetId] # For ship repairs
    shipId*: Option[ShipId] # Ship being repaired
    colonyId*: Option[SystemId] # For starbase repairs
    starbaseIndex*: int # Index within colony
    cost*: int
    turnsRemaining*: int

  RepairTargetType* {.pure.} = enum
    Ship
    Starbase

  RepairRequest* = object ## Request to repair a ship or starbase
    targetType*: RepairTargetType
    shipClass*: Option[ShipClass] # For cost calculation
    systemId*: SystemId # Where repair happens
    requestingHouse*: HouseId

  RepairValidation* = object ## Validation result for repair request
    valid*: bool
    message*: string
    cost*: int

## Salvage Operations
##
## IMPORTANT: Salvage operations should only be performed in systems
## controlled by the salvaging house. The FleetOrder.Salvage should validate
## system ownership before allowing salvage to proceed.

proc getSalvageValue*(shipClass: ShipClass, salvageType: SalvageType): int =
  ## Calculate salvage value for destroyed ship
  ## Per config/ships.kdl and docs/specs/05-construction.md:
  ## - Salvage: 50% of build cost (PC recovery)
  ## Note: Emergency salvage not implemented in specs, uses same multiplier

  let stats = config_engine.getShipStats(shipClass)
  let buildCost = stats.buildCost

  # Per ships.kdl: salvageValueMultiplier = 0.5 (50% of build cost)
  # Both Normal and Emergency use same multiplier (Emergency not in specs)
  let multiplier = globalShipsConfig.salvage.salvageValueMultiplier

  return int(float(buildCost) * multiplier)

proc salvageShip*(shipClass: ShipClass, salvageType: SalvageType): SalvageResult =
  ## Salvage a destroyed ship for resources
  ## Returns resources based on ship class and salvage type

  let resourcesRecovered = getSalvageValue(shipClass, salvageType)

  result = SalvageResult(
    shipClass: shipClass,
    salvageType: salvageType,
    resourcesRecovered: resourcesRecovered,
    success: true,
    message: $shipClass & " salvaged for " & $resourcesRecovered & " PP",
  )

proc salvageDestroyedShips*(
    destroyedShips: seq[ShipClass], salvageType: SalvageType
): seq[SalvageResult] =
  ## Salvage multiple destroyed ships
  ## Returns sequence of salvage results

  result = @[]
  for shipClass in destroyedShips:
    result.add(salvageShip(shipClass, salvageType))

## Repair Operations

proc getShipRepairCost*(shipClass: ShipClass): int =
  ## Calculate repair cost for crippled ship
  ## Per construction.kdl: 25% of build cost

  let stats = config_engine.getShipStats(shipClass)
  let buildCost = stats.buildCost
  let multiplier = globalConstructionConfig.repair.shipRepairCostMultiplier

  return int(float(buildCost) * multiplier)

proc getStarbaseRepairCost*(): int =
  ## Calculate repair cost for crippled starbase
  ## Per construction.kdl: 25% of build cost

  let buildCost = globalFacilitiesConfig.facilities[FacilityClass.Starbase].productionCost
  let multiplier = globalConstructionConfig.repair.starbaseRepairCostMultiplier

  return int(float(buildCost) * multiplier)

proc getRepairTurns*(): int =
  ## Get number of turns required for repair
  ## Per construction.toml: ship_repair_turns

  return globalConstructionConfig.repair.ship_repair_turns

proc validateRepairRequest*(
    request: RepairRequest, state: GameState
): RepairValidation =
  ## Validate a repair request
  ## Checks:
  ## - Colony exists and is owned by requesting house
  ## - Colony has operational shipyard
  ## - House can afford repair cost
  ##
  ## IMPORTANT: Ships can ONLY be repaired at own colonies, not allied/hostile

  result = RepairValidation(valid: false, message: "", cost: 0)

  # Check colony exists
  if request.systemId notin state.colonies:
    result.message = "Colony does not exist"
    return

  let colony = state.colonies[request.systemId]

  # Check colony ownership - MUST be own colony
  if colony.owner != request.requestingHouse:
    result.message = "Cannot repair at another house's colony"
    return

  # Different facility requirements for Ship vs Starbase repairs
  case request.targetType
  of RepairTargetType.Ship:
    # Ship repairs require Shipyards
    if colony.shipyards.len == 0:
      result.message = "Colony has no shipyard for ship repairs"
      return

    # Check for operational shipyard
    var hasOperationalShipyard = false
    for shipyard in colony.shipyards:
      if not shipyard.isCrippled:
        hasOperationalShipyard = true
        break

    if not hasOperationalShipyard:
      result.message = "No operational shipyard available (all crippled)"
      return
  of RepairTargetType.Starbase:
    # Starbase repairs require Spaceports (not Shipyards)
    if colony.spaceports.len == 0:
      result.message = "Colony has no spaceport for starbase repairs"
      return

    # Note: Spaceport operational status checked implicitly (exists = operational)
    # Starbases do NOT check dock capacity (facilities don't consume docks)

  # Calculate repair cost
  let cost =
    case request.targetType
    of RepairTargetType.Ship:
      if request.shipClass.isNone:
        result.message = "Ship class required for cost calculation"
        return
      getShipRepairCost(request.shipClass.get())
    of RepairTargetType.Starbase:
      getStarbaseRepairCost()

  # Check house can afford
  if request.requestingHouse notin state.houses:
    result.message = "House does not exist"
    return

  let house = state.houses[request.requestingHouse]
  if house.treasury < cost:
    result.message =
      "Insufficient funds (need " & $cost & " PP, have " & $house.treasury & " PP)"
    return

  # Check dock capacity for Ship repairs only (Starbases don't consume docks)
  if request.targetType == RepairTargetType.Ship:
    let activeProjects =
      colony.getActiveProjectsByFacility(econ_types.FacilityClass.Shipyard)
    let capacity = colony.getShipyardDockCapacity()

    if activeProjects >= capacity:
      result.message =
        "All shipyard docks occupied (" & $activeProjects & "/" & $capacity & " in use)"
      return

  result.valid = true
  result.cost = cost
  result.message = "Repair approved"

proc repairShip*(state: var GameState, fleetId: FleetId, shipId: ShipId): bool =
  ## Immediately repair a crippled ship at a friendly shipyard
  ## Deducts repair cost from house treasury
  ## Returns true if repair successful

  # Find fleet
  if fleetId notin state.fleets:
    return false

  let fleet = state.fleets[fleetId]

  # Find ship in fleet
  var shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return false

  var ship = shipOpt.get()

  # Verify ship is in this fleet
  if ship.fleetId != fleetId:
    return false

  # Check if ship is crippled
  if ship.state != CombatState.Crippled:
    return false

  # Validate repair request
  let request = RepairRequest(
    targetType: RepairTargetType.Ship,
    shipClass: some(ship.shipClass),
    systemId: fleet.location,
    requestingHouse: fleet.houseId,
  )

  let validation = validateRepairRequest(request, state)
  if not validation.valid:
    return false

  # Deduct cost
  var house = state.houses[fleet.houseId]
  house.treasury -= validation.cost
  state.houses[fleet.houseId] = house

  # Repair ship
  ship.state = CombatState.Undamaged
  state.updateShip(shipId, ship)

  return true

proc repairStarbase*(
    state: var GameState, systemId: SystemId, starbaseIndex: int
): bool =
  ## Immediately repair a crippled starbase at colony shipyard
  ## Deducts repair cost from house treasury
  ## Returns true if repair successful

  # Check colony exists
  if systemId notin state.colonies:
    return false

  var colony = state.colonies[systemId]

  # Validate starbase index
  if starbaseIndex < 0 or starbaseIndex >= colony.starbases.len:
    return false

  var starbase = colony.starbases[starbaseIndex]

  # Check if starbase is crippled
  if not starbase.isCrippled:
    return false

  # Validate repair request
  let request = RepairRequest(
    targetType: RepairTargetType.Starbase,
    shipClass: none(ShipClass),
    systemId: systemId,
    requestingHouse: colony.owner,
  )

  let validation = validateRepairRequest(request, state)
  if not validation.valid:
    return false

  # Deduct cost
  state.houses[colony.owner].treasury -= validation.cost

  # Repair starbase
  starbase.isCrippled = false
  colony.starbases[starbaseIndex] = starbase
  state.colonies[systemId] = colony

  return true

## Helper Functions

proc getFleetSalvageValue*(
    state: GameState, fleet: Fleet, salvageType: SalvageType
): int =
  ## Calculate total salvage value for an entire fleet
  result = 0
  for shipId in fleet.ships:
    let ship = state.ship(shipId).get()
    result += getSalvageValue(ship.shipClass, salvageType)

proc getCrippledShips*(state: GameState, fleet: Fleet): seq[(ShipId, ShipClass)] =
  ## Get list of crippled ships in fleet
  ## Returns (ship ID, ship class) pairs
  result = @[]
  for shipId in fleet.ships:
    let ship = state.ship(shipId).get()
    if ship.state == CombatState.Crippled:
      result.add((shipId, ship.shipClass))

proc getCrippledStarbases*(colony: Colony): seq[(int, string)] =
  ## Get list of crippled starbases at colony
  ## Returns (starbase index, starbase id) pairs
  result = @[]
  for i, starbase in colony.starbases:
    if starbase.isCrippled:
      result.add((i, starbase.id))
