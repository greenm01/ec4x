## Prestige Engine - Multiplier and Utilities

import std/options
import ../state/engine
import ../types/[prestige, core, game_state, house]
import ../../common/logger
import ../globals

# Private backing storage
var prestigeMultiplierImpl {.threadvar.}: float64

# Prestige multiplier property
proc `prestigeMultiplier=`*(multiplier: float32) =
  ## Set the prestige multiplier directly for testing
  ## Use 1.0 to disable multiplier effects in tests
  prestigeMultiplierImpl = multiplier

proc prestigeMultiplier*(): float32 =
  ## Get the current prestige multiplier
  ## Returns the base multiplier if not initialized
  if prestigeMultiplierImpl == 0.0:
    logWarn(
      "Prestige",
      "Multiplier uninitialized! Using base value",
      "base=",
      $gameConfig.prestige.dynamicScaling.baseMultiplier
    )
    return gameConfig.prestige.dynamicScaling.baseMultiplier
  return prestigeMultiplierImpl

proc applyPrestigeMultiplier*(baseValue: int32): int32 =
  ## Apply the dynamic multiplier to a base prestige value
  result = int32(float32(baseValue) * prestigeMultiplier())

proc applyPrestigeEvent*(state: GameState, houseId: HouseId, event: PrestigeEvent) =
  ## Apply a single prestige event to a house
  ##
  ## This is the ONLY function that should mutate house.prestige
  ## Follows DoD pattern: read-modify-write using EntityManager

  # Get current house (safe lookup)
  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    # Silently ignore - house may have been eliminated
    return

  # Apply prestige change (read-modify-write pattern)
  var house = houseOpt.get()
  house.prestige += event.amount

  # Write back to EntityManager
  state.updateHouse(houseId, house)

proc applyPrestigeEvents*(
    state: GameState, houseId: HouseId, events: seq[PrestigeEvent]
) =
  ## Apply multiple prestige events to a house
  ##
  ## Convenience function for applying a batch of events
  ## Calls applyPrestigeEvent() for each event

  for event in events:
    applyPrestigeEvent(state, houseId, event)
