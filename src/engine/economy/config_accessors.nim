## Config Accessor Macros
##
## Data-Oriented Design: Eliminate 120+ lines of case duplication
## in construction.nim by using compile-time code generation
##
## Before: 18 × 2 case branches + 5 × 2 case branches = 56 case branches
## After: 2 macro calls

import std/macros
import ../../common/types/units
import ../config/[ships_config, construction_config, facilities_config]

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

  # Add else branch (should never hit, but makes Nim happy)
  result.add(nnkElse.newTree(
    nnkStmtList.newTree(
      nnkReturnStmt.newTree(newLit(0))
    )
  ))

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

  # Add else branch (should never hit, but makes Nim happy)
  result.add(nnkElse.newTree(
    nnkStmtList.newTree(
      nnkReturnStmt.newTree(newLit(0))
    )
  ))

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
      requiresSpaceport: facilitiesConfig.shipyard.requires_spaceport
    )
  of "Spaceport":
    BuildingConfig(
      cost: facilitiesConfig.spaceport.build_cost,
      time: facilitiesConfig.spaceport.build_time,
      requiresSpaceport: false
    )
  of "Starbase":
    BuildingConfig(
      cost: constructionConfig.starbase_cost,
      time: constructionTimes.starbase_turns,
      requiresSpaceport: false
    )
  of "GroundBattery":
    BuildingConfig(
      cost: constructionConfig.ground_battery_cost,
      time: constructionTimes.ground_battery_turns,
      requiresSpaceport: false
    )
  of "FighterSquadron":
    BuildingConfig(
      cost: constructionConfig.fighter_squadron_cost,
      time: 1,
      requiresSpaceport: false
    )
  else:
    BuildingConfig(cost: 50, time: 1, requiresSpaceport: false)

proc getBuildingCost*(buildingType: string): int =
  ## Get construction cost for building type from config
  ## REFACTORED: Was 19 lines, now single lookup
  getBuildingConfig(buildingType).cost

proc getBuildingTime*(buildingType: string): int =
  ## Get construction time for building type from config
  ## REFACTORED: Was 18 lines, now single lookup
  getBuildingConfig(buildingType).time

proc requiresSpaceport*(buildingType: string): bool =
  ## Check if building requires a spaceport
  ## REFACTORED: Was 9 lines, now single lookup
  getBuildingConfig(buildingType).requiresSpaceport

## Export for use in construction.nim
export getShipConstructionCost, getShipBaseBuildTime
export getBuildingCost, getBuildingTime, requiresSpaceport
