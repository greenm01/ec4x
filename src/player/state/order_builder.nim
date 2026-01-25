## Order Builder - Write fleet orders to KDL files
##
## This module writes player-submitted fleet orders to msgpack files in the
## game's orders directory for non-Nostr workflows.
##
## Format:
##   base64-encoded msgpack CommandPacket

import std/[os, strformat, times, base64]
import ../sam/tui_model
import ./msgpack_serializer
import ../../engine/types/[core, fleet]

type
  FleetOrder* = object
    fleetId*: int
    commandType*: int
    targetSystemId*: int  ## 0 for commands with no target (Hold)

proc commandTypeToFleetCommandType(cmdType: int): FleetCommandType =
  ## Convert command type constant to FleetCommandType
  case cmdType
  of CmdHold: FleetCommandType.Hold
  of CmdMove: FleetCommandType.Move
  of CmdPatrol: FleetCommandType.Patrol
  of CmdSeekHome: FleetCommandType.SeekHome
  of CmdGuardStarbase: FleetCommandType.GuardStarbase
  of CmdGuardColony: FleetCommandType.GuardColony
  of CmdBlockade: FleetCommandType.Blockade
  of CmdBombard: FleetCommandType.Bombard
  of CmdInvade: FleetCommandType.Invade
  of CmdBlitz: FleetCommandType.Blitz
  of CmdColonize: FleetCommandType.Colonize
  of CmdScoutColony: FleetCommandType.ScoutColony
  of CmdScoutSystem: FleetCommandType.ScoutSystem
  of CmdHackStarbase: FleetCommandType.HackStarbase
  of CmdJoinFleet: FleetCommandType.JoinFleet
  of CmdRendezvous: FleetCommandType.Rendezvous
  of CmdSalvage: FleetCommandType.Salvage
  of CmdReserve: FleetCommandType.Reserve
  of CmdMothball: FleetCommandType.Mothball
  of CmdView: FleetCommandType.View
  else: FleetCommandType.Hold

proc formatFleetOrderMsgpackBase64*(
  order: FleetOrder,
  turn: int,
  houseId: int
): string =
  ## Format a fleet order as base64-encoded msgpack content
  let msgpack = formatFleetOrderMsgpack(
    FleetId(order.fleetId.uint32),
    commandTypeToFleetCommandType(order.commandType),
    SystemId(order.targetSystemId.uint32),
    turn,
    houseId
  )
  encode(msgpack)

proc writeFleetOrder*(gameDir: string, order: FleetOrder, turn: int,
                      houseId: int): string =
  ## Write a fleet order to a msgpack file in the orders directory
  ## Returns the path to the written file
  
  let ordersDir = gameDir / "orders"
  if not dirExists(ordersDir):
    createDir(ordersDir)
  
  # Generate unique filename with timestamp
  let timestamp = getTime().toUnix()
  let filename = fmt"fleet_{order.fleetId}_{timestamp}.msgpack"
  let path = ordersDir / filename

  let content = formatFleetOrderMsgpackBase64(order, turn, houseId)
  writeFile(path, content)
  
  return path

proc writeFleetOrderFromModel*(gameDir: string, model: TuiModel): string =
  ## Write pending fleet order from model to msgpack file
  ## Returns the path to the written file, or empty string if no order pending
  
  if not model.ui.pendingFleetOrderReady:
    return ""
  
  let order = FleetOrder(
    fleetId: model.ui.pendingFleetOrderFleetId,
    commandType: model.ui.pendingFleetOrderCommandType,
    targetSystemId: model.ui.pendingFleetOrderTargetSystemId
  )
  
  return writeFleetOrder(gameDir, order, model.view.turn,
    model.view.viewingHouse)
