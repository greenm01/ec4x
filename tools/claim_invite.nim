import std/[asyncdispatch, os, strutils]

import ../src/daemon/transport/nostr/[client, events, crypto]

proc main() {.async.} =
  if paramCount() < 4:
    stderr.writeLine(
      "Usage: nim r tools/claim_invite.nim " &
      "<relay> <invite_code> <player_priv_hex> <player_pub_hex> [game_id]"
    )
    quit(1)

  let relay = paramStr(1)
  let inviteCode = paramStr(2)
  let playerPrivHex = paramStr(3)
  let playerPubHex = paramStr(4)
  let gameId =
    if paramCount() >= 5 and paramStr(5).len > 0:
      paramStr(5)
    else:
      "invite"

  let priv = hexToBytes32(playerPrivHex)

  let nostrClient = newNostrClient(@[relay])
  await nostrClient.connect()
  if not nostrClient.isConnected():
    stderr.writeLine("Failed to connect relay: " & relay)
    quit(1)

  var event = createSlotClaim(
    gameId = gameId,
    inviteCode = inviteCode,
    playerPubkey = playerPubHex
  )
  signEvent(event, priv)

  let ok = await nostrClient.publish(event)
  await nostrClient.disconnect()

  if ok:
    stdout.writeLine("claimed " & inviteCode & " for " & playerPubHex)
  else:
    stderr.writeLine("failed to publish claim for " & inviteCode)
    quit(1)

waitFor main()
