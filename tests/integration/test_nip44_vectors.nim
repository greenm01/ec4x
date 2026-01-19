import std/[unittest, json, os, strutils, base64]
import nimcrypto/[sha2, hmac]
import nim_chacha20_poly1305/chacha20

import ../../src/daemon/transport/nostr/crypto

const
  VectorPath = "tests/fixtures/nip44.vectors.json"
  Nip44Version = 2'u8

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

proc encryptWithConversationKey(
    plaintext: string,
    conversationKey: array[32, byte],
    nonce: array[32, byte]
  ): string =
  let keys = messageKeys(conversationKey, nonce)
  let padded = padPlaintext(plaintext)
  var ciphertext = newSeq[byte](padded.len)
  var cipher = ChaCha(key: keys.chachaKey, nonce: keys.chachaNonce, counter: 0)
  cipher.chacha20_xor(padded, ciphertext)

  var macInput = newSeq[byte](nonce.len + ciphertext.len)
  for i in 0..<nonce.len:
    macInput[i] = nonce[i]
  for i in 0..<ciphertext.len:
    macInput[nonce.len + i] = ciphertext[i]

  let macDigest = sha256.hmac(keys.hmacKey, macInput)
  var output = newSeq[byte](1 + nonce.len + ciphertext.len + macDigest.data.len)
  output[0] = Nip44Version
  for i in 0..<nonce.len:
    output[1 + i] = nonce[i]
  for i in 0..<ciphertext.len:
    output[1 + nonce.len + i] = ciphertext[i]
  for i in 0..<macDigest.data.len:
    output[1 + nonce.len + ciphertext.len + i] = macDigest.data[i]

  base64.encode(output)

proc decryptWithConversationKey(
    payload: string,
    conversationKey: array[32, byte]
  ): string =
  if payload.len == 0 or payload[0] == '#':
    raise newException(ValueError, "Unsupported encryption version")
  if payload.len < 132 or payload.len > 87472:
    raise newException(ValueError, "Invalid payload length")

  let decoded = base64.decode(payload)
  if decoded.len < 99 or decoded.len > 65603:
    raise newException(ValueError, "Invalid decoded length")
  if cast[ptr byte](unsafeAddr decoded[0])[] != Nip44Version:
    raise newException(ValueError, "Unsupported encryption version")

  var nonce: array[32, byte]
  for i in 0..<32:
    nonce[i] = cast[ptr byte](unsafeAddr decoded[1 + i])[]

  let macStart = decoded.len - 32
  let cipherStart = 1 + 32
  let cipherLen = macStart - cipherStart
  if cipherLen <= 0:
    raise newException(ValueError, "Invalid ciphertext length")

  var cipherBytes = newSeq[byte](cipherLen)
  for i in 0..<cipherLen:
    cipherBytes[i] = cast[ptr byte](unsafeAddr decoded[cipherStart + i])[]

  var macExpected: array[32, byte]
  for i in 0..<32:
    macExpected[i] = cast[ptr byte](unsafeAddr decoded[macStart + i])[]

  let keys = messageKeys(conversationKey, nonce)
  var macInput = newSeq[byte](nonce.len + cipherBytes.len)
  for i in 0..<nonce.len:
    macInput[i] = nonce[i]
  for i in 0..<cipherBytes.len:
    macInput[nonce.len + i] = cipherBytes[i]

  let macDigest = sha256.hmac(keys.hmacKey, macInput)
  if not constantTimeEqualsFixed(macDigest.data, macExpected):
    raise newException(ValueError, "Invalid MAC")

  var plaintextPadded = newSeq[byte](cipherBytes.len)
  var cipher = ChaCha(key: keys.chachaKey, nonce: keys.chachaNonce, counter: 0)
  cipher.chacha20_xor(cipherBytes, plaintextPadded)

  unpadPlaintext(plaintextPadded)

proc loadVectors(): JsonNode =
  if not fileExists(VectorPath):
    raise newException(CatchableError, "Missing NIP-44 vectors fixture")
  parseJson(readFile(VectorPath))

suite "NIP-44 Test Vectors":
  test "conversation key vectors":
    let vectors = loadVectors()["v2"]["valid"]["get_conversation_key"]
    for entry in vectors:
      let sec1 = entry["sec1"].getStr()
      let pub2 = entry["pub2"].getStr()
      let expected = entry["conversation_key"].getStr()
      let convKey = conversationKey(hexToBytes32(sec1), hexToBytes32(pub2))
      check toLowerHex(convKey) == expected

  test "message key vectors":
    let messageKeysNode = loadVectors()["v2"]["valid"]["get_message_keys"]
    let convKey = hexToBytes32(messageKeysNode["conversation_key"].getStr())
    for entry in messageKeysNode["keys"]:
      let nonce = hexToBytes32(entry["nonce"].getStr())
      let keys = messageKeys(convKey, nonce)
      check toLowerHex(keys.chachaKey) == entry["chacha_key"].getStr()
      check toLowerHex(keys.chachaNonce) == entry["chacha_nonce"].getStr()
      check toLowerHex(keys.hmacKey) == entry["hmac_key"].getStr()

  test "calc padded length vectors":
    let entries = loadVectors()["v2"]["valid"]["calc_padded_len"]
    for entry in entries:
      let inputLen = entry[0].getInt()
      let expected = entry[1].getInt()
      check calcPaddedLen(inputLen) == expected

  test "encrypt/decrypt vectors":
    let entries = loadVectors()["v2"]["valid"]["encrypt_decrypt"]
    for entry in entries:
      let sec1 = entry["sec1"].getStr()
      let sec2 = entry["sec2"].getStr()
      let nonce = entry["nonce"].getStr()
      let plaintext = entry["plaintext"].getStr()
      let expectedPayload = entry["payload"].getStr()

      let pub2 = derivePublicKeyHex(sec2)
      let convKey = conversationKey(hexToBytes32(sec1), hexToBytes32(pub2))
      let payload = encryptWithConversationKey(
        plaintext,
        convKey,
        hexToBytes32(nonce)
      )
      check payload == expectedPayload

      let pub1 = derivePublicKeyHex(sec1)
      let convKeyReverse = conversationKey(
        hexToBytes32(sec2),
        hexToBytes32(pub1)
      )
      let decrypted = decryptWithConversationKey(payload, convKeyReverse)
      check decrypted == plaintext

  test "long message vectors":
    let entries = loadVectors()["v2"]["valid"]["encrypt_decrypt_long_msg"]
    for entry in entries:
      let convKey = hexToBytes32(entry["conversation_key"].getStr())
      let nonce = hexToBytes32(entry["nonce"].getStr())
      let pattern = entry["pattern"].getStr()
      let repeatCount = entry["repeat"].getInt()
      let plaintext = pattern.repeat(repeatCount)

      let plaintextDigest = sha256.digest(plaintext)
      check plaintextDigest.data.toHex().toLowerAscii() ==
        entry["plaintext_sha256"].getStr()

      let payload = encryptWithConversationKey(plaintext, convKey, nonce)
      let payloadDigest = sha256.digest(payload)
      check payloadDigest.data.toHex().toLowerAscii() ==
        entry["payload_sha256"].getStr()

  test "invalid encryption lengths":
    let entries = loadVectors()["v2"]["invalid"]["encrypt_msg_lengths"]
    for entry in entries:
      let length = entry.getInt()
      let payload = newString(length)
      expect(ValueError):
        discard padPlaintext(payload)

  test "invalid conversation keys":
    let entries = loadVectors()["v2"]["invalid"]["get_conversation_key"]
    for entry in entries:
      let sec1 = entry["sec1"].getStr()
      let pub2 = entry["pub2"].getStr()
      expect(CatchableError):
        discard conversationKey(hexToBytes32(sec1), hexToBytes32(pub2))

  test "invalid payloads":
    let entries = loadVectors()["v2"]["invalid"]["decrypt"]
    for entry in entries:
      let convKey = hexToBytes32(entry["conversation_key"].getStr())
      let payload = entry["payload"].getStr()
      expect(ValueError):
        discard decryptWithConversationKey(payload, convKey)
