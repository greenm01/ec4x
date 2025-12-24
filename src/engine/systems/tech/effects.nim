## Research Effects
##
## Tech level effects on game systems per economy.md:4.0
##
## Tech effects implemented here:
## - WEP: +10% AS/DS per level (combat)
## - EL: +5% GCO per level (economy)
## - CST: Dock capacity multiplier (facility docks)
## - TER: Terraforming cost and requirements
##
## Tech effects implemented elsewhere:
## - CST: Squadron limit (gamestate.nim)
## - ELI: Detection system (intelligence/detection.nim)
## - CLK: Cloaking system (intelligence/detection.nim)
## - SLD: Planetary shields (combat/ground.nim)
## - CIC: Counter-intelligence (espionage/types.nim)
## - FD: Fighter capacity multiplier (economy/fighter_capacity.nim)
## - ACO: Carrier capacity (implemented here)

import ../../types/[core, game_state, tech, command]
import ../../state/[game_state, iterators]
import ../../config/tech_config
import ../../../common/logger
import std/options

export tech.TechLevel

## Economic Level Effects (economy.md:4.2)

proc getEconomicBonus*(elLevel: int): float =
  ## Get GCO bonus from Economic Level
  ## Per economy.md:4.2: +5% per level, max 50%
  result = min(float(elLevel) * 0.05, 0.50)

proc applyEconomicBonus*(gco: int, elLevel: int): int =
  ## Apply EL bonus to GCO
  let bonus = getEconomicBonus(elLevel)
  result = int(float(gco) * (1.0 + bonus))

## Weapons Tech Effects (economy.md:4.6)

proc getWeaponsBonus*(wepLevel: int): float =
  ## Get AS/DS bonus from Weapons tech
  ## Per economy.md:4.6: +10% per level
  result = float(wepLevel) * 0.10

proc applyWeaponsBonus*(baseAS: int, wepLevel: int): int =
  ## Apply WEP bonus to Attack Strength
  let bonus = getWeaponsBonus(wepLevel)
  result = int(float(baseAS) * (1.0 + bonus))

proc applyDefenseBonus*(baseDS: int, wepLevel: int): int =
  ## Apply WEP bonus to Defense Strength
  ## Note: WEP affects both AS and DS
  let bonus = getWeaponsBonus(wepLevel)
  result = int(float(baseDS) * (1.0 + bonus))

## Construction Tech Effects (economy.md:4.5)

proc getConstructionCapacityMultiplier*(cstLevel: int): float =
  ## Get production capacity multiplier from CST tech
  ## Per economy.md:4.5: +10% per level (construction capacity increases)
  ## This affects GCO calculation by boosting industrial output
  result = 1.0 + (float(cstLevel - 1) * 0.10)

proc getDockCapacityMultiplier*(cstLevel: int): float =
  ## Get dock capacity multiplier from CST tech
  ## Per economy.md:4.5: +10% per level (dock count increases)
  ## Formula: effectiveDocks = baseDocks × (1.0 + (CST - 1) × multiplier)
  ## Pulls multiplier from config/tech.toml
  let multiplierPerLevel =
    if globalTechConfig.construction_tech.capacity_multiplier_per_level.isSome:
      globalTechConfig.construction_tech.capacity_multiplier_per_level.get()
    else:
      0.10 # Default fallback
  result = 1.0 + (float(cstLevel - 1) * multiplierPerLevel)

proc calculateEffectiveDocks*(baseDocks: int, cstLevel: int): int =
  ## Calculate effective dock capacity based on CST technology
  ## Per economy.md:4.5 - Dock Count = base_docks × CST_MULTIPLIER (rounded down)
  let multiplier = getDockCapacityMultiplier(cstLevel)
  result = int(float(baseDocks) * multiplier)

## Electronic Intelligence Effects (economy.md:4.8)
## NOTE: Full ELI detection system implemented in intelligence/detection.nim
## This module does not provide ELI functions - use intelligence/detection.nim

proc getELICounterCloakBonus*(eliLevel: int): int =
  ## Get bonus to detect cloaked raiders
  ## Used for quick calculations where full detection system not needed
  result = eliLevel div 2 # +1 per 2 levels

## Terraforming Effects (economy.md:4.7)

proc getTerraformingBaseCost*(currentClass: int): int =
  ## Get base PP cost for terraforming to next class
  ## Per economy.md Section 4.7 and config/tech.toml
  ##
  ## Costs by target class:
  ## Extreme (1) -> Desolate (2): 60 PP
  ## Desolate (2) -> Hostile (3): 180 PP
  ## Hostile (3) -> Harsh (4): 500 PP
  ## Harsh (4) -> Benign (5): 1000 PP
  ## Benign (5) -> Lush (6): 1500 PP
  ## Lush (6) -> Eden (7): 2000 PP
  case currentClass
  of 1:
    60
  # Extreme -> Desolate
  of 2:
    180
  # Desolate -> Hostile
  of 3:
    500
  # Hostile -> Harsh
  of 4:
    1000
  # Harsh -> Benign
  of 5:
    1500
  # Benign -> Lush
  of 6:
    2000
  # Lush -> Eden
  else:
    0 # Already Eden or invalid

proc getTerraformingSpeed*(terLevel: int): int =
  ## Terraforming completes instantly (1 turn)
  ## Per new time narrative: turns represent variable time periods (1-15 years)
  ## TER level affects cost only, not duration
  result = 1 # Always instant

proc canTerraform*(currentClass: int, terLevel: int): bool =
  ## Check if colony can be terraformed with current TER level
  ## Must have TER level equal to target class
  let targetClass = currentClass + 1
  if targetClass > 7:
    return false # Already Eden
  return terLevel >= targetClass

## Cloaking Effects (economy.md:4.9)
## NOTE: Full cloaking system implemented in intelligence/detection.nim
## Use detection.nim for CLK detection difficulty calculations

## Planetary Shields Effects (economy.md:4.10)
## NOTE: Full shield system implemented in combat/ground.nim
## Use gamestate shield lookup functions for shield block percentages

## Counter-Intelligence Effects (economy.md:4.11)
## NOTE: Full CIC system implemented in espionage/types.nim
## Use espionage detection thresholds for CIC mechanics

## Fighter Doctrine Effects (economy.md:4.12)
## NOTE: Fighter capacity multiplier system implemented in economy/capacity/fighter.nim
## Formula: Max FS = floor(IU / 100) × FD Multiplier (IU-based, not PU-based)
## Use getFighterDoctrineMultiplier() for capacity calculations

## Advanced Carrier Operations Effects (economy.md:4.13)
## NOTE: Full ACO carrier capacity system implemented in squadron.nim
## Use squadron.getCarrierCapacity() for capacity calculations
##
## ACO capacity progression:
## - ACO I: CV=3FS, CX=5FS (starting tech)
## - ACO II: CV=4FS, CX=6FS
## - ACO III: CV=5FS, CX=8FS

proc getCarrierCapacityCV*(acoLevel: int): int =
  ## Get Carrier (CV) fighter capacity for ACO tech level
  ## Per economy.md:4.13
  case acoLevel
  of 1:
    3
  # ACO I
  of 2:
    4
  # ACO II
  else:
    5 # ACO III+

proc getCarrierCapacityCX*(acoLevel: int): int =
  ## Get Super Carrier (CX) fighter capacity for ACO tech level
  ## Per economy.md:4.13
  case acoLevel
  of 1:
    5
  # ACO I
  of 2:
    6
  # ACO II
  else:
    8 # ACO III+
