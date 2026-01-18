## Identity persistence for EC4X daemon
##
## Manages Nostr keypair generation, storage, and loading.
## Storage location: ~/.local/share/ec4x/daemon_identity.kdl

import std/[os, times, options, strutils]
import kdl

import transport/nostr/crypto
import transport/nostr/nip19
import ../common/logger

type
  IdentityType* {.pure.} = enum
    Local = "local"
    Imported = "imported"

  DaemonIdentity* = object
    privateKeyHex*: string
    publicKeyHex*: string
    identityType*: IdentityType
    created*: DateTime

const
  IdentityNode = "identity"
  IdentityFile = "daemon_identity.kdl"

proc getXdgDataDir*(): string =
  ## Get XDG_DATA_HOME or default to ~/.local/share
  result = getEnv("XDG_DATA_HOME")
  if result.len == 0:
    result = getHomeDir() / ".local" / "share"

proc identityDir*(): string =
  getXdgDataDir() / "ec4x"

proc identityPath*(): string =
  identityDir() / IdentityFile

proc loadIdentity*(): Option[DaemonIdentity] =
  ## Load daemon identity from disk
  ## Returns none if no identity file exists
  let path = identityPath()
  if not fileExists(path):
    return none(DaemonIdentity)

  try:
    let doc = parseKdl(readFile(path))
    if doc.len == 0 or doc[0].name != IdentityNode:
      logError("DaemonIdentity", "Invalid identity file format")
      return none(DaemonIdentity)

    let node = doc[0]
    if not node.props.hasKey("nsec"):
      logError("DaemonIdentity", "Identity file missing nsec")
      return none(DaemonIdentity)

    let nsec = node.props["nsec"].getString()
    let nsecHex = if nsec.startsWith("nsec"):
                    decodeNsecToHex(nsec)
                  else:
                    normalizeHex(nsec)

    let publicHex =
      if node.props.hasKey("npub"):
        let npubValue = node.props["npub"].getString()
        if npubValue.startsWith("npub"):
          decodeNpubToHex(npubValue)
        else:
          normalizeHex(npubValue)
      else:
        derivePublicKeyHex(nsecHex)
    let identityType =
      if node.props.hasKey("type") and node.props["type"].getString() == "imported":
        IdentityType.Imported
      else:
        IdentityType.Local

    let created = if node.props.hasKey("created"):
                    try:
                      parse(node.props["created"].getString(),
                            "yyyy-MM-dd'T'HH:mm:sszzz")
                    except CatchableError:
                      now()
                  else:
                    now()

    some(DaemonIdentity(
      privateKeyHex: nsecHex,
      publicKeyHex: publicHex,
      identityType: identityType,
      created: created
    ))
  except CatchableError as e:
    logError("DaemonIdentity", "Failed to load identity: ", e.msg)
    none(DaemonIdentity)

proc saveIdentity*(identity: DaemonIdentity) =
  ## Save daemon identity to disk
  let dir = identityDir()
  createDir(dir)

  let path = identityPath()
  let nsec = encodeNsec(identity.privateKeyHex)
  let npub = encodeNpub(identity.publicKeyHex)
  let typeStr = case identity.identityType
                of IdentityType.Local: "local"
                of IdentityType.Imported: "imported"
  let createdStr = identity.created.format("yyyy-MM-dd'T'HH:mm:sszzz")

  let content = IdentityNode & " nsec=\"" & nsec & "\" " &
                "npub=\"" & npub & "\" " &
                "type=\"" & typeStr & "\" " &
                "created=\"" & createdStr & "\"\n"
  writeFile(path, content)
  logInfo("DaemonIdentity", "Saved daemon identity to ", path)

proc createLocalIdentity*(): DaemonIdentity =
  ## Generate and save a new local identity
  let keys = generateKeyPair()
  result = DaemonIdentity(
    privateKeyHex: keys.privateKey,
    publicKeyHex: keys.publicKey,
    identityType: IdentityType.Local,
    created: now()
  )
  saveIdentity(result)
  logInfo("DaemonIdentity", "Created new daemon identity")

proc importIdentity*(nsec: string): DaemonIdentity =
  ## Import an identity from an nsec string
  let nsecHex = decodeNsecToHex(nsec)
  let pubHex = derivePublicKeyHex(nsecHex)
  result = DaemonIdentity(
    privateKeyHex: nsecHex,
    publicKeyHex: pubHex,
    identityType: IdentityType.Imported,
    created: now()
  )
  saveIdentity(result)
  logInfo("DaemonIdentity", "Imported daemon identity")

proc ensureIdentity*(allowRegen: bool): DaemonIdentity =
  ## Load existing identity or create a new local one
  let existing = loadIdentity()
  if existing.isSome:
    return existing.get()
  if not allowRegen:
    raise newException(CatchableError,
      "Daemon identity missing or invalid; set EC4X_REGEN_IDENTITY=1 to regenerate")
  createLocalIdentity()

proc ensureIdentity*(): DaemonIdentity =
  ## Backwards-compatible default (regen allowed)
  ensureIdentity(true)

proc npub*(identity: DaemonIdentity): string =
  ## Get bech32-encoded public key
  encodeNpub(identity.publicKeyHex)
