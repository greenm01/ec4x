## Bot transport helpers built on player-side Nostr client.

import std/asyncdispatch

import ./types
import ../player/nostr/client
import ../player/state/msgpack_serializer
import ../engine/types/command

proc newBotNostrClient*(
    cfg: BotConfig,
    handlers: PlayerNostrHandlers
): PlayerNostrClient =
  newPlayerNostrClient(
    relays = cfg.relays,
    gameId = cfg.gameId,
    playerPrivHex = cfg.playerPrivHex,
    playerPubHex = cfg.playerPubHex,
    daemonPubkey = cfg.daemonPubkey,
    handlers = handlers
  )

proc submitCompiledPacket*(
    client: PlayerNostrClient,
    packet: CommandPacket
): Future[bool] {.async.} =
  let payload = serializeCommandPacket(packet)
  await client.submitCommands(payload, int(packet.turn))
