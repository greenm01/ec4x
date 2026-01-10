## Planetary Shield Capacity Enforcement System
##
## Implements planetary shield limits per assets.md Section 2.4.7
##
## Capacity Formula: Max Shields = 1 per colony
##
## **IMPORTANT:** Only one planetary shield per colony is allowed.
## To upgrade, players must salvage the existing shield (50% refund)
## and build a new one at a higher SLD tier.
##
## Enforcement: Build validation only (no runtime enforcement needed)
##
## Data-oriented design: Pure calculation functions for build validation

import std/[options]
import
  ../../types/[core, game_state, ground_unit, production, colony]
import ../../state/[engine, iterators]
import ../../globals
import ../../../common/logger

proc countPlanetaryShields*(state: GameState, colony: Colony): int32 =
  ## Count operational planetary shields at a colony
  ## Checks colony.groundUnitIds for PlanetaryShield units
  result = 0'i32
  for unitId in colony.groundUnitIds:
    let unitOpt = state.groundUnit(unitId)
    if unitOpt.isSome:
      let unit = unitOpt.get()
      if unit.stats.unitType == GroundClass.PlanetaryShield:
        result += 1'i32

proc countPlanetaryShieldsUnderConstruction*(
    state: GameState, colonyId: ColonyId
): int32 =
  ## Count planetary shields currently under construction at a colony
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
      if project.groundClass == some(GroundClass.PlanetaryShield):
        result += 1'i32

  # Check construction queue
  for projectId in colony.constructionQueue:
    let projectOpt = state.constructionProject(projectId)
    if projectOpt.isSome:
      let project = projectOpt.get()
      if project.groundClass == some(GroundClass.PlanetaryShield):
        result += 1'i32

type
  CapacityViolation* = object
    current*: int32
    maximum*: int32
    underConstruction*: int32

proc canBuildPlanetaryShield*(state: GameState, colony: Colony): bool =
  ## Check if colony can build a new planetary shield
  ## Returns false if colony already has a shield or one under construction
  ## Uses gameConfig.limits.quantityLimits.maxPlanetaryShieldsPerColony
  ##
  ## Pure function - no mutations

  let maxShields = gameConfig.limits.quantityLimits.maxPlanetaryShieldsPerColony
  let currentShields = state.countPlanetaryShields(colony)
  let underConstruction = state.countPlanetaryShieldsUnderConstruction(colony.id)

  let total = currentShields + underConstruction

  if total >= maxShields:
    logDebug(
      "Capacity",
      "Planetary shield build rejected",
      " colony=", $colony.id,
      " current=", $currentShields,
      " underConstruction=", $underConstruction,
      " max=", $maxShields
    )
    return false

  return true

proc analyzeCapacity*(state: GameState, colony: Colony): CapacityViolation =
  ## Analyze planetary shield capacity for error reporting
  ## Returns current count, maximum, and under-construction count
  let maxShields = gameConfig.limits.quantityLimits.maxPlanetaryShieldsPerColony
  let currentShields = state.countPlanetaryShields(colony)
  let underConstruction = state.countPlanetaryShieldsUnderConstruction(colony.id)

  result = CapacityViolation(
    current: currentShields + underConstruction,
    maximum: maxShields,
    underConstruction: underConstruction,
  )

## Design Notes:
##
## **Simpler than other capacity modules:**
## - No grace period (hard limit at build time)
## - No enforcement phase (cannot exceed limit via normal gameplay)
## - No auto-scrap logic (shields can't be orphaned like planet-breakers)
##
## **Upgrade Path:**
## Players must salvage their existing shield (50% refund) before building
## a new one at a higher SLD tier. This is handled by the ScrapCommand system.
##
## **Spec Compliance:**
## - assets.md:2.4.7: One shield per colony
## - Limit stored in config/limits.kdl [quantityLimits].maxPlanetaryShieldsPerColony
##
## **Integration Points:**
## - Call canBuildPlanetaryShield() in build command validation
## - No runtime enforcement needed
