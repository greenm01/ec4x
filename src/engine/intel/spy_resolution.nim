## Spy Scout Turn Resolution
## Implements spy detection per assets.md:2.4.2

import std/[options, random]
import ../../common/logger
import ../types/[core, game_state]
import ../state/engine as state_helpers

type SpyDetectionResult* = object
  ## Detection result for spy missions with roll details
  detected*: bool
  roll*: int32
  threshold*: int32

proc resolveSpyScoutDetection*(
    state: GameState,
    attacker: HouseId,
    fleetId: FleetId,
    targetSystem: SystemId,
    rng: var Rand,
): bool =
  ## Resolve detection for a spy scout mission per assets.md:2.4.2
  ## Returns true if detected, false otherwise.

  # 1. Get number of scouts using safe accessor
  let fleetOpt = state_helpers.fleet(state, fleetId)
  if fleetOpt.isNone:
    logWarn("Intelligence", "Spy fleet not found for detection check", "fleetId=", $fleetId)
    return true # Cannot find fleet, assume mission fails/detected

  let fleet = fleetOpt.get()
  let numScouts = int32(fleet.squadrons.len)
    # Assuming 1 scout per squadron in a scout-only fleet

  if numScouts == 0:
    logWarn("Intelligence", "Spy fleet has no scouts for detection check", "fleetId=", $fleetId)
    return true

  # 2. Get defender's info using safe accessors
  let colonyOpt = state_helpers.colony(state, ColonyId(targetSystem))
  if colonyOpt.isNone:
    # No colony, no owner, no detection
    return false

  let colony = colonyOpt.get()
  let defender = colony.owner

  if defender == attacker:
    # Spying on self? No detection
    return false

  let defenderHouseOpt = state_helpers.house(state, defender)
  if defenderHouseOpt.isNone:
    logWarn("Intelligence", "Defender house not found for detection check", "defender=", $defender)
    return false # No defender, no detection

  let defenderHouse = defenderHouseOpt.get()
  let defenderELI = defenderHouse.techTree.levels.eli

  # 3. Get starbase bonus (+2 ELI for detection per assets.md:2.4.2)
  let starbaseBonus: int32 = if colony.starbaseIds.len > 0: 2 else: 0

  # 4. Calculate target number
  let targetNumber = 15 - numScouts + (defenderELI + starbaseBonus)

  # 5. Roll 1d20 (result 1-20)
  let roll = int32(rng.rand(1 .. 20))

  let detected = roll >= targetNumber

  if detected:
    logInfo(
      "Intelligence",
      "Spy mission DETECTED",
      "attacker=", $attacker,
      " defender=", $defender,
      " system=", $targetSystem,
      " roll=", $roll,
      " target=", $targetNumber,
    )
  else:
    logInfo(
      "Intelligence",
      "Spy mission UNDETECTED",
      "attacker=", $attacker,
      " defender=", $defender,
      " system=", $targetSystem,
      " roll=", $roll,
      " target=", $targetNumber,
    )

  return detected

proc resolveSpyScoutDetection*(
    state: GameState,
    scoutCount: int32,
    defender: HouseId,
    targetSystem: SystemId,
    rng: var Rand,
): SpyDetectionResult =
  ## Resolve detection for active spy mission (fleet-based system)
  ## Takes scout count directly instead of looking up fleet
  ## Returns SpyDetectionResult with detected flag and roll details

  # Get defender's ELI level using safe accessor
  let defenderHouseOpt = state_helpers.house(state, defender)
  if defenderHouseOpt.isNone:
    logWarn("Intelligence", "Defender house not found for detection check", "defender=", $defender)
    # No defender house found, detection fails (spies succeed)
    return SpyDetectionResult(detected: false, roll: 0, threshold: 0)

  let defenderHouse = defenderHouseOpt.get()
  let defenderELI = defenderHouse.techTree.levels.eli

  # Get starbase bonus (+2 ELI for detection per assets.md:2.4.2)
  var starbaseBonus: int32 = 0
  let colonyOpt = state_helpers.colony(state, ColonyId(targetSystem))
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    starbaseBonus = if colony.starbaseIds.len > 0: 2 else: 0

  # Calculate target number
  let targetNumber = 15 - scoutCount + (defenderELI + starbaseBonus)

  # Roll 1d20 (result 1-20)
  let roll = int32(rng.rand(1 .. 20))

  let detected = roll >= targetNumber

  if detected:
    logInfo(
      "Intelligence",
      "Spy mission DETECTED",
      "defender=", $defender,
      " system=", $targetSystem,
      " roll=", $roll,
      " target=", $targetNumber,
    )
  else:
    logDebug(
      "Intelligence",
      "Spy mission UNDETECTED",
      "defender=", $defender,
      " system=", $targetSystem,
      " roll=", $roll,
      " target=", $targetNumber,
    )

  return SpyDetectionResult(detected: detected, roll: roll, threshold: targetNumber)
