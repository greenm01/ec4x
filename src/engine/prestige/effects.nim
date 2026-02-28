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

