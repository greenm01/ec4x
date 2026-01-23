## Player state snapshot persistence helpers
##
## Stores per-house PlayerState snapshots for delta generation.
## Migration: Switched from JSON to msgpack for faster serialization.

import std/[tables, base64]
import msgpack4nim
import ../../engine/types/player_state
import ../../engine/types/[core, colony, fleet, ship, ground_unit, diplomacy, progression]
import ./msgpack_state

# =============================================================================
# Snapshot Types
# =============================================================================

type
  HouseValue* = object
    houseId*: HouseId
    value*: int32

  HouseCount* = object
    houseId*: HouseId
    count*: int32

  RelationSnapshot* = object
    sourceHouse*: HouseId
    targetHouse*: HouseId
    state*: DiplomaticState

  PlayerStateSnapshot* = object
    viewingHouse*: HouseId
    turn*: int32
    ownColonies*: seq[Colony]
    ownFleets*: seq[Fleet]
    ownShips*: seq[Ship]
    ownGroundUnits*: seq[GroundUnit]
    visibleSystems*: seq[VisibleSystem]
    visibleColonies*: seq[VisibleColony]
    visibleFleets*: seq[VisibleFleet]
    housePrestige*: seq[HouseValue]
    houseColonyCounts*: seq[HouseCount]
    diplomaticRelations*: seq[RelationSnapshot]
    eliminatedHouses*: seq[HouseId]
    actProgression*: ActProgressionState

# =============================================================================
# Snapshot Conversion
# =============================================================================

proc snapshotFromPlayerState*(ps: PlayerState): PlayerStateSnapshot =
  result.viewingHouse = ps.viewingHouse
  result.turn = ps.turn
  result.ownColonies = ps.ownColonies
  result.ownFleets = ps.ownFleets
  result.ownShips = ps.ownShips
  result.ownGroundUnits = ps.ownGroundUnits
  for _, visibleSystem in ps.visibleSystems:
    result.visibleSystems.add(visibleSystem)
  result.visibleColonies = ps.visibleColonies
  result.visibleFleets = ps.visibleFleets
  for houseId, prestige in ps.housePrestige:
    result.housePrestige.add(HouseValue(houseId: houseId, value: prestige))
  for houseId, count in ps.houseColonyCounts:
    result.houseColonyCounts.add(HouseCount(houseId: houseId, count: count))
  for key, relation in ps.diplomaticRelations:
    result.diplomaticRelations.add(RelationSnapshot(
      sourceHouse: key[0],
      targetHouse: key[1],
      state: relation,
    ))
  result.eliminatedHouses = ps.eliminatedHouses
  result.actProgression = ps.actProgression

proc snapshotToMsgpack*(snapshot: PlayerStateSnapshot): string =
  ## Serialize PlayerStateSnapshot to msgpack binary
  ## Returns base64-encoded msgpack data for safe SQLite storage
  let binary = pack(snapshot)
  result = encode(binary)

proc snapshotFromMsgpack*(data: string): PlayerStateSnapshot =
  ## Deserialize PlayerStateSnapshot from msgpack binary
  ## Expects base64-encoded msgpack data
  let binary = decode(data)
  unpack(binary, PlayerStateSnapshot)
