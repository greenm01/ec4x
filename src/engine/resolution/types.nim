## Common types for resolution modules

import std/[options]
import ../../common/types/core

type
  GameEvent* = object
    eventType*: GameEventType
    houseId*: HouseId
    description*: string
    systemId*: Option[SystemId]

  GameEventType* {.pure.} = enum
    ColonyEstablished, SystemCaptured, ColonyCaptured, TerraformComplete,
    Battle, BattleOccurred, Bombardment, FleetDestroyed, InvasionRepelled,
    ConstructionStarted, ShipCommissioned, BuildingCompleted, UnitRecruited, UnitDisbanded,
    TechAdvance, HouseEliminated, PopulationTransfer, IntelGathered

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int
    defenderLosses*: int
    victor*: Option[HouseId]
