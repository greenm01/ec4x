import std/[unittest, strutils]

import ../../src/daemon/transport/nostr/crypto

proc hexToBytes32(hexStr: string): array[32, byte] =
  if hexStr.len != 64:
    raise newException(ValueError, "Expected 64 hex chars")
  for i in 0..<32:
    result[i] = byte(parseHexInt(hexStr[i * 2 .. i * 2 + 1]))

proc toLowerHex(bytes: openArray[byte]): string =
  var pieces: seq[string] = @[]
  for value in bytes:
    pieces.add(value.toHex(2))
  pieces.join("").toLowerAscii()

suite "NIP-44 Crypto":
  test "conversation key is symmetric":
    let sec1 = "0000000000000000000000000000000000000000000000000000000000000001"
    let sec2 = "0000000000000000000000000000000000000000000000000000000000000002"
    let pub1 = hexToBytes32(derivePublicKeyHex(sec1))
    let pub2 = hexToBytes32(derivePublicKeyHex(sec2))
    let key1 = conversationKey(hexToBytes32(sec1), pub2)
    let key2 = conversationKey(hexToBytes32(sec2), pub1)
    check key1 == key2

  test "message keys match expected vector":
    let convKey = hexToBytes32(
      "a1a3d60f3470a8612633924e91febf96dc5366ce130f658b1f0fc652c20b3b54"
    )
    let nonce = hexToBytes32(
      "e1e6f880560d6d149ed83dcc7e5861ee62a5ee051f7fde9975fe5d25d2a02d72"
    )
    let keys = messageKeys(convKey, nonce)
    check toLowerHex(keys.chachaKey) ==
      "f145f3bed47cb70dbeaac07f3a3fe683e822b3715edb7c4fe310829014ce7d76"
    check toLowerHex(keys.chachaNonce) == "c4ad129bb01180c0933a160c"
    check toLowerHex(keys.hmacKey) ==
      "027c1db445f05e2eee864a0975b0ddef5b7110583c8c192de3732571ca5838c4"

  test "padding roundtrip":
    let padded = padPlaintext("hello")
    check padded.len == 34
    check unpadPlaintext(padded) == "hello"

  test "calc padded length boundaries":
    check calcPaddedLen(1) == 32
    check calcPaddedLen(32) == 32
    check calcPaddedLen(33) == 64
    check calcPaddedLen(256) == 256
    check calcPaddedLen(257) == 320

  test "encrypt and decrypt roundtrip":
    let sec1 = "0000000000000000000000000000000000000000000000000000000000000001"
    let sec2 = "0000000000000000000000000000000000000000000000000000000000000002"
    let priv1 = hexToBytes32(sec1)
    let priv2 = hexToBytes32(sec2)
    let pub1 = hexToBytes32(derivePublicKeyHex(sec1))
    let pub2 = hexToBytes32(derivePublicKeyHex(sec2))
    let payload = encryptNIP44("hello nostr", priv1, pub2)
    let plaintext = decryptNIP44(payload, priv2, pub1)
    check plaintext == "hello nostr"

  test "encrypt rejects empty message":
    let sec1 = "0000000000000000000000000000000000000000000000000000000000000001"
    let sec2 = "0000000000000000000000000000000000000000000000000000000000000002"
    let priv1 = hexToBytes32(sec1)
    let pub2 = hexToBytes32(derivePublicKeyHex(sec2))
    expect(ValueError):
      discard encryptNIP44("", priv1, pub2)
