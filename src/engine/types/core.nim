## Core Game State Management for EC4X
##
## This module provides the central GameState type and game initialization functions.
## It manages all game entities (houses, colonies, fleets) and their relationships.
##

##
## ## Architecture Notes
##
## **Data-Oriented Design (DoD):**
## - All entities stored in flat `Table[Id, Entity]` structures
## - No deep nesting or pointer chasing
## - Efficient iteration and cache-friendly layout
##
## **Entity Management:**
## - Houses: Player factions with resources and technology
## - Colonies: Planetary settlements with production and infrastructure
## - Fleets: Mobile ship groups with squadrons
## - Squadrons: Ship formations within fleets
##
## **Separation of Concerns:**
## - This module: Core state and initialization
## - Resolution modules: Turn processing and game logic
## - Economy modules: Production and resource management
## - Combat modules: Battle resolution
## - Diplomacy modules: Inter-house relations

import std/[tables, options, math, algorithm, logging]
import ../common/types/[core, planets, tech, diplomacy]
import ./types/military/fleet_types
import ./types/military/squadron_types
import ./types/map/starmap_definition
import ./types/map/types as map_types
import ./types/core # Import all new types from core.nim
import ./systems/economy/facilities_queries
import ./victory/conditions
import ./systems/economy/facility_queue



# Squadron and military limits



proc getCurrentFighterCount*(colony: Colony): int =
  ## Get current number of fighter squadrons at colony
  return colony.fighterSquadrons.len
