## Combat Prestige Awards
##
## Zero-sum prestige awards for combat victories
##
## Per operations.md:7.3.3 - Combat is competitive: winner gains prestige,
## loser loses equal amount

import ../types/[core, prestige]
import ./[engine, sources, events]

type CombatPrestigeResult* = object ## Result of combat prestige calculation
  victorEvents*: seq[PrestigeEvent] # Prestige events for victor (positive)
  defeatedEvents*: seq[PrestigeEvent] # Prestige events for defeated (negative)

proc awardCombatPrestige*(
    victor: HouseId,
    defeated: HouseId,
    taskForceDestroyed: bool,
    squadronsDestroyed: int,
    forcedRetreat: bool,
): CombatPrestigeResult =
  ## Award prestige for combat outcome (zero-sum: winner gains, loser loses)
  result.victorEvents = @[]
  result.defeatedEvents = @[]

  # Combat victory (zero-sum)
  let victoryPrestige =
    applyPrestigeMultiplier(getPrestigeValue(PrestigeSource.CombatVictory))
  result.victorEvents.add(
    createPrestigeEvent(
      PrestigeSource.CombatVictory, victoryPrestige, $victor & " defeated " & $defeated
    )
  )
  result.defeatedEvents.add(
    createPrestigeEvent(
      PrestigeSource.CombatVictory,
      -victoryPrestige,
      $defeated & " defeated by " & $victor,
    )
  )

  # Task force destroyed (zero-sum)
  if taskForceDestroyed:
    let tfPrestige =
      applyPrestigeMultiplier(getPrestigeValue(PrestigeSource.TaskForceDestroyed))
    result.victorEvents.add(
      createPrestigeEvent(
        PrestigeSource.TaskForceDestroyed,
        tfPrestige,
        $victor & " destroyed " & $defeated & " task force",
      )
    )
    result.defeatedEvents.add(
      createPrestigeEvent(
        PrestigeSource.TaskForceDestroyed,
        -tfPrestige,
        $defeated & " lost task force to " & $victor,
      )
    )

  # Squadrons destroyed (zero-sum)
  if squadronsDestroyed > 0:
    let squadronPrestige =
      applyPrestigeMultiplier(getPrestigeValue(PrestigeSource.SquadronDestroyed)) *
      int32(squadronsDestroyed)
    result.victorEvents.add(
      createPrestigeEvent(
        PrestigeSource.SquadronDestroyed,
        squadronPrestige,
        $victor & " destroyed " & $squadronsDestroyed & " squadrons",
      )
    )
    result.defeatedEvents.add(
      createPrestigeEvent(
        PrestigeSource.SquadronDestroyed,
        -squadronPrestige,
        $defeated & " lost " & $squadronsDestroyed & " squadrons",
      )
    )

  # Forced retreat (zero-sum)
  if forcedRetreat:
    let retreatPrestige =
      applyPrestigeMultiplier(getPrestigeValue(PrestigeSource.FleetRetreated))
    result.victorEvents.add(
      createPrestigeEvent(
        PrestigeSource.FleetRetreated,
        retreatPrestige,
        $victor & " forced " & $defeated & " to retreat",
      )
    )
    result.defeatedEvents.add(
      createPrestigeEvent(
        PrestigeSource.FleetRetreated,
        -retreatPrestige,
        $defeated & " forced to retreat by " & $victor,
      )
    )
