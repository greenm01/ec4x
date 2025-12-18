## Protostrator Collector - Diplomacy & Foreign Affairs Domain
##
## Tracks diplomatic relationships (3-level system: Neutral, Hostile, Enemy),
## pact violations, dishonored status, diplomatic isolation, and bilateral relations.
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim (lines 552-612)

import std/[strformat, tables, strutils]
import ./types
import ../../../engine/gamestate
import ../../../engine/diplomacy/types as dip_types
import ../../../common/types/diplomacy

proc collectProtostratorMetrics*(state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics): DiagnosticMetrics =
  ## Collect diplomacy & foreign affairs metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)

  # ================================================================
  # DIPLOMATIC STATUS (4-level system)
  # ================================================================

  # Count diplomatic relationships
  var hostileCount = 0
  var enemyCount = 0
  var neutralCount = 0

  for otherHouseId, otherHouse in state.houses:
    if otherHouseId == houseId or otherHouse.eliminated:
      continue

    # Check diplomatic state from house's diplomaticRelations
    # This is the authoritative source used by combat and fleet orders
    let dipState = house.diplomaticRelations.getDiplomaticState(otherHouseId)
    case dipState
    of DiplomaticState.Neutral:
      neutralCount += 1
    of DiplomaticState.Hostile:
      hostileCount += 1
    of DiplomaticState.Enemy:
      enemyCount += 1

  result.hostileStatusCount = hostileCount
  result.enemyStatusCount = enemyCount
  result.neutralStatusCount = neutralCount

  # ================================================================
  # DIPLOMATIC PENALTIES & STATUS
  # ================================================================

  # Violation tracking
  # DishonoredStatus and DiplomaticIsolation fields have been removed from House.
  # Their logic is now implicitly handled by ViolationHistory and diplomatic rules.
  result.pactViolationsTotal = house.violationHistory.violations.len

  # ================================================================
  # TREATY ACTIVITY METRICS (cumulative counts)
  # ================================================================

  # Track historical diplomatic events from last turn's data
  result.pactFormationsTotal = prevMetrics.pactFormationsTotal + house.lastTurnPactFormations
  result.pactBreaksTotal = prevMetrics.pactBreaksTotal + house.lastTurnPactBreaks
  result.hostilityDeclarationsTotal = prevMetrics.hostilityDeclarationsTotal + house.lastTurnHostilityDeclarations
  result.warDeclarationsTotal = prevMetrics.warDeclarationsTotal + house.lastTurnWarDeclarations

  # ================================================================
  # BILATERAL RELATIONS (dynamic for any number of houses)
  # ================================================================

  # Format: "houseId:state;houseId:state;..." (up to 12 houses)
  # State codes: N=Neutral, H=Hostile, E=Enemy
  var relations: seq[string] = @[]
  for otherHouseId, otherHouse in state.houses:
    if otherHouseId == houseId or otherHouse.eliminated:
      continue

    let dipState = house.diplomaticRelations.getDiplomaticState(otherHouseId)
    let stateStr = case dipState
      of DiplomaticState.Neutral: "N"
      of DiplomaticState.Hostile: "H"
      of DiplomaticState.Enemy: "E"

    relations.add(&"{otherHouseId}:{stateStr}")

  result.bilateralRelations = relations.join(";")
