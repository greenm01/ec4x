## Player state snapshot persistence helpers
##
## Stores per-house PlayerState snapshots for delta generation.
## Migration: Switched from JSON to msgpack for faster serialization.

import std/[tables, base64, options]
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

  HouseNameEntry* = object
    houseId*: HouseId
    name*: string

  RelationSnapshot* = object
    sourceHouse*: HouseId
    targetHouse*: HouseId
    state*: DiplomaticState

  LtuSystem* = object
    systemId*: SystemId
    turn*: int32

  LtuColony* = object
    colonyId*: ColonyId
    turn*: int32

  LtuFleet* = object
    fleetId*: FleetId
    turn*: int32

  PlayerStateSnapshot* = object
    viewingHouse*: HouseId
    turn*: int32
    homeworldSystemId*: Option[SystemId]
    treasuryBalance*: Option[int32]
    netIncome*: Option[int32]
    ownColonies*: seq[Colony]
    ownFleets*: seq[Fleet]
    ownShips*: seq[Ship]
    ownGroundUnits*: seq[GroundUnit]
    visibleSystems*: seq[VisibleSystem]
    visibleColonies*: seq[VisibleColony]
    visibleFleets*: seq[VisibleFleet]
    ltuSystems*: seq[LtuSystem]
    ltuColonies*: seq[LtuColony]
    ltuFleets*: seq[LtuFleet]
    housePrestige*: seq[HouseValue]
    houseColonyCounts*: seq[HouseCount]
    houseNames*: seq[HouseNameEntry]
    diplomaticRelations*: seq[RelationSnapshot]
    eliminatedHouses*: seq[HouseId]
    actProgression*: ActProgressionState

# =============================================================================
# Snapshot Conversion
# =============================================================================

proc snapshotFromPlayerState*(ps: PlayerState): PlayerStateSnapshot =
  result.viewingHouse = ps.viewingHouse
  result.turn = ps.turn
  result.homeworldSystemId = ps.homeworldSystemId
  result.treasuryBalance = ps.treasuryBalance
  result.netIncome = ps.netIncome
  result.ownColonies = ps.ownColonies
  result.ownFleets = ps.ownFleets
  result.ownShips = ps.ownShips
  result.ownGroundUnits = ps.ownGroundUnits
  for _, visibleSystem in ps.visibleSystems:
    result.visibleSystems.add(visibleSystem)
  result.visibleColonies = ps.visibleColonies
  result.visibleFleets = ps.visibleFleets
  for systemId, turn in ps.ltuSystems:
    result.ltuSystems.add(LtuSystem(systemId: systemId, turn: turn))
  for colonyId, turn in ps.ltuColonies:
    result.ltuColonies.add(LtuColony(colonyId: colonyId, turn: turn))
  for fleetId, turn in ps.ltuFleets:
    result.ltuFleets.add(LtuFleet(fleetId: fleetId, turn: turn))
  for houseId, prestige in ps.housePrestige:
    result.housePrestige.add(HouseValue(houseId: houseId, value: prestige))
  for houseId, count in ps.houseColonyCounts:
    result.houseColonyCounts.add(HouseCount(houseId: houseId, count: count))
  for houseId, name in ps.houseNames:
    result.houseNames.add(HouseNameEntry(houseId: houseId, name: name))
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
