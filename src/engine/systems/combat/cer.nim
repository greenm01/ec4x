## Combat Effectiveness Rating (CER) System
##
## Implements CER tables for combat resolution.
## Two tables: Space/Orbital vs Ground (Planetary)
##
## Per docs/specs/07-combat.md Section 7.4.1

import std/random
import ../../types/[combat]

proc rollCER*(rng: var Rand, drm: int32, theater: CombatTheater): CERResult =
  ## Roll 1d10 + DRM, lookup CER from theater-specific table
  ## Per docs/specs/07-combat.md Section 7.4.1
  ##
  ## **Space/Orbital CRT:**
  ## - Roll ≤2: 0.25× effectiveness
  ## - Roll 3-5: 0.50× effectiveness
  ## - Roll 6+:  1.00× effectiveness (max)
  ##
  ## **Ground Combat CRT (more lethal):**
  ## - Roll ≤2: 0.5× effectiveness
  ## - Roll 3-6: 1.0× effectiveness
  ## - Roll 7-8: 1.5× effectiveness
  ## - Roll 9+:  2.0× effectiveness (max)
  ##
  ## **Critical Hits:**
  ## - Natural 9 (before DRM) = Critical Hit
  ## - Can bypass "cripple all first" protection rule

  let naturalRoll = rand(rng, 1..10)
  let modifiedRoll = naturalRoll + drm.int
  
  # Track if this is a critical hit (natural 9, before modifiers)
  result.isCriticalHit = (naturalRoll == 9)

  case theater
  of CombatTheater.Space, CombatTheater.Orbital:
    # Space/Orbital CRT (07-combat.md Section 7.4.1)
    if modifiedRoll <= 2:
      result.cer = 0.25
    elif modifiedRoll <= 5:
      result.cer = 0.50
    else:
      result.cer = 1.00

  of CombatTheater.Planetary:
    # Ground Combat CRT (more lethal, higher ceiling)
    if modifiedRoll <= 2:
      result.cer = 0.5
    elif modifiedRoll <= 6:
      result.cer = 1.0
    elif modifiedRoll <= 8:
      result.cer = 1.5
    else:
      result.cer = 2.0

proc getCERDescription*(cer: float32, theater: CombatTheater): string =
  ## Get human-readable description of CER result
  ## Used for combat reports and logging

  case theater
  of CombatTheater.Space, CombatTheater.Orbital:
    if cer <= 0.25:
      return "Poor (0.25×)"
    elif cer <= 0.50:
      return "Fair (0.50×)"
    else:
      return "Good (1.00×)"

  of CombatTheater.Planetary:
    if cer <= 0.5:
      return "Poor (0.5×)"
    elif cer <= 1.0:
      return "Fair (1.0×)"
    elif cer <= 1.5:
      return "Good (1.5×)"
    else:
      return "Excellent (2.0×)"

## Design Notes:
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.4.1 - CER Tables
## - docs/specs/07-combat.md Table 7.1 - Space/Orbital CRT
## - docs/specs/07-combat.md Table 7.2 - Ground Combat CRT
##
## **Key Differences Between Tables:**
## - Space/Orbital: Max 1.0× effectiveness (defensive advantage)
## - Ground: Max 2.0× effectiveness (offensive advantage)
## - Ground combat is more lethal and decisive
##
## **DRM Integration:**
## - DRM adds to 1d10 roll before table lookup
## - Positive DRM improves effectiveness
## - Negative DRM reduces effectiveness
## - No roll can go below 1 or above natural limits
##
## **Random Number Generator:**
## - Uses Nim's std/random for deterministic seeding
## - Caller must provide seeded RNG for reproducibility
## - Each side rolls independently
