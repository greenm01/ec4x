## EC4X LLM bot entrypoint (MVP scaffold).

import std/[asyncdispatch, monotimes, os, strutils, times]
import std/logging

import ./types
import ./llm_client
import ./runner
import ./session
import ./transport

import ../engine/types/command
import ../player/nostr/client

const
  connectTimeoutMs = 5000
  loopPollMs = 100
  decisionRetryDelaySec = 5

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
    poll(loopPollMs)
    if client.isConnected():
      return true
  false

proc runBot*() =
  let cfg = loadBotConfig()
  if not validateConfig(cfg):
    quit(1)

  var botSession = initBotSession(cfg)

  var handlers = PlayerNostrHandlers()
  handlers.onFullState = proc(event: NostrEvent, payload: string) =
    if botSession.ingestFullStatePayload(payload, event.id):
      info "Bot ingested full state turn ", botSession.runtime.playerState.turn

  handlers.onDelta = proc(event: NostrEvent, payload: string) =
    if botSession.ingestDeltaPayload(payload, event.id):
      info "Bot ingested delta turn ", botSession.runtime.playerState.turn

  handlers.onJoinError = proc(message: string) =
    warn "Bot join error: ", message

  handlers.onError = proc(message: string) =
    warn "Bot Nostr error: ", message

  let client = newBotNostrClient(cfg, handlers)
  asyncCheck client.start()

  if not waitForConnection(client, connectTimeoutMs):
    error "Bot failed to connect within timeout"
    quit(1)

  asyncCheck client.listen()
  asyncCheck client.subscribeGame(cfg.gameId)
  info "Bot connected for game ", cfg.gameId, " using model ", cfg.model

  let generator: DraftGenerator = proc(prompt: string): BotLlmResult =
    generateDraftJson(cfg, prompt)

  let submitter: PacketSubmitter = proc(
      packet: CommandPacket
  ): tuple[ok: bool, message: string] =
    try:
      let submitted = waitFor(client.submitCompiledPacket(packet))
      if submitted:
        return (true, "")
      (false, "Nostr publish returned false")
    except CatchableError as e:
      (false, "Nostr publish failed: " & e.msg)

  var nextDecisionAt = getMonoTime()
  while true:
    poll(loopPollMs)
    if not client.isConnected():
      warn "Bot relay connection dropped; waiting for reconnect"
      sleep(1000)
      continue

    if not botSession.readyForDecision():
      continue
    if getMonoTime() < nextDecisionAt:
      continue

    let turn = int(botSession.runtime.playerState.turn)
    info "Bot deciding turn ", turn
    let result = botSession.decideAndSubmitPacket(generator, submitter)
    if result.ok:
      info "Bot submitted turn ", turn,
        " in ", result.attempts, " attempt(s)"
      nextDecisionAt = getMonoTime()
    else:
      warn "Bot failed turn ", turn, ": ", result.errors.join("; ")
      nextDecisionAt = getMonoTime() +
        initDuration(seconds = decisionRetryDelaySec)

when isMainModule:
  runBot()
