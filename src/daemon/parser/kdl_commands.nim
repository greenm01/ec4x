import kdl
import std/[strutils, options, tables, os]
import ../../engine/types/[command, core, fleet, production, tech, diplomacy,
  colony, espionage, ship, facilities, ground_unit, zero_turn]
import ../../common/logger

type
  KdlParseError* = object of CatchableError

# =============================================================================
# Type Parsing Helpers
# =============================================================================

proc parseId[T](val: KdlVal): T =
  ## Parse ID from KDL value, handling optional type annotation
  case val.kind
  of KInt, KInt8, KInt16, KInt32, KInt64, KUInt8, KUInt16, KUInt32, KUInt64:
    return T(val.kInt().uint32)
  of KString:
    # Some IDs might be strings in future, but distinct uint32 for now
    try:
      return T(parseInt(val.kString()).uint32)
    except ValueError:
      raise newException(KdlParseError, "Invalid ID format: " & val.kString())
  else:
    raise newException(KdlParseError, "ID must be integer or string, got " & $val.kind)

proc parseEnumFromStr[T: enum](s: string): T =
  try:
    # Try case-insensitive match
    for enumVal in T:
      if ($enumVal).toLowerAscii() == s.toLowerAscii().replace("-", ""):
        return enumVal
    return parseEnum[T](s) 
  except ValueError:
    raise newException(KdlParseError, "Invalid enum value: " & s)

proc getArg(node: KdlNode, index: int, name: string): KdlVal =
  if index < node.args.len:
    return node.args[index]
  raise newException(KdlParseError, "Missing argument '" & name & "' for node " & node.name)

proc getPropOrErr(node: KdlNode, key: string): KdlVal =
  if node.props.hasKey(key):
    return node.props[key]
  raise newException(KdlParseError, "Missing property '" & key & "' for node " & node.name)

# =============================================================================
# Command Parsers
# =============================================================================

proc parseFleetCommand(node: KdlNode): FleetCommand =
  # Syntax: fleet (FleetId)1 hold
  # OR: fleet (FleetId)1 { move to=... }
  
  let fleetId = parseId[FleetId](getArg(node, 0, "fleetId"))
  
  var cmdTypeStr = ""
  var paramsNode: Option[KdlNode] = none(KdlNode)
  
  if node.children.len > 0:
    # Command is child node: fleet 1 { move ... }
    # Assume first child is the command
    let child = node.children[0]
    cmdTypeStr = child.name
    paramsNode = some(child)
  elif node.args.len > 1:
    # Command is argument: fleet 1 hold
    if node.args[1].kind == KValKind.KString:
      cmdTypeStr = node.args[1].kString()
    else:
      raise newException(KdlParseError, "Command type must be string")
  else:
    raise newException(KdlParseError, "Fleet command missing action")

  let cmdType = parseEnumFromStr[FleetCommandType](cmdTypeStr)
  var cmd = FleetCommand(
    fleetId: fleetId,
    commandType: cmdType,
    priority: 0 # Default
  )
  
  # Parse params if present
  if paramsNode.isSome:
    let pNode = paramsNode.get()
    
    # Target System: to=(SystemId)15 or system=(SystemId)15 or at=(SystemId)15
    if pNode.props.hasKey("to"):
      cmd.targetSystem = some(parseId[SystemId](pNode.props["to"]))
    elif pNode.props.hasKey("system"):
      cmd.targetSystem = some(parseId[SystemId](pNode.props["system"]))
    elif pNode.props.hasKey("at"):
      cmd.targetSystem = some(parseId[SystemId](pNode.props["at"]))
      
    # Target Fleet: target=(FleetId)10
    if pNode.props.hasKey("target"):
      # Target could be HouseId (for diplomacy) or FleetId (for join)
      # For fleet commands, usually FleetId unless 'target' implies system?
      # Spec says: join-fleet target=(FleetId)10
      cmd.targetFleet = some(parseId[FleetId](pNode.props["target"]))
      
    # ROE
    if pNode.props.hasKey("roe"):
      cmd.roe = some(pNode.props["roe"].kInt().int32)
      
    # Priority
    if pNode.props.hasKey("priority"):
      cmd.priority = pNode.props["priority"].kInt().int32

  return cmd

proc parseBuildCommand(node: KdlNode, colonyId: ColonyId): seq[BuildCommand] =
  # Syntax: build (ColonyId)1 { ship corvette ... }
  # Returns a sequence because `build` block can contain multiple orders
  result = @[]
  
  for child in node.children:
    var cmd = BuildCommand(colonyId: colonyId, quantity: 1, industrialUnits: 0)
    
    # Infer BuildType from node name
    case child.name.toLowerAscii():
    of "ship":
      cmd.buildType = BuildType.Ship
      if child.args.len > 0:
        cmd.shipClass = some(parseEnumFromStr[ShipClass](child.args[0].kString()))
      else:
        raise newException(KdlParseError, "Ship build command missing class")
    of "facility":
      cmd.buildType = BuildType.Facility
      if child.args.len > 0:
        cmd.facilityClass = some(parseEnumFromStr[FacilityClass](child.args[0].kString()))
      else:
        raise newException(KdlParseError, "Facility build command missing class")
    of "ground":
      cmd.buildType = BuildType.Ground
      if child.args.len > 0:
        cmd.groundClass = some(parseEnumFromStr[GroundClass](child.args[0].kString()))
      else:
        raise newException(KdlParseError, "Ground unit build command missing class")
    of "industrial":
      cmd.buildType = BuildType.Industrial
      if child.props.hasKey("units"):
        cmd.industrialUnits = child.props["units"].kInt().int32
      else:
        # Default to quantity if units not specified? Spec says units=10
        cmd.industrialUnits = 1
    else:
      # Unknown build type
      continue

    # Common params
    if child.props.hasKey("quantity"):
      cmd.quantity = child.props["quantity"].kInt().int32
      
    result.add(cmd)

proc parseScrapCommand(node: KdlNode, colonyId: ColonyId): seq[ScrapCommand] =
  # Syntax: scrap (ColonyId)1 { ship (ShipId)99 ... }
  result = @[]
  for child in node.children:
    var targetType: ScrapTargetType
    var targetId: uint32
    
    case child.name.toLowerAscii():
    of "ship": targetType = ScrapTargetType.Ship
    of "ground-unit": targetType = ScrapTargetType.GroundUnit
    of "neoria": targetType = ScrapTargetType.Neoria
    of "kastra": targetType = ScrapTargetType.Kastra
    else: continue
    
    if child.args.len > 0:
      targetId = parseId[uint32](child.args[0])
    else:
      raise newException(KdlParseError, "Scrap command missing ID")
      
    let ack = if child.props.hasKey("acknowledge-queue-loss"): 
                child.props["acknowledge-queue-loss"].kBool()
              else: false
              
    result.add(ScrapCommand(
      colonyId: colonyId,
      targetType: targetType,
      targetId: targetId,
      acknowledgeQueueLoss: ack
    ))

proc parseColonyManagement(node: KdlNode, colonyId: ColonyId): ColonyManagementCommand =
  # Syntax: colony (ColonyId)1 { tax-rate 60 ... }
  var cmd = ColonyManagementCommand(
    colonyId: colonyId,
    autoRepair: false,
    autoLoadFighters: false,
    autoLoadMarines: false
  )
  
  for child in node.children:
    case child.name.toLowerAscii():
    of "tax-rate":
      if child.args.len > 0:
        cmd.taxRate = some(child.args[0].kInt().int32)
    of "auto-repair":
      if child.args.len > 0:
        cmd.autoRepair = child.args[0].kBool()
    of "auto-load-fighters":
      if child.args.len > 0:
        cmd.autoLoadFighters = child.args[0].kBool()
    of "auto-load-marines":
      if child.args.len > 0:
        cmd.autoLoadMarines = child.args[0].kBool()
        
  return cmd

proc parseResearch(node: KdlNode): ResearchAllocation =
  # Syntax: research { economic 100 ... tech { wep 40 } }
  # ResearchAllocation structure: economic, science, technology (Table)
  result = ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int32]()
  )
  
  for child in node.children:
    case child.name.toLowerAscii():
    of "economic":
      result.economic = child.args[0].kInt().int32
    of "science":
      result.science = child.args[0].kInt().int32
    of "tech":
      for techNode in child.children:
        let field = parseEnumFromStr[TechField](techNode.name)
        let amount = techNode.args[0].kInt().int32
        result.technology[field] = amount

proc parseDiplomacy(node: KdlNode): seq[DiplomaticCommand] =
  # Syntax: diplomacy { declare-hostile target=(HouseId)3 ... }
  result = @[]
  for child in node.children:
    var cmd = DiplomaticCommand()
    
    # Map KDL action to DiplomaticActionType enum
    # KDL: declare-hostile -> Enum: DeclareHostile
    cmd.actionType = parseEnumFromStr[DiplomaticActionType](child.name)
    
    if child.props.hasKey("target"):
      cmd.targetHouse = parseId[HouseId](child.props["target"])
      
    if child.props.hasKey("id"): # Proposal ID
      cmd.proposalId = some(parseId[ProposalId](child.props["id"]))
      
    # Handle 'to' for propose-deescalate
    # to=neutral -> ProposalType (e.g. DeescalateToNeutral)
    if child.props.hasKey("to"):
      let toState = child.props["to"].kString().toLowerAscii()
      if toState == "neutral":
        cmd.proposalType = some(ProposalType.DeescalateToNeutral)
      elif toState == "hostile":
        cmd.proposalType = some(ProposalType.DeescalateToHostile)
        
    result.add(cmd)

proc parseEspionage(node: KdlNode): tuple[ebp: int32, cip: int32, actions: seq[EspionageAttempt]] =
  # Syntax: espionage { invest ebp=200 cip=80; tech-theft target=... }
  result.ebp = 0
  result.cip = 0
  result.actions = @[]
  
  for child in node.children:
    if child.name == "invest":
      if child.props.hasKey("ebp"): result.ebp = child.props["ebp"].kInt().int32
      if child.props.hasKey("cip"): result.cip = child.props["cip"].kInt().int32
    else:
      # Operations
      var attempt = EspionageAttempt()
      attempt.action = parseEnumFromStr[EspionageAction](child.name)
      
      if child.props.hasKey("target"):
        attempt.target = parseId[HouseId](child.props["target"])
        
      if child.props.hasKey("system"):
        attempt.targetSystem = some(parseId[SystemId](child.props["system"]))
        
      result.actions.add(attempt)

proc parseTransfer(node: KdlNode): PopulationTransferCommand =
  # Syntax: transfer from=(ColonyId)1 to=(ColonyId)2 ptu=50
  var cmd = PopulationTransferCommand()
  if node.props.hasKey("from"): cmd.sourceColony = parseId[ColonyId](node.props["from"])
  if node.props.hasKey("to"): cmd.destColony = parseId[ColonyId](node.props["to"])
  if node.props.hasKey("ptu"): cmd.ptuAmount = node.props["ptu"].kInt().int32
  return cmd

proc parseTerraform(node: KdlNode): TerraformCommand =
  # Syntax: terraform colony=(ColonyId)3
  var cmd = TerraformCommand()
  if node.props.hasKey("colony"): cmd.colonyId = parseId[ColonyId](node.props["colony"])
  return cmd

proc parseZeroTurnCommands(
    node: KdlNode, houseId: HouseId
): seq[ZeroTurnCommand] =
  ## Parse a zero-turn block into a sequence of ZeroTurnCommands.
  ##
  ## Syntax:
  ##   zero-turn {
  ##     detach-ships source=(FleetId)4 new-fleet=(FleetId)999 {
  ##       ship (ShipId)10
  ##       ship (ShipId)14
  ##     }
  ##     transfer-ships source=(FleetId)4 target=(FleetId)7 {
  ##       ship (ShipId)12
  ##     }
  ##     merge-fleets source=(FleetId)3 target=(FleetId)4
  ##     reactivate source=(FleetId)5
  ##     load-cargo source=(FleetId)4 cargo="marines" quantity=10
  ##     unload-cargo source=(FleetId)4
  ##     load-fighters source=(FleetId)4 carrier=(ShipId)50 {
  ##       fighter (ShipId)60
  ##     }
  ##     unload-fighters source=(FleetId)4 carrier=(ShipId)50 {
  ##       fighter (ShipId)60
  ##     }
  ##     transfer-fighters source=(FleetId)4 \
  ##         source-carrier=(ShipId)50 target-carrier=(ShipId)55 {
  ##       fighter (ShipId)60
  ##     }
  ##   }
  result = @[]
  for child in node.children:
    let cmdType = parseEnumFromStr[ZeroTurnCommandType](child.name)
    var cmd = ZeroTurnCommand(
      houseId: houseId,
      commandType: cmdType,
      colonySystem: none(SystemId),
      sourceFleetId: none(FleetId),
      targetFleetId: none(FleetId),
      shipIndices: @[],
      shipIds: @[],
      cargoType: none(CargoClass),
      cargoQuantity: none(int),
      fighterIds: @[],
      carrierShipId: none(ShipId),
      sourceCarrierShipId: none(ShipId),
      targetCarrierShipId: none(ShipId),
      newFleetId: none(FleetId)
    )

    # Fleet ID properties
    if child.props.hasKey("source"):
      cmd.sourceFleetId = some(parseId[FleetId](child.props["source"]))
    if child.props.hasKey("target"):
      cmd.targetFleetId = some(parseId[FleetId](child.props["target"]))
    if child.props.hasKey("new-fleet"):
      cmd.newFleetId = some(parseId[FleetId](child.props["new-fleet"]))

    # Carrier properties (fighter operations)
    if child.props.hasKey("carrier"):
      cmd.carrierShipId = some(parseId[ShipId](child.props["carrier"]))
    if child.props.hasKey("source-carrier"):
      cmd.sourceCarrierShipId =
        some(parseId[ShipId](child.props["source-carrier"]))
    if child.props.hasKey("target-carrier"):
      cmd.targetCarrierShipId =
        some(parseId[ShipId](child.props["target-carrier"]))

    # Cargo properties
    if child.props.hasKey("cargo"):
      let cargoStr = child.props["cargo"].kString()
      cmd.cargoType = some(parseEnumFromStr[CargoClass](cargoStr))
    if child.props.hasKey("quantity"):
      cmd.cargoQuantity = some(child.props["quantity"].kInt().int)

    # Child nodes: ship (ShipId)N → shipIds, fighter (ShipId)N → fighterIds
    for sub in child.children:
      case sub.name.toLowerAscii()
      of "ship":
        if sub.args.len > 0:
          cmd.shipIds.add(parseId[ShipId](sub.args[0]))
        else:
          raise newException(
            KdlParseError, "zero-turn ship node missing ID"
          )
      of "fighter":
        if sub.args.len > 0:
          cmd.fighterIds.add(parseId[ShipId](sub.args[0]))
        else:
          raise newException(
            KdlParseError, "zero-turn fighter node missing ID"
          )
      else:
        logWarn("Parser", "Unknown zero-turn sub-node: " & sub.name)

    result.add(cmd)

# =============================================================================
# Main Parser
# =============================================================================

proc parseOrdersKdl*(doc: KdlDoc): CommandPacket =
  ## Parse a KDL document into a CommandPacket
  
  # 1. Validate Root Node
  if doc.len == 0 or doc[0].name != "orders":
    raise newException(KdlParseError, "Root node must be 'orders'")
    
  let root = doc[0]
  
  # 2. Extract Header (House & Turn)
  let houseId = parseId[HouseId](getPropOrErr(root, "house"))
  let turn = getPropOrErr(root, "turn").kInt().int32
  
  # 3. Initialize Packet
  var packet = CommandPacket(
    houseId: houseId,
    turn: turn,
    zeroTurnCommands: @[],
    fleetCommands: @[],
    buildCommands: @[],
    repairCommands: @[],
    scrapCommands: @[],
    researchAllocation: ResearchAllocation(),
    diplomaticCommand: @[],
    populationTransfers: @[],
    terraformCommands: @[],
    colonyManagement: @[],
    espionageActions: @[],
    ebpInvestment: 0,
    cipInvestment: 0
  )
  
  # 4. Iterate Children
  for node in root.children:
    case node.name.toLowerAscii():
    of "fleet":
      packet.fleetCommands.add(parseFleetCommand(node))
    of "build":
      # Build node: build (ColonyId)1 { ... }
      if node.args.len > 0:
        let colonyId = parseId[ColonyId](node.args[0])
        packet.buildCommands.add(parseBuildCommand(node, colonyId))
    of "repair":
      # repair (ColonyId)1 { ... }
      # Implementation logic similar to build/scrap
      discard
    of "scrap":
      if node.args.len > 0:
        let colonyId = parseId[ColonyId](node.args[0])
        packet.scrapCommands.add(parseScrapCommand(node, colonyId))
    of "colony":
      if node.args.len > 0:
        let colonyId = parseId[ColonyId](node.args[0])
        packet.colonyManagement.add(parseColonyManagement(node, colonyId))
    of "research":
      packet.researchAllocation = parseResearch(node)
    of "diplomacy":
      packet.diplomaticCommand.add(parseDiplomacy(node))
    of "espionage":
      let (ebp, cip, actions) = parseEspionage(node)
      packet.ebpInvestment = ebp
      packet.cipInvestment = cip
      packet.espionageActions.add(actions)
    of "transfer":
      packet.populationTransfers.add(parseTransfer(node))
    of "terraform":
      packet.terraformCommands.add(parseTerraform(node))
    of "zero-turn":
      packet.zeroTurnCommands.add(
        parseZeroTurnCommands(node, houseId)
      )
    else:
      logWarn("Parser", "Unknown order node: " & node.name)
      
  return packet

proc parseOrdersFile*(path: string): CommandPacket =
  ## Parse orders from a KDL file
  if not fileExists(path):
    raise newException(IOError, "File not found: " & path)
    
  try:
    let content = readFile(path)
    let doc = parseKdl(content)
    return parseOrdersKdl(doc)
  except CatchableError as e:
    raise newException(KdlParseError, "Failed to parse KDL file: " & e.msg)

proc parseOrdersString*(content: string): CommandPacket =
  ## Parse orders from a KDL string
  try:
    let doc = parseKdl(content)
    return parseOrdersKdl(doc)
  except CatchableError as e:
    raise newException(KdlParseError, "Failed to parse KDL content: " & e.msg)
