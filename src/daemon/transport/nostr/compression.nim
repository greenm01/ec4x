## Compression helpers for Nostr payloads
## Uses zippy (gzip) for payload compression.

import zippy

const
  DefaultFormat = dfGzip

proc compressPayload*(payload: string): string =
  ## Compress a KDL payload into gzip bytes (binary string)
  compress(payload, dataFormat = DefaultFormat)

proc decompressPayload*(payload: string): string =
  ## Decompress a gzip payload into KDL string
  uncompress(payload, dataFormat = DefaultFormat)
