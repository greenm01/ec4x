## Combat Intelligence Analyzer
##
## Processes CombatEncounterReport from engine intelligence database
## Learns tactical lessons from combat outcomes
##
## Phase C implementation

import std/[tables, options, sequtils, strformat, algorithm, strutils]
import ../../../../engine/[gamestate, fog_of_war, logger]
import ../../../../engine/intelligence/types as intel_types
import ../../../../engine/combat/types as combat_types
import ../../../../common/types/[core, units]
import ../../controller_types
import ../../config
import ../../shared/intelligence_types

proc extractFleetComposition(
  fleetComposition: intel_types.CombatFleetComposition
): FleetComposition =
  ## Extract fleet composition summary from detailed intelligence
  result = FleetComposition(
    capitalShips: 0,
    cruisers: 0,
    destroyers: 0,
    escorts: 0,
    scouts: 0,
    spaceLiftShips: 0,
    totalShips: 0
  )

  for squadron in fleetComposition.squadrons:
    let shipClass = squadron.shipClass
    result.totalShips += 1

    # Count ship types
    case shipClass:
    of "Raider", "raider":
      result.escorts += 1
    of "Destroyer", "destroyer":
      result.destroyers += 1
    of "Cruiser", "cruiser":
      result.cruisers += 1
    of "Carrier", "carrier", "Dreadnought", "dreadnought", "Battleship", "battleship":
      result.capitalShips += 1
    of "Scout", "scout":
      result.scouts += 1
    else:
      # Unknown ship type, count as generic
      discard

  # Count space lift ships
  result.spaceLiftShips = fleetComposition.spaceLiftShips.len

proc determineEffectiveShipTypes(
  outcome: intel_types.CombatOutcome,
  ourComposition: FleetComposition,
  enemyComposition: FleetComposition
): seq[ShipClass] =
  ## Determine which of our ship types were effective based on outcome
  result = @[]

  case outcome:
  of intel_types.CombatOutcome.Victory:
    # All ship types in our composition were effective
    if ourComposition.escorts > 0:
      result.add(ShipClass.Raider)
    if ourComposition.destroyers > 0:
      result.add(ShipClass.Destroyer)
    if ourComposition.cruisers > 0:
      result.add(ShipClass.Cruiser)
    if ourComposition.capitalShips > 0:
      result.add(ShipClass.Dreadnought)
      result.add(ShipClass.Carrier)

  of intel_types.CombatOutcome.Defeat, intel_types.CombatOutcome.Retreat:
    # Heavy ships that survived are effective
    if ourComposition.capitalShips > 0:
      result.add(ShipClass.Dreadnought)
      result.add(ShipClass.Carrier)

  of intel_types.CombatOutcome.MutualRetreat:
    # Mixed effectiveness - heavy ships held the line
    if ourComposition.cruisers > 0:
      result.add(ShipClass.Cruiser)
    if ourComposition.capitalShips > 0:
      result.add(ShipClass.Dreadnought)

  of intel_types.CombatOutcome.Ongoing:
    # Combat still ongoing, no lessons yet
    discard

proc determineIneffectiveShipTypes(
  outcome: intel_types.CombatOutcome,
  ourComposition: FleetComposition,
  ourLosses: seq[string]
): seq[ShipClass] =
  ## Determine which ship types performed poorly
  result = @[]

  case outcome:
  of intel_types.CombatOutcome.Defeat:
    # All ship types were ineffective in defeat
    if ourComposition.escorts > 0:
      result.add(ShipClass.Raider)
    if ourComposition.destroyers > 0:
      result.add(ShipClass.Destroyer)
    if ourComposition.cruisers > 0:
      result.add(ShipClass.Cruiser)

  of intel_types.CombatOutcome.Retreat:
    # Light ships were ineffective (forced retreat)
    if ourComposition.escorts > 0:
      result.add(ShipClass.Raider)
    if ourComposition.destroyers > 0:
      result.add(ShipClass.Destroyer)

  else:
    # Parse losses to identify lost ship types
    for loss in ourLosses:
      # Loss strings are squadron IDs or ship class names
      if "raider" in loss.toLowerAscii():
        result.add(ShipClass.Raider)
      elif "destroyer" in loss.toLowerAscii():
        result.add(ShipClass.Destroyer)
      elif "cruiser" in loss.toLowerAscii():
        result.add(ShipClass.Cruiser)

proc analyzeCombatReports*(
  filtered: FilteredGameState,
  controller: AIController
): seq[TacticalLesson] =
  ## Analyze CombatEncounterReport data to learn what works in combat
  ## Phase C implementation
  result = @[]

  let config = globalRBAConfig.intelligence

  # Skip if combat learning is disabled
  if not config.combat_report_learning_enabled:
    return

  let recentTurn = filtered.turn - config.combat_lesson_retention_turns

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Combat Analyzer: Analyzing combat reports from turn {recentTurn}+")

  # Iterate through combat reports
  for reportId, report in filtered.ownHouse.intelligence.combatReports:
    # Filter to recent reports
    if report.turn < recentTurn:
      continue

    # Only analyze reports from our house
    if report.reportingHouse != controller.houseId:
      continue

    # Extract enemy house (from first enemy fleet)
    if report.enemyForces.len == 0:
      continue  # No enemy data, can't learn

    let enemyHouse = report.enemyForces[0].owner

    # Extract fleet compositions
    var ourComposition = FleetComposition(
      capitalShips: 0, cruisers: 0, destroyers: 0,
      escorts: 0, scouts: 0, spaceLiftShips: 0, totalShips: 0
    )
    for fleet in report.alliedForces:
      let fleetComp = extractFleetComposition(fleet)
      ourComposition.capitalShips += fleetComp.capitalShips
      ourComposition.cruisers += fleetComp.cruisers
      ourComposition.destroyers += fleetComp.destroyers
      ourComposition.escorts += fleetComp.escorts
      ourComposition.scouts += fleetComp.scouts
      ourComposition.spaceLiftShips += fleetComp.spaceLiftShips
      ourComposition.totalShips += fleetComp.totalShips

    var enemyComposition = FleetComposition(
      capitalShips: 0, cruisers: 0, destroyers: 0,
      escorts: 0, scouts: 0, spaceLiftShips: 0, totalShips: 0
    )
    for fleet in report.enemyForces:
      let fleetComp = extractFleetComposition(fleet)
      enemyComposition.capitalShips += fleetComp.capitalShips
      enemyComposition.cruisers += fleetComp.cruisers
      enemyComposition.destroyers += fleetComp.destroyers
      enemyComposition.escorts += fleetComp.escorts
      enemyComposition.scouts += fleetComp.scouts
      enemyComposition.spaceLiftShips += fleetComp.spaceLiftShips
      enemyComposition.totalShips += fleetComp.totalShips

    # Analyze effectiveness
    let effectiveTypes = determineEffectiveShipTypes(report.outcome, ourComposition, enemyComposition)
    let ineffectiveTypes = determineIneffectiveShipTypes(report.outcome, ourComposition, report.alliedLosses)

    # Count losses
    let ourLosses = report.alliedLosses.len
    let enemyLosses = report.enemyLosses.len

    # Create tactical lesson
    result.add(TacticalLesson(
      combatId: report.reportId,  # Use the reportId field from report
      turn: report.turn,
      enemyHouse: enemyHouse,
      location: report.systemId,
      outcome: report.outcome,
      effectiveShipTypes: effectiveTypes,
      ineffectiveShipTypes: ineffectiveTypes,
      observedEnemyComposition: enemyComposition,
      ourLosses: ourLosses,
      enemyLosses: enemyLosses
    ))

  # Sort by recency (most recent first)
  result.sort(proc (a, b: TacticalLesson): int = cmp(b.turn, a.turn))

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Combat Analyzer: Learned {result.len} tactical lessons")

  return result
