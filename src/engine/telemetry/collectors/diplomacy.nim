## @engine/telemetry/collectors/diplomacy.nim
##
## Collect diplomacy metrics from events and GameState.
## Covers: diplomatic relations, pacts, hostilities, wars.

import std/[options, strformat, tables, strutils]
import ../../types/[telemetry, core, game_state, event, diplomacy, house]
import ../../state/interators

proc collectDiplomacyMetrics*(
    state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect diplomacy metrics from events and GameState
  result = prevMetrics # Start with previous metrics

  # The 'house' variable is not directly used in this collector after the check for houseOpt.isNone. 
  # Its purpose was primarily to ensure the house exists before proceeding, which is now handled by the early return.

  # ================================================================
  # DIPLOMATIC STATUS (3-level system: Neutral, Hostile, Enemy)
  # ================================================================

  var hostileCount: int32 = 0
  var enemyCount: int32 = 0
  var neutralCount: int32 = 0

  for otherHouse in state.allHouses():
    if otherHouse.id == houseId or otherHouse.isEliminated:
      continue

    # Check both directions (houseId, otherHouse.id) and (otherHouse.id, houseId)
    let key1 = (houseId, otherHouse.id)
    let key2 = (otherHouse.id, houseId)

    if state.diplomaticRelation.hasKey(key1):
      let relation = state.diplomaticRelation[key1]
      case relation.state
      of DiplomaticState.Neutral:
        neutralCount += 1
      of DiplomaticState.Hostile:
        hostileCount += 1
      of DiplomaticState.Enemy:
        enemyCount += 1
    elif state.diplomaticRelation.hasKey(key2):
      let relation = state.diplomaticRelation[key2]
      case relation.state
      of DiplomaticState.Neutral:
        neutralCount += 1
      of DiplomaticState.Hostile:
        hostileCount += 1
      of DiplomaticState.Enemy:
        enemyCount += 1
    else:
      # No explicit relation = Neutral by default
      neutralCount += 1

  result.hostileStatusCount = hostileCount
  result.enemyStatusCount = enemyCount
  result.neutralStatusCount = neutralCount

  # ================================================================
  # DIPLOMATIC PENALTIES & STATUS
  # ================================================================

  # Query violation history from GameState (centralized storage)
  if state.diplomaticViolation.hasKey(houseId):
    result.pactViolationsTotal = state.diplomaticViolation[houseId].violations.len.int32
  else:
    result.pactViolationsTotal = 0

  # ================================================================
  # TREATY ACTIVITY METRICS (cumulative counts from events)
  # ================================================================

  var pactFormations: int32 = 0
  var pactBreaks: int32 = 0
  var hostilityDeclarations: int32 = 0
  var warDeclarations: int32 = 0

  for event in state.lastTurnEvents:
    # Check if this house is involved in the diplomatic event
    if event.houseId != some(houseId) and event.sourceHouseId != some(houseId) and
        event.targetHouseId != some(houseId):
      continue

    case event.eventType
    of TreatyAccepted:
      pactFormations += 1
    of TreatyBroken:
      pactBreaks += 1
    of DiplomaticRelationChanged:
      # TODO: Determine if this is a hostility declaration or war declaration
      # based on event details
      discard
    of WarDeclared:
      warDeclarations += 1
    else:
      discard

  result.pactFormationsTotal = prevMetrics.pactFormationsTotal + pactFormations
  result.pactBreaksTotal = prevMetrics.pactBreaksTotal + pactBreaks
  result.hostilityDeclarationsTotal =
    prevMetrics.hostilityDeclarationsTotal + hostilityDeclarations
  result.warDeclarationsTotal = prevMetrics.warDeclarationsTotal + warDeclarations

  # ================================================================
  # BILATERAL RELATIONS (dynamic for any number of houses)
  # ================================================================

  # Format: "houseId:state;houseId:state;..." (up to 12 houses)
  # State codes: N=Neutral, H=Hostile, E=Enemy
  var relations: seq[string] = @[]

  for otherHouse in state.allHouses():
    if otherHouse.id == houseId or otherHouse.isEliminated:
      continue

    # Check both directions for relation
    let key1 = (houseId, otherHouse.id)
    let key2 = (otherHouse.id, houseId)

    var dipState = DiplomaticState.Neutral # Default
    if state.diplomaticRelation.hasKey(key1):
      dipState = state.diplomaticRelation[key1].state
    elif state.diplomaticRelation.hasKey(key2):
      dipState = state.diplomaticRelation[key2].state

    let stateStr =
      case dipState
      of DiplomaticState.Neutral: "N"
      of DiplomaticState.Hostile: "H"
      of DiplomaticState.Enemy: "E"

    relations.add(&"{otherHouse.id}:{stateStr}")

  result.bilateralRelations = relations.join(";")
