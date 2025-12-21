## Game Setup Validation
##
## Validates game setup parameters before initialization.
## Ensures configuration values are within acceptable ranges.
##
## Part of the game initialization refactoring (Phase 2).

import ../types/tech

proc validateTechTree*(techTree: TechTree) =
  ## Validate that technology levels are within valid ranges
  ## Per economy.md:4.0: "ALL technology levels start at level 1, never 0"
  ##
  ## This validation is automatically called by:
  ## - initializeHouse() when creating new houses
  ## - Manual House creation should also call this or use initTechTree()
  ##
  ## Common mistake in tests: Creating House() without techTree field
  ## Fix: Always include `techTree: res_types.initTechTree()` in House
  ## constructors
  if techTree.levels.economicLevel < 1:
    raise newException(ValueError,
      "EL (Economics Level) cannot be less than 1. Found: " &
      $techTree.levels.economicLevel &
      ". Use initTechTree() to create valid tech tree.")
  if techTree.levels.scienceLevel < 1:
    raise newException(ValueError,
      "SL (Science Level) cannot be less than 1. Found: " &
      $techTree.levels.scienceLevel &
      ". Use initTechTree() to create valid tech tree.")
  if techTree.levels.economicLevel > 11:
    raise newException(ValueError,
      "EL (Economics Level) cannot exceed 11. Found: " &
      $techTree.levels.economicLevel)
  if techTree.levels.scienceLevel > 11:
    raise newException(ValueError,
      "SL (Science Level) cannot exceed 11. Found: " &
      $techTree.levels.scienceLevel)
