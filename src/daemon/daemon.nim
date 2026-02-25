## EC4X Daemon - Autonomous Turn Processing Service
##
## The daemon monitors active games, collects player orders, resolves turns,
## and publishes results—all without human intervention.

import std/[os, tables, sets, asyncdispatch, strutils, options, times]
import cligen
import ../common/logger
import ./sam_core
import ./config
import ./identity
import ./transport/nostr/[types, client, wire, events, crypto]
import ./subscriber
import ./publisher
import ../daemon/persistence/reader
import ../daemon/persistence/writer
import ../common/wordlist
import ../common/message_types

# Replay protection

import ../daemon/parser/msgpack_commands
import ../engine/turn_cycle/engine
import ../engine/config/engine
import ../engine/globals
import ../engine/types/[core, command, game_state]

# =============================================================================
# Core Types
# =============================================================================
type
  GameId* = string
  GameInfo* = object
    id*: GameId
    dbPath*: string
    turn*: int
    phase*: string
    transportMode*: string # e.g. "nostr"
    turnDeadline*: Option[int64]

type
  DaemonModel* = object
    ## Central application state
    games*: Table[GameId, GameInfo]        # All managed games
    resolving*: HashSet[GameId]            # Currently resolving games
    pendingOrders*: Table[GameId, int]     # Count of pending orders per game
    running*: bool                         # Main loop control
    dataDir*: string                       # Root data directory
    pollInterval*: int                     # Seconds between polls
    replayRetentionTurns*: int             # Replay log turns retention
    replayRetentionDays*: int              # Replay log days retention
    replayRetentionDaysDefinition*: int    # Game definition retention
    replayRetentionDaysState*: int         # State publish retention
    turnDeadlineMinutes*: int              # Auto-resolve deadline length
    identity*: DaemonIdentity              # Nostr keypair
    nostrClient*: NostrClient              # Nostr relay client
    nostrSubscriber*: Subscriber           # Nostr subscriber wrapper
    nostrPublisher*: Publisher             # Nostr publisher wrapper
    relayUrls*: seq[string]                # Relay URLs from config
    readyLogged*: bool                     # Ready log emitted
    # Reactor triggers (SAM side effects)
    resolutionRequested*: HashSet[GameId]  # Games requesting turn resolution
    discoveryRequested*: bool              # Request game discovery
    maintenanceRequested*: bool            # Request maintenance (cleanup, deadlines)
    tickRequested*: bool                   # Request next tick


type
  DaemonLoop* = SamLoop[DaemonModel]

var shutdownRequested {.global.}: bool = false

# =============================================================================
# Global State
# =============================================================================

var daemonLoop* {.global.}: DaemonLoop

# =============================================================================
# SAM Commands (Async Effects)
# =============================================================================

type DaemonCmd* = proc (): Future[Proposal[DaemonModel]]

# =============================================================================
# Command Helpers
# =============================================================================

# Forward declarations
proc resolveTurnCmd(gameId: GameId): DaemonCmd
proc resolveHouseId(state: GameState, pubkey: string): Option[HouseId]


proc calculateTurnDeadline(minutes: int): Option[int64] =
  ## Calculate deadline timestamp for current turn
  if minutes <= 0:
    return none(int64)
  let nowUnix = getTime().toUnix()
  some(nowUnix + int64(minutes * 60))

proc checkDeadlineResolution(gameId: GameId) =
  ## Auto-resolve when deadline expires
  let gameInfo = daemonLoop.model.games[gameId]
  if gameInfo.phase != "Active":
    return
  let deadlineOpt = gameInfo.turnDeadline
  if deadlineOpt.isNone:
    return
  if gameId in daemonLoop.model.resolving:
    return

  let deadline = deadlineOpt.get()
  let nowUnix = getTime().toUnix()
  if nowUnix < deadline:
    return

  logInfo("Daemon", "Turn deadline reached; auto-resolving game=", gameId,
    " turn=", $gameInfo.turn)

  # Request turn resolution via proposal (reactor will queue the Cmd)
  let gId = gameId
  daemonLoop.present(Proposal[DaemonModel](
    name: "request_turn_resolution",
    payload: proc(m: var DaemonModel) =
      m.resolving.incl(gId)
      m.resolutionRequested.incl(gId)
  ))

proc checkAndTriggerResolution(gameId: GameId) =
  ## Check if all expected players have submitted orders
  ## If so, automatically queue turn resolution
  let gameInfo = daemonLoop.model.games[gameId]
  let currentTurn = gameInfo.turn

  # Only auto-resolve games in Active phase
  if gameInfo.phase != "Active":
    logDebug("Daemon", "Game ", gameId, " in phase ", gameInfo.phase,
      " - skipping auto-resolve")
    return

  let expectedPlayers = countExpectedPlayers(gameInfo.dbPath, gameId)

  # Edge case: No human players yet (all slots unclaimed)
  if expectedPlayers == 0:
    logDebug("Daemon", "No human players assigned yet for game ", gameId)
    return

  let submittedPlayers = countPlayersSubmitted(gameInfo.dbPath, gameId,
    currentTurn.int32)

  logDebug("Daemon", "Turn readiness check: ", $submittedPlayers, "/",
    $expectedPlayers, " players submitted for game=", gameId,
    " turn=", $currentTurn)

  let deadlineOpt = gameInfo.turnDeadline
  if deadlineOpt.isSome:
    let deadline = deadlineOpt.get()
    logDebug("Daemon", "Turn deadline at ", $deadline, " for game=", gameId)

  # Check if all players ready
  if submittedPlayers >= expectedPlayers:
    logInfo("Daemon", "All players submitted! Auto-triggering resolution for game=",
      gameId, " turn=", $currentTurn)

    # Guard: Don't queue if already resolving
    if gameId in daemonLoop.model.resolving:
      logWarn("Daemon", "Turn already resolving for game ", gameId, " - skipping")
      return

    # Request turn resolution via proposal (reactor will queue the Cmd)
    let gId = gameId
    daemonLoop.present(Proposal[DaemonModel](
      name: "request_turn_resolution",
      payload: proc(m: var DaemonModel) =
        m.resolving.incl(gId)
        m.resolutionRequested.incl(gId)
    ))
  else:
    logDebug("Daemon", "Waiting for ", $(expectedPlayers - submittedPlayers),
      " more player(s) for turn ", $currentTurn)

proc resolveTurnCmd(gameId: GameId): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    logInfo("Daemon", "Resolving turn for game: ", gameId)

    # Game is already marked as resolving by the requesting proposal
    try:
      let gameInfo = daemonLoop.model.games[gameId]

      # 1. Load state and orders
      let state = loadFullState(gameInfo.dbPath)
      let commands = loadOrders(gameInfo.dbPath, state.turn)

      # 2. Resolve turn (deterministic)
      let result = resolveTurnDeterministic(state, commands)

      # 3. Persist results
      saveFullState(state) # Saves NEW turn number and updated entities
      saveGameEvents(state, result.events)
      markCommandsProcessed(gameInfo.dbPath, gameId, state.turn - 1)

      let nextDeadline = calculateTurnDeadline(
        daemonLoop.model.turnDeadlineMinutes
      )
      updateTurnDeadline(gameInfo.dbPath, gameInfo.id, nextDeadline)

      # 4. Publish turn results via Nostr
      if daemonLoop.model.nostrPublisher != nil:
        await daemonLoop.model.nostrPublisher.publishTurnResults(
          gameInfo.id,
          gameInfo.dbPath,
          state
        )
        if result.victoryCheck.victoryOccurred:
          await daemonLoop.model.nostrPublisher.publishGameStatus(
            gameInfo.id,
            state.gameName,
            GameStatusCompleted
          )
          writer.updateGamePhase(gameInfo.dbPath, gameInfo.id, "Completed")
          let gameDir = gameInfo.dbPath.parentDir
          let archiveDir = daemonLoop.model.dataDir / "archive"
          try:
            createDir(archiveDir)
            let timestamp = getTime().format("yyyy-MM-dd")
            let archiveName = timestamp & "-" & gameDir.splitPath.tail
            let destDir = archiveDir / archiveName
            createDir(destDir)
            let dbPath = gameInfo.dbPath
            if fileExists(dbPath):
              let destDb = destDir / (archiveName & ".db")
              moveFile(dbPath, destDb)
            if dirExists(gameDir):
              removeDir(gameDir)
            logInfo("Daemon", "Archived game to ", destDir)
          except CatchableError as e:
            logWarn("Daemon", "Failed to archive game: ", e.msg)

      writer.cleanupProcessedEvents(gameInfo.dbPath, gameId, state.turn.int32,
        daemonLoop.model.replayRetentionTurns,
        daemonLoop.model.replayRetentionDays,
        daemonLoop.model.replayRetentionDaysDefinition,
        daemonLoop.model.replayRetentionDaysState)

      return Proposal[DaemonModel](
        name: "turn_resolved",
        payload: proc(model: var DaemonModel) =
          model.games[gameId].turn = state.turn
          model.games[gameId].turnDeadline = nextDeadline
          model.resolving.excl(gameId)
          model.pendingOrders[gameId] = 0
      )

    except CatchableError as e:
      logError("Daemon", "Turn resolution failed for game ", gameId, ": ", e.msg)
      # Critical: Clear resolving flag even on failure
      return Proposal[DaemonModel](
        name: "resolution_failed",
        payload: proc(model: var DaemonModel) =
          model.resolving.excl(gameId)
      )

proc createGameDiscoveredProposal(gameId, dbPath, phase: string, turn: int32,
  deadline: Option[int64]): Proposal[DaemonModel] =
  let gId = gameId
  let dbP = dbPath
  let turnNum = turn
  let phaseStr = phase
  return Proposal[DaemonModel](
    name: "game_discovered",
    payload: proc(model: var DaemonModel) =
      logDebug("Daemon", "Applying game_discovered for ID: ", gId)
      model.games[gId] = GameInfo(
        id: gId,
        dbPath: dbP,
        turn: turnNum.int,
        phase: phaseStr,
        transportMode: "nostr",
        turnDeadline: deadline
      )
  )

proc discoverGamesCmd(dir: string): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    let gamesDir = dir / "games"
    var gameDiscoveredProposals = newSeq[Proposal[DaemonModel]]()
    var discoveredGameIds = initHashSet[GameId]()
    if dirExists(gamesDir):
      for kind, path in walkDir(gamesDir):
        if kind == pcDir:
          let dbPath = path / "ec4x.db"
          if fileExists(dbPath):
            let state = reader.loadGameState(dbPath)
            if state == nil:
              logError("Daemon", "Failed to load game state for: ", path)
              continue

            let gameId = state.gameId
            discoveredGameIds.incl(gameId)
            let phase = reader.loadGamePhase(dbPath)
            let phaseStr = if phase.len > 0: phase else: $state.phase
            let deadline = reader.loadGameDeadline(dbPath)

            logInfo("Daemon", "Discovered game: ", state.gameName, " (ID: ",
              gameId, ") turn: ", $state.turn)

            gameDiscoveredProposals.add createGameDiscoveredProposal(
              gameId, dbPath, phaseStr, state.turn, deadline
            )
    let discoveredIds = discoveredGameIds  # Capture for closure
    return Proposal[DaemonModel](
      name: "discovery_complete",
      payload: proc(model: var DaemonModel) =
        # Remove stale games that no longer exist on disk
        var staleIds: seq[GameId] = @[]
        for gameId in model.games.keys:
          if gameId notin discoveredIds:
            staleIds.add(gameId)
        for gameId in staleIds:
          logInfo("Daemon", "Removing stale game from model: ", gameId)
          model.games.del(gameId)
          model.resolving.excl(gameId)
          model.resolutionRequested.excl(gameId)
          if model.pendingOrders.hasKey(gameId):
            model.pendingOrders.del(gameId)
        # Add/update discovered games
        for p in gameDiscoveredProposals:
          if p.payload != nil:
            p.payload(model)
        if not model.readyLogged and model.nostrClient != nil and
            model.nostrClient.isConnected():
          if model.games.len > 0:
            logInfo("Daemon", "Ready - managing ", $model.games.len, " games")
            model.readyLogged = true
    )

proc scheduleNextTickCmd(delayMs: int): DaemonCmd

proc tickMaintenanceCmd(): DaemonCmd =
  ## Async maintenance: cleanup old events, set deadlines, subscribe to games
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    try:
      # Gather game info for maintenance
      var deadlineUpdates = initTable[GameId, Option[int64]]()

      for gameId, gameInfo in daemonLoop.model.games:
        # Cleanup old events
        writer.cleanupProcessedEvents(gameInfo.dbPath, gameId,
          gameInfo.turn.int32, daemonLoop.model.replayRetentionTurns,
          daemonLoop.model.replayRetentionDays,
          daemonLoop.model.replayRetentionDaysDefinition,
          daemonLoop.model.replayRetentionDaysState)

        # Set turn deadlines for games that need them
        if daemonLoop.model.turnDeadlineMinutes > 0 and
            gameInfo.phase == "Active" and gameInfo.turnDeadline.isNone:
          let deadline = calculateTurnDeadline(
            daemonLoop.model.turnDeadlineMinutes)
          updateTurnDeadline(gameInfo.dbPath, gameInfo.id, deadline)
          deadlineUpdates[gameId] = deadline
          if deadline.isSome:
            logInfo("Daemon", "Set turn deadline for game=", gameId,
              " at ", $deadline.get())

        # Subscribe to commands for active games
        if daemonLoop.model.nostrSubscriber != nil and
            daemonLoop.model.nostrClient.isConnected():
          let subId = "daemon:" & gameId
          if subId notin daemonLoop.model.nostrClient.subscriptions:
            asyncCheck daemonLoop.model.nostrSubscriber.subscribeDaemon(gameId,
              daemonLoop.model.identity.publicKeyHex)
            logDebug("Nostr", "Subscribed to commands for game: ", gameId)

      # Subscribe to invite claims (must be outside loop - runs even with no
      # games so players can join new lobbies)
      if daemonLoop.model.nostrSubscriber != nil and
          daemonLoop.model.nostrClient.isConnected():
        if "daemon:invite" notin daemonLoop.model.nostrClient.subscriptions:
          asyncCheck daemonLoop.model.nostrSubscriber.subscribeInviteClaims()
          logDebug("Nostr", "Subscribed to invite slot claims")

      return Proposal[DaemonModel](
        name: "maintenance_complete",
        payload: proc(m: var DaemonModel) =
          # Update model with new deadlines
          for gameId, deadline in deadlineUpdates:
            m.games[gameId].turnDeadline = deadline
      )
    except CatchableError as e:
      logError("Daemon", "Maintenance failed: ", e.msg)
      return Proposal[DaemonModel](
        name: "maintenance_failed",
        payload: proc(m: var DaemonModel) = discard
      )

proc tickProposal(): Proposal[DaemonModel] =
  return Proposal[DaemonModel](
    name: "tick",
    payload: proc(model: var DaemonModel) =
      logInfo("Daemon", "Tick - checking for updates. Managed games: ",
        $model.games.len)

      # Request async operations via reactor
      model.discoveryRequested = true
      model.maintenanceRequested = true

      # Check deadline resolutions (pure logic, no I/O)
      for gameId in model.games.keys:
        checkDeadlineResolution(gameId)

      # Request next tick
      model.tickRequested = true
  )

proc scheduleNextTickCmd(delayMs: int): DaemonCmd =
  proc (): Future[Proposal[DaemonModel]] {.async.} =
    await sleepAsync(delayMs)
    return tickProposal()

proc requestShutdown() {.noconv.} =
  shutdownRequested = true

# =============================================================================
# Nostr Event Processing Helpers
# =============================================================================


proc processIncomingCommand(event: NostrEvent) {.async.} =
  ## Process a turn command event (30402) from a player
  try:
    let gameIdOpt = event.getGameId()
    let turnOpt = event.getTurn()
    
    if gameIdOpt.isNone or turnOpt.isNone:
      logError("Nostr", "Command event missing game ID or turn")
      return
    
    let gameId = gameIdOpt.get()
    let turn = turnOpt.get()

    if not verifyEvent(event):
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Invalid command signature for game=", gameId,
        " event=", eventId)
      return
    
    # Get game info
    if not daemonLoop.model.games.hasKey(gameId):
      logWarn("Nostr", "Command for unknown game: ", gameId)
      return
    
    let gameInfo = daemonLoop.model.games[gameId]

    if reader.hasProcessedEvent(gameInfo.dbPath, gameId,
        event.kind, event.id, reader.ReplayDirection.Inbound):
      logWarn("Nostr", "Duplicate command event ignored: ", event.id[0..7])
      return

    # Validate turn matches current game turn
    if turn != gameInfo.turn:
      logWarn("Nostr", "Command for wrong turn: event has turn=", $turn,
        " but game is on turn=", $gameInfo.turn, " - ignoring")
      return

    # Decrypt command payload (msgpack binary)
    let daemonPriv = crypto.hexToBytes32(daemonLoop.model.identity.privateKeyHex)
    let senderPub = crypto.hexToBytes32(event.pubkey)
    let msgpackCommands = decodePayload(event.content, daemonPriv, senderPub)

    # Parse msgpack into CommandPacket
    let commandPacket = parseOrdersMsgpack(msgpackCommands)

    # Enforce payload turn consistency with validated event turn tag
    if int(commandPacket.turn) != turn:
      logWarn("Nostr", "Command packet turn mismatch for game=", gameId,
        " eventTurn=", $turn, " packetTurn=", $commandPacket.turn)
      return

    # Validate sender ownership of submitted house id
    let state = loadFullState(gameInfo.dbPath)
    let senderHouseOpt = resolveHouseId(state, event.pubkey)
    if senderHouseOpt.isNone:
      logWarn("Nostr", "Command sender not in game=", gameId)
      return

    let senderHouse = senderHouseOpt.get()
    if senderHouse != commandPacket.houseId:
      logWarn("Nostr", "Command sender/house mismatch for game=", gameId,
        " senderHouse=", $senderHouse, " packetHouse=",
        $commandPacket.houseId)
      return

    # Save to database
    saveCommandPacket(gameInfo.dbPath, gameId, commandPacket,
      event.created_at)

    logInfo("Nostr", "Received and saved commands for game=", gameId,
            " turn=", $turn, " house=", $commandPacket.houseId)

    # Check if all players have submitted, trigger turn resolution
    checkAndTriggerResolution(gameId)

    writer.insertProcessedEvent(gameInfo.dbPath, gameId,
      turn.int32, event.kind, event.id, reader.ReplayDirection.Inbound)
    
  except CatchableError as e:
    logError("Nostr", "Failed to process command: ", e.msg)

proc processSlotClaim*(event: NostrEvent) {.async.} =
  ## Process a slot claim event (30401) from a player
  try:
    let gameIdOpt = event.getGameId()
    let inviteCodeOpt = event.getInviteCode()
    
    if gameIdOpt.isNone or inviteCodeOpt.isNone:
      logError("Nostr", "Slot claim event missing game ID or invite code")
      return
    
    let gameId = gameIdOpt.get()
    let inviteCodeRaw = inviteCodeOpt.get()
    let inviteCode = normalizeInviteCode(inviteCodeRaw)
    let playerPubkey = event.pubkey

    if not verifyEvent(event):
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Invalid slot claim signature for game=", gameId,
        " event=", eventId)
      return

    var resolvedGameId = gameId
    var gameInfoOpt = none(GameInfo)
    if gameId == "invite":
      var matches: seq[GameInfo] = @[]
      for _, info in daemonLoop.model.games:
        if reader.inviteCodeMatches(info.dbPath, inviteCode):
          matches.add(info)
      if matches.len == 1:
        gameInfoOpt = some(matches[0])
        resolvedGameId = matches[0].id
      elif matches.len == 0:
        logWarn("Nostr", "Invite code not found in any game")
        if daemonLoop.model.nostrPublisher != nil:
          await daemonLoop.model.nostrPublisher.publishJoinError(
            event.pubkey,
            "Invite code not found"
          )
        return
      else:
        logWarn("Nostr", "Invite code matches multiple games")
        if daemonLoop.model.nostrPublisher != nil:
          await daemonLoop.model.nostrPublisher.publishJoinError(
            event.pubkey,
            "Invite code matches multiple games"
          )
        return
    else:
      if not daemonLoop.model.games.hasKey(gameId):
        logWarn("Nostr", "Slot claim for unknown game: ", gameId)
        return
      gameInfoOpt = some(daemonLoop.model.games[gameId])

    let gameInfo = gameInfoOpt.get()

    if reader.hasProcessedEvent(gameInfo.dbPath, resolvedGameId,
        event.kind, event.id, reader.ReplayDirection.Inbound):
      logWarn("Nostr", "Duplicate slot claim ignored: ", event.id[0..7])
      return

    if not isValidInviteCode(inviteCode):
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Invalid invite code for game=", resolvedGameId,
        " event=", eventId)
      return
 
    let houseOpt = getHouseByInviteCode(gameInfo.dbPath, resolvedGameId,
      inviteCode)
    if houseOpt.isNone:
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Unknown invite code for game=", resolvedGameId,
        " event=", eventId)
      return

    let houseId = houseOpt.get()

    # Load state for claim validation + update
    let updatedState = loadFullState(gameInfo.dbPath)
    if not updatedState.houses.entities.index.hasKey(houseId):
      logError("Nostr", "House not found for invite code in game=",
        resolvedGameId)
      return

    let idx = updatedState.houses.entities.index[houseId]
    let currentPubkey = updatedState.houses.entities.data[idx].nostrPubkey
    if currentPubkey.len > 0:
      if currentPubkey == playerPubkey:
        logInfo("Nostr", "Idempotent slot claim for game=", resolvedGameId,
          " house=", $houseId)

        if daemonLoop.model.nostrPublisher != nil:
          await daemonLoop.model.nostrPublisher.publishFullState(
            gameInfo.id,
            gameInfo.dbPath,
            updatedState,
            houseId
          )
          await daemonLoop.model.nostrPublisher.publishGameDefinition(
            gameInfo.id,
            gameInfo.dbPath,
            gameInfo.phase,
            updatedState
          )

        writer.insertProcessedEvent(gameInfo.dbPath, resolvedGameId,
          0, event.kind, event.id, reader.ReplayDirection.Inbound)
        return

      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Invite code already claimed for game=",
        resolvedGameId, " event=", eventId)
      if daemonLoop.model.nostrPublisher != nil:
        await daemonLoop.model.nostrPublisher.publishJoinError(
          event.pubkey,
          "Invite code already claimed"
        )
      return

    for house in updatedState.houses.entities.data:
      if house.nostrPubkey == playerPubkey and house.id != houseId:
        logWarn("Nostr", "Player already claimed slot for game=",
          resolvedGameId, " player=", playerPubkey[0..7], "...")
        if daemonLoop.model.nostrPublisher != nil:
          await daemonLoop.model.nostrPublisher.publishJoinError(
            event.pubkey,
            "Player already claimed a slot"
          )
        return

    # Update house with player pubkey
    updatedState.houses.entities.data[idx].nostrPubkey = playerPubkey
    saveFullState(updatedState)

    # Publish full state immediately after slot claim
    if daemonLoop.model.nostrPublisher != nil:
      await daemonLoop.model.nostrPublisher.publishFullState(
        gameInfo.id,
        gameInfo.dbPath,
        updatedState,
        houseId
      )
      await daemonLoop.model.nostrPublisher.publishGameDefinition(
        gameInfo.id,
        gameInfo.dbPath,
        gameInfo.phase,
        updatedState
      )

    logInfo("Nostr", "Slot claimed for game=", resolvedGameId,
            " house=", $houseId, " player=", playerPubkey[0..7], "...")

    writer.insertProcessedEvent(gameInfo.dbPath, resolvedGameId,
      0, event.kind, event.id, reader.ReplayDirection.Inbound)


    
  except CatchableError as e:
    logError("Nostr", "Failed to process slot claim: ", e.msg)

proc resolveHouseId(state: GameState, pubkey: string): Option[HouseId] =
  ## Resolve house id for a player pubkey
  for house in state.houses.entities.data:
    if house.nostrPubkey == pubkey:
      return some(house.id)
  none(HouseId)

proc validateMessageText(text: string, maxLen: int32): bool =
  text.len > 0 and text.len <= int(maxLen)

proc processIncomingMessage(event: NostrEvent) {.async.} =
  ## Process a player message event (30406) from a player
  try:
    let gameIdOpt = event.getGameId()
    if gameIdOpt.isNone:
      logError("Nostr", "Message event missing game ID")
      return

    let gameId = gameIdOpt.get()

    if not verifyEvent(event):
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logWarn("Nostr", "Invalid message signature for game=", gameId,
        " event=", eventId)
      return

    if not daemonLoop.model.games.hasKey(gameId):
      logWarn("Nostr", "Message for unknown game: ", gameId)
      return

    let gameInfo = daemonLoop.model.games[gameId]
    if reader.hasProcessedEvent(gameInfo.dbPath, gameId,
        event.kind, event.id, reader.ReplayDirection.Inbound):
      logWarn("Nostr", "Duplicate message event ignored: ", event.id[0..7])
      return

    let daemonPriv = crypto.hexToBytes32(daemonLoop.model.identity.privateKeyHex)
    let senderPub = crypto.hexToBytes32(event.pubkey)
    let msgpackData = decodePayload(event.content, daemonPriv, senderPub)
    let msg = deserializeMessage(msgpackData)

    let state = loadFullState(gameInfo.dbPath)
    let senderHouseOpt = resolveHouseId(state, event.pubkey)
    if senderHouseOpt.isNone:
      logWarn("Nostr", "Message sender not in game=", gameId)
      return

    let senderHouse = senderHouseOpt.get()
    if int32(senderHouse) != msg.fromHouse:
      logWarn("Nostr", "Message sender mismatch for game=", gameId)
      return

    if state.houses.entities.index.hasKey(senderHouse):
      let idx = state.houses.entities.index[senderHouse]
      if state.houses.entities.data[idx].isEliminated:
        logWarn("Nostr", "Message from eliminated house ignored: ",
          $senderHouse)
        return

    if gameConfig.limits.messagingLimits.maxMessageLength <= 0:
      logError("Nostr", "Messaging limits not loaded; rejecting message")
      return
    let maxLen = gameConfig.limits.messagingLimits.maxMessageLength
    if not validateMessageText(msg.text, maxLen):
      logWarn("Nostr", "Message length invalid for game=", gameId)
      return

    let rateLimit = gameConfig.limits.messagingLimits.maxMessagesPerMinute
    if rateLimit > 0:
      if not reader.allowMessageSend(gameInfo.dbPath, gameId,
          msg.fromHouse, rateLimit):
        logWarn("Nostr", "Message rate limit exceeded for house=",
          $senderHouse)
        return

    writer.saveMessage(gameInfo.dbPath, gameId, msg, event.id)
    writer.insertProcessedEvent(gameInfo.dbPath, gameId,
      state.turn.int32, event.kind, event.id, reader.ReplayDirection.Inbound)

    if daemonLoop.model.nostrPublisher == nil:
      logWarn("Nostr", "No publisher available for message forwarding")
      return

    var recipientHouses: seq[HouseId] = @[]
    if msg.toHouse == 0:
      for house in state.houses.entities.data:
        if house.isEliminated:
          continue
        if house.id == senderHouse:
          continue
        recipientHouses.add(house.id)
    else:
      let target = HouseId(msg.toHouse)
      if state.houses.entities.index.hasKey(target):
        let idx = state.houses.entities.index[target]
        if state.houses.entities.data[idx].isEliminated:
          logWarn("Nostr", "Message to eliminated house ignored: ", $target)
          return
        recipientHouses.add(target)
      else:
        logWarn("Nostr", "Message to unknown house ignored: ", $target)
        return

    # Echo back to sender as confirmation
    recipientHouses.add(senderHouse)

    let daemonPubkey = daemonLoop.model.identity.publicKeyHex
    for houseId in recipientHouses:
      let pubkeyOpt = reader.getHousePubkey(gameInfo.dbPath, gameId, houseId)
      if pubkeyOpt.isNone:
        logWarn("Nostr", "No pubkey for house ", $houseId,
          " - skipping message forward")
        continue

      let playerPubkey = pubkeyOpt.get()
      let playerPub = crypto.hexToBytes32(playerPubkey)
      let encryptedPayload = encodePayload(msgpackData, daemonPriv, playerPub)

      var forwardEvent = createPlayerMessage(
        gameId = gameId,
        encryptedPayload = encryptedPayload,
        recipientPubkey = playerPubkey,
        senderPubkey = daemonPubkey,
        fromHouse = msg.fromHouse,
        toHouse = msg.toHouse
      )
      signEvent(forwardEvent, daemonPriv)

      let published = await daemonLoop.model.nostrClient.publish(forwardEvent)
      if published:
        writer.insertProcessedEvent(gameInfo.dbPath, gameId,
          state.turn.int32, forwardEvent.kind, forwardEvent.id,
          reader.ReplayDirection.Outbound)
      else:
        logError("Nostr", "Failed to publish message to house ", $houseId)

  except CatchableError as e:
    logError("Nostr", "Failed to process message: ", e.msg)

# =============================================================================
# Main Event Loop
# =============================================================================

proc initModel*(dataDir: string, pollInterval: int, relayUrls: seq[string],
  replayRetentionTurns: int, replayRetentionDays: int,
  replayRetentionDaysDefinition: int, replayRetentionDaysState: int,
  turnDeadlineMinutes: int, allowIdentityRegen: bool): DaemonModel =
  result = DaemonModel(
    games: initTable[GameId, GameInfo](),
    resolving: initHashSet[GameId](),
    pendingOrders: initTable[GameId, int](),
    running: true,
    dataDir: dataDir,
    pollInterval: pollInterval,
    replayRetentionTurns: replayRetentionTurns,
    replayRetentionDays: replayRetentionDays,
    replayRetentionDaysDefinition: replayRetentionDaysDefinition,
    replayRetentionDaysState: replayRetentionDaysState,
    turnDeadlineMinutes: turnDeadlineMinutes,
    identity: ensureIdentity(allowIdentityRegen),
    nostrClient: nil,  # Will be initialized in mainLoop
    nostrSubscriber: nil,
    nostrPublisher: nil,
    relayUrls: relayUrls,
    readyLogged: false,
    resolutionRequested: initHashSet[GameId](),
    discoveryRequested: false,
    maintenanceRequested: false,
    tickRequested: false
  )
  logInfo("Daemon", "Initialized with identity: ", result.identity.npub())

proc newDaemonLoop(dataDir: string, pollInterval: int, relayUrls: seq[string],
  replayRetentionTurns: int, replayRetentionDays: int,
  replayRetentionDaysDefinition: int, replayRetentionDaysState: int,
  turnDeadlineMinutes: int, allowIdentityRegen: bool): DaemonLoop =
  result = newSamLoop(initModel(dataDir, pollInterval, relayUrls,
    replayRetentionTurns, replayRetentionDays,
    replayRetentionDaysDefinition, replayRetentionDaysState,
    turnDeadlineMinutes, allowIdentityRegen))
  # Add generic acceptor to execute proposal payloads
  result.addAcceptor(proc(model: var DaemonModel,
      proposal: Proposal[DaemonModel]): bool =
    if proposal.payload == nil:
      logError("Daemon", "Received proposal with nil payload: ", proposal.name)
      return false
    proposal.payload(model)
    return true
  )

  # Add reactor to handle side effects (SAM pattern)
  result.addReactor(proc(model: DaemonModel,
      dispatch: proc(p: Proposal[DaemonModel])) =
    # Handle turn resolution requests
    for gameId in model.resolutionRequested:
      if gameId notin model.resolving:
        logDebug("Daemon", "Reactor queueing turn resolution for ", gameId)
        daemonLoop.queueCmd(resolveTurnCmd(gameId))

    # Clear resolution requests via proposal
    if model.resolutionRequested.len > 0:
      let requestedGames = model.resolutionRequested
      dispatch(Proposal[DaemonModel](
        name: "clear_resolution_requests",
        payload: proc(m: var DaemonModel) =
          for gameId in requestedGames:
            m.resolutionRequested.excl(gameId)
      ))

    # Handle game discovery requests
    if model.discoveryRequested:
      logDebug("Daemon", "Reactor queueing game discovery")
      daemonLoop.queueCmd(discoverGamesCmd(model.dataDir))
      dispatch(Proposal[DaemonModel](
        name: "clear_discovery_request",
        payload: proc(m: var DaemonModel) =
          m.discoveryRequested = false
      ))

    # Handle maintenance requests
    if model.maintenanceRequested:
      logDebug("Daemon", "Reactor queueing maintenance")
      daemonLoop.queueCmd(tickMaintenanceCmd())
      dispatch(Proposal[DaemonModel](
        name: "clear_maintenance_request",
        payload: proc(m: var DaemonModel) =
          m.maintenanceRequested = false
      ))

    # Handle tick requests
    if model.tickRequested:
      logDebug("Daemon", "Reactor queueing next tick")
      daemonLoop.queueCmd(scheduleNextTickCmd(model.pollInterval * 1000))
      dispatch(Proposal[DaemonModel](
        name: "clear_tick_request",
        payload: proc(m: var DaemonModel) =
          m.tickRequested = false
      ))
  )

proc initTestDaemonLoop*(dataDir: string): DaemonLoop =
  result = newDaemonLoop(dataDir, 30, @[], 2, 7, 30, 14, 60, true)

proc mainLoop(dataDir: string, pollInterval: int, relayUrls: seq[string],
  replayRetentionTurns: int, replayRetentionDays: int,
  replayRetentionDaysDefinition: int, replayRetentionDaysState: int,
  turnDeadlineMinutes: int, allowIdentityRegen: bool) {.async.} =
  ## SAM daemon loop
  daemonLoop = newDaemonLoop(dataDir, pollInterval, relayUrls,
    replayRetentionTurns, replayRetentionDays,
    replayRetentionDaysDefinition, replayRetentionDaysState,
    turnDeadlineMinutes, allowIdentityRegen)
  
  logInfo("Daemon", "Starting SAM daemon...")
  logInfo("Daemon", "Data directory: ", dataDir)
  logInfo("Daemon", "Poll interval: ", pollInterval, " seconds")
  logInfo("Daemon", "Daemon pubkey: ", daemonLoop.model.identity.npub())

  # Initialize and connect Nostr client
  daemonLoop.model.nostrClient = newNostrClient(relayUrls)
  daemonLoop.model.nostrPublisher = newPublisher(
    daemonLoop.model.nostrClient,
    daemonLoop.model.identity.publicKeyHex,
    crypto.hexToBytes32(daemonLoop.model.identity.privateKeyHex)
  )

  # Set up event callback for incoming commands
  daemonLoop.model.nostrSubscriber = newSubscriber(daemonLoop.model.nostrClient)
  daemonLoop.model.nostrSubscriber.onSlotClaim = proc(event: NostrEvent) =
    try:
      asyncCheck processSlotClaim(event)
    except CatchableError as e:
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logError("Nostr", "Slot claim handler failed: kind=", $event.kind,
        " id=", eventId, " error=", e.msg)
  daemonLoop.model.nostrSubscriber.onCommand = proc(event: NostrEvent) =
    try:
      let gameIdOpt = event.getGameId()
      if gameIdOpt.isNone:
        logError("Nostr", "Command event missing game ID")
        return

      let gameId = gameIdOpt.get()
      if not daemonLoop.model.games.hasKey(gameId):
        logWarn("Nostr", "Received commands for unknown game: ", gameId)
        return

      asyncCheck processIncomingCommand(event)
    except CatchableError as e:
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logError("Nostr", "Event handler failed: kind=", $event.kind,
        " id=", eventId, " error=", e.msg)
  daemonLoop.model.nostrSubscriber.onMessage = proc(event: NostrEvent) =
    try:
      let gameIdOpt = event.getGameId()
      if gameIdOpt.isNone:
        logError("Nostr", "Message event missing game ID")
        return

      let gameId = gameIdOpt.get()
      if not daemonLoop.model.games.hasKey(gameId):
        logWarn("Nostr", "Received message for unknown game: ", gameId)
        return

      asyncCheck processIncomingMessage(event)
    except CatchableError as e:
      let eventId = if event.id.len >= 8: event.id[0..7] else: "unknown"
      logError("Nostr", "Message handler failed: kind=", $event.kind,
        " id=", eventId, " error=", e.msg)
  daemonLoop.model.nostrSubscriber.attachHandlers()

  
  # Connect to relays with backoff
  var backoffMs = 1000
  let maxBackoffMs = 10000
  logInfo("Daemon", "Connecting to relays (backoff enabled)")
  while not shutdownRequested:
    await daemonLoop.model.nostrClient.connect()
    if daemonLoop.model.nostrClient.isConnected():
      break
    logWarn("Daemon", "Failed to connect to any relay; retrying in ",
      $backoffMs, "ms")
    await sleepAsync(backoffMs)
    backoffMs = min(backoffMs * 2, maxBackoffMs)

  if not daemonLoop.model.nostrClient.isConnected():
    logError("Daemon", "Failed to connect to any relay")
    return

  # Start listening for events (non-blocking)
  asyncCheck daemonLoop.model.nostrClient.listen()

  # Start tick chain
  daemonLoop.queueCmd(scheduleNextTickCmd(0))  # Initial immediate

  var reconnectBackoffMs = 1000

  while daemonLoop.model.running and not shutdownRequested:
    daemonLoop.process()

    if not daemonLoop.model.nostrClient.isConnected():
      logWarn("Daemon", "Relay connection lost; reconnecting")
      reconnectBackoffMs = await daemonLoop.model.nostrClient
        .reconnectWithBackoff(reconnectBackoffMs, maxBackoffMs)
      if daemonLoop.model.nostrClient.isConnected():
        asyncCheck daemonLoop.model.nostrClient.listen()

    await sleepAsync(100)  # Non-block poll

  if shutdownRequested:
    logInfo("Daemon", "Shutdown requested")
    daemonLoop.model.running = false

  if daemonLoop.model.nostrClient != nil:
    await daemonLoop.model.nostrClient.disconnect()

  logInfo("Daemon", "Daemon stopped")

  shutdownRequested = false

# =============================================================================
# CLI Entry Point
# =============================================================================

proc start*(
    dataDir: string = "data",
    pollInterval: int = 30,
    configKdl: string = ""
): int =
  ## Start the EC4X daemon
  var finalDataDir = dataDir
  var finalPollInterval = pollInterval
  var finalRelayUrls: seq[string] = @[]
  var replayRetentionTurns = 2
  var replayRetentionDays = 7
  var replayRetentionDaysDefinition = 30
  var replayRetentionDaysState = 14
  var turnDeadlineMinutes = 60

  if configKdl.len > 0:
    logInfo("Daemon", "Loading config from: ", configKdl)
    let cfg = parseDaemonKdl(configKdl)
    finalDataDir = cfg.data_dir
    finalPollInterval = cfg.poll_interval
    finalRelayUrls = cfg.relay_urls
    replayRetentionTurns = cfg.replay_retention_turns
    replayRetentionDays = cfg.replay_retention_days
    replayRetentionDaysDefinition = cfg.replay_retention_days_definition
    replayRetentionDaysState = cfg.replay_retention_days_state
    turnDeadlineMinutes = cfg.turn_deadline_minutes
  else:
    # Default relay
    finalRelayUrls = @["ws://localhost:8080"]

  logInfo("Daemon", "EC4X Daemon starting...")

  if finalDataDir.len == 0:
    logError("Daemon", "Data directory is empty")
    return 1

  if not dirExists(finalDataDir):
    logError("Daemon", "Data directory does not exist: ", finalDataDir)
    return 1

  if finalRelayUrls.len == 0:
    logError("Daemon", "No relay URLs configured")
    return 1

  for url in finalRelayUrls:
    if url.len == 0:
      logError("Daemon", "Relay URL is empty")
      return 1

  try:
    gameConfig = loadGameConfig("config")
  except CatchableError as e:
    logError("Daemon", "Failed to load game config: ", e.msg)
    return 1

  setControlCHook(requestShutdown)

  let allowIdentityRegen = getEnv("EC4X_REGEN_IDENTITY") == "1"
  if allowIdentityRegen:
    logWarn("DaemonIdentity", "Regenerating identity enabled via env")

  try:
    waitFor mainLoop(finalDataDir, finalPollInterval, finalRelayUrls,
      replayRetentionTurns, replayRetentionDays,
      replayRetentionDaysDefinition, replayRetentionDaysState,
      turnDeadlineMinutes, allowIdentityRegen)
  except CatchableError as e:
    logError("Daemon", "Failed to start daemon: ", e.msg)
    return 1

  return 0

proc resolve*(gameId: string, dataDir: string = "data"): int =
  ## Manually trigger turn resolution for a game
  let gamesDir = dataDir / "games"
  let dbPath = gamesDir / gameId / "ec4x.db"

  if not fileExists(dbPath):
    logError("Daemon", "Game database not found: ", dbPath)
    return 1

  logInfo("Daemon", "Manually resolving game: ", gameId)

  # Load game config (required for calculations)
  gameConfig = loadGameConfig("config")

  # Initialize global loop if needed (some cmds might use it)
  let daemonConfig = parseDaemonKdl("config/daemon.kdl")
  daemonLoop = newDaemonLoop(dataDir, 30, daemonConfig.relay_urls,
    daemonConfig.replay_retention_turns, daemonConfig.replay_retention_days,
    daemonConfig.replay_retention_days_definition,
    daemonConfig.replay_retention_days_state, daemonConfig.turn_deadline_minutes,
    true)
  daemonLoop.model.nostrClient = newNostrClient(daemonConfig.relay_urls)
  daemonLoop.model.nostrPublisher = newPublisher(
    daemonLoop.model.nostrClient,
    daemonLoop.model.identity.publicKeyHex,
    crypto.hexToBytes32(daemonLoop.model.identity.privateKeyHex)
  )
  waitFor daemonLoop.model.nostrClient.connect()

  # Load state
  let state = loadFullState(dbPath)
  let commands = loadOrders(dbPath, state.turn)

  # Resolve
  let resolution = resolveTurnDeterministic(state, commands)
  
  # Save
  saveFullState(state)
  saveGameEvents(state, resolution.events)
  markCommandsProcessed(dbPath, gameId, state.turn - 1)

  # Publish turn results via Nostr (if connected)
  if daemonLoop.model.nostrPublisher != nil:
    let gameInfo = GameInfo(
      id: gameId,
      dbPath: dbPath,
      turn: state.turn,
      phase: reader.loadGamePhase(dbPath),
      transportMode: "nostr",
      turnDeadline: reader.loadGameDeadline(dbPath)
    )
    waitFor daemonLoop.model.nostrPublisher.publishTurnResults(
      gameInfo.id,
      gameInfo.dbPath,
      state
    )
  else:
    logWarn("Daemon", "No Nostr publisher - skipping result publishing")
  
  logInfo("Daemon", "Resolution complete. Now at turn ", $state.turn)
  return 0

proc stop*(): int =
  echo "Stop command not yet implemented"
  return 0

proc status*(): int =
  echo "Status command not yet implemented"
  return 0

proc version*(): int =
  echo "EC4X Daemon v0.1.0"
  return 0

when isMainModule:
  dispatchMulti(
    [start, help = "Start the daemon"],
    [stop, help = "Stop the daemon"],
    [status, help = "Show daemon status"],
    [resolve, help = "Manually resolve a turn"],
    [version, help = "Show version"]
  )
