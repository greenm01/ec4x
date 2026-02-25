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
import ./wallet_crypto

type
  IdentityWallet* = object
    identities*: seq[Identity]
    activeIdx*: int
    encryptedOnDisk*: bool
    sessionPassword*: string

const
  WalletNode = "wallet"
  WalletIdentityNode = "identity"
  WalletFile = "wallet.kdl"
  MaxIdentityCount* = 10

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

proc syncLegacyIdentityMirror(activeIdentity: Identity,
    allowPlaintextMirror: bool) =
  ## Keep legacy identity.kdl only for plaintext wallets.
  let mirrorPath = identityPath()
  if allowPlaintextMirror:
    saveIdentity(activeIdentity)
  elif fileExists(mirrorPath):
    try:
      removeFile(mirrorPath)
    except OSError:
      discard

proc saveWallet*(wallet: IdentityWallet, passwordOpt: Option[string] = none(string)) =
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

  var finalContent = content
  var willBeEncrypted = false

  if passwordOpt.isSome:
    finalContent = encryptWallet(content, passwordOpt.get())
    willBeEncrypted = true
  elif wallet.encryptedOnDisk and wallet.sessionPassword.len > 0:
    finalContent = encryptWallet(content, wallet.sessionPassword)
    willBeEncrypted = true

  writeFile(walletPath(), finalContent)
  syncLegacyIdentityMirror(
    normalized.identities[normalized.activeIdx],
    not willBeEncrypted
  )
  
  if willBeEncrypted:
    logInfo("Wallet", "Saved encrypted wallet to ", walletPath())
  else:
    logInfo("Wallet", "Saved plaintext wallet to ", walletPath())

type
  WalletLoadStatus* {.pure.} = enum
    Success
    NeedsPassword
    WrongPassword
    Error

proc loadWallet*(passwordOpt: Option[string] = none(string)): tuple[status: WalletLoadStatus, wallet: Option[IdentityWallet]] =
  let path = walletPath()
  if not fileExists(path):
    return (WalletLoadStatus.Error, none(IdentityWallet))

  try:
    let fileContent = readFile(path)
    if fileContent.len == 0:
      return (WalletLoadStatus.Error, none(IdentityWallet))

    var kdlStr = fileContent
    var isEncrypted = false

    if isEncryptedContainer(fileContent):
      if passwordOpt.isNone or passwordOpt.get().len == 0:
        return (WalletLoadStatus.NeedsPassword, none(IdentityWallet))
      let decrypted = decryptWallet(fileContent, passwordOpt.get())
      if decrypted.isNone:
        return (WalletLoadStatus.WrongPassword, none(IdentityWallet))
      kdlStr = decrypted.get()
      isEncrypted = true

    let doc = parseKdl(kdlStr)
    if doc.len == 0:
      return (WalletLoadStatus.Error, none(IdentityWallet))

    var wallet = IdentityWallet(
      identities: @[],
      activeIdx: 0,
      encryptedOnDisk: isEncrypted,
      sessionPassword: if isEncrypted: passwordOpt.get() else: ""
    )

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
      return (WalletLoadStatus.Error, none(IdentityWallet))

    wallet.clampActiveIdx()
    return (WalletLoadStatus.Success, some(wallet))
  except CatchableError as e:
    logError("Wallet", "Failed to load wallet: ", e.msg)
    return (WalletLoadStatus.Error, none(IdentityWallet))

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
  if wallet.identities.len >= MaxIdentityCount:
    raise newException(ValueError, "Identity limit reached")
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

  if wallet.identities.len >= MaxIdentityCount:
    raise newException(ValueError, "Identity limit reached")

  result = Identity(
    nsecHex: nsecHex,
    npubHex: npubHex,
    identityType: IdentityType.Imported,
    created: now()
  )
  wallet.identities.add(result)
  wallet.activeIdx = wallet.identities.len - 1
  saveWallet(wallet)

proc removeIdentityAt*(wallet: var IdentityWallet, idx: int): bool =
  ## Remove an identity by index. Returns false if not allowed.
  if wallet.identities.len <= 1:
    return false
  if idx < 0 or idx >= wallet.identities.len:
    return false
  wallet.identities.delete(idx)
  wallet.clampActiveIdx()
  saveWallet(wallet)
  true

proc ensureWallet*(passwordOpt: Option[string] = none(string)): tuple[status: WalletLoadStatus, wallet: Option[IdentityWallet]] =
  let existing = loadWallet(passwordOpt)
  if existing.status == WalletLoadStatus.Success:
    var wallet = existing.wallet.get()
    syncLegacyIdentityMirror(wallet.activeIdentity(), not wallet.encryptedOnDisk)
    return (WalletLoadStatus.Success, some(wallet))
  elif existing.status == WalletLoadStatus.NeedsPassword or existing.status == WalletLoadStatus.WrongPassword:
    return existing

  let legacy = loadIdentity()
  if legacy.isSome:
    var wallet = IdentityWallet(
      identities: @[legacy.get()],
      activeIdx: 0,
      encryptedOnDisk: passwordOpt.isSome,
      sessionPassword: if passwordOpt.isSome: passwordOpt.get() else: ""
    )
    saveWallet(wallet, passwordOpt)
    logInfo("Wallet", "Migrated legacy identity to wallet")
    return (WalletLoadStatus.Success, some(wallet))

  let keys = identity.generateKeyPair()
  let first = Identity(
    nsecHex: keys.nsecHex,
    npubHex: keys.npubHex,
    identityType: IdentityType.Local,
    created: now()
  )
  var newWallet = IdentityWallet(
    identities: @[first],
    activeIdx: 0,
    encryptedOnDisk: passwordOpt.isSome,
    sessionPassword: if passwordOpt.isSome: passwordOpt.get() else: ""
  )
  saveWallet(newWallet, passwordOpt)
  logInfo("Wallet", "Created new wallet with local identity")
  return (WalletLoadStatus.Success, some(newWallet))
