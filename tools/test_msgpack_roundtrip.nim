## Roundtrip test for custom msgpack pack/unpack procs on case objects.
import msgpack4nim
import ../src/engine/types/[core, ground_unit, capacity, tech, event,
  espionage, ship, prestige]
import ../src/common/msgpack_types
import std/options

# Test GroundUnitGarrison roundtrip
block:
  let a = GroundUnitGarrison(
    locationType: GroundUnitLocation.OnColony,
    colonyId: ColonyId(42)
  )
  let b = GroundUnitGarrison(
    locationType: GroundUnitLocation.OnTransport,
    shipId: ShipId(99)
  )
  let bufA = pack(a)
  let bufB = pack(b)
  var ra: GroundUnitGarrison
  var rb: GroundUnitGarrison
  unpack(bufA, ra)
  unpack(bufB, rb)
  assert ra.locationType == OnColony, "OnColony discriminant"
  assert ra.colonyId == ColonyId(42), "colonyId"
  assert rb.locationType == OnTransport, "OnTransport discriminant"
  assert rb.shipId == ShipId(99), "shipId"
  echo "GroundUnitGarrison: OK"

# Test EntityIdUnion roundtrip
block:
  let a = EntityIdUnion(
    kind: CapacityType.FighterSquadron,
    colonyId: ColonyId(7)
  )
  let b = EntityIdUnion(
    kind: CapacityType.FleetSize,
    fleetId: FleetId(3)
  )
  let c = EntityIdUnion(
    kind: CapacityType.C2Pool,
    houseId: HouseId(2)
  )
  var ra, rb, rc: EntityIdUnion
  unpack(pack(a), ra)
  unpack(pack(b), rb)
  unpack(pack(c), rc)
  assert ra.kind == CapacityType.FighterSquadron
  assert ra.colonyId == ColonyId(7)
  assert rb.kind == CapacityType.FleetSize
  assert rb.fleetId == FleetId(3)
  assert rc.kind == CapacityType.C2Pool
  assert rc.houseId == HouseId(2)
  echo "EntityIdUnion: OK"

# Test ResearchAdvancement roundtrip
block:
  let a = ResearchAdvancement(
    advancementType: AdvancementType.EconomicLevel,
    elFromLevel: 1,
    elToLevel: 2,
    elCost: 100,
    houseId: HouseId(1),
    prestigeEvent: none(PrestigeEvent)
  )
  let b = ResearchAdvancement(
    advancementType: AdvancementType.Technology,
    techField: TechField.WeaponsTech,
    techFromLevel: 0,
    techToLevel: 1,
    techCost: 50,
    houseId: HouseId(2),
    prestigeEvent: none(PrestigeEvent)
  )
  let c = ResearchAdvancement(
    advancementType: AdvancementType.ScienceLevel,
    slFromLevel: 3,
    slToLevel: 4,
    slCost: 200,
    houseId: HouseId(3),
    prestigeEvent: none(PrestigeEvent)
  )
  var ra, rb, rc: ResearchAdvancement
  unpack(pack(a), ra)
  unpack(pack(b), rb)
  unpack(pack(c), rc)
  assert ra.advancementType == AdvancementType.EconomicLevel
  assert ra.elFromLevel == 1 and ra.elToLevel == 2
  assert ra.houseId == HouseId(1)
  assert rb.advancementType == AdvancementType.Technology
  assert rb.techField == TechField.WeaponsTech
  assert rb.houseId == HouseId(2)
  assert rc.advancementType == AdvancementType.ScienceLevel
  assert rc.slFromLevel == 3 and rc.slToLevel == 4
  assert rc.houseId == HouseId(3)
  echo "ResearchAdvancement: OK"

# Test GameEvent roundtrip (multiple branches)
block:
  let evCmd = GameEvent(
    eventType: GameEventType.CommandRejected,
    turn: 2,
    houseId: some(HouseId(1)),
    systemId: none(SystemId),
    description: "colonize rejected",
    sourceHouseId: none(HouseId),
    targetHouseId: none(HouseId),
    targetSystemId: none(SystemId),
    success: some(false),
    detected: none(bool),
    details: none(string),
    fleetId: some(FleetId(5)),
    newOwner: none(HouseId),
    oldOwner: none(HouseId),
    orderType: some("Colonize"),
    reason: some("target already colonized")
  )
  let evColony = GameEvent(
    eventType: GameEventType.ColonyEstablished,
    turn: 1,
    houseId: some(HouseId(1)),
    systemId: some(SystemId(23)),
    description: "colony established",
    sourceHouseId: none(HouseId),
    targetHouseId: none(HouseId),
    targetSystemId: none(SystemId),
    success: some(true),
    detected: none(bool),
    details: none(string),
    fleetId: none(FleetId),
    newOwner: some(HouseId(1)),
    oldOwner: none(HouseId),
    colonyEventType: some("Established"),
    salvageValueColony: none(int),
    lostProjectType: none(string),
    lostProjectPP: none(int)
  )
  let evGen = GameEvent(
    eventType: GameEventType.General,
    turn: 1,
    houseId: none(HouseId),
    systemId: none(SystemId),
    description: "info",
    sourceHouseId: none(HouseId),
    targetHouseId: none(HouseId),
    targetSystemId: none(SystemId),
    success: none(bool),
    detected: none(bool),
    details: none(string),
    fleetId: none(FleetId),
    newOwner: none(HouseId),
    oldOwner: none(HouseId),
    message: "Turn 1 resolution complete"
  )
  let evHouseElim = GameEvent(
    eventType: GameEventType.HouseEliminated,
    turn: 5,
    houseId: some(HouseId(3)),
    systemId: none(SystemId),
    description: "house eliminated",
    sourceHouseId: none(HouseId),
    targetHouseId: none(HouseId),
    targetSystemId: none(SystemId),
    success: none(bool),
    detected: none(bool),
    details: none(string),
    fleetId: none(FleetId),
    newOwner: none(HouseId),
    oldOwner: none(HouseId),
    eliminatedBy: some(HouseId(1))
  )
  var ra, rb, rc, rd: GameEvent
  unpack(pack(evCmd), ra)
  unpack(pack(evColony), rb)
  unpack(pack(evGen), rc)
  unpack(pack(evHouseElim), rd)
  assert ra.eventType == GameEventType.CommandRejected
  assert ra.turn == 2
  assert ra.orderType == some("Colonize")
  assert ra.reason == some("target already colonized")
  assert ra.fleetId == some(FleetId(5))
  assert rb.eventType == GameEventType.ColonyEstablished
  assert rb.colonyEventType == some("Established")
  assert rb.newOwner == some(HouseId(1))
  assert rc.eventType == GameEventType.General
  assert rc.message == "Turn 1 resolution complete"
  assert rd.eventType == GameEventType.HouseEliminated
  assert rd.eliminatedBy == some(HouseId(1))
  echo "GameEvent: OK"

echo "All roundtrip tests passed!"
