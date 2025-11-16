## EC4X Combat Types
## Combat states, effectiveness, and lane types

# =============================================================================
# Star Map and Lane Types
# =============================================================================

type
  LaneType* {.pure.} = enum
    ## Jump lane classifications (hardcoded)
    ## Determines movement restrictions per game specs
    Major        ## Standard lanes, 2 jumps/turn if owned
    Minor        ## 1 jump/turn
    Restricted   ## 1 jump/turn, no crippled/spacelift ships

# =============================================================================
# Combat Types
# =============================================================================

type
  CombatState* {.pure.} = enum
    ## Unit combat readiness
    Undamaged
    Crippled
    Destroyed

  CombatEffectivenessRating* = float  ## CER multiplier (0.25 to 2.0)
