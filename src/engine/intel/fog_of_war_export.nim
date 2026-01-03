## Fog-of-War Export for Claude Play-Testing
##
## Generates filtered game state views for AI opponents that respect
## fog-of-war visibility rules. Used for Claude-as-opponent play-testing.
##
## Architecture:
## - Filters GameState based on house intelligence and visibility
## - Exports to JSON for easy consumption by Claude
## - Respects all fog-of-war rules from event_processor/visibility.nim
##
## DRY Principle: Reuses existing visibility logic
## DoD Principle: Filters data without modifying game state

import std/[json, jsonutils, tables, options]
import ../types/[core, game_state, event, intel, diplomacy]
import ./event_processor/visibility

type
  FogOfWarView* = object
    ## Filtered view of game state for a specific house
    ## Only includes information visible to that house
    gameId*: string
    turn*: int32
    phase*: string
    houseId*: HouseId

    # Own entities (full visibility)
    ownColonies*: seq[JsonNode]
    ownFleets*: seq[JsonNode]
    ownHouse*: JsonNode

    # Intel database (what the house knows about others)
    knownSystems*: seq[JsonNode]
    knownFleets*: seq[JsonNode]
    knownColonies*: seq[JsonNode]

    # Diplomatic relations (what the house knows)
    diplomaticRelations*: seq[JsonNode]

    # Visible events (filtered by fog-of-war)
    visibleEvents*: seq[JsonNode]

proc exportFogOfWarView*(state: GameState, houseId: HouseId): FogOfWarView =
  ## Generate a fog-of-war filtered view of game state for a specific house
  ##
  ## This function creates a complete view of what the house can see,
  ## respecting all fog-of-war visibility rules.
  ##
  ## Args:
  ##   state: Current game state
  ##   houseId: House to generate view for
  ##
  ## Returns:
  ##   FogOfWarView with all visible information

  result = FogOfWarView(
    gameId: state.gameId,
    turn: state.turn,
    phase: $state.phase,
    houseId: houseId,
    ownColonies: @[],
    ownFleets: @[],
    knownSystems: @[],
    knownFleets: @[],
    knownColonies: @[],
    diplomaticRelations: @[],
    visibleEvents: @[],
  )

  # Get house's own data (full visibility)
  for (colonyId, colony) in state.allColoniesWithId():
    if colony.owner == houseId:
      result.ownColonies.add(toJson(colony))

  for (fleetId, fleet) in state.allFleetsWithId():
    if fleet.houseId == houseId:
      result.ownFleets.add(toJson(fleet))

  # Get own house data
  let houseOpt = state.house(houseId)
  if houseOpt.isSome:
    let house = houseOpt.get()
    result.ownHouse = toJson(house)

  # Get intelligence database for this house
  if houseId in state.intelligence:
    let intel = state.intelligence[houseId]

    # Known systems (from system intel reports)
    for systemId, systemReport in intel.systemReports:
      result.knownSystems.add(toJson(systemReport))

    # Known fleets (scout encounters)
    for report in intel.scoutEncounters:
      result.knownFleets.add(toJson(report))

    # Known colonies (from colony intel reports)
    for colonyId, colonyReport in intel.colonyReports:
      result.knownColonies.add(toJson(colonyReport))

  # Get diplomatic relations
  for relationKey, relation in state.diplomaticRelation:
    let (sourceHouse, targetHouse) = relationKey
    if sourceHouse == houseId:
      var relationData = %* {
        "targetHouse": targetHouse.uint32,
        "state": $relation.state,
        "sinceTurn": relation.sinceTurn
      }
      result.diplomaticRelations.add(relationData)

  # Filter events by fog-of-war visibility
  for event in state.lastTurnEvents:
    if shouldHouseSeeEvent(state, houseId, event):
      result.visibleEvents.add(toJson(event))

proc exportFogOfWarViewToJson*(state: GameState, houseId: HouseId): JsonNode =
  ## Export fog-of-war view as JSON
  ## Convenience wrapper around exportFogOfWarView
  let view = exportFogOfWarView(state, houseId)
  return toJson(view)

proc saveFogOfWarViewToFile*(
    state: GameState, houseId: HouseId, filePath: string
) =
  ## Save fog-of-war view to JSON file
  ## Useful for Claude play-testing - generates a file per house per turn
  ##
  ## Suggested naming: fog_of_war_{gameId}_house{houseId}_turn{turn}.json
  let jsonView = exportFogOfWarViewToJson(state, houseId)
  writeFile(filePath, jsonView.pretty())
