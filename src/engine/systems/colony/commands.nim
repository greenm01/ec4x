## Colony Management Command Processing
##
## Handles colony-specific configuration commands:
## - Tax rate adjustments (per-colony override of house tax rate)
## - Auto-repair facility toggles (for infrastructure damage repair)
## - Auto-reload ETAC toggles (automatic cargo loading)
##
## Per architecture.md: Colony system owns colony operations,
## called from turn_cycle/command_phase.nim during command resolution

import std/[options, strformat, logging]
import ../../types/[core, game_state, command]
import ../../state/engine

proc resolveColonyManagementCommands*(state: var GameState, packet: CommandPacket) =
  ## Process colony management commands - tax rates, auto-repair toggles, etc.
  for command in packet.colonyManagement:
    # Validate colony exists and is owned using public API
    let colonyOpt = state.colony(command.colonyId)
    if colonyOpt.isNone:
      error &"Colony management failed: System-{$command.colonyId} has no colony"
      continue

    var colony = colonyOpt.get()
    if colony.owner != packet.houseId:
      error &"Colony management failed: {$packet.houseId} does not own system-{$command.colonyId}"
      continue

    # Apply colony settings from command
    colony.autoRepair = command.autoRepair

    if command.taxRate.isSome:
      colony.taxRate = command.taxRate.get()
      info &"Colony-{$command.colonyId} tax rate set to {command.taxRate.get()}%"

    let repairStatus = if command.autoRepair: "enabled" else: "disabled"
    info &"Colony-{$command.colonyId} auto-repair {repairStatus}"

    # Write back using public API
    state.updateColony(command.colonyId, colony)
