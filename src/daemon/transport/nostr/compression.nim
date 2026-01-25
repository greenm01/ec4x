## Compression helpers for Nostr payloads
## Uses zstd for payload compression.
##
## Zstd provides better compression ratios and faster decompression
## than gzip, making it ideal for real-time game state sync.

import ../../../common/zstd

const
  ZstdMagic = "\x28\xB5\x2F\xFD"

proc isZstdPayload(payload: string): bool =
  if payload.len < ZstdMagic.len:
    return false
  for idx in 0 ..< ZstdMagic.len:
    if payload[idx] != ZstdMagic[idx]:
      return false
  true

proc compressPayload*(payload: string): string =
  ## Compress a binary payload using zstd
  let compressed = compress(payload)
  if compressed.len >= payload.len:
    return payload
  compressed

proc decompressPayload*(payload: string): string =
  ## Decompress a zstd payload back to binary
  if payload.len == 0:
    return ""
  if not isZstdPayload(payload):
    return payload
  try:
    decompress(payload)
  except ZstdError:
    payload
