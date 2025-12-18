## Phase 3: Requirement Execution
##
## Execute advisor requirements using allocated budgets

import std/[strformat, strutils, sequtils, options, random, tables]
import ../../../common/types/units
import ../../../engine/[fog_of_war, logger, orders]
import ../../../engine/research/types as res_types
import ../../../engine/espionage/types as esp_types
import ../controller_types
import ../treasurer/multi_advisor
import ../logothete/allocation
import ../drungarius
import ../eparch
import ../basileus/execution as basileus_exec

proc executeResearchAllocation*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation
): res_types.ResearchAllocation =
  ## Execute Logothete research requirements with allocated budget

  let researchBudget = allocation.budgets.getOrDefault(controller_types.AdvisorType.Logothete, 0)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Executing research allocation " &
          &"(budget={researchBudget}PP)")

  # Use Logothete allocation module
  result = allocateResearch(
    controller,
    filtered,
    researchBudget
  )

  return result

proc executeEspionageAction*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation,
  rng: var Rand
): Option[EspionageAttempt] =
  ## Execute Drungarius espionage requirements with allocated budget

  let espionageBudget = allocation.budgets.getOrDefault(controller_types.AdvisorType.Drungarius, 0)
  let house = filtered.ownHouse

  # Calculate projected EBP/CIP from budget
  # Conversion: 1 PP = 1 EBP, 1 PP = 0.5 CIP (counter-intel is cheaper than ops)
  let projectedEBP = house.espionageBudget.ebpPoints + espionageBudget
  let projectedCIP = house.espionageBudget.cipPoints + (espionageBudget div 2)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Executing espionage action " &
          &"(budget={espionageBudget}PP, projectedEBP={projectedEBP}, projectedCIP={projectedCIP})")

  # Use Drungarius module to generate espionage action with proper budget
  result = generateEspionageAction(controller, filtered, projectedEBP, projectedCIP, rng)

  return result

proc executeTerraformOrders*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation,
  rng: var Rand
): seq[TerraformOrder] =
  ## Execute Eparch economic requirements with allocated budget

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Executing terraform orders " &
          &"(budget={allocation.budgets.getOrDefault(AdvisorType.Eparch, 0)}PP)")

  # Use Eparch module to generate terraform orders
  result = generateTerraformOrders(controller, filtered, rng)

  return result

proc executeFacilityOrders*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation
): seq[BuildOrder] =
  ## Execute Eparch facility requirements (Shipyards/Spaceports)
  ## Converts fulfilled EconomicRequirements into BuildOrders

  result = @[]

  let eparchBudget = allocation.budgets.getOrDefault(AdvisorType.Eparch, 0)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === EXECUTING FACILITY ORDERS ===")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Eparch budget: {eparchBudget}PP")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Fulfilled requirements count: " &
          &"{allocation.eparchFeedback.fulfilledRequirements.len}")

  # Get fulfilled requirements from Eparch feedback
  for econReq in allocation.eparchFeedback.fulfilledRequirements:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Processing fulfilled requirement: " &
            &"type={econReq.requirementType}, target={econReq.targetColony}")

    # Only process Facility requirements
    if econReq.requirementType != EconomicRequirementType.Facility:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Skipping non-facility requirement ({econReq.requirementType})")
      continue

    # Facility type must be specified
    if econReq.facilityType.isNone:
      logWarn(LogCategory.lcAI,
              &"{controller.houseId} Facility requirement missing facilityType!")
      continue

    let facilityType = econReq.facilityType.get()

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} CREATING BUILDORDER: {facilityType} at {econReq.targetColony}")

    # SPECIAL CASE: ETACs are ships, not buildings
    if facilityType == "ETAC":
      # Calculate quantity from estimated cost (each ETAC costs 15PP)
      let etacCost = 15  # From ship config
      let quantity = max(1, econReq.estimatedCost div etacCost)

      let buildOrder = BuildOrder(
        colonySystem: econReq.targetColony,
        buildType: BuildType.Ship,
        quantity: quantity,
        shipClass: some(ShipClass.ETAC),
        buildingType: none(string),
        industrialUnits: 0
      )
      result.add(buildOrder)

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} *** ETAC SHIP BUILDORDER CREATED: {quantity} " &
              &"ETACs at {econReq.targetColony} (cost={econReq.estimatedCost}PP) ***")
    else:
      # Regular facility (Spaceport, Shipyard, Starbase)
      let buildOrder = BuildOrder(
        colonySystem: econReq.targetColony,
        buildType: BuildType.Building,
        quantity: 1,
        shipClass: none(ShipClass),
        buildingType: some(facilityType),
        industrialUnits: 0
      )
      result.add(buildOrder)

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} *** FACILITY BUILDORDER CREATED: {facilityType} at " &
              &"{econReq.targetColony} (cost={econReq.estimatedCost}PP) ***")

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Facility orders: {result.len} facilities queued")

proc executePopulationTransferOrders*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation
): seq[PopulationTransferOrder] =
  ## Execute Eparch population transfer requirements (Space Guild)
  ## Converts fulfilled EconomicRequirements into PopulationTransferOrders
  ##
  ## Design: Source colony in targetColony, destination encoded in facilityType
  ## Format: facilityType = "TRANSFER_TO:systemId"

  result = @[]

  let eparchBudget = allocation.budgets.getOrDefault(AdvisorType.Eparch, 0)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === EXECUTING POPULATION TRANSFER ORDERS ===")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Eparch budget: {eparchBudget}PP")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Fulfilled requirements count: " &
          &"{allocation.eparchFeedback.fulfilledRequirements.len}")

  # Get fulfilled requirements from Eparch feedback
  for econReq in allocation.eparchFeedback.fulfilledRequirements:
    # Only process PopulationTransfer requirements
    if econReq.requirementType != EconomicRequirementType.PopulationTransfer:
      continue

    # Extract destination from facilityType encoding
    if econReq.facilityType.isNone:
      logWarn(LogCategory.lcAI,
              &"{controller.houseId} PopulationTransfer requirement missing " &
              &"destination encoding!")
      continue

    let encodedDest = econReq.facilityType.get()
    if not encodedDest.startsWith("TRANSFER_TO:"):
      logWarn(LogCategory.lcAI,
              &"{controller.houseId} Invalid destination encoding: {encodedDest}")
      continue

    # Parse destination SystemId
    let destStr = encodedDest[12..^1]  # Skip "TRANSFER_TO:" prefix
    var destSystemId: SystemId
    try:
      destSystemId = SystemId(parseInt(destStr))
    except ValueError:
      logWarn(LogCategory.lcAI,
              &"{controller.houseId} Failed to parse destination: {destStr}")
      continue

    # Validate source and destination colonies exist and are owned
    let sourceColony = filtered.ownColonies.filterIt(it.systemId == econReq.targetColony)
    let destColony = filtered.ownColonies.filterIt(it.systemId == destSystemId)

    if sourceColony.len == 0:
      logWarn(LogCategory.lcAI,
              &"{controller.houseId} Source colony {econReq.targetColony} not found!")
      continue

    if destColony.len == 0:
      logWarn(LogCategory.lcAI,
              &"{controller.houseId} Destination colony {destSystemId} not found!")
      continue

    # Validate source has population to transfer
    if sourceColony[0].population <= 1:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Source colony {econReq.targetColony} has " &
              &"insufficient population for transfer")
      continue

    # Create PopulationTransferOrder
    let order = PopulationTransferOrder(
      sourceColony: econReq.targetColony,
      destColony: destSystemId,
      ptuAmount: 1  # Always 1 PTU per transfer (from opportunity evaluation)
    )
    result.add(order)

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} *** POPULATION TRANSFER ORDER CREATED: " &
            &"{econReq.targetColony} → {destSystemId} (1 PTU, 1 PP) ***")

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Population transfer orders: {result.len} transfers queued")

proc executeDiplomaticActions*(
  controller: AIController,
  filtered: FilteredGameState
): seq[DiplomaticAction] =
  ## Execute Protostrator diplomatic requirements (costs 0 PP)
  ## This function redirects to the centralized Basileus execution module
  ## for cleaner separation of concerns (advisors recommend, Basileus executes)
  return basileus_exec.executeDiplomaticActions(controller, filtered)
