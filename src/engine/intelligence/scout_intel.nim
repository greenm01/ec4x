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

import std/[tables, options, sequtils, strformat]
import types as intel_types
import ../gamestate, ../fleet, ../squadron, ../spacelift

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

      # Scout also gets spacelift cargo details
      var spaceliftDetails: seq[intel_types.SpaceLiftCargoIntel] = @[]
      for ship in fleet.spaceLiftShips:
        spaceliftDetails.add(intel_types.SpaceLiftCargoIntel(
          shipClass: $ship.shipClass,
          cargoType: if ship.cargo.quantity == 0: "Empty" else: $ship.cargo.cargoType,
          quantity: ship.cargo.quantity,
          isCrippled: ship.isCrippled
        ))

      let fleetIntel = intel_types.FleetIntel(
        fleetId: fleetId,
        owner: fleet.owner,
        location: systemId,
        shipCount: fleet.squadrons.len,
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

  # Get construction queue
  if colony.underConstruction.isSome:
    colonyIntel.constructionQueue.add(colony.underConstruction.get().itemId)

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

  # Generate scout encounter report for fleets
  let fleetEncounter = generateScoutFleetEncounter(state, scoutId, scoutOwner, systemId, turn)
  if fleetEncounter.isSome:
    state.houses[scoutOwner].intelligence.addScoutEncounter(fleetEncounter.get())

    # Update fleet movement history for each observed fleet
    for fleetIntel in fleetEncounter.get().fleetDetails:
      state.houses[scoutOwner].intelligence.updateFleetMovementHistory(
        fleetIntel.fleetId,
        fleetIntel.owner,
        systemId,
        turn
      )

  # Generate scout encounter report for colonies
  let colonyEncounter = generateScoutColonyObservation(state, scoutId, scoutOwner, systemId, turn)
  if colonyEncounter.isSome:
    state.houses[scoutOwner].intelligence.addScoutEncounter(colonyEncounter.get())

    # Update construction activity tracking
    let colonyDetails = colonyEncounter.get().colonyDetails.get()
    if systemId in state.colonies:
      let colony = state.colonies[systemId]
      state.houses[scoutOwner].intelligence.updateConstructionActivity(
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
    state.houses[scoutOwner].intelligence.addColonyReport(colonyDetails)
