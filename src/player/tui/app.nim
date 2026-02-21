## TUI application entry
##
## Main SAM-based TUI loop and event handling.

import std/[options, strformat, tables, strutils, parseopt, os, algorithm,
  asyncdispatch, sequtils, sets, times]

import ../../common/logger
import ../../engine/globals
import ../../engine/types/[core, command, fleet, tech, player_state as ps_types]
import ../../common/config_sync
import ../../daemon/transport/nostr/[types, events, filter, crypto, nip01]
import ../nostr/client
import ../tui/term/term
import ../tui/buffer
import ../tui/events
import ../tui/input
import ../tui/tty
import ../tui/signals
import ../tui/widget/overview
import ../tui/widget/[hud, breadcrumb, command_dock, scroll_state]
import ../sam/sam_pkg
import ../sam/client_limits
import ../sam/bindings
import ../state/join_flow
import ../state/lobby_profile
import ../state/msgpack_serializer
import ../state/msgpack_state
import ../state/tui_cache
import ../state/tui_config
import ../state/game_name_resolver
import ../../common/message_types
import ./sync
import ./input_map
import ./view_render
import ./output
import ./cursor_target

proc runTui*(gameId: string = "") =
  ## Main TUI execution (called from player entry point)
  logInfo("TUI Player SAM", "Starting EC4X TUI Player with SAM pattern...")

  # Initialize keybinding registry (single source of truth)
  initBindings()

  # Initialize TUI cache (client-side SQLite)
  var tuiCache = openTuiCache()
  var tuiConfig = loadTuiConfig()
  
  # Enable file logging for TUI (stdout goes to terminal buffer)
  let logDir = getHomeDir() / ".config" / "ec4x"
  enableFileLogging(logDir / "tui.log")
  disableStdoutLogging()

  # Initialize player state (TUI now uses PlayerState only, not GameState)
  var playerState = ps_types.PlayerState()
  var viewingHouse = HouseId(1)
  var activeGameId = gameId
  var nostrClient: PlayerNostrClient = nil
  var nostrListenerStarted = false
  var nostrSubscriptions: seq[string] = @[]
  var nostrDaemonPubkey = ""
  var nostrGameDefinitionSeen = initTable[string, int64]()
  var authoritativeConfigLoaded = false
  var authoritativeConfigHash = ""
  var authoritativeConfigSchema = 0'i32
  var authoritativeConfigError = ""
  var lastDraftFingerprint = ""

  var nostrHandlers = PlayerNostrHandlers()

  proc applyAuthoritativeConfig(snapshot: AuthoritativeConfig): bool =
    authoritativeConfigError = ""
    if snapshot.schemaVersion != ConfigSchemaVersion:
      authoritativeConfigError = "schema version mismatch"
      logWarn("TUI/Config", "Rejected config: ", authoritativeConfigError)
      return false
    if computeConfigHash(snapshot) != snapshot.configHash:
      authoritativeConfigError = "config hash mismatch"
      logWarn("TUI/Config", "Rejected config: ", authoritativeConfigError)
      return false
    if not snapshot.hasRequiredSections():
      authoritativeConfigError = "missing required sections"
      logWarn("TUI/Config", "Rejected config: ", authoritativeConfigError)
      return false
    if not snapshot.hasRequiredCapabilities():
      authoritativeConfigError = "missing required capabilities"
      logWarn("TUI/Config", "Rejected config: ", authoritativeConfigError)
      return false
    let contentError = snapshot.requiredContentError()
    if contentError.len > 0:
      authoritativeConfigError = contentError
      logWarn("TUI/Config", "Rejected config: ", authoritativeConfigError)
      return false
    let configOpt = toGameConfig(snapshot)
    if configOpt.isNone:
      authoritativeConfigError = "failed to materialize game config"
      logWarn("TUI/Config", "Rejected config: ", authoritativeConfigError)
      return false
    gameConfig = configOpt.get()
    authoritativeConfigLoaded = true
    authoritativeConfigHash = snapshot.configHash
    authoritativeConfigSchema = snapshot.schemaVersion
    true

  proc setConfigBlockingError(model: var TuiModel, message: string) =
    ## Show a persistent blocking sync error in lobby/load flow.
    model.ui.statusMessage = message
    model.ui.lobbyJoinError = message
    model.ui.entryModal.inviteError = message
    model.ui.appPhase = AppPhase.Lobby

  proc normalizeDraftPacket(packet: CommandPacket): CommandPacket =
    ## Stable ordering for deterministic draft fingerprints.
    result = packet
    result.zeroTurnCommands.sort(
      proc(a: ZeroTurnCommand, b: ZeroTurnCommand): int =
        result = cmp(int(a.commandType), int(b.commandType))
        if result != 0:
          return
        result = cmp(
          if a.sourceFleetId.isSome: int(a.sourceFleetId.get()) else: -1,
          if b.sourceFleetId.isSome: int(b.sourceFleetId.get()) else: -1
        )
        if result != 0:
          return
        result = cmp(
          if a.targetFleetId.isSome: int(a.targetFleetId.get()) else: -1,
          if b.targetFleetId.isSome: int(b.targetFleetId.get()) else: -1
        )
    )
    result.fleetCommands.sort(
      proc(a: FleetCommand, b: FleetCommand): int =
        cmp(int(a.fleetId), int(b.fleetId))
    )

  proc hasResearchDraft(allocation: ResearchAllocation): bool =
    if allocation.economic > 0 or allocation.science > 0:
      return true
    for _, pp in allocation.technology.pairs:
      if pp > 0:
        return true
    false

  proc packetHasDraftData(packet: CommandPacket): bool =
    packet.zeroTurnCommands.len > 0 or
      packet.fleetCommands.len > 0 or
      packet.buildCommands.len > 0 or
      packet.repairCommands.len > 0 or
      packet.scrapCommands.len > 0 or
      packet.colonyManagement.len > 0 or
      packet.diplomaticCommand.len > 0 or
      packet.populationTransfers.len > 0 or
      packet.terraformCommands.len > 0 or
      packet.espionageActions.len > 0 or
      packet.ebpInvestment > 0 or
      packet.cipInvestment > 0 or
      hasResearchDraft(packet.researchAllocation)

  proc packetFingerprint(packet: CommandPacket): string =
    serializeCommandPacket(normalizeDraftPacket(packet))

  proc applyOrderDraft(model: var TuiModel, packet: CommandPacket) =
    ## Replace staged UI orders with restored draft content.
    let normalized = normalizeDraftPacket(packet)
    model.ui.stagedFleetCommands.clear()
    model.ui.stagedZeroTurnCommands = @[]
    model.ui.stagedBuildCommands = @[]
    model.ui.stagedRepairCommands = @[]
    model.ui.stagedScrapCommands = @[]
    model.ui.stagedColonyManagement = @[]
    model.ui.stagedEspionageActions = @[]
    model.ui.stagedEbpInvestment = 0
    model.ui.stagedCipInvestment = 0
    model.ui.stagedZeroTurnCommands = normalized.zeroTurnCommands
    for cmd in normalized.fleetCommands:
      model.stageFleetCommand(cmd)
    model.ui.stagedBuildCommands = normalized.buildCommands
    model.ui.stagedRepairCommands = normalized.repairCommands
    model.ui.stagedScrapCommands = normalized.scrapCommands
    model.ui.stagedColonyManagement = normalized.colonyManagement
    model.ui.stagedEspionageActions = normalized.espionageActions
    model.ui.stagedEbpInvestment = normalized.ebpInvestment
    model.ui.stagedCipInvestment = normalized.cipInvestment
    model.ui.researchAllocation = normalized.researchAllocation
    model.ui.turnSubmissionConfirmed = false

  # Initialize terminal
  var tty = openTty()
  if not tty.start():
    logError("TUI Player SAM", "Failed to enter raw mode")
    quit(1)

  setupResizeHandler()
  var (termWidth, termHeight) = tty.windowSize()
  logInfo("TUI Player SAM", &"Terminal size: {termWidth}x{termHeight}")

  var buf = initBuffer(termWidth, termHeight)

  # =========================================================================
  # SAM Setup
  # =========================================================================

  # Create SAM instance (history disabled)
  var sam = initTuiSam()

  # ============================================================================
  # Proposal Queue (async-safe)
  # ============================================================================
 
  type ProposalSignature = tuple[
    kind: ProposalKind,
    actionKind: ActionKind,
    timestamp: int64
  ]

  var proposalQueue: seq[Proposal] = @[]
  var recentProposals = initHashSet[ProposalSignature]()
  const MaxProposalQueue = 100
  
  proc proposalSignature(p: Proposal): ProposalSignature =
    (
      kind: p.kind,
      actionKind: p.actionKind,
      timestamp: p.timestamp
    )
 
  proc enqueueProposal(p: Proposal) =
    let sig = proposalSignature(p)
    if sig in recentProposals:
      return
    if proposalQueue.len >= MaxProposalQueue:
      let old = proposalQueue[0]
      let oldSig = proposalSignature(old)
      recentProposals.excl(oldSig)
      proposalQueue.delete(0)
    proposalQueue.add(p)
    recentProposals.incl(sig)
 
  proc drainProposalQueue() =
    while proposalQueue.len > 0:
      let p = proposalQueue[0]
      proposalQueue.delete(0)
      sam.present(p)

  proc syncCachedIntelNotes(model: var TuiModel) =
    if activeGameId.len == 0:
      return
    let notes = tuiCache.loadIntelNotes(activeGameId, int(viewingHouse))
    model.applyIntelNotes(notes)

  proc syncCachedMessages(model: var TuiModel) =
    if activeGameId.len == 0:
      return
    if int(viewingHouse) <= 0:
      return
    let msgs = tuiCache.loadMessages(activeGameId, int(viewingHouse))
    let previousThreadCounts = model.view.messageThreads
    model.view.messageThreads.clear()
    model.view.messageHouses = @[(0'i32, "Broadcast", 0)]
    for id, name in model.view.houseNames:
      if id == int(viewingHouse):
        continue
      model.view.messageHouses.add((int32(id), name, 0))
    for msg in msgs:
      let threadId =
        if msg.toHouse == 0:
          0'i32
        elif msg.fromHouse == int32(viewingHouse):
          msg.toHouse
        else:
          msg.fromHouse
      if not model.view.messageThreads.hasKey(threadId):
        model.view.messageThreads[threadId] = @[]
      model.view.messageThreads[threadId].add(msg)
    for i in 0 ..< model.view.messageHouses.len:
      let threadId = model.view.messageHouses[i].id
      let unread = tuiCache.unreadThreadMessageCount(
        activeGameId,
        int(viewingHouse),
        int(threadId)
      )
      model.view.messageHouses[i].unread = unread
    var shouldAutoScroll = false
    var wasAtBottom = false
    if model.ui.mode == ViewMode.Messages:
      wasAtBottom = model.ui.messagesScroll.isAtBottom()
      let idx = clamp(model.ui.messageHouseIdx, 0,
        max(0, model.view.messageHouses.len - 1))
      let targetId = if model.view.messageHouses.len > 0:
        model.view.messageHouses[idx].id
      else:
        0'i32
      if model.view.messageThreads.hasKey(targetId):
        let items = model.view.messageThreads[targetId]
        let previousCount =
          if previousThreadCounts.hasKey(targetId):
            previousThreadCounts[targetId].len
          else:
            0
        if items.len > previousCount and
            (model.ui.inboxFocus == InboxPaneFocus.Detail or
             model.ui.inboxFocus == InboxPaneFocus.Compose) and
            wasAtBottom:
          shouldAutoScroll = true
    if shouldAutoScroll:
      model.ui.messagesScroll.verticalOffset = 1_000_000_000
    if model.ui.mode == ViewMode.Messages and
        model.ui.inboxFocus == InboxPaneFocus.Detail and
        model.view.messageThreads.len > 0:
      let idx = clamp(model.ui.messageHouseIdx, 0,
        max(0, model.view.messageHouses.len - 1))
      let targetId = if model.view.messageHouses.len > 0:
        model.view.messageHouses[idx].id
      else:
        0'i32
      var anyUnread = false
      if model.view.messageThreads.hasKey(targetId):
        for msg in model.view.messageThreads[targetId]:
          if msg.fromHouse != int32(viewingHouse):
            anyUnread = true
            break
      if anyUnread:
        tuiCache.markMessagesRead(activeGameId, int(viewingHouse),
          int(targetId))
    model.view.unreadMessages =
      tuiCache.unreadMessageCount(activeGameId, int(viewingHouse))

  proc handleIncomingMessage(event: NostrEvent, msg: GameMessage) =
    if activeGameId.len == 0:
      return
    if event.id.len > 0 and tuiCache.hasReceivedEvent(event.id):
      return
    if event.id.len > 0:
      tuiCache.markEventReceived(event.id, event.kind, activeGameId)
    let isLocalSender = msg.fromHouse == int32(viewingHouse)
    if not isLocalSender:
      tuiCache.saveMessage(activeGameId, msg, isRead = false)
      syncCachedMessages(sam.model)
    if msg.fromHouse != int32(viewingHouse):
      sam.model.ui.statusMessage = "New message received"
    enqueueProposal(emptyProposal())

  # Create initial model
  var initialModel = initTuiModel()
  initialModel.ui.termWidth = termWidth
  initialModel.ui.termHeight = termHeight
  initialModel.view.viewingHouse = int(viewingHouse)
  initialModel.ui.mode = ViewMode.Overview

  if gameId.len > 0:
    initialModel.ui.appPhase = AppPhase.Lobby
    activeGameId = gameId
    # Load game info from cache instead of daemon's DB
    let cachedGame = tuiCache.getGame(gameId)
    if cachedGame.isSome:
      let gameInfo = cachedGame.get()
      initialModel.view.turn = gameInfo.turn
      initialModel.view.houseName = gameInfo.name
    else:
      initialModel.ui.statusMessage = "Game not found in cache"

  proc isPlaceholderGame(game: CachedGame, houseId: int): bool =
    if game.id == "invite":
      return true
    if game.status == "placeholder" or game.status == "invite":
      return true
    if game.relayUrl.len == 0 and game.daemonPubkey.len == 0 and
        game.turn == 0 and houseId == 0:
      return true
    false

  proc isRemovablePlaceholder(game: CachedGame): bool =
    game.id == "invite" or game.status == "placeholder" or
      game.status == "invite"

  if initialModel.ui.lobbyProfilePubkeyInput.value().len > 0:
    # Run migration from old KDL join cache files
    tuiCache.runMigrations("data", initialModel.ui.lobbyProfilePubkeyInput.value())
    tuiCache.pruneStaleGames(30)

    # Load games from cache instead of daemon's DB
    let cachedGames = tuiCache.listPlayerGames(
      initialModel.ui.lobbyProfilePubkeyInput.value()
    )
    for (game, houseId) in cachedGames:
      if isPlaceholderGame(game, houseId):
        if isRemovablePlaceholder(game):
          tuiCache.deletePlayerSlot(game.id,
            initialModel.ui.lobbyProfilePubkeyInput.value())
          tuiCache.deleteGame(game.id)
        continue
      initialModel.view.lobbyActiveGames.add(ActiveGameInfo(
        id: game.id,
        name: game.name,
        turn: game.turn,
        phase: game.status,
        houseId: houseId
      ))
  else:
    let profiles = loadProfiles("data")
    if profiles.len > 0:
      initialModel.ui.lobbyProfilePubkeyInput.setText(profiles[0])
      let profileInfo = loadProfile("data",
        initialModel.ui.lobbyProfilePubkeyInput.value())
      initialModel.ui.lobbyProfileNameInput.setText(profileInfo.name)
      initialModel.ui.lobbySessionKeyActive = profileInfo.session

      # Run migration and load from cache
      tuiCache.runMigrations("data", initialModel.ui.lobbyProfilePubkeyInput.value())
      tuiCache.pruneStaleGames(30)
      let cachedGames = tuiCache.listPlayerGames(
        initialModel.ui.lobbyProfilePubkeyInput.value()
      )
      for (game, houseId) in cachedGames:
        if isPlaceholderGame(game, houseId):
          if isRemovablePlaceholder(game):
            tuiCache.deletePlayerSlot(game.id,
              initialModel.ui.lobbyProfilePubkeyInput.value())
            tuiCache.deleteGame(game.id)
          continue
        initialModel.view.lobbyActiveGames.add(ActiveGameInfo(
          id: game.id,
          name: game.name,
          turn: game.turn,
          phase: game.status,
          houseId: houseId
        ))

  # Sync lobbyActiveGames to entryModal.activeGames (includes houseId)
  for game in initialModel.view.lobbyActiveGames:
    initialModel.ui.entryModal.activeGames.add(EntryActiveGameInfo(
      id: game.id,
      name: game.name,
      turn: game.turn,
      houseName: "",
      houseId: game.houseId,
      status: game.phase
    ))

  # Note: lobbyJoinGames (available games to join) comes from Nostr events
  # games appear when their definition events arrive from the relay

  # Set default relay URL from config if not provided via entry modal
  if initialModel.ui.entryModal.relayUrl().len > 0:
    initialModel.ui.nostrRelayUrl = initialModel.ui.entryModal.relayUrl()
  elif tuiConfig.defaultRelay.len > 0:
    initialModel.ui.nostrRelayUrl = tuiConfig.defaultRelay

  # Sync player state to model (only after joining a game)
  if initialModel.ui.appPhase == AppPhase.InGame and
      initialModel.view.playerStateLoaded:
    syncPlayerStateToModel(initialModel, playerState)
    syncCachedIntelNotes(initialModel)
    syncCachedMessages(initialModel)
    syncBuildModalData(initialModel, playerState)
    initialModel.resetBreadcrumbs(initialModel.ui.mode)

    if initialModel.view.homeworld.isSome:
      initialModel.ui.mapState.cursor = initialModel.view.homeworld.get

  if initialModel.ui.nostrRelayUrl.len > 0:
    try:
      let identity = initialModel.ui.entryModal.identity
      let relayList = @[initialModel.ui.nostrRelayUrl]

      nostrHandlers.onDelta = proc(event: NostrEvent, payload: string) =
        try:
          if not authoritativeConfigLoaded:
            sam.model.ui.statusMessage =
              "Ignored delta: missing authoritative config"
            return
          let turnOpt = event.getTurn()
          if turnOpt.isNone:
            sam.model.ui.statusMessage = "Ignored event: missing turn"
            return
          if sam.model.view.playerStateLoaded and
              turnOpt.get() <= sam.model.view.turn:
            sam.model.ui.statusMessage = "Ignored event: stale turn"
            return
          if event.pubkey.len > 0 and
              nostrDaemonPubkey.len > 0 and
              event.pubkey != nostrDaemonPubkey:
            sam.model.ui.statusMessage = "Ignored event: unknown server"
            return
          let appliedTurnOpt = applyDeltaMsgpack(
            playerState,
            payload,
            authoritativeConfigHash,
            authoritativeConfigSchema
          )
          if appliedTurnOpt.isSome:
            sam.model.view.turn = int(appliedTurnOpt.get())
            sam.model.view.playerStateLoaded = true
            sam.model.ui.statusMessage = "Delta applied"
            # Sync PlayerState to model after delta
            syncPlayerStateToModel(sam.model, playerState)
            syncCachedIntelNotes(sam.model)
            syncCachedMessages(sam.model)
            # Sync build modal data if active
            syncBuildModalData(sam.model, playerState)
            # Cache the updated state
            if activeGameId.len > 0:
              tuiCache.savePlayerState(activeGameId, int(viewingHouse),
                playerState.turn, playerState)
          else:
            sam.model.ui.statusMessage =
              "Rejected delta: config mismatch or invalid payload"
          enqueueProposal(emptyProposal())
        except CatchableError as e:
          sam.model.ui.nostrLastError = e.msg
          sam.model.ui.nostrStatus = "error"
          sam.model.ui.nostrEnabled = false
          enqueueProposal(emptyProposal())

      nostrHandlers.onFullState = proc(event: NostrEvent, payload: string) =
        try:
          logDebug("TUI/State", "onFullState called",
            "eventId=", event.id[0..min(15, event.id.len-1)],
            "payloadLen=", $payload.len)
          let turnOpt = event.getTurn()
          if turnOpt.isNone:
            sam.model.ui.statusMessage = "Ignored event: missing turn"
            logDebug("TUI/State", "Missing turn tag in event")
            return
          if sam.model.view.playerStateLoaded and
              turnOpt.get() <= sam.model.view.turn:
            sam.model.ui.statusMessage = "Ignored event: stale turn"
            return
          if event.pubkey.len > 0 and
              nostrDaemonPubkey.len > 0 and
              event.pubkey != nostrDaemonPubkey:
            sam.model.ui.statusMessage = "Ignored event: unknown server"
            return
          logDebug("TUI/State", "Parsing full state msgpack",
            "payloadLen=", $payload.len)
          let envelopeOpt = parseFullStateMsgpack(payload)
          if envelopeOpt.isSome:
            let envelope = envelopeOpt.get()
            if not applyAuthoritativeConfig(envelope.authoritativeConfig):
              let reason = if authoritativeConfigError.len > 0:
                authoritativeConfigError
              else:
                "invalid authoritative config"
              setConfigBlockingError(
                sam.model,
                "Rejected full state: " & reason
              )
              enqueueProposal(emptyProposal())
              return
            if activeGameId.len > 0:
              tuiCache.saveConfigSnapshot(
                activeGameId,
                envelope.authoritativeConfig
              )
            logDebug("TUI/State", "State parsed successfully",
              "turn=", $envelope.playerState.turn,
              "houseId=", $envelope.playerState.viewingHouse)
            playerState = envelope.playerState
            sam.model.view.playerStateLoaded = true
            viewingHouse = playerState.viewingHouse
            sam.model.view.viewingHouse = int(viewingHouse)
            sam.model.view.turn = int(playerState.turn)
            sam.model.ui.statusMessage = "Full state received"
            if sam.model.ui.nostrEnabled:
              sam.model.ui.nostrStatus = "connected"
            # Sync PlayerState to model
            syncPlayerStateToModel(sam.model, playerState)
            syncCachedIntelNotes(sam.model)
            syncCachedMessages(sam.model)
            syncBuildModalData(sam.model, playerState)
            if activeGameId.len > 0 and authoritativeConfigLoaded:
              let draftOpt = tuiCache.loadOrderDraft(
                activeGameId,
                int(viewingHouse)
              )
              if draftOpt.isSome:
                let draft = draftOpt.get()
                if draft.turn != playerState.turn:
                  tuiCache.clearOrderDraft(activeGameId, int(viewingHouse))
                  sam.model.ui.statusMessage =
                    "Discarded saved draft (turn changed)"
                elif draft.configHash != authoritativeConfigHash:
                  tuiCache.clearOrderDraft(activeGameId, int(viewingHouse))
                  sam.model.ui.statusMessage =
                    "Discarded saved draft (rules changed)"
                else:
                  applyOrderDraft(sam.model, draft.packet)
                  syncBuildModalData(sam.model, playerState)
                  let cmdCount = sam.model.stagedCommandCount()
                  sam.model.ui.statusMessage =
                    "Restored saved draft (" & $cmdCount & " staged)"
                  lastDraftFingerprint = packetFingerprint(draft.packet)
            sam.model.resetBreadcrumbs(sam.model.ui.mode)
            if sam.model.view.homeworld.isSome:
              sam.model.ui.mapState.cursor = sam.model.view.homeworld.get
            if sam.model.ui.appPhase == AppPhase.Lobby:
              sam.model.ui.appPhase = AppPhase.InGame
              sam.model.ui.mode = ViewMode.Overview
            # Cache the received state for future sessions
            if activeGameId.len > 0:
              tuiCache.savePlayerState(activeGameId, int(viewingHouse),
                playerState.turn, playerState)
          else:
            sam.model.ui.statusMessage = "Invalid full state payload"
            logDebug("TUI/State", "Failed to parse state msgpack",
              "payloadLen=", $payload.len)
          enqueueProposal(emptyProposal())
        except CatchableError as e:
          sam.model.ui.nostrLastError = e.msg
          sam.model.ui.nostrStatus = "error"
          sam.model.ui.nostrEnabled = false
          enqueueProposal(emptyProposal())

      nostrHandlers.onMessage = proc(event: NostrEvent, msg: GameMessage) =
        handleIncomingMessage(event, msg)

      nostrHandlers.onEvent = proc(subId: string, event: NostrEvent) =
        logInfo("EVENT", "Received event: subId=", subId, " kind=", event.kind,
          " id=", event.id[0..min(8, event.id.len-1)])
        try:
          if event.kind == EventKindGameDefinition:
            let joinRequested = sam.model.ui.nostrJoinRequested
            let joinSent = sam.model.ui.nostrJoinSent
            let joinGameId = sam.model.ui.nostrJoinGameId
            let joinPubkey = sam.model.ui.nostrJoinPubkey
            let gameIdOpt = event.getGameId()
            logDebug("TUI/Join", "GameDef received",
              "gid=", if gameIdOpt.isSome: gameIdOpt.get() else: "",
              "req=", $joinRequested,
              "sent=", $joinSent,
              "jgid=", joinGameId,
              "jpkLen=", $joinPubkey.len,
              "evPkLen=", $event.pubkey.len)
            if gameIdOpt.isSome:
              let gameId = gameIdOpt.get()
              let lastSeen = if nostrGameDefinitionSeen.hasKey(gameId):
                nostrGameDefinitionSeen[gameId]
                else:
                  0'i64
              if event.created_at <= lastSeen:
                sam.model.ui.statusMessage =
                  "Ignored game definition: stale"
                return
              nostrGameDefinitionSeen[gameId] = event.created_at

              if event.pubkey.len > 0 and
                  nostrDaemonPubkey.len > 0 and
                  event.pubkey != nostrDaemonPubkey:
                sam.model.ui.statusMessage =
                  "Ignored game definition: unknown server"
                return

              let nameTag = event.getTagValue(TagName)
              let statusTag = event.getStatus()
              let turnOpt = event.getTurn()
              let cachedGameOpt = tuiCache.getGame(gameId)
              let cachedName = if cachedGameOpt.isSome:
                cachedGameOpt.get().name
              else:
                ""
              let resolvedName = resolveGameName(nameTag, gameId, cachedName)
              let gameNameStr = resolvedName.name
              let turnNum = if turnOpt.isSome: turnOpt.get() else: 0
              let gameStatus = if statusTag.isSome: statusTag.get() else: "active"
              logDebug("TUI/Join", "Resolved game name",
                "gid=", gameId,
                "src=", resolvedName.source,
                "name=", gameNameStr)

              if gameStatus == GameStatusCancelled or
                  gameStatus == GameStatusRemoved:
                tuiCache.deletePlayerSlot(gameId,
                  sam.model.ui.lobbyProfilePubkeyInput.value())
                tuiCache.deleteGame(gameId)
                sam.model.view.lobbyActiveGames =
                  sam.model.view.lobbyActiveGames.filterIt(it.id != gameId)
                sam.model.ui.entryModal.activeGames =
                  sam.model.ui.entryModal.activeGames.filterIt(it.id != gameId)
                if gameId == activeGameId:
                  sam.model.ui.statusMessage = "Game removed"
                return

              # Update cache with game metadata from Nostr event
              tuiCache.upsertGame(gameId, gameNameStr, turnNum, gameStatus,
                sam.model.ui.nostrRelayUrl, event.pubkey)

              # Check if player has a slot in this game
              let slotOpt = tuiCache.getPlayerSlot(gameId,
                sam.model.ui.lobbyProfilePubkeyInput.value())
              let houseIdFromCache = if slotOpt.isSome:
                slotOpt.get().houseId else: 0

              if houseIdFromCache > 0:
                let gameInfo = EntryActiveGameInfo(
                  id: gameId,
                  name: gameNameStr,
                  turn: turnNum,
                  houseName: "",
                  houseId: houseIdFromCache,
                  status: gameStatus
                )
                var updated = false
                for idx in 0..<sam.model.ui.entryModal.activeGames.len:
                  if sam.model.ui.entryModal.activeGames[idx].id == gameId:
                    # Preserve houseId if we had one
                    let existingHouseId =
                      sam.model.ui.entryModal.activeGames[idx].houseId
                    sam.model.ui.entryModal.activeGames[idx] = gameInfo
                    if existingHouseId != 0:
                      sam.model.ui.entryModal.activeGames[idx].houseId =
                        existingHouseId
                    sam.model.ui.entryModal.activeGames[idx].status =
                      gameStatus
                    updated = true
                    break
                if not updated:
                  sam.model.ui.entryModal.activeGames.add(gameInfo)

                var lobbyUpdated = false
                for idx in 0..<sam.model.view.lobbyActiveGames.len:
                  if sam.model.view.lobbyActiveGames[idx].id == gameId:
                    sam.model.view.lobbyActiveGames[idx] = ActiveGameInfo(
                      id: gameId,
                      name: gameNameStr,
                      turn: turnNum,
                      phase: gameStatus,
                      houseId: houseIdFromCache
                    )
                    lobbyUpdated = true
                    break
                if not lobbyUpdated:
                  sam.model.view.lobbyActiveGames.add(ActiveGameInfo(
                    id: gameId,
                    name: gameNameStr,
                    turn: turnNum,
                    phase: gameStatus,
                    houseId: houseIdFromCache
                  ))
              if gameId == activeGameId and
                  event.pubkey.len > 0 and
                  nostrDaemonPubkey.len == 0:
                nostrDaemonPubkey = event.pubkey
                if nostrClient != nil:
                  nostrClient.setDaemonPubkey(nostrDaemonPubkey)
            logInfo("JOIN", "GameDef event: gameId=",
              if gameIdOpt.isSome: gameIdOpt.get() else: "none",
              " joinReq=", sam.model.ui.nostrJoinRequested,
              " joinSent=", sam.model.ui.nostrJoinSent,
              " joinGameId=", sam.model.ui.nostrJoinGameId,
              " joinPubkey=",
              sam.model.ui.nostrJoinPubkey[0..min(16,
              sam.model.ui.nostrJoinPubkey.len-1)])
            if (sam.model.ui.nostrJoinRequested or
                sam.model.ui.nostrJoinSent) and
                sam.model.ui.nostrJoinGameId.len > 0 and
                event.pubkey.len > 0 and
                sam.model.ui.nostrJoinPubkey.len > 0 and
                gameIdOpt.isSome:
              logInfo("JOIN", "Passed join handler checks, looking for claimed slot...")
              let slots = event.getSlots()
              logDebug("TUI/Join", "Slots received",
                "count=", $slots.len)
              for slot in slots:
                let slotPk =
                  if slot.pubkey.len > 0:
                    slot.pubkey[0..<min(16, slot.pubkey.len)]
                  else:
                    ""
                let joinPk =
                  if sam.model.ui.nostrJoinPubkey.len > 0:
                    sam.model.ui.nostrJoinPubkey[0..<min(16,
                      sam.model.ui.nostrJoinPubkey.len)]
                  else:
                    ""
                let pubkeyMatch = slot.pubkey == sam.model.ui.nostrJoinPubkey
                logDebug("TUI/Join", "Slot candidate",
                  "idx=", $slot.index,
                  "status=", $slot.status,
                  "pk=", slotPk,
                  "jpk=", joinPk,
                  "match=", $pubkeyMatch)
                if slot.status == SlotStatusClaimed and
                    slot.pubkey == sam.model.ui.nostrJoinPubkey:
                  let joinPubkey = sam.model.ui.nostrJoinPubkey
                  # Use actual game ID from event, not the "invite" placeholder
                  let joinGameId = gameIdOpt.get()
                  let gameName = event.getTagValue(TagName)
                  let turnOpt = event.getTurn()
                  let houseId = HouseId(slot.index.uint32)
                  logInfo("JOIN", "★★★ FOUND MATCH! Adding game to cache",
                    " game=", joinGameId, " house=", $houseId)

                  # Update TUI cache with joined game
                  let cachedGameOpt = tuiCache.getGame(joinGameId)
                  let cachedName = if cachedGameOpt.isSome:
                    cachedGameOpt.get().name
                  else:
                    ""
                  let resolvedName = resolveGameName(
                    gameName, joinGameId, cachedName)
                  let gameNameStr = resolvedName.name
                  let turnNum = if turnOpt.isSome: turnOpt.get() else: 0
                  logInfo("JOIN", "Writing to cache: game=", joinGameId,
                    " name=", gameNameStr, " turn=", turnNum,
                    " relay=", sam.model.ui.nostrRelayUrl,
                    " src=", resolvedName.source)
                  tuiCache.upsertGame(joinGameId, gameNameStr, turnNum,
                    "active", sam.model.ui.nostrRelayUrl, event.pubkey)
                  tuiCache.insertPlayerSlot(joinGameId, joinPubkey,
                    int(houseId))
                  logInfo("JOIN", "Cache updated successfully")

                  # Also write legacy join cache for backward compat
                  writeJoinCache("data", joinPubkey, joinGameId,
                    houseId, gameNameStr)
                  if gameName.isSome:
                    saveProfile("data", joinPubkey,
                      sam.model.ui.lobbyProfileNameInput.value(),
                      sam.model.ui.lobbySessionKeyActive)

                  # Update in-memory model from cache
                  sam.model.view.lobbyActiveGames.add(ActiveGameInfo(
                    id: joinGameId,
                    name: gameNameStr,
                    turn: turnNum,
                    phase: "active",
                    houseId: int(houseId)
                  ))

                  # Update entry modal with houseId (or add if not present)
                  var foundGame = false
                  for idx in 0..<sam.model.ui.entryModal.activeGames.len:
                    if sam.model.ui.entryModal.activeGames[idx].id ==
                        joinGameId:
                      sam.model.ui.entryModal.activeGames[idx].houseId =
                        int(houseId)
                      sam.model.ui.entryModal.activeGames[idx].status =
                        "active"
                      foundGame = true
                      logInfo("JOIN", "Updated existing game in entryModal")
                      break
                  if not foundGame:
                    logInfo("JOIN", "Adding new game to entryModal")
                    # Add the game if not already in entry modal
                    sam.model.ui.entryModal.activeGames.add(
                      EntryActiveGameInfo(
                      id: joinGameId,
                      name: gameNameStr,
                      turn: turnNum,
                      houseName: "",
                      houseId: int(houseId),
                      status: "active"
                    ))
                  sam.model.ui.lobbyJoinStatus = JoinStatus.Joined
                  sam.model.ui.lobbyJoinError = ""
                  sam.model.ui.statusMessage = "Joined game " & joinGameId
                  sam.model.ui.nostrJoinRequested = false
                  sam.model.ui.nostrJoinSent = false
                  sam.model.ui.nostrJoinInviteCode = ""
                  sam.model.ui.nostrJoinRelayUrl = ""
                  sam.model.ui.nostrJoinGameId = ""
                  sam.model.ui.nostrJoinPubkey = ""
                  sam.model.ui.entryModal.inviteInput.clear()
                  sam.model.ui.entryModal.inviteError = ""
                  logInfo("JOIN", "★★★ JOIN COMPLETE! Game should now appear in YOUR GAMES")
                  break
            enqueueProposal(emptyProposal())
        except CatchableError as e:
          sam.model.ui.nostrLastError = e.msg
          sam.model.ui.nostrStatus = "error"
          sam.model.ui.nostrEnabled = false
          enqueueProposal(emptyProposal())

      nostrHandlers.onJoinError = proc(message: string) =
        if sam.model.ui.lobbyJoinStatus == JoinStatus.WaitingResponse:
          sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
          sam.model.ui.lobbyJoinError = message
          sam.model.ui.statusMessage = message
          sam.model.ui.nostrJoinRequested = false
          sam.model.ui.nostrJoinSent = false
          sam.model.ui.nostrJoinInviteCode = ""
          sam.model.ui.nostrJoinGameId = ""
        enqueueProposal(emptyProposal())

      nostrHandlers.onError = proc(message: string) =
        # Log error but don't disable the entire client
        # Individual event decode errors shouldn't kill the connection
        logWarn("Nostr/Error", message)
        sam.model.ui.nostrLastError = message
        # Don't change status or disable - keep processing other events
        enqueueProposal(emptyProposal())

      nostrClient = newPlayerNostrClient(
        relayList,
        activeGameId,
        identity.nsecHex,
        identity.npubHex,
        nostrDaemonPubkey,
        nostrHandlers
      )

      asyncCheck nostrClient.start()
      initialModel.ui.nostrStatus = "connecting"
      initialModel.ui.nostrEnabled = true
      
      # Wait for connection to establish (up to 5 seconds)
      for i in 0..50:
        poll(100)
        if nostrClient.isConnected():
          logInfo("Nostr", "Connection established after ", $((i+1)*100), "ms")
          initialModel.ui.nostrStatus = "connected"

          # Start listening and subscribe to lobby games
          asyncCheck nostrClient.listen()
          nostrListenerStarted = true
          let lobbyFilter = newFilter().withKinds(@[EventKindGameDefinition])
          asyncCheck nostrClient.subscribe("lobby:games", @[lobbyFilter])
          nostrSubscriptions.add("lobby:games")
          logInfo("Nostr", "Subscribed to lobby:games")

          # Subscribe to join errors for this player
          if identity.npubHex.len > 0:
            let joinErrorFilter = newFilter()
              .withKinds(@[EventKindJoinError])
              .withTag(TagP, @[identity.npubHex])
            asyncCheck nostrClient.subscribe("lobby:join-errors", @[joinErrorFilter])
            nostrSubscriptions.add("lobby:join-errors")
            logInfo("Nostr", "Subscribed to lobby:join-errors")
          break

      if not nostrClient.isConnected():
        logWarn("Nostr", "Connection not established within timeout")
        initialModel.ui.nostrStatus = "error"
    except CatchableError as e:
      initialModel.ui.nostrLastError = e.msg
      initialModel.ui.nostrStatus = "error"
      initialModel.ui.nostrEnabled = false
  
  # Sync initial nostr status to entry modal
  initialModel.ui.entryModal.nostrStatus = initialModel.ui.nostrStatus

  # =========================================================================
  # Render Function (decoupled from SAM - called explicitly by main loop)
  # =========================================================================
  # 
  # We do NOT set a render callback on SAM. Instead, we control rendering
  # explicitly in the main loop at a fixed frame rate (60fps). This:
  # - Prevents multiple renders when processing batched input
  # - Keeps the UI responsive regardless of input volume
  # - Allows model updates to be processed without render overhead
  # - Follows the game loop pattern: input → update → render
  #
  var needsRender = true  # Flag set when model changes
  var lastRenderTime = epochTime()
  const TargetFrameTimeMs = 16  # ~60fps (16.67ms per frame)
  
  proc doRender() =
    ## Explicit render function - called by main loop, not SAM
    clearCursorTarget()
    buf.clear()
    renderDashboard(buf, sam.model, playerState)
    outputBuffer(buf)
    let targetOpt = cursorTarget()
    if targetOpt.isSome:
      let target = targetOpt.get()
      stdout.write(showCursor())
      stdout.write(setCursorStyle(target.style))
      stdout.write(moveCursor(target.y + 1, target.x + 1))
    else:
      stdout.write(hideCursor())
    stdout.flushFile()
  
  # Note: We intentionally don't call sam.setRender() - rendering is 
  # controlled by the main loop's frame timing, not triggered by present()

  # Enter alternate screen before initial render
  stdout.write(altScreen())
  stdout.write(hideCursor())
  stdout.write(enableKittyKeys())
  stdout.flushFile()

  # Set initial state (no longer triggers render - we control that)
  sam.setInitialState(initialModel)

  logInfo("TUI Player SAM", "SAM initialized, entering TUI mode...")

  # Create input parser
  var parser = initParser()

  # Initial render (explicit)
  doRender()
  lastRenderTime = epochTime()
  needsRender = false

  # =========================================================================
  # Nostr Connection State Machine
  # =========================================================================
  # These variables track async connection/publish operations without blocking.
  # Instead of polling in a loop, we check progress on each main loop iteration.
  #
  var nostrConnectStartTime: float = 0.0  # When connection attempt started
  var nostrPublishFuture: Future[bool] = nil  # Pending publish operation
  var nostrPublishStartTime: float = 0.0  # When publish started
  const NostrConnectTimeoutSec = 3.0  # Max time to wait for connection
  const NostrPublishTimeoutSec = 3.0  # Max time to wait for publish

  proc processNostr() =
    ## Process Nostr connection state machine - NON-BLOCKING.
    ## This function checks connection status and progresses async operations
    ## without blocking. Called every frame from the main loop.
    
    # -----------------------------------------------------------------------
    # Handle disconnected client that needs reconnection
    # -----------------------------------------------------------------------
    if sam.model.ui.nostrJoinRequested and
        sam.model.ui.nostrJoinRelayUrl.len > 0 and
        nostrClient != nil and
        not nostrClient.isConnected():
      logInfo("Nostr", "Client disconnected, resetting for reconnect")
      asyncCheck nostrClient.stop()
      nostrListenerStarted = false
      nostrSubscriptions.setLen(0)
      nostrDaemonPubkey = ""
      nostrClient = nil
      sam.model.ui.nostrEnabled = false
      sam.model.ui.nostrStatus = "idle"
      nostrConnectStartTime = 0.0
      needsRender = true

    # -----------------------------------------------------------------------
    # Start new connection when requested but no client exists
    # -----------------------------------------------------------------------
    if sam.model.ui.nostrJoinRequested and
        sam.model.ui.nostrJoinRelayUrl.len > 0 and
        nostrClient == nil:
      logInfo("Nostr", "Starting connection to: ", sam.model.ui.nostrJoinRelayUrl)
      sam.model.ui.nostrRelayUrl = sam.model.ui.nostrJoinRelayUrl

      let identity = sam.model.ui.entryModal.identity
      let relayList = @[sam.model.ui.nostrJoinRelayUrl]
      nostrClient = newPlayerNostrClient(
        relayList, activeGameId,
        identity.nsecHex, identity.npubHex,
        nostrDaemonPubkey, nostrHandlers)
      asyncCheck nostrClient.start()
      sam.model.ui.nostrStatus = "connecting"
      sam.model.ui.nostrEnabled = true
      nostrConnectStartTime = epochTime()
      needsRender = true
      # Don't block - connection will be checked on next iteration

    # -----------------------------------------------------------------------
    # Check if connecting client has connected (non-blocking)
    # -----------------------------------------------------------------------
    if sam.model.ui.nostrStatus == "connecting" and nostrClient != nil:
      if nostrClient.isConnected():
        logInfo("Nostr", "Connected successfully")
        sam.model.ui.nostrStatus = "connected"
        sam.model.ui.statusMessage = "Nostr connected"
        nostrConnectStartTime = 0.0
        
        if not nostrListenerStarted:
          asyncCheck nostrClient.listen()
          nostrListenerStarted = true
        
        # Subscribe to lobby games
        if "lobby:games" notin nostrSubscriptions:
          let lobbyFilter = newFilter().withKinds(@[EventKindGameDefinition])
          asyncCheck nostrClient.subscribe("lobby:games", @[lobbyFilter])
          nostrSubscriptions.add("lobby:games")
          logInfo("Nostr", "Subscribed to lobby:games")
        
        # Subscribe to join errors
        let joinPubkey = sam.model.ui.entryModal.identity.npubHex
        if joinPubkey.len > 0 and "lobby:join-errors" notin nostrSubscriptions:
          let joinErrorFilter = newFilter()
            .withKinds(@[EventKindJoinError])
            .withTag(TagP, @[joinPubkey])
          asyncCheck nostrClient.subscribe("lobby:join-errors", @[joinErrorFilter])
          nostrSubscriptions.add("lobby:join-errors")
          logInfo("Nostr", "Subscribed to lobby:join-errors")
        
        needsRender = true
        
      elif nostrConnectStartTime > 0 and
           epochTime() - nostrConnectStartTime > NostrConnectTimeoutSec:
        # Connection timeout
        logWarn("Nostr", "Connection timeout after ", $NostrConnectTimeoutSec, "s")
        sam.model.ui.nostrStatus = "error"
        sam.model.ui.nostrLastError = "Connection timeout"
        sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
        sam.model.ui.lobbyJoinError = "Failed to connect to relay"
        sam.model.ui.statusMessage = sam.model.ui.lobbyJoinError
        sam.model.ui.entryModal.setInviteError(sam.model.ui.lobbyJoinError)
        sam.model.ui.nostrJoinRequested = false
        sam.model.ui.nostrJoinSent = false
        sam.model.ui.nostrJoinInviteCode = ""
        sam.model.ui.nostrJoinRelayUrl = ""
        nostrClient = nil
        sam.model.ui.nostrEnabled = false
        nostrConnectStartTime = 0.0
        needsRender = true

    # -----------------------------------------------------------------------
    # Handle connected client state
    # -----------------------------------------------------------------------
    if sam.model.ui.nostrEnabled and nostrClient != nil and
        sam.model.ui.nostrStatus == "connected":
      
      # Check for relay URL change (requires restart)
      if sam.model.ui.entryModal.relayUrl() != sam.model.ui.nostrRelayUrl and
          sam.model.ui.entryModal.relayUrl().len > 0:
        sam.model.ui.nostrRelayUrl = sam.model.ui.entryModal.relayUrl()
        sam.model.ui.nostrStatus = "error"
        sam.model.ui.nostrLastError = "Relay URL changed - restart required"
        sam.model.ui.nostrEnabled = false
        nostrListenerStarted = false
        nostrSubscriptions.setLen(0)
        nostrDaemonPubkey = ""
        needsRender = true

      # Subscribe to active game if needed
      if activeGameId.len > 0 and
          ("game:" & activeGameId) notin nostrSubscriptions:
        asyncCheck nostrClient.subscribeGame(activeGameId)
        nostrSubscriptions.add("game:" & activeGameId)
        sam.model.ui.statusMessage = "Subscribed to game updates"
        needsRender = true

      # Check for disconnection
      if not nostrClient.isConnected():
        sam.model.ui.nostrStatus = "error"
        sam.model.ui.nostrLastError = "Relay disconnected"
        sam.model.ui.nostrEnabled = false
        nostrListenerStarted = false
        nostrSubscriptions.setLen(0)
        nostrDaemonPubkey = ""
        needsRender = true

    # -----------------------------------------------------------------------
    # Handle relay switch for join (non-blocking)
    # -----------------------------------------------------------------------
    if sam.model.ui.nostrJoinRequested and
        not sam.model.ui.nostrJoinSent and
        sam.model.ui.nostrJoinInviteCode.len > 0 and
        sam.model.ui.nostrStatus == "connected" and
        nostrClient != nil:
      
      let joinRelay = sam.model.ui.nostrJoinRelayUrl
      if joinRelay.len > 0 and joinRelay != sam.model.ui.nostrRelayUrl:
        # Need to switch relays - stop current client
        logInfo("Nostr", "Switching relay for join: ", 
          sam.model.ui.nostrRelayUrl, " -> ", joinRelay)
        sam.model.ui.statusMessage = "Connecting to " & joinRelay
        sam.model.ui.nostrRelayUrl = joinRelay
        
        asyncCheck nostrClient.stop()
        nostrListenerStarted = false
        nostrSubscriptions.setLen(0)
        nostrDaemonPubkey = ""
        
        # Create new client
        let identity = sam.model.ui.entryModal.identity
        let relayList = @[joinRelay]
        nostrClient = newPlayerNostrClient(
          relayList, activeGameId,
          identity.nsecHex, identity.npubHex,
          nostrDaemonPubkey, nostrHandlers)
        asyncCheck nostrClient.start()
        sam.model.ui.nostrStatus = "connecting"
        nostrConnectStartTime = epochTime()
        needsRender = true
        # Connection will be checked on next iteration

    # -----------------------------------------------------------------------
    # Publish slot claim (non-blocking)
    # -----------------------------------------------------------------------
    if sam.model.ui.nostrJoinRequested and
        not sam.model.ui.nostrJoinSent and
        sam.model.ui.nostrJoinInviteCode.len > 0 and
        sam.model.ui.nostrStatus == "connected" and
        nostrClient != nil and
        (sam.model.ui.nostrJoinRelayUrl.len == 0 or
         sam.model.ui.nostrJoinRelayUrl == sam.model.ui.nostrRelayUrl):
      
      if nostrPublishFuture == nil:
        # Start the publish operation
        let identity = sam.model.ui.entryModal.identity
        let privOpt = hexToBytes32Safe(identity.nsecHex)
        if privOpt.isSome:
          let gameId =
            if sam.model.ui.nostrJoinGameId.len > 0:
              sam.model.ui.nostrJoinGameId
            elif sam.model.ui.entryModal.selectedGame().isSome:
              sam.model.ui.entryModal.selectedGame().get().id
            else:
              ""
          let joinTarget = if gameId.len > 0: gameId else: "invite"
          var event = createSlotClaim(
            gameId = joinTarget,
            inviteCode = sam.model.ui.nostrJoinInviteCode,
            playerPubkey = identity.npubHex
          )
          signEvent(event, privOpt.get())
          
          logInfo("Nostr", "Publishing slot claim for game: ", joinTarget)
          nostrPublishFuture = nostrClient.publish(event)
          nostrPublishStartTime = epochTime()
          sam.model.ui.statusMessage = "Sending join request..."
          needsRender = true
        else:
          sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
          sam.model.ui.lobbyJoinError = "Invalid signing key"
          sam.model.ui.statusMessage = sam.model.ui.lobbyJoinError
          sam.model.ui.nostrJoinRequested = false
          sam.model.ui.nostrJoinSent = false
          sam.model.ui.nostrJoinInviteCode = ""
          sam.model.ui.nostrJoinRelayUrl = ""
          sam.model.ui.nostrJoinGameId = ""
          sam.model.ui.nostrJoinPubkey = ""
          needsRender = true

    # -----------------------------------------------------------------------
    # Check pending publish result (non-blocking)
    # -----------------------------------------------------------------------
    if nostrPublishFuture != nil:
      if nostrPublishFuture.finished:
        let published = nostrPublishFuture.read()
        nostrPublishFuture = nil
        nostrPublishStartTime = 0.0
        
        if published:
          logInfo("Nostr", "Slot claim published successfully")
          sam.model.ui.statusMessage = "Join request sent"
          sam.model.ui.nostrJoinSent = true
          sam.model.ui.nostrJoinRequested = false
          let gameId =
            if sam.model.ui.nostrJoinGameId.len > 0:
              sam.model.ui.nostrJoinGameId
            elif sam.model.ui.entryModal.selectedGame().isSome:
              sam.model.ui.entryModal.selectedGame().get().id
            else:
              "invite"
          sam.model.ui.nostrJoinGameId = gameId
          sam.model.ui.nostrJoinInviteCode = ""
          sam.model.ui.nostrJoinRelayUrl = ""
        else:
          logWarn("Nostr", "Failed to publish slot claim")
          sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
          sam.model.ui.lobbyJoinError = "Failed to send join request"
          sam.model.ui.statusMessage = "Join failed - check relay connection"
          sam.model.ui.nostrJoinRequested = false
          sam.model.ui.nostrJoinSent = false
        needsRender = true
        
      elif nostrPublishStartTime > 0 and
           epochTime() - nostrPublishStartTime > NostrPublishTimeoutSec:
        # Publish timeout
        logWarn("Nostr", "Publish timeout after ", $NostrPublishTimeoutSec, "s")
        nostrPublishFuture = nil
        nostrPublishStartTime = 0.0
        sam.model.ui.lobbyJoinStatus = JoinStatus.Failed
        sam.model.ui.lobbyJoinError = "Join request timed out"
        sam.model.ui.statusMessage = sam.model.ui.lobbyJoinError
        sam.model.ui.nostrJoinRequested = false
        sam.model.ui.nostrJoinSent = false
        needsRender = true

  # =========================================================================
  # Main Loop (Input-first with frame-based rendering)
  # =========================================================================
  #
  # This loop is structured to ALWAYS wait for input, preventing busy-loops:
  #   1. Wait for input OR timeout (blocking wait - this is where we spend time)
  #   2. Process any input received
  #   3. Process async events (Nostr)
  #   4. Handle game state changes
  #   5. Render if needed (at frame rate)
  #
  # Key principle: The loop blocks waiting for input, not busy-polling.
  # This ensures responsive input handling and low CPU usage.
  #
  
  logInfo("TUI", "Entering main loop")

  while sam.state.ui.running:
    # -------------------------------------------------------------------------
    # Phase 1: Wait for input (blocking with timeout)
    # -------------------------------------------------------------------------
    # This is where we spend most of our time. We wait for either:
    # - Input from the user (returns immediately when key pressed)
    # - Timeout (returns after TargetFrameTimeMs to allow async processing)
    #
    let inputByte = tty.readByteTimeout(TargetFrameTimeMs)
    
    # -------------------------------------------------------------------------
    # Phase 2: Process input if available
    # -------------------------------------------------------------------------
    if inputByte >= 0:
      var events: seq[Event] = @[]
      
      if inputByte == 0x1B:
        # ESC byte - check for escape sequence
        let nextByte = tty.readByteTimeout(5)  # Short wait for sequence
        if nextByte == -2:
          # Standalone ESC
          events.add(parser.feedByte(0x1B))
          let pending = parser.flushPending()
          if pending.len > 0:
            events.add(pending)
        elif nextByte >= 0:
          # Escape sequence - feed both bytes
          events.add(parser.feedByte(0x1B))
          events.add(parser.feedByte(nextByte.uint8))
          # Read rest of escape sequence (non-blocking)
          var followup = tty.readByteTimeout(0)
          while followup >= 0:
            events.add(parser.feedByte(followup.uint8))
            followup = tty.readByteTimeout(0)
      else:
        events.add(parser.feedByte(inputByte.uint8))
        # Read all remaining available bytes (non-blocking batch)
        var followup = tty.readByteTimeout(0)
        var followupCount = 0
        while followup >= 0 and followupCount < 256:
          inc followupCount
          events.add(parser.feedByte(followup.uint8))
          followup = tty.readByteTimeout(0)

      # Process all events
      for event in events:
        if event.kind == EventKind.Key:
          let proposalOpt = mapKeyEvent(event.keyEvent, sam.model)
          if proposalOpt.isSome:
            sam.present(proposalOpt.get)
            needsRender = true
            # Sync build modal data if modal is active
            if sam.model.ui.buildModal.active:
              syncBuildModalData(sam.model, playerState)
    
    elif inputByte == -2:
      # Timeout - flush any pending parser state
      let pending = parser.flushPending()
      for event in pending:
        if event.kind == EventKind.Key:
          let proposalOpt = mapKeyEvent(event.keyEvent, sam.model)
          if proposalOpt.isSome:
            sam.present(proposalOpt.get)
            needsRender = true

    # -------------------------------------------------------------------------
    # Phase 3: Drain async proposal queue (from Nostr handlers)
    # -------------------------------------------------------------------------
    if proposalQueue.len > 0:
      drainProposalQueue()
      needsRender = true

    # -------------------------------------------------------------------------
    # Phase 4: Check for terminal resize
    # -------------------------------------------------------------------------
    if checkResize():
      (termWidth, termHeight) = tty.windowSize()
      buf.resize(termWidth, termHeight)
      buf.invalidate()
      sam.present(actionResize(termWidth, termHeight))
      needsRender = true

    # -------------------------------------------------------------------------
    # Phase 5: Process async operations (Nostr WebSocket events)
    # -------------------------------------------------------------------------
    if hasPendingOperations():
      poll(0)  # Non-blocking poll for async events

    processNostr()
    
    # Sync nostr status to entry modal
    sam.model.ui.entryModal.nostrStatus = sam.model.ui.nostrStatus

    # Poll for join response when waiting (don't set needsRender unconditionally)
    if sam.model.ui.appPhase == AppPhase.Lobby and
        sam.model.ui.lobbyJoinStatus == JoinStatus.WaitingResponse:
      sam.present(actionLobbyJoinPoll())

    # -------------------------------------------------------------------------
    # Phase 6: Handle game loading and state changes
    # -------------------------------------------------------------------------
    if sam.model.ui.loadGameRequested:
      let gameId = sam.model.ui.loadGameId
      sam.model.view.playerStateLoaded = false
      authoritativeConfigLoaded = false
      authoritativeConfigHash = ""
      authoritativeConfigSchema = 0
      authoritativeConfigError = ""
      lastDraftFingerprint = ""

      # Check for valid houseId
      if sam.model.ui.loadHouseId == 0:
          setConfigBlockingError(
            sam.model,
            "Cannot load: no house assigned yet"
          )
          sam.model.ui.loadGameRequested = false
      else:
        let houseId = HouseId(sam.model.ui.loadHouseId.uint32)
        let cachedConfigOpt = tuiCache.loadLatestConfigSnapshot(gameId)
        var invalidCachedConfig = false
        if cachedConfigOpt.isSome:
          if not applyAuthoritativeConfig(cachedConfigOpt.get().snapshot):
            invalidCachedConfig = true

        # Try to load from TUI cache first (for Nostr games)
        let cachedStateOpt = tuiCache.loadLatestPlayerState(gameId,
          int(houseId))
        if cachedStateOpt.isSome and authoritativeConfigLoaded:
          playerState = cachedStateOpt.get()
          viewingHouse = houseId
          activeGameId = gameId
          sam.model.view.playerStateLoaded = true
          sam.model.ui.appPhase = AppPhase.InGame
          sam.model.view.viewingHouse = int(houseId)
          sam.model.view.turn = playerState.turn
          sam.model.ui.mode = ViewMode.Overview
          # Sync PlayerState to model (for Nostr games)
          syncPlayerStateToModel(sam.model, playerState)
          syncCachedIntelNotes(sam.model)
          syncCachedMessages(sam.model)
          syncBuildModalData(sam.model, playerState)
          sam.model.resetBreadcrumbs(sam.model.ui.mode)
          if sam.model.view.homeworld.isSome:
            sam.model.ui.mapState.cursor = sam.model.view.homeworld.get
          let cachedGame = tuiCache.getGame(gameId)
          let gameName = if cachedGame.isSome: cachedGame.get().name
                         else: gameId
          sam.model.ui.statusMessage = "Loaded game " & gameName
          let draftOpt = tuiCache.loadOrderDraft(
            activeGameId,
            int(viewingHouse)
          )
          if draftOpt.isSome:
            let draft = draftOpt.get()
            if draft.turn != playerState.turn:
              tuiCache.clearOrderDraft(activeGameId, int(viewingHouse))
              sam.model.ui.statusMessage =
                "Loaded game " & gameName &
                " (discarded stale draft: turn changed)"
            elif draft.configHash != authoritativeConfigHash:
              tuiCache.clearOrderDraft(activeGameId, int(viewingHouse))
              sam.model.ui.statusMessage =
                "Loaded game " & gameName &
                " (discarded stale draft: rules changed)"
            else:
              applyOrderDraft(sam.model, draft.packet)
              syncBuildModalData(sam.model, playerState)
              let cmdCount = sam.model.stagedCommandCount()
              sam.model.ui.statusMessage =
                "Loaded game " & gameName &
                " (restored draft: " & $cmdCount & " staged)"
              lastDraftFingerprint = packetFingerprint(draft.packet)
          syncCachedIntelNotes(sam.model)
          syncCachedMessages(sam.model)
        elif cachedStateOpt.isSome and not authoritativeConfigLoaded:
          # Cached state exists but config snapshot is missing/invalid.
          activeGameId = gameId
          viewingHouse = houseId
          sam.model.view.viewingHouse = int(houseId)
          if invalidCachedConfig and authoritativeConfigError.len > 0:
            setConfigBlockingError(
              sam.model,
              "Cached config invalid (" & authoritativeConfigError &
                "); waiting for server snapshot..."
            )
          else:
            setConfigBlockingError(
              sam.model,
              "Waiting for authoritative config snapshot..."
            )
        else:
          # No cached state - set up for Nostr subscription
          # The game will load when full state arrives via onFullState handler
          activeGameId = gameId
          viewingHouse = houseId
          sam.model.view.viewingHouse = int(houseId)
          let cachedGame = tuiCache.getGame(gameId)
          let gameName = if cachedGame.isSome: cachedGame.get().name
                         else: gameId
          sam.model.view.houseName = gameName
          setConfigBlockingError(sam.model, "Waiting for game state...")
          # Don't switch to InGame yet - wait for state via Nostr
        sam.model.ui.loadGameRequested = false

      needsRender = true  # Game state changed

    # Handle map export requests (disabled - requires full GameState)
    if sam.model.ui.exportMapRequested:
      sam.model.ui.statusMessage = "Map export requires local game (not available in Nostr mode)"
      sam.model.ui.exportMapRequested = false
      sam.model.ui.openMapRequested = false
      needsRender = true

    # Persist intel note edits (local TUI cache only)
    if sam.model.ui.intelNoteSaveRequested:
      if activeGameId.len > 0 and
          sam.model.ui.intelNoteSaveSystemId > 0:
        tuiCache.saveIntelNote(
          activeGameId,
          int(viewingHouse),
          sam.model.ui.intelNoteSaveSystemId,
          sam.model.ui.intelNoteSaveText,
        )
        let notes = tuiCache.loadIntelNotes(activeGameId, int(viewingHouse))
        sam.model.applyIntelNotes(notes)
      else:
        sam.model.ui.statusMessage = "Intel note not saved (game not loaded)"
      sam.model.ui.intelNoteSaveRequested = false
      needsRender = true

    # Handle turn submission (expert :submit)
    if sam.model.ui.turnSubmissionPending:
      let buildErrors = validateStagedBuildLimits(sam.model)
      let fleetErrors = validateStagedFleetLimits(sam.model)
      if buildErrors.len > 0 or fleetErrors.len > 0:
        if buildErrors.len > 0:
          sam.model.ui.statusMessage = "Submit blocked: " & buildErrors[0]
        else:
          sam.model.ui.statusMessage = "Submit blocked: " & fleetErrors[0]
      else:
        # Build command packet from staged commands
        let packet = sam.model.buildCommandPacket(
          playerState.turn,
          viewingHouse
        )

        # Send via Nostr (only supported transport)
        if sam.model.ui.nostrEnabled and nostrClient != nil and
            nostrClient.isConnected():
          let msgpack = serializeCommandPacket(packet)
          asyncCheck nostrClient.submitCommands(msgpack, sam.model.view.turn)
          sam.model.ui.statusMessage = "Turn submitted"
          logInfo("TUI Player SAM", "Turn submitted via Nostr")
          # Clear staged commands on successful submission
          sam.model.ui.stagedFleetCommands.clear()
          sam.model.ui.stagedZeroTurnCommands.setLen(0)
          sam.model.ui.stagedBuildCommands.setLen(0)
          sam.model.ui.stagedRepairCommands.setLen(0)
          sam.model.ui.stagedScrapCommands.setLen(0)
          sam.model.ui.stagedColonyManagement.setLen(0)
          sam.model.ui.stagedEspionageActions.setLen(0)
          sam.model.ui.stagedEbpInvestment = 0
          sam.model.ui.stagedCipInvestment = 0
          if activeGameId.len > 0:
            tuiCache.clearOrderDraft(activeGameId, int(viewingHouse))
          let postSubmit = sam.model.buildCommandPacket(
            playerState.turn,
            viewingHouse
          )
          lastDraftFingerprint = packetFingerprint(postSubmit)
        else:
          sam.model.ui.statusMessage =
            "Cannot submit: not connected to relay"

      sam.model.ui.turnSubmissionPending = false
      needsRender = true

    # Handle message send requests
    if sam.model.ui.mode == ViewMode.Messages:
      if sam.model.ui.messageComposeActive:
        if sam.model.ui.statusMessage == "Sending message..." and
            activeGameId.len > 0:
          if nostrClient != nil and nostrClient.isConnected():
            let idx = clamp(sam.model.ui.messageHouseIdx, 0,
              max(0, sam.model.view.messageHouses.len - 1))
            let targetId = if sam.model.view.messageHouses.len > 0:
              sam.model.view.messageHouses[idx].id
            else:
              0'i32
            let msgText = sam.model.ui.messageComposeInput.value().strip()
            if msgText.len == 0:
              sam.model.ui.statusMessage = "Message is empty"
              sam.model.ui.messageComposeActive = false
              needsRender = true
            else:
              let msg = GameMessage(
                fromHouse: int32(viewingHouse),
                toHouse: targetId,
                text: msgText,
                timestamp: getTime().toUnix(),
                gameId: activeGameId
              )
              asyncCheck nostrClient.sendMessage(msg)
              tuiCache.saveMessage(activeGameId, msg, isRead = true)
              syncCachedMessages(sam.model)
              sam.model.ui.messageComposeInput.clear()
              sam.model.ui.messageComposeActive = false
              sam.model.ui.statusMessage = "Message sent"
              needsRender = true
          else:
            sam.model.ui.statusMessage = "Cannot send: not connected"
            needsRender = true
      if sam.model.ui.statusMessage == "Marking thread read..." and
          activeGameId.len > 0:
        let idx = clamp(sam.model.ui.messageHouseIdx, 0,
          max(0, sam.model.view.messageHouses.len - 1))
        let targetId = if sam.model.view.messageHouses.len > 0:
          sam.model.view.messageHouses[idx].id
        else:
          0'i32
        tuiCache.markMessagesRead(activeGameId, int(viewingHouse),
          int(targetId))
        syncCachedMessages(sam.model)
        sam.model.ui.statusMessage = "Thread marked read"
        needsRender = true

    # -------------------------------------------------------------------------
    # Phase 7: Game list maintenance
    # -------------------------------------------------------------------------
    # Filter out placeholder games, maintain selection consistency
    let selectedId =
      if sam.model.ui.entryModal.selectedIdx >= 0 and
          sam.model.ui.entryModal.selectedIdx <
          sam.model.ui.entryModal.activeGames.len:
        sam.model.ui.entryModal.activeGames[
          sam.model.ui.entryModal.selectedIdx
        ].id
      else:
        ""
    var joinedGames: seq[EntryActiveGameInfo] = @[]
    for game in sam.model.ui.entryModal.activeGames:
      if game.houseId > 0:
        joinedGames.add(game)
    if joinedGames.len != sam.model.ui.entryModal.activeGames.len:
      sam.model.ui.entryModal.activeGames = joinedGames
      if joinedGames.len == 0:
        sam.model.ui.entryModal.selectedIdx = 0
      else:
        var newIdx = 0
        if selectedId.len > 0:
          for idx, game in joinedGames:
            if game.id == selectedId:
              newIdx = idx
              break
        sam.model.ui.entryModal.selectedIdx = newIdx
      needsRender = true

    if sam.model.ui.entryModal.activeGames.len > 0 and
        sam.model.ui.entryModal.selectedIdx >=
        sam.model.ui.entryModal.activeGames.len:
      sam.model.ui.entryModal.selectedIdx =
        sam.model.ui.entryModal.activeGames.len - 1
      needsRender = true

    # -------------------------------------------------------------------------
    # Phase 8: Persist staged order draft
    # -------------------------------------------------------------------------
    if activeGameId.len > 0 and sam.model.view.playerStateLoaded and
        authoritativeConfigLoaded and int(viewingHouse) > 0:
      let draftPacket = sam.model.buildCommandPacket(
        playerState.turn,
        viewingHouse
      )
      let fingerprint = packetFingerprint(draftPacket)
      if packetHasDraftData(draftPacket):
        if fingerprint != lastDraftFingerprint:
          tuiCache.saveOrderDraft(
            activeGameId,
            int(viewingHouse),
            playerState.turn,
            authoritativeConfigHash,
            normalizeDraftPacket(draftPacket)
          )
          lastDraftFingerprint = fingerprint
      elif lastDraftFingerprint.len > 0:
        tuiCache.clearOrderDraft(activeGameId, int(viewingHouse))
        lastDraftFingerprint = ""

    # -------------------------------------------------------------------------
    # Phase 9: Frame-based rendering
    # -------------------------------------------------------------------------
    # Render if needed. Since we wait for input at the start of each iteration,
    # we render at most once per TargetFrameTimeMs.
    if needsRender:
      doRender()
      lastRenderTime = epochTime()
      needsRender = false

  # =========================================================================
  # Cleanup
  # =========================================================================

  stdout.write(showCursor())
  stdout.write(disableKittyKeys())
  stdout.write(exitAltScreen())
  stdout.flushFile()
  discard tty.stop()
  tty.close()

  logInfo("TUI Player SAM", "TUI Player exited.")

proc parseCommandLine*(): tuple[spawnWindow: bool, showHelp: bool,
    gameId: string, cleanCache: string] =
  ## Parse command line arguments
  result = (spawnWindow: true, showHelp: false, gameId: "",
    cleanCache: "")

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      case p.key
      of "no-spawn-window":
        result.spawnWindow = false
      of "spawn-window":
        result.spawnWindow =
          if p.val == "":
            true
          else:
            parseBool(p.val)
      of "game":
        result.gameId = p.val
      of "clean-cache":
        result.cleanCache = p.val
      of "help", "h":
        result.showHelp = true
      else:
        logWarn("TUI Player SAM", "Unknown option: --" & p.key)
        result.showHelp = true
    of cmdArgument:
      logWarn("TUI Player SAM", "Unexpected argument: " & p.key)
      result.showHelp = true

proc showHelp*() =
  logInfo("TUI Player SAM", "Showing help")
  stdout.write("""
EC4X TUI Player

Usage: ec4x-play [options]

Options:
  --spawn-window        Launch in new terminal window (default: true)
  --no-spawn-window     Run in current terminal
  --game <id>           Enter a game directly
  --clean-cache[=mode]  Clear cache (all|games|game:<id>)
  --help, -h            Show this help message

  Controls:
    F1-F8    Switch views
    F12      Quit
    Ctrl-C   Quit
    Ctrl-Q   Quit
    Esc      Back
    :        Expert mode (vim-style commands)

See docs/tools/ec4x-play.md for full documentation.
""")
