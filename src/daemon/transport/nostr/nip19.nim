## NIP-19 helpers for Nostr identifiers

import std/strutils

proc isHexChar(ch: char): bool =
  (ch >= '0' and ch <= '9') or
    (ch >= 'a' and ch <= 'f') or
    (ch >= 'A' and ch <= 'F')

proc normalizeHex*(value: string): string =
  if value.len != 64:
    raise newException(ValueError, "Hex pubkey must be 64 chars")
  for ch in value:
    if not ch.isHexChar:
      raise newException(ValueError, "Invalid hex pubkey")
  value.toLowerAscii()

const
  Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
  Generators = [
    0x3b6a57b2,
    0x26508e6d,
    0x1ea119fa,
    0x3d4233dd,
    0x2a1462b3,
  ]

proc bech32Polymod(values: seq[int]): int =
  var chk = 1
  for value in values:
    let top = chk shr 25
    chk = (chk and 0x1ffffff) shl 5 xor value
    for i in 0..<5:
      if ((top shr i) and 1) == 1:
        chk = chk xor Generators[i]
  chk

proc bech32HrpExpand(hrp: string): seq[int] =
  result = @[]
  for ch in hrp:
    result.add(ord(ch) shr 5)
  result.add(0)
  for ch in hrp:
    result.add(ord(ch) and 31)

proc bech32VerifyChecksum(hrp: string, data: seq[int]): bool =
  let values = bech32HrpExpand(hrp) & data
  bech32Polymod(values) == 1

proc bech32Decode*(bech: string): tuple[hrp: string, data: seq[int]] =
  let lower = bech.toLowerAscii()
  let pos = lower.rfind('1')
  if pos <= 0 or pos + 7 > lower.len:
    raise newException(ValueError, "Invalid bech32 string")

  result.hrp = lower[0..<pos]
  result.data = @[]

  for ch in lower[(pos + 1)..<lower.len]:
    let idx = Charset.find(ch)
    if idx < 0:
      raise newException(ValueError, "Invalid bech32 character")
    result.data.add(idx)

  if not bech32VerifyChecksum(result.hrp, result.data):
    raise newException(ValueError, "Invalid bech32 checksum")

proc convertBits(
    data: seq[int], fromBits, toBits: int, pad: bool
): seq[int] =
  var acc = 0
  var bits = 0
  let maxv = (1 shl toBits) - 1
  let maxAcc = (1 shl (fromBits + toBits - 1)) - 1

  for value in data:
    if value < 0 or value >= (1 shl fromBits):
      raise newException(ValueError, "Invalid bech32 data value")
    acc = ((acc shl fromBits) or value) and maxAcc
    bits += fromBits
    while bits >= toBits:
      bits -= toBits
      result.add((acc shr bits) and maxv)

  if pad:
    if bits > 0:
      result.add((acc shl (toBits - bits)) and maxv)
  else:
    if bits >= fromBits:
      raise newException(ValueError, "Excess padding in bech32 data")
    if ((acc shl (toBits - bits)) and maxv) != 0:
      raise newException(ValueError, "Non-zero padding in bech32 data")

proc bytesToHex(bytes: seq[int]): string =
  result = ""
  for value in bytes:
    result.add(value.toHex(2).toLowerAscii())

proc decodeNpubToHex*(npub: string): string =
  let decoded = bech32Decode(npub)
  if decoded.hrp != "npub":
    raise newException(ValueError, "Unsupported NIP-19 prefix")
  if decoded.data.len < 6:
    raise newException(ValueError, "Invalid NIP-19 payload")

  let payload = decoded.data[0 ..< decoded.data.len - 6]
  let bytes = convertBits(payload, 5, 8, false)
  if bytes.len != 32:
    raise newException(ValueError, "Invalid NIP-19 payload length")

  bytesToHex(bytes)

proc normalizeNostrPubkey*(value: string): string =
  let trimmed = value.strip()
  if trimmed.startsWith("npub"):
    return decodeNpubToHex(trimmed)
  normalizeHex(trimmed)
