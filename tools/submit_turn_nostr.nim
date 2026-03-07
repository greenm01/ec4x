import std/[asyncdispatch, options, os, strutils]

import ../src/daemon/identity
import ../src/daemon/parser/[kdl_commands, msgpack_commands]
import ../src/daemon/persistence/reader
import ../src/engine/types/core
import ../src/player/nostr/client as player_nostr
import ../src/player/state/wallet

proc usage() =
  stdout.writeLine("Usage:")
  stdout.writeLine(
    "  nim r tools/submit_turn_nostr.nim " &
    "<relay> <game> <orders.kdl> [--house N] [--password PW]"
  )
  quit(1)

proc loadWalletIdentity(
    passwordOpt: Option[string]
): tuple[privHex: string, pubHex: string] =
  let walletResult = checkWallet(passwordOpt)
  case walletResult.status
  of WalletLoadStatus.Success:
    let identity = walletResult.wallet.get().activeIdentity()
    (identity.nsecHex, identity.npubHex)
  of WalletLoadStatus.NotFound:
    stderr.writeLine("Wallet not found. Initialize one first.")
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

proc loadDaemonIdentityFromDefaultPath(): string =
  let originalXdg = getEnv("XDG_DATA_HOME")
  putEnv("XDG_DATA_HOME", getHomeDir() / ".local" / "share")
  defer:
    if originalXdg.len == 0:
      putEnv("XDG_DATA_HOME", "")
    else:
      putEnv("XDG_DATA_HOME", originalXdg)

  let daemonOpt = loadIdentity()
  if daemonOpt.isNone:
    stderr.writeLine(
      "Error: Daemon identity not found in ~/.local/share/ec4x."
    )
    quit(1)
  daemonOpt.get().publicKeyHex

proc main() {.async.} =
  let args = commandLineParams()
  if args.len < 3:
    usage()

  let relay = args[0]
  let gameToken = args[1]
  let ordersPath = args[2]

  var houseOverride = -1
  var passwordOpt = none(string)
  var i = 3
  while i < args.len:
    case args[i]
    of "--house":
      if i + 1 >= args.len:
        usage()
      try:
        houseOverride = parseInt(args[i + 1])
      except ValueError:
        stderr.writeLine("Error: --house requires a numeric argument")
        quit(1)
      i += 2
    of "--password":
      if i + 1 >= args.len:
        usage()
      passwordOpt = some(args[i + 1])
      i += 2
    else:
      stderr.writeLine("Error: Unknown argument: " & args[i])
      usage()

  if not fileExists(ordersPath):
    stderr.writeLine("Error: Orders file not found: " & ordersPath)
    quit(1)

  let gameOpt = findGameByToken(gameToken)
  if gameOpt.isNone:
    stderr.writeLine("Error: Game not found: " & gameToken)
    quit(1)
  let game = gameOpt.get()

  var packet =
    try:
      parseOrdersFile(ordersPath)
    except KdlParseError as e:
      stderr.writeLine("Error: Failed to parse orders file: " & e.msg)
      quit(1)
    except IOError as e:
      stderr.writeLine("Error: Could not read orders file: " & e.msg)
      quit(1)

  if houseOverride > 0:
    packet.houseId = HouseId(houseOverride.uint32)

  let daemonPubkey = loadDaemonIdentityFromDefaultPath()

  let playerIdentity = loadWalletIdentity(passwordOpt)
  let pc = newPlayerNostrClient(
    @[relay],
    game.gameId,
    playerIdentity.privHex,
    playerIdentity.pubHex,
    daemonPubkey,
    PlayerNostrHandlers()
  )

  await pc.start()
  if not pc.isConnected():
    stderr.writeLine("Error: Failed to connect relay: " & relay)
    quit(1)

  let msgpack = serializeCommandPacket(packet)
  let ok = await pc.submitCommands(msgpack, packet.turn.int)
  await pc.stop()

  if not ok:
    stderr.writeLine("Error: Failed to publish turn commands")
    quit(1)

  stdout.writeLine(
    "Published turn commands for house " & $uint32(packet.houseId) &
    " turn " & $packet.turn &
    " game " & game.gameId
  )

waitFor main()
