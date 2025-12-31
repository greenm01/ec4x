## Prestige Application - Centralized Prestige Mutation
##
## This module provides the SINGLE point of entry for all prestige changes
## in the EC4X engine. All scattered `house.prestige += amount` mutations
## should be replaced with calls to `applyPrestigeEvent()`.
##
## **Architecture Role:** Write API (like @entities modules)
## - Low-level mutator with NO business logic
## - Just applies prestige changes to GameState
## - Business logic lives in prestige/advancement.nim, prestige/combat.nim, etc.
##
## **Usage:**
## ```nim
## # OLD (scattered across codebase):
## house.prestige += 50
##
## # NEW (centralized):
## applyPrestigeEvent(state, houseId, prestigeEvent)
## ```

import std/options
import ../state/entity_manager
import ../types/[prestige, core, game_state, house]

proc applyPrestigeEvent*(state: var GameState, houseId: HouseId, event: PrestigeEvent) =
  ## Apply a single prestige event to a house
  ##
  ## This is the ONLY function that should mutate house.prestige
  ## Follows DoD pattern: read-modify-write using EntityManager

  # Get current house (safe lookup)
  let houseOpt = state.houses.entities.entity(houseId)
  if houseOpt.isNone:
    # Silently ignore - house may have been eliminated
    return

  # Apply prestige change (read-modify-write pattern)
  var house = houseOpt.get()
  house.prestige += event.amount

  # Write back to EntityManager
  state.houses.entities.updateEntity(houseId, house)

proc applyPrestigeEvents*(
    state: var GameState, houseId: HouseId, events: seq[PrestigeEvent]
) =
  ## Apply multiple prestige events to a house
  ##
  ## Convenience function for applying a batch of events
  ## Calls applyPrestigeEvent() for each event

  for event in events:
    applyPrestigeEvent(state, houseId, event)
