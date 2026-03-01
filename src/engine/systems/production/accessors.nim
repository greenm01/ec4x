## Config Accessor Wrappers
##
## Provides simple wrappers around gameConfig for backward compatibility.
## New code should access gameConfig directly instead.
##
## Architecture:
## - All configs loaded into unified gameConfig (see src/engine/globals.nim)
## - Ships/Facilities/GroundUnits use array[Enum, T] for O(1) access
## - Construction times are global (all build in 1 turn per KDL config)

import ../../types/[ship, facilities, ground_unit]
import ../../globals

## Ship Config Accessors

proc shipConstructionCost*(shipClass: ShipClass): int32 =
  ## Get construction cost (PP) for ship class from ships.kdl
  ## Direct array access - no case statement needed
  gameConfig.ships.ships[shipClass].productionCost

proc shipBaseBuildTime*(shipClass: ShipClass): int32 =
  ## Get base construction time from construction.kdl
  ## Per KDL config: all ships build in 1 turn
  gameConfig.construction.construction.shipTurns

proc shipCSTRequirement*(shipClass: ShipClass): int32 =
  ## Get CST tech level required to build ship class
  ## Per economy.md:4.5 - CST unlocks new ship classes
  gameConfig.ships.ships[shipClass].minCST

proc shipMaintenanceCost*(shipClass: ShipClass): int32 =
  ## Get maintenance cost (PP/turn) for ship class
  gameConfig.ships.ships[shipClass].maintenanceCost

## Facility Config Accessors

proc buildingCost*(buildingType: FacilityClass): int32 =
  ## Get construction cost (PP) for facility from facilities.kdl
  ## Direct array access - no case statement needed
  gameConfig.facilities.facilities[buildingType].buildCost

proc buildingTime*(buildingType: FacilityClass): int32 =
  ## Get construction time for facility
  ## Per construction.kdl: all facilities build in 1 turn
  case buildingType
  of FacilityClass.Spaceport:
    gameConfig.construction.construction.spaceportTurns
  of FacilityClass.Shipyard:
    gameConfig.construction.construction.shipyardTurns
  of FacilityClass.Drydock:
    gameConfig.construction.construction.drydockTurns
  of FacilityClass.Starbase:
    gameConfig.construction.construction.starbaseTurns

proc buildingCSTRequirement*(buildingType: FacilityClass): int32 =
  ## Get CST tech level required to build facility
  ## Returns minCST from facilities.kdl (e.g., Starbase requires CST3)
  gameConfig.facilities.facilities[buildingType].minCST

proc facilityPrerequisite*(buildingType: FacilityClass): string =
  ## Get the prerequisite facility name for a given facility type.
  ## Returns the `prerequisite` string from facilities.kdl, or "" if none.
  ## Use facility_queries.facilityPrerequisiteMet for the state-aware check.
  gameConfig.facilities.facilities[buildingType].prerequisite

## Ground Unit Config Accessors

proc armyBuildCost*(): int32 =
  ## Get construction cost for army division
  gameConfig.groundUnits.units[GroundClass.Army].productionCost

proc marineBuildCost*(): int32 =
  ## Get construction cost for marine division
  gameConfig.groundUnits.units[GroundClass.Marine].productionCost

proc groundBatteryBuildCost*(): int32 =
  ## Get construction cost for ground battery
  gameConfig.groundUnits.units[GroundClass.GroundBattery].productionCost

proc planetaryShieldCost*(sldLevel: int32): int32 =
  ## Get construction cost for planetary shield
  ## Note: Currently uses base cost; SLD level affects strength, not cost
  ## Note: Simple per-unit cost model used (no tiered pricing in spec)
  gameConfig.groundUnits.units[GroundClass.PlanetaryShield].productionCost

## Generic Ground Unit Accessors

proc groundUnitCost*(groundClass: GroundClass): int32 =
  ## Get construction cost (PP) for any ground unit type
  gameConfig.groundUnits.units[groundClass].productionCost

proc groundUnitBuildTime*(groundClass: GroundClass): int32 =
  ## Get construction time (turns) for any ground unit type
  gameConfig.groundUnits.units[groundClass].buildTime

proc groundUnitCSTRequirement*(groundClass: GroundClass): int32 =
  ## Get CST tech level required to build ground unit type
  gameConfig.groundUnits.units[groundClass].minCST

proc groundUnitPopulationCost*(groundClass: GroundClass): int32 =
  ## Get population cost for recruiting ground unit (Army/Marine only)
  gameConfig.groundUnits.units[groundClass].populationCost

## Construction Modifier Accessors

proc planetsideConstructionMultiplier*(): float32 =
  ## Get cost multiplier for planet-side ship construction
  ## Per construction.kdl: 2.0 = +100% cost penalty
  gameConfig.construction.modifiers.planetsideConstructionCostMultiplier

## Export all public procs
export shipConstructionCost, shipBaseBuildTime, shipCSTRequirement,
  shipMaintenanceCost
export buildingCost, buildingTime, buildingCSTRequirement,
  facilityPrerequisite
export armyBuildCost, marineBuildCost, groundBatteryBuildCost,
  planetaryShieldCost
export groundUnitCost, groundUnitBuildTime,
  groundUnitCSTRequirement, groundUnitPopulationCost
export planetsideConstructionMultiplier

## Design Notes:
##
## **Why This Module Exists:**
## Provides stable API layer over gameConfig for:
## 1. Backward compatibility with existing code
## 2. Convenience wrappers for common queries
## 3. Single place to handle special cases (e.g., string-based building lookups)
##
## **New Code Should:**
## - Access gameConfig directly: `gameConfig.ships.ships[shipClass].productionCost`
## - Use enum types (ShipClass, FacilityClass, GroundClass) not strings
## - Avoid this module if possible - it's a compatibility layer
##
## **Refactoring from Old System:**
## Old system (TOML-based):
## - Used macro-generated case statements
## - Had separate global configs per domain
## - Required 120+ lines of case duplication
##
## New system (KDL-based):
## - Uses array[Enum, T] for O(1) access
## - Unified gameConfig global
## - Direct indexing eliminates case statements
