## Identity persistence for EC4X player client
##
## Manages Nostr keypair generation, storage, and loading.
## Storage location: ~/.local/share/ec4x/identity.kdl
##
## Identity types:
##   - local: Auto-generated on first launch
##   - imported: User-provided nsec from existing Nostr identity

import std/[os, times, options, strutils, sysrand]
import kdl

import ../../daemon/transport/nostr/[nip19, crypto]
import ../../common/logger

type
  IdentityType* {.pure.} = enum
    Local = "local"
    Imported = "imported"

  Identity* = object
    nsecHex*: string       # 32-byte hex private key
    npubHex*: string       # 32-byte hex public key (derived)
    identityType*: IdentityType
    created*: DateTime

const
  IdentityNode = "identity"

proc getXdgDataDir*(): string =
  ## Get XDG_DATA_HOME or default to ~/.local/share
  result = getEnv("XDG_DATA_HOME")
  if result.len == 0:
    result = getHomeDir() / ".local" / "share"

proc identityDir*(): string =
  getXdgDataDir() / "ec4x"

proc identityPath*(): string =
  identityDir() / "identity.kdl"

proc bytesToHex(data: openArray[byte]): string =
  result = ""
  for b in data:
    result.add(b.toHex().toLowerAscii())

proc derivePublicKey(privkeyHex: string): string =
  ## Derive public key from private key using secp256k1
  derivePublicKeyHex(privkeyHex)

proc generateKeyPair*(): tuple[nsecHex: string, npubHex: string] =
  ## Generate a new random keypair
  ## Returns hex-encoded private and public keys
  var privBytes: array[32, byte]
  if not urandom(privBytes):
    raise newException(IOError, "Failed to generate random bytes")

  result.nsecHex = bytesToHex(privBytes)
  result.npubHex = derivePublicKey(result.nsecHex)

proc loadIdentity*(): Option[Identity] =
  ## Load identity from disk
  ## Returns none if no identity file exists
  let path = identityPath()
  if not fileExists(path):
    return none(Identity)

  try:
    let doc = parseKdl(readFile(path))
    if doc.len == 0 or doc[0].name != IdentityNode:
      logError("Identity", "Invalid identity file format")
      return none(Identity)

    let node = doc[0]

    # Required fields
    if not node.props.hasKey("nsec"):
      logError("Identity", "Identity file missing nsec")
      return none(Identity)

    let nsec = node.props["nsec"].getString()
    let nsecHex = if nsec.startsWith("nsec"):
                    decodeNsecToHex(nsec)
                  else:
                    nsec

    # Derive public key
    let npubHex = derivePublicKey(nsecHex)

    # Type (default to local)
    let typeStr = if node.props.hasKey("type"):
                    node.props["type"].getString()
                  else:
                    "local"
    let identityType = if typeStr == "imported":
                         IdentityType.Imported
                       else:
                         IdentityType.Local

    # Created timestamp (optional)
    let created = if node.props.hasKey("created"):
                    try:
                      parse(node.props["created"].getString(),
                            "yyyy-MM-dd'T'HH:mm:sszzz")
                    except CatchableError:
                      now()
                  else:
                    now()

    some(Identity(
      nsecHex: nsecHex,
      npubHex: npubHex,
      identityType: identityType,
      created: created
    ))
  except CatchableError as e:
    logError("Identity", "Failed to load identity: ", e.msg)
    none(Identity)

proc saveIdentity*(identity: Identity) =
  ## Save identity to disk
  let dir = identityDir()
  createDir(dir)

  let path = identityPath()
  let nsec = encodeNsec(identity.nsecHex)
  let typeStr = case identity.identityType
                of IdentityType.Local: "local"
                of IdentityType.Imported: "imported"
  let createdStr = identity.created.format("yyyy-MM-dd'T'HH:mm:sszzz")

  let content = IdentityNode & " nsec=\"" & nsec & "\" " &
                "type=\"" & typeStr & "\" " &
                "created=\"" & createdStr & "\"\n"
  writeFile(path, content)
  logInfo("Identity", "Saved identity to ", path)

proc createLocalIdentity*(): Identity =
  ## Generate and save a new local identity
  let (nsecHex, npubHex) = generateKeyPair()
  result = Identity(
    nsecHex: nsecHex,
    npubHex: npubHex,
    identityType: IdentityType.Local,
    created: now()
  )
  saveIdentity(result)
  logInfo("Identity", "Created new local identity")

proc importIdentity*(nsec: string): Identity =
  ## Import an identity from an nsec string
  ## Raises ValueError if nsec is invalid
  let nsecHex = decodeNsecToHex(nsec)
  let npubHex = derivePublicKey(nsecHex)
  result = Identity(
    nsecHex: nsecHex,
    npubHex: npubHex,
    identityType: IdentityType.Imported,
    created: now()
  )
  saveIdentity(result)
  logInfo("Identity", "Imported identity")

proc ensureIdentity*(): Identity =
  ## Load existing identity or create a new local one
  let existing = loadIdentity()
  if existing.isSome:
    return existing.get()
  createLocalIdentity()

proc npub*(identity: Identity): string =
  ## Get the bech32-encoded public key
  encodeNpub(identity.npubHex)

proc npubTruncated*(identity: Identity): string =
  ## Get truncated npub for display: npub1q3z...7xkf
  truncateNpub(identity.npub)

proc typeLabel*(identity: Identity): string =
  ## Get display label for identity type
  case identity.identityType
  of IdentityType.Local: "(local)"
  of IdentityType.Imported: "(imported)"
