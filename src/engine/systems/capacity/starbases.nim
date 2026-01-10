## Starbase Capacity Enforcement System
##
## Implements starbase limits per assets.md Section 2.4.4
##
## Capacity Formula: Max Starbases = 3 per colony
##
## **IMPORTANT:** Maximum of 3 starbases per colony.
## Economic bonuses (population growth and industrial production) cap at 15%
## (3 starbases × 5% each). Additional starbases provide no benefit.
##
## Enforcement: Build validation only (no runtime enforcement needed)
##
## Data-oriented design: Pure calculation functions for build validation

import std/[options]
import
  ../../types/[core, game_state, facilities, production, colony]
import ../../state/engine
import ../../globals
import ../../../common/logger

proc countStarbases*(state: GameState, colony: Colony): int32 =
  ## Count operational starbases at a colony
  ## Checks colony.kastraIds for Starbase units
  result = 0'i32
  for kastraId in colony.kastraIds:
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isSome:
      let kastra = kastraOpt.get()
      if kastra.kastraClass == KastraClass.Starbase:
        result += 1'i32

proc countStarbasesUnderConstruction*(
    state: GameState, colonyId: ColonyId
): int32 =
  ## Count starbases currently under construction at a colony
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
      if project.facilityClass == some(FacilityClass.Starbase):
        result += 1'i32

  # Check construction queue
  for projectId in colony.constructionQueue:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      if project.facilityClass == some(FacilityClass.Starbase):
        result += 1'i32

type
  CapacityViolation* = object
    current*: int32
    maximum*: int32
    underConstruction*: int32

proc canBuildStarbase*(state: GameState, colony: Colony): bool =
  ## Check if colony can build a new starbase
  ## Returns false if colony already has 3 starbases or would exceed with
  ## current construction
  ## Uses gameConfig.limits.quantityLimits.maxStarbasesPerColony
  ##
  ## Pure function - no mutations

  let maxStarbases = gameConfig.limits.quantityLimits.maxStarbasesPerColony
  let currentStarbases = state.countStarbases(colony)
  let underConstruction = state.countStarbasesUnderConstruction(colony.id)

  let total = currentStarbases + underConstruction

  if total >= maxStarbases:
    logDebug(
      "Capacity",
      "Starbase build rejected",
      " colony=", $colony.id,
      " current=", $currentStarbases,
      " underConstruction=", $underConstruction,
      " max=", $maxStarbases
    )
    return false

  return true

proc analyzeCapacity*(state: GameState, colony: Colony): CapacityViolation =
  ## Analyze starbase capacity for error reporting
  ## Returns current count, maximum, and under-construction count
  let maxStarbases = gameConfig.limits.quantityLimits.maxStarbasesPerColony
  let currentStarbases = state.countStarbases(colony)
  let underConstruction = state.countStarbasesUnderConstruction(colony.id)

  result = CapacityViolation(
    current: currentStarbases + underConstruction,
    maximum: maxStarbases,
    underConstruction: underConstruction,
  )

## Design Notes:
##
## **Simpler than other capacity modules:**
## - No grace period (hard limit at build time)
## - No enforcement phase (cannot exceed limit via normal gameplay)
## - No auto-scrap logic (starbases are permanent defensive structures)
##
## **Economic Bonus Cap:**
## Economic bonuses (pop growth + industrial production) cap at 15% (3 starbases).
## This is handled by the production system in src/engine/systems/production/engine.nim
## which uses min(starbaseCount, 3) when calculating bonuses.
##
## **Spec Compliance:**
## - assets.md:2.4.4: Maximum 3 starbases per colony
## - reference.md Table 10.5: Starbase limit per colony
## - Limit stored in config/limits.kdl [quantityLimits].maxStarbasesPerColony
##
## **Integration Points:**
## - Call canBuildStarbase() in build command validation
## - No runtime enforcement needed
