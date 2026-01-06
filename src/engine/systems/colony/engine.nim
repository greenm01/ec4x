## Colony System - Public API
##
## Main entry point for all colony operations.
## Re-exports specialized subsystems (colonization, terraforming).
##
## Architecture:
## - engine.nim = Public facade (lifecycle + management + re-exports)
## - colonization.nim = Colonization conflict resolution
## - terraforming.nim = Terraform operations
##
## Usage:
##   import systems/colony/engine as colony_api
##   colony_api.resolveColonization(...)
##   colony_api.resolveTerraforming(...)

import std/[options, strformat]
import ../../types/[core, game_state, starmap, prestige, colony, command]
import ../../entities/colony_ops
import ../../state/engine
import ../../globals
import ../../prestige/application as prestige_app
import ../../../common/logger

# ============================================================================
# Colony Lifecycle
# ============================================================================

proc canColonize*(state: GameState, systemId: SystemId): bool =
  ## Check if a system can be colonized (no existing colony)
  ## Per operations.md:6.3.12
  state.colonyBySystem(systemId).isNone

proc establishColony*(
    state: var GameState,
    houseId: HouseId,
    systemId: SystemId,
    planetClass: PlanetClass,
    resources: ResourceRating,
    ptuCount: int32,
): Option[ColonyId] =
  ## Establish a new colony at system
  ##
  ## Returns:
  ## - Some(ColonyId) if successful
  ## - None if validation fails (logs error)
  ##
  ## Validation:
  ## - System must not already have a colony
  ## - Must have at least 1 PTU
  ##
  ## Side effects:
  ## - Creates colony entity via @entities/colony_ops
  ## - Awards prestige via prestige system

  # Validate: System must be uncolonized
  if not canColonize(state, systemId):
    logError("Colonization",
      &"Cannot colonize {systemId}: system already has colony")
    return none(ColonyId)

  # Validate: Must have PTU
  if ptuCount < 1:
    logError("Colonization",
      &"Cannot colonize {systemId}: insufficient PTU (need ≥1, got {ptuCount})")
    return none(ColonyId)

  # Create colony via entities layer (low-level state mutation)
  let colonyId = colony_ops.establishColony(
    state, systemId, houseId, planetClass, resources, ptuCount
  )

  # Award prestige
  let basePrestige = gameConfig.prestige.economic.establishColony
  let prestigeEvent = PrestigeEvent(
    source: PrestigeSource.ColonyEstablished,
    amount: basePrestige,
    description: &"Established colony at system {systemId}",
  )
  prestige_app.applyPrestigeEvent(state, houseId, prestigeEvent)

  logInfo("Colonization",
    &"House {houseId} established colony at {systemId} " &
    &"({planetClass}, {resources}, {ptuCount} PU) [+{basePrestige} prestige]")

  return some(colonyId)

# ============================================================================
# Colony Management
# ============================================================================

proc resolveColonyCommands*(state: var GameState, packet: CommandPacket) =
  ## Process colony management commands - tax rates, auto-repair toggles
  ## Per architecture.md: Colony system owns colony operations
  ##
  ## Commands:
  ## - Tax rate adjustments (per-colony override of house tax rate)
  ## - Auto-repair facility toggles (for infrastructure damage repair)
  ##
  ## Called from turn_cycle/command_phase.nim during command resolution
  ##
  ## TODO: This is currently incomplete
  for command in packet.colonyManagement:
    # Validate colony exists and is owned using public API
    let colonyOpt = state.colony(command.colonyId)
    if colonyOpt.isNone:
      logError("Colony", &"Management failed: System {command.colonyId} has no colony")
      continue

    var colony = colonyOpt.get()
    if colony.owner != packet.houseId:
      logError("Colony",
        &"Management failed: House {packet.houseId} does not own system {command.colonyId}")
      continue

    # Apply colony settings from command
    colony.autoRepair = command.autoRepair

    if command.taxRate.isSome:
      colony.taxRate = command.taxRate.get()
      logInfo("Colony", &"Colony {command.colonyId} tax rate set to {command.taxRate.get()}%")

    let repairStatus = if command.autoRepair: "enabled" else: "disabled"
    logInfo("Colony", &"Colony {command.colonyId} auto-repair {repairStatus}")

    # Write back using public API
    state.updateColony(command.colonyId, colony)

# ============================================================================
# Subsystem Implementations (included, not imported)
# ============================================================================

include ./colonization
include ./terraforming
