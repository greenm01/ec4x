## Prestige Application - Centralized Prestige Mutation
##
## This module provides the SINGLE point of entry for all prestige changes
## in the EC4X engine. All scattered `house.prestige += amount` mutations
## should be replaced with calls to `applyPrestigeEvent()`.
##
## **Why Centralized Application?**
## - Single source of truth for prestige changes
## - Enables validation (e.g., prevent negative prestige from going too low)
## - Easier debugging and auditing of prestige changes
## - Future-proof for prestige change history tracking
## - Prevents inconsistent direct mutations across 8+ modules
##
## **Usage:**
## ```nim
## # OLD (scattered across codebase):
## house.prestige += 50
##
## # NEW (centralized):
## applyPrestigeEvent(state, houseId, prestigeEvent)
## ```

# Import types module for PrestigeEvent
import types
import ../../common/types/core # For HouseId

# Forward declare GameState to avoid circular dependency
# The actual import happens in modules that call these procs
type GameState = object
  # Placeholder - will be the real type from gamestate.nim (NOT exported to avoid ambiguity)

proc applyPrestigeEvent*[T](state: var T, houseId: HouseId, event: PrestigeEvent) =
  ## Apply a single prestige event to a house
  ##
  ## This is the ONLY function that should mutate house.prestige
  ## All other modules should call this function instead of direct mutation
  ##
  ## **Validation:**
  ## - Prestige can go negative (defensive collapse at < 0 for 3+ turns)
  ## - No upper limit on prestige
  ##
  ## **Future Extensions:**
  ## - Add prestige change history tracking
  ## - Add diagnostic logging for prestige auditing
  ## - Add event aggregation for turn reports

  if houseId notin state.houses:
    # Silently ignore - house may have been eliminated
    return

  # Apply prestige change
  state.houses[houseId].prestige += event.amount

proc applyPrestigeEvents*[T](
    state: var T, houseId: HouseId, events: seq[PrestigeEvent]
) =
  ## Apply multiple prestige events to a house
  ##
  ## Convenience function for applying a batch of events
  ## Calls applyPrestigeEvent() for each event

  for event in events:
    applyPrestigeEvent(state, houseId, event)
