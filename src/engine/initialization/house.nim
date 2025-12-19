## House Initialization
##
## Creates new houses with starting resources and technology.
## Extracted from gamestate.nim as part of initialization refactoring.

import std/[strutils, options]
import ../gamestate
import ../config/[prestige_config, tech_config, game_setup_config]
import ../types/research as res_types
import ../types/diplomacy as dip_types
import ../types/espionage as esp_types
import ../types/economy as econ_types
import ../types/intelligence as intel_types
import ../../common/types/core
import ./validation

proc initializeHouse*(name: string, color: string): House =
  ## Create a new house with starting resources
  ## Per economy.md:4.0: "ALL technology levels start at level 1, never 0"
  ##
  ## Uses configuration from:
  ## - config/prestige_config.toml: starting_prestige
  ## - config/tech_config.toml: starting tech levels
  ## - game_setup/standard.toml: treasury (TODO: will use in Phase 4)

  let startingTech = tech_config.globalTechConfig.starting_tech

  result = House(
    id: "house-" & name.toLower(),
    name: name,
    color: color,
    prestige: prestige_config.globalPrestigeConfig.victory.starting_prestige,
    treasury: game_setup_config.globalGameSetupConfig.starting_resources.treasury,
    techTree: res_types.initTechTree(res_types.TechLevel(
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
    )),
    eliminated: false,
    status: HouseStatus.Active,
    negativePrestigeTurns: 0,
    turnsWithoutOrders: 0,
    diplomaticRelations: dip_types.initDiplomaticRelations(),
    violationHistory: dip_types.initViolationHistory(),
    espionageBudget: esp_types.initEspionageBudget(),
    taxPolicy: econ_types.TaxPolicy(
      currentRate: 50, history: @[50]),  # Default 50% tax rate
    planetBreakerCount: 0,
    intelligence: intel_types.newIntelligenceDatabase(),
    latestIncomeReport: none(econ_types.HouseIncomeReport),
    fallbackRoutes: @[],  # Initialize empty, populated by AI strategy
    autoRetreatPolicy: AutoRetreatPolicy.MissionsOnly
  )

  # Validate tech tree
  validation.validateTechTree(result.techTree)
