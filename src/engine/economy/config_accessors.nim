## Config Accessor Macros
##
## Data-Oriented Design: Eliminate 120+ lines of case duplication
## in construction.nim by using compile-time code generation
##
## Before: 18 × 2 case branches + 5 × 2 case branches = 56 case branches
## After: 2 macro calls

import std/macros
import ../../common/types/units
import ../config/[ships_config, construction_config, facilities_config, ground_units_config]

## Ship Config Accessor Macro

macro getShipField*(shipClass: ShipClass, fieldName: untyped, config: untyped): untyped =
  ## Generate case statement to access any ship config field
  ## Eliminates 18-branch case duplication across multiple procs
  ##
  ## Usage:
  ##   getShipField(shipClass, build_cost, globalShipsConfig)
  ##   getShipField(shipClass, as_rating, globalShipsConfig)

  result = nnkCaseStmt.newTree(shipClass)

  # Map ShipClass enum values to config field names
  let shipMappings = {
    "Fighter": "fighter",
    "Corvette": "corvette",
    "Frigate": "frigate",
    "Raider": "raider",
    "Destroyer": "destroyer",
    "Cruiser": "cruiser",
    "LightCruiser": "light_cruiser",
    "HeavyCruiser": "heavy_cruiser",
    "Carrier": "carrier",
    "SuperCarrier": "supercarrier",
    "Battleship": "battleship",
    "Battlecruiser": "battlecruiser",
    "Dreadnought": "dreadnought",
    "SuperDreadnought": "super_dreadnought",
    "TroopTransport": "troop_transport",
    "ETAC": "etac",
    "Scout": "scout",
    "Starbase": "starbase",
    "PlanetBreaker": "planetbreaker"
  }

  # Generate case branches
  for (enumName, configName) in shipMappings:
    let ofBranch = nnkOfBranch.newTree(
      nnkDotExpr.newTree(ident("ShipClass"), ident(enumName)),
      nnkStmtList.newTree(
        nnkReturnStmt.newTree(
          nnkDotExpr.newTree(
            nnkDotExpr.newTree(config, ident(configName)),
            fieldName
          )
        )
      )
    )
    result.add(ofBranch)

  # No else branch needed - all enum cases are covered

## Construction Time Accessor Macro

macro getConstructionTimeField*(shipClass: ShipClass, config: untyped): untyped =
  ## Generate case statement to access construction time fields
  ## These fields have "_base_time" suffix in config
  ##
  ## Usage:
  ##   getConstructionTimeField(shipClass, globalShipsConfig.construction)

  result = nnkCaseStmt.newTree(shipClass)

  # Map ShipClass to construction time field names
  let shipMappings = {
    "Fighter": "fighter_base_time",
    "Corvette": "corvette_base_time",
    "Frigate": "frigate_base_time",
    "Raider": "raider_base_time",
    "Destroyer": "destroyer_base_time",
    "Cruiser": "cruiser_base_time",
    "LightCruiser": "light_cruiser_base_time",
    "HeavyCruiser": "heavy_cruiser_base_time",
    "Carrier": "carrier_base_time",
    "SuperCarrier": "supercarrier_base_time",
    "Battleship": "battleship_base_time",
    "Battlecruiser": "battlecruiser_base_time",
    "Dreadnought": "dreadnought_base_time",
    "SuperDreadnought": "super_dreadnought_base_time",
    "TroopTransport": "troop_transport_base_time",
    "ETAC": "etac_base_time",
    "Scout": "scout_base_time",
    "Starbase": "starbase_base_time",
    "PlanetBreaker": "planetbreaker_base_time"
  }

  # Generate case branches
  for (enumName, fieldName) in shipMappings:
    let ofBranch = nnkOfBranch.newTree(
      nnkDotExpr.newTree(ident("ShipClass"), ident(enumName)),
      nnkStmtList.newTree(
        nnkReturnStmt.newTree(
          nnkDotExpr.newTree(config, ident(fieldName))
        )
      )
    )
    result.add(ofBranch)

  # No else branch needed - all enum cases are covered

## Clean Wrapper Procs (These replace the duplicated case statements)

proc getShipConstructionCost*(shipClass: ShipClass): int =
  ## Get construction cost (PC) for ship class from ships.toml
  ## Per reference.md:9.1
  ## REFACTORED: Was 44 lines, now 3 lines (macro generates code at compile time)
  getShipField(shipClass, build_cost, globalShipsConfig)

proc getShipBaseBuildTime*(shipClass: ShipClass): int =
  ## Get base construction time (before CST modifier) from ships.toml
  ## Per reference.md:9.1.1
  ## REFACTORED: Was 44 lines, now 3 lines (macro generates code at compile time)
  getConstructionTimeField(shipClass, globalShipsConfig.construction)

## Building Config (smaller duplication, but still worth cleaning up)

type BuildingConfig = object
  cost: int
  time: int
  requiresSpaceport: bool
  requiresShipyard: bool
  cstRequirement: int

proc getBuildingConfig(buildingType: string): BuildingConfig =
  ## Single lookup for all building properties
  ## Eliminates 3 separate case statements
  let constructionConfig = globalConstructionConfig.costs
  let constructionTimes = globalConstructionConfig.construction
  let facilitiesConfig = globalFacilitiesConfig

  case buildingType
  of "Shipyard":
    BuildingConfig(
      cost: facilitiesConfig.shipyard.build_cost,
      time: facilitiesConfig.shipyard.build_time,
      requiresSpaceport: facilitiesConfig.shipyard.requires_spaceport,
      requiresShipyard: false,
      cstRequirement: 0  # No CST requirement
    )
  of "Spaceport":
    BuildingConfig(
      cost: facilitiesConfig.spaceport.build_cost,
      time: facilitiesConfig.spaceport.build_time,
      requiresSpaceport: false,
      requiresShipyard: false,
      cstRequirement: 0
    )
  of "Starbase":
    BuildingConfig(
      cost: constructionConfig.starbase_cost,
      time: constructionTimes.starbase_turns,
      requiresSpaceport: false,
      requiresShipyard: constructionTimes.starbase_requires_shipyard,
      cstRequirement: globalShipsConfig.starbase.tech_level  # CST3 from ships.toml
    )
  of "GroundBattery":
    BuildingConfig(
      cost: constructionConfig.ground_battery_cost,
      time: constructionTimes.ground_battery_turns,
      requiresSpaceport: false,
      requiresShipyard: false,
      cstRequirement: 0
    )
  of "FighterSquadron":
    BuildingConfig(
      cost: constructionConfig.fighter_squadron_cost,
      time: 1,
      requiresSpaceport: false,
      requiresShipyard: false,
      cstRequirement: 0
    )
  else:
    BuildingConfig(cost: 50, time: 1, requiresSpaceport: false, requiresShipyard: false, cstRequirement: 0)

proc getBuildingCost*(buildingType: string): int =
  ## Get construction cost for building type from config
  ## REFACTORED: Was 19 lines, now single lookup
  getBuildingConfig(buildingType).cost

proc getBuildingTime*(buildingType: string): int =
  ## Building construction completes instantly (1 turn)
  ## Per new time narrative: turns represent variable time periods (1-15 years)
  ## Multi-turn construction would cause severe balance issues across map sizes
  return 1  # Always instant

proc requiresSpaceport*(buildingType: string): bool =
  ## Check if building requires a spaceport
  ## REFACTORED: Was 9 lines, now single lookup
  getBuildingConfig(buildingType).requiresSpaceport

proc requiresShipyard*(buildingType: string): bool =
  ## Check if building requires a shipyard (e.g., Starbase requires shipyard)
  ## Per construction.toml: starbase_requires_shipyard = true
  getBuildingConfig(buildingType).requiresShipyard

proc getBuildingCSTRequirement*(buildingType: string): int =
  ## Get CST tech level required to build building type
  ## Per ships.toml: Starbase has tech_level = 3 (CST3 requirement)
  ## Returns 0 for buildings with no CST requirement
  getBuildingConfig(buildingType).cstRequirement

proc getShipCSTRequirement*(shipClass: ShipClass): int =
  ## Get CST tech level required to build ship class
  ## Per economy.md:4.5 - CST unlocks new ship classes
  ## Returns 0 for ground units (no CST requirement)
  getShipField(shipClass, tech_level, globalShipsConfig)

## Ground Units Cost Accessors
## Added for Phase 1 RBA cost accessor fixes

proc getPlanetaryShieldCost*(sldLevel: int): int =
  ## Get construction cost for planetary shield by SLD tech level
  ## Returns cost from construction.toml for SLD1-6 shields
  ## Returns 0 for invalid levels
  case sldLevel
  of 1: globalConstructionConfig.costs.planetary_shield_sld1_cost
  of 2: globalConstructionConfig.costs.planetary_shield_sld2_cost
  of 3: globalConstructionConfig.costs.planetary_shield_sld3_cost
  of 4: globalConstructionConfig.costs.planetary_shield_sld4_cost
  of 5: globalConstructionConfig.costs.planetary_shield_sld5_cost
  of 6: globalConstructionConfig.costs.planetary_shield_sld6_cost
  else: 0

proc getArmyBuildCost*(): int =
  ## Get construction cost for army division
  ## Returns build_cost from ground_units.toml
  globalGroundUnitsConfig.army.build_cost

proc getMarineBuildCost*(): int =
  ## Get construction cost for marine division
  ## Returns build_cost from ground_units.toml
  globalGroundUnitsConfig.marine_division.build_cost

## Export for use in construction.nim
export getShipConstructionCost, getShipBaseBuildTime, getShipCSTRequirement
export getBuildingCost, getBuildingTime, requiresSpaceport, requiresShipyard, getBuildingCSTRequirement
export getPlanetaryShieldCost, getArmyBuildCost, getMarineBuildCost
