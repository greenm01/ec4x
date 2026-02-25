## Player identity wallet for EC4X TUI
##
## Supports multiple local/imported identities and active identity
## selection. Wallet is stored at ~/.local/share/ec4x/wallet.kdl.
##
## Compatibility:
## - Migrates legacy identity.kdl on first wallet load.
## - Mirrors active identity back to identity.kdl for tools that still
##   read single-identity state.

import std/[os, times, options, strutils]
import kdl

import ../../common/logger
import ../../daemon/transport/nostr/[crypto, nip19]
import ./identity

type
  IdentityWallet* = object
    identities*: seq[Identity]
    activeIdx*: int

const
  WalletNode = "wallet"
  WalletIdentityNode = "identity"
  WalletFile = "wallet.kdl"

proc walletPath*(): string =
  identityDir() / WalletFile

proc parsePrivateKey(input: string): string =
  let value = input.strip()
  if value.len == 0:
    raise newException(ValueError, "Secret key cannot be empty")
  if value.startsWith("nsec"):
    return decodeNsecToHex(value)
  normalizeHex(value)

proc clampActiveIdx(wallet: var IdentityWallet) =
  if wallet.identities.len == 0:
    wallet.activeIdx = 0
  elif wallet.activeIdx < 0:
    wallet.activeIdx = 0
  elif wallet.activeIdx >= wallet.identities.len:
    wallet.activeIdx = wallet.identities.len - 1

proc saveWallet*(wallet: IdentityWallet) =
  var normalized = wallet
  normalized.clampActiveIdx()
  if normalized.identities.len == 0:
    raise newException(ValueError, "Wallet must contain identities")

  createDir(identityDir())

  var content = WalletNode & " active=\"" & $normalized.activeIdx & "\"\n"
  for identity in normalized.identities:
    let typeStr = case identity.identityType
      of IdentityType.Local: "local"
      of IdentityType.Imported: "imported"
    let createdStr = identity.created.format("yyyy-MM-dd'T'HH:mm:sszzz")
    let nsec = encodeNsec(identity.nsecHex)
    content.add(
      WalletIdentityNode & " nsec=\"" & nsec & "\" " &
      "type=\"" & typeStr & "\" " &
      "created=\"" & createdStr & "\"\n"
    )

  writeFile(walletPath(), content)
  saveIdentity(normalized.identities[normalized.activeIdx])
  logInfo("Wallet", "Saved wallet to ", walletPath())

proc loadWallet*(): Option[IdentityWallet] =
  let path = walletPath()
  if not fileExists(path):
    return none(IdentityWallet)

  try:
    let doc = parseKdl(readFile(path))
    if doc.len == 0:
      return none(IdentityWallet)

    var wallet = IdentityWallet(identities: @[], activeIdx: 0)

    for node in doc:
      if node.name == WalletNode:
        if node.props.hasKey("active"):
          try:
            wallet.activeIdx = parseInt(node.props["active"].kString())
          except ValueError:
            wallet.activeIdx = 0
      elif node.name == WalletIdentityNode:
        if not node.props.hasKey("nsec"):
          continue
        let nsecHex = parsePrivateKey(node.props["nsec"].kString())
        let npubHex = derivePublicKeyHex(nsecHex)
        let typeStr = if node.props.hasKey("type"):
          node.props["type"].kString()
        else:
          "local"
        let identityType = if typeStr == "imported":
          IdentityType.Imported
        else:
          IdentityType.Local
        let created = if node.props.hasKey("created"):
          try:
            parse(node.props["created"].kString(),
              "yyyy-MM-dd'T'HH:mm:sszzz")
          except CatchableError:
            now()
        else:
          now()
        wallet.identities.add(Identity(
          nsecHex: nsecHex,
          npubHex: npubHex,
          identityType: identityType,
          created: created
        ))

    if wallet.identities.len == 0:
      return none(IdentityWallet)

    wallet.clampActiveIdx()
    some(wallet)
  except CatchableError as e:
    logError("Wallet", "Failed to load wallet: ", e.msg)
    none(IdentityWallet)

proc activeIdentity*(wallet: IdentityWallet): Identity =
  if wallet.identities.len == 0:
    raise newException(ValueError, "Wallet has no identities")
  let idx = clamp(wallet.activeIdx, 0, wallet.identities.len - 1)
  wallet.identities[idx]

proc setActiveIndex*(wallet: var IdentityWallet, idx: int): bool =
  if wallet.identities.len == 0:
    return false
  let nextIdx = clamp(idx, 0, wallet.identities.len - 1)
  if nextIdx == wallet.activeIdx:
    return false
  wallet.activeIdx = nextIdx
  saveWallet(wallet)
  true

proc cycleActive*(wallet: var IdentityWallet, delta: int): bool =
  if wallet.identities.len <= 1:
    return false
  let count = wallet.identities.len
  var idx = wallet.activeIdx + delta
  while idx < 0:
    idx += count
  while idx >= count:
    idx -= count
  if idx == wallet.activeIdx:
    return false
  wallet.activeIdx = idx
  saveWallet(wallet)
  true

proc createNewLocalIdentity*(wallet: var IdentityWallet): Identity =
  let keys = identity.generateKeyPair()
  result = Identity(
    nsecHex: keys.nsecHex,
    npubHex: keys.npubHex,
    identityType: IdentityType.Local,
    created: now()
  )
  wallet.identities.add(result)
  wallet.activeIdx = wallet.identities.len - 1
  saveWallet(wallet)

proc importIntoWallet*(wallet: var IdentityWallet, nsecOrHex: string):
    Identity =
  let nsecHex = parsePrivateKey(nsecOrHex)
  let npubHex = derivePublicKeyHex(nsecHex)
  for idx, identity in wallet.identities:
    if identity.npubHex == npubHex:
      wallet.activeIdx = idx
      saveWallet(wallet)
      return identity

  result = Identity(
    nsecHex: nsecHex,
    npubHex: npubHex,
    identityType: IdentityType.Imported,
    created: now()
  )
  wallet.identities.add(result)
  wallet.activeIdx = wallet.identities.len - 1
  saveWallet(wallet)

proc ensureWallet*(): IdentityWallet =
  let existing = loadWallet()
  if existing.isSome:
    result = existing.get()
    saveIdentity(result.activeIdentity())
    return

  let legacy = loadIdentity()
  if legacy.isSome:
    result = IdentityWallet(
      identities: @[legacy.get()],
      activeIdx: 0
    )
    saveWallet(result)
    let oldPath = identityPath()
    if fileExists(oldPath):
      try:
        removeFile(oldPath)
      except OSError:
        discard
    saveIdentity(result.activeIdentity())
    logInfo("Wallet", "Migrated legacy identity to wallet")
    return

  let keys = identity.generateKeyPair()
  let first = Identity(
    nsecHex: keys.nsecHex,
    npubHex: keys.npubHex,
    identityType: IdentityType.Local,
    created: now()
  )
  result = IdentityWallet(
    identities: @[first],
    activeIdx: 0
  )
  saveWallet(result)
  logInfo("Wallet", "Created new wallet with local identity")
