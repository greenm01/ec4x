## Order Builder - Write fleet orders to KDL files
##
## This module writes player-submitted fleet orders to KDL files in the
## game's orders directory. The daemon picks these up and processes them.
##
## KDL Format:
##   orders turn=42 house=(HouseId)1 {
##     fleet (FleetId)1 {
##       move to=(SystemId)15
##     }
##   }

import std/[os, strformat, times]
import ../sam/tui_model

type
  FleetOrder* = object
    fleetId*: int
    commandType*: int
    targetSystemId*: int  ## 0 for commands with no target (Hold)

proc commandTypeToKdl(cmdType: int): string =
  ## Convert command type constant to KDL command name
  case cmdType
  of CmdHold: "hold"
  of CmdMove: "move"
  of CmdPatrol: "patrol"
  of CmdSeekHome: "seek-home"
  of CmdGuardStarbase: "guard-starbase"
  of CmdGuardColony: "guard-colony"
  of CmdBlockade: "blockade"
  of CmdBombard: "bombard"
  of CmdInvade: "invade"
  of CmdBlitz: "blitz"
  of CmdColonize: "colonize"
  of CmdScoutColony: "scout-colony"
  of CmdScoutSystem: "scout-system"
  of CmdHackStarbase: "hack-starbase"
  of CmdJoinFleet: "join-fleet"
  of CmdRendezvous: "rendezvous"
  of CmdSalvage: "salvage"
  of CmdReserve: "reserve"
  of CmdMothball: "mothball"
  of CmdView: "view"
  else: "hold"

proc needsTarget(cmdType: int): bool =
  ## Check if command type requires a target system
  cmdType in [CmdMove, CmdPatrol, CmdBlockade, CmdBombard, CmdInvade,
              CmdBlitz, CmdColonize, CmdScoutColony, CmdScoutSystem,
              CmdJoinFleet, CmdRendezvous]

proc formatFleetOrderKdl*(order: FleetOrder, turn: int, houseId: int): string =
  ## Format a fleet order as KDL content
  let cmdName = commandTypeToKdl(order.commandType)
  
  if needsTarget(order.commandType) and order.targetSystemId > 0:
    result = fmt"""orders turn={turn} house=(HouseId){houseId} {{
  fleet (FleetId){order.fleetId} {{
    {cmdName} to=(SystemId){order.targetSystemId}
  }}
}}
"""
  else:
    result = fmt"""orders turn={turn} house=(HouseId){houseId} {{
  fleet (FleetId){order.fleetId} {{
    {cmdName}
  }}
}}
"""

proc writeFleetOrder*(gameDir: string, order: FleetOrder, turn: int,
                      houseId: int): string =
  ## Write a fleet order to a KDL file in the orders directory
  ## Returns the path to the written file
  
  let ordersDir = gameDir / "orders"
  if not dirExists(ordersDir):
    createDir(ordersDir)
  
  # Generate unique filename with timestamp
  let timestamp = getTime().toUnix()
  let filename = fmt"fleet_{order.fleetId}_{timestamp}.kdl"
  let path = ordersDir / filename
  
  let content = formatFleetOrderKdl(order, turn, houseId)
  writeFile(path, content)
  
  return path

proc writeFleetOrderFromModel*(gameDir: string, model: TuiModel): string =
  ## Write pending fleet order from model to KDL file
  ## Returns the path to the written file, or empty string if no order pending
  
  if not model.pendingFleetOrderReady:
    return ""
  
  let order = FleetOrder(
    fleetId: model.pendingFleetOrderFleetId,
    commandType: model.pendingFleetOrderCommandType,
    targetSystemId: model.pendingFleetOrderTargetSystemId
  )
  
  return writeFleetOrder(gameDir, order, model.turn, model.viewingHouse)
