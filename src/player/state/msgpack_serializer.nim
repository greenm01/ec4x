## Msgpack command serialization for TUI
##
## Serializes CommandPacket to msgpack for sending via Nostr.

import msgpack4nim
import ../../engine/types/command
import ../../common/msgpack_types

export msgpack_types

proc serializeCommandPacket*(packet: CommandPacket): string =
  ## Serialize CommandPacket to msgpack binary
  pack(packet)
