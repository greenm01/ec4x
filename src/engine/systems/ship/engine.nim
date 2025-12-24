## Ship Engine - High-level coordination for ship operations
##
## This module provides coordination functions that bridge:
## - ship/entity.nim (business logic, cargo operations)
## - facilities/repair_queue.nim (repair coordination)
## - State validation and error handling
##
## Per DoD architecture: This is the coordination layer that validates
## state, calls entity-level functions, and handles cross-system interactions.
##
## **Cargo Operations:**
## - loadShipCargo: Load marines/colonists onto transport ships
## - unloadShipCargo: Unload cargo from transport ships
## - transferCargoToColony: Transfer cargo from ship to colony
## - transferCargoFromColony: Transfer cargo from colony to ship
##
## **Repair Operations:**
## - repairShip: Coordinate ship repairs via drydock queue
## - upgradeShipWEP: Stub for future (no retrofitting currently)

import std/[options, strformat]
import ../../types/[core, ship, game_state]
import ../../../common/logger
import ./entity as ship_entity  # Ship business logic

# Cargo Operations

type
  CargoTransferResult* = object
    ## Result of cargo transfer operation
    success*: bool
    error*: string
    amountTransferred*: int32

proc loadShipCargo*(
  ship: var Ship,
  cargoType: CargoType,
  amount: int32
): CargoTransferResult =
  ## Load cargo onto ship (marines or colonists)
  ## Validates ship type and capacity constraints
  ##
  ## **Usage:**
  ## ```nim
  ## let result = loadShipCargo(ship, CargoType.Marines, 5)
  ## if result.success:
  ##   echo "Loaded ", result.amountTransferred, " marines"
  ## ```

  # Validate ship is a transport
  if not ship.isTransport():
    return CargoTransferResult(
      success: false,
      error: "Ship is not a transport (ETAC/TroopTransport)",
      amountTransferred: 0
    )

  # Check if cargo hold initialized
  if ship.cargo.isNone:
    return CargoTransferResult(
      success: false,
      error: "Ship cargo hold not initialized",
      amountTransferred: 0
    )

  # Validate cargo type matches ship type
  let currentCargo = ship.cargo.get()
  if currentCargo.cargoType != CargoType.None and
     currentCargo.cargoType != cargoType:
    return CargoTransferResult(
      success: false,
      error: &"Ship already carrying {currentCargo.cargoType}, cannot load {cargoType}",
      amountTransferred: 0
    )

  # Calculate how much can actually be loaded
  let availableSpace = ship.availableCargoCapacity()
  let amountToLoad = min(amount, availableSpace)

  if amountToLoad <= 0:
    return CargoTransferResult(
      success: false,
      error: "Ship cargo hold is full",
      amountTransferred: 0
    )

  # Load cargo using entity function
  if ship.loadCargo(amountToLoad):
    return CargoTransferResult(
      success: true,
      error: "",
      amountTransferred: amountToLoad
    )
  else:
    return CargoTransferResult(
      success: false,
      error: "Failed to load cargo (capacity exceeded)",
      amountTransferred: 0
    )

proc unloadShipCargo*(
  ship: var Ship,
  amount: int32
): CargoTransferResult =
  ## Unload cargo from ship
  ## Use amount=0 to unload all cargo
  ##
  ## **Usage:**
  ## ```nim
  ## let result = unloadShipCargo(ship, 0)  # Unload all
  ## if result.success:
  ##   echo "Unloaded ", result.amountTransferred, " units"
  ## ```

  # Check if cargo hold exists
  if ship.cargo.isNone:
    return CargoTransferResult(
      success: false,
      error: "Ship has no cargo hold",
      amountTransferred: 0
    )

  # Check if cargo is empty
  if ship.isCargoEmpty():
    return CargoTransferResult(
      success: false,
      error: "Ship cargo hold is already empty",
      amountTransferred: 0
    )

  # Determine amount to unload (0 = all)
  let currentCargo = ship.cargo.get()
  let amountToUnload = if amount <= 0:
    currentCargo.quantity
  else:
    min(amount, currentCargo.quantity)

  # Unload cargo using entity function
  if ship.unloadCargo(amountToUnload):
    return CargoTransferResult(
      success: true,
      error: "",
      amountTransferred: amountToUnload
    )
  else:
    return CargoTransferResult(
      success: false,
      error: &"Failed to unload cargo (insufficient cargo: {currentCargo.quantity})",
      amountTransferred: 0
    )

proc transferCargoFromColony*(
  state: var GameState,
  shipId: ShipId,
  colonyId: SystemId,
  cargoType: CargoType,
  amount: int32
): CargoTransferResult =
  ## Transfer cargo from colony to ship
  ## Validates colony has cargo available and ship has capacity
  ##
  ## **Cargo Types:**
  ## - Marines: Transferred from colony.marines to TroopTransport
  ## - Colonists: Transferred from colony.souls to ETAC (1 PTU = soulsPerPtu())
  ##
  ## **Note:** This is for manual cargo operations.
  ## Auto-loading handled by fleet/mechanics.nim:autoLoadCargo()

  # This is a placeholder for future implementation
  # For now, cargo operations are handled directly in fleet/mechanics.nim
  # and command/logistics.nim

  return CargoTransferResult(
    success: false,
    error: "Manual cargo transfers not yet implemented - use zero-turn commands",
    amountTransferred: 0
  )

proc transferCargoToColony*(
  state: var GameState,
  shipId: ShipId,
  colonyId: SystemId,
  amount: int32
): CargoTransferResult =
  ## Transfer cargo from ship to colony
  ## Amount=0 unloads all cargo
  ##
  ## **Cargo Types:**
  ## - Marines: Transferred to colony.marines
  ## - Colonists: Used for colonization (ship is cannibalized)
  ##
  ## **Note:** Colonization handled by fleet/mechanics.nim:resolveColonizationCommand()

  # This is a placeholder for future implementation
  # For now, cargo operations are handled directly in fleet/mechanics.nim
  # and conflict/simultaneous.nim for colonization

  return CargoTransferResult(
    success: false,
    error: "Manual cargo transfers not yet implemented - use zero-turn commands",
    amountTransferred: 0
  )

# Repair Operations

type
  RepairResult* = object
    ## Result of ship repair operation
    success*: bool
    error*: string
    repairCost*: int32
    turnsRequired*: int32

proc repairShip*(
  state: var GameState,
  shipId: ShipId,
  colonyId: SystemId
): RepairResult =
  ## Coordinate ship repair via drydock at colony
  ##
  ## **Process:**
  ## 1. Validates ship is at colony and is crippled
  ## 2. Validates colony has available drydock capacity
  ## 3. Creates repair project in drydock queue
  ## 4. Extracts ship from fleet into repair queue
  ##
  ## **Note:** Actual repair logic handled by facilities/repair_queue.nim
  ## This function is a stub for future coordination

  # This is a placeholder for future implementation
  # For now, repairs are handled automatically by facilities/repair_queue.nim
  # which processes crippled ships at colonies with drydocks

  return RepairResult(
    success: false,
    error: "Manual ship repairs not yet implemented - automatic via drydock queue",
    repairCost: 0,
    turnsRequired: 0
  )

proc upgradeShipWEP*(
  state: var GameState,
  shipId: ShipId,
  newWEPLevel: int32
): RepairResult =
  ## Upgrade ship to new WEP tech level
  ##
  ## **IMPORTANT:** Ship retrofitting is NOT currently supported in the game.
  ## Per docs/specs/04-research_development.md:
  ## "There is no retrofitting system. Ships built at WEP III remain WEP III forever.
  ##  To upgrade your fleet, you must salvage old ships and build replacements."
  ##
  ## **This stub exists for potential future implementation.**

  return RepairResult(
    success: false,
    error: "Ship retrofitting not supported - must salvage and rebuild",
    repairCost: 0,
    turnsRequired: 0
  )
