## Detection System for Spy Scouts and Raiders
##
## Implements ELI-based detection mechanics for spy scouts and cloaked raiders
## Based on assets.md Sections 2.4.2 and 2.4.3
##
## REFACTORED (Phase 10): Data-Oriented Design
## - Eliminated 98 lines of RNG overload duplication
## - Global RNG versions now just wrap parameterized versions
## - Reduced from 357 lines → 259 lines (27% reduction)

import std/[math, random, sequtils, options, strutils]
import ../../squadron
import ../../config/espionage_config

export Option

## Global RNG instance (for overload wrappers)
var globalRNG* = initRand()

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

## ELI Detection Calculation

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

proc calculateEffectiveELI*(eliLevels: seq[int], isStarbase: bool = false): int =
  ## Calculate final effective ELI level for detection
  ## Combines weighted average and dominant tech penalty
  ## Starbases get +2 bonus against spy scouts
  if eliLevels.len == 0:
    return 0

  let cfg = globalEspionageConfig.scout_detection

  # Step 1: Weighted average
  let weightedAvg = calculateWeightedAverageELI(eliLevels)

  # Step 2: Dominant tech penalty
  let afterPenalty = applyDominantTechPenalty(weightedAvg, eliLevels)

  # Step 3: Starbase bonus (only against spy scouts)
  let starbaseBonus = if isStarbase: cfg.starbase_eli_bonus else: 0

  # Final ELI (capped at max level)
  result = min(cfg.max_eli_level, afterPenalty + starbaseBonus)

## Spy Scout Detection

proc detectSpyScouts*(
  numScouts: int,
  defenderELI: int,
  starbaseBonus: int,
  rng: var Rand
): DetectionResult =
  ## Detect spy scouts using simplified formula from assets.md:2.4.2
  ## Formula: Target = 15 - numScouts + (defenderELI + starbaseBonus)
  ## Roll 1d20, >= target = detected
  ##
  ## Returns detection result with roll details

  let targetNumber = 15 - numScouts + (defenderELI + starbaseBonus)
  let roll = rng.rand(1..20)
  let detected = roll >= targetNumber

  result = DetectionResult(
    detected: detected,
    effectiveELI: defenderELI + starbaseBonus,
    threshold: targetNumber,
    roll: roll
  )

proc detectSpyScouts*(
  numScouts: int,
  defenderELI: int,
  starbaseBonus: int = 0
): DetectionResult =
  ## Wrapper using global RNG
  detectSpyScouts(numScouts, defenderELI, starbaseBonus, globalRNG)

## Raider Detection

proc detectRaider*(
  attackerCLK: int,
  defenderELI: int,
  starbaseBonus: int,
  rng: var Rand
): DetectionResult =
  ## Detect cloaked raiders using opposed roll from assets.md:2.4.3
  ## Formula: Attacker rolls 1d10 + CLK vs Defender rolls 1d10 + ELI + starbaseBonus
  ## Detected = defenderRoll >= attackerRoll (ties go to defender)
  ##
  ## Returns detection result with roll details

  let attackerRoll = rng.rand(1..10) + attackerCLK
  let defenderRoll = rng.rand(1..10) + defenderELI + starbaseBonus
  let detected = defenderRoll >= attackerRoll

  result = DetectionResult(
    detected: detected,
    effectiveELI: defenderRoll,  # Defender's total roll
    threshold: attackerRoll,     # Attacker's total roll (used as "threshold" to beat)
    roll: defenderRoll           # Defender's roll (same as effectiveELI)
  )

proc detectRaider*(
  attackerCLK: int,
  defenderELI: int,
  starbaseBonus: int = 0
): DetectionResult =
  ## Wrapper using global RNG
  detectRaider(attackerCLK, defenderELI, starbaseBonus, globalRNG)

## Fleet ELI Capability Check

proc hasELICapability*(squadrons: seq[Squadron]): bool =
  ## Check if fleet has any ELI-capable units (scouts)
  for squadron in squadrons:
    for ship in squadron.allShips():
      if ship.stats.specialCapability.startsWith("ELI"):
        return true
  return false
