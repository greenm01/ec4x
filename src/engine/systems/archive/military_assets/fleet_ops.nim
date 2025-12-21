## Fleet Operations for EC4X
##
## This module contains logic related to fleet management, such as adding/removing
## squadrons, checking fleet capabilities, and balancing squadrons.

import std/[algorithm, strutils, options]
import ../../types/military/[fleet_types, squadron_types, ship_types]
import ../../systems/military_assets/squadron_ops # For SquadronType
import ../../../common/types/[core, combat]

proc newFleet*(squadrons: seq[Squadron] = @[],
               id: FleetId = "", owner: HouseId = "", location: SystemId = 0,
               status: FleetStatus = FleetStatus.Active,
               autoBalanceSquadrons: bool = true): Fleet =
  Fleet(id: id, squadrons: squadrons,
        owner: owner, location: location, status: status,
        autoBalanceSquadrons: autoBalanceSquadrons,
        missionState: FleetMissionState.None,
        missionType: none(int),
        missionTarget: none(SystemId),
        missionStartTurn: 0)

proc `$`*(f: Fleet): string =
  if f.squadrons.len == 0:
    "Empty Fleet"
  else:
    var shipClasses: seq[string] = @[]
    for sq in f.squadrons:
      let status = if sq.flagship.isCrippled: "*" else: ""
      let typeTag = case sq.squadronType
        of SquadronType.Expansion: "[E]"
        of SquadronType.Auxiliary: "[A]"
        of SquadronType.Intel: "[I]"
        of SquadronType.Fighter: "[F]"
        else: ""
      shipClasses.add($sq.flagship.shipClass & status & typeTag)
    "Fleet[" & $f.squadrons.len & " squadrons: " & shipClasses.join(", ") & "]"

proc len*(f: Fleet): int =
  f.squadrons.len

proc isEmpty*(f: Fleet): bool =
  f.squadrons.len == 0

proc hasIntelSquadrons*(f: Fleet): bool =
  for sq in f.squadrons:
    if sq.squadronType == SquadronType.Intel:
      return true
  return false

proc hasNonIntelSquadrons*(f: Fleet): bool =
  for sq in f.squadrons:
    if sq.squadronType != SquadronType.Intel:
      return true
  return false

proc canAddSquadron*(f: Fleet, squadron: Squadron): tuple[canAdd: bool, reason: string] =
  if f.squadrons.len == 0:
    return (canAdd: true, reason: "")
  let isIntelSquadron = squadron.squadronType == SquadronType.Intel
  let fleetHasIntel = f.hasIntelSquadrons()
  let fleetHasNonIntel = f.hasNonIntelSquadrons()
  if isIntelSquadron and fleetHasNonIntel:
    return (canAdd: false, reason: "Cannot add Intel squadron to fleet with non-Intel squadrons")
  if not isIntelSquadron and fleetHasIntel:
    return (canAdd: false, reason: "Cannot add non-Intel squadron to Intel-only fleet")
  return (canAdd: true, reason: "")

proc add*(f: var Fleet, squadron: Squadron) =
  let validation = f.canAddSquadron(squadron)
  if not validation.canAdd:
    raise newException(ValueError,
      "Fleet composition violation: " & validation.reason &
      " (fleet: " & f.id & ", squadron: " & $squadron.flagship.shipClass & ")")
  f.squadrons.add(squadron)

proc remove*(f: var Fleet, index: int) =
  if index >= 0 and index < f.squadrons.len:
    f.squadrons.delete(index)

proc clear*(f: var Fleet) =
  f.squadrons.setLen(0)

proc canTraverse*(f: Fleet, laneType: LaneType): bool =
  case laneType
  of LaneType.Restricted:
    for sq in f.squadrons:
      if sq.flagship.isCrippled:
        return false
      if sq.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
        return false
    return true
  else:
    true

proc combatStrength*(f: Fleet): int =
  result = 0
  for sq in f.squadrons:
    result += sq.combatStrength()

proc isCloaked*(f: Fleet): bool =
  if f.squadrons.len == 0:
    return false
  for sq in f.squadrons:
    let raiders = sq.raiderShips()
    for raider in raiders:
      if not raider.isCrippled:
        return true
  return false

proc transportCapacity*(f: Fleet): int =
  result = 0
  for sq in f.squadrons:
    if sq.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
      if not sq.flagship.isCrippled:
        result += 1

proc hasCombatShips*(f: Fleet): bool =
  for sq in f.squadrons:
    if sq.combatStrength() > 0:
      return true
  return false

proc hasTransportShips*(f: Fleet): bool =
  for sq in f.squadrons:
    if sq.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
      if not sq.flagship.isCrippled:
        return true
  return false

proc isScoutOnly*(f: Fleet): bool =
  if f.squadrons.len == 0:
    return false
  for sq in f.squadrons:
    if sq.flagship.shipClass != ShipClass.Scout:
      return false
  return true

proc hasScouts*(f: Fleet): bool =
  for sq in f.squadrons:
    if sq.flagship.shipClass == ShipClass.Scout:
      return true
  return false

proc countScoutSquadrons*(f: Fleet): int =
  result = 0
  for sq in f.squadrons:
    if sq.flagship.shipClass == ShipClass.Scout:
      result += 1

proc hasCombatSquadrons*(f: Fleet): bool =
  for sq in f.squadrons:
    if sq.flagship.shipClass != ShipClass.Scout:
      return true
  return false

proc canMergeWith*(f1: Fleet, f2: Fleet): tuple[canMerge: bool, reason: string] =
  let f1HasIntel = f1.hasIntelSquadrons()
  let f2HasIntel = f2.hasIntelSquadrons()
  let f1HasNonIntel = f1.hasNonIntelSquadrons()
  let f2HasNonIntel = f2.hasNonIntelSquadrons()
  if (f1HasIntel and f2HasNonIntel) or (f1HasNonIntel and f2HasIntel):
    return (false, "Intel squadrons cannot be mixed with other squadron types")
  return (true, "")

proc combatSquadrons*(f: Fleet): seq[Squadron] =
  result = @[]
  for sq in f.squadrons:
    if sq.combatStrength() > 0:
      result.add(sq)

proc expansionSquadrons*(f: Fleet): seq[Squadron] =
  result = @[]
  for sq in f.squadrons:
    if sq.squadronType == SquadronType.Expansion:
      result.add(sq)

proc auxiliarySquadrons*(f: Fleet): seq[Squadron] =
  result = @[]
  for sq in f.squadrons:
    if sq.squadronType == SquadronType.Auxiliary:
      result.add(sq)

proc crippledSquadrons*(f: Fleet): seq[Squadron] =
  result = @[]
  for sq in f.squadrons:
    if sq.flagship.isCrippled:
      result.add(sq)

proc effectiveSquadrons*(f: Fleet): seq[Squadron] =
  result = @[]
  for sq in f.squadrons:
    if not sq.flagship.isCrippled:
      result.add(sq)

proc merge*(f1: var Fleet, f2: Fleet) =
  f1.squadrons.add(f2.squadrons)

proc split*(f: var Fleet, indices: seq[int]): Fleet =
  var newSquadrons: seq[Squadron] = @[]
  var toRemove: seq[int] = @[]
  for i in indices:
    if i >= 0 and i < f.squadrons.len:
      newSquadrons.add(f.squadrons[i])
      toRemove.add(i)
  for i in toRemove.sorted(Descending):
    f.squadrons.delete(i)
  newFleet(newSquadrons)

proc balanceSquadrons*(f: var Fleet) =
  if f.squadrons.len < 2:
    return
  var minEscorts = 999999
  var maxEscorts = 0
  for sq in f.squadrons:
    let escortCount = sq.ships.len
    if escortCount < minEscorts:
      minEscorts = escortCount
    if escortCount > maxEscorts:
      maxEscorts = escortCount
  if maxEscorts - minEscorts <= 1:
    return
  var allEscorts: seq[Ship] = @[]
  for i in 0..<f.squadrons.len:
    allEscorts.add(f.squadrons[i].ships)
    f.squadrons[i].ships = @[]
  if allEscorts.len == 0:
    return
  allEscorts.sort do (a, b: Ship) -> int:
    result = cmp(b.stats.commandCost, a.stats.commandCost)
  for escort in allEscorts:
    var bestSquadronIdx = -1
    var bestCapacity = -1
    for i in 0..<f.squadrons.len:
      let availableCapacity = f.squadrons[i].availableCommandCapacity()
      if availableCapacity >= escort.stats.commandCost:
        if availableCapacity > bestCapacity:
          bestCapacity = availableCapacity
          bestSquadronIdx = i
    if bestSquadronIdx >= 0:
      discard f.squadrons[bestSquadronIdx].addShip(escort)
    else:
      var maxCapacityIdx = 0
      var maxCapacity = f.squadrons[0].availableCommandCapacity()
      for i in 1..<f.squadrons.len:
        let cap = f.squadrons[i].availableCommandCapacity()
        if cap > maxCapacity:
          maxCapacity = cap
          maxCapacityIdx = i
      f.squadrons[maxCapacityIdx].ships.add(escort)

proc getAllShips*(f: Fleet): seq[Ship] =
  result = @[]
  for sq in f.squadrons:
    result.add(sq.flagship)
    for ship in sq.ships:
      result.add(ship)

proc translateShipIndicesToSquadrons*(f: Fleet, indices: seq[int]): seq[int] =
  var shipIndexToSquadron: seq[int] = @[]
  for sqIdx, sq in f.squadrons:
    shipIndexToSquadron.add(sqIdx)
    for _ in sq.ships:
      shipIndexToSquadron.add(sqIdx)
  var squadronsToRemove: seq[bool] = newSeq[bool](f.squadrons.len)
  for idx in indices:
    if idx < shipIndexToSquadron.len:
      let sqIdx = shipIndexToSquadron[idx]
      squadronsToRemove[sqIdx] = true
  result = @[]
  for sqIdx in 0..<f.squadrons.len:
    if squadronsToRemove[sqIdx]:
      result.add(sqIdx)
