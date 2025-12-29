## Accessors for commonly-used values

import std/strutils
import ./types/[starmap, ship, tech, config]

import ./globals

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
  case shipClass
  of ShipClass.Fighter: gameConfig.ships.fighter
  of ShipClass.Corvette: gameConfig.ships.corvette
  of ShipClass.Frigate: gameConfig.ships.frigate
  of ShipClass.Scout: gameConfig.ships.scout
  of ShipClass.Raider: gameConfig.ships.raider
  of ShipClass.Destroyer: gameConfig.ships.destroyer
  of ShipClass.LightCruiser: gameConfig.ships.lightCruiser
  of ShipClass.Cruiser: gameConfig.ships.cruiser
  of ShipClass.Battlecruiser: gameConfig.ships.battlecruiser
  of ShipClass.Battleship: gameConfig.ships.battleship
  of ShipClass.Dreadnought: gameConfig.ships.dreadnought
  of ShipClass.SuperDreadnought: gameConfig.ships.superDreadnought
  of ShipClass.Carrier: gameConfig.ships.carrier
  of ShipClass.SuperCarrier: gameConfig.ships.supercarrier
  of ShipClass.ETAC: gameConfig.ships.etac
  of ShipClass.TroopTransport: gameConfig.ships.troopTransport
  of ShipClass.PlanetBreaker: gameConfig.ships.planetbreaker

proc elUpgradeCost*(level: int32): int32 =
  ## Get ERP cost for advancing from level N to N+1
  ## Uses loaded config data from tech.kdl
  let cfg = gameConfig.tech.economicLevel

  case level
  of 1: return cfg.level1Erp
  of 2: return cfg.level2Erp
  of 3: return cfg.level3Erp
  of 4: return cfg.level4Erp
  of 5: return cfg.level5Erp
  of 6: return cfg.level6Erp
  of 7: return cfg.level7Erp
  of 8: return cfg.level8Erp
  of 9: return cfg.level9Erp
  of 10: return cfg.level10Erp
  of 11: return cfg.level11Erp
  else:
    raise newException(
      ValueError,
      "Invalid EL level: " & $level & " (max is 11)"
    )

proc slUpgradeCost*(level: int32): int32 =
  ## Get SRP cost for advancing from level N to N+1
  let cfg = gameConfig.tech.scienceLevel

  case level
  of 1: return cfg.level1Srp
  of 2: return cfg.level2Srp
  of 3: return cfg.level3Srp
  of 4: return cfg.level4Srp
  of 5: return cfg.level5Srp
  of 6: return cfg.level6Srp
  of 7: return cfg.level7Srp
  of 8: return cfg.level8Srp
  else:
    raise newException(
      ValueError,
      "Invalid SL level: " & $level & " (max is 8)"
    )

proc techUpgradeCost*(techField: TechField, level: int32): int32 =
  ## Get TRP cost for advancing from level N to N+1
  ## Looks up cost from gameConfig.tech based on field and level

  case techField
  of TechField.ConstructionTech:
    let cfg = gameConfig.tech.constructionTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid CST level: " & $level & " (max is 15)"
      )
  of TechField.WeaponsTech:
    let cfg = gameConfig.tech.weaponsTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid WEP level: " & $level & " (max is 15)"
      )
  of TechField.TerraformingTech:
    let cfg = gameConfig.tech.terraformingTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    else: return 30 + (level - 7) * 5 # Level 8+
  of TechField.ElectronicIntelligence:
    let cfg = gameConfig.tech.electronicIntelligence
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid ELI level: " & $level & " (max is 15)"
      )
  of TechField.CloakingTech:
    let cfg = gameConfig.tech.cloakingTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid CLK level: " & $level & " (max is 15)"
      )
  of TechField.ShieldTech:
    let cfg = gameConfig.tech.shieldTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid SLD level: " & $level & " (max is 15)"
      )
  of TechField.CounterIntelligence:
    let cfg = gameConfig.tech.counterIntelligenceTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid CIC level: " & $level & " (max is 15)"
      )
  of TechField.FighterDoctrine:
    let cfg = gameConfig.tech.fighterDoctrine
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    else:
      raise newException(
        ValueError,
        "Invalid FD level: " & $level & " (max is 3)"
      )
  of TechField.AdvancedCarrierOps:
    let cfg = gameConfig.tech.advancedCarrierOperations
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    else:
      raise newException(
        ValueError,
        "Invalid ACO level: " & $level & " (max is 3)"
      )
