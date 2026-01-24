## Msgpack command serialization for TUI
##
## Serializes CommandPacket and fleet orders to msgpack for sending via Nostr.

import std/options
import msgpack4nim
import ../../engine/types/[command, core, fleet]
import ../../common/msgpack_types

export msgpack_types

proc serializeCommandPacket*(packet: CommandPacket): string =
  ## Serialize CommandPacket to msgpack binary
  pack(packet)

proc formatFleetOrderMsgpack*(
  fleetId: FleetId,
  commandType: FleetCommandType,
  targetSystemId: SystemId,
  turn: int,
  houseId: int
): string =
  ## Create a msgpack-serialized CommandPacket for a single fleet order
  let cmd = FleetCommand(
    fleetId: fleetId,
    commandType: commandType,
    targetSystem: some(targetSystemId),
    targetFleet: none(FleetId),
    roe: none(int32),
    priority: 0
  )
  let packet = CommandPacket(
    turn: int32(turn),
    houseId: HouseId(houseId.uint32),
    fleetCommands: @[cmd],
    buildCommands: @[],
    repairCommands: @[],
    scrapCommands: @[]
  )
  pack(packet)
