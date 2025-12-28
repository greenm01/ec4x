## Prestige System Types
##
## Core types for prestige tracking and victory conditions
import std/options
import ./core

type
  PrestigeSource* {.pure.} = enum
    CombatVictory
    TaskForceDestroyed
    FleetRetreated
    SquadronDestroyed
    ColonySeized
    ColonyEstablished
    TechAdvancement
    LowTaxBonus
    HighTaxPenalty
    BlockadePenalty
    MaintenanceShortfall
    Eliminated

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

  ColonyPrestigeResult* = object ## Result of colony prestige calculation
    attackerEvent*: PrestigeEvent # Attacker gains (if seized)
    defenderEvent*: Option[PrestigeEvent] # Defender loses (if seized, zero-sum)

