## Detection System for Spy Scouts and Raiders
##
## Implements ELI-based detection mechanics for spy scouts and cloaked raiders
## Based on assets.md Sections 2.4.2 and 2.4.3

import std/[math, random, sequtils, options, strutils]
import ../squadron
import ../config/espionage_config

export ThresholdRange, Option

type
  ELIUnit* = object
    ## A unit capable of ELI detection (fleet with scouts or starbase)
    eliLevels*: seq[int]  ## ELI tech levels of all scouts in unit
    isStarbase*: bool     ## True if this is a starbase (gets +2 ELI bonus vs spies)

  DetectionResult* = object
    ## Result of a detection attempt
    detected*: bool
    effectiveELI*: int
    threshold*: int
    roll*: int

## ELI Mesh Network Calculation

proc calculateWeightedAverageELI*(eliLevels: seq[int]): int =
  ## Calculate weighted average ELI level (step 1)
  ## Returns rounded-up average
  if eliLevels.len == 0:
    return 0

  let sum = eliLevels.foldl(a + b, 0)
  let avg = float(sum) / float(eliLevels.len)
  return int(ceil(avg))

proc applyDominantTechPenalty*(weightedAvg: int, eliLevels: seq[int]): int =
  ## Apply dominant tech level penalty (step 2)
  ## If >50% of scouts are below weighted average, reduce by 1
  if eliLevels.len == 0:
    return weightedAvg

  let belowCount = eliLevels.countIt(it < weightedAvg)
  let halfCount = float(eliLevels.len) / 2.0

  if float(belowCount) > halfCount:
    return max(1, weightedAvg - 1)
  else:
    return weightedAvg

proc getMeshNetworkBonus*(scoutCount: int): int =
  ## Calculate mesh network modifier based on scout count
  ## Per assets.md:2.4.2: 1=+0, 2-3=+1, 4-5=+2, 6+=+3
  let cfg = globalEspionageConfig.scout_detection

  if scoutCount <= 1:
    return 0
  elif scoutCount <= 3:
    return cfg.mesh_2_3_scouts
  elif scoutCount <= 5:
    return cfg.mesh_4_5_scouts
  else:
    return cfg.mesh_6_plus_scouts

proc calculateEffectiveELI*(eliLevels: seq[int], isStarbase: bool = false): int =
  ## Calculate final effective ELI level for detection
  ## Combines weighted average, dominant tech penalty, and mesh network bonus
  ## Starbases get +2 bonus against spy scouts
  if eliLevels.len == 0:
    return 0

  let cfg = globalEspionageConfig.scout_detection

  # Step 1: Weighted average
  let weightedAvg = calculateWeightedAverageELI(eliLevels)

  # Step 2: Dominant tech penalty
  let afterPenalty = applyDominantTechPenalty(weightedAvg, eliLevels)

  # Step 3: Mesh network modifier (only for fleets, not starbases)
  let meshBonus = if isStarbase: 0 else: getMeshNetworkBonus(eliLevels.len)

  # Step 4: Starbase bonus (only against spy scouts)
  let starbaseBonus = if isStarbase: cfg.starbase_eli_bonus else: 0

  # Final ELI (capped at max level)
  result = min(cfg.max_eli_level, afterPenalty + meshBonus + starbaseBonus)

## Spy Scout Detection

proc rollDetectionThreshold*(thresholdRange: ThresholdRange): int =
  ## Roll 1d3 to select value within threshold range
  ## Range is [min, max], roll determines which value to use
  let roll = rand(1..3)
  case roll
  of 1: thresholdRange[0]
  of 2: (thresholdRange[0] + thresholdRange[1]) div 2
  else: thresholdRange[1]

proc attemptSpyDetection*(
  detectorELI: int,
  spyELI: int
): DetectionResult =
  ## Attempt to detect a spy scout (using global RNG)
  ## Returns detection result with all roll details
  ##
  ## Process:
  ## 1. Get threshold range from detection table
  ## 2. Roll 1d3 to select threshold within range
  ## 3. Roll 1d20, if >= threshold then detected

  # Get threshold range from config
  let thresholdRange = getSpyDetectionThreshold(detectorELI, spyELI)

  # Roll for actual threshold (1d3)
  let threshold = rollDetectionThreshold(thresholdRange)

  # Roll for detection (1d20)
  let detectionRoll = rand(1..20)

  result = DetectionResult(
    detected: detectionRoll > threshold,
    effectiveELI: detectorELI,
    threshold: threshold,
    roll: detectionRoll
  )

proc attemptSpyDetection*(
  detectorELI: int,
  spyELI: int,
  rng: var Rand
): DetectionResult =
  ## Attempt to detect a spy scout (with provided RNG)
  ## Returns detection result with all roll details

  # Get threshold range from config
  let thresholdRange = getSpyDetectionThreshold(detectorELI, spyELI)

  # Roll for actual threshold (1d3)
  let roll3 = rng.rand(1..3)
  let threshold = case roll3
    of 1: thresholdRange[0]
    of 2: (thresholdRange[0] + thresholdRange[1]) div 2
    else: thresholdRange[1]

  # Roll for detection (1d20)
  let detectionRoll = rng.rand(1..20)

  result = DetectionResult(
    detected: detectionRoll > threshold,
    effectiveELI: detectorELI,
    threshold: threshold,
    roll: detectionRoll
  )

proc detectSpyScout*(
  detectorUnit: ELIUnit,
  spyELI: int
): DetectionResult =
  ## High-level spy scout detection (using global RNG)
  ## Calculates effective ELI and attempts detection

  let effectiveELI = calculateEffectiveELI(detectorUnit.eliLevels, detectorUnit.isStarbase)
  result = attemptSpyDetection(effectiveELI, spyELI)
  result.effectiveELI = effectiveELI

proc detectSpyScout*(
  detectorUnit: ELIUnit,
  spyELI: int,
  rng: var Rand
): DetectionResult =
  ## High-level spy scout detection (with provided RNG)
  ## Calculates effective ELI and attempts detection

  let effectiveELI = calculateEffectiveELI(detectorUnit.eliLevels, detectorUnit.isStarbase)
  result = attemptSpyDetection(effectiveELI, spyELI, rng)
  result.effectiveELI = effectiveELI

## Raider Detection

proc getRaiderThresholdStrategy*(eliLevel: int, cloakLevel: int): string =
  ## Determine which threshold to use based on ELI advantage
  ## Returns: "lower" if ELI is 2+ higher, "random" if equal/1 higher, "upper" if lower
  let advantage = eliLevel - cloakLevel

  if advantage >= 2:
    return "lower"
  elif advantage >= 0:
    return "random"
  else:
    return "upper"

proc rollRaiderThreshold*(
  thresholdRange: ThresholdRange,
  strategy: string
): int =
  ## Roll threshold based on strategy (using global RNG)
  ## "lower" = use min, "upper" = use max, "random" = roll 1d3
  case strategy
  of "lower":
    thresholdRange[0]
  of "upper":
    thresholdRange[1]
  of "random":
    rollDetectionThreshold(thresholdRange)
  else:
    thresholdRange[1]  # Default to upper

proc rollRaiderThreshold*(
  thresholdRange: ThresholdRange,
  strategy: string,
  rng: var Rand
): int =
  ## Roll threshold based on strategy (with provided RNG)
  case strategy
  of "lower":
    thresholdRange[0]
  of "upper":
    thresholdRange[1]
  of "random":
    let roll = rng.rand(1..3)
    case roll
    of 1: thresholdRange[0]
    of 2: (thresholdRange[0] + thresholdRange[1]) div 2
    else: thresholdRange[1]
  else:
    thresholdRange[1]

proc attemptRaiderDetection*(
  detectorELI: int,
  cloakLevel: int
): DetectionResult =
  ## Attempt to detect a cloaked raider fleet (using global RNG)
  ## Returns detection result with all roll details
  ##
  ## Process:
  ## 1. Get threshold range from detection table
  ## 2. Determine strategy based on ELI advantage
  ## 3. Apply strategy to get threshold
  ## 4. Roll 1d20, if >= threshold then detected

  # Get threshold range from config
  let thresholdRange = getRaiderDetectionThreshold(detectorELI, cloakLevel)

  # Determine strategy based on ELI advantage
  let strategy = getRaiderThresholdStrategy(detectorELI, cloakLevel)

  # Get threshold based on strategy
  let threshold = rollRaiderThreshold(thresholdRange, strategy)

  # Roll for detection (1d20)
  let detectionRoll = rand(1..20)

  result = DetectionResult(
    detected: detectionRoll > threshold,
    effectiveELI: detectorELI,
    threshold: threshold,
    roll: detectionRoll
  )

proc attemptRaiderDetection*(
  detectorELI: int,
  cloakLevel: int,
  rng: var Rand
): DetectionResult =
  ## Attempt to detect a cloaked raider fleet (with provided RNG)
  ## Returns detection result with all roll details

  # Get threshold range from config
  let thresholdRange = getRaiderDetectionThreshold(detectorELI, cloakLevel)

  # Determine strategy based on ELI advantage
  let strategy = getRaiderThresholdStrategy(detectorELI, cloakLevel)

  # Get threshold based on strategy
  let threshold = rollRaiderThreshold(thresholdRange, strategy, rng)

  # Roll for detection (1d20)
  let detectionRoll = rng.rand(1..20)

  result = DetectionResult(
    detected: detectionRoll > threshold,
    effectiveELI: detectorELI,
    threshold: threshold,
    roll: detectionRoll
  )

proc detectRaider*(
  detectorUnit: ELIUnit,
  cloakLevel: int
): DetectionResult =
  ## High-level raider detection (using global RNG)
  ## Calculates effective ELI and attempts detection

  let effectiveELI = calculateEffectiveELI(detectorUnit.eliLevels, detectorUnit.isStarbase)
  result = attemptRaiderDetection(effectiveELI, cloakLevel)
  result.effectiveELI = effectiveELI

proc detectRaider*(
  detectorUnit: ELIUnit,
  cloakLevel: int,
  rng: var Rand
): DetectionResult =
  ## High-level raider detection (with provided RNG)
  ## Calculates effective ELI and attempts detection

  let effectiveELI = calculateEffectiveELI(detectorUnit.eliLevels, detectorUnit.isStarbase)
  result = attemptRaiderDetection(effectiveELI, cloakLevel, rng)
  result.effectiveELI = effectiveELI

## Fleet/Squadron ELI Helpers

proc getScoutELILevels*(squadron: Squadron): seq[int] =
  ## Extract ELI levels from all scouts in a squadron
  ## Returns sequence of ELI tech levels
  result = @[]

  for ship in squadron.allShips():
    if ship.stats.specialCapability.startsWith("ELI"):
      result.add(ship.stats.techLevel)

proc getFleetELILevels*(squadrons: seq[Squadron]): seq[int] =
  ## Extract ELI levels from all scouts in a fleet
  result = @[]

  for squadron in squadrons:
    for eliLevel in getScoutELILevels(squadron):
      result.add(eliLevel)

proc getFleetCloakLevel*(squadrons: seq[Squadron]): int =
  ## Get highest cloaking level in a fleet
  ## Fleets are cloaked if they contain raiders
  ## Returns highest CLK level, or 0 if no cloaking
  result = 0

  for squadron in squadrons:
    for ship in squadron.allShips():
      if ship.stats.specialCapability.startsWith("CLK") and not ship.isCrippled:
        # Extract CLK level from "CLK1", "CLK2", etc.
        let clkLevel = ship.stats.techLevel
        result = max(result, clkLevel)

proc hasELICapability*(squadrons: seq[Squadron]): bool =
  ## Check if fleet has any ELI-capable units (scouts)
  for squadron in squadrons:
    for ship in squadron.allShips():
      if ship.stats.specialCapability.startsWith("ELI"):
        return true
  return false

proc createELIUnit*(squadrons: seq[Squadron], isStarbase: bool = false): ELIUnit =
  ## Create an ELIUnit from squadrons or starbase
  result = ELIUnit(
    eliLevels: getFleetELILevels(squadrons),
    isStarbase: isStarbase
  )
