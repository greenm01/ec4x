## Act Progression System Types
##
## Dynamic 4-act strategic progression system
## Per docs/ai/architecture/ai_architecture.adoc

import ./core

type
  GameAct* {.pure.} = enum
    ## 4-Act game structure that scales with map size
    ## Each act has different strategic priorities
    Act1_LandGrab,      # Turns 1-7: Rapid colonization, exploration
    Act2_RisingTensions, # Turns 8-15: Consolidation, military buildup, diplomacy
    Act3_TotalWar,      # Turns 16-25: Major conflicts, invasions
    Act4_Endgame        # Turns 26-30: Final push for victory

  ActProgressionState* = object
    ## Global game act progression tracking (public information)
    ## Prestige and planet counts are on public leaderboard, so no FOW restrictions
    ## Per docs/ai/architecture/ai_architecture.adoc lines 279-300
    currentAct*: GameAct
    actStartTurn*: int32

    # Act 2 tracking: Snapshot top 3 houses at Act 2 start (90% colonization)
    act2TopThreeHouses*: seq[HouseId]
    act2TopThreePrestige*: seq[int]

    # Cached values for transition gates (diagnostics)
    lastColonizationPercent*: float32
    lastTotalPrestige*: int32

 
  ActProgressionConfig* = object
    act1_to_act2_colonization_threshold*: float32
    act3_to_act4_prestige_threshold*: float32
