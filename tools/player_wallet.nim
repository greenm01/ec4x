import std/[options, os]

import ../src/player/state/identity
import ../src/player/state/wallet

proc usage() =
  stdout.writeLine("Usage:")
  stdout.writeLine("  nim r tools/player_wallet.nim status [--password PW]")
  stdout.writeLine("  nim r tools/player_wallet.nim init [--password PW]")
  stdout.writeLine(
    "  nim r tools/player_wallet.nim show-active [--password PW]"
  )
  quit(1)

proc parsePasswordArg(args: seq[string]): Option[string] =
  var i = 0
  while i < args.len:
    case args[i]
    of "--password":
      if i + 1 >= args.len:
        usage()
      return some(args[i + 1])
    else:
      stdout.writeLine("Unknown argument: " & args[i])
      usage()
    inc i
  none(string)

proc describeWalletResult(
    result: tuple[status: WalletLoadStatus, wallet: Option[IdentityWallet]]
) =
  case result.status
  of WalletLoadStatus.Success:
    let wallet = result.wallet.get()
    let identity = wallet.activeIdentity()
    stdout.writeLine("status: success")
    stdout.writeLine("wallet: " & walletPath())
    stdout.writeLine("encrypted: " & $wallet.encryptedOnDisk)
    stdout.writeLine("identities: " & $wallet.identities.len)
    stdout.writeLine("active-index: " & $wallet.activeIdx)
    stdout.writeLine("active-pubkey: " & identity.npubHex)
    stdout.writeLine("active-npub: " & identity.npub())
  of WalletLoadStatus.NotFound:
    stdout.writeLine("status: not-found")
    stdout.writeLine("wallet: " & walletPath())
  of WalletLoadStatus.NeedsPassword:
    stdout.writeLine("status: needs-password")
    stdout.writeLine("wallet: " & walletPath())
  of WalletLoadStatus.WrongPassword:
    stdout.writeLine("status: wrong-password")
    stdout.writeLine("wallet: " & walletPath())
  of WalletLoadStatus.Error:
    stdout.writeLine("status: error")
    stdout.writeLine("wallet: " & walletPath())

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    usage()

  let command = args[0]
  let passwordOpt = parsePasswordArg(args[1 .. ^1])

  case command
  of "status":
    describeWalletResult(checkWallet(passwordOpt))
  of "init":
    let current = checkWallet(passwordOpt)
    case current.status
    of WalletLoadStatus.Success:
      describeWalletResult(current)
    of WalletLoadStatus.NotFound:
      let created = createAndSaveWallet(passwordOpt)
      describeWalletResult(created)
    of WalletLoadStatus.NeedsPassword,
        WalletLoadStatus.WrongPassword,
        WalletLoadStatus.Error:
      describeWalletResult(current)
      quit(1)
  of "show-active":
    let current = checkWallet(passwordOpt)
    if current.status != WalletLoadStatus.Success:
      describeWalletResult(current)
      quit(1)
    let wallet = current.wallet.get()
    let identity = wallet.activeIdentity()
    stdout.writeLine("pubkey: " & identity.npubHex)
    stdout.writeLine("npub: " & identity.npub())
    stdout.writeLine("type: " & identity.typeLabel())
  else:
    usage()

when isMainModule:
  main()
