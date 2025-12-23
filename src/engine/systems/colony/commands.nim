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
import ../../types/[game_state, command]
import ../../state/entity_manager

proc resolveColonyManagementCommands*(state: var GameState, packet: CommandPacket) =
  ## Process colony management commands - tax rates, auto-repair toggles, etc.
  for order in packet.colonyManagement:
    # Validate colony exists and is owned using entity_manager accessor
    let colonyOpt = state.colonies.entities.getEntity(order.colonyId)
    if colonyOpt.isNone:
      error &"Colony management failed: System-{$order.colonyId} has no colony"
      continue

    var colony = colonyOpt.get()
    if colony.owner != packet.houseId:
      error &"Colony management failed: {$packet.houseId} does not own system-{$order.colonyId}"
      continue

    # Apply colony settings from command
    colony.autoRepairEnabled = order.autoRepair
    colony.autoReloadETACs = order.autoReloadETACs

    if order.taxRate.isSome:
      colony.taxRate = order.taxRate.get()
      info &"Colony-{$order.colonyId} tax rate set to {order.taxRate.get()}%"

    let repairStatus = if order.autoRepair: "enabled" else: "disabled"
    info &"Colony-{$order.colonyId} auto-repair {repairStatus}"

    let etacStatus = if order.autoReloadETACs: "enabled" else: "disabled"
    info &"Colony-{$order.colonyId} auto-reload ETACs {etacStatus}"

    # Write back using entity_manager accessor
    state.colonies.entities.updateEntity(order.colonyId, colony)
