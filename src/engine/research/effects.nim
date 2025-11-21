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
  ## TODO: Define proper ELI detection mechanics
  result = eliLevel

proc getELICounterCloakBonus*(eliLevel: int): int =
  ## Get bonus to detect cloaked raiders
  result = eliLevel div 2  # +1 per 2 levels

## Terraforming Effects (economy.md:4.7)

proc getTerraformingCost*(terLevel: int, planetClass: int): int =
  ## Get cost to terraform planet
  ## Higher TER = lower cost
  ##
  ## TODO: Define proper terraforming costs
  ## Placeholder
  let baseCost = 1000
  let reduction = float(terLevel) * 0.10
  result = int(float(baseCost) * (1.0 - reduction))

proc getTerraformingSpeed*(terLevel: int): int =
  ## Get turns required for terraforming
  ## Higher TER = faster terraforming
  ##
  ## TODO: Define proper terraforming speed
  result = max(1, 10 - terLevel)

## Cloaking Effects (economy.md:4.9)

proc getCloakingDetectionDifficulty*(clkLevel: int): int =
  ## Get detection difficulty for cloaked ships
  ## Higher CLK = harder to detect
  ##
  ## TODO: Define proper cloaking mechanics
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
