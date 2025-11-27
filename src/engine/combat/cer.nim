## Combat Effectiveness Rating (CER) System
##
## Implements dice rolling and effectiveness calculation
## for EC4X combat resolution (Section 7.3.3)
##
## Uses deterministic PRNG for reproducible tests

import std/[hashes, strutils]
import types

export CERRoll, CERModifier

## Deterministic PRNG (LCG - Linear Congruential Generator)
## Simple but sufficient for game dice rolls

type
  CombatRNG* = object
    state*: uint64

proc initRNG*(seed: int64): CombatRNG =
  ## Initialize RNG with seed
  ## Seed format: gameId-turnNum-combatId-phaseNum-roundNum
  CombatRNG(state: cast[uint64](seed))

proc initRNG*(seedString: string): CombatRNG =
  ## Initialize from string seed (for testing)
  let h = hash(seedString)
  CombatRNG(state: cast[uint64](h))

proc next*(rng: var CombatRNG): uint64 =
  ## Generate next random number
  ## Using LCG: Xn+1 = (a * Xn + c) mod m
  const
    a = 6364136223846793005'u64
    c = 1442695040888963407'u64

  rng.state = a * rng.state + c
  return rng.state

proc rollDie*(rng: var CombatRNG, sides: int): int =
  ## Roll a die with given number of sides (1-based)
  ## Returns value from 1 to sides (inclusive)
  let raw = rng.next()
  return int(raw mod uint64(sides)) + 1

proc roll1d10*(rng: var CombatRNG): int =
  ## Roll a standard 1D10 die for CER
  ## Returns 1-10 (but we treat as 0-9 internally per spec)
  ## Spec uses "natural 9" for critical, which is roll result 9
  rng.rollDie(10) - 1  # Convert to 0-9 range

proc roll1d20*(rng: var CombatRNG): int =
  ## Roll a standard 1D20 die for ground combat and shield rolls
  ## Returns 1-20 (inclusive)
  rng.rollDie(20)

## CER Calculation (Section 7.3.3)

proc calculateModifiers*(
  phase: CombatPhase,
  roundNumber: int,
  hasScouts: bool,
  moraleModifier: int,
  isSurprise: bool,
  isAmbush: bool
): int =
  ## Calculate total CER modifiers for an attack
  ## Returns sum of all applicable modifiers
  result = 0

  # Scouts: +1 max for entire Task Force
  if hasScouts:
    result += 1

  # Morale: -1 to +2 from prestige check
  result += moraleModifier

  # First round only modifiers
  if roundNumber == 1:
    # Surprise: +3 (first round)
    if isSurprise:
      result += 3

    # Ambush: +4 (Phase 1 only, first round)
    if isAmbush and phase == CombatPhase.Ambush:
      result += 4

proc rollCER*(
  rng: var CombatRNG,
  phase: CombatPhase,
  roundNumber: int,
  hasScouts: bool,
  moraleModifier: int,
  isSurprise: bool = false,
  isAmbush: bool = false,
  desperationBonus: int = 0  # Bonus for desperation rounds
): CERRoll =
  ## Roll for Combat Effectiveness Rating
  ## Returns CERRoll with all details
  ##
  ## desperationBonus: Additional modifier when combat stalls (both sides fight desperately)

  let naturalRoll = rng.roll1d10()  # 0-9
  let baseModifiers = calculateModifiers(
    phase, roundNumber, hasScouts, moraleModifier,
    isSurprise, isAmbush
  )
  let modifiers = baseModifiers + desperationBonus
  let finalRoll = naturalRoll + modifiers

  # Check for critical hit (natural 9 before modifiers)
  let isCrit = isCritical(naturalRoll)

  # Look up effectiveness from CER table
  let effectiveness = lookupCER(finalRoll)

  result = CERRoll(
    naturalRoll: naturalRoll,
    modifiers: modifiers,
    finalRoll: finalRoll,
    effectiveness: effectiveness,
    isCriticalHit: isCrit
  )

proc applyDamage*(damage: int, effectiveness: float): int =
  ## Calculate actual damage: damage * CER
  ## Round up (Section 7.3.3)
  let exactDamage = float(damage) * effectiveness
  return int(exactDamage + 0.5)  # Round to nearest (0.5+ rounds up)

proc calculateHits*(squadronAS: int, cerRoll: CERRoll): int =
  ## Calculate total hits from squadron attack
  ## Total Hits = CER × Squadron_AS
  applyDamage(squadronAS, cerRoll.effectiveness)

## String formatting for logging

proc `$`*(cer: CERRoll): string =
  ## Pretty print CER roll for logs
  let critMark = if cer.isCriticalHit: " CRITICAL!" else: ""
  result = "CER: d10=$# $#=$# → $#x$#" % [
    $cer.naturalRoll,
    (if cer.modifiers >= 0: "+" else: ""),
    $cer.modifiers,
    $cer.finalRoll,
    formatFloat(cer.effectiveness, precision = 2),
    critMark
  ]

## Testing helpers

proc deterministicRoll*(seed: string, phase: CombatPhase, roundNum: int): CERRoll =
  ## Create deterministic CER roll for testing
  ## Uses same seed every time for reproducibility
  var rng = initRNG(seed)
  rollCER(rng, phase, roundNum, hasScouts = false, moraleModifier = 0)

proc simulateRolls*(seed: int64, count: int): seq[int] =
  ## Simulate multiple dice rolls to verify distribution
  ## Returns sequence of natural rolls (0-9)
  var rng = initRNG(seed)
  result = @[]
  for i in 0..<count:
    result.add(rng.roll1d10())
