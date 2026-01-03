## Combat Effectiveness Rating (CER) System
##
## Implements dice rolling and effectiveness calculation
## for EC4X combat resolution (Section 7.3.3)
##
## Uses deterministic PRNG for reproducible tests

import std/[hashes, strutils, options]
import ../../types/combat as combat_types
import ../../globals

export combat_types

## Deterministic PRNG (LCG - Linear Congruential Generator)
## Simple but sufficient for game dice rolls

type CombatRNG* = object
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
  rng.rollDie(10) - 1 # Convert to 0-9 range

proc roll1d20*(rng: var CombatRNG): int =
  ## Roll a standard 1D20 die for ground combat and shield rolls
  ## Returns 1-20 (inclusive)
  rng.rollDie(20)

## CER Calculation (Section 7.3.3)

proc isCritical*(naturalRoll: int): bool =
  ## Check if a natural roll is a critical hit
  ## Natural 9 (on 0-9 scale) is a critical
  naturalRoll == 9

proc lookupCER*(finalRoll: int): float32 =
  ## Look up Combat Effectiveness Rating from CER table
  ## Reads bucketed values from config/combat.kdl per Section 7.3.3
  ##
  ## Spec table (07-combat.md:344-354):
  ## | Modified Roll | CER Multiplier |
  ## |---------------|----------------|
  ## | 0, 1, 2       | 0.25           |
  ## | 3, 4          | 0.50           |
  ## | 5, 6          | 0.75           |
  ## | 7, 8          | 1.00           |
  ## | 9*            | 1.00 (critical)|
  ##
  ## Returns effectiveness multiplier from config (typically 0.25 to 1.00)
  let cfg = gameConfig.combat.cerTable

  if finalRoll <= cfg.veryPoorMax:
    cfg.veryPoorMultiplier # Typically 0.25 for rolls 0-2
  elif finalRoll <= cfg.poorMax:
    cfg.poorMultiplier # Typically 0.50 for rolls 3-4
  elif finalRoll <= cfg.averageMax:
    cfg.averageMultiplier # Typically 0.75 for rolls 5-6
  else:
    cfg.goodMultiplier # Typically 1.00 for rolls 7+

proc calculateModifiers*(
    phase: ResolutionPhase,
    roundNumber: int,
    moraleModifier: int,
    isSurprise: bool,
    isAmbush: bool,
): int =
  ## Calculate total CER modifiers for an attack
  ## Returns sum of all applicable modifiers
  result = 0

  # Morale: -1 to +2 from prestige check
  result += moraleModifier

  # First round only modifiers
  if roundNumber == 1:
    # Surprise: +3 (first round)
    if isSurprise:
      result += 3

    # Ambush: +4 (Phase 1 only, first round)
    if isAmbush and phase == ResolutionPhase.Ambush:
      result += 4

proc rollCER*(
    rng: var CombatRNG,
    phase: ResolutionPhase,
    roundNumber: int,
    moraleModifier: int,
    isSurprise: bool = false,
    isAmbush: bool = false,
    desperationBonus: int = 0, # Bonus for desperation rounds
): CERRoll =
  ## Roll for Combat Effectiveness Rating
  ## Returns CERRoll with all details
  ##
  ## desperationBonus: Additional modifier when combat stalls (both sides fight desperately)

  let naturalRoll = rng.roll1d10() # 0-9
  let baseModifiers =
    calculateModifiers(phase, roundNumber, moraleModifier, isSurprise, isAmbush)
  let modifiers = baseModifiers + desperationBonus
  let finalRoll = naturalRoll + modifiers

  # Check for critical hit (natural 9 before modifiers)
  let isCrit = isCritical(naturalRoll)

  # Look up effectiveness from CER table
  let effectiveness = lookupCER(finalRoll)

  result = CERRoll(
    naturalRoll: int32(naturalRoll),
    modifiers: int32(modifiers),
    finalRoll: int32(finalRoll),
    effectiveness: effectiveness,
    isCriticalHit: isCrit,
  )

proc applyDamage*(damage: int32, effectiveness: float): int32 =
  ## Calculate actual damage: damage * CER
  ## Round up (Section 7.3.3)
  let exactDamage = float(damage) * effectiveness
  return int32(exactDamage + 0.5) # Round to nearest (0.5+ rounds up)

proc calculateHits*(squadronAS: int32, cerRoll: CERRoll): int32 =
  ## Calculate total hits from squadron attack
  ## Total Hits = CER × Squadron_AS
  applyDamage(squadronAS, cerRoll.effectiveness)

## Morale Check System (Section 7.3.3)

proc getMoraleTierFromPrestige*(prestige: int): MoraleTier =
  ## Determine morale tier from house prestige
  ## Reads thresholds from config/prestige.kdl morale section
  let cfg = gameConfig.prestige.morale

  if prestige <= cfg.crisisMax:
    MoraleTier.Collapsing
  elif prestige <= cfg.veryLowMax:
    MoraleTier.VeryLow
  elif prestige <= cfg.lowMax:
    MoraleTier.Low
  elif prestige <= cfg.averageMax:
    MoraleTier.Normal
  elif prestige <= cfg.goodMax:
    MoraleTier.High
  elif prestige <= cfg.highMax:
    MoraleTier.VeryHigh
  else:
    MoraleTier.VeryHigh

proc rollMoraleCheck*(
  prestige: int, rng: var CombatRNG, d10CriticalRoll: Option[int] = none(int)
): MoraleCheckResult =
  ## Roll 1d20 morale check for a house
  ## Based on docs/specs/07-combat.md Section 7.3.3
  ##
  ## Args:
  ##   prestige: House prestige value
  ##   rng: Combat RNG for die rolls
  ##   d10CriticalRoll: Optional d10 crit roll for high morale auto-success
  ##
  ## Returns: MoraleCheckResult with roll outcome and CER bonus

  let tier = getMoraleTierFromPrestige(prestige)
  let cfg = gameConfig.combat.moraleChecks[tier]

  # Roll 1d20
  let roll = rng.roll1d20()

  # Check for critical auto-success (high morale only)
  var criticalAutoSuccess = false
  if cfg.criticalAutoSuccess and d10CriticalRoll.isSome:
    # High morale: natural 9+ on d10 auto-succeeds morale check
    if d10CriticalRoll.get() >= 9:
      criticalAutoSuccess = true

  # Determine success
  let success = criticalAutoSuccess or (roll > cfg.threshold)

  # Collapsing tier: penalty applies regardless of success
  let appliedBonus =
    if tier == MoraleTier.Collapsing:
      cfg.cerBonus  # Always apply (it's negative)
    elif success:
      cfg.cerBonus  # Apply if successful
    else:
      0  # No bonus if failed

  result = MoraleCheckResult(
    rolled: true,
    roll: int32(roll),
    threshold: cfg.threshold,
    success: success,
    cerBonus: appliedBonus,
    appliesTo: if success or tier == MoraleTier.Collapsing: cfg.appliesTo
    else: MoraleEffectTarget.None,
    criticalAutoSuccess: criticalAutoSuccess,
  )

## String formatting for logging

proc `$`*(cer: CERRoll): string =
  ## Pretty print CER roll for logs
  let critMark = if cer.isCriticalHit: " CRITICAL!" else: ""
  result =
    "CER: d10=$# $#=$# → $#x$#" % [
      $cer.naturalRoll,
      (if cer.modifiers >= 0: "+" else: ""),
      $cer.modifiers,
      $cer.finalRoll,
      formatFloat(cer.effectiveness, precision = 2),
      critMark,
    ]

## Testing helpers

proc deterministicRoll*(seed: string, phase: ResolutionPhase, roundNum: int): CERRoll =
  ## Create deterministic CER roll for testing
  ## Uses same seed every time for reproducibility
  var rng = initRNG(seed)
  rollCER(rng, phase, roundNum, moraleModifier = 0)

proc simulateRolls*(seed: int64, count: int): seq[int] =
  ## Simulate multiple dice rolls to verify distribution
  ## Returns sequence of natural rolls (0-9)
  var rng = initRNG(seed)
  result = @[]
  for i in 0 ..< count:
    result.add(rng.roll1d10())
