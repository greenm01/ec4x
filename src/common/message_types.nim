## Shared message types for player-to-player communication
##
## Serialized via msgpack for Nostr transport.

import msgpack4nim

type
  GameMessage* = object
    fromHouse*: int32
    toHouse*: int32        ## 0 = broadcast
    text*: string
    timestamp*: int64      ## Unix epoch seconds
    gameId*: string

proc serializeMessage*(msg: GameMessage): string =
  ## Serialize GameMessage to msgpack binary
  pack(msg)

proc deserializeMessage*(data: string): GameMessage =
  ## Deserialize msgpack binary to GameMessage
  unpack(data, GameMessage)
