## Prestige System Types
##
## Core types for prestige tracking and victory conditions

import ../../common/types/core

export core.HouseId

type
  PrestigeSource* {.pure.} = enum
    ## Sources of prestige gain/loss
    CombatVictory,          # Win space battle
    TaskForceDestroyed,     # Destroy enemy task force
    FleetRetreated,         # Force enemy retreat
    SquadronDestroyed,      # Destroy individual squadron
    ColonySeized,           # Capture colony via invasion
    ColonyEstablished,      # Establish new colony
    TechAdvancement,        # Advance tech level
    LowTaxBonus,            # Low tax rate bonus (per colony)
    HighTaxPenalty,         # High tax average penalty
    BlockadePenalty,        # Colony under blockade
    MaintenanceShortfall,   # Failed to pay maintenance
    PactViolation,          # Violated non-aggression pact
    Eliminated,             # House eliminated from game

  PrestigeEvent* = object
    ## Single prestige gain/loss event
    source*: PrestigeSource
    amount*: int            # Positive = gain, negative = loss
    description*: string    # Event description for reports

  PrestigeReport* = object
    ## Prestige changes for a turn
    houseId*: HouseId
    startingPrestige*: int
    events*: seq[PrestigeEvent]
    endingPrestige*: int
