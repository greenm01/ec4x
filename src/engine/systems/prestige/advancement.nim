## Advancement Prestige Awards
##
## Prestige for colonies and tech advancement

import std/options
import ../../types/prestige as types
import sources
import events
import ../../config/prestige_multiplier

type
  ColonyPrestigeResult* = object
    ## Result of colony prestige calculation
    attackerEvent*: PrestigeEvent        # Attacker gains (if seized)
    defenderEvent*: Option[PrestigeEvent] # Defender loses (if seized, zero-sum)

proc awardColonyPrestige*(
  attackerId: HouseId,
  colonyType: string,
  defenderId: Option[HouseId] = none(HouseId)
): ColonyPrestigeResult =
  ## Award prestige for colony actions
  ## - "established": New colony (absolute gain, no defender)
  ## - "seized": Invasion/blitz (zero-sum: attacker gains, defender loses)

  let source = if colonyType == "seized":
    PrestigeSource.ColonySeized
  else:
    PrestigeSource.ColonyEstablished

  let amount = applyMultiplier(getPrestigeValue(source))

  result.attackerEvent = createPrestigeEvent(
    source,
    amount,
    $attackerId & " " & colonyType & " colony"
  )

  # Zero-sum for seized colonies
  if colonyType == "seized" and defenderId.isSome:
    result.defenderEvent = some(createPrestigeEvent(
      PrestigeSource.ColonySeized,
      -amount,
      $defenderId.get() & " lost colony to " & $attackerId
    ))
  else:
    result.defenderEvent = none(PrestigeEvent)

proc awardTechPrestige*(
  houseId: HouseId,
  techField: string,
  level: int
): PrestigeEvent =
  ## Award prestige for tech advancement
  let amount = applyMultiplier(getPrestigeValue(PrestigeSource.TechAdvancement))

  return createPrestigeEvent(
    PrestigeSource.TechAdvancement,
    amount,
    $houseId & " advanced " & techField & " to level " & $level
  )
