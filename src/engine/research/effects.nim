## Research Effects
##
## Tech level effects on game systems per economy.md:4.0
##
## Tech effects:
## - WEP: +10% AS/DS per level (combat)
## - EL: +5% GCO per level (economy)
## - CST: +1 squadron limit per level (fleet capacity)
## - ELI: Detection bonus (scouts, raiders)
## - TER: Terraforming speed and cost
## - SLD: Planetary shields
## - CIC: Counter-intelligence

import ../../common/types/tech

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

proc getSquadronLimit*(cstLevel: int): int =
  ## Get squadron limit from Construction tech
  ## Per economy.md:4.5: Base + tech level
  ##
  ## TODO: Define base squadron limit
  ## Placeholder: 10 + level
  result = 10 + cstLevel

proc getConstructionSpeedBonus*(cstLevel: int): float =
  ## Get construction speed bonus
  ## Higher CST = faster ship/building construction
  ##
  ## TODO: Define proper CST speed bonus
  result = float(cstLevel) * 0.05  # +5% per level

## Electronic Intelligence Effects (economy.md:4.8)

proc getELIDetectionBonus*(eliLevel: int): int =
  ## Get detection bonus for scouts
  ## Per economy.md:4.8
  ##
  ## NOTE: Full ELI detection system implemented in intelligence/detection.nim
  ## This function returns basic level for simple calculations
  result = eliLevel

proc getELICounterCloakBonus*(eliLevel: int): int =
  ## Get bonus to detect cloaked raiders
  result = eliLevel div 2  # +1 per 2 levels

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
  of 1: 60    # Extreme -> Desolate
  of 2: 180   # Desolate -> Hostile
  of 3: 500   # Hostile -> Harsh
  of 4: 1000  # Harsh -> Benign
  of 5: 1500  # Benign -> Lush
  of 6: 2000  # Lush -> Eden
  else: 0     # Already Eden or invalid

proc getTerraformingSpeed*(terLevel: int): int =
  ## Get turns required for terraforming
  ## Higher TER = faster terraforming
  ## Per spec: 10 - TER_level turns (minimum 1)
  result = max(1, 10 - terLevel)

proc canTerraform*(currentClass: int, terLevel: int): bool =
  ## Check if colony can be terraformed with current TER level
  ## Must have TER level equal to target class
  let targetClass = currentClass + 1
  if targetClass > 7:
    return false  # Already Eden
  return terLevel >= targetClass

## Cloaking Effects (economy.md:4.9)

proc getCloakingDetectionDifficulty*(clkLevel: int): int =
  ## Get detection difficulty for cloaked ships
  ## Higher CLK = harder to detect
  ##
  ## NOTE: Full cloaking system implemented in intelligence/detection.nim
  ## Formula: d20 + ELI_total vs (10 + CLK_level)
  result = 10 + clkLevel

## Planetary Shields Effects (economy.md:4.10)

proc getPlanetaryShieldStrength*(sldLevel: int): int =
  ## Get planetary shield strength
  ## Reduces bombardment damage
  ##
  ## TODO: Define proper shield mechanics
  result = sldLevel * 10

## Counter-Intelligence Effects (economy.md:4.11)

proc getCICCounterEspionageBonus*(cicLevel: int): int =
  ## Get bonus to counter espionage attempts
  ##
  ## TODO: Define proper CIC mechanics
  result = cicLevel

## Fighter Doctrine Effects (economy.md:4.12)

proc getFighterDoctrineBonus*(fdLevel: int): float =
  ## Get fighter effectiveness bonus
  ##
  ## TODO: Define proper FD mechanics
  result = float(fdLevel) * 0.05

## Carrier Operations Effects (economy.md:4.13)

proc getCarrierCapacityBonus*(acoLevel: int): int =
  ## Get bonus fighter capacity for carriers
  ##
  ## TODO: Define proper ACO mechanics
  result = acoLevel * 2  # +2 fighters per level
