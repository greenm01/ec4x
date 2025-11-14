## Daemon processor - decrypts orders, validates, and resolves turns

import std/[json, tables]
import ../transport/nostr/[types, crypto]

type
  OrderPacket* = object
    gameId*: string
    house*: string
    turn*: int
    orders*: JsonNode
    submittedAt*: int64

  Processor* = ref object
    moderatorPrivKey*: array[32, byte]

proc newProcessor*(moderatorPrivKey: array[32, byte]): Processor =
  ## Create new order processor
  result = Processor(
    moderatorPrivKey: moderatorPrivKey
  )

proc decryptOrder*(proc: Processor, event: NostrEvent): OrderPacket =
  ## Decrypt and parse order event
  ## TODO: Implement NIP-44 decryption and parsing
  raise newException(CatchableError, "Not yet implemented")

proc validateOrder*(proc: Processor, order: OrderPacket): bool =
  ## Validate order packet against game rules
  ## TODO: Implement order validation
  raise newException(CatchableError, "Not yet implemented")

proc resolveTurn*(proc: Processor, gameId: string, orders: seq[OrderPacket]): JsonNode =
  ## Resolve turn with collected orders
  ## TODO: Call engine.resolveTurn and return new game state
  raise newException(CatchableError, "Not yet implemented")
