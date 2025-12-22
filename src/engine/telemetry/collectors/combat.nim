## @engine/telemetry/collectors/combat.nim
##
## Collect combat performance metrics from events and GameState.
## Covers: space combat, ground combat, orbital bombardment, detection, invasions.

import std/[options, math]
import ../../types/[telemetry, core, game_state, event]

proc collectCombatMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect combat metrics from events and GameState
  result = prevMetrics  # Start with previous metrics

  # Initialize combat counters for this turn
  var spaceCombatWins = 0
  var spaceCombatLosses = 0
  var spaceCombatTotal = 0
  var orbitalFailures = 0
  var orbitalTotal = 0
  var raiderAmbushSuccess = 0
  var raiderAmbushAttempts = 0
  var raidersDetected = 0
  var raidersStealthSuccess = 0
  var eliDetectionAttempts = 0
  var eliRollsSum = 0
  var clkRollsSum = 0
  var scoutsDetected = 0
  var scoutsDetectedBy = 0
  var combatCERSum = 0
  var combatCERCount = 0
  var bombardmentRounds = 0
  var groundCombatVictories = 0
  var retreatsExecuted = 0
  var criticalHitsDealt = 0
  var criticalHitsReceived = 0
  var cloakedAmbushSuccess = 0
  var shieldsActivated = 0
  var totalInvasions = 0

  # Process events from state.lastTurnEvents
  for event in state.lastTurnEvents:
    # Combat Result events (space/orbital/ground combat outcomes)
    if event.eventType == CombatResult:
      if event.attackingHouseId == some(houseId):
        spaceCombatTotal += 1
        if event.outcome == some("Victory"):
          spaceCombatWins += 1
        elif event.outcome == some("Defeat"):
          spaceCombatLosses += 1
      elif event.defendingHouseId == some(houseId):
        spaceCombatTotal += 1
        if event.outcome == some("Defeat"):
          spaceCombatWins += 1  # Defender wins if attacker loses
        elif event.outcome == some("Victory"):
          spaceCombatLosses += 1  # Defender loses if attacker wins

    # Raider detection events
    elif event.eventType == RaiderDetected:
      if event.targetHouseId == some(houseId):
        # This house's raiders were detected
        raidersDetected += 1
      # TODO: Extract CLK rolls from event details if available

    elif event.eventType == RaiderStealthSuccess:
      if event.houseId == some(houseId):
        raidersStealthSuccess += 1
      # TODO: Extract CLK rolls from event details if available

    # Raider ambush events
    elif event.eventType == RaiderAmbush:
      if event.houseId == some(houseId):
        raiderAmbushAttempts += 1
        if event.success.get(false):
          raiderAmbushSuccess += 1

    # Scout detection events
    elif event.eventType == ScoutDetected:
      if event.targetHouseId == some(houseId):
        # This house's scouts were detected
        scoutsDetected += 1
      elif event.houseId == some(houseId):
        # This house detected enemy scouts
        scoutsDetectedBy += 1

    # Bombardment events
    elif event.eventType in {Bombardment, BombardmentRoundCompleted}:
      if event.houseId == some(houseId):
        bombardmentRounds += 1
        # TODO: Track orbital failures vs successes from event details

    # Shield activation events
    elif event.eventType == ShieldActivated:
      if event.houseId == some(houseId):
        shieldsActivated += 1

    # Retreat events
    elif event.eventType == FleetRetreat:
      if event.houseId == some(houseId):
        retreatsExecuted += 1

    # Invasion events
    elif event.eventType == InvasionBegan:
      if event.houseId == some(houseId):
        totalInvasions += 1

    elif event.eventType == ColonyCaptured:
      if event.newOwner == some(houseId):
        # Successful invasion by this house
        groundCombatVictories += 1

    # Ship damage/destruction events (for critical hits tracking)
    # TODO: Need to determine how to extract critical hits from events
    # This may require additional event fields or parsing from details

  # Assign computed metrics to result
  result.spaceCombatWins = spaceCombatWins
  result.spaceCombatLosses = spaceCombatLosses
  result.spaceCombatTotal = spaceCombatTotal
  result.orbitalFailures = orbitalFailures
  result.orbitalTotal = orbitalTotal
  result.raiderAmbushSuccess = raiderAmbushSuccess
  result.raiderAmbushAttempts = raiderAmbushAttempts
  result.raiderDetectedCount = raidersDetected
  result.raiderStealthSuccessCount = raidersStealthSuccess
  result.eliDetectionAttempts = eliDetectionAttempts

  # Calculate average ELI roll
  if eliDetectionAttempts > 0:
    result.avgEliRoll = float(eliRollsSum) / float(eliDetectionAttempts)
  else:
    result.avgEliRoll = 0.0

  # Calculate average CLK roll
  let totalClkRolls = raidersDetected + raidersStealthSuccess
  if totalClkRolls > 0:
    result.avgClkRoll = float(clkRollsSum) / float(totalClkRolls)
  else:
    result.avgClkRoll = 0.0

  result.scoutsDetected = scoutsDetected
  result.scoutsDetectedBy = scoutsDetectedBy

  # Calculate average CER (Combat Efficiency Rating)
  if combatCERCount > 0:
    result.combatCERAverage = combatCERSum div combatCERCount
  else:
    result.combatCERAverage = 0

  result.bombardmentRoundsTotal = bombardmentRounds
  result.groundCombatVictories = groundCombatVictories
  result.retreatsExecuted = retreatsExecuted
  result.criticalHitsDealt = criticalHitsDealt
  result.criticalHitsReceived = criticalHitsReceived
  result.cloakedAmbushSuccess = cloakedAmbushSuccess
  result.shieldsActivatedCount = shieldsActivated

  # Cumulative invasion tracking
  result.totalInvasions = prevMetrics.totalInvasions + totalInvasions

  # Invasion order tracking (Phase 1 - populated during order generation)
  result.invasionOrders_generated = prevMetrics.invasionOrders_generated
  result.invasionOrders_bombard = prevMetrics.invasionOrders_bombard
  result.invasionOrders_invade = prevMetrics.invasionOrders_invade
  result.invasionOrders_blitz = prevMetrics.invasionOrders_blitz
  result.invasionOrders_canceled = prevMetrics.invasionOrders_canceled
