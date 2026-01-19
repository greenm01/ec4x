## Compression ratio checks for Nostr payloads.

import std/[os, unittest]
import ../../src/daemon/config
import ../../src/daemon/transport/nostr/compression
import kdl

const
  ConfigPath = "config/nostr.kdl"

suite "Nostr Compression Ratio":
  test "delta payload ratio meets threshold":
    if not fileExists(ConfigPath):
      skip()

    let cfg = parseNostrKdl(ConfigPath)
    let payload = "delta turn=1 { fleet-moved id=1 to=2 }"
    let compressed = compressPayload(payload)
    let ratio = compressed.len.float / payload.len.float

    check ratio <= 1.0
    check ratio >= cfg.compression_min_ratio

  test "full state payload stays under max":
    if not fileExists(ConfigPath):
      skip()

    let cfg = parseNostrKdl(ConfigPath)
    let payload = "state turn=1 { house id=1 name=\"Test\" }"
    let compressed = compressPayload(payload)

    check payload.len <= cfg.compression_max_raw_bytes
    check compressed.len <= cfg.compression_max_raw_bytes
    discard parseKdl(payload)
