## Bot state ingestion from Nostr PlayerState payloads.

import std/options

import ../player/state/msgpack_state
import ./types

proc applyFullStatePayload*(
    runtime: var BotRuntimeState,
    payload: string,
    eventId: string = ""
): bool =
  if eventId.len > 0 and runtime.lastEventId.isSome and
      runtime.lastEventId.get() == eventId:
    return false

  let envelopeOpt = parseFullStateMsgpack(payload)
  if envelopeOpt.isNone:
    return false

  let envelope = envelopeOpt.get()
  runtime.hasState = true
  runtime.playerState = envelope.playerState
  runtime.configHash = envelope.authoritativeConfig.configHash
  runtime.configSchemaVersion =
    envelope.authoritativeConfig.schemaVersion
  runtime.lastSeenTurn = envelope.playerState.turn
  if eventId.len > 0:
    runtime.lastEventId = some(eventId)
  true

proc applyDeltaPayload*(
    runtime: var BotRuntimeState,
    payload: string,
    eventId: string = ""
): bool =
  if eventId.len > 0 and runtime.lastEventId.isSome and
      runtime.lastEventId.get() == eventId:
    return false

  if not runtime.hasState:
    return false

  let updatedTurn = applyDeltaMsgpack(
    runtime.playerState,
    payload,
    runtime.configHash,
    runtime.configSchemaVersion
  )
  if updatedTurn.isNone:
    return false

  runtime.lastSeenTurn = updatedTurn.get()
  if eventId.len > 0:
    runtime.lastEventId = some(eventId)
  true

proc hasActionableTurn*(runtime: BotRuntimeState): bool =
  runtime.hasState and runtime.playerState.turn > runtime.lastSubmittedTurn

proc markTurnSubmitted*(runtime: var BotRuntimeState) =
  if runtime.hasState:
    runtime.lastSubmittedTurn = runtime.playerState.turn
