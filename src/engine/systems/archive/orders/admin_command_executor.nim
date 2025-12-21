## Admin Command Execution Dispatcher
##
## This module acts as the main dispatcher for zero-turn administrative commands,
## routing them to specialized handler modules within `src/engine/systems/orders/admin/`.
## Per 06-operations.md: Section 6.4 - Zero-Turn Administrative Commands.

import std/[options, tables, strformat]
import ../../../common/types/core
import ../../gamestate, ../../fleet, ../../logger
import ../../types/resolution as resolution_types
import ../main as orders # For AdminCommand, AdminCommandType, AdminCommandOutcome

# Import individual admin command modules
import ./admin/cargo
import ./admin/fleet_management
import ./admin/fighters
import ./admin/squadron

# =============================================================================
# Admin Command Execution Dispatcher
# =============================================================================

proc executeAdminCommand*(
  state: var GameState,
  houseId: HouseId,
  command: orders.AdminCommand,
  events: var seq[resolution_types.GameEvent]
): orders.AdminCommandOutcome =
  ## Main dispatcher for administrative commands
  ## Routes to appropriate handler based on command type

  logDebug(LogCategory.lcOrders, &"Executing AdminCommand: {command.commandType} for house {houseId}")

  case command.commandType
  of orders.AdminCommandType.LoadCargo:
    # Note: autoLoadCargo is called in turn cycle, manual LoadCargo is here
    # Placeholder for explicit LoadCargo command
    logInfo(LogCategory.lcOrders, "Placeholder for explicit LoadCargo command")
    return orders.AdminCommandOutcome.Success
  of orders.AdminCommandType.UnloadCargo:
    # Placeholder for explicit UnloadCargo command
    logInfo(LogCategory.lcOrders, "Placeholder for explicit UnloadCargo command")
    return orders.AdminCommandOutcome.Success
  of orders.AdminCommandType.DetachShips:
    return fleet_management.executeDetachShips(state, houseId, command, events)
  of orders.AdminCommandType.TransferShips:
    return fleet_management.executeTransferShips(state, houseId, command, events)
  of orders.AdminCommandType.MergeFleets:
    return fleet_management.executeMergeFleets(state, houseId, command, events)
  of orders.AdminCommandType.LoadFighters:
    return fighters.executeLoadFighters(state, houseId, command, events)
  of orders.AdminCommandType.UnloadFighters:
    return fighters.executeUnloadFighters(state, houseId, command, events)
  of orders.AdminCommandType.TransferFighters:
    return fighters.executeTransferFighters(state, houseId, command, events)
  of orders.AdminCommandType.TransferShipBetweenSquadrons:
    return squadron.executeTransferShipBetweenSquadrons(state, houseId, command, events)
  of orders.AdminCommandType.AssignSquadronToFleet:
    return squadron.executeAssignSquadronToFleet(state, houseId, command, events)
  else:
    logWarn(LogCategory.lcOrders, &"Unknown AdminCommandType: {command.commandType}")
    return orders.AdminCommandOutcome.Failed
