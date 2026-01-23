## Join flow state helpers for TUI

import std/[options, os]
import kdl

import ../../daemon/transport/nostr/nip19
import ../../engine/types/[core, player_state as ps_types]
import ./delta_applicator

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
                     houseId: HouseId) =
  let cachePath = joinCachePath(dataDir, pubkey, gameId)
  let content = "join-cache game=\"" & gameId & "\" " &
    "house=(HouseId)" & $houseId.uint32 & " " &
    "pubkey=\"" & pubkey & "\"\n"
  writeFile(cachePath, content)

proc applyDeltaToCachedState*(
  dataDir: string,
  pubkey: string,
  gameId: string,
  state: var ps_types.PlayerState,
  deltaKdl: string
): Option[int32] =
  ## Apply a delta to a PlayerState. Returns the new turn number if successful.
  ## Note: This function no longer caches to the old format - use TuiCache instead.
  applyDeltaToPlayerState(state, deltaKdl)

proc parseFullStateKdl*(kdlState: string): Option[ps_types.PlayerState] =
  ## Parse a full state KDL document into a PlayerState
  applyFullStateKdl(kdlState)
