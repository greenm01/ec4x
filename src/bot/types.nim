## Shared bot runtime types.

import std/options

import ../engine/types/player_state

type
  BotConfig* = object
    relays*: seq[string]
    gameId*: string
    daemonPubkey*: string
    playerPrivHex*: string
    playerPubHex*: string
    model*: string
    baseUrl*: string
    apiKey*: string
    maxRetries*: int
    requestTimeoutSec*: int

  BotRuntimeState* = object
    hasState*: bool
    playerState*: PlayerState
    configHash*: string
    configSchemaVersion*: int32
    lastSeenTurn*: int32
    lastSubmittedTurn*: int32
    lastEventId*: Option[string]

proc initBotRuntimeState*(): BotRuntimeState =
  BotRuntimeState(
    hasState: false,
    configHash: "",
    configSchemaVersion: 0,
    lastSeenTurn: -1,
    lastSubmittedTurn: -1,
    lastEventId: none(string)
  )
