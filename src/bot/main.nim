## EC4X LLM bot entrypoint (MVP scaffold).

import std/[os, strutils]
import std/logging

import ./types

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
  true

proc runBot*() =
  let cfg = loadBotConfig()
  if not validateConfig(cfg):
    quit(1)
  info "Bot scaffold ready for game ", cfg.gameId,
    " with model ", cfg.model

when isMainModule:
  runBot()
