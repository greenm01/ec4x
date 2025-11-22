## Colonization Engine
##
## Colony establishment per operations.md:6.2.13
##
## Colonization rules:
## - Requires ETAC ship with PTU
## - One system can only have one colony (any house)
## - New colonies start at infrastructure level 1
## - Awards +5 prestige for establishing colony

import std/[options]
import ../../common/types/[core, planets]
import ../prestige
import ../config/prestige_config
import ../economy/types as econ_types

export core.HouseId, core.SystemId
export prestige.PrestigeEvent

type
  ColonizationAttempt* = object
    ## Attempt to colonize a planet
    houseId*: HouseId
    systemId*: SystemId
    fleetId*: FleetId
    ptuUsed*: int

  ColonizationResult* = object
    ## Result of colonization attempt
    success*: bool
    reason*: string
    newColony*: Option[econ_types.Colony]
    prestigeEvent*: Option[PrestigeEvent]

## Colonization

proc canColonize*(systemId: SystemId, existingColonies: seq[econ_types.Colony]): bool =
  ## Check if system can be colonized (no existing colony)
  ## Per operations.md:6.2.13
  for colony in existingColonies:
    if colony.systemId == systemId:
      return false
  return true

proc establishColony*(houseId: HouseId, systemId: SystemId,
                     planetClass: PlanetClass, resources: ResourceRating,
                     startingPTU: int): ColonizationResult =
  ## Establish new colony at system
  ## Per operations.md:6.2.13: "New colonies start at Level I"

  let config = globalPrestigeConfig

  # Create new colony
  let colony = econ_types.initColony(
    systemId,
    houseId,
    planetClass,
    resources,
    startingPTU
  )

  # Create prestige event
  let prestigeEvent = createPrestigeEvent(
    PrestigeSource.ColonyEstablished,
    config.economic.establish_colony,
    "Established colony at system " & $systemId
  )

  return ColonizationResult(
    success: true,
    reason: "Colony established successfully",
    newColony: some(colony),
    prestigeEvent: some(prestigeEvent)
  )

proc attemptColonization*(attempt: ColonizationAttempt,
                         existingColonies: seq[econ_types.Colony],
                         planetClass: PlanetClass,
                         resources: ResourceRating): ColonizationResult =
  ## Attempt to colonize a system
  ## Per operations.md:6.2.13

  # Check if system is available
  if not canColonize(attempt.systemId, existingColonies):
    return ColonizationResult(
      success: false,
      reason: "System already colonized",
      newColony: none(econ_types.Colony),
      prestigeEvent: none(PrestigeEvent)
    )

  # Check PTU availability
  if attempt.ptuUsed < 1:
    return ColonizationResult(
      success: false,
      reason: "Insufficient PTU (need at least 1)",
      newColony: none(econ_types.Colony),
      prestigeEvent: none(PrestigeEvent)
    )

  # Establish colony
  return establishColony(
    attempt.houseId,
    attempt.systemId,
    planetClass,
    resources,
    attempt.ptuUsed
  )
