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

proc getShipConstructionCost*(shipClass: ShipClass): int32 =
  ## Get construction cost (PP) for ship class from ships.kdl
  ## Direct array access - no case statement needed
  gameConfig.ships.ships[shipClass].productionCost

proc getShipBaseBuildTime*(shipClass: ShipClass): int32 =
  ## Get base construction time from construction.kdl
  ## Per KDL config: all ships build in 1 turn
  gameConfig.construction.construction.shipTurns

proc getShipCSTRequirement*(shipClass: ShipClass): int32 =
  ## Get CST tech level required to build ship class
  ## Per economy.md:4.5 - CST unlocks new ship classes
  gameConfig.ships.ships[shipClass].minCST

proc getShipMaintenanceCost*(shipClass: ShipClass): int32 =
  ## Get maintenance cost (PP/turn) for ship class
  gameConfig.ships.ships[shipClass].maintenanceCost

## Facility Config Accessors

proc getBuildingCost*(buildingType: FacilityClass): int32 =
  ## Get construction cost (PP) for facility from facilities.kdl
  ## Direct array access - no case statement needed
  gameConfig.facilities.facilities[buildingType].buildCost

proc getBuildingTime*(buildingType: FacilityClass): int32 =
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

proc getBuildingCSTRequirement*(buildingType: FacilityClass): int32 =
  ## Get CST tech level required to build facility
  ## Returns minCST from facilities.kdl (e.g., Starbase requires CST3)
  gameConfig.facilities.facilities[buildingType].minCST

proc requiresSpaceport*(buildingType: FacilityClass): bool =
  ## Check if facility requires a spaceport to build
  ## Currently only used for shipyard construction
  case buildingType
  of FacilityClass.Shipyard:
    gameConfig.construction.construction.shipyardRequiresSpaceport
  else:
    false

proc requiresShipyard*(buildingType: string): bool =
  ## Check if building requires a shipyard (e.g., Starbase requires shipyard)
  ## Per construction.kdl: starbaseRequiresShipyard
  ##
  ## Note: Takes string for backward compatibility with old command validation
  ## New code should use FacilityClass enum
  buildingType == "Starbase" and
    gameConfig.construction.construction.starbaseRequiresShipyard

## Ground Unit Config Accessors

proc getArmyBuildCost*(): int32 =
  ## Get construction cost for army division
  gameConfig.groundUnits.units[GroundClass.Army].productionCost

proc getMarineBuildCost*(): int32 =
  ## Get construction cost for marine division
  gameConfig.groundUnits.units[GroundClass.Marine].productionCost

proc getGroundBatteryBuildCost*(): int32 =
  ## Get construction cost for ground battery
  gameConfig.groundUnits.units[GroundClass.GroundBattery].productionCost

proc getPlanetaryShieldCost*(sldLevel: int32): int32 =
  ## Get construction cost for planetary shield
  ## Note: Currently uses base cost; SLD level affects strength, not cost
  ## TODO: Implement tiered costs if needed
  gameConfig.groundUnits.units[GroundClass.PlanetaryShield].productionCost

## Generic Ground Unit Accessors

proc getGroundUnitCost*(groundClass: GroundClass): int32 =
  ## Get construction cost (PP) for any ground unit type
  gameConfig.groundUnits.units[groundClass].productionCost

proc getGroundUnitBuildTime*(groundClass: GroundClass): int32 =
  ## Get construction time (turns) for any ground unit type
  gameConfig.groundUnits.units[groundClass].buildTime

proc getGroundUnitCSTRequirement*(groundClass: GroundClass): int32 =
  ## Get CST tech level required to build ground unit type
  gameConfig.groundUnits.units[groundClass].minCST

proc getGroundUnitPopulationCost*(groundClass: GroundClass): int32 =
  ## Get population cost for recruiting ground unit (Army/Marine only)
  gameConfig.groundUnits.units[groundClass].populationCost

## Construction Modifier Accessors

proc getPlanetsideConstructionMultiplier*(): float32 =
  ## Get cost multiplier for planet-side ship construction
  ## Per construction.kdl: 2.0 = +100% cost penalty
  gameConfig.construction.modifiers.planetsideConstructionCostMultiplier

## Export all public procs
export getShipConstructionCost, getShipBaseBuildTime, getShipCSTRequirement,
  getShipMaintenanceCost
export getBuildingCost, getBuildingTime, getBuildingCSTRequirement,
  requiresSpaceport, requiresShipyard
export getArmyBuildCost, getMarineBuildCost, getGroundBatteryBuildCost,
  getPlanetaryShieldCost, getGroundUnitCost, getGroundUnitBuildTime,
  getGroundUnitCSTRequirement, getGroundUnitPopulationCost
export getPlanetsideConstructionMultiplier

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
