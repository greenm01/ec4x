## Staging Area Selection Sub-module
## Selects optimal staging areas for fleet rendezvous (2-3 jumps from objectives)
##
## Strategy:
## - Find systems 2-3 jumps from target objectives (not too close, not too far)
## - Prefer owned/friendly systems for safety
## - Fallback to homeworld if no suitable staging area found

import std/[options, tables, algorithm]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, fleet, starmap]
import ../controller_types
import ../config  # For globalRBAConfig

proc evaluateStagingCandidate(
  candidate: SystemId,
  targetSystem: SystemId,
  filtered: FilteredGameState,
  controller: AIController
): Option[float] =
  ## Evaluate a candidate staging area for fleet rendezvous
  ## Returns priority score (higher = better), or None if unsuitable

  # Calculate distance to target
  let pathResult = filtered.starMap.findPath(candidate, targetSystem, Fleet())
  if not pathResult.found:
    return none(float)

  let distance = pathResult.path.len

  # Ideal distance: 2-3 jumps from target
  if distance < 1 or distance > 5:
    return none(float)  # Too close or too far

  var priority = 0.0

  # Distance scoring (prefer 2-3 jumps)
  if distance == 2 or distance == 3:
    priority += 100.0  # Ideal distance
  elif distance == 1:
    priority += controller.rbaConfig.domestikos_staging.priority_acceptable_close   # Acceptable but close
  elif distance == 4 or distance == 5:
    priority += controller.rbaConfig.domestikos_staging.priority_acceptable_far   # Acceptable but far

  # Safety bonus: owned systems are safer
  var isOwnedSystem = false
  for colony in filtered.ownColonies:
    if colony.systemId == candidate:
      isOwnedSystem = true
      break

  if isOwnedSystem:
    priority += controller.rbaConfig.domestikos_staging.priority_owned_system  # Strong preference for owned systems

  # Proximity to homeworld (prefer closer to home for supply lines)
  let pathToHome = filtered.starMap.findPath(candidate, controller.homeworld, Fleet())
  if pathToHome.found:
    let distanceFromHome = pathToHome.path.len
    # Closer to home is better (within reason)
    if distanceFromHome <= 5:
      priority += (5.0 - distanceFromHome.float) * 10.0

  return some(priority)

proc selectStagingArea*(
  filtered: FilteredGameState,
  controller: AIController,
  targetSystem: SystemId
): SystemId =
  ## Select optimal staging area for fleet rendezvous near target
  ## Returns system 2-3 jumps from target, preferring owned/safe systems

  # Build list of candidate staging areas
  type StagingCandidate = tuple[systemId: SystemId, priority: float]
  var candidates: seq[StagingCandidate] = @[]

  # Consider all systems we've scouted as potential staging areas
  for systemId, system in filtered.starMap.systems:
    let evaluation = evaluateStagingCandidate(
      systemId, targetSystem, filtered, controller
    )

    if evaluation.isSome:
      candidates.add((systemId, evaluation.get()))

  # Sort by priority (highest first)
  candidates.sort(proc(a, b: StagingCandidate): int =
    if a.priority > b.priority: -1
    elif a.priority < b.priority: 1
    else: 0
  )

  # Return best candidate, or homeworld as fallback
  if candidates.len > 0:
    return candidates[0].systemId
  else:
    return controller.homeworld

proc selectStagingAreaForGeneral*(
  filtered: FilteredGameState,
  controller: AIController
): SystemId =
  ## Select general staging area when no specific target (e.g., frontline position)
  ## Prefers owned colonies on the frontier (far from homeworld)

  if filtered.ownColonies.len <= 1:
    # Only homeworld - use it as staging
    return controller.homeworld

  # Find frontier colonies (furthest from homeworld)
  var coloniesByDistance: seq[tuple[colony: Colony, distance: int]] = @[]

  for colony in filtered.ownColonies:
    if colony.systemId == controller.homeworld:
      continue  # Skip homeworld

    let pathResult = filtered.starMap.findPath(
      colony.systemId, controller.homeworld, Fleet()
    )

    if pathResult.found:
      coloniesByDistance.add((colony, pathResult.path.len))

  # Sort by distance (furthest first)
  coloniesByDistance.sort(proc(a, b: auto): int =
    if a.distance > b.distance: -1
    elif a.distance < b.distance: 1
    else: 0
  )

  # Return frontier colony, or homeworld if none found
  if coloniesByDistance.len > 0:
    return coloniesByDistance[0].colony.systemId
  else:
    return controller.homeworld
