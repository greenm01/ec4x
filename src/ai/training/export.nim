## Training Data Export for Neural Network Training
##
## Encodes game state and AI decisions into training data format for
## GPU-based PyTorch neural network training.
##
## This module provides:
## - Game state encoding to fixed-size vector (600 dimensions)
## - Action encoding for multi-head output
## - JSON export format for PyTorch data pipeline

import std/[json, tables, sequtils, options, strformat, algorithm]
import ../../engine/[gamestate, orders, fleet]
import ../../engine/diplomacy/types as dip_types
import ../../engine/research/types as res_types
import ../../common/types/[core, tech]
import ../../engine/logger
import ../common/types  # For AIStrategy and other AI types

type
  TrainingExample* = object
    ## Single training example: game state → AI decision
    turn*: int
    houseId*: HouseId
    strategy*: AIStrategy

    # Encoded state vector (600 dimensions)
    stateVector*: seq[float]

    # Action outputs (multi-head)
    diplomaticAction*: Option[DiplomaticActionEncoding]
    fleetActions*: seq[FleetActionEncoding]
    buildPriority*: BuildPriorityEncoding
    researchAllocation*: ResearchEncoding

  DiplomaticActionEncoding* = object
    actionType*: int  # 0-3: None, ProposeNAP, DeclareEnemy, SetNeutral
    targetHouse*: int  # 0-3: house index

  FleetActionEncoding* = object
    fleetIndex*: int  # Index in our fleet list
    orderType*: int  # 0-2: Hold, Move, Patrol
    targetSystemIndex*: int  # -1 for none, else system index

  BuildPriorityEncoding* = object
    military*: float  # 0-1: priority for military builds
    economic*: float  # 0-1: priority for economic builds
    defense*: float  # 0-1: priority for defensive builds

  ResearchEncoding* = object
    economic*: float  # 0-1: allocation to economic research
    science*: float  # 0-1: allocation to science
    weapons*: float  # 0-1: allocation to weapons
    other*: float  # 0-1: allocation to other tech

proc encodeGameState*(state: GameState, houseId: HouseId): seq[float] =
  ## Encode game state into 600-dimensional vector for neural network input
  ##
  ## Vector layout (600 dimensions total):
  ## - 0-99: House status (treasury, prestige, tech levels, etc.) [100 dims]
  ## - 100-199: Colony information (top 10 colonies, 10 dims each) [100 dims]
  ## - 200-399: Fleet information (top 20 fleets, 10 dims each) [200 dims]
  ## - 400-499: Diplomatic relations (25 houses max, 4 dims each) [100 dims]
  ## - 500-599: Strategic situation (threats, opportunities, etc.) [100 dims]

  result = newSeq[float](600)

  # Initialize to zero
  for i in 0..<600:
    result[i] = 0.0

  if houseId notin state.houses:
    logWarn(LogCategory.lcAI, &"encodeGameState: house {houseId} not found in game state")
    return result

  let house = state.houses[houseId]

  # Section 1: House status (0-99)
  var idx = 0

  # Basic resources (normalized)
  result[idx] = float(house.treasury) / 10000.0; inc idx  # 0: treasury
  result[idx] = float(house.prestige) / 1000.0; inc idx  # 1: prestige

  # Tech levels (0-20 scale, normalize to 0-1)
  result[idx] = float(house.techTree.levels.economicLevel) / 20.0; inc idx  # 2
  result[idx] = float(house.techTree.levels.scienceLevel) / 20.0; inc idx  # 3
  result[idx] = float(house.techTree.levels.weaponsTech) / 20.0; inc idx  # 4
  result[idx] = float(house.techTree.levels.constructionTech) / 20.0; inc idx  # 5
  result[idx] = float(house.techTree.levels.terraformingTech) / 20.0; inc idx  # 6
  result[idx] = float(house.techTree.levels.electronicIntelligence) / 20.0; inc idx  # 7
  result[idx] = float(house.techTree.levels.cloakingTech) / 20.0; inc idx  # 8
  result[idx] = float(house.techTree.levels.shieldTech) / 20.0; inc idx  # 9
  result[idx] = float(house.techTree.levels.counterIntelligence) / 20.0; inc idx  # 10
  result[idx] = float(house.techTree.levels.fighterDoctrine) / 20.0; inc idx  # 11
  result[idx] = float(house.techTree.levels.advancedCarrierOps) / 20.0; inc idx  # 12

  # Reserved for future house metrics (13-99)
  idx = 100

  # Section 2: Colony information (100-199)
  # Top 10 colonies by population units (production), 10 dims each
  var ourColonies = state.colonies.values.toSeq.filterIt(it.owner == houseId)
  ourColonies.sort(proc(a, b: Colony): int = cmp(b.populationUnits, a.populationUnits))

  for i in 0..<10:
    if i < ourColonies.len:
      let colony = ourColonies[i]
      result[idx] = float(colony.population) / 100.0; inc idx  # population
      result[idx] = float(colony.populationUnits) / 100.0; inc idx  # population units
      result[idx] = (if colony.blockaded: 1.0 else: 0.0); inc idx  # blockaded
      result[idx] = float(colony.infrastructure) / 10.0; inc idx  # infrastructure
      # Reserved (6 more dims per colony)
      idx += 6
    else:
      idx += 10  # Skip unused colony slot

  # Section 3: Fleet information (200-399)
  # Top 20 fleets by combat strength, 10 dims each
  var ourFleets = state.fleets.values.toSeq.filterIt(it.owner == houseId)
  ourFleets.sort(proc(a, b: Fleet): int = cmp(combatStrength(b), combatStrength(a)))

  idx = 200
  for i in 0..<20:
    if i < ourFleets.len:
      let fleet = ourFleets[i]
      result[idx] = float(combatStrength(fleet)) / 1000.0; inc idx  # combat strength
      result[idx] = float(fleet.squadrons.len) / 10.0; inc idx  # squadron count
      result[idx] = (if fleet.status == FleetStatus.Active: 1.0 else: 0.0); inc idx  # is active
      result[idx] = (if fleet.id in state.fleetOrders: 1.0 else: 0.0); inc idx  # has persistent orders
      # Reserved (6 more dims per fleet)
      idx += 6
    else:
      idx += 10  # Skip unused fleet slot

  # Section 4: Diplomatic relations (400-499)
  # Up to 25 houses, 4 dims each
  idx = 400
  var houseCount = 0
  for otherHouseId, otherHouse in state.houses:
    if otherHouseId != houseId and houseCount < 25:
      let dipState = dip_types.getDiplomaticState(house.diplomaticRelations, otherHouseId)

      # One-hot encode diplomatic state (3-state system)
      result[idx] = (if dipState == dip_types.DiplomaticState.Neutral: 1.0 else: 0.0); inc idx
      result[idx] = (if dipState == dip_types.DiplomaticState.Hostile: 1.0 else: 0.0); inc idx
      result[idx] = (if dipState == dip_types.DiplomaticState.Enemy: 1.0 else: 0.0); inc idx

      # Relative strength (their prestige / our prestige)
      let relativeStrength = if house.prestige > 0:
        float(otherHouse.prestige) / float(house.prestige)
      else:
        1.0
      result[idx] = min(relativeStrength, 5.0) / 5.0; inc idx  # cap at 5x

      inc houseCount
    else:
      idx += 4  # Skip unused house slot

  # Section 5: Strategic situation (500-599)
  idx = 500

  # Count various strategic factors
  var totalProduction = 0
  var coloniesUnderThreat = 0
  for colony in state.colonies.values:
    if colony.owner == houseId:
      totalProduction += colony.populationUnits  # Use PU for production
      if colony.blockaded:
        inc coloniesUnderThreat

  result[idx] = float(totalProduction) / 1000.0; inc idx  # 500: total production
  result[idx] = float(coloniesUnderThreat) / float(max(ourColonies.len, 1)); inc idx  # 501: threat ratio
  result[idx] = float(ourFleets.len) / 20.0; inc idx  # 502: fleet count
  result[idx] = float(ourColonies.len) / 30.0; inc idx  # 503: colony count

  # Calculate military and economic strength relative to enemies
  var ownMilitary = 0
  var enemyMilitary = 0
  var enemyEconomy = 0

  for fleet in state.fleets.values:
    if fleet.owner == houseId:
      ownMilitary += combatStrength(fleet)
    else:
      let dipState = dip_types.getDiplomaticState(house.diplomaticRelations, fleet.owner)
      if dipState == dip_types.DiplomaticState.Enemy:
        enemyMilitary += combatStrength(fleet)

  for otherHouse in state.houses.values:
    if otherHouse.id != houseId:
      let dipState = dip_types.getDiplomaticState(house.diplomaticRelations, otherHouse.id)
      if dipState == dip_types.DiplomaticState.Enemy:
        enemyEconomy += otherHouse.treasury
        # Estimate enemy production from their colonies
        for colony in state.colonies.values:
          if colony.owner == otherHouse.id:
            enemyEconomy += colony.production * 10

  let militaryRatio = if enemyMilitary > 0:
    float(ownMilitary) / float(enemyMilitary)
  else:
    10.0  # No enemies = overwhelming superiority

  let economicRatio = if enemyEconomy > 0:
    float(house.treasury + totalProduction * 10) / float(enemyEconomy)
  else:
    10.0

  result[idx] = min(militaryRatio, 10.0) / 10.0; inc idx  # 504: military ratio
  result[idx] = min(economicRatio, 10.0) / 10.0; inc idx  # 505: economic ratio

  # Game phase (Act1-4)
  let currentAct = getCurrentGameAct(state.turn)
  result[idx] = (if currentAct == GameAct.Act1_LandGrab: 1.0 else: 0.0); inc idx  # 506
  result[idx] = (if currentAct == GameAct.Act2_RisingTensions: 1.0 else: 0.0); inc idx  # 507
  result[idx] = (if currentAct == GameAct.Act3_TotalWar: 1.0 else: 0.0); inc idx  # 508
  result[idx] = (if currentAct == GameAct.Act4_Endgame: 1.0 else: 0.0); inc idx  # 509

  # Reserved for future strategic metrics (510-599)

proc encodeOrders*(orders: OrderPacket, state: GameState): tuple[
  diplomatic: Option[DiplomaticActionEncoding],
  fleets: seq[FleetActionEncoding],
  build: BuildPriorityEncoding,
  research: ResearchEncoding
] =
  ## Encode AI orders into multi-head action format

  # Encode diplomatic action
  if orders.diplomaticActions.len > 0:
    let dipAction = orders.diplomaticActions[0]
    let actionTypeInt = case dipAction.actionType
      of DiplomaticActionType.ProposeAllyPact: 1
      of DiplomaticActionType.DeclareEnemy: 2
      of DiplomaticActionType.SetNeutral: 3
      of DiplomaticActionType.BreakPact: 3  # Map to SetNeutral
      of DiplomaticActionType.AcceptProposal: 0  # Map to None
      of DiplomaticActionType.RejectProposal: 0  # Map to None
      of DiplomaticActionType.WithdrawProposal: 0  # Map to None

    # Convert HouseId to index (0-3)
    var targetIndex = 0
    var idx = 0
    for houseId in state.houses.keys:
      if houseId == dipAction.targetHouse:
        targetIndex = idx
        break
      inc idx

    result.diplomatic = some(DiplomaticActionEncoding(
      actionType: actionTypeInt,
      targetHouse: targetIndex
    ))

  # Encode fleet actions
  result.fleets = @[]
  for fleetOrder in orders.fleetOrders:
    let orderTypeInt = case fleetOrder.orderType
      of FleetOrderType.Hold: 0
      of FleetOrderType.Move: 1
      of FleetOrderType.Patrol: 2
      else: 0  # Map other types to Hold

    let targetIdx = if fleetOrder.targetSystem.isSome:
      # Convert SystemId to index
      var idx = 0
      for systemId in state.starMap.systems.keys:
        if systemId == fleetOrder.targetSystem.get():
          break
        inc idx
      idx
    else:
      -1

    result.fleets.add(FleetActionEncoding(
      fleetIndex: 0,  # Would need fleet index mapping
      orderType: orderTypeInt,
      targetSystemIndex: targetIdx
    ))

  # Encode build priority (normalized to sum to 1.0)
  var militaryCount = 0
  var economicCount = 0
  var defenseCount = 0

  for buildOrder in orders.buildOrders:
    case buildOrder.buildType
    of BuildType.Ship:
      inc militaryCount
    of BuildType.Infrastructure:
      inc economicCount
    of BuildType.Building:
      inc defenseCount

  let total = float(militaryCount + economicCount + defenseCount)
  if total > 0:
    result.build = BuildPriorityEncoding(
      military: float(militaryCount) / total,
      economic: float(economicCount) / total,
      defense: float(defenseCount) / total
    )
  else:
    result.build = BuildPriorityEncoding(
      military: 0.33, economic: 0.33, defense: 0.34
    )

  # Encode research allocation (already normalized)
  let resAlloc = orders.researchAllocation
  let resTotal = float(resAlloc.economic + resAlloc.science)
  let techTotal = resAlloc.technology.values.toSeq.foldl(a + b, 0)
  let grandTotal = resTotal + float(techTotal)

  if grandTotal > 0:
    let weaponsAlloc = resAlloc.technology.getOrDefault(TechField.WeaponsTech, 0)
    result.research = ResearchEncoding(
      economic: float(resAlloc.economic) / grandTotal,
      science: float(resAlloc.science) / grandTotal,
      weapons: float(weaponsAlloc) / grandTotal,
      other: float(techTotal - weaponsAlloc) / grandTotal
    )
  else:
    result.research = ResearchEncoding(
      economic: 0.25, science: 0.25, weapons: 0.25, other: 0.25
    )

proc exportTrainingExample*(
  turn: int,
  state: GameState,
  houseId: HouseId,
  strategy: AIStrategy,
  orders: OrderPacket
): JsonNode =
  ## Create and export a complete training example as JSON

  let stateVector = encodeGameState(state, houseId)
  let (diplomatic, fleets, build, research) = encodeOrders(orders, state)

  result = %* {
    "turn": turn,
    "house_id": $houseId,
    "strategy": $strategy,
    "state_vector": stateVector,
    "actions": {
      "diplomatic": if diplomatic.isSome:
        %* {
          "action_type": diplomatic.get().actionType,
          "target_house": diplomatic.get().targetHouse
        }
      else:
        newJNull(),
      "fleets": fleets.mapIt(%* {
        "fleet_index": it.fleetIndex,
        "order_type": it.orderType,
        "target_system": it.targetSystemIndex
      }),
      "build_priority": %* {
        "military": build.military,
        "economic": build.economic,
        "defense": build.defense
      },
      "research_allocation": %* {
        "economic": research.economic,
        "science": research.science,
        "weapons": research.weapons,
        "other": research.other
      }
    }
  }
