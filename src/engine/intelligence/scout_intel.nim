## Scout Intelligence Generation
##
## Scouts are elite intelligence gatherers that provide the most detailed reports
## They observe EVERYTHING: fleets, colonies, combat, bombardment, blockades, construction
##
## Scout advantages over standard visibility:
## - Detailed fleet composition (tech levels, hull integrity, cargo)
## - Construction progress tracking over time
## - Fleet movement pattern detection
## - Patrol route analysis
## - Witness events (combat, bombardment, blockades)

import std/[tables, options, strformat, random, hashes, sequtils]
import types as intel_types
import corruption
import ../gamestate, ../fleet, ../squadron, ../spacelift
import ../espionage/types as esp_types

proc generateScoutFleetEncounter*(
  state: GameState,
  scoutId: string,
  scoutOwner: HouseId,
  systemId: SystemId,
  turn: int
): Option[intel_types.ScoutEncounterReport] =
  ## Generate detailed scout report for fleet encounter
  ## Scouts provide COMPLETE intelligence on every fleet they encounter

  var fleetIntels: seq[intel_types.FleetIntel] = @[]
  var observedHouses: seq[HouseId] = @[]

  # Scan all fleets in the system
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId and fleet.owner != scoutOwner:
      # Scout gets PERFECT intel on fleet composition
      var squadDetails: seq[intel_types.SquadronIntel] = @[]
      for squadron in fleet.squadrons:
        squadDetails.add(intel_types.SquadronIntel(
          squadronId: squadron.id,
          shipClass: $squadron.flagship.shipClass,
          shipCount: 1 + squadron.ships.len,
          techLevel: squadron.flagship.stats.techLevel,
          hullIntegrity: if squadron.flagship.isCrippled: some(50) else: some(100)
        ))

      # Scout also gets Expansion/Auxiliary squadron cargo details
      var spaceliftDetails: seq[intel_types.SpaceLiftCargoIntel] = @[]
      for squadron in fleet.squadrons:
        if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
          let cargo = squadron.flagship.cargo
          let cargoQty = if cargo.isSome: cargo.get().quantity else: 0
          let cargoType = if cargo.isSome and cargoQty > 0:
                           $cargo.get().cargoType
                         else:
                           "Empty"
          spaceliftDetails.add(intel_types.SpaceLiftCargoIntel(
            shipClass: $squadron.flagship.shipClass,
            cargoType: cargoType,
            quantity: cargoQty,
            isCrippled: squadron.flagship.isCrippled
          ))

      let transportCount = fleet.squadrons.countIt(it.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary})
      let fleetIntel = intel_types.FleetIntel(
        fleetId: fleetId,
        owner: fleet.owner,
        location: systemId,
        shipCount: fleet.squadrons.len,
        standingOrders: some($fleet.status),  # Scout sees fleet behavior
        spaceLiftShipCount: some(transportCount),
        squadronDetails: some(squadDetails)
      )

      fleetIntels.add(fleetIntel)

      if fleet.owner notin observedHouses:
        observedHouses.add(fleet.owner)

  if fleetIntels.len == 0:
    return none(intel_types.ScoutEncounterReport)

  let description = &"Scout {scoutId} observed {fleetIntels.len} enemy fleet(s) at system {systemId}"

  return some(intel_types.ScoutEncounterReport(
    reportId: &"{scoutOwner}-scout-{scoutId}-{turn}-{systemId}",
    scoutId: scoutId,
    turn: turn,
    systemId: systemId,
    encounterType: intel_types.ScoutEncounterType.FleetSighting,
    observedHouses: observedHouses,
    fleetDetails: fleetIntels,
    colonyDetails: none(intel_types.ColonyIntelReport),
    fleetMovements: @[],
    description: description,
    significance: 7  # Fleet sighting is significant
  ))

proc generateScoutColonyObservation*(
  state: GameState,
  scoutId: string,
  scoutOwner: HouseId,
  systemId: SystemId,
  turn: int
): Option[intel_types.ScoutEncounterReport] =
  ## Generate detailed scout report for colony observation
  ## Scouts get complete colony intelligence with construction tracking

  if systemId notin state.colonies:
    return none(intel_types.ScoutEncounterReport)

  let colony = state.colonies[systemId]

  if colony.owner == scoutOwner:
    return none(intel_types.ScoutEncounterReport)  # Don't report on own colonies

  # Generate detailed colony intel (scouts get PERFECT quality)
  var colonyIntel = intel_types.ColonyIntelReport(
    colonyId: systemId,
    targetOwner: colony.owner,
    gatheredTurn: turn,
    quality: intel_types.IntelQuality.Perfect,  # Scouts get perfect intel
    population: colony.population,
    industry: colony.infrastructure,
    defenses: colony.armies + colony.marines + colony.groundBatteries,
    starbaseLevel: colony.starbases.len,
    constructionQueue: @[],
    grossOutput: none(int),
    taxRevenue: none(int),
    unassignedSquadronCount: colony.unassignedSquadrons.len,
    reserveFleetCount: 0,
    mothballedFleetCount: 0,
    shipyardCount: colony.shipyards.len
  )

  # Count reserve/mothballed fleets
  for fleet in state.fleets.values:
    if fleet.owner == colony.owner and fleet.location == systemId:
      if fleet.status == FleetStatus.Reserve:
        colonyIntel.reserveFleetCount += 1
      elif fleet.status == FleetStatus.Mothballed:
        colonyIntel.mothballedFleetCount += 1

  # Get economic data from latest income report (scouts get PERFECT intel)
  let targetHouse = state.houses[colony.owner]
  if targetHouse.latestIncomeReport.isSome:
    let incomeReport = targetHouse.latestIncomeReport.get()
    # Find this colony's data in the house income report
    for colonyReport in incomeReport.colonies:
      if colonyReport.colonyId == systemId:
        colonyIntel.grossOutput = some(colonyReport.grossOutput)
        colonyIntel.taxRevenue = some(colonyReport.netValue)
        break

  # Get construction queue (scouts get perfect intel on all queued projects)
  for project in colony.constructionQueue:
    colonyIntel.constructionQueue.add(project.itemId)
  # Also check legacy underConstruction field for backward compatibility
  if colony.underConstruction.isSome:
    let legacyItem = colony.underConstruction.get().itemId
    if legacyItem notin colonyIntel.constructionQueue:
      colonyIntel.constructionQueue.add(legacyItem)

  let description = &"Scout {scoutId} surveyed colony at system {systemId} (owner: {colony.owner})"

  let report = intel_types.ScoutEncounterReport(
    reportId: &"{scoutOwner}-scout-{scoutId}-{turn}-{systemId}",
    scoutId: scoutId,
    turn: turn,
    systemId: systemId,
    encounterType: intel_types.ScoutEncounterType.ColonyDiscovered,
    observedHouses: @[colony.owner],
    fleetDetails: @[],
    colonyDetails: some(colonyIntel),
    fleetMovements: @[],
    description: description,
    significance: 8  # Colony discovery is very significant
  )

  return some(report)

proc processScoutIntelligence*(
  state: var GameState,
  scoutId: string,
  scoutOwner: HouseId,
  systemId: SystemId
) =
  ## Process all intelligence gathering for a scout at a system
  ## This is called whenever a scout enters/observes a system
  ## Scouts automatically:
  ## 1. Generate detailed encounter reports
  ## 2. Update fleet movement history
  ## 3. Track construction activity
  ## 4. Update standard intel reports (colony/system/starbase)

  let turn = state.turn

  # Check if scout owner has corrupted intelligence (disinformation)
  let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, scoutOwner)
  var rng = initRand(turn xor hash(scoutOwner) xor int(systemId))  # Deterministic corruption per turn/house/system

  # Generate scout encounter report for fleets
  # CRITICAL: Get house once, modify intelligence, write back to persist
  var house = state.houses[scoutOwner]

  var fleetEncounter = generateScoutFleetEncounter(state, scoutId, scoutOwner, systemId, turn)
  if fleetEncounter.isSome:
    # Apply corruption if scout owner's intelligence is compromised
    if corruptionEffect.isSome:
      let magnitude = corruptionEffect.get().magnitude
      var corrupted = fleetEncounter.get()
      corrupted = corruption.corruptScoutEncounter(corrupted, magnitude, rng)
      house.intelligence.addScoutEncounter(corrupted)

      # Update fleet movement history (use corrupted data)
      for fleetIntel in corrupted.fleetDetails:
        house.intelligence.updateFleetMovementHistory(
          fleetIntel.fleetId,
          fleetIntel.owner,
          systemId,
          turn
        )
    else:
      house.intelligence.addScoutEncounter(fleetEncounter.get())

      # Update fleet movement history for each observed fleet
      for fleetIntel in fleetEncounter.get().fleetDetails:
        house.intelligence.updateFleetMovementHistory(
          fleetIntel.fleetId,
          fleetIntel.owner,
          systemId,
          turn
        )

  # Generate scout encounter report for colonies
  var colonyEncounter = generateScoutColonyObservation(state, scoutId, scoutOwner, systemId, turn)
  if colonyEncounter.isSome:
    # Apply corruption if scout owner's intelligence is compromised
    if corruptionEffect.isSome:
      let magnitude = corruptionEffect.get().magnitude
      var corrupted = colonyEncounter.get()
      corrupted = corruption.corruptScoutEncounter(corrupted, magnitude, rng)
      house.intelligence.addScoutEncounter(corrupted)
    else:
      house.intelligence.addScoutEncounter(colonyEncounter.get())

    # Update construction activity tracking
    let colonyDetails = colonyEncounter.get().colonyDetails.get()
    if systemId in state.colonies:
      let colony = state.colonies[systemId]
      house.intelligence.updateConstructionActivity(
        systemId,
        colony.owner,
        turn,
        colony.infrastructure,
        colony.shipyards.len,
        colony.spaceports.len,
        colony.starbases.len,
        colonyDetails.constructionQueue
      )

    # Also add to standard colony intel database
    house.intelligence.addColonyReport(colonyDetails)

  # Write back modified house to persist intelligence
  state.houses[scoutOwner] = house
