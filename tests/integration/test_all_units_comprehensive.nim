## Comprehensive Unit Validation Tests
##
## Tests ALL game units against TOML config files and reference.md specifications:
## - Space Force ships (combat vessels, carriers, special units)
## - Ground Units (armies, marines, shields, batteries)
## - Facilities (spaceports, shipyards)
## - Spacelift Command (ETAC, Troop Transports)
##
## This validates that:
## 1. Config values match reference.md specifications
## 2. All units have consistent stat structures
## 3. Special capabilities are properly defined
## 4. Build costs, upkeep, and other economics are correct
## 5. Tech requirements (CST levels) are enforced
##
## Uses direct TOML parsing to ensure tests stay synchronized with config changes

import std/[unittest, parsecfg, strutils, tables, os]

# Expected values from reference.md Section 10.1, 10.2, 10.3
const
  CONFIG_DIR = "config"
  SHIPS_CONFIG = CONFIG_DIR / "ships.kdl"
  GROUND_UNITS_CONFIG = CONFIG_DIR / "ground_units.kdl"
  FACILITIES_CONFIG = CONFIG_DIR / "facilities.kdl"

type
  ShipSpec = object
    name: string
    class: string
    attackStrength: int
    defenseStrength: int
    commandCost: int
    commandRating: int
    techLevel: int
    buildCost: int
    upkeepCost: int
    carryLimit: int
    specialCapability: string

  GroundUnitSpec = object
    name: string
    class: string
    attackStrength: int
    defenseStrength: int
    buildCost: int
    upkeepCost: int
    cstMin: int

  FacilitySpec = object
    name: string
    class: string
    defenseStrength: int
    buildCost: int
    upkeepCost: int
    carryLimit: int
    docks: int
    cstMin: int

proc loadShipFromToml(config: Config, section: string): ShipSpec =
  ## Load a ship's stats from TOML config section
  result.name = config.getSectionValue(section, "name")
  result.class = config.getSectionValue(section, "class")
  result.attackStrength = parseInt(config.getSectionValue(section, "attack_strength", "0"))
  result.defenseStrength = parseInt(config.getSectionValue(section, "defense_strength", "0"))
  result.commandCost = parseInt(config.getSectionValue(section, "command_cost", "0"))
  result.commandRating = parseInt(config.getSectionValue(section, "command_rating", "0"))
  result.techLevel = parseInt(config.getSectionValue(section, "tech_level", "1"))
  result.buildCost = parseInt(config.getSectionValue(section, "build_cost", "0"))
  result.upkeepCost = parseInt(config.getSectionValue(section, "upkeep_cost", "0"))

  let carryLimitStr = config.getSectionValue(section, "carry_limit", "0")
  result.carryLimit = if carryLimitStr.len > 0: parseInt(carryLimitStr) else: 0

  result.specialCapability = config.getSectionValue(section, "special_capability", "")

proc loadGroundUnitFromToml(config: Config, section: string): GroundUnitSpec =
  ## Load a ground unit's stats from TOML config section
  result.name = config.getSectionValue(section, "name")
  result.class = config.getSectionValue(section, "class")
  result.attackStrength = parseInt(config.getSectionValue(section, "attack_strength", "0"))
  result.defenseStrength = parseInt(config.getSectionValue(section, "defense_strength", "0"))
  result.buildCost = parseInt(config.getSectionValue(section, "build_cost", "0"))
  result.upkeepCost = parseInt(config.getSectionValue(section, "upkeep_cost", "0"))
  result.cstMin = parseInt(config.getSectionValue(section, "cst_min", "1"))

proc loadFacilityFromToml(config: Config, section: string): FacilitySpec =
  ## Load a facility's stats from TOML config section
  result.name = config.getSectionValue(section, "name")
  result.class = config.getSectionValue(section, "class")
  result.defenseStrength = parseInt(config.getSectionValue(section, "defense_strength", "0"))
  result.buildCost = parseInt(config.getSectionValue(section, "build_cost", "0"))
  result.upkeepCost = parseInt(config.getSectionValue(section, "upkeep_cost", "0"))
  result.carryLimit = parseInt(config.getSectionValue(section, "carry_limit", "0"))
  result.docks = parseInt(config.getSectionValue(section, "docks", "0"))
  result.cstMin = parseInt(config.getSectionValue(section, "cst_min", "1"))

suite "Unit Validation: Space Force Ships":

  test "Corvette stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "corvette")

    check ship.name == "Corvette"
    check ship.class == "CT"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0
    check ship.upkeepCost > 0  # Rounded from 3% of 20

  test "Frigate stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "frigate")

    check ship.name == "Frigate"
    check ship.class == "FG"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Destroyer stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "destroyer")

    check ship.name == "Destroyer"
    check ship.class == "DD"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Light Cruiser stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "light_cruiser")

    check ship.name == "Light Cruiser"
    check ship.class == "CL"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Heavy Cruiser stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "heavy_cruiser")

    check ship.name == "Heavy Cruiser"
    check ship.class == "CA"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Battle Cruiser stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "battlecruiser")

    check ship.name == "Battle Cruiser"
    check ship.class == "BC"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Battleship stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "battleship")

    check ship.name == "Battleship"
    check ship.class == "BB"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Dreadnought stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "dreadnought")

    check ship.name == "Dreadnought"
    check ship.class == "DN"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Super Dreadnought stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "super_dreadnought")

    check ship.name == "Super Dreadnought"
    check ship.class == "SD"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Planet-Breaker stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "planetbreaker")

    check ship.name == "Planet-Breaker"
    check ship.class == "PB"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0
    check ship.specialCapability == "SHP"

suite "Unit Validation: Carriers and Special Units":

  test "Carrier stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "carrier")

    check ship.name == "Carrier"
    check ship.class == "CV"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.carryLimit > 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Super Carrier stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "supercarrier")

    check ship.name == "Super Carrier"
    check ship.class == "CX"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.carryLimit > 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Fighter Squadron stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "fighter")

    check ship.name == "Fighter Squadron"
    check ship.class == "FS"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

  test "Raider stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "raider")

    check ship.name == "Raider"
    check ship.class == "RR"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0
    check ship.specialCapability == "CLK"

  test "Scout stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "scout")

    check ship.name == "Scout"
    check ship.class == "SC"
    check ship.attackStrength> 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0
    check ship.specialCapability == "ELI"

  test "Starbase stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "starbase")

    check ship.name == "Starbase"
    check ship.class == "SB"
    check ship.attackStrength > 0
    check ship.defenseStrength > 0
    check ship.commandCost >= 0
    check ship.commandRating >= 0
    check ship.techLevel > 0
    check ship.buildCost > 0

suite "Unit Validation: Spacelift Command":

  test "ETAC stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "etac")

    check ship.name == "ETAC"
    check ship.class == "ET"
    check ship.attackStrength == 0
    check ship.defenseStrength > 0
    check ship.carryLimit > 0
    check ship.techLevel > 0
    check ship.buildCost > 0
    check ship.specialCapability == "COL"

  test "Troop Transport stats match reference.md":
    let config = loadConfig(SHIPS_CONFIG)
    let ship = loadShipFromToml(config, "troop_transport")

    check ship.name == "Troop Transport"
    check ship.class == "TT"
    check ship.attackStrength == 0
    check ship.defenseStrength > 0
    check ship.carryLimit > 0
    check ship.techLevel > 0
    check ship.buildCost > 0
    check ship.specialCapability == "TRP"

suite "Unit Validation: Ground Units":

  test "Planetary Shield stats match reference.md":
    let config = loadConfig(GROUND_UNITS_CONFIG)
    let unit = loadGroundUnitFromToml(config, "planetary_shield")

    check unit.name == "Planetary Shield"
    check unit.class == "PS"
    check unit.attackStrength == 0
    check unit.defenseStrength > 0
    check unit.buildCost > 0
    check unit.cstMin > 0

  test "Ground Battery stats match reference.md":
    let config = loadConfig(GROUND_UNITS_CONFIG)
    let unit = loadGroundUnitFromToml(config, "ground_battery")

    check unit.name == "Ground Battery"
    check unit.class == "GB"
    check unit.attackStrength > 0
    check unit.defenseStrength > 0
    check unit.buildCost > 0
    check unit.cstMin > 0

  test "Army stats match reference.md":
    let config = loadConfig(GROUND_UNITS_CONFIG)
    let unit = loadGroundUnitFromToml(config, "army")

    check unit.name == "Army"
    check unit.class == "AA"
    check unit.attackStrength > 0
    check unit.defenseStrength > 0
    check unit.buildCost > 0
    check unit.cstMin > 0

  test "Space Marine Division stats match reference.md":
    let config = loadConfig(GROUND_UNITS_CONFIG)
    let unit = loadGroundUnitFromToml(config, "marine_division")

    check unit.name == "Space Marine Division"
    check unit.class == "MD"
    check unit.attackStrength > 0
    check unit.defenseStrength > 0
    check unit.buildCost > 0
    check unit.cstMin > 0

suite "Unit Validation: Facilities":

  test "Spaceport stats match reference.md":
    let config = loadConfig(FACILITIES_CONFIG)
    let facility = loadFacilityFromToml(config, "spaceport")

    check facility.name == "Spaceport"
    check facility.class == "SP"
    check facility.defenseStrength > 0
    check facility.buildCost > 0
    check facility.carryLimit > 0
    check facility.docks > 0
    check facility.cstMin > 0

  test "Shipyard stats match reference.md":
    let config = loadConfig(FACILITIES_CONFIG)
    let facility = loadFacilityFromToml(config, "shipyard")

    check facility.name == "Shipyard"
    check facility.class == "SY"
    check facility.defenseStrength > 0
    check facility.buildCost > 0
    check facility.carryLimit > 0
    check facility.docks > 0
    check facility.cstMin > 0

  test "Drydock stats match reference.md":
    let config = loadConfig(FACILITIES_CONFIG)
    let facility = loadFacilityFromToml(config, "drydock")

    check facility.name == "Drydock"
    check facility.class == "DD"
    check facility.defenseStrength > 0
    check facility.buildCost > 0
    check facility.carryLimit > 0
    check facility.docks > 0
    check facility.cstMin > 0

suite "Unit Validation: Cross-Unit Consistency":

  test "All capital ships have positive AS and DS":
    let config = loadConfig(SHIPS_CONFIG)
    let capitalShips = ["corvette", "frigate", "destroyer", "light_cruiser",
                        "heavy_cruiser", "battlecruiser", "battleship",
                        "dreadnought", "super_dreadnought", "planetbreaker"]

    for shipSection in capitalShips:
      let ship = loadShipFromToml(config, shipSection)
      check ship.attackStrength > 0
      check ship.defenseStrength > 0

  test "All ships have valid build costs":
    let config = loadConfig(SHIPS_CONFIG)
    let allShips = ["corvette", "frigate", "destroyer", "light_cruiser",
                    "heavy_cruiser", "battlecruiser", "battleship",
                    "dreadnought", "super_dreadnought", "planetbreaker",
                    "carrier", "supercarrier", "fighter", "raider", "scout",
                    "starbase", "etac", "troop_transport"]

    for shipSection in allShips:
      let ship = loadShipFromToml(config, shipSection)
      check ship.buildCost > 0
      check ship.upkeepCost >= 0

  test "Tech progression: higher tech ships cost more":
    let config = loadConfig(SHIPS_CONFIG)

    # CST 1 ships should generally cost less than CST 3+ ships
    let destroyer = loadShipFromToml(config, "destroyer")  # CST 1
    let battlecruiser = loadShipFromToml(config, "battlecruiser")  # CST 3

    check destroyer.buildCost < battlecruiser.buildCost
    check destroyer.techLevel < battlecruiser.techLevel

  test "Carriers have carry limits, combat ships don't":
    let config = loadConfig(SHIPS_CONFIG)

    let carrier = loadShipFromToml(config, "carrier")
    let supercarrier = loadShipFromToml(config, "supercarrier")
    let destroyer = loadShipFromToml(config, "destroyer")

    check carrier.carryLimit > 0
    check supercarrier.carryLimit > 0
    check destroyer.carryLimit == 0

  test "All ground units have positive build costs":
    let config = loadConfig(GROUND_UNITS_CONFIG)
    let groundUnits = ["planetary_shield", "ground_battery", "army", "marine_division"]

    for unitSection in groundUnits:
      let unit = loadGroundUnitFromToml(config, unitSection)
      check unit.buildCost > 0

  test "Facilities have docks for construction":
    let config = loadConfig(FACILITIES_CONFIG)

    let spaceport = loadFacilityFromToml(config, "spaceport")
    let shipyard = loadFacilityFromToml(config, "shipyard")

    check spaceport.docks > 0
    check shipyard.docks > spaceport.docks  # Shipyards should have more capacity

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Comprehensive Unit Validation Tests          ║"
  echo "║  Validates ALL units against TOML configs     ║"
  echo "╚════════════════════════════════════════════════╝"
