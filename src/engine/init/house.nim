## @initialization/house.nim
##
## Creates new House objects with starting resources and technology,
## compatible with the new DoD type system.

import std/tables
import ../globals
import ../types/[core, house, tech, espionage, income]

proc initHouse*(houseId: HouseId, name: string): House =
  ## Creates a new House object with default starting values.
  let startingTech = gameSetup.startingTech

  result = House(
    id: houseId,
    name: name,
    prestige: gameSetup.startingResources.startingPrestige,
    treasury: gameSetup.startingResources.treasury,
    techTree: TechTree(
      houseId: houseId,
      levels: TechLevel(
        economicLevel: startingTech.economicLevel,
        scienceLevel: startingTech.scienceLevel,
        constructionTech: startingTech.constructionTech,
        weaponsTech: startingTech.weaponsTech,
        terraformingTech: startingTech.terraformingTech,
        electronicIntelligence: startingTech.electronicIntelligence,
        cloakingTech: startingTech.cloakingTech,
        shieldTech: startingTech.shieldTech,
        counterIntelligence: startingTech.counterIntelligence,
        fighterDoctrine: startingTech.fighterDoctrine,
        advancedCarrierOps: startingTech.advancedCarrierOps
      ),
      accumulated: ResearchPoints(
        economic: 0'i32, science: 0'i32, technology: initTable[TechField, int32]()
      ),
      breakthroughBonus: initTable[TechField, float32](),
    ),
    espionageBudget: EspionageBudget(houseId: houseId),
    taxPolicy: TaxPolicy(currentRate: 50'i32, history: @[50'i32]),
    isEliminated: false,
    eliminatedTurn: 0'i32,
    status: HouseStatus.Active,
    turnsWithoutOrders: 0'i32,
    consecutiveShortfallTurns: 0'i32,
    negativePrestigeTurns: 0'i32,
    planetBreakerCount: 0'i32,
  )
