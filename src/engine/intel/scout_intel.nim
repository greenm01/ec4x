## Scout Intelligence Generation
##
## Scouts are elite intelligence gatherers that provide Spy-quality intelligence
## They observe: fleets, colonies, combat, bombardment, blockades, construction
##
## Scout advantages over standard visibility:
## - Spy-quality intelligence (construction queues, economic data, embarked fighters)
## - Detailed fleet composition (tech levels, hull integrity, cargo)
## - Construction progress tracking over time
## - Fleet movement pattern detection
## - Patrol route analysis
## - Witness events (combat, bombardment, blockades)

import std/[tables, options, strformat, random, hashes]
import ../types/[core, game_state, intel]
import corruption
import generator # Use refactored report generation functions

proc processScoutIntelligence*(
    state: GameState, scoutFleetId: FleetId, scoutOwner: HouseId, systemId: SystemId
) =
  ## Process all intelligence gathering for a scout at a system
  ## Scouts automatically generate Spy-quality intelligence:
  ## 1. System intel (fleets, squadrons, embarked fighters)
  ## 2. Colony intel (ground forces, construction queue, economic data)
  ## 3. Orbital intel (starbases, shipyards, fighters, guard/blockade fleets)
  ##
  ## Architecture: Uses generator.nim functions + Table read-modify-write pattern

  let turn = state.turn

  # Generate Spy-quality intelligence reports
  let systemIntel = generator.generateSystemIntelReport(
    state, scoutOwner, systemId, IntelQuality.Spy
  )

  let colonyIntel = generator.generateColonyIntelReport(
    state, scoutOwner, systemId, IntelQuality.Spy
  )

  let orbitalIntel = generator.generateOrbitalIntelReport(
    state, scoutOwner, systemId, IntelQuality.Spy
  )

  # Apply corruption if scout owner's intelligence is compromised (disinformation)
  let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, scoutOwner)
  var rng = initRand(turn xor hash(scoutOwner) xor int(systemId))

  # Store intelligence reports (Table read-modify-write pattern)
  if state.intelligence.contains(scoutOwner):
    var intel = state.intelligence[scoutOwner]

    # Store system intelligence (fleets and squadrons)
    if systemIntel.isSome:
      let package = systemIntel.get()

      # Apply corruption if compromised
      var report = package.report
      var fleetIntelData = package.fleetIntel
      var squadronIntelData = package.squadronIntel

      if corruptionEffect.isSome:
        let magnitude = corruptionEffect.get().magnitude
        report = corruption.corruptSystemIntel(report, magnitude, rng)

        for i in 0 ..< fleetIntelData.len:
          fleetIntelData[i].intel = corruption.corruptFleetIntel(
            fleetIntelData[i].intel, magnitude, rng
          )

        for i in 0 ..< squadronIntelData.len:
          squadronIntelData[i].intel = corruption.corruptSquadronIntel(
            squadronIntelData[i].intel, magnitude, rng
          )

      # Store reports
      intel.systemReports[systemId] = report

      # Store detailed fleet and squadron intel
      for (fleetId, fleetIntel) in fleetIntelData:
        intel.fleetIntel[fleetId] = fleetIntel

      for (squadronId, squadronIntel) in squadronIntelData:
        intel.squadronIntel[squadronId] = squadronIntel

      # Extract observed houses from fleet intel
      var observedHouses: seq[HouseId] = @[]
      for (_, fleetIntel) in fleetIntelData:
        if fleetIntel.owner notin observedHouses:
          observedHouses.add(fleetIntel.owner)

      # Create scout encounter report for tracking
      let scoutReport = ScoutEncounterReport(
        reportId: &"{scoutOwner}-scout-{scoutFleetId}-{turn}-{systemId}",
        fleetId: scoutFleetId,
        turn: turn,
        systemId: systemId,
        encounterType: ScoutEncounterType.FleetSighting,
        observedHouses: observedHouses,
        observedFleetIds: report.detectedFleetIds,
        colonyId: none(ColonyId),
        fleetMovements: @[],
        description:
          &"Scout fleet {scoutFleetId} surveyed system {systemId} - detected {report.detectedFleetIds.len} enemy fleet(s)",
        significance: int32(7), # Fleet sighting is significant
      )

      intel.scoutEncounters.add(scoutReport)

    # Store colony intelligence
    if colonyIntel.isSome:
      var report = colonyIntel.get()

      # Apply corruption if compromised
      if corruptionEffect.isSome:
        let magnitude = corruptionEffect.get().magnitude
        report = corruption.corruptColonyIntel(report, magnitude, rng)

      intel.colonyReports[report.colonyId] = report

      # Create scout encounter report for colony
      let scoutReport = ScoutEncounterReport(
        reportId: &"{scoutOwner}-scout-{scoutFleetId}-{turn}-{systemId}-colony",
        fleetId: scoutFleetId,
        turn: turn,
        systemId: systemId,
        encounterType: ScoutEncounterType.ColonyDiscovered,
        observedHouses: @[report.targetOwner],
        observedFleetIds: @[],
        colonyId: some(report.colonyId),
        fleetMovements: @[],
        description:
          &"Scout fleet {scoutFleetId} surveyed colony at {systemId} (owner: {report.targetOwner})",
        significance: int32(8), # Colony discovery is very significant
      )

      intel.scoutEncounters.add(scoutReport)

    # Store orbital intelligence
    if orbitalIntel.isSome:
      var report = orbitalIntel.get()

      # Apply corruption if compromised
      if corruptionEffect.isSome:
        let magnitude = corruptionEffect.get().magnitude
        report = corruption.corruptOrbitalIntel(report, magnitude, rng)

      intel.orbitalReports[report.colonyId] = report

    # Write back modified intelligence database
    state.intelligence[scoutOwner] = intel
