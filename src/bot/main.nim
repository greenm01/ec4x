## EC4X LLM bot entrypoint (MVP scaffold).

import std/[asyncdispatch, monotimes, os, strutils, times]
import std/logging

import ./types
import ./llm_client
import ./runner
import ./session
import ./trace_log
import ./transport

import ../engine/types/command
import ../player/nostr/client

const
  connectTimeoutMs = 5000
  loopPollMs = 100
  maxReconnectDelaySec = 30

var shutdownRequested {.global.}: bool = false

proc requestShutdown() {.noconv.} =
  shutdownRequested = true

proc splitRelays(value: string): seq[string] =
  result = @[]
  for item in value.split(','):
    let relay = item.strip()
    if relay.len > 0:
      result.add(relay)

proc loadBotConfig*(): BotConfig =
  result = BotConfig(
    relays: splitRelays(getEnv("BOT_RELAYS", "")),
    gameId: getEnv("BOT_GAME_ID", ""),
    daemonPubkey: getEnv("BOT_DAEMON_PUBHEX", ""),
    playerPrivHex: getEnv("BOT_PLAYER_PRIV_HEX", ""),
    playerPubHex: getEnv("BOT_PLAYER_PUB_HEX", ""),
    model: getEnv("BOT_MODEL", ""),
    baseUrl: getEnv("BOT_BASE_URL", ""),
    apiKey: getEnv("BOT_API_KEY", ""),
    maxRetries: parseInt(getEnv("BOT_MAX_RETRIES", "2")),
    requestTimeoutSec: parseInt(getEnv("BOT_REQUEST_TIMEOUT_SEC", "45")),
    logDir: getEnv("BOT_LOG_DIR", "logs/bot")
  )

proc validateConfig(cfg: BotConfig): bool =
  if cfg.relays.len == 0:
    warn "BOT_RELAYS is empty"
    return false
  if cfg.gameId.len == 0:
    warn "BOT_GAME_ID is empty"
    return false
  if cfg.playerPrivHex.len == 0 or cfg.playerPubHex.len == 0:
    warn "Player key env vars are missing"
    return false
  if cfg.daemonPubkey.len == 0:
    warn "BOT_DAEMON_PUBHEX is empty"
    return false
  if cfg.model.len == 0:
    warn "BOT_MODEL is empty"
    return false
  if cfg.apiKey.len == 0:
    warn "BOT_API_KEY is empty"
    return false
  true

proc waitForConnection(client: PlayerNostrClient, timeoutMs: int): bool =
  let startedAt = getMonoTime()
  while (getMonoTime() - startedAt).inMilliseconds < timeoutMs:
    try:
      poll(loopPollMs)
    except ValueError:
      sleep(loopPollMs)
    if client.isConnected():
      return true
  false

proc reconnectDelaySec*(attempt: int): int =
  let bounded = max(0, attempt)
  let exp = min(5, bounded)
  let base = 1 shl exp
  let jitter = bounded mod 3
  min(maxReconnectDelaySec, base + jitter)

proc decisionRetryDelaySec*(retry: RetryResult, failures: int): int =
  let boundedFailures = max(0, failures)
  let base =
    case classifyRetryResult(retry)
    of "transport":
      2
    of "llm_request":
      4
    of "validation":
      6
    else:
      5
  min(45, base + min(20, boundedFailures * 2))

proc makeHandlers(session: ptr BotSession): PlayerNostrHandlers =
  var handlers = PlayerNostrHandlers()
  handlers.onFullState = proc(event: NostrEvent, payload: string) =
    if session[].ingestFullStatePayload(payload, event.id):
      info "Bot ingested full state turn ", session[].runtime.playerState.turn

  handlers.onDelta = proc(event: NostrEvent, payload: string) =
    if session[].ingestDeltaPayload(payload, event.id):
      info "Bot ingested delta turn ", session[].runtime.playerState.turn

  handlers.onJoinError = proc(message: string) =
    warn "Bot join error: ", message

  handlers.onError = proc(message: string) =
    warn "Bot Nostr error: ", message

  handlers

proc stopClient(client: PlayerNostrClient) =
  if client.isNil:
    return
  try:
    waitFor(client.stop())
  except CatchableError as e:
    warn "Bot client stop failed: ", e.msg

proc connectClient(
    cfg: BotConfig,
    session: ptr BotSession
): tuple[ok: bool, client: PlayerNostrClient, message: string] =
  let handlers = makeHandlers(session)
  let client = newBotNostrClient(cfg, handlers)
  asyncCheck client.start()

  if not waitForConnection(client, connectTimeoutMs):
    return (false, nil, "connection timeout")

  asyncCheck client.listen()
  asyncCheck client.subscribeGame(cfg.gameId)
  info "Bot connected for game ", cfg.gameId, " using model ", cfg.model
  (true, client, "")

proc runBot*() =
  let cfg = loadBotConfig()
  if not validateConfig(cfg):
    quit(1)

  setControlCHook(requestShutdown)
  persistSessionTrace(cfg.logDir, cfg)

  var botSession = initBotSession(cfg)
  var client: PlayerNostrClient = nil
  var reconnectAttempt = 0
  var nextReconnectAt = getMonoTime()
  var failureStreak = 0

  let generator: DraftGenerator = proc(prompt: string): BotLlmResult =
    generateDraftJson(cfg, prompt)

  let submitter: PacketSubmitter = proc(
      packet: CommandPacket
  ): tuple[ok: bool, message: string] =
    if client.isNil:
      return (false, "Nostr client unavailable")
    if not client.isConnected():
      return (false, "Nostr client disconnected")

    try:
      let submitted = waitFor(client.submitCompiledPacket(packet))
      if submitted:
        return (true, "")
      (false, "Nostr publish returned false")
    except CatchableError as e:
      (false, "Nostr publish failed: " & e.msg)

  var nextDecisionAt = getMonoTime()
  while not shutdownRequested:
    try:
      poll(loopPollMs)
    except ValueError:
      sleep(loopPollMs)

    if client.isNil or not client.isConnected():
      if getMonoTime() < nextReconnectAt:
        continue

      stopClient(client)
      client = nil

      reconnectAttempt.inc
      info "Bot connecting (attempt ", reconnectAttempt, ")"
      let connectResult = connectClient(cfg, addr botSession)
      if connectResult.ok:
        client = connectResult.client
        reconnectAttempt = 0
        nextReconnectAt = getMonoTime()
      else:
        let delaySec = reconnectDelaySec(reconnectAttempt)
        warn "Bot connection failed: ", connectResult.message,
          "; retry in ", delaySec, "s"
        nextReconnectAt = getMonoTime() +
          initDuration(seconds = delaySec)
      continue

    if not botSession.readyForDecision():
      continue
    if getMonoTime() < nextDecisionAt:
      continue

    let turn = int(botSession.runtime.playerState.turn)
    info "Bot deciding turn ", turn
    let result = botSession.decideAndSubmitPacket(generator, submitter)
    if result.ok:
      failureStreak = 0
      info "Bot submitted turn ", turn,
        " in ", result.attempts, " attempt(s)"
      nextDecisionAt = getMonoTime()
    else:
      failureStreak.inc
      let delaySec = decisionRetryDelaySec(result, failureStreak)
      warn "Bot failed turn ", turn, ": ", result.errors.join("; ")
      nextDecisionAt = getMonoTime() +
        initDuration(seconds = delaySec)

  stopClient(client)
  info "Bot shutdown complete"

when isMainModule:
  runBot()
