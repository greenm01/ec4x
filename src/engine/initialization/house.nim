## @initialization/house.nim
##
## Creates new House objects with starting resources and technology,
## compatible with the new DoD type system.

import std/tables
import ../types/[core, house, tech, espionage, income]
import ../config/[prestige_config, tech_config, game_setup_config]

proc initHouse*(houseId: HouseId, name: string): House =
  ## Creates a new House object with default starting values.
  let startingTech = tech_config.globalTechConfig.starting_tech
  
  result = House(
    id: houseId,
    name: name,
    prestige: prestige_config.globalPrestigeConfig.victory.starting_prestige,
    treasury: game_setup_config.globalGameSetupConfig.starting_resources.treasury,
    techTree: TechTree(
      houseId: houseId,
      levels: TechLevel(
        economicLevel: startingTech.economic_level,
        scienceLevel: startingTech.science_level,
        constructionTech: startingTech.construction_tech,
        weaponsTech: startingTech.weapons_tech,
        terraformingTech: startingTech.terraforming_tech,
        electronicIntelligence: startingTech.electronic_intelligence,
        cloakingTech: startingTech.cloaking_tech,
        shieldTech: startingTech.shield_tech,
        counterIntelligence: startingTech.counter_intelligence,
        fighterDoctrine: startingTech.fighter_doctrine,
        advancedCarrierOps: startingTech.advanced_carrier_ops
      ),
      accumulated: ResearchPoints(economic: 0'i32, science: 0'i32, technology: initTable[TechField, int32]()),
      breakthroughBonus: initTable[TechField, float32]()
    ),
    espionageBudget: EspionageBudget(houseId: houseId),
    taxPolicy: TaxPolicy(currentRate:50'i32, history: @[50'i32]),
    isEliminated: false,
    eliminatedTurn: 0'i32
  )
