## Economic Prestige Effects
##
## Prestige modifiers from taxation and blockades

import types
import sources
import events
import ../config/prestige_multiplier

proc applyTaxPrestige*(
    houseId: HouseId, colonyCount: int, taxRate: int
): PrestigeEvent =
  ## Apply prestige bonus from low tax rate
  ## Per economy.md:3.2.2
  var bonusPerColony = 0

  if taxRate >= 41:
    bonusPerColony = 0
  elif taxRate >= 31:
    bonusPerColony = 0
  elif taxRate >= 21:
    bonusPerColony = 1
  elif taxRate >= 11:
    bonusPerColony = 2
  else:
    bonusPerColony = 3

  let totalBonus = bonusPerColony * colonyCount

  return createPrestigeEvent(
    PrestigeSource.LowTaxBonus,
    totalBonus,
    $houseId & " low tax bonus (rate: " & $taxRate & "%)",
  )

proc applyHighTaxPenalty*(houseId: HouseId, avgTaxRate: int): PrestigeEvent =
  ## Apply prestige penalty from high rolling average tax
  ## Per economy.md:3.2.1
  var penalty = 0

  if avgTaxRate <= 50:
    penalty = 0
  elif avgTaxRate <= 60:
    penalty = -1
  elif avgTaxRate <= 70:
    penalty = -2
  elif avgTaxRate <= 80:
    penalty = -4
  elif avgTaxRate <= 90:
    penalty = -7
  else:
    penalty = -11

  return createPrestigeEvent(
    PrestigeSource.HighTaxPenalty,
    penalty,
    $houseId & " high tax penalty (avg: " & $avgTaxRate & "%)",
  )

proc applyBlockadePenalty*(houseId: HouseId, blockadedColonies: int): PrestigeEvent =
  ## Apply prestige penalty for blockaded colonies
  ## Per operations.md:6.2.6: -2 prestige per blockaded colony per turn
  let penalty =
    applyMultiplier(getPrestigeValue(PrestigeSource.BlockadePenalty)) * blockadedColonies

  return createPrestigeEvent(
    PrestigeSource.BlockadePenalty,
    penalty,
    $houseId & " has " & $blockadedColonies & " blockaded colonies",
  )
