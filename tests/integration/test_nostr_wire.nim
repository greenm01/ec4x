import std/[unittest, strutils]

import ../../src/daemon/transport/nostr/wire
import ../../src/daemon/transport/nostr/crypto

proc hexToBytes32(hexStr: string): array[32, byte] =
  if hexStr.len != 64:
    raise newException(ValueError, "Expected 64 hex chars")
  for i in 0..<32:
    result[i] = byte(parseHexInt(hexStr[i * 2 .. i * 2 + 1]))

suite "Nostr Wire Format":
  test "encode/decode payload roundtrip":
    let sec1 = "0000000000000000000000000000000000000000000000000000000000000001"
    let sec2 = "0000000000000000000000000000000000000000000000000000000000000002"
    let priv1 = hexToBytes32(sec1)
    let priv2 = hexToBytes32(sec2)
    let pub1 = hexToBytes32(derivePublicKeyHex(sec1))
    let pub2 = hexToBytes32(derivePublicKeyHex(sec2))
    let payload = "state turn=1 { house name=\"Test\" }"

    let encoded = encodePayload(payload, priv1, pub2)
    let decoded = decodePayload(encoded, priv2, pub1)
    check decoded == payload

  test "decode rejects invalid payload":
    let sec1 = "0000000000000000000000000000000000000000000000000000000000000001"
    let sec2 = "0000000000000000000000000000000000000000000000000000000000000002"
    let priv1 = hexToBytes32(sec1)
    let priv2 = hexToBytes32(sec2)
    let pub1 = hexToBytes32(derivePublicKeyHex(sec1))
    let pub2 = hexToBytes32(derivePublicKeyHex(sec2))

    let encoded = encodePayload("delta turn=1 {}", priv1, pub2)
    let tampered = encoded[0 ..< encoded.len - 4] & "ABCD"

    expect(ValueError):
      discard decodePayload(tampered, priv2, pub1)
