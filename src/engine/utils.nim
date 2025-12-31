## Accessors for commonly-used values

import std/[strutils, strformat, tables]
import ./types/[starmap, ship, tech, config, validation]

import ./globals

proc techLevel[T](
  levels: Table[int32, T],
  level: int32,
  techName: string,
  minLevel: int32 = 1,
  maxLevel: int32 = 15
): T =
  ## Retrieve tech level data with validation
  ## Raises ValidationError if level is out of bounds or doesn't exist
  if level < minLevel or level > maxLevel:
    raise newException(
      ValidationError,
      &"{techName} level must be between {minLevel} and {maxLevel}, got {level}"
    )

  if not levels.hasKey(level):
    raise newException(
      ValidationError,
      &"{techName} level {level} does not exist in configuration"
    )

  return levels[level]

proc soulsPerPtu*(): int32 =
  gameConfig.economy.ptuDefinition.soulsPerPtu

proc ptuSizeMillions*(): float32 =
  gameConfig.economy.ptuDefinition.ptuSizeMillions

proc minViablePopulation*(): int32 =
  gameConfig.economy.population.minViableColonyPop

## Enum parsing utilities

proc parsePlanetClass*(className: string): PlanetClass =
  ## Parse planet class string from config
  case className.toLower()
  of "extreme":
    PlanetClass.Extreme
  of "desolate":
    PlanetClass.Desolate
  of "hostile":
    PlanetClass.Hostile
  of "harsh":
    PlanetClass.Harsh
  of "benign":
    PlanetClass.Benign
  of "lush":
    PlanetClass.Lush
  of "eden":
    PlanetClass.Eden
  else:
    raise newException(ValueError, "Invalid planet class: " & className)

proc parseResourceRating*(ratingName: string): ResourceRating =
  ## Parse resource rating string from config
  case ratingName.toLower()
  of "verypoor", "very_poor":
    ResourceRating.VeryPoor
  of "poor":
    ResourceRating.Poor
  of "abundant":
    ResourceRating.Abundant
  of "rich":
    ResourceRating.Rich
  of "veryrich", "very_rich":
    ResourceRating.VeryRich
  else:
    raise newException(ValueError, "Invalid resource rating: " & ratingName)

proc shipConfig*(shipClass: ShipClass): ShipStatsConfig =
  ## Get configuration for a ship class
  ## Direct array access - O(1) lookup
  gameConfig.ships.ships[shipClass]

proc elUpgradeCost*(level: int32): int32 =
  ## Get ERP cost for advancing from level N to N+1
  ## Uses loaded config data from tech.kdl
  let cfg = gameConfig.tech.el
  return techLevel(cfg.levels, level, "EL", 2, 10).erpCost

proc slUpgradeCost*(level: int32): int32 =
  ## Get SRP cost for advancing from level N to N+1
  let cfg = gameConfig.tech.sl
  return techLevel(cfg.levels, level, "SL", 2, 10).srpRequired

proc techUpgradeCost*(techField: TechField, level: int32): int32 =
  ## Get TRP/SRP cost for advancing from level N to N+1
  ## Looks up cost from gameConfig.tech based on field and level

  case techField
  of TechField.ConstructionTech:
    let cfg = gameConfig.tech.cst
    return techLevel(cfg.levels, level, "CST", 2, 10).trpCost

  of TechField.WeaponsTech:
    let cfg = gameConfig.tech.wep
    return techLevel(cfg.levels, level, "WEP", 2, 10).trpCost

  of TechField.TerraformingTech:
    if level < 1 or level > 6:
      # Level 7+ uses formula (if needed)
      return 60 + (level - 6) * 10
    let cfg = gameConfig.tech.ter
    return techLevel(cfg.levels, level, "TER", 1, 6).srpCost

  of TechField.ElectronicIntelligence:
    let cfg = gameConfig.tech.eli
    return techLevel(cfg.levels, level, "ELI", 1, 15).srpCost

  of TechField.CloakingTech:
    let cfg = gameConfig.tech.clk
    return techLevel(cfg.levels, level, "CLK", 1, 15).srpCost

  of TechField.ShieldTech:
    let cfg = gameConfig.tech.sld
    return techLevel(cfg.levels, level, "SLD", 1, 6).srpCost

  of TechField.CounterIntelligence:
    let cfg = gameConfig.tech.cic
    return techLevel(cfg.levels, level, "CIC", 1, 15).srpCost

  of TechField.StrategicLiftTech:
    let cfg = gameConfig.tech.stl
    return techLevel(cfg.levels, level, "STL", 1, 15).srpCost

  of TechField.FlagshipCommandTech:
    let cfg = gameConfig.tech.fc
    return techLevel(cfg.levels, level, "FC", 2, 6).trpCost

  of TechField.StrategicCommandTech:
    let cfg = gameConfig.tech.sc
    return techLevel(cfg.levels, level, "SC", 1, 5).trpCost

  of TechField.FighterDoctrine:
    let cfg = gameConfig.tech.fd
    return techLevel(cfg.levels, level, "FD", 2, 3).trpCost

  of TechField.AdvancedCarrierOps:
    let cfg = gameConfig.tech.aco
    return techLevel(cfg.levels, level, "ACO", 1, 3).trpCost

proc taxTier*(tier: int32): TaxTierData =
  ## Get tax tier data with validation
  ## Tax tiers range from 1 (lowest tax) to 5 (highest tax)
  let cfg = gameConfig.economy.taxPopulationGrowth
  return techLevel(cfg.tiers, tier, "Tax Tier", 1, 5)
