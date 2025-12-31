## Game Setup Validation
##
## Validates game setup parameters before initialization.
## Ensures configuration values are within acceptable ranges.

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
  if techTree.levels.el < 1:
    raise newException(
      ValueError,
      "EL (Economics Level) cannot be less than 1. Found: " &
        $techTree.levels.el &
        ". Use initTechTree() to create valid tech tree.",
    )
  if techTree.levels.sl < 1:
    raise newException(
      ValueError,
      "SL (Science Level) cannot be less than 1. Found: " & $techTree.levels.sl &
        ". Use initTechTree() to create valid tech tree.",
    )
  if techTree.levels.el > 11:
    raise newException(
      ValueError,
      "EL (Economics Level) cannot exceed 11. Found: " & $techTree.levels.el,
    )
  if techTree.levels.sl > 11:
    raise newException(
      ValueError,
      "SL (Science Level) cannot exceed 11. Found: " & $techTree.levels.sl,
    )
