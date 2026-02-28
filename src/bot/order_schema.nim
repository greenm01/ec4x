## Strict JSON order draft schema for LLM bot output.

import std/[json, options, tables]

type
  BotFleetOrder* = object
    fleetId*: int
    commandType*: string
    targetSystemId*: Option[int]
    targetFleetId*: Option[int]
    roe*: Option[int]

  BotBuildOrder* = object
    colonyId*: int
    buildType*: string
    shipClass*: Option[string]
    facilityClass*: Option[string]
    groundClass*: Option[string]
    quantity*: Option[int]

  BotZeroTurnOrder* = object
    commandType*: string
    sourceFleetId*: Option[int]
    targetFleetId*: Option[int]
    shipIndices*: seq[int]
    fighterShipIds*: seq[int]
    carrierShipId*: Option[int]
    sourceCarrierShipId*: Option[int]
    targetCarrierShipId*: Option[int]
    cargoType*: Option[string]
    quantity*: Option[int]

  BotRepairOrder* = object
    colonyId*: int
    targetType*: string
    targetId*: int
    priority*: Option[int]

  BotScrapOrder* = object
    colonyId*: int
    targetType*: string
    targetId*: int
    acknowledgeQueueLoss*: Option[bool]

  BotPopulationTransfer* = object
    sourceColonyId*: int
    destColonyId*: int
    ptuAmount*: int

  BotTerraformOrder* = object
    colonyId*: int

  BotColonyManagementOrder* = object
    colonyId*: int
    taxRate*: Option[int]
    autoRepair*: Option[bool]
    autoLoadMarines*: Option[bool]
    autoLoadFighters*: Option[bool]

  BotDiplomaticOrder* = object
    targetHouseId*: int
    action*: string
    proposalId*: Option[int]
    proposedState*: Option[string]

  BotEspionageOrder* = object
    operation*: string
    targetHouseId*: Option[int]
    targetSystemId*: Option[int]

  BotResearchAllocation* = object
    economic*: Option[int]
    science*: Option[int]
    fields*: Table[string, int]

  BotOrderDraft* = object
    turn*: int
    houseId*: int
    fleetCommands*: seq[BotFleetOrder]
    buildCommands*: seq[BotBuildOrder]
    repairCommands*: seq[BotRepairOrder]
    scrapCommands*: seq[BotScrapOrder]
    zeroTurnCommands*: seq[BotZeroTurnOrder]
    populationTransfers*: seq[BotPopulationTransfer]
    terraformCommands*: seq[BotTerraformOrder]
    colonyManagement*: seq[BotColonyManagementOrder]
    espionageActions*: seq[BotEspionageOrder]
    diplomaticCommand*: Option[BotDiplomaticOrder]
    researchAllocation*: Option[BotResearchAllocation]
    ebpInvestment*: Option[int]
    cipInvestment*: Option[int]

  BotOrderParseResult* = object
    ok*: bool
    draft*: BotOrderDraft
    errors*: seq[string]

proc parseRequiredInt(node: JsonNode, key: string,
    errors: var seq[string]): int =
  if key notin node:
    errors.add("Missing required field: " & key)
    return 0
  if node[key].kind != JInt:
    errors.add("Expected int for field: " & key)
    return 0
  node[key].getInt()

proc parseOptionalInt(node: JsonNode, key: string,
    errors: var seq[string]): Option[int] =
  if key notin node:
    return none(int)
  if node[key].kind == JNull:
    return none(int)
  if node[key].kind != JInt:
    errors.add("Expected optional int for field: " & key)
    return none(int)
  some(node[key].getInt())

proc parseOptionalBool(node: JsonNode, key: string,
    errors: var seq[string]): Option[bool] =
  if key notin node:
    return none(bool)
  if node[key].kind == JNull:
    return none(bool)
  if node[key].kind != JBool:
    errors.add("Expected optional bool for field: " & key)
    return none(bool)
  some(node[key].getBool())

proc parseRequiredString(node: JsonNode, key: string,
    errors: var seq[string]): string =
  if key notin node:
    errors.add("Missing required field: " & key)
    return ""
  if node[key].kind != JString:
    errors.add("Expected string for field: " & key)
    return ""
  node[key].getStr()

proc parseOptionalString(node: JsonNode, key: string,
    errors: var seq[string]): Option[string] =
  if key notin node:
    return none(string)
  if node[key].kind == JNull:
    return none(string)
  if node[key].kind != JString:
    errors.add("Expected optional string for field: " & key)
    return none(string)
  some(node[key].getStr())

proc parseFleetCommands(node: JsonNode,
    errors: var seq[string]): seq[BotFleetOrder] =
  if node.kind != JArray:
    errors.add("fleetCommands must be an array")
    return @[]
  result = @[]
  for idx in 0 ..< node.len:
    let item = node[idx]
    if item.kind != JObject:
      errors.add("fleetCommands[" & $idx & "] must be an object")
      continue
    result.add(BotFleetOrder(
      fleetId: parseRequiredInt(item, "fleetId", errors),
      commandType: parseRequiredString(item, "commandType", errors),
      targetSystemId: parseOptionalInt(item, "targetSystemId", errors),
      targetFleetId: parseOptionalInt(item, "targetFleetId", errors),
      roe: parseOptionalInt(item, "roe", errors)
    ))

proc parseBuildCommands(node: JsonNode,
    errors: var seq[string]): seq[BotBuildOrder] =
  if node.kind != JArray:
    errors.add("buildCommands must be an array")
    return @[]
  result = @[]
  for idx in 0 ..< node.len:
    let item = node[idx]
    if item.kind != JObject:
      errors.add("buildCommands[" & $idx & "] must be an object")
      continue
    result.add(BotBuildOrder(
      colonyId: parseRequiredInt(item, "colonyId", errors),
      buildType: parseRequiredString(item, "buildType", errors),
      shipClass: parseOptionalString(item, "shipClass", errors),
      facilityClass: parseOptionalString(item, "facilityClass", errors),
      groundClass: parseOptionalString(item, "groundClass", errors),
      quantity: parseOptionalInt(item, "quantity", errors)
    ))

proc parseRepairCommands(node: JsonNode,
    errors: var seq[string]): seq[BotRepairOrder] =
  if node.kind != JArray:
    errors.add("repairCommands must be an array")
    return @[]
  result = @[]
  for idx in 0 ..< node.len:
    let item = node[idx]
    if item.kind != JObject:
      errors.add("repairCommands[" & $idx & "] must be an object")
      continue
    result.add(BotRepairOrder(
      colonyId: parseRequiredInt(item, "colonyId", errors),
      targetType: parseRequiredString(item, "targetType", errors),
      targetId: parseRequiredInt(item, "targetId", errors),
      priority: parseOptionalInt(item, "priority", errors)
    ))

proc parseScrapCommands(node: JsonNode,
    errors: var seq[string]): seq[BotScrapOrder] =
  if node.kind != JArray:
    errors.add("scrapCommands must be an array")
    return @[]
  result = @[]
  for idx in 0 ..< node.len:
    let item = node[idx]
    if item.kind != JObject:
      errors.add("scrapCommands[" & $idx & "] must be an object")
      continue
    result.add(BotScrapOrder(
      colonyId: parseRequiredInt(item, "colonyId", errors),
      targetType: parseRequiredString(item, "targetType", errors),
      targetId: parseRequiredInt(item, "targetId", errors),
      acknowledgeQueueLoss: parseOptionalBool(
        item, "acknowledgeQueueLoss", errors
      )
    ))

proc parseIntArray(node: JsonNode, key: string,
    errors: var seq[string]): seq[int] =
  if key notin node:
    return @[]
  if node[key].kind != JArray:
    errors.add(key & " must be an array")
    return @[]
  for item in node[key]:
    if item.kind != JInt:
      errors.add(key & " entries must be ints")
      continue
    result.add(item.getInt())

proc parseZeroTurnCommands(node: JsonNode,
    errors: var seq[string]): seq[BotZeroTurnOrder] =
  if node.kind != JArray:
    errors.add("zeroTurnCommands must be an array")
    return @[]
  result = @[]
  for idx in 0 ..< node.len:
    let item = node[idx]
    if item.kind != JObject:
      errors.add("zeroTurnCommands[" & $idx & "] must be an object")
      continue
    result.add(BotZeroTurnOrder(
      commandType: parseRequiredString(item, "commandType", errors),
      sourceFleetId: parseOptionalInt(item, "sourceFleetId", errors),
      targetFleetId: parseOptionalInt(item, "targetFleetId", errors),
      shipIndices: parseIntArray(item, "shipIndices", errors),
      fighterShipIds: parseIntArray(item, "fighterShipIds", errors),
      carrierShipId: parseOptionalInt(item, "carrierShipId", errors),
      sourceCarrierShipId: parseOptionalInt(
        item, "sourceCarrierShipId", errors
      ),
      targetCarrierShipId: parseOptionalInt(
        item, "targetCarrierShipId", errors
      ),
      cargoType: parseOptionalString(item, "cargoType", errors),
      quantity: parseOptionalInt(item, "quantity", errors)
    ))

proc parsePopulationTransfers(node: JsonNode,
    errors: var seq[string]): seq[BotPopulationTransfer] =
  if node.kind != JArray:
    errors.add("populationTransfers must be an array")
    return @[]
  result = @[]
  for idx in 0 ..< node.len:
    let item = node[idx]
    if item.kind != JObject:
      errors.add("populationTransfers[" & $idx & "] must be an object")
      continue
    result.add(BotPopulationTransfer(
      sourceColonyId: parseRequiredInt(item, "sourceColonyId", errors),
      destColonyId: parseRequiredInt(item, "destColonyId", errors),
      ptuAmount: parseRequiredInt(item, "ptuAmount", errors)
    ))

proc parseTerraformCommands(node: JsonNode,
    errors: var seq[string]): seq[BotTerraformOrder] =
  if node.kind != JArray:
    errors.add("terraformCommands must be an array")
    return @[]
  result = @[]
  for idx in 0 ..< node.len:
    let item = node[idx]
    if item.kind != JObject:
      errors.add("terraformCommands[" & $idx & "] must be an object")
      continue
    result.add(BotTerraformOrder(
      colonyId: parseRequiredInt(item, "colonyId", errors)
    ))

proc parseColonyManagement(node: JsonNode,
    errors: var seq[string]): seq[BotColonyManagementOrder] =
  if node.kind != JArray:
    errors.add("colonyManagement must be an array")
    return @[]
  result = @[]
  for idx in 0 ..< node.len:
    let item = node[idx]
    if item.kind != JObject:
      errors.add("colonyManagement[" & $idx & "] must be an object")
      continue
    result.add(BotColonyManagementOrder(
      colonyId: parseRequiredInt(item, "colonyId", errors),
      taxRate: parseOptionalInt(item, "taxRate", errors),
      autoRepair: parseOptionalBool(item, "autoRepair", errors),
      autoLoadMarines: parseOptionalBool(item, "autoLoadMarines", errors),
      autoLoadFighters: parseOptionalBool(item, "autoLoadFighters", errors)
    ))

proc parseEspionageActions(node: JsonNode,
    errors: var seq[string]): seq[BotEspionageOrder] =
  if node.kind != JArray:
    errors.add("espionageActions must be an array")
    return @[]
  result = @[]
  for idx in 0 ..< node.len:
    let item = node[idx]
    if item.kind != JObject:
      errors.add("espionageActions[" & $idx & "] must be an object")
      continue
    result.add(BotEspionageOrder(
      operation: parseRequiredString(item, "operation", errors),
      targetHouseId: parseOptionalInt(item, "targetHouseId", errors),
      targetSystemId: parseOptionalInt(item, "targetSystemId", errors)
    ))

proc parseDiplomatic(node: JsonNode,
    errors: var seq[string]): Option[BotDiplomaticOrder] =
  if node.kind == JNull:
    return none(BotDiplomaticOrder)
  if node.kind != JObject:
    errors.add("diplomaticCommand must be object or null")
    return none(BotDiplomaticOrder)
  some(BotDiplomaticOrder(
    targetHouseId: parseRequiredInt(node, "targetHouseId", errors),
    action: parseRequiredString(node, "action", errors),
    proposalId: parseOptionalInt(node, "proposalId", errors),
    proposedState: parseOptionalString(node, "proposedState", errors)
  ))

proc parseResearch(node: JsonNode,
    errors: var seq[string]): Option[BotResearchAllocation] =
  if node.kind == JNull:
    return none(BotResearchAllocation)
  if node.kind != JObject:
    errors.add("researchAllocation must be object or null")
    return none(BotResearchAllocation)
  var fields = initTable[string, int]()
  if "fields" in node:
    if node["fields"].kind != JObject:
      errors.add("researchAllocation.fields must be object")
    else:
      for key, value in node["fields"].pairs:
        if value.kind != JInt:
          errors.add("researchAllocation.fields." & key & " must be int")
        else:
          fields[key] = value.getInt()
  some(BotResearchAllocation(
    economic: parseOptionalInt(node, "economic", errors),
    science: parseOptionalInt(node, "science", errors),
    fields: fields
  ))

proc parseBotOrderDraft*(jsonText: string): BotOrderParseResult =
  var errors: seq[string] = @[]
  var root: JsonNode
  try:
    root = parseJson(jsonText)
  except CatchableError as e:
    return BotOrderParseResult(ok: false, errors: @["Invalid JSON: " & e.msg])

  if root.kind != JObject:
    return BotOrderParseResult(
      ok: false,
      errors: @["Top-level payload must be a JSON object"]
    )

  var draft = BotOrderDraft(
    turn: parseRequiredInt(root, "turn", errors),
    houseId: parseRequiredInt(root, "houseId", errors),
    fleetCommands: @[],
    buildCommands: @[],
    repairCommands: @[],
    scrapCommands: @[],
    zeroTurnCommands: @[],
    populationTransfers: @[],
    terraformCommands: @[],
    colonyManagement: @[],
    espionageActions: @[],
    diplomaticCommand: none(BotDiplomaticOrder),
    researchAllocation: none(BotResearchAllocation),
    ebpInvestment: parseOptionalInt(root, "ebpInvestment", errors),
    cipInvestment: parseOptionalInt(root, "cipInvestment", errors)
  )

  if "fleetCommands" in root:
    draft.fleetCommands = parseFleetCommands(root["fleetCommands"], errors)
  if "buildCommands" in root:
    draft.buildCommands = parseBuildCommands(root["buildCommands"], errors)
  if "repairCommands" in root:
    draft.repairCommands = parseRepairCommands(
      root["repairCommands"], errors)
  if "scrapCommands" in root:
    draft.scrapCommands = parseScrapCommands(root["scrapCommands"], errors)
  if "zeroTurnCommands" in root:
    draft.zeroTurnCommands = parseZeroTurnCommands(
      root["zeroTurnCommands"], errors)
  if "populationTransfers" in root:
    draft.populationTransfers = parsePopulationTransfers(
      root["populationTransfers"], errors)
  if "terraformCommands" in root:
    draft.terraformCommands = parseTerraformCommands(
      root["terraformCommands"], errors)
  if "colonyManagement" in root:
    draft.colonyManagement = parseColonyManagement(
      root["colonyManagement"], errors)
  if "espionageActions" in root:
    draft.espionageActions = parseEspionageActions(
      root["espionageActions"], errors)
  if "diplomaticCommand" in root:
    draft.diplomaticCommand = parseDiplomatic(
      root["diplomaticCommand"], errors)
  if "researchAllocation" in root:
    draft.researchAllocation = parseResearch(
      root["researchAllocation"], errors)

  BotOrderParseResult(
    ok: errors.len == 0,
    draft: draft,
    errors: errors
  )
