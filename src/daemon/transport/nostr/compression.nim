## Compression helpers for Nostr payloads
## Uses zstd for payload compression.
##
## Zstd provides better compression ratios and faster decompression
## than gzip, making it ideal for real-time game state sync.

import ../../../common/zstd

proc compressPayload*(payload: string): string =
  ## Compress a binary payload using zstd
  compress(payload)

proc decompressPayload*(payload: string): string =
  ## Decompress a zstd payload back to binary
  decompress(payload)
