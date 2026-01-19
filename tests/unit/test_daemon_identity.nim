import std/[unittest, os, options]

import ../../src/daemon/identity
import ../../src/daemon/transport/nostr/crypto
import ../../src/daemon/transport/nostr/nip19

proc tempDir(): string =
  let base = getTempDir() / "ec4x_identity_test"
  createDir(base)
  base

proc withTempDataDir(body: proc(dir: string)) =
  let dir = tempDir()
  let oldValue = getEnv("XDG_DATA_HOME")
  putEnv("XDG_DATA_HOME", dir)
  try:
    body(dir)
  finally:
    try:
      let identityFile = identityPath()
      if fileExists(identityFile):
        removeFile(identityFile)
      if dirExists(identityDir()):
        removeDir(identityDir())
      if dirExists(dir):
        removeDir(dir)
    except OSError:
      discard
    if oldValue.len == 0:
      delEnv("XDG_DATA_HOME")
    else:
      putEnv("XDG_DATA_HOME", oldValue)

suite "Daemon Identity":
  test "create and load identity":
    withTempDataDir(proc (dir: string) =
      let identity = createLocalIdentity()
      let loadedOpt = loadIdentity()
      check loadedOpt.isSome
      let loaded = loadedOpt.get()
      check loaded.privateKeyHex == identity.privateKeyHex
      check loaded.publicKeyHex == identity.publicKeyHex
      check loaded.identityType == identity.identityType
    )

  test "import identity uses nsec":
    withTempDataDir(proc (dir: string) =
      let example = "0000000000000000000000000000000000000000000000000000000000000001"
      let nsec = encodeNsec(example)
      let identity = importIdentity(nsec)
      check identity.privateKeyHex == example
      check identity.publicKeyHex == derivePublicKeyHex(example)
      check identity.identityType == IdentityType.Imported
    )

  test "missing identity returns none":
    withTempDataDir(proc (dir: string) =
      let loaded = loadIdentity()
      check loaded.isNone
    )
