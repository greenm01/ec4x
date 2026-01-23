## Daemon publisher - publishes game states and turn results to Nostr

import std/[asyncdispatch, options]
import ../common/logger
import ../engine/types/core
import ../engine/types/game_state
import ../engine/state/iterators
import ./transport/nostr/[types, client, events, crypto, wire]
import ./persistence/reader
import ./persistence/writer
import ./transport/nostr/delta_kdl
import ./transport/nostr/state_kdl

type
  Publisher* = ref object
    client*: NostrClient
    daemonPubkey*: string
    daemonPriv*: array[32, byte]

proc newPublisher*(client: NostrClient, daemonPubkey: string,
  daemonPriv: array[32, byte]): Publisher =
  ## Create new publisher wrapper
  result = Publisher(
    client: client,
    daemonPubkey: daemonPubkey,
    daemonPriv: daemonPriv
  )

proc getPlayerPubkey(dbPath: string, gameId: string,
  houseId: HouseId): string =
  ## Get player's Nostr pubkey for a house
  let pubkeyOpt = getHousePubkey(dbPath, gameId, houseId)
  if pubkeyOpt.isSome:
    return pubkeyOpt.get()
  else:
    return ""

proc buildDeltaKdl(dbPath: string, gameId: string, state: GameState,
  houseId: HouseId): string =
  ## Build fog-of-war filtered delta KDL for a house
  let previousTurn = state.turn - 1
  let previousSnapshot = loadPlayerStateSnapshot(
    dbPath,
    gameId,
    houseId,
    previousTurn
  )

  let currentSnapshot = buildPlayerStateSnapshot(state, houseId)
  let delta = diffPlayerState(previousSnapshot, currentSnapshot)

  savePlayerStateSnapshot(
    dbPath,
    gameId,
    houseId,
    state.turn,
    currentSnapshot
  )

  formatPlayerStateDeltaKdl(gameId, delta)

proc publishFullState*(pub: Publisher, gameId: string, dbPath: string,
  state: GameState, houseId: HouseId) {.async.} =
  ## Publish full state (30405) to a specific house
  try:
    let playerPubkey = getPlayerPubkey(dbPath, gameId, houseId)
    if playerPubkey.len == 0:
      logWarn("Nostr", "No player pubkey for house ", $houseId,
        " - skipping state publish")
      return

    let playerPub = crypto.hexToBytes32(playerPubkey)
    let stateKdl = formatPlayerStateKdl(gameId, state, houseId)
    let encryptedPayload = encodePayload(stateKdl, pub.daemonPriv, playerPub)

    var event = createGameState(
      gameId = gameId,
      turn = state.turn.int,
      encryptedPayload = encryptedPayload,
      playerPubkey = playerPubkey,
      daemonPubkey = pub.daemonPubkey
    )
    signEvent(event, pub.daemonPriv)

    if hasProcessedEvent(dbPath, gameId,
        event.kind, event.id, reader.ReplayDirection.Outbound):
      logDebug("Nostr", "Skipping duplicate full state publish for house ",
        $houseId)
      return

    let published = await pub.client.publish(event)
    if published:
      logInfo("Nostr", "Published full state for house ", $houseId)
      insertProcessedEvent(dbPath, gameId,
        state.turn.int32, event.kind, event.id,
        reader.ReplayDirection.Outbound)
    else:
      logError("Nostr", "Failed to publish full state for house ", $houseId)

  except CatchableError as e:
    logError("Nostr", "Failed to publish full state: ", e.msg)

proc publishGameDefinition*(pub: Publisher, gameId: string, dbPath: string,
  phase: string, state: GameState) {.async.} =
  ## Publish game definition (30400) for lobby updates
  try:
    var slots: seq[SlotInfo] = @[]

    for (houseId, house) in state.allHousesWithId():
      discard house
      let codeOpt = getHouseInviteCode(dbPath, gameId, houseId)
      let code = if codeOpt.isSome: codeOpt.get() else: ""
      let pubkey = getPlayerPubkey(dbPath, gameId, houseId)
      let status = if pubkey.len > 0:
                    SlotStatusClaimed
                  else:
                    SlotStatusPending
      let index = int(houseId.uint32)
      slots.add(SlotInfo(
        index: index,
        code: code,
        status: status,
        pubkey: pubkey
      ))

    var event = createGameDefinition(
      gameId = gameId,
      name = state.gameName,
      status = phase,
      slots = slots,
      daemonPubkey = pub.daemonPubkey
    )

    signEvent(event, pub.daemonPriv)

    if hasProcessedEvent(dbPath, gameId,
        event.kind, event.id, reader.ReplayDirection.Outbound):
      logDebug("Nostr", "Skipping duplicate game definition for game=",
        gameId)
      return

    let published = await pub.client.publish(event)
    if published:
      logInfo("Nostr", "Published game definition for game=", gameId)
      insertProcessedEvent(dbPath, gameId,
        0, event.kind, event.id, reader.ReplayDirection.Outbound)
    else:
      logError("Nostr", "Failed to publish game definition for game=", gameId)
  except CatchableError as e:
    logError("Nostr", "Failed to publish game definition: ", e.msg)

proc publishGameStatus*(pub: Publisher, gameId: string, name: string,
  status: string) {.async.} =
  ## Publish game status update (30400) without slots
  try:
    var event = createGameDefinitionNoSlots(
      gameId = gameId,
      name = name,
      status = status,
      daemonPubkey = pub.daemonPubkey
    )

    signEvent(event, pub.daemonPriv)

    let published = await pub.client.publish(event)
    if published:
      logInfo("Nostr", "Published game status for game=", gameId,
        " status=", status)
    else:
      logError("Nostr", "Failed to publish game status for game=", gameId,
        " status=", status)
  except CatchableError as e:
    logError("Nostr", "Failed to publish game status: ", e.msg)

proc publishJoinError*(pub: Publisher, playerPubkey: string,
  message: string) {.async.} =
  ## Publish join error to a player
  try:
    let playerPub = crypto.hexToBytes32(playerPubkey)
    let encrypted = encodePayload(message, pub.daemonPriv, playerPub)

    var event = createJoinError(pub.daemonPubkey, playerPubkey, encrypted)
    signEvent(event, pub.daemonPriv)

    let published = await pub.client.publish(event)
    if published:
      logInfo("Nostr", "Published join error")
    else:
      logError("Nostr", "Failed to publish join error")
  except CatchableError as e:
    logError("Nostr", "Failed to publish join error: ", e.msg)

proc publishTurnResults*(pub: Publisher, gameId: string, dbPath: string,
  state: GameState) {.async.} =
  ## Publish turn results to all players via Nostr
  try:
    for (houseId, house) in state.allHousesWithId():
      discard house
      let playerPubkey = getPlayerPubkey(dbPath, gameId, houseId)
      if playerPubkey.len == 0:
        logWarn("Nostr", "No player pubkey for house ", $houseId,
          " - skipping delta publish")
        continue

      let deltaKdl = buildDeltaKdl(dbPath, gameId, state, houseId)
      let playerPub = crypto.hexToBytes32(playerPubkey)
      let encryptedPayload = encodePayload(deltaKdl, pub.daemonPriv, playerPub)

      var event = createTurnResults(
        gameId = gameId,
        turn = state.turn.int,
        encryptedPayload = encryptedPayload,
        playerPubkey = playerPubkey,
        daemonPubkey = pub.daemonPubkey
      )
      signEvent(event, pub.daemonPriv)

      if hasProcessedEvent(dbPath, gameId,
          event.kind, event.id, reader.ReplayDirection.Outbound):
        logDebug("Nostr", "Skipping duplicate delta publish for house ",
          $houseId)
        continue

      let published = await pub.client.publish(event)
      if published:
        logInfo("Nostr", "Published turn ", $state.turn,
          " delta for house ", $houseId)
        insertProcessedEvent(dbPath, gameId,
          state.turn.int32, event.kind, event.id,
          reader.ReplayDirection.Outbound)
      else:
        logError("Nostr", "Failed to publish delta for house ", $houseId)

  except CatchableError as e:
    logError("Nostr", "Failed to publish turn results: ", e.msg)
