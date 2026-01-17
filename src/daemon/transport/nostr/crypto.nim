## Cryptographic operations for Nostr protocol
## Implements secp256k1 signing and NIP-44 encryption

import std/[base64, strutils, sysrand]
import nimcrypto/[sha2, hmac]
import secp256k1
import stew/byteutils
import nim_chacha20_poly1305/[common, chacha20, helpers]

import types
import nip01
import nip19

const
  Nip44Salt = "nip44-v2"
  Nip44Version = 2'u8
  MinPlaintextSize = 1
  MaxPlaintextSize = 65535

# =============================================================================
# Key Helpers
# =============================================================================

proc generateKeyPair*(): KeyPair =
  ## Generate a new Nostr keypair
  let keypairResult = SkKeyPair.random(urandom)
  if keypairResult.isErr:
    raise newException(CatchableError, $keypairResult.error)

  let keypair = keypairResult.get()
  let xonly = keypair.pubkey.toXOnly()
  let publicHex = xonly.toHex().toLowerAscii()
  let privateHex = keypair.seckey.toHex().toLowerAscii()

  result = KeyPair(
    privateKey: privateHex,
    publicKey: publicHex,
    npub: encodeNpub(publicHex),
    nsec: encodeNsec(privateHex)
  )

proc derivePublicKeyHex*(privateHex: string): string =
  ## Derive x-only public key hex from private key hex
  let keyResult = SkSecretKey.fromHex(privateHex)
  if keyResult.isErr:
    raise newException(ValueError, $keyResult.error)

  let publicKey = keyResult.get().toPublicKey().toXOnly()
  publicKey.toHex().toLowerAscii()

proc sha256Hash*(data: string): string =
  ## Compute SHA256 hash and return hex
  $sha256.digest(data).toLowerAscii()

proc toHex*(data: openArray[byte]): string =
  ## Convert bytes to lowercase hex
  data.toHex().toLowerAscii()

proc toBytes(hexStr: string): seq[byte] =
  let resultValue = seq[byte].fromHex(hexStr)
  if resultValue.isErr:
    raise newException(ValueError, $resultValue.error)
  resultValue.get()

# =============================================================================
# Event Signing
# =============================================================================

proc signEvent*(event: var NostrEvent, privateKey: array[32, byte]) =
  ## Sign a Nostr event with private key (NIP-01)
  let serialized = serializeForSigning(event)
  let digest = sha256.digest(serialized)
  let msg = SkMessage.fromBytes(digest.data).get()
  let sec = SkSecretKey.fromRaw(privateKey).get()
  let sig = sec.signSchnorr(msg, urandom).get()

  event.id = computeEventId(event)
  event.sig = sig.toHex().toLowerAscii()

proc verifyEvent*(event: NostrEvent): bool =
  ## Verify event signature
  if computeEventId(event) != event.id:
    return false

  let serialized = serializeForSigning(event)
  let digest = sha256.digest(serialized)
  let msg = SkMessage.fromBytes(digest.data).get()
  let pubkey = SkXOnlyPublicKey.fromHex(event.pubkey).get()
  let sig = SkSchnorrSignature.fromHex(event.sig).get()
  sig.verify(msg, pubkey)

# =============================================================================
# NIP-44: Conversation Keys
# =============================================================================

proc hkdfExtractSha256(ikm: openArray[byte],
    salt: openArray[byte]): array[32, byte] =
  var hctx: HMAC[sha256]
  hctx.init(salt)
  hctx.update(ikm)
  discard hctx.finish(result)
  hctx.clear()

proc hkdfExpandSha256(prk: array[32, byte], info: openArray[byte],
    outLen: int): seq[byte] =
  if outLen <= 0:
    return @[]

  var output: seq[byte] = @[]
  var previous: array[32, byte]
  var counter = 1'u8

  while output.len < outLen:
    var hctx: HMAC[sha256]
    hctx.init(prk)
    if output.len > 0:
      hctx.update(previous)
    hctx.update(info)
    hctx.update([counter])
    discard hctx.finish(previous)
    hctx.clear()

    let remaining = outLen - output.len
    let toCopy = min(remaining, 32)
    for i in 0..<toCopy:
      output.add(previous[i])
    counter.inc()

  output

proc conversationKey(privKey: array[32, byte],
    pubKey: array[32, byte]): array[32, byte] =
  let seckey = SkSecretKey.fromRaw(privKey).get()
  let xonly = SkXOnlyPublicKey.fromRaw(pubKey).get()

  var compressed: array[33, byte]
  compressed[0] = 0x02'u8
  let xOnlyRaw = xonly.toRaw()
  for i in 0..<32:
    compressed[1 + i] = xOnlyRaw[i]

  let pubkey = SkPublicKey.fromRaw(compressed).get()
  let shared = seckey.ecdh(pubkey)
  let salt = Nip44Salt.toOpenArrayByte(0, Nip44Salt.len - 1)
  hkdfExtractSha256(shared.data, salt)

proc messageKeys(conversationKey: array[32, byte],
    nonce: array[32, byte]):
    tuple[chachaKey: array[32, byte], chachaNonce: array[12, byte],
          hmacKey: array[32, byte]] =
  let expanded = hkdfExpandSha256(conversationKey, nonce, 76)
  for i in 0..<32:
    result.chachaKey[i] = expanded[i]
  for i in 0..<12:
    result.chachaNonce[i] = expanded[32 + i]
  for i in 0..<32:
    result.hmacKey[i] = expanded[44 + i]

# =============================================================================
# NIP-44: Padding
# =============================================================================

proc nextPowerOfTwo(n: int): int =
  var power = 1
  while power <= n:
    power = power shl 1
  power

proc calcPaddedLen(unpaddedLen: int): int =
  if unpaddedLen <= 32:
    return 32

  let nextPower = nextPowerOfTwo(unpaddedLen - 1)
  let chunk = if nextPower <= 256: 32 else: nextPower div 8
  chunk * ((unpaddedLen - 1) div chunk + 1)

proc padPlaintext(plaintext: string): seq[byte] =
  let bytes = cast[seq[byte]](plaintext)
  let len = bytes.len
  if len < MinPlaintextSize or len > MaxPlaintextSize:
    raise newException(ValueError, "Invalid plaintext length")

  let paddedLen = calcPaddedLen(len)
  result = newSeq[byte](2 + paddedLen)
  result[0] = byte((len shr 8) and 0xff)
  result[1] = byte(len and 0xff)
  for i in 0..<len:
    result[2 + i] = bytes[i]

proc unpadPlaintext(padded: openArray[byte]): string =
  if padded.len < 2:
    raise newException(ValueError, "Invalid padded plaintext")

  let len = (int(padded[0]) shl 8) or int(padded[1])
  if len < MinPlaintextSize or len > MaxPlaintextSize:
    raise newException(ValueError, "Invalid plaintext length")

  let paddedLen = calcPaddedLen(len)
  if padded.len != paddedLen + 2:
    raise newException(ValueError, "Invalid padding length")

  let content = padded[2 ..< 2 + len]
  result = cast[string](content)

# =============================================================================
# NIP-44: Encryption
# =============================================================================

proc encryptNIP44*(plaintext: string, senderPrivKey: array[32, byte],
    recipientPubKey: array[32, byte]): string =
  ## Encrypt message using NIP-44
  let convKey = conversationKey(senderPrivKey, recipientPubKey)

  var nonce: array[32, byte]
  if not urandom(nonce):
    raise newException(CatchableError, "Failed to generate nonce")

  let keys = messageKeys(convKey, nonce)
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
  var output = newSeq[byte](
    1 + nonce.len + ciphertext.len + macDigest.data.len
  )
  output[0] = Nip44Version
  for i in 0..<nonce.len:
    output[1 + i] = nonce[i]
  for i in 0..<ciphertext.len:
    output[1 + nonce.len + i] = ciphertext[i]
  for i in 0..<macDigest.data.len:
    output[1 + nonce.len + ciphertext.len + i] = macDigest.data[i]

  base64.encode(output)

proc decryptNIP44*(ciphertext: string, recipientPrivKey: array[32, byte],
    senderPubKey: array[32, byte]): string =
  ## Decrypt NIP-44 message
  if ciphertext.len == 0 or ciphertext[0] == '#':
    raise newException(ValueError, "Unsupported encryption version")

  if ciphertext.len < 132 or ciphertext.len > 87472:
    raise newException(ValueError, "Invalid payload length")

  let decoded = base64.decode(ciphertext)
  let decodedBytes = decoded.toOpenArrayByte(0, decoded.len - 1)
  if decodedBytes.len < 99 or decodedBytes.len > 65603:
    raise newException(ValueError, "Invalid decoded length")

  if decodedBytes[0] != Nip44Version:
    raise newException(ValueError, "Unsupported encryption version")

  var nonce: array[32, byte]
  for i in 0..<32:
    nonce[i] = decodedBytes[1 + i]

  let macStart = decodedBytes.len - 32
  let cipherStart = 1 + 32
  let cipherLen = macStart - cipherStart
  if cipherLen <= 0:
    raise newException(ValueError, "Invalid ciphertext length")

  var cipherBytes = newSeq[byte](cipherLen)
  for i in 0..<cipherLen:
    cipherBytes[i] = decodedBytes[cipherStart + i]

  var macExpected: array[32, byte]
  for i in 0..<32:
    macExpected[i] = decodedBytes[macStart + i]

  let convKey = conversationKey(recipientPrivKey, senderPubKey)
  let keys = messageKeys(convKey, nonce)

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
