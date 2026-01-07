## Spy Scout Turn Resolution
## Implements spy detection per assets.md:2.4.2

import std/[options, random]
import ../../common/logger
import ../types/[core, game_state]
import ../state/engine

type ScoutDetectionResult* = object
  ## Detection result for scout missions with roll details
  detected*: bool
  roll*: int32
  threshold*: int32

proc resolveScoutDetection*(
    state: GameState,
    scoutCount: int32,
    defender: HouseId,
    targetSystem: SystemId,
    rng: var Rand,
): ScoutDetectionResult =
  ## Resolve detection for active scout mission (fleet-based system)
  ## Takes scout count directly instead of looking up fleet
  ## Returns ScoutDetectionResult with detected flag and roll details

  # Get defender's ELI level using safe accessor
  let defenderHouseOpt = state.house(defender)
  if defenderHouseOpt.isNone:
    logWarn("Intelligence", "Defender house not found for detection check", "defender=", $defender)
    # No defender house found, detection fails (scouts succeed)
    return ScoutDetectionResult(detected: false, roll: 0, threshold: 0)

  let defenderHouse = defenderHouseOpt.get()
  let defenderELI = defenderHouse.techTree.levels.eli

  # Get starbase bonus (+2 ELI for detection per assets.md:2.4.2)
  var starbaseBonus: int32 = 0
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    starbaseBonus = if state.countStarbasesAtColony(colony.id) > 0: 2 else: 0

  # Calculate target number
  let targetNumber = 15 - scoutCount + (defenderELI + starbaseBonus)

  # Roll 1d20 (result 1-20)
  let roll = int32(rng.rand(1 .. 20))

  let detected = roll >= targetNumber

  if detected:
    logInfo(
      "Intelligence",
      "Scout mission DETECTED",
      "defender=", $defender,
      " system=", $targetSystem,
      " roll=", $roll,
      " target=", $targetNumber,
    )
  else:
    logDebug(
      "Intelligence",
      "Scout mission UNDETECTED",
      "defender=", $defender,
      " system=", $targetSystem,
      " roll=", $roll,
      " target=", $targetNumber,
    )

  return ScoutDetectionResult(detected: detected, roll: roll, threshold: targetNumber)
