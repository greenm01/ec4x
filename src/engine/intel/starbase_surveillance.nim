## Starbase Surveillance System - CON1f.iv
##
## Per docs/specs/09-intel-espionage.md Section 9.1.4:
## - Starbases continuously monitor their home system (not adjacent)
## - Detects non-stealthed fleet movements automatically
## - Provides early warning of enemy approaches
## - Scouts and cloaked Raiders can evade via stealth checks
##
## Architecture:
## - Called during Conflict Phase CON1f.iv (after espionage)
## - Uses existing detection.nim functions for stealth mechanics
## - Stores observations in IntelDatabase.fleetObservations
## - Only stores successful detections (not failed attempts)

import std/[options, random, tables]
import ../../common/logger
import ../types/[core, game_state, player_state, ship, fleet, facilities, combat, event]
import ../state/[engine, iterators]
import ../event_factory/[intel, military]
import ./detection
import ./generator

type
  DetectionOutcome = object
    detected: bool
    isRaider: bool
    eliRoll: int
    clkRoll: int

proc countScoutsInFleet(state: GameState, fleet: Fleet): int32 =
  ## Count scout ships in a fleet
  result = 0
  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass == ShipClass.Scout:
        result += 1

proc countRaidersInFleet(state: GameState, fleet: Fleet): int32 =
  ## Count raider ships in a fleet
  result = 0
  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass == ShipClass.Raider:
        result += 1

proc fleetCLKLevel(state: GameState, fleet: Fleet): int32 =
  ## Get the highest CLK tech level in a fleet (for raider stealth)
  result = 0
  let fleetOwnerOpt = state.house(fleet.houseId)
  if fleetOwnerOpt.isSome:
    result = fleetOwnerOpt.get().techTree.levels.clk

proc detectFleetByStarbase(
    state: GameState,
    fleet: Fleet,
    starbaseOwner: HouseId,
    defenderELI: int32,
    rng: var Rand,
): DetectionOutcome =
  ## Check if a fleet is detected by a starbase
  ## Returns DetectionOutcome with detection result and stealth roll details
  ##
  ## Detection Rules (per docs/specs/02-assets.md):
  ## - Scout fleets: Use scout detection formula (Section 2.4.2)
  ## - Raider fleets: Use raider cloaking formula (Section 2.4.3)
  ## - Other fleets: Automatically detected (no stealth)

  # Check if fleet has scouts (uses scout stealth mechanics)
  let scoutCount = state.countScoutsInFleet(fleet)
  if scoutCount > 0:
    let starbaseBonus = 2
    let detectionResult = detectScouts(
      int(scoutCount), int(defenderELI), starbaseBonus, rng
    )

    if not detectionResult.detected:
      logDebug(
        "Surveillance",
        "Scout fleet evaded starbase detection",
        " fleet=", $fleet.id,
        " owner=", $fleet.houseId,
        " scouts=", $scoutCount,
        " roll=", $detectionResult.roll,
        " threshold=", $detectionResult.threshold,
      )
      return DetectionOutcome(
        detected: false, isRaider: false,
        eliRoll: detectionResult.roll, clkRoll: 0,
      )

  # Check if fleet has raiders (uses raider cloaking mechanics)
  let raiderCount = state.countRaidersInFleet(fleet)
  if raiderCount > 0:
    let attackerCLK = state.fleetCLKLevel(fleet)
    let starbaseBonus = 2
    let detectionResult = detectRaider(
      int(attackerCLK), int(defenderELI), starbaseBonus, rng
    )

    if not detectionResult.detected:
      logDebug(
        "Surveillance",
        "Raider fleet evaded starbase detection",
        " fleet=", $fleet.id,
        " owner=", $fleet.houseId,
        " raiders=", $raiderCount,
        " attackerCLK=", $attackerCLK,
        " defenderRoll=", $detectionResult.roll,
        " attackerRoll=", $detectionResult.threshold,
      )
      return DetectionOutcome(
        detected: false, isRaider: true,
        eliRoll: detectionResult.roll, clkRoll: detectionResult.threshold,
      )

    # Raider detected
    return DetectionOutcome(
      detected: true, isRaider: true,
      eliRoll: detectionResult.roll, clkRoll: detectionResult.threshold,
    )

  # All other fleets (or scouts/raiders that failed stealth): Detected
  return DetectionOutcome(detected: true, isRaider: false, eliRoll: 0, clkRoll: 0)

proc processStarbaseSurveillance*(
    state: GameState, turn: int32, rng: var Rand,
    events: var seq[GameEvent]
) =
  ## Process all starbase surveillance for the turn
  ## Called during Conflict Phase CON1f.iv
  ##
  ## For each house's starbases:
  ## 1. Find all operational starbases
  ## 2. For each starbase system, detect enemy fleets
  ## 3. Apply stealth checks (scouts and raiders can evade)
  ## 4. Store successful detections in IntelDatabase.fleetObservations
  ## 5. Emit detection/stealth events

  logInfo("Surveillance", "[CON1f.iv] Processing starbase surveillance...")

  var totalDetections = 0

  # Process each house's starbases
  for house in state.allHouses():
    let houseId = house.id
    let defenderELI = house.techTree.levels.eli

    # Find all colonies with operational starbases
    for colony in state.coloniesOwned(houseId):
      # Get all starbases at this colony
      let kastras = state.kastrasAtColony(colony.id)
      var hasOperationalStarbase = false
      var starbaseId = ""

      for kastra in kastras:
        if kastra.kastraClass == KastraClass.Starbase and
            kastra.state != CombatState.Crippled:
          hasOperationalStarbase = true
          starbaseId = $kastra.id
          break

      if not hasOperationalStarbase:
        continue

      # Starbase is operational - scan the system for enemy fleets
      let systemId = colony.systemId

      logDebug(
        "Surveillance",
        "Starbase scanning system",
        " house=", $houseId,
        " colony=", $colony.id,
        " system=", $systemId,
      )

      # Check if there are enemy fleets in system (before stealth checks)
      var hasEnemyFleets = false
      for fleet in state.fleetsInSystem(systemId):
        if fleet.houseId != houseId:
          hasEnemyFleets = true
          break

      if not hasEnemyFleets:
        continue

      # Check each enemy fleet for stealth capability
      var detectedCount = 0
      var undetectedCount = 0
      for fleet in state.fleetsInSystem(systemId):
        if fleet.houseId == houseId:
          continue

        # Attempt detection (checks stealth for scouts/raiders)
        let outcome = state.detectFleetByStarbase(
          fleet, houseId, defenderELI, rng
        )

        if outcome.detected:
          detectedCount += 1
          logDebug(
            "Surveillance",
            "Starbase detected fleet",
            " observer=", $houseId,
            " fleet=", $fleet.id,
            " owner=", $fleet.houseId,
          )

          # Emit raider detected event
          if outcome.isRaider:
            events.add(military.raiderDetected(
              fleet.id, fleet.houseId, houseId, "Starbase",
              systemId, outcome.eliRoll, outcome.clkRoll
            ))
        else:
          undetectedCount += 1

          # Emit raider stealth success event
          if outcome.isRaider:
            events.add(military.raiderStealthSuccess(
              fleet.id, fleet.houseId, houseId, "Starbase",
              systemId, outcome.eliRoll, outcome.clkRoll
            ))

      # If at least one fleet was detected, generate system intel package
      if detectedCount > 0:
        # Emit starbase surveillance detection summary event
        events.add(intel.starbaseSurveillanceDetection(
          starbaseId, houseId, systemId,
          detectedCount, undetectedCount
        ))

        # Use existing generator to create proper SystemObservation with Visual quality
        let intelPackage = generateSystemObservation(
          state, houseId, systemId, IntelQuality.Visual
        )

        if intelPackage.isSome:
          let pkg = intelPackage.get()

          # Ensure intel database exists for this house
          if not state.intel.hasKey(houseId):
            state.intel[houseId] = IntelDatabase(houseId: houseId)

          # Store system observation
          state.intel[houseId].systemObservations[systemId] = pkg.report

          # Store fleet observations
          for (fleetId, fleetObs) in pkg.fleetObservations:
            state.intel[houseId].fleetObservations[fleetId] = fleetObs

          # Store ship observations
          for (shipId, shipObs) in pkg.shipObservations:
            state.intel[houseId].shipObservations[shipId] = shipObs

          totalDetections += 1

          logInfo(
            "Surveillance",
            "Starbase surveillance complete",
            " observer=", $houseId,
            " system=", $systemId,
            " fleets=", $pkg.fleetObservations.len,
          )

  logInfo(
    "Surveillance",
    "[CON1f.iv] Starbase surveillance complete",
    " detections=", $totalDetections,
  )
