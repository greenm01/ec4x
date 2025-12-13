## Starbase Surveillance System
##
## Starbases have advanced sensors that continuously monitor their sector
## Sector = starbase system ONLY (not adjacent systems)
##
## Detection Rules:
## - Standard fleets: Automatically detected
## - Scouts (ELI capability): Stealth roll required (ELI level vs detection)
## - Raiders (CLK capability): Stealth roll required (cloaked if successful)
## - Crippled starbases: No surveillance capability

import std/[tables, options, strutils, random, hashes]
import types as intel_types
import corruption
import ../gamestate, ../fleet, ../squadron
import ../espionage/types as esp_types
import ../resolution/[types as res_types]
import ../resolution/event_factory/[intelligence as event_factory]

proc performStealthCheck*(
  stealthLevel: int,
  sensorLevel: int = 5,  # Starbase default sensor level
  rng: var Rand
): bool =
  ## Roll for stealth detection
  ## Returns true if unit EVADES detection
  ##
  ## Stealth level: ELI tech level (1-5) or CLK capability
  ## Sensor level: Starbase sensor strength (default 5)
  ##
  ## Formula: d20 + stealthLevel vs 10 + sensorLevel
  ## Higher stealth level = better chance to evade

  let stealthRoll = rng.rand(1..20) + stealthLevel
  let detectionThreshold = 10 + sensorLevel

  return stealthRoll >= detectionThreshold

proc generateStarbaseSurveillance*(
  state: var GameState,
  starbaseSystemId: SystemId,
  starbaseOwner: HouseId,
  turn: int,
  rng: var Rand,
  events: var seq[res_types.GameEvent]
): Option[intel_types.StarbaseSurveillanceReport] =
  ## Generate surveillance report from starbase sensors
  ## Monitors starbase system ONLY (not adjacent systems)
  ## Applies stealth checks for scouts and raiders

  # Find starbase(s) at this system
  if starbaseSystemId notin state.colonies:
    return none(intel_types.StarbaseSurveillanceReport)

  let colony = state.colonies[starbaseSystemId]
  if colony.owner != starbaseOwner:
    return none(intel_types.StarbaseSurveillanceReport)

  if colony.starbases.len == 0:
    return none(intel_types.StarbaseSurveillanceReport)

  # Check if any starbase is operational (not crippled)
  var hasOperationalStarbase = false
  var starbaseId = ""
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      hasOperationalStarbase = true
      starbaseId = starbase.id
      break

  if not hasOperationalStarbase:
    return none(intel_types.StarbaseSurveillanceReport)  # Crippled starbases can't surveil

  # Get surveillance sector (own system ONLY)
  var surveillanceSector: seq[SystemId] = @[starbaseSystemId]

  var detectedFleets: seq[tuple[fleetId: FleetId, location: SystemId, owner: HouseId, shipCount: int]] = @[]
  var undetectedFleets: seq[FleetId] = @[]
  var transitingFleets: seq[tuple[fleetId: FleetId, fromSystem: SystemId, toSystem: SystemId]] = @[]

  # Scan all fleets in surveillance sector
  for fleetId, fleet in state.fleets:
    if fleet.location in surveillanceSector and fleet.owner != starbaseOwner:
      # Check if fleet has stealth capability
      var hasScouts = false
      var hasCloakedRaiders = false

      for squadron in fleet.squadrons:
        # Check for scouts (ELI capability)
        if squadron.flagship.stats.specialCapability.startsWith("ELI") and not squadron.flagship.isCrippled:
          hasScouts = true

        # Check for raiders (CLK capability)
        if squadron.flagship.stats.specialCapability.startsWith("CLK") and not squadron.flagship.isCrippled:
          hasCloakedRaiders = true

      # Determine if fleet evades detection
      var evaded = false

      if hasScouts:
        # Scouts can evade with ELI capability (house-level tech)
        let fleetOwnerHouse = state.houses[fleet.owner]
        let scoutELI = fleetOwnerHouse.techTree.levels.electronicIntelligence
        evaded = performStealthCheck(scoutELI, 5, rng)

      elif hasCloakedRaiders:
        # Cloaked raiders can evade (house-level CLK tech)
        let fleetOwnerHouse = state.houses[fleet.owner]
        let raiderCLK = fleetOwnerHouse.techTree.levels.cloakingTech
        evaded = performStealthCheck(raiderCLK, 5, rng)

      if evaded:
        undetectedFleets.add(fleetId)
      else:
        # Fleet detected
        detectedFleets.add((
          fleetId: fleetId,
          location: fleet.location,
          owner: fleet.owner,
          shipCount: fleet.squadrons.len
        ))

  # Generate report if there's significant activity
  if detectedFleets.len == 0:
    return none(intel_types.StarbaseSurveillanceReport)

  let report = intel_types.StarbaseSurveillanceReport(
    starbaseId: starbaseId,
    systemId: starbaseSystemId,
    owner: starbaseOwner,
    turn: turn,
    detectedFleets: detectedFleets,
    undetectedFleets: undetectedFleets,
    transitingFleets: transitingFleets,  # Future: Track fleet movements between systems
    combatDetected: @[],                 # Future: Detect combat in adjacent systems
    bombardmentDetected: @[],            # Future: Detect bombardment operations
    significantActivity: detectedFleets.len > 0,
    threatsDetected: detectedFleets.len
  )

  # Generate StarbaseSurveillanceDetection event for diagnostics
  events.add(event_factory.starbaseSurveillanceDetection(
    starbaseId = starbaseId,
    owner = starbaseOwner,
    systemId = starbaseSystemId,
    detectedCount = detectedFleets.len,
    undetectedCount = undetectedFleets.len
  ))

  return some(report)

proc processAllStarbaseSurveillance*(
  state: var GameState,
  turn: int,
  rng: var Rand,
  events: var seq[res_types.GameEvent]
) =
  ## Process surveillance for ALL starbases in the game
  ## Called once per turn during intelligence phase

  for systemId, colony in state.colonies:
    if colony.starbases.len > 0:
      var surveillance = generateStarbaseSurveillance(state, systemId, colony.owner, turn, rng, events)

      if surveillance.isSome:
        # Apply corruption if starbase owner's intelligence is compromised (disinformation)
        let corruptionEffect = corruption.hasIntelCorruption(state.ongoingEffects, colony.owner)

        if corruptionEffect.isSome:
          var corruptionRng = initRand(turn xor hash(colony.owner) xor int(systemId))
          var report = surveillance.get()
          let magnitude = corruptionEffect.get().magnitude

          # Corrupt detected fleet data (tuples -> corrupted tuples)
          var corruptedDetected: seq[tuple[fleetId: FleetId, location: SystemId, owner: HouseId, shipCount: int]] = @[]
          for fleet in report.detectedFleets:
            let corruptedCount = corruption.corruptInt(fleet.shipCount, magnitude, corruptionRng)
            corruptedDetected.add((
              fleetId: fleet.fleetId,
              location: fleet.location,
              owner: fleet.owner,
              shipCount: corruptedCount
            ))
          report.detectedFleets = corruptedDetected

          # CRITICAL: Get, modify, write back to persist
          var house = state.houses[colony.owner]
          house.intelligence.addStarbaseSurveillance(report)
          state.houses[colony.owner] = house
        else:
          # CRITICAL: Get, modify, write back to persist
          var house = state.houses[colony.owner]
          house.intelligence.addStarbaseSurveillance(surveillance.get())
          state.houses[colony.owner] = house
