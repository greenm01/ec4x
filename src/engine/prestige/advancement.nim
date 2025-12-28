## Advancement Prestige Awards
##
## Prestige for colonies and tech advancement

import std/options
import ../types/[core, prestige, tech]
import ./[engine, sources, events]

proc awardColonyPrestige*(
    attackerId: HouseId, source: PrestigeSource, defenderId: Option[HouseId] = none(HouseId)
): ColonyPrestigeResult =
  ## Award prestige for colony actions
  ## - "established": New colony (absolute gain, no defender)
  ## - "seized": Invasion/blitz (zero-sum: attacker gains, defender loses)

  const ValidSources = {PrestigeSource.ColonySeized, PrestigeSource.ColonyEstablished}

  if source notin ValidSources:
    raise newException(ValueError, "Not a colony event")
    
  let amount = applyPrestigeMultiplier(getPrestigeValue(source))

  result.attackerEvent =
    createPrestigeEvent(source, amount, $attackerId & " " & $source & " colony")

  # Zero-sum for seized colonies
  if source == PrestigeSource.ColonySeized and defenderId.isSome:
    result.defenderEvent = some(
      createPrestigeEvent(
        PrestigeSource.ColonySeized,
        -amount,
        $defenderId.get() & " lost colony to " & $attackerId,
      )
    )
  else:
    result.defenderEvent = none(PrestigeEvent)

proc awardTechPrestige*(
    houseId: HouseId, techField: TechField, level: int
): PrestigeEvent =
  ## Award prestige for tech advancement
  let amount = applyPrestigeMultiplier(getPrestigeValue(PrestigeSource.TechAdvancement))

  return createPrestigeEvent(
    PrestigeSource.TechAdvancement,
    amount,
    $houseId & " advanced " & $techField & " to level " & $level,
  )
