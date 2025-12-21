## Facility Query Helpers for Economy System
##
## This module provides helper functions for querying various aspects of colony facilities,
## such as starbases, shipyards, and spaceports. These functions are primarily
## used for economic calculations, capacity checks, and strategic assessments.

import std/[options, algorithm]
import ../../common/types/core
import ../../gamestate # For Colony type
import ../config/economy_config # For globalEconomyConfig

proc getOperationalStarbaseCount*(colony: Colony): int =
  ## Count operational (non-crippled) starbases
  result = 0
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      result += 1

proc getStarbaseGrowthBonus*(colony: Colony): float =
  ## Calculate population/IU growth bonus from starbases
  ## Per assets.md:2.4.4: Configurable % per operational starbase
  let operational = getOperationalStarbaseCount(colony)
  let bonusConfig = economy_config.globalEconomyConfig.starbase_bonuses
  let bonus = float(min(operational, bonusConfig.max_starbases_for_bonus)) *
              bonusConfig.growth_bonus_per_starbase
  return bonus

# Facility management (assets.md:2.3.2)

proc hasSpaceport*(colony: Colony): bool =
  ## Check if colony has at least one spaceport
  return colony.spaceports.len > 0

proc getOperationalShipyardCount*(colony: Colony): int =
  ## Count operational (non-crippled) shipyards
  result = 0
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:
      result += 1

proc hasOperationalShipyard*(colony: Colony): bool =
  ## Check if colony has at least one operational shipyard
  return getOperationalShipyardCount(colony) > 0

proc getTotalConstructionDocks*(colony: Colony): int =
  ## Get total construction docks (uses pre-calculated effectiveDocks)
  result = 0
  for spaceport in colony.spaceports:
    result += spaceport.effectiveDocks
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:
      result += shipyard.effectiveDocks

proc getTotalRepairDocks*(colony: Colony): int =
  ## Get total repair docks from drydocks (uses pre-calculated effectiveDocks)
  result = 0
  for drydock in colony.drydocks:
    if not drydock.isCrippled:
      result += drydock.effectiveDocks

proc getShipyardDockCapacity*(colony: Colony): int =
  ## Get shipyard dock capacity (uses pre-calculated effectiveDocks)
  result = 0
  for shipyard in colony.shipyards:
    if not shipyard.isCrippled:
      result += shipyard.effectiveDocks

proc getDrydockDockCapacity*(colony: Colony): int =
  ## Get drydock dock capacity (uses pre-calculated effectiveDocks)
  result = 0
  for drydock in colony.drydocks:
    if not drydock.isCrippled:
      result += drydock.effectiveDocks

proc getSpaceportDockCapacity*(colony: Colony): int =
  ## Get spaceport dock capacity (uses pre-calculated effectiveDocks)
  result = 0
  for spaceport in colony.spaceports:
    result += spaceport.effectiveDocks
