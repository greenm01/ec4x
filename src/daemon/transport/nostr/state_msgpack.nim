## PlayerState msgpack serialization for Nostr transport (30405)
##
## Serializes PlayerState to msgpack binary for wire transmission.
## Uses shared pack/unpack procs from common/msgpack_types.

import msgpack4nim
import ../../../engine/types/[core, player_state, game_state]
import ../../../engine/state/fog_of_war
import ../../../common/msgpack_types
export msgpack_types

# =============================================================================
# Full State Serialization
# =============================================================================

proc serializePlayerState*(state: PlayerState): string =
  ## Serialize PlayerState to msgpack binary (as string for wire)
  pack(state)

proc deserializePlayerState*(data: string): PlayerState =
  ## Deserialize msgpack binary to PlayerState
  unpack(data, PlayerState)

proc formatPlayerStateMsgpack*(
  gameId: string,
  state: GameState,
  houseId: HouseId
): string =
  ## Create fog-of-war filtered PlayerState and serialize to msgpack
  ## Returns raw binary string (not base64 encoded - wire.nim handles encoding)
  let playerState = createPlayerState(state, houseId)
  serializePlayerState(playerState)
