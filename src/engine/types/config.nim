import std/tables
import ./[core, ship, ground_unit, facilities]

type
  ConfigError* = object of CatchableError

  CombatConfig* = object
    criticalHitRoll*: int32
    retreatAfterRound*: int32
    starbaseCriticalReroll*: bool
    starbaseDieModifier*: int32

  EconomyConfig* = object
    startingTreasury*: int32
    startingPopulation*: int32
    startingInfrastructure*: int32
    naturalGrowthRate*: float32
    researchCostBase*: int32
    researchCostExponent*: int32
    ebpCostPerPoint*: int32
    cipCostPerPoint*: int32

  PrestigeConfig* = object
    startingPrestige*: int32
    victoryThreshold*: int32
    defeatThreshold*: int32
    defeatConsecutiveTurns*: int32

  GameConfig* = object
    ships*: Table[ShipClass, ShipStats]
    groundUnits*: Table[GroundUnitType, GroundUnitStats]
    facilities*: Table[FacilityType, FacilityStats]
    combat*: CombatConfig
    economy*: EconomyConfig
    prestige*: PrestigeConfig
