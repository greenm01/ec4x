## Prestige Effects
##
## Victory conditions and morale modifiers based on prestige

const prestigeVictoryThreshold* = 5000

proc checkPrestigeVictory*(prestige: int): bool =
  ## Check if house achieved prestige victory
  return prestige >= prestigeVictoryThreshold

proc checkDefensiveCollapse*(prestige: int, turnsBelow: int): bool =
  ## Check if house enters defensive collapse
  ## Per gameplay.md:1.4.1: Prestige < 0 for 3 consecutive turns
  return prestige < 0 and turnsBelow >= 3

proc moraleROEModifier*(prestige: int): int =
  ## Get morale modifier to ROE from prestige
  ## Per operations.md:7.1.4
  if prestige <= 0:
    return -2 # Crisis
  elif prestige <= 20:
    return -1 # Low
  elif prestige <= 60:
    return 0 # Average/Good
  elif prestige <= 80:
    return +1 # High
  else:
    return +2 # Elite (81+)

proc moraleCERModifier*(prestige: int): int =
  ## Get morale modifier to CER from prestige
  ## Per operations.md:7.1.4
  ## Note: Requires turn-based morale check roll (not implemented here)
  return moraleROEModifier(prestige)
