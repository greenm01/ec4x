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

import std/[tables, options, sequtils, strformat, strutils, random]
import types as intel_types
import ../gamestate, ../fleet, ../squadron, ../starmap

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
  rng: var Rand
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
        # Scouts can evade with ELI capability
        # Assume ELI level 3 for stealth (TODO: track actual ELI level)
        evaded = performStealthCheck(3, 5, rng)

      elif hasCloakedRaiders:
        # Cloaked raiders can evade
        # Raiders have high stealth (level 4)
        evaded = performStealthCheck(4, 5, rng)

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
    transitingFleets: transitingFleets,  # TODO: Track fleet movements
    combatDetected: @[],                 # TODO: Detect combat in adjacent systems
    bombardmentDetected: @[],            # TODO: Detect bombardment
    significantActivity: detectedFleets.len > 0,
    threatsDetected: detectedFleets.len
  )

  return some(report)

proc processAllStarbaseSurveillance*(state: var GameState, turn: int, rng: var Rand) =
  ## Process surveillance for ALL starbases in the game
  ## Called once per turn during intelligence phase

  for systemId, colony in state.colonies:
    if colony.starbases.len > 0:
      let surveillance = generateStarbaseSurveillance(state, systemId, colony.owner, turn, rng)

      if surveillance.isSome:
        state.houses[colony.owner].intelligence.addStarbaseSurveillance(surveillance.get())
