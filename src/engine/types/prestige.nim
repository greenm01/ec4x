## Prestige System Types
##
## Core types for prestige tracking and victory conditions

import ./core

type
  PrestigeSource* {.pure.} = enum
    CombatVictory, TaskForceDestroyed, FleetRetreated, SquadronDestroyed,
    ColonySeized, ColonyEstablished, TechAdvancement, LowTaxBonus,
    HighTaxPenalty, BlockadePenalty, MaintenanceShortfall,
    PactViolation, Eliminated

  PrestigeEvent* = object
    source*: PrestigeSource
    amount*: int32
    description*: string

  PrestigeReport* = object
    houseId*: HouseId
    turn*: int32
    startingPrestige*: int32
    events*: seq[PrestigeEvent]
    endingPrestige*: int32
