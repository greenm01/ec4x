## Minimal zstd compression bindings
##
## Wraps the zstd C library for simple single-shot compression/decompression.
## Uses the system libzstd (install via: apt install libzstd-dev)

{.passL: "-lzstd".}

const
  ZSTD_CONTENTSIZE_UNKNOWN* = high(uint64)
  ZSTD_CONTENTSIZE_ERROR* = high(uint64) - 1

# Core functions from zstd.h
proc ZSTD_compress(
  dst: pointer, dstCapacity: csize_t,
  src: pointer, srcSize: csize_t,
  compressionLevel: cint
): csize_t {.cdecl, importc.}

proc ZSTD_decompress(
  dst: pointer, dstCapacity: csize_t,
  src: pointer, compressedSize: csize_t
): csize_t {.cdecl, importc.}

proc ZSTD_compressBound(srcSize: csize_t): csize_t {.cdecl, importc.}

proc ZSTD_getFrameContentSize(
  src: pointer, srcSize: csize_t
): culonglong {.cdecl, importc.}

proc ZSTD_isError(code: csize_t): cuint {.cdecl, importc.}

proc ZSTD_getErrorName(code: csize_t): cstring {.cdecl, importc.}

# =============================================================================
# High-level Nim API
# =============================================================================

type
  ZstdError* = object of CatchableError

proc compress*(data: string, level: int = 3): string =
  ## Compress data using zstd
  ## Level 1-22, default 3 (good balance of speed/compression)
  if data.len == 0:
    return ""
    
  let maxSize = ZSTD_compressBound(data.len.csize_t)
  result = newString(maxSize)
  
  let compressedSize = ZSTD_compress(
    addr result[0], maxSize,
    unsafeAddr data[0], data.len.csize_t,
    level.cint
  )
  
  if ZSTD_isError(compressedSize) != 0:
    raise newException(ZstdError,
      "Zstd compression failed: " & $ZSTD_getErrorName(compressedSize))
  
  result.setLen(compressedSize)

proc decompress*(data: string): string =
  ## Decompress zstd-compressed data
  if data.len == 0:
    return ""
    
  # Get decompressed size from frame header
  let frameSize = ZSTD_getFrameContentSize(
    unsafeAddr data[0], data.len.csize_t
  )
  
  if frameSize == ZSTD_CONTENTSIZE_ERROR:
    raise newException(ZstdError, "Invalid zstd frame")
  
  if frameSize == ZSTD_CONTENTSIZE_UNKNOWN:
    # Fallback: allocate progressively larger buffers
    # For EC4X payloads, this shouldn't happen (single-frame compression)
    raise newException(ZstdError,
      "Unknown content size (streaming frames not supported)")
  
  result = newString(frameSize)
  
  let decompressedSize = ZSTD_decompress(
    addr result[0], frameSize.csize_t,
    unsafeAddr data[0], data.len.csize_t
  )
  
  if ZSTD_isError(decompressedSize) != 0:
    raise newException(ZstdError,
      "Zstd decompression failed: " & $ZSTD_getErrorName(decompressedSize))
  
  result.setLen(decompressedSize)
