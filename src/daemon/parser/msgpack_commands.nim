## MessagePack command parser for Nostr player orders
##
## Deserializes CommandPacket from msgpack binary received via Nostr.
## Much simpler than KDL parsing since msgpack4nim handles the structure.

import msgpack4nim
import ../../engine/types/command
import ../../common/msgpack_types
export msgpack_types

type
  MsgpackParseError* = object of CatchableError

# =============================================================================
# Command Deserialization
# =============================================================================

proc parseOrdersMsgpack*(data: string): CommandPacket =
  ## Deserialize CommandPacket from msgpack binary
  try:
    var stream = MsgStream.init(data, MSGPACK_OBJ_TO_MAP)
    var packet: CommandPacket
    stream.unpack(packet)
    packet
  except CatchableError as e:
    raise newException(
      MsgpackParseError,
      "Failed to parse msgpack commands: " & e.msg
    )

proc serializeCommandPacket*(packet: CommandPacket): string =
  ## Serialize CommandPacket to msgpack binary
  ## Used by TUI to send orders to daemon
  var stream = MsgStream.init(0, MSGPACK_OBJ_TO_MAP)
  stream.pack(packet)
  stream.data
