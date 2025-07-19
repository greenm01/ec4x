## Common type definitions for EC4X core
##
## This module contains shared type definitions used across multiple
## EC4X core modules to avoid circular dependencies.

type
  LaneType* = enum
    ## Types of jump lanes between star systems
    Major,      ## Major lanes - easy to traverse (weight 1)
    Minor,      ## Minor lanes - moderate difficulty (weight 2)
    Restricted  ## Restricted lanes - only certain ships can use (weight 3)

proc weight*(laneType: LaneType): uint32 =
  ## Get the movement cost for a lane type
  case laneType
  of Major: 1
  of Minor: 2
  of Restricted: 3

proc `$`*(laneType: LaneType): string =
  ## String representation of lane type
  case laneType
  of Major: "Major"
  of Minor: "Minor"
  of Restricted: "Restricted"
