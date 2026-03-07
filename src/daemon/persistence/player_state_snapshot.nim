## Player state snapshot persistence helpers
##
## Stores per-house PlayerState snapshots for delta generation.
## Migration: Switched from JSON to msgpack for faster serialization.

import std/[algorithm, base64, options, strutils, tables]
import msgpack4nim
import nimcrypto/sha2
import ../../engine/types/player_state
import ../../engine/types/[core, colony, fleet, ship, ground_unit, diplomacy,
  progression, tech, event, facilities]
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
    ebpPool*: Option[int32]
    cipPool*: Option[int32]
    netIncome*: Option[int32]
    taxRate*: Option[int32]
    techLevels*: Option[TechLevel]
    researchPoints*: Option[ResearchPoints]
    ownColonies*: seq[Colony]
    ownFleets*: seq[Fleet]
    ownShips*: seq[Ship]
    ownGroundUnits*: seq[GroundUnit]
    ownNeorias*: seq[Neoria]
    ownKastras*: seq[Kastra]
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
    pendingProposals*: seq[PendingProposal]
    eliminatedHouses*: seq[HouseId]
    actProgression*: ActProgressionState
    turnEvents*: seq[GameEvent]

# =============================================================================
# Snapshot Conversion
# =============================================================================

proc snapshotFromPlayerState*(ps: PlayerState): PlayerStateSnapshot =
  result.viewingHouse = ps.viewingHouse
  result.turn = ps.turn
  result.homeworldSystemId = ps.homeworldSystemId
  result.treasuryBalance = ps.treasuryBalance
  result.ebpPool = ps.ebpPool
  result.cipPool = ps.cipPool
  result.netIncome = ps.netIncome
  result.taxRate = ps.taxRate
  result.techLevels = ps.techLevels
  result.researchPoints = ps.researchPoints
  result.ownColonies = ps.ownColonies
  result.ownFleets = ps.ownFleets
  result.ownShips = ps.ownShips
  result.ownGroundUnits = ps.ownGroundUnits
  result.ownNeorias = ps.ownNeorias
  result.ownKastras = ps.ownKastras
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
  result.pendingProposals = ps.pendingProposals
  result.eliminatedHouses = ps.eliminatedHouses
  result.actProgression = ps.actProgression
  result.turnEvents = ps.turnEvents

proc normalizeSnapshot(snapshot: PlayerStateSnapshot): PlayerStateSnapshot =
  result = snapshot
  result.ownColonies.sort(
    proc(a, b: Colony): int = cmp(a.id.uint32, b.id.uint32)
  )
  result.ownFleets.sort(
    proc(a, b: Fleet): int = cmp(a.id.uint32, b.id.uint32)
  )
  result.ownShips.sort(
    proc(a, b: Ship): int = cmp(a.id.uint32, b.id.uint32)
  )
  result.ownGroundUnits.sort(
    proc(a, b: GroundUnit): int = cmp(a.id.uint32, b.id.uint32)
  )
  result.ownNeorias.sort(
    proc(a, b: Neoria): int = cmp(a.id.uint32, b.id.uint32)
  )
  result.ownKastras.sort(
    proc(a, b: Kastra): int = cmp(a.id.uint32, b.id.uint32)
  )
  result.visibleSystems.sort(
    proc(a, b: VisibleSystem): int = cmp(a.systemId.uint32, b.systemId.uint32)
  )
  result.visibleColonies.sort(
    proc(a, b: VisibleColony): int = cmp(a.colonyId.uint32, b.colonyId.uint32)
  )
  result.visibleFleets.sort(
    proc(a, b: VisibleFleet): int = cmp(a.fleetId.uint32, b.fleetId.uint32)
  )
  result.ltuSystems.sort(
    proc(a, b: LtuSystem): int = cmp(a.systemId.uint32, b.systemId.uint32)
  )
  result.ltuColonies.sort(
    proc(a, b: LtuColony): int = cmp(a.colonyId.uint32, b.colonyId.uint32)
  )
  result.ltuFleets.sort(
    proc(a, b: LtuFleet): int = cmp(a.fleetId.uint32, b.fleetId.uint32)
  )
  result.housePrestige.sort(
    proc(a, b: HouseValue): int = cmp(a.houseId.uint32, b.houseId.uint32)
  )
  result.houseColonyCounts.sort(
    proc(a, b: HouseCount): int = cmp(a.houseId.uint32, b.houseId.uint32)
  )
  result.houseNames.sort(
    proc(a, b: HouseNameEntry): int = cmp(a.houseId.uint32, b.houseId.uint32)
  )
  result.diplomaticRelations.sort(
    proc(a, b: RelationSnapshot): int =
      result = cmp(a.sourceHouse.uint32, b.sourceHouse.uint32)
      if result == 0:
        result = cmp(a.targetHouse.uint32, b.targetHouse.uint32)
  )
  result.pendingProposals.sort(
    proc(a, b: PendingProposal): int = cmp(a.id.uint32, b.id.uint32)
  )
  result.eliminatedHouses.sort(
    proc(a, b: HouseId): int = cmp(a.uint32, b.uint32)
  )

proc sha256Hex(data: string): string =
  let digest = sha256.digest(data)
  var hexValue = newStringOfCap(64)
  for value in digest.data:
    hexValue.add(value.toHex(2).toLowerAscii())
  hexValue

proc computePlayerStateHash*(snapshot: PlayerStateSnapshot): string =
  let normalized = normalizeSnapshot(snapshot)
  sha256Hex(pack(normalized))

proc computePlayerStateHash*(ps: PlayerState): string =
  computePlayerStateHash(snapshotFromPlayerState(ps))

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
