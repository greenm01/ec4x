## Act Progression System Types
##
## Dynamic 4-act strategic progression system
## Per docs/ai/architecture/ai_architecture.adoc

import ./core

type
  GameAct* {.pure.} = enum
    Act1_LandGrab
    Act2_RisingTensions
    Act3_TotalWar
    Act4_Endgame

  ActProgressionState* = object
    currentAct*: GameAct
    actStartTurn*: int32
    act2TopThreeHouses*: seq[HouseId]  # Top 3 houses by prestige at Act 2 start

  ActProgressionConfig* = object
    act1_to_act2_colonization_threshold*: float32
    act3_to_act4_prestige_threshold*: float32
