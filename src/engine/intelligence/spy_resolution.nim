## Spy Scout Turn Resolution
## Implements spy detection per assets.md:2.4.2

import std/[tables, options, random, strformat]
import ../../common/types/core
import ../gamestate, ../logger
import ./types as intel_types
import ../resolution/types as res_types
import ../config/facilities_config

proc resolveSpyScoutDetection*(
  state: GameState,
  attacker: HouseId,
  fleetId: FleetId,
  targetSystem: SystemId,
  rng: var Rand
): bool =
  ## Resolve detection for a spy scout mission per assets.md:2.4.2
  ## Returns true if detected, false otherwise.

  # 1. Get number of scouts
  if fleetId notin state.fleets:
    logWarn(LogCategory.lcGeneral, &"Spy fleet {fleetId} not found for detection check.")
    return true # Cannot find fleet, assume mission fails/detected.

  let fleet = state.fleets[fleetId]
  let numScouts = fleet.squadrons.len # Assuming 1 scout per squadron in a scout-only fleet

  if numScouts == 0:
    logWarn(LogCategory.lcGeneral, &"Spy fleet {fleetId} has no scouts for detection check.")
    return true

  # 2. Get defender's info
  if targetSystem notin state.colonies:
    # No colony, no owner, no detection.
    return false

  let colony = state.colonies[targetSystem]
  let defender = colony.owner

  if defender == attacker:
    # Spying on self? No detection.
    return false

  let defenderHouse = state.houses[defender]
  let defenderELI = defenderHouse.techTree.levels.electronicIntelligence

  # 3. Get starbase bonus
  var starbaseBonus = 0
  if colony.starbases.len > 0:
    starbaseBonus = globalFacilitiesConfig.starbase.economic_lift_bonus

  # 4. Calculate target number
  let targetNumber = 15 - numScouts + (defenderELI + starbaseBonus)

  # 5. Roll 1d20 (result 1-20)
  let roll = rng.rand(1..20)

  let detected = roll >= targetNumber

  if detected:
    logInfo(LogCategory.lcOrders,
      &"Spy mission DETECTED. Attacker: {attacker}, Defender: {defender}, System: {targetSystem}. " &
      &"Roll: {roll} >= Target: {targetNumber} (15 - {numScouts} scouts + {defenderELI} ELI + {starbaseBonus} SB bonus)")
  else:
    logInfo(LogCategory.lcOrders,
      &"Spy mission UNDETECTED. Attacker: {attacker}, Defender: {defender}, System: {targetSystem}. " &
      &"Roll: {roll} < Target: {targetNumber} (15 - {numScouts} scouts + {defenderELI} ELI + {starbaseBonus} SB bonus)")

  return detected
