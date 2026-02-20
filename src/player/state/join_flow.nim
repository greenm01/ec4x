## Join flow state helpers for TUI
##
## Provides join cache file operations for backward compatibility with
## legacy KDL join cache format.

import std/[options, os, strutils]

import ../../daemon/transport/nostr/nip19
import ../../engine/types/core

proc normalizePubkey*(pubkey: string): Option[string] =
  try:
    some(normalizeNostrPubkey(pubkey))
  except CatchableError:
    none(string)

proc joinCachePath(dataDir: string, pubkey: string, gameId: string): string =
  let playersDir = dataDir / "players" / pubkey / "games"
  createDir(playersDir)
  playersDir / (gameId & ".kdl")

proc writeJoinCache*(dataDir: string, pubkey: string, gameId: string,
                     houseId: HouseId, gameName: string = "") =
  ## Write legacy KDL join cache file for backward compatibility
  let cachePath = joinCachePath(dataDir, pubkey, gameId)
  var content = "join-cache game=\"" & gameId & "\" " &
    "house=(HouseId)" & $houseId.uint32 & " " &
    "pubkey=\"" & pubkey & "\""
  let normalizedName = gameName.strip()
  if normalizedName.len > 0:
    content &= " {\n"
    content &= "  name \"" & normalizedName & "\"\n"
    content &= "}\n"
  else:
    content &= "\n"
  writeFile(cachePath, content)
