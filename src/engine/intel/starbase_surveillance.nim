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

import std/[options, random, hashes, tables]
import ../types/[core, game_state, intel, ship, combat]
import ../state/[engine as state_helpers, iterators]
import corruption

proc performStealthCheck*(
    stealthLevel: int,
    sensorLevel: int = 5, # Starbase default sensor level
    rng: var Rand,
): bool =
  ## Roll for stealth detection
  ## Returns true if unit EVADES detection
  ##
  ## Stealth level: ELI tech level (1-5) or CLK capability
  ## Sensor level: Starbase sensor strength (default 5)
  ##
  ## Formula: d20 + stealthLevel vs 10 + sensorLevel
  ## Higher stealth level = better chance to evade

  let stealthRoll = rng.rand(1 .. 20) + stealthLevel
  let detectionThreshold = 10 + sensorLevel

  return stealthRoll >= detectionThreshold

proc generateStarbaseSurveillance*(
    state: GameState,
    starbaseSystemId: SystemId,
    starbaseOwner: HouseId,
    turn: int32,
    rng: var Rand,
): Option[StarbaseSurveillanceReport] =
  ## Generate surveillance report from starbase sensors
  ## Monitors starbase system ONLY (not adjacent systems)
  ## Applies stealth checks for scouts and raiders

  # Find starbase(s) at this system using safe accessor
  let colonyOpt = state_helpers.colonyBySystem(state, starbaseSystemId)
  if colonyOpt.isNone:
    return none(StarbaseSurveillanceReport)

  let colony = colonyOpt.get()
  if colony.owner != starbaseOwner:
    return none(StarbaseSurveillanceReport)

  if colony.starbaseIds.len == 0:
    return none(StarbaseSurveillanceReport)

  # Check if any starbase is operational (not crippled)
  var hasOperationalStarbase = false
  var operationalStarbaseId = StarbaseId(0)
  for starbaseId in colony.starbaseIds:
    let starbaseOpt = state_helpers.starbase(state, starbaseId)
    if starbaseOpt.isSome:
      let starbase = starbaseOpt.get()
      if starbase.state != CombatState.Crippled:
        hasOperationalStarbase = true
        operationalStarbaseId = starbaseId
        break

  if not hasOperationalStarbase:
    return none(StarbaseSurveillanceReport) # Crippled starbases can't surveil

  # Surveillance sector is own system ONLY (not adjacent systems)
  var detectedFleets:
    seq[tuple[fleetId: FleetId, location: SystemId, owner: HouseId, shipCount: int32]] =
    @[]
  var undetectedFleets: seq[FleetId] = @[]
  var transitingFleets:
    seq[tuple[fleetId: FleetId, fromSystem: SystemId, toSystem: SystemId]] = @[]

  # Scan all fleets in surveillance sector using iterator
  for fleet in state.fleetsAtSystem(starbaseSystemId):
    if fleet.houseId != starbaseOwner:
      # Check if fleet has stealth capability
      var hasScouts = false
      var hasCloakedRaiders = false

      # Check each squadron in the fleet
      for squadronId in fleet.squadrons:
        let squadronOpt = state_helpers.squadrons(state, squadronId)
        if squadronOpt.isNone:
          continue

        let squadron = squadronOpt.get()
        let flagshipOpt = state_helpers.ship(state, squadron.flagshipId)
        if flagshipOpt.isNone:
          continue

        let flagship = flagshipOpt.get()

        # Check for scouts (ELI capability)
        if flagship.shipClass == ShipClass.Scout and flagship.state != CombatState.Crippled:
          hasScouts = true

        # Check for raiders (CLK capability)
        if flagship.shipClass == ShipClass.Raider and flagship.state != CombatState.Crippled:
          hasCloakedRaiders = true

      # Determine if fleet evades detection
      var evaded = false

      if hasScouts:
        # Scouts can evade with ELI capability (house-level tech)
        let fleetOwnerHouseOpt = state_helpers.house(state, fleet.houseId)
        if fleetOwnerHouseOpt.isSome:
          let fleetOwnerHouse = fleetOwnerHouseOpt.get()
          let scoutELI = fleetOwnerHouse.techTree.levels.eli
          evaded = performStealthCheck(int(scoutELI), 5, rng)
      elif hasCloakedRaiders:
        # Cloaked raiders can evade (house-level CLK tech)
        let fleetOwnerHouseOpt = state_helpers.house(state, fleet.houseId)
        if fleetOwnerHouseOpt.isSome:
          let fleetOwnerHouse = fleetOwnerHouseOpt.get()
          let raiderCLK = fleetOwnerHouse.techTree.levels.clk
          evaded = performStealthCheck(int(raiderCLK), 5, rng)

      if evaded:
        undetectedFleets.add(fleet.id)
      else:
        # Fleet detected
        detectedFleets.add(
          (
            fleetId: fleet.id,
            location: fleet.location,
            owner: fleet.houseId,
            shipCount: int32(fleet.squadrons.len),
          )
        )

  # Generate report if there's significant activity
  if detectedFleets.len == 0:
    return none(StarbaseSurveillanceReport)

  let report = StarbaseSurveillanceReport(
    starbaseId: operationalStarbaseId,
    systemId: starbaseSystemId,
    owner: starbaseOwner,
    turn: turn,
    detectedFleets: detectedFleets,
    undetectedFleets: undetectedFleets,
    transitingFleets: transitingFleets, # Future: Track fleet movements between systems
    combatDetected: @[], # Future: Detect combat in adjacent systems
    bombardmentDetected: @[], # Future: Detect bombardment operations
    significantActivity: detectedFleets.len > 0,
    threatsDetected: int32(detectedFleets.len),
  )

  return some(report)

proc processAllStarbaseSurveillance*(state: var GameState, turn: int32, rng: var Rand) =
  ## Process surveillance for ALL starbases in the game
  ## Called once per turn during intelligence phase
  ## Reports are stored in state.intelligence Table

  # Process each house's colonies
  for (houseId, _) in state.allHousesWithId():
    for colony in state.coloniesOwned(houseId):
      if colony.starbaseIds.len > 0:
        let surveillance =
          generateStarbaseSurveillance(state, colony.systemId, colony.owner, turn, rng)

        if surveillance.isSome:
          var report = surveillance.get()

          # Apply corruption if starbase owner's intelligence is compromised (disinformation)
          let corruptionEffect =
            corruption.hasIntelCorruption(state.ongoingEffects, colony.owner)

          if corruptionEffect.isSome:
            var corruptionRng =
              initRand(turn xor hash(colony.owner) xor int(colony.systemId))
            let magnitude = corruptionEffect.get().magnitude

            # Corrupt detected fleet data (tuples -> corrupted tuples)
            var corruptedDetected: seq[
              tuple[fleetId: FleetId, location: SystemId, owner: HouseId, shipCount: int32]
            ] = @[]
            for fleet in report.detectedFleets:
              let corruptedCount =
                corruption.corruptInt(fleet.shipCount, magnitude, corruptionRng)
              corruptedDetected.add(
                (
                  fleetId: fleet.fleetId,
                  location: fleet.location,
                  owner: fleet.owner,
                  shipCount: corruptedCount,
                )
              )
            report.detectedFleets = corruptedDetected

          # Store report in intelligence database (Table read-modify-write pattern)
          if state.intelligence.contains(colony.owner):
            var intel = state.intelligence[colony.owner]
            intel.starbaseSurveillance.add(report)
            state.intelligence[colony.owner] = intel
