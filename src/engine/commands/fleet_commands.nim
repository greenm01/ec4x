## Fleet Management Commands for EC4X
##
## Administrative commands for fleet reorganization (detach/transfer ships)
## Execute immediately during order submission (0 turns, at friendly colonies)
##
## Architecture:
## - Separate from FleetOrder system (NOT part of OrderPacket)
## - Execute synchronously during order submission phase
## - Only available at friendly colonies
## - Player selects individual ships (squadron structure abstracted)
##
## Usage:
##   let cmd = FleetManagementCommand(...)
##   let result = submitFleetManagementCommand(state, cmd)
##   if result.success: echo "Success!"

import ../gamestate
import ../fleet
import ../squadron
import ../spacelift
import ../orders
import ../../common/types/[core, combat]
import std/[options, algorithm, tables]

export FleetManagementCommand, FleetManagementResult, FleetManagementAction

# ============================================================================
# Validation
# ============================================================================

type
  ValidationResult* = object
    valid*: bool
    error*: string

proc validateFleetManagementCommand*(state: GameState, cmd: FleetManagementCommand): ValidationResult =
  ## Validate fleet management command
  ## Checks ownership, location, ship indices, and action-specific rules

  # 1. Check source fleet exists
  if not state.fleets.hasKey(cmd.sourceFleetId):
    return ValidationResult(valid: false, error: "Source fleet not found")

  let sourceFleet = state.fleets[cmd.sourceFleetId]

  # 2. Check ownership
  if sourceFleet.owner != cmd.houseId:
    return ValidationResult(valid: false, error: "Fleet not owned by house")

  # 3. CRITICAL: Fleet must be at friendly colony
  # Find colony at fleet location
  var colonyFound = false
  var colonyOwner: HouseId = ""

  for colony in state.colonies.values:
    if colony.systemId == sourceFleet.location:
      colonyFound = true
      colonyOwner = colony.owner
      break

  if not colonyFound:
    return ValidationResult(valid: false, error: "Fleet must be at a colony for reorganization")

  if colonyOwner != cmd.houseId:
    return ValidationResult(valid: false, error: "Fleet must be at a friendly colony for reorganization")

  # 4. Validate ship indices
  let allShips = sourceFleet.getAllShips()
  for idx in cmd.shipIndices:
    if idx < 0 or idx >= allShips.len:
      return ValidationResult(valid: false, error: "Invalid ship index: " & $idx)

  # 5. Must select at least one ship
  if cmd.shipIndices.len == 0:
    return ValidationResult(valid: false, error: "Must select at least one ship")

  # 6. Cannot select ALL ships (would leave empty fleet)
  if cmd.shipIndices.len == allShips.len:
    return ValidationResult(valid: false, error: "Cannot transfer all ships (fleet would be empty)")

  # 7. Action-specific validation
  case cmd.action:
  of FleetManagementAction.DetachShips:
    # CRITICAL: Validate spacelift escort requirement
    # Cannot detach spacelift-only fleet (must have combat escorts)
    let (squadronIndices, spaceliftIndices) = sourceFleet.translateShipIndicesToSquadrons(cmd.shipIndices)

    if squadronIndices.len == 0 and spaceliftIndices.len > 0:
      return ValidationResult(valid: false, error: "Cannot detach spacelift ships without combat escorts")

    # newFleetId is optional (will auto-generate if not provided)

  of FleetManagementAction.TransferShips:
    # Target fleet must be specified
    if cmd.targetFleetId.isNone:
      return ValidationResult(valid: false, error: "Target fleet ID required for transfer")

    let targetFleetId = cmd.targetFleetId.get()

    # Target fleet must exist
    if not state.fleets.hasKey(targetFleetId):
      return ValidationResult(valid: false, error: "Target fleet not found")

    let targetFleet = state.fleets[targetFleetId]

    # Target must be owned by same house
    if targetFleet.owner != cmd.houseId:
      return ValidationResult(valid: false, error: "Target fleet not owned by house")

    # Target must be at same location (same friendly colony)
    if targetFleet.location != sourceFleet.location:
      return ValidationResult(valid: false, error: "Both fleets must be at same location")

  of FleetManagementAction.MergeFleets:
    # Target fleet must be specified
    if cmd.targetFleetId.isNone:
      return ValidationResult(valid: false, error: "Target fleet ID required for merge")

    let targetFleetId = cmd.targetFleetId.get()

    # Target fleet must exist
    if not state.fleets.hasKey(targetFleetId):
      return ValidationResult(valid: false, error: "Target fleet not found")

    let targetFleet = state.fleets[targetFleetId]

    # Target must be owned by same house
    if targetFleet.owner != cmd.houseId:
      return ValidationResult(valid: false, error: "Target fleet not owned by house")

    # Target must be at same location (same friendly colony)
    if targetFleet.location != sourceFleet.location:
      return ValidationResult(valid: false, error: "Both fleets must be at same location")

    # Cannot merge fleet into itself
    if cmd.sourceFleetId == targetFleetId:
      return ValidationResult(valid: false, error: "Cannot merge fleet into itself")

  return ValidationResult(valid: true, error: "")

# ============================================================================
# Execution - Detach Ships
# ============================================================================

proc executeDetachShips*(state: var GameState, cmd: FleetManagementCommand): FleetManagementResult =
  ## Split ships from source fleet to create new fleet
  ## Both fleets remain at same location

  # Get source fleet (CRITICAL: Table copy semantics - get-modify-write)
  var sourceFleet = state.fleets[cmd.sourceFleetId]

  # Translate ship indices to squadron/spacelift indices
  let (squadronIndices, spaceliftIndices) = sourceFleet.translateShipIndicesToSquadrons(cmd.shipIndices)

  # Split squadrons (existing proc)
  let splitResult = sourceFleet.split(squadronIndices)

  # Split spacelift ships
  var newSpaceLiftShips: seq[SpaceLiftShip] = @[]
  # Sort indices in descending order to avoid index shifting issues
  for idx in spaceliftIndices.sorted(Descending):
    newSpaceLiftShips.add(sourceFleet.spaceLiftShips[idx])
    sourceFleet.spaceLiftShips.delete(idx)

  # Generate new fleet ID if not provided
  let newFleetId = if cmd.newFleetId.isSome:
    cmd.newFleetId.get()
  else:
    cmd.houseId & "_fleet_" & $state.turn & "_" & $state.fleets.len

  # Create new fleet
  var newFleet = Fleet(
    id: newFleetId,
    squadrons: splitResult.squadrons,
    spaceLiftShips: newSpaceLiftShips,
    owner: cmd.houseId,
    location: sourceFleet.location,
    status: FleetStatus.Active,
    autoBalanceSquadrons: true
  )

  # Balance squadrons in BOTH fleets
  sourceFleet.balanceSquadrons()
  newFleet.balanceSquadrons()

  # CRITICAL: Write back to state (Table copy semantics)
  state.fleets[cmd.sourceFleetId] = sourceFleet
  state.fleets[newFleetId] = newFleet

  return FleetManagementResult(
    success: true,
    error: "",
    newFleetId: some(newFleetId),
    warnings: @[]
  )

# ============================================================================
# Execution - Transfer Ships
# ============================================================================

proc executeTransferShips*(state: var GameState, cmd: FleetManagementCommand): FleetManagementResult =
  ## Move ships from source fleet to target fleet
  ## If source becomes empty, it's deleted

  let targetFleetId = cmd.targetFleetId.get()

  # Get both fleets (CRITICAL: Table copy semantics)
  var sourceFleet = state.fleets[cmd.sourceFleetId]
  var targetFleet = state.fleets[targetFleetId]

  # Translate ship indices to squadron/spacelift indices
  let (squadronIndices, spaceliftIndices) = sourceFleet.translateShipIndicesToSquadrons(cmd.shipIndices)

  # Transfer squadrons
  let transferredFleet = sourceFleet.split(squadronIndices)
  targetFleet.merge(transferredFleet)

  # Transfer spacelift ships
  # Sort indices in descending order to avoid index shifting issues
  for idx in spaceliftIndices.sorted(Descending):
    targetFleet.spaceLiftShips.add(sourceFleet.spaceLiftShips[idx])
    sourceFleet.spaceLiftShips.delete(idx)

  # Balance both fleets
  sourceFleet.balanceSquadrons()
  targetFleet.balanceSquadrons()

  # Check if source fleet is now empty
  if sourceFleet.isEmpty():
    # Delete empty fleet and cleanup orders
    state.fleets.del(cmd.sourceFleetId)
    if cmd.sourceFleetId in state.fleetOrders:
      state.fleetOrders.del(cmd.sourceFleetId)
    if cmd.sourceFleetId in state.standingOrders:
      state.standingOrders.del(cmd.sourceFleetId)
  else:
    # Write back modified source fleet
    state.fleets[cmd.sourceFleetId] = sourceFleet

  # Write back modified target fleet
  state.fleets[targetFleetId] = targetFleet

  return FleetManagementResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    warnings: @[]
  )

# ============================================================================
# Execution - Merge Fleets
# ============================================================================

proc executeMergeFleets*(state: var GameState, cmd: FleetManagementCommand): FleetManagementResult =
  ## Merge entire source fleet into target fleet (0 turns, at colony)
  ## Source fleet is deleted, all ships transferred to target
  ##
  ## This is different from Order 13 (Join Fleet):
  ## - MergeFleets: Immediate execution (0 turns) at colony
  ## - Order 13: Can involve travel, executes during Command Phase

  let targetFleetId = cmd.targetFleetId.get()

  # Get both fleets (CRITICAL: Table copy semantics)
  let sourceFleet = state.fleets[cmd.sourceFleetId]
  var targetFleet = state.fleets[targetFleetId]

  # Merge all squadrons
  targetFleet.merge(sourceFleet)

  # Balance target fleet after merge
  targetFleet.balanceSquadrons()

  # Write back modified target fleet
  state.fleets[targetFleetId] = targetFleet

  # Delete source fleet and cleanup orders
  state.fleets.del(cmd.sourceFleetId)
  if cmd.sourceFleetId in state.fleetOrders:
    state.fleetOrders.del(cmd.sourceFleetId)
  if cmd.sourceFleetId in state.standingOrders:
    state.standingOrders.del(cmd.sourceFleetId)

  return FleetManagementResult(
    success: true,
    error: "",
    newFleetId: none(FleetId),
    warnings: @[]
  )

# ============================================================================
# Main API Entry Point
# ============================================================================

proc submitFleetManagementCommand*(
  state: var GameState,
  cmd: FleetManagementCommand
): FleetManagementResult =
  ## Main entry point for fleet management commands
  ## Validates and executes command immediately (0 turns)
  ##
  ## Returns:
  ##   FleetManagementResult with success flag, error message, and optional newFleetId

  # Validate command
  let validation = validateFleetManagementCommand(state, cmd)
  if not validation.valid:
    return FleetManagementResult(
      success: false,
      error: validation.error,
      newFleetId: none(FleetId),
      warnings: @[]
    )

  # Execute based on action type
  case cmd.action:
  of FleetManagementAction.DetachShips:
    return executeDetachShips(state, cmd)
  of FleetManagementAction.TransferShips:
    return executeTransferShips(state, cmd)
  of FleetManagementAction.MergeFleets:
    return executeMergeFleets(state, cmd)
