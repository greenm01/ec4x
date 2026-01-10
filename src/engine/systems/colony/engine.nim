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
##   import systems/colony/engine
##   resolveColonization(...)
##   resolveTerraforming(...)

import std/[options, strformat]
import ../../types/[core, game_state, colony, command]
import ../../state/engine
import ../../../common/logger
import ./[colonization, terraforming]

export colonization, terraforming

proc resolveColonyCommands*(state: GameState, packet: CommandPacket) =
  ## Process colony management commands - tax rates, auto-repair toggles
  ## Per architecture.md: Colony system owns colony operations
  ##
  ## Commands:
  ## - Tax rate adjustments (per-colony override of house tax rate)
  ## - Auto-repair facility toggles (for infrastructure damage repair)
  ##
  ## Called from turn_cycle/command_phase.nim during command resolution
  ##
  ## Note: System handles auto-repair and tax rate settings
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
