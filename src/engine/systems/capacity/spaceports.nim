## Spaceport Capacity Enforcement System
##
## Implements spaceport limits per assets.md Section 2.3.2.1
##
## Capacity Formula: Max Spaceports = 1 per colony
##
## **IMPORTANT:** Only one spaceport per colony is allowed.
## Additional construction capacity requires building Shipyards.
## To rebuild, players must salvage the existing spaceport first.
##
## Enforcement: Build validation only (no runtime enforcement needed)
##
## Data-oriented design: Pure calculation functions for build validation

import std/[options]
import
  ../../types/[core, game_state, facilities, production, colony]
import ../../state/[engine, iterators]
import ../../globals
import ../../../common/logger

proc countSpaceportsUnderConstruction*(
    state: GameState, colonyId: ColonyId
): int32 =
  ## Count spaceports currently under construction at a colony
  ## Checks both active construction and construction queue
  result = 0'i32

  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return

  let colony = colonyOpt.get()

  # Check underConstruction (single active project)
  if colony.underConstruction.isSome:
    let projectId = colony.underConstruction.get()
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      if project.facilityClass == some(FacilityClass.Spaceport):
        result += 1'i32

  # Check construction queue
  for projectId in colony.constructionQueue:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      if project.facilityClass == some(FacilityClass.Spaceport):
        result += 1'i32

type
  CapacityViolation* = object
    current*: int32
    maximum*: int32
    underConstruction*: int32

proc canBuildSpaceport*(state: GameState, colony: Colony): bool =
  ## Check if colony can build a new spaceport
  ## Returns false if colony already has a spaceport or one under construction
  ## Uses existing state.countSpaceportsAtColony() for operational count
  ## Uses gameConfig.limits.quantityLimits.maxSpaceportsPerColony
  ##
  ## Pure function - no mutations

  let maxSpaceports = gameConfig.limits.quantityLimits.maxSpaceportsPerColony
  let currentSpaceports = state.countSpaceportsAtColony(colony.id)
  let underConstruction = state.countSpaceportsUnderConstruction(colony.id)

  let total = currentSpaceports + underConstruction

  if total >= maxSpaceports:
    logDebug(
      "Capacity",
      "Spaceport build rejected",
      " colony=", $colony.id,
      " current=", $currentSpaceports,
      " underConstruction=", $underConstruction,
      " max=", $maxSpaceports
    )
    return false

  return true

proc analyzeCapacity*(state: GameState, colony: Colony): CapacityViolation =
  ## Analyze spaceport capacity for error reporting
  ## Returns current count, maximum, and under-construction count
  let maxSpaceports = gameConfig.limits.quantityLimits.maxSpaceportsPerColony
  let currentSpaceports = state.countSpaceportsAtColony(colony.id)
  let underConstruction = state.countSpaceportsUnderConstruction(colony.id)

  result = CapacityViolation(
    current: currentSpaceports + underConstruction,
    maximum: maxSpaceports,
    underConstruction: underConstruction,
  )

## Design Notes:
##
## **Simpler than other capacity modules:**
## - No grace period (hard limit at build time)
## - No enforcement phase (cannot exceed limit via normal gameplay)
## - No auto-scrap logic (spaceports can't be orphaned)
##
## **Rationale for limit:**
## Spaceports have a 100% PP cost penalty for ship construction.
## Players should build Shipyards for additional construction capacity.
## One spaceport is sufficient for the initial bootstrapping of a colony.
##
## **Spec Compliance:**
## - assets.md:2.3.2.1: One spaceport per colony
## - Limit stored in config/limits.kdl [quantityLimits].maxSpaceportsPerColony
##
## **Integration Points:**
## - Call canBuildSpaceport() in build command validation
## - No runtime enforcement needed
