import std/[asyncdispatch, options, os, strutils]

import ../src/daemon/transport/nostr/[client, events, crypto]
import ../src/daemon/persistence/reader
import ../src/common/invite_code
import ../src/player/state/wallet

proc usage() =
  stderr.writeLine(
    "Usage:"
  )
  stderr.writeLine(
    "  nim r tools/claim_invite.nim " &
    "<relay> <invite_code> <player_priv_hex> <player_pub_hex> [game_id]"
  )
  stderr.writeLine(
    "  nim r tools/claim_invite.nim " &
    "<relay> <invite_code> [--password PW] [--game GAME] [--ensure-wallet]"
  )
  quit(1)

proc loadWalletIdentity(
    passwordOpt: Option[string],
    ensureWalletFlag: bool
): tuple[privHex: string, pubHex: string] =
  let walletResult =
    if ensureWalletFlag:
      ensureWallet(passwordOpt)
    else:
      checkWallet(passwordOpt)

  case walletResult.status
  of WalletLoadStatus.Success:
    let identity = walletResult.wallet.get().activeIdentity()
    (identity.nsecHex, identity.npubHex)
  of WalletLoadStatus.NotFound:
    stderr.writeLine("Wallet not found. Use --ensure-wallet to create one.")
    quit(1)
  of WalletLoadStatus.NeedsPassword:
    stderr.writeLine("Wallet is encrypted. Pass --password.")
    quit(1)
  of WalletLoadStatus.WrongPassword:
    stderr.writeLine("Wallet password is incorrect.")
    quit(1)
  of WalletLoadStatus.Error:
    stderr.writeLine("Failed to load wallet.")
    quit(1)

proc main() {.async.} =
  let args = commandLineParams()
  if args.len < 2:
    usage()

  let relay = args[0]
  let inviteCode = normalizeInviteCode(args[1])

  var playerPrivHex = ""
  var playerPubHex = ""
  var gameId = "invite"
  var passwordOpt = none(string)
  var ensureWalletFlag = false

  if args.len >= 4 and not args[2].startsWith("--"):
    playerPrivHex = args[2]
    playerPubHex = args[3]
    if args.len >= 5 and args[4].len > 0:
      gameId = args[4]
  else:
    var i = 2
    while i < args.len:
      case args[i]
      of "--password":
        if i + 1 >= args.len:
          usage()
        passwordOpt = some(args[i + 1])
        i += 2
      of "--game":
        if i + 1 >= args.len:
          usage()
        gameId = args[i + 1]
        i += 2
      of "--ensure-wallet":
        ensureWalletFlag = true
        i += 1
      else:
        stderr.writeLine("Unknown argument: " & args[i])
        usage()

    let identity = loadWalletIdentity(passwordOpt, ensureWalletFlag)
    playerPrivHex = identity.privHex
    playerPubHex = identity.pubHex

  if gameId != "invite":
    let gameOpt = findGameByToken(gameId)
    if gameOpt.isNone:
      stderr.writeLine("Game not found: " & gameId)
      quit(1)
    gameId = gameOpt.get().gameId

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
