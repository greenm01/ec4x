## Colony System - High-level API
##
## Provides high-level colony operations that coordinate between:
## - @entities/colony_ops (low-level state mutations)
## - Prestige system
##
## Per operations.md:6.3.12 - Colony establishment rules

import std/[options, strformat]
import ../../types/[core, game_state, starmap, prestige, colony]
import ../../entities/colony_ops
import ../../state/engine
import ../../globals
import ../../prestige/application as prestige_app
import ../../../common/logger

proc canColonize*(state: GameState, systemId: SystemId): bool =
  ## Check if a system can be colonized (no existing colony)
  ## Per operations.md:6.3.12
  state.colonyBySystem(systemId).isNone

proc establishColony*(
    state: var GameState,
    houseId: HouseId,
    systemId: SystemId,
    planetClass: PlanetClass,
    resources: ResourceRating,
    ptuCount: int32,
): Option[ColonyId] =
  ## Establish a new colony at system
  ##
  ## Returns:
  ## - Some(ColonyId) if successful
  ## - None if validation fails (logs error)
  ##
  ## Validation:
  ## - System must not already have a colony
  ## - Must have at least 1 PTU
  ##
  ## Side effects:
  ## - Creates colony entity via @entities/colony_ops
  ## - Awards prestige via prestige system

  # Validate: System must be uncolonized
  if not canColonize(state, systemId):
    logError("Colonization",
      &"Cannot colonize {systemId}: system already has colony")
    return none(ColonyId)

  # Validate: Must have PTU
  if ptuCount < 1:
    logError("Colonization",
      &"Cannot colonize {systemId}: insufficient PTU (need ≥1, got {ptuCount})")
    return none(ColonyId)

  # Create colony via entities layer (low-level state mutation)
  let colonyId = colony_ops.establishColony(
    state, systemId, houseId, planetClass, resources, ptuCount
  )

  # Award prestige
  let basePrestige = gameConfig.prestige.economic.establishColony
  let prestigeEvent = PrestigeEvent(
    source: PrestigeSource.ColonyEstablished,
    amount: basePrestige,
    description: &"Established colony at system {systemId}",
  )
  prestige_app.applyPrestigeEvent(state, houseId, prestigeEvent)

  logInfo("Colonization",
    &"House {houseId} established colony at {systemId} " &
    &"({planetClass}, {resources}, {ptuCount} PU) [+{basePrestige} prestige]")

  return some(colonyId)
