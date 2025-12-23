## Zero-Turn Command System for EC4X
##
## Unified administrative command system for fleet/cargo/squadron operations
## Execute immediately during order submission (0 turns, at friendly colonies)
##
## Architecture:
## - Consolidates FleetManagementCommand, CargoManagementOrder, SquadronManagementOrder
## - Separate from OrderPacket system (NOT queued for turn resolution)
## - Execute synchronously during order submission phase
## - Only available at friendly colonies (logistics infrastructure requirement)
## - Follows DRY principles with shared validation and cleanup helpers
##
## Usage:
##   let cmd = ZeroTurnCommand(...)
##   let result = submitZeroTurnCommand(state, cmd)
##   if result.success: echo "Success!"

import ../[gamestate, fleet, squadron, logger]
import ../index_maintenance
import ../../common/types/core
import ../config/population_config  # For population config (soulsPerPtu, ptuSizeMillions)
import ../economy/capacity/carrier_hangar  # For carrier capacity checks
import ../resolution/[event_factory/init as event_factory, types as resolution_types]
import std/[options, algorithm, tables, strformat, sequtils]

# ============================================================================
# Type Definitions
# ============================================================================

type
  ZeroTurnCommandType* {.pure.} = enum
    ## Administrative commands that execute immediately (0 turns)
    ## All require fleet/squadron to be at friendly colony
    ## Execute during order submission phase, NOT turn resolution

    # Fleet reorganization (from FleetManagementCommand)
    DetachShips        ## Split ships from fleet → create new fleet
    TransferShips      ## Move ships between existing fleets
    MergeFleets        ## Merge entire source fleet into target fleet

    # Cargo operations (from CargoManagementOrder)
    LoadCargo          ## Load marines/colonists onto transport squadrons
    UnloadCargo        ## Unload cargo from transport squadrons

    # Fighter operations (from FighterManagementOrder)
    LoadFighters       ## Load fighter squadrons from colony to carrier
    UnloadFighters     ## Unload fighter squadrons from carrier to colony
    TransferFighters   ## Transfer fighter squadrons between carriers

    # Squadron operations (from SquadronManagementOrder)
    FormSquadron       ## Create squadron from commissioned ships pool
    TransferShipBetweenSquadrons  ## Move individual ship between squadrons
    AssignSquadronToFleet         ## Move squadron between fleets (or create new fleet)

  ZeroTurnCommand* = object
    ## Immediate-execution administrative command
    ## Executes synchronously during order submission (NOT in OrderPacket)
    ## Returns immediate result (success/failure + error message)
    houseId*: HouseId
    commandType*: ZeroTurnCommandType

    # Context (varies by command type)
    colonySystem*: Option[SystemId]      ## Colony where action occurs (for squadron ops)
    sourceFleetId*: Option[FleetId]      ## Source fleet for fleet/cargo operations
    targetFleetId*: Option[FleetId]      ## Target fleet for transfer/merge

    # Ship/squadron selection
    shipIndices*: seq[int]               ## For ship selection (DetachShips, FormSquadron)
    sourceSquadronId*: Option[string]    ## For TransferShipBetweenSquadrons
    targetSquadronId*: Option[string]    ## For TransferShipBetweenSquadrons
    squadronId*: Option[string]          ## For AssignSquadronToFleet
    shipIndex*: Option[int]              ## For TransferShipBetweenSquadrons (single ship)

    # Cargo-specific
    cargoType*: Option[CargoType]        ## Type: Marines, Colonists
    cargoQuantity*: Option[int]          ## Amount to load/unload (0 = all available)

    # Fighter-specific
    fighterSquadronIndices*: seq[int]           ## Colony fighter squadron indices (for LoadFighters)
    carrierSquadronId*: Option[string]          ## Carrier squadron ID (for Load/Unload)
    embarkedFighterIndices*: seq[int]           ## Embarked fighter indices (for Unload/Transfer)
    sourceCarrierSquadronId*: Option[string]    ## Source carrier (for TransferFighters)
    targetCarrierSquadronId*: Option[string]    ## Target carrier (for TransferFighters)

    # Squadron formation
    newSquadronId*: Option[string]       ## Custom squadron ID for FormSquadron
    newFleetId*: Option[FleetId]         ## Custom fleet ID for DetachShips/AssignSquadronToFleet

  ZeroTurnResult* = object
    ## Immediate result from zero-turn command execution
    success*: bool
    error*: string                       ## Human-readable error message

    # Optional result data
    newFleetId*: Option[FleetId]         ## For DetachShips, AssignSquadronToFleet
    newSquadronId*: Option[string]       ## For FormSquadron
    cargoLoaded*: int                    ## For LoadCargo (actual amount loaded)
    cargoUnloaded*: int                  ## For UnloadCargo (actual amount unloaded)
    fightersLoaded*: int                 ## For LoadFighters (squadrons loaded)
    fightersUnloaded*: int               ## For UnloadFighters (squadrons unloaded)
    fightersTransferred*: int            ## For TransferFighters (squadrons transferred)
    warnings*: seq[string]               ## Non-fatal issues

  ValidationResult* = object
    ## Validation result (used internally)
    valid*: bool
    error*: string

# ============================================================================
# Shared Validation Helpers (DRY)
# ============================================================================

proc validateOwnership*(state: GameState, houseId: HouseId): ValidationResult =
  ## DRY: Validate house exists
  if houseId notin state.houses:
    return ValidationResult(valid: false, error: "House does not exist")
  return ValidationResult(valid: true, error: "")

proc validateFleetAtFriendlyColony*(state: GameState, fleetId: FleetId, houseId: HouseId): ValidationResult =
  ## DRY: Validate fleet exists, is owned by house, and is at friendly colony
  ## CRITICAL: All zero-turn fleet/cargo operations require friendly colony

  # 1. Check fleet exists
  if not state.fleets.hasKey(fleetId):
    return ValidationResult(valid: false, error: "Fleet not found")

  let fleet = state.fleets[fleetId]

  # 2. Check ownership
  if fleet.owner != houseId:
    return ValidationResult(valid: false, error: "Fleet not owned by house")

  # 3. CRITICAL: Fleet must be at friendly colony
  var colonyFound = false
  var colonyOwner: HouseId = ""

  for colony in state.colonies.values:
    if colony.systemId == fleet.location:
      colonyFound = true
      colonyOwner = colony.owner
      break

  if not colonyFound:
    return ValidationResult(valid: false, error: "Fleet must be at a colony for zero-turn operations")

  if colonyOwner != houseId:
    return ValidationResult(valid: false, error: "Fleet must be at a friendly colony for zero-turn operations")

  return ValidationResult(valid: true, error: "")

proc validateColonyOwnership*(state: GameState, systemId: SystemId, houseId: HouseId): ValidationResult =
  ## DRY: Validate colony exists and is owned by house

  if systemId notin state.colonies:
    return ValidationResult(valid: false, error: "Colony not found")

  let colony = state.colonies[systemId]
  if colony.owner != houseId:
    return ValidationResult(valid: false, error: "Colony not owned by house")

  return ValidationResult(valid: true, error: "")

proc validateShipIndices*(fleet: Fleet, indices: seq[int]): ValidationResult =
  ## DRY: Validate ship indices are valid and not selecting all ships

  let allShips = fleet.getAllShips()

  # Must select at least one ship
  if indices.len == 0:
    return ValidationResult(valid: false, error: "Must select at least one ship")

  # Validate each index
  for idx in indices:
    if idx < 0 or idx >= allShips.len:
      return ValidationResult(valid: false, error: "Invalid ship index: " & $idx)

  # Check for duplicate indices
  var seenIndices: seq[int] = @[]
  for idx in indices:
    if idx in seenIndices:
      return ValidationResult(valid: false, error: "Duplicate ship index: " & $idx)
    seenIndices.add(idx)

  return ValidationResult(valid: true, error: "")

# ============================================================================
# Main Validation Dispatcher
# ============================================================================

proc validateZeroTurnCommand*(state: GameState, cmd: ZeroTurnCommand): ValidationResult =
  ## Validate zero-turn command
  ## Multi-layer validation strategy:
  ##   Layer 1: Basic validation (house exists)
  ##   Layer 2: Fleet operations validation (ownership, location)
  ##   Layer 3: Squadron operations validation (colony ownership)
  ##   Layer 4: Command-specific validation

  # Layer 1: Basic validation
  result = validateOwnership(state, cmd.houseId)
  if not result.valid:
    return result

  # Layer 2: Fleet operations validation (requires colony)
  if cmd.commandType in {ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips,
                         ZeroTurnCommandType.MergeFleets, ZeroTurnCommandType.LoadCargo,
                         ZeroTurnCommandType.UnloadCargo, ZeroTurnCommandType.LoadFighters,
                         ZeroTurnCommandType.UnloadFighters}:
    if cmd.sourceFleetId.isNone:
      return ValidationResult(valid: false, error: "Source fleet ID required")

    result = validateFleetAtFriendlyColony(state, cmd.sourceFleetId.get(), cmd.houseId)
    if not result.valid:
      return result

  # Layer 3: Squadron operations validation
  if cmd.commandType in {ZeroTurnCommandType.FormSquadron, ZeroTurnCommandType.TransferShipBetweenSquadrons,
                         ZeroTurnCommandType.AssignSquadronToFleet}:
    if cmd.colonySystem.isNone:
      return ValidationResult(valid: false, error: "Colony system required for squadron operations")

    result = validateColonyOwnership(state, cmd.colonySystem.get(), cmd.houseId)
    if not result.valid:
      return result

  # Layer 4: Command-specific validation
  case cmd.commandType
  of ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips:
    # Validate ship indices
    let fleet = state.fleets[cmd.sourceFleetId.get()]
    result = validateShipIndices(fleet, cmd.shipIndices)
    if not result.valid:
      return result

    # DetachShips specific: cannot detach transport-only fleet (except ETACs)
    if cmd.commandType == ZeroTurnCommandType.DetachShips:
      let squadronIndices = fleet.translateShipIndicesToSquadrons(cmd.shipIndices)

      # Check if only Expansion squadrons (ETACs) are being detached
      # ETACs don't need combat escorts, but transports do
      if squadronIndices.len > 0:
        var onlyExpansion = true
        var hasNonETAC = false

        for idx in squadronIndices:
          let squadron = fleet.squadrons[idx]
          if squadron.squadronType != SquadronType.Expansion:
            onlyExpansion = false
          elif squadron.flagship.shipClass != ShipClass.ETAC:
            hasNonETAC = true

        if onlyExpansion and hasNonETAC:
          # Only detaching Expansion squadrons, but some are non-ETAC transports
          # These need combat escorts
          return ValidationResult(valid: false, error: "Cannot detach non-ETAC transport squadrons without combat escorts")

    # TransferShips specific: validate target fleet
    if cmd.commandType == ZeroTurnCommandType.TransferShips:
      if cmd.targetFleetId.isNone:
        return ValidationResult(valid: false, error: "Target fleet ID required for transfer")

      let targetFleetId = cmd.targetFleetId.get()
      if not state.fleets.hasKey(targetFleetId):
        return ValidationResult(valid: false, error: "Target fleet not found")

      let targetFleet = state.fleets[targetFleetId]
      if targetFleet.owner != cmd.houseId:
        return ValidationResult(valid: false, error: "Target fleet not owned by house")

      let sourceFleet = state.fleets[cmd.sourceFleetId.get()]
      if targetFleet.location != sourceFleet.location:
        return ValidationResult(valid: false, error: "Both fleets must be at same location")

      # Check scout/combat fleet mixing (validate after transfer would occur)
      # TODO: This is a simplified check - ideally we'd simulate the transfer
      # and check if the result would mix scouts with combat ships
      let mergeCheck = sourceFleet.canMergeWith(targetFleet)
      if not mergeCheck.canMerge:
        return ValidationResult(valid: false, error: mergeCheck.reason)

  of ZeroTurnCommandType.MergeFleets:
    # Validate target fleet
    if cmd.targetFleetId.isNone:
      return ValidationResult(valid: false, error: "Target fleet ID required for merge")

    let targetFleetId = cmd.targetFleetId.get()
    if not state.fleets.hasKey(targetFleetId):
      return ValidationResult(valid: false, error: "Target fleet not found")

    let targetFleet = state.fleets[targetFleetId]
    if targetFleet.owner != cmd.houseId:
      return ValidationResult(valid: false, error: "Target fleet not owned by house")

    let sourceFleet = state.fleets[cmd.sourceFleetId.get()]
    if targetFleet.location != sourceFleet.location:
      return ValidationResult(valid: false, error: "Both fleets must be at same location")

    # Cannot merge fleet into itself
    if cmd.sourceFleetId.get() == targetFleetId:
      return ValidationResult(valid: false, error: "Cannot merge fleet into itself")

    # Check scout/combat fleet mixing
    let mergeCheck = sourceFleet.canMergeWith(targetFleet)
    if not mergeCheck.canMerge:
      return ValidationResult(valid: false, error: mergeCheck.reason)

  of ZeroTurnCommandType.LoadCargo, ZeroTurnCommandType.UnloadCargo:
    # Validate cargo type specified for LoadCargo
    if cmd.commandType == ZeroTurnCommandType.LoadCargo:
      if cmd.cargoType.isNone:
        return ValidationResult(valid: false, error: "Cargo type required for LoadCargo")

  of ZeroTurnCommandType.LoadFighters:
    # Validate carrier squadron ID
    if cmd.carrierSquadronId.isNone:
      return ValidationResult(valid: false, error: "Carrier squadron ID required")
    # Validate at least one fighter squadron selected
    if cmd.fighterSquadronIndices.len == 0:
      return ValidationResult(valid: false, error: "Must select at least one fighter squadron to load")

  of ZeroTurnCommandType.UnloadFighters:
    # Validate carrier squadron ID
    if cmd.carrierSquadronId.isNone:
      return ValidationResult(valid: false, error: "Carrier squadron ID required")
    # Validate at least one embarked fighter selected
    if cmd.embarkedFighterIndices.len == 0:
      return ValidationResult(valid: false, error: "Must select at least one embarked fighter to unload")

  of ZeroTurnCommandType.TransferFighters:
    # TransferFighters can happen anywhere (mobile operations)
    # Validate source and target carrier squadron IDs
    if cmd.sourceCarrierSquadronId.isNone:
      return ValidationResult(valid: false, error: "Source carrier squadron ID required")
    if cmd.targetCarrierSquadronId.isNone:
      return ValidationResult(valid: false, error: "Target carrier squadron ID required")
    if cmd.sourceCarrierSquadronId.get() == cmd.targetCarrierSquadronId.get():
      return ValidationResult(valid: false, error: "Cannot transfer fighters to same carrier")
    # Validate at least one embarked fighter selected
    if cmd.embarkedFighterIndices.len == 0:
      return ValidationResult(valid: false, error: "Must select at least one embarked fighter to transfer")
    # Validate both carriers exist and are at same location
    if cmd.sourceFleetId.isNone:
      return ValidationResult(valid: false, error: "Source fleet ID required")
    let sourceFleet = state.fleets[cmd.sourceFleetId.get()]
    # Find both carriers and ensure they're in same fleet or adjacent fleets at same location
    # (detailed validation in execute function)

  of ZeroTurnCommandType.FormSquadron:
    # Must specify ships from commissioned pool
    if cmd.shipIndices.len == 0:
      return ValidationResult(valid: false, error: "Must select at least one ship for squadron")

  of ZeroTurnCommandType.TransferShipBetweenSquadrons:
    # Must specify source/target squadrons and ship index
    if cmd.sourceSquadronId.isNone or cmd.targetSquadronId.isNone or cmd.shipIndex.isNone:
      return ValidationResult(valid: false, error: "Must specify source squadron, target squadron, and ship index")

  of ZeroTurnCommandType.AssignSquadronToFleet:
    # Must specify squadron
    if cmd.squadronId.isNone:
      return ValidationResult(valid: false, error: "Must specify squadron ID")

  return ValidationResult(valid: true, error: "")

# ============================================================================
# Shared Cleanup Helper (DRY)
# ============================================================================

proc cleanupEmptyFleet*(state: var GameState, fleetId: FleetId) =
  ## DRY: Remove fleet and cleanup all associated orders
  ## Used by TransferShips, MergeFleets, AssignSquadronToFleet, DetachShips
  ## NOTE: Caller must ensure fleet should be deleted (this doesn't check isEmpty)
  if fleetId in state.fleets:
    let fleet = state.fleets[fleetId]
    state.removeFleetFromIndices(fleetId, fleet.owner, fleet.location)
    state.fleets.del(fleetId)
    if fleetId in state.fleetOrders:
      state.fleetOrders.del(fleetId)
    if fleetId in state.standingOrders:
      state.standingOrders.del(fleetId)
    logInfo(LogCategory.lcFleet, &"Removed fleet {fleetId} and associated orders")

# ============================================================================
# Execution - Fleet Operations (from fleet_commands.nim)
# ============================================================================

proc executeDetachShips*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Split ships from source fleet to create new fleet
  ## Both fleets remain at same location

  # Get source fleet (CRITICAL: Table copy semantics - get-modify-write)
  var sourceFleet = state.fleets[cmd.sourceFleetId.get()]
  let systemId = sourceFleet.location

  # Translate ship indices to squadron indices
  let squadronIndices = sourceFleet.translateShipIndicesToSquadrons(cmd.shipIndices)

  # Split squadrons (existing proc)
  let splitResult = sourceFleet.split(squadronIndices)

  # Generate new fleet ID if not provided
  let newFleetId = if cmd.newFleetId.isSome:
    cmd.newFleetId.get()
  else:
    cmd.houseId & "_fleet_" & $state.turn & "_" & $state.fleets.len

  # Create new fleet
  var newFleet = Fleet(
    id: newFleetId,
    squadrons: splitResult.squadrons,
    owner: cmd.houseId,
    location: sourceFleet.location,
    status: FleetStatus.Active,
    autoBalanceSquadrons: true
  )

  let squadronsDetached = newFleet.squadrons.len

  # Balance squadrons in BOTH fleets
  sourceFleet.balanceSquadrons()
  newFleet.balanceSquadrons()

  # Check if source fleet is now empty after detaching
  if sourceFleet.isEmpty():
    # Delete empty source fleet and cleanup orders
    cleanupEmptyFleet(state, cmd.sourceFleetId.get())
    logInfo(LogCategory.lcFleet, &"DetachShips: Detached all ships from {cmd.sourceFleetId.get()}, deleted source fleet, created new fleet {newFleetId}")
  else:
    # Write back modified source fleet
    state.fleets[cmd.sourceFleetId.get()] = sourceFleet
    logInfo(LogCategory.lcFleet, &"DetachShips: Created fleet {newFleetId} with {newFleet.squadrons.len} squadrons")

  # Write new fleet to state
  state.fleets[newFleetId] = newFleet

  # Emit FleetDetachment event (Phase 7b)
  events.add(event_factory.fleetDetachment(
    cmd.houseId,
    cmd.sourceFleetId.get(),
    newFleetId,
    squadronsDetached,
    systemId
  ))

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: some(newFleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

proc executeTransferShips*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Move ships from source fleet to target fleet
  ## If source becomes empty, it's deleted

  let targetFleetId = cmd.targetFleetId.get()

  # Get both fleets (CRITICAL: Table copy semantics)
  var sourceFleet = state.fleets[cmd.sourceFleetId.get()]
  var targetFleet = state.fleets[targetFleetId]
  let systemId = sourceFleet.location

  # Translate ship indices to squadron indices
  let squadronIndices = sourceFleet.translateShipIndicesToSquadrons(cmd.shipIndices)
  let squadronsTransferred = squadronIndices.len

  # Transfer squadrons
  let transferredFleet = sourceFleet.split(squadronIndices)
  targetFleet.merge(transferredFleet)

  # Balance both fleets
  sourceFleet.balanceSquadrons()
  targetFleet.balanceSquadrons()

  # Write back modified target fleet first
  state.fleets[targetFleetId] = targetFleet

  # Check if source fleet is now empty
  if sourceFleet.isEmpty():
    # Delete empty fleet and cleanup orders (DRY helper)
    # NOTE: We don't write sourceFleet back since we're deleting it
    cleanupEmptyFleet(state, cmd.sourceFleetId.get())
    logInfo(LogCategory.lcFleet, &"TransferShips: Merged all ships from {cmd.sourceFleetId.get()} into {targetFleetId}, deleted source fleet")
  else:
    # Write back modified source fleet
    state.fleets[cmd.sourceFleetId.get()] = sourceFleet
    logInfo(LogCategory.lcFleet, &"TransferShips: Transferred {squadronIndices.len} squadrons from {cmd.sourceFleetId.get()} to {targetFleetId}")

  # Emit FleetTransfer event (Phase 7b)
  events.add(event_factory.fleetTransfer(
    cmd.houseId,
    cmd.sourceFleetId.get(),
    targetFleetId,
    squadronsTransferred,
    systemId
  ))

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

proc executeMergeFleets*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Merge entire source fleet into target fleet (0 turns, at colony)
  ## Source fleet is deleted, all ships transferred to target
  ##
  ## This is different from Order 13 (Join Fleet):
  ## - MergeFleets: Immediate execution (0 turns) at colony
  ## - Order 13: Can involve travel, executes during Command Phase

  let targetFleetId = cmd.targetFleetId.get()

  # Get both fleets (CRITICAL: Table copy semantics)
  let sourceFleet = state.fleets[cmd.sourceFleetId.get()]
  var targetFleet = state.fleets[targetFleetId]

  let squadronsMerged = sourceFleet.squadrons.len
  let systemId = sourceFleet.location

  # Merge all squadrons
  targetFleet.merge(sourceFleet)

  # Balance target fleet after merge
  targetFleet.balanceSquadrons()

  # Write back modified target fleet
  state.fleets[targetFleetId] = targetFleet

  # Delete source fleet from state table
  let sourceFleetId = cmd.sourceFleetId.get()
  state.removeFleetFromIndices(sourceFleetId, sourceFleet.owner,
                               sourceFleet.location)
  state.fleets.del(sourceFleetId)

  # Cleanup associated orders
  if sourceFleetId in state.fleetOrders:
    state.fleetOrders.del(sourceFleetId)
  if sourceFleetId in state.standingOrders:
    state.standingOrders.del(sourceFleetId)

  logInfo(LogCategory.lcFleet, &"MergeFleets: Merged {sourceFleet.squadrons.len} squadrons from {cmd.sourceFleetId.get()} into {targetFleetId}")

  # Emit FleetMerged event (Phase 7b)
  events.add(event_factory.fleetMerged(
    cmd.houseId,
    cmd.sourceFleetId.get(),
    targetFleetId,
    squadronsMerged,
    systemId
  ))

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

# ============================================================================
# Execution - Cargo Operations (from economy_resolution.nim)
# ============================================================================

proc executeLoadCargo*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Load marines or colonists onto transport squadrons at colony
  ## Source: economy_resolution.nim:409-501

  let cargoType = cmd.cargoType.get()
  let fleetId = cmd.sourceFleetId.get()
  var requestedQty = if cmd.cargoQuantity.isSome: cmd.cargoQuantity.get() else: 0  # 0 = all available

  # Get fleet location to find colony
  let fleet = state.fleets[fleetId]
  let colonySystem = fleet.location

  # Get mutable colony and fleet
  var colony = state.colonies[colonySystem]
  var mutableFleet = fleet
  var totalLoaded = 0

  # Check colony inventory based on cargo type
  var availableUnits = case cargoType
    of CargoType.Marines: colony.marines
    of CargoType.Colonists:
      # Calculate how many complete PTUs can be loaded from exact population
      # Using souls field for accurate counting (no float rounding errors)
      # Per config/population.toml [transfer_limits] min_source_pu_remaining = 1
      # Must keep 1 PU minimum at source colony
      let minSoulsToKeep = 1_000_000  # 1 PU = 1 million souls
      if colony.souls <= minSoulsToKeep:
        0  # Cannot load any PTUs, colony at minimum viable population
      else:
        let availableSouls = colony.souls - minSoulsToKeep
        let maxPTUs = availableSouls div soulsPerPtu()
        maxPTUs
    else: 0

  if availableUnits <= 0:
    return ZeroTurnResult(
      success: false,
      error: &"No {cargoType} available at colony {colonySystem}",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # If quantity = 0, load all available
  if requestedQty == 0:
    requestedQty = availableUnits

  # Load cargo onto compatible transport squadrons (Expansion/Auxiliary flagships)
  var remainingToLoad = min(requestedQty, availableUnits)

  for squadron in mutableFleet.squadrons.mitems:
    if remainingToLoad <= 0:
      break

    # Only Expansion and Auxiliary squadrons carry cargo
    if squadron.squadronType notin {SquadronType.Expansion, SquadronType.Auxiliary}:
      continue

    if squadron.flagship.isCrippled:
      continue

    # Determine ship capacity and compatible cargo type
    let shipCargoType = case squadron.flagship.shipClass
      of ShipClass.TroopTransport: CargoType.Marines
      of ShipClass.ETAC: CargoType.Colonists
      else: CargoType.None

    if shipCargoType != cargoType:
      continue  # Ship can't carry this cargo type

    # Try to load cargo onto this flagship
    let currentCargo = if squadron.flagship.cargo.isSome: squadron.flagship.cargo.get() else: ShipCargo(cargoType: CargoType.None, quantity: 0, capacity: 0)
    let loadAmount = min(remainingToLoad, currentCargo.capacity - currentCargo.quantity)

    if loadAmount > 0:
      var newCargo = currentCargo
      newCargo.cargoType = cargoType
      newCargo.quantity += loadAmount
      squadron.flagship.cargo = some(newCargo)

      totalLoaded += loadAmount
      remainingToLoad -= loadAmount
      logDebug(LogCategory.lcEconomy, &"Loaded {loadAmount} {cargoType} onto {squadron.flagship.shipClass} squadron {squadron.id}")

  # Update colony inventory
  if totalLoaded > 0:
    case cargoType
    of CargoType.Marines:
      colony.marines -= totalLoaded
    of CargoType.Colonists:
      # Colonists come from population: 1 PTU = 50k souls
      # Use souls field for exact counting (no rounding errors)
      let soulsToLoad = totalLoaded * soulsPerPtu()
      colony.souls -= soulsToLoad
      # Update display field (population in millions)
      colony.population = colony.souls div 1_000_000
      logDebug(LogCategory.lcEconomy, &"Removed {totalLoaded} PTU ({soulsToLoad} souls, {totalLoaded.float * ptuSizeMillions()}M) from colony")
    else:
      discard

    # Write back modified state
    state.fleets[fleetId] = mutableFleet
    state.colonies[colonySystem] = colony
    logInfo(LogCategory.lcEconomy, &"LoadCargo: Successfully loaded {totalLoaded} {cargoType} onto fleet {fleetId} at system {colonySystem}")

    # Emit CargoLoaded event (Phase 7b)
    events.add(event_factory.cargoLoaded(
      cmd.houseId,
      fleetId,
      $cargoType,
      totalLoaded,
      colonySystem
    ))

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: totalLoaded,
    cargoUnloaded: 0,
    warnings: if remainingToLoad > 0: @[&"Only loaded {totalLoaded} of {requestedQty} requested (capacity or availability limit)"] else: @[]
  )

proc executeUnloadCargo*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Unload cargo from transport squadrons at colony
  ## Source: economy_resolution.nim:503-547

  let fleetId = cmd.sourceFleetId.get()

  # Get fleet location to find colony
  let fleet = state.fleets[fleetId]
  let colonySystem = fleet.location

  # Get mutable colony and fleet
  var colony = state.colonies[colonySystem]
  var mutableFleet = fleet
  var totalUnloaded = 0
  var unloadedType = CargoType.None

  # Unload cargo from transport squadrons (Expansion/Auxiliary flagships)
  for squadron in mutableFleet.squadrons.mitems:
    # Only Expansion and Auxiliary squadrons carry cargo
    if squadron.squadronType notin {SquadronType.Expansion, SquadronType.Auxiliary}:
      continue

    if squadron.flagship.cargo.isNone:
      continue  # No cargo to unload

    let cargo = squadron.flagship.cargo.get()
    if cargo.cargoType == CargoType.None or cargo.quantity == 0:
      continue  # Empty cargo

    # Unload cargo back to colony inventory
    let cargoType = cargo.cargoType
    let quantity = cargo.quantity
    totalUnloaded += quantity
    unloadedType = cargoType

    case cargoType
    of CargoType.Marines:
      colony.marines += quantity
      logDebug(LogCategory.lcEconomy, &"Unloaded {quantity} Marines from squadron {squadron.id} to colony")
    of CargoType.Colonists:
      # Colonists are delivered to population: 1 PTU = 50k souls
      # Use souls field for exact counting (no rounding errors)
      let soulsToUnload = quantity * soulsPerPtu()
      colony.souls += soulsToUnload
      # Update display field (population in millions)
      colony.population = colony.souls div 1_000_000
      logDebug(LogCategory.lcEconomy, &"Unloaded {quantity} PTU ({soulsToUnload} souls, {quantity.float * ptuSizeMillions()}M) from squadron {squadron.id} to colony")
    else:
      discard

    # Clear cargo from flagship
    squadron.flagship.cargo = some(ShipCargo(cargoType: CargoType.None, quantity: 0, capacity: cargo.capacity))

  # Write back modified state
  if totalUnloaded > 0:
    state.fleets[fleetId] = mutableFleet
    state.colonies[colonySystem] = colony
    logInfo(LogCategory.lcEconomy, &"UnloadCargo: Successfully unloaded {totalUnloaded} {unloadedType} from fleet {fleetId} at system {colonySystem}")

    # Emit CargoUnloaded event (Phase 7b)
    events.add(event_factory.cargoUnloaded(
      cmd.houseId,
      fleetId,
      $unloadedType,
      totalUnloaded,
      colonySystem
    ))

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: totalUnloaded,
    warnings: if totalUnloaded == 0: @["No cargo to unload"] else: @[]
  )

# ============================================================================
# Execution - Squadron Operations (from economy_resolution.nim)
# ============================================================================

proc executeFormSquadron*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Create new squadron from colony's commissioned ships pool
  ## NEW: Not in current implementation - gives players manual control
  ## before auto-assignment runs during turn resolution

  let colonySystem = cmd.colonySystem.get()
  var colony = state.colonies[colonySystem]

  # Validate ships exist in unassigned pool
  if cmd.shipIndices.len > colony.unassignedSquadrons.len:
    return ZeroTurnResult(
      success: false,
      error: &"Only {colony.unassignedSquadrons.len} unassigned squadrons available at colony",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # For now, FormSquadron simply selects existing squadrons from unassigned pool
  # In the future, this could be extended to create squadrons from individual ships
  var selectedSquadrons: seq[Squadron] = @[]
  var remainingSquadrons: seq[Squadron] = @[]

  for i, squad in colony.unassignedSquadrons:
    if i in cmd.shipIndices:
      selectedSquadrons.add(squad)
    else:
      remainingSquadrons.add(squad)

  if selectedSquadrons.len == 0:
    return ZeroTurnResult(
      success: false,
      error: "No squadrons selected from unassigned pool",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # Update colony's unassigned squadrons
  colony.unassignedSquadrons = remainingSquadrons
  state.colonies[colonySystem] = colony

  # Generate squadron IDs (if not custom provided)
  let newSquadronId = if cmd.newSquadronId.isSome:
    cmd.newSquadronId.get()
  else:
    selectedSquadrons[0].id  # Use first selected squadron's ID as representative

  logInfo(LogCategory.lcFleet, &"FormSquadron: Selected {selectedSquadrons.len} squadrons from unassigned pool at {colonySystem}")

  # Note: Squadrons remain in unassigned pool but are now "formed" (tracked)
  # Player can then use AssignSquadronToFleet to assign to a fleet

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: some(newSquadronId),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[&"Selected {selectedSquadrons.len} squadrons, use AssignSquadronToFleet to assign to fleet"]
  )

proc executeTransferShipBetweenSquadrons*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Transfer ship between squadrons at this colony
  ## Source: economy_resolution.nim:216-291

  let colonySystem = cmd.colonySystem.get()

  # Find source and target squadrons in fleets at this colony
  var sourceFleetId: Option[FleetId] = none(FleetId)
  var targetFleetId: Option[FleetId] = none(FleetId)
  var sourceSquadIndex: int = -1
  var targetSquadIndex: int = -1

  # Locate source squadron
  for fleetId, fleet in state.fleets:
    if fleet.location == colonySystem and fleet.owner == cmd.houseId:
      for i, squad in fleet.squadrons:
        if squad.id == cmd.sourceSquadronId.get():
          sourceFleetId = some(fleetId)
          sourceSquadIndex = i
          break
      if sourceFleetId.isSome:
        break

  if sourceFleetId.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Source squadron {cmd.sourceSquadronId.get()} not found at colony",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # Locate target squadron
  for fleetId, fleet in state.fleets:
    if fleet.location == colonySystem and fleet.owner == cmd.houseId:
      for i, squad in fleet.squadrons:
        if squad.id == cmd.targetSquadronId.get():
          targetFleetId = some(fleetId)
          targetSquadIndex = i
          break
      if targetFleetId.isSome:
        break

  if targetFleetId.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Target squadron {cmd.targetSquadronId.get()} not found at colony",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # Remove ship from source squadron
  let shipIndex = cmd.shipIndex.get()
  var sourceFleet = state.fleets[sourceFleetId.get()]
  var sourceSquad = sourceFleet.squadrons[sourceSquadIndex]

  if shipIndex < 0 or shipIndex >= sourceSquad.ships.len:
    return ZeroTurnResult(
      success: false,
      error: &"Invalid ship index {shipIndex} (squadron has {sourceSquad.ships.len} ships)",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  let shipOpt = sourceSquad.removeShip(shipIndex)
  if shipOpt.isNone:
    return ZeroTurnResult(
      success: false,
      error: "Could not remove ship from source squadron",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  let ship = shipOpt.get()

  # Add ship to target squadron
  var targetFleet = state.fleets[targetFleetId.get()]
  var targetSquad = targetFleet.squadrons[targetSquadIndex]

  if not targetSquad.addShip(ship):
    # ROLLBACK: Put ship back in source squadron
    discard sourceSquad.addShip(ship)
    sourceFleet.squadrons[sourceSquadIndex] = sourceSquad
    state.fleets[sourceFleetId.get()] = sourceFleet
    return ZeroTurnResult(
      success: false,
      error: "Could not add ship to target squadron (may be full or incompatible)",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # Update both squadrons in state
  sourceFleet.squadrons[sourceSquadIndex] = sourceSquad
  targetFleet.squadrons[targetSquadIndex] = targetSquad
  state.fleets[sourceFleetId.get()] = sourceFleet
  state.fleets[targetFleetId.get()] = targetFleet

  logInfo(LogCategory.lcFleet, &"TransferShipBetweenSquadrons: Transferred ship from {cmd.sourceSquadronId.get()} to {cmd.targetSquadronId.get()}")

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

proc executeAssignSquadronToFleet*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Assign existing squadron to fleet (move between fleets or create new fleet)
  ## Source: economy_resolution.nim:293-382

  let colonySystem = cmd.colonySystem.get()
  var colony = state.colonies[colonySystem]

  # Find squadron in existing fleets at this colony
  var foundSquadron: Option[Squadron] = none(Squadron)
  var sourceFleetId: Option[FleetId] = none(FleetId)

  for fleetId, fleet in state.fleets:
    if fleet.location == colonySystem and fleet.owner == cmd.houseId:
      for i, squad in fleet.squadrons:
        if squad.id == cmd.squadronId.get():
          foundSquadron = some(squad)
          sourceFleetId = some(fleetId)
          break
      if foundSquadron.isSome:
        break

  # If not found in fleets, check unassigned squadrons at colony
  if foundSquadron.isNone:
    for i, squad in colony.unassignedSquadrons:
      if squad.id == cmd.squadronId.get():
        foundSquadron = some(squad)
        # Remove from unassigned list
        var newUnassigned: seq[Squadron] = @[]
        for j, s in colony.unassignedSquadrons:
          if j != i:
            newUnassigned.add(s)
        colony.unassignedSquadrons = newUnassigned
        state.colonies[colonySystem] = colony
        break

  if foundSquadron.isNone:
    return ZeroTurnResult(
      success: false,
      error: &"Squadron {cmd.squadronId.get()} not found at colony {colonySystem}",
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  let squadron = foundSquadron.get()

  # Remove squadron from source fleet
  if sourceFleetId.isSome:
    var srcFleet = state.fleets[sourceFleetId.get()]
    var newSquadrons: seq[Squadron] = @[]
    for squad in srcFleet.squadrons:
      if squad.id != cmd.squadronId.get():
        newSquadrons.add(squad)
    srcFleet.squadrons = newSquadrons
    state.fleets[sourceFleetId.get()] = srcFleet

    # If source fleet is now empty, remove it and clean up orders (DRY helper)
    if newSquadrons.len == 0:
      cleanupEmptyFleet(state, sourceFleetId.get())

  # Add squadron to target fleet or create new one
  var resultFleetId: FleetId
  if cmd.targetFleetId.isSome:
    # Assign to existing fleet
    let targetId = cmd.targetFleetId.get()
    if targetId in state.fleets:
      var targetFleet = state.fleets[targetId]
      # Only allow assignment to Active fleets (exclude Reserve and Mothballed)
      if targetFleet.status != FleetStatus.Active:
        return ZeroTurnResult(
          success: false,
          error: &"Cannot assign squadrons to {targetFleet.status} fleets (only Active fleets allowed)",
          newFleetId: none(FleetId),
          newSquadronId: none(string),
          cargoLoaded: 0,
          cargoUnloaded: 0,
          warnings: @[]
        )

      # CRITICAL: Validate squadron type compatibility (Intel never mixes)
      let squadronIsIntel = squadron.squadronType == SquadronType.Intel
      let fleetHasIntel = targetFleet.squadrons.anyIt(it.squadronType == SquadronType.Intel)
      let fleetHasNonIntel = targetFleet.squadrons.anyIt(it.squadronType != SquadronType.Intel)

      if squadronIsIntel and fleetHasNonIntel:
        return ZeroTurnResult(
          success: false,
          error: "Cannot assign Intel squadron to fleet with non-Intel squadrons (Intel operations require dedicated fleets)",
          newFleetId: none(FleetId),
          newSquadronId: none(string),
          cargoLoaded: 0,
          cargoUnloaded: 0,
          warnings: @[]
        )

      if not squadronIsIntel and fleetHasIntel:
        return ZeroTurnResult(
          success: false,
          error: "Cannot assign non-Intel squadron to Intel-only fleet (Intel operations require dedicated fleets)",
          newFleetId: none(FleetId),
          newSquadronId: none(string),
          cargoLoaded: 0,
          cargoUnloaded: 0,
          warnings: @[]
        )

      targetFleet.squadrons.add(squadron)
      state.fleets[targetId] = targetFleet
      resultFleetId = targetId
      logInfo(LogCategory.lcFleet, &"AssignSquadronToFleet: Assigned squadron {squadron.id} to existing fleet {targetId}")
    else:
      return ZeroTurnResult(
        success: false,
        error: &"Target fleet {targetId} does not exist",
        newFleetId: none(FleetId),
        newSquadronId: none(string),
        cargoLoaded: 0,
        cargoUnloaded: 0,
        warnings: @[]
      )
  else:
    # Create new fleet
    let newFleetId = if cmd.newFleetId.isSome:
      cmd.newFleetId.get()
    else:
      cmd.houseId & "_fleet_" & $colonySystem & "_" & $state.turn

    state.fleets[newFleetId] = Fleet(
      id: newFleetId,
      owner: cmd.houseId,
      location: colonySystem,
      squadrons: @[squadron],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    resultFleetId = newFleetId
    logInfo(LogCategory.lcFleet, &"AssignSquadronToFleet: Created new fleet {newFleetId} with squadron {squadron.id}")

  return ZeroTurnResult(
    success: true,
    error: "",
    newFleetId: some(resultFleetId),
    newSquadronId: none(string),
    cargoLoaded: 0,
    cargoUnloaded: 0,
    warnings: @[]
  )

# ============================================================================
# Execution - Fighter Operations
# ============================================================================

proc executeLoadFighters*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Load fighter squadrons from colony onto carrier
  ## Requires: Fleet at friendly colony, carrier with available hangar space

  let sourceFleetId = cmd.sourceFleetId.get()
  var sourceFleet = state.fleets[sourceFleetId]
  let systemId = sourceFleet.location
  let carrierSquadronId = cmd.carrierSquadronId.get()

  # Find carrier squadron in fleet
  var carrierSquadronIdx = -1
  for i, sq in sourceFleet.squadrons:
    if sq.id == carrierSquadronId:
      carrierSquadronIdx = i
      break

  if carrierSquadronIdx < 0:
    return ZeroTurnResult(
      success: false,
      error: "Carrier squadron not found in fleet",
      warnings: @[]
    )

  # Validate carrier
  let carrierSquadron = sourceFleet.squadrons[carrierSquadronIdx]
  if not carrierSquadron.isCarrier():
    return ZeroTurnResult(
      success: false,
      error: "Squadron is not a carrier (CV/CX required)",
      warnings: @[]
    )

  # Get colony
  if systemId notin state.colonies:
    return ZeroTurnResult(
      success: false,
      error: "No colony at fleet location",
      warnings: @[]
    )

  var colony = state.colonies[systemId]

  # Get ACO tech level for capacity calculation
  let acoLevel = state.houses[cmd.houseId].techTree.levels.advancedCarrierOps
  let maxCapacity = carrierSquadron.getCarrierCapacity(acoLevel)
  let currentLoad = carrierSquadron.embarkedFighters.len

  # Load fighters one at a time until capacity full or all requested loaded
  var loadedCount = 0
  var warnings: seq[string] = @[]

  for fighterIdx in cmd.fighterSquadronIndices:
    # Check capacity
    if currentLoad + loadedCount >= maxCapacity:
      warnings.add(&"Carrier at capacity ({maxCapacity} squadrons), remaining fighters not loaded")
      break

    # Validate fighter index
    if fighterIdx < 0 or fighterIdx >= colony.fighterSquadrons.len:
      warnings.add(&"Invalid fighter squadron index {fighterIdx}, skipping")
      continue

    # Load fighter
    let fighterSquadron = colony.fighterSquadrons[fighterIdx]
    sourceFleet.squadrons[carrierSquadronIdx].embarkedFighters.add(fighterSquadron)
    colony.fighterSquadrons.delete(fighterIdx)
    loadedCount += 1

    let totalFighters = 1 + fighterSquadron.ships.len
    logInfo(LogCategory.lcFleet,
      &"Loaded Fighter squadron {fighterSquadron.id} ({totalFighters}/12) " &
      &"onto carrier {carrierSquadronId} ({currentLoad + loadedCount}/{maxCapacity})")

  # Write back
  state.fleets[sourceFleetId] = sourceFleet
  state.colonies[systemId] = colony

  return ZeroTurnResult(
    success: true,
    error: "",
    fightersLoaded: loadedCount,
    warnings: warnings
  )

proc executeUnloadFighters*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Unload fighter squadrons from carrier to colony
  ## Requires: Fleet at friendly colony

  let sourceFleetId = cmd.sourceFleetId.get()
  var sourceFleet = state.fleets[sourceFleetId]
  let systemId = sourceFleet.location
  let carrierSquadronId = cmd.carrierSquadronId.get()

  # Find carrier squadron in fleet
  var carrierSquadronIdx = -1
  for i, sq in sourceFleet.squadrons:
    if sq.id == carrierSquadronId:
      carrierSquadronIdx = i
      break

  if carrierSquadronIdx < 0:
    return ZeroTurnResult(
      success: false,
      error: "Carrier squadron not found in fleet",
      warnings: @[]
    )

  # Get colony
  if systemId notin state.colonies:
    return ZeroTurnResult(
      success: false,
      error: "No colony at fleet location",
      warnings: @[]
    )

  var colony = state.colonies[systemId]

  # Unload fighters (reverse order to avoid index issues)
  var unloadedCount = 0
  var warnings: seq[string] = @[]
  var sortedIndices = cmd.embarkedFighterIndices
  sortedIndices.sort(system.cmp, order = SortOrder.Descending)

  for fighterIdx in sortedIndices:
    # Validate fighter index
    if fighterIdx < 0 or fighterIdx >= sourceFleet.squadrons[carrierSquadronIdx].embarkedFighters.len:
      warnings.add(&"Invalid embarked fighter index {fighterIdx}, skipping")
      continue

    # Unload fighter
    let fighterSquadron = sourceFleet.squadrons[carrierSquadronIdx].embarkedFighters[fighterIdx]
    colony.fighterSquadrons.add(fighterSquadron)
    sourceFleet.squadrons[carrierSquadronIdx].embarkedFighters.delete(fighterIdx)
    unloadedCount += 1

    let totalFighters = 1 + fighterSquadron.ships.len
    logInfo(LogCategory.lcFleet,
      &"Unloaded Fighter squadron {fighterSquadron.id} ({totalFighters}/12) " &
      &"from carrier {carrierSquadronId} to colony {systemId}")

  # Write back
  state.fleets[sourceFleetId] = sourceFleet
  state.colonies[systemId] = colony

  return ZeroTurnResult(
    success: true,
    error: "",
    fightersUnloaded: unloadedCount,
    warnings: warnings
  )

proc executeTransferFighters*(state: var GameState, cmd: ZeroTurnCommand, events: var seq[resolution_types.GameEvent]): ZeroTurnResult =
  ## Transfer fighter squadrons between carriers (mobile operations)
  ## Can happen anywhere - both carriers must be in same fleet or adjacent fleets at same location

  let sourceFleetId = cmd.sourceFleetId.get()
  let sourceCarrierSquadronId = cmd.sourceCarrierSquadronId.get()
  let targetCarrierSquadronId = cmd.targetCarrierSquadronId.get()

  # Find source carrier
  var sourceFleet = state.fleets[sourceFleetId]
  var sourceCarrierIdx = -1
  for i, sq in sourceFleet.squadrons:
    if sq.id == sourceCarrierSquadronId:
      sourceCarrierIdx = i
      break

  if sourceCarrierIdx < 0:
    return ZeroTurnResult(
      success: false,
      error: "Source carrier squadron not found",
      warnings: @[]
    )

  # Find target carrier (could be in same fleet or different fleet at same location)
  var targetFleet: Fleet
  var targetFleetId: FleetId
  var targetCarrierIdx = -1
  var targetInSameFleet = false

  # Check same fleet first
  for i, sq in sourceFleet.squadrons:
    if sq.id == targetCarrierSquadronId:
      targetCarrierIdx = i
      targetInSameFleet = true
      targetFleet = sourceFleet
      targetFleetId = sourceFleetId
      break

  # Check other fleets at same location
  if targetCarrierIdx < 0:
    for fid, fleet in state.fleets.mpairs:
      if fleet.location == sourceFleet.location and fleet.owner == cmd.houseId:
        for i, sq in fleet.squadrons:
          if sq.id == targetCarrierSquadronId:
            targetCarrierIdx = i
            targetFleet = fleet
            targetFleetId = fid
            break
        if targetCarrierIdx >= 0:
          break

  if targetCarrierIdx < 0:
    return ZeroTurnResult(
      success: false,
      error: "Target carrier squadron not found at same location",
      warnings: @[]
    )

  # Validate both are carriers
  if not sourceFleet.squadrons[sourceCarrierIdx].isCarrier():
    return ZeroTurnResult(
      success: false,
      error: "Source squadron is not a carrier",
      warnings: @[]
    )

  if not targetFleet.squadrons[targetCarrierIdx].isCarrier():
    return ZeroTurnResult(
      success: false,
      error: "Target squadron is not a carrier",
      warnings: @[]
    )

  # Get ACO tech level for capacity calculation
  let acoLevel = state.houses[cmd.houseId].techTree.levels.advancedCarrierOps
  let targetMaxCapacity = targetFleet.squadrons[targetCarrierIdx].getCarrierCapacity(acoLevel)
  let targetCurrentLoad = targetFleet.squadrons[targetCarrierIdx].embarkedFighters.len

  # Transfer fighters (reverse order to avoid index issues)
  var transferredCount = 0
  var warnings: seq[string] = @[]
  var sortedIndices = cmd.embarkedFighterIndices
  sortedIndices.sort(system.cmp, order = SortOrder.Descending)

  for fighterIdx in sortedIndices:
    # Check target capacity
    if targetCurrentLoad + transferredCount >= targetMaxCapacity:
      warnings.add(&"Target carrier at capacity ({targetMaxCapacity} squadrons), remaining fighters not transferred")
      break

    # Validate fighter index
    if fighterIdx < 0 or fighterIdx >= sourceFleet.squadrons[sourceCarrierIdx].embarkedFighters.len:
      warnings.add(&"Invalid embarked fighter index {fighterIdx}, skipping")
      continue

    # Transfer fighter
    let fighterSquadron = sourceFleet.squadrons[sourceCarrierIdx].embarkedFighters[fighterIdx]

    if targetInSameFleet:
      # Same fleet - direct transfer
      sourceFleet.squadrons[targetCarrierIdx].embarkedFighters.add(fighterSquadron)
      sourceFleet.squadrons[sourceCarrierIdx].embarkedFighters.delete(fighterIdx)
    else:
      # Different fleet - need to modify both
      targetFleet.squadrons[targetCarrierIdx].embarkedFighters.add(fighterSquadron)
      sourceFleet.squadrons[sourceCarrierIdx].embarkedFighters.delete(fighterIdx)

    transferredCount += 1

    let totalFighters = 1 + fighterSquadron.ships.len
    logInfo(LogCategory.lcFleet,
      &"Transferred Fighter squadron {fighterSquadron.id} ({totalFighters}/12) " &
      &"from carrier {sourceCarrierSquadronId} to {targetCarrierSquadronId}")

  # Write back
  state.fleets[sourceFleetId] = sourceFleet
  if not targetInSameFleet:
    state.fleets[targetFleetId] = targetFleet

  return ZeroTurnResult(
    success: true,
    error: "",
    fightersTransferred: transferredCount,
    warnings: warnings
  )

# ============================================================================
# Main API Entry Point
# ============================================================================

proc submitZeroTurnCommand*(
  state: var GameState,
  cmd: ZeroTurnCommand,
  events: var seq[resolution_types.GameEvent]
): ZeroTurnResult =
  ## Main entry point for zero-turn administrative commands
  ## Validates and executes command immediately (0 turns)
  ##
  ## Execution Flow:
  ##   1. Validate command (ownership, location, parameters)
  ##   2. Execute command (modify game state)
  ##   3. Emit events (Phase 7b)
  ##   4. Return immediate result
  ##
  ## Returns:
  ##   ZeroTurnResult with success flag, error message, and optional result data
  ##
  ## Location Requirement:
  ##   All operations require fleet/squadron at friendly colony
  ##   Validation fails if not at colony or colony not owned by house

  # Step 1: Validate
  let validation = validateZeroTurnCommand(state, cmd)
  if not validation.valid:
    return ZeroTurnResult(
      success: false,
      error: validation.error,
      newFleetId: none(FleetId),
      newSquadronId: none(string),
      cargoLoaded: 0,
      cargoUnloaded: 0,
      warnings: @[]
    )

  # Step 2: Execute based on command type (emits events)
  case cmd.commandType
  of ZeroTurnCommandType.DetachShips:
    return executeDetachShips(state, cmd, events)
  of ZeroTurnCommandType.TransferShips:
    return executeTransferShips(state, cmd, events)
  of ZeroTurnCommandType.MergeFleets:
    return executeMergeFleets(state, cmd, events)
  of ZeroTurnCommandType.LoadCargo:
    return executeLoadCargo(state, cmd, events)
  of ZeroTurnCommandType.UnloadCargo:
    return executeUnloadCargo(state, cmd, events)
  of ZeroTurnCommandType.LoadFighters:
    return executeLoadFighters(state, cmd, events)
  of ZeroTurnCommandType.UnloadFighters:
    return executeUnloadFighters(state, cmd, events)
  of ZeroTurnCommandType.TransferFighters:
    return executeTransferFighters(state, cmd, events)
  of ZeroTurnCommandType.FormSquadron:
    return executeFormSquadron(state, cmd, events)
  of ZeroTurnCommandType.TransferShipBetweenSquadrons:
    return executeTransferShipBetweenSquadrons(state, cmd, events)
  of ZeroTurnCommandType.AssignSquadronToFleet:
    return executeAssignSquadronToFleet(state, cmd, events)

# Export main types
export ZeroTurnCommandType, ZeroTurnCommand, ZeroTurnResult, ValidationResult
