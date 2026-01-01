## Colony System - High-level API
##
## Provides high-level colony operations that coordinate between:
## - @entities/colony_ops (low-level state mutations)
## - Prestige awards
##
## Per operations.md:6.2.13 - Colony establishment rules

import std/[options, tables]
import ../../types/[core, game_state, starmap, prestige]
import ../../entities/colony_ops
import ../../globals
import ../../prestige/engine as prestige_engine

type ColonizationResult* = object ## Result of a colonization attempt
  success*: bool
  reason*: string
  colonyId*: Option[ColonyId]
  prestigeEvent*: Option[PrestigeEvent]

proc canColonize*(state: GameState, systemId: SystemId): bool =
  ## Check if a system can be colonized (no existing colony)
  ## Per operations.md:6.2.13
  not state.colonies.bySystem.hasKey(systemId)

proc establishColony*(
    state: var GameState,
    houseId: HouseId,
    systemId: SystemId,
    planetClass: PlanetClass,
    resources: ResourceRating,
    ptuCount: int32 = 3,
): ColonizationResult =
  ## High-level colony establishment with prestige award
  ##
  ## Coordinates:
  ## 1. Validation (can colonize?)
  ## 2. Entity creation via @entities/colony_ops
  ## 3. Prestige calculation
  ##
  ## Returns result with success/failure and prestige event

  # Validate: System must be uncolonized
  if not canColonize(state, systemId):
    return ColonizationResult(
      success: false,
      reason: "System already colonized",
      colonyId: none(ColonyId),
      prestigeEvent: none(PrestigeEvent),
    )

  # Validate: Must have PTU
  if ptuCount < 1:
    return ColonizationResult(
      success: false,
      reason: "Insufficient PTU (need at least 1)",
      colonyId: none(ColonyId),
      prestigeEvent: none(PrestigeEvent),
    )

  # Create colony via entities layer (low-level state mutation)
  let colonyId = colony_ops.establishColony(
    state, systemId, houseId, planetClass, resources, ptuCount
  )

  # Award prestige with dynamic scaling
  let basePrestige = gameConfig.prestige.economic.establishColony
  let prestigeAmount = prestige_engine.applyPrestigeMultiplier(basePrestige)
  let prestigeEvent = PrestigeEvent(
    source: PrestigeSource.ColonyEstablished,
    amount: prestigeAmount.int32,
    description: "Established colony at system " & $systemId,
  )

  return ColonizationResult(
    success: true,
    reason: "Colony established successfully",
    colonyId: some(colonyId),
    prestigeEvent: some(prestigeEvent),
  )
