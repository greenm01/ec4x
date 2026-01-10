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

import std/options
import ../../types/[core, game_state, fleet, ship, facilities, combat, colony]
import ../../state/engine
import ../../globals

export HouseId, SystemId, FleetId, ShipClass

type
  SalvageType* {.pure.} = enum
    Normal # Planned salvage at friendly colony (50% value)
    Emergency # Combat/field salvage (25% value)

  SalvageResult* = object ## Result of salvaging destroyed ships
    shipClass*: ShipClass
    salvageType*: SalvageType
    resourcesRecovered*: int32
    success*: bool
    message*: string

  RepairProject* = object ## Ship or starbase repair project
    targetType*: RepairTargetType
    fleetId*: Option[FleetId] # For ship repairs
    shipId*: Option[ShipId] # Ship being repaired
    colonyId*: Option[SystemId] # For starbase repairs
    starbaseIndex*: int32 # Index within colony
    cost*: int32
    turnsRemaining*: int32

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
    cost*: int32

## Salvage Operations
##
## IMPORTANT: Salvage operations should only be performed in systems
## controlled by the salvaging house. The FleetOrder.Salvage should validate
## system ownership before allowing salvage to proceed.

proc getSalvageValue*(shipClass: ShipClass, salvageType: SalvageType): int32 =
  ## Calculate salvage value for destroyed ship
  ## Per config/ships.kdl and docs/specs/05-construction.md:
  ## - Salvage: 50% of build cost (PC recovery)
  ## Note: Emergency salvage not implemented in specs, uses same multiplier

  let stats = gameConfig.ships.ships[shipClass]
  let buildCost = stats.productionCost

  # Per ships.kdl: salvageValueMultiplier = 0.5 (50% of build cost)
  # Both Normal and Emergency use same multiplier (Emergency not in specs)
  let multiplier = gameConfig.ships.salvage.salvageValueMultiplier

  return int32(float32(buildCost) * multiplier)

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

proc getShipRepairCost*(shipClass: ShipClass): int32 =
  ## Calculate repair cost for crippled ship
  ## Per construction.kdl: 25% of build cost

  let stats = gameConfig.ships.ships[shipClass]
  let buildCost = stats.productionCost
  let multiplier = gameConfig.construction.repair.shipRepairCostMultiplier

  return int32(float32(buildCost) * multiplier)

proc getStarbaseRepairCost*(): int32 =
  ## Calculate repair cost for crippled starbase
  ## Per construction.kdl: 25% of build cost

  let buildCost = gameConfig.facilities.facilities[FacilityClass.Starbase].buildCost
  let multiplier = gameConfig.construction.repair.starbaseRepairCostMultiplier

  return int32(float32(buildCost) * multiplier)

proc getRepairTurns*(): int32 =
  ## Get number of turns required for repair
  ## Per construction.toml: ship_repair_turns

  return gameConfig.construction.repair.ship_repair_turns

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
  let colonyOpt = state.colonyBySystem(request.systemId)
  if colonyOpt.isNone:
    result.message = "Colony does not exist"
    return

  let colony = colonyOpt.get()

  # Check colony ownership - MUST be own colony
  if colony.owner != request.requestingHouse:
    result.message = "Cannot repair at another house's colony"
    return

  # Different facility requirements for Ship vs Starbase repairs
  # Per operations.md:6.2.1 - "All ship repairs require drydocks"
  case request.targetType
  of RepairTargetType.Ship:
    # Ship repairs require DRYDOCKS (per operations.md:6.2.1 lines 59-69)
    if state.countDrydocksAtColony(colony.id) == 0:
      result.message = "Colony has no drydock for ship repairs"
      return

    # Check for operational drydock
    let operationalNeorias = state.countOperationalNeoriasAtColony(colony.id)
    let hasOperationalDrydock = operationalNeorias > 0

    if not hasOperationalDrydock:
      result.message = "No operational drydock available (all crippled)"
      return
  of RepairTargetType.Starbase:
    # Starbase repairs require Spaceports (per operations.md:6.2.1 lines 72-76)
    if state.countSpaceportsAtColony(colony.id) == 0:
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

  # Check house can afford (use proper state accessor per architecture.md)
  let houseOpt = state.house(request.requestingHouse)
  if houseOpt.isNone:
    result.message = "House does not exist"
    return

  let house = houseOpt.get()
  if house.treasury < cost:
    result.message =
      "Insufficient funds (need " & $cost & " PP, have " & $house.treasury & " PP)"
    return

  # TODO: Check drydock capacity for Ship repairs when repair queue system implemented
  # Per operations.md:6.2.1, drydocks provide 10 repair docks
  # Starbase repairs do NOT consume dock capacity (separate queue)

  result.valid = true
  result.cost = cost
  result.message = "Repair approved"

proc repairShip*(state: GameState, fleetId: FleetId, shipId: ShipId): bool =
  ## Immediately repair a crippled ship at a friendly shipyard
  ## Deducts repair cost from house treasury
  ## Returns true if repair successful

  # Find fleet (use proper state accessor per architecture.md)
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return false

  let fleet = fleetOpt.get()

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

  # Deduct cost from house treasury (use proper state accessor per architecture.md)
  let houseOpt = state.house(fleet.houseId)
  if houseOpt.isNone:
    return false
  var house = houseOpt.get()
  house.treasury -= validation.cost
  state.updateHouse(fleet.houseId, house)

  # Repair ship
  ship.state = CombatState.Undamaged
  state.updateShip(shipId, ship)

  return true

proc repairStarbase*(
    state: GameState, systemId: SystemId, starbaseIndex: int
): bool =
  ## Immediately repair a crippled starbase at colony shipyard
  ## Deducts repair cost from house treasury
  ## Returns true if repair successful

  # Check colony exists
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return false

  let colony = colonyOpt.get()

  # Get kastras (starbases) at colony
  let kastras = state.kastrasAtColony(colony.id)

  # Validate starbase index
  if starbaseIndex < 0 or starbaseIndex >= kastras.len:
    return false

  var kastra = kastras[starbaseIndex]

  # Check if kastra (starbase) is crippled
  if kastra.state != CombatState.Crippled:
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

  # Deduct cost from house treasury
  let houseOpt = state.house(colony.owner)
  if houseOpt.isNone:
    return false
  var house = houseOpt.get()
  house.treasury -= validation.cost
  state.updateHouse(colony.owner, house)

  # Repair kastra (starbase)
  kastra.state = CombatState.Undamaged
  state.updateKastra(kastra.id, kastra)

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

proc getCrippledStarbases*(state: GameState, colony: Colony): seq[(int, KastraId)] =
  ## Get list of crippled starbases (kastras) at colony
  ## Returns (starbase index, kastra ID) pairs
  result = @[]
  let kastras = state.kastrasAtColony(colony.id)
  for i, kastra in kastras:
    if kastra.state == CombatState.Crippled:
      result.add((i, kastra.id))
