## Executes ExpertCommand AST by modifying TUI model state

import std/[strutils, options, parseutils, tables]
import ./tui_model
import ./expert_parser
import ../../engine/types/[core, fleet, production, ship, facilities, ground_unit, command, diplomacy, espionage, tech]

proc findFleetId*(model: TuiModel, nameOrId: string): Option[int] =
  let q = nameOrId.toLowerAscii().strip(chars = {'"'})
  var id: int
  if parseInt(q, id) > 0 and model.view.ownFleetsById.hasKey(id):
    return some(id)
  for f in model.view.fleets:
    if f.owner == model.view.viewingHouse and f.name.toLowerAscii() == q:
      return some(f.id)
  none(int)

proc findSystemId*(model: TuiModel, nameOrId: string): Option[int] =
  let q = nameOrId.toLowerAscii().strip(chars = {'"'})
  var id: int
  if parseInt(q, id) > 0:
    for coord, sys in model.view.systems.pairs:
      if sys.id == id: return some(id)
  for coord, sys in model.view.systems.pairs:
    if sys.name.toLowerAscii() == q:
      return some(sys.id)
  none(int)

proc findColonyId*(model: TuiModel, nameOrId: string): Option[int] =
  let q = nameOrId.toLowerAscii().strip(chars = {'"'})
  var id: int
  if parseInt(q, id) > 0:
    for c in model.view.colonies:
      if c.colonyId == id and c.owner == model.view.viewingHouse: return some(id)
  for c in model.view.colonies:
    if c.systemName.toLowerAscii() == q and c.owner == model.view.viewingHouse:
      return some(c.colonyId)
  none(int)

proc findHouseId*(model: TuiModel, nameOrId: string): Option[int] =
  let q = nameOrId.toLowerAscii().strip(chars = {'"'})
  var id: int
  if parseInt(q, id) > 0:
    if model.view.houseNames.hasKey(id): return some(id)
  for hId, name in model.view.houseNames.pairs:
    if name.toLowerAscii() == q: return some(hId)
  none(int)

proc parseShipClass(s: string): Option[ShipClass] =
  let lower = s.toLowerAscii()
  case lower
  of "corvette": some(ShipClass.Corvette)
  of "frigate": some(ShipClass.Frigate)
  of "destroyer": some(ShipClass.Destroyer)
  of "lightcruiser", "light-cruiser", "light_cruiser": some(ShipClass.LightCruiser)
  of "cruiser": some(ShipClass.Cruiser)
  of "battlecruiser", "battle-cruiser", "battle_cruiser": some(ShipClass.Battlecruiser)
  of "battleship": some(ShipClass.Battleship)
  of "dreadnought": some(ShipClass.Dreadnought)
  of "superdreadnought", "super-dreadnought", "super_dreadnought": some(ShipClass.SuperDreadnought)
  of "carrier": some(ShipClass.Carrier)
  of "supercarrier", "super-carrier", "super_carrier": some(ShipClass.SuperCarrier)
  of "raider": some(ShipClass.Raider)
  of "scout": some(ShipClass.Scout)
  of "etac": some(ShipClass.ETAC)
  of "trooptransport", "troop-transport", "troop_transport": some(ShipClass.TroopTransport)
  of "fighter": some(ShipClass.Fighter)
  of "planetbreaker", "planet-breaker", "planet_breaker": some(ShipClass.PlanetBreaker)
  else: none(ShipClass)

proc parseFacilityType(s: string): Option[FacilityClass] =
  let lower = s.toLowerAscii()
  case lower
  of "shipyard": some(FacilityClass.Shipyard)
  of "spaceport": some(FacilityClass.Spaceport)
  of "drydock": some(FacilityClass.Drydock)
  else: none(FacilityClass)

proc getColonyMgmtIdx(model: TuiModel, colonyId: int): int =
  for i in 0 ..< model.ui.stagedColonyManagement.len:
    if int(model.ui.stagedColonyManagement[i].colonyId) == colonyId:
      return i
  return -1

proc executeExpertCommand*(model: var TuiModel, cmd: ExpertCommand): tuple[success: bool, message: string] =
  case cmd.kind
  of ExpertCommandKind.FleetMove:
    let fId = findFleetId(model, cmd.fleetId)
    if fId.isNone: return (false, "Fleet not found: " & cmd.fleetId)
    let sId = findSystemId(model, cmd.targetSystem)
    if sId.isNone: return (false, "System not found: " & cmd.targetSystem)
    
    let fCmd = FleetCommand(
      fleetId: FleetId(fId.get()),
      commandType: FleetCommandType.Move,
      targetSystem: some(SystemId(sId.get())),
      targetFleet: none(FleetId),
      priority: 1,
      roe: none(int32)
    )
    model.stageFleetCommand(fCmd)
    model.ui.modifiedSinceSubmit = true
    return (true, "Moved fleet to " & cmd.targetSystem)
    
  of ExpertCommandKind.FleetHold:
    let fId = findFleetId(model, cmd.holdFleetId)
    if fId.isNone: return (false, "Fleet not found: " & cmd.holdFleetId)
    let fCmd = FleetCommand(
      fleetId: FleetId(fId.get()),
      commandType: FleetCommandType.Hold,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 1,
      roe: none(int32)
    )
    model.stageFleetCommand(fCmd)
    model.ui.modifiedSinceSubmit = true
    return (true, "Fleet holding")
    
  of ExpertCommandKind.FleetRoe:
    let fId = findFleetId(model, cmd.roeFleetId)
    if fId.isNone: return (false, "Fleet not found: " & cmd.roeFleetId)
    if cmd.roeLevel < 0 or cmd.roeLevel > 10: return (false, "ROE must be 0-10")
    
    var existing = if model.ui.stagedFleetCommands.hasKey(fId.get()):
      model.ui.stagedFleetCommands[fId.get()]
    else:
      FleetCommand(
        fleetId: FleetId(fId.get()),
        commandType: FleetCommandType.Hold,
        priority: 1
      )
    existing.roe = some(int32(cmd.roeLevel))
    model.stageFleetCommand(existing)
    model.ui.modifiedSinceSubmit = true
    return (true, "Set ROE to " & $cmd.roeLevel)

  of ExpertCommandKind.FleetSplit:
    return (false, "ZTC split not implemented yet in executor")

  of ExpertCommandKind.FleetMerge:
    return (false, "ZTC merge not implemented yet in executor")

  of ExpertCommandKind.FleetLoad:
    return (false, "ZTC load not implemented yet in executor")

  of ExpertCommandKind.FleetStatus:
    let fId = findFleetId(model, cmd.statusFleetId)
    if fId.isNone: return (false, "Fleet not found: " & cmd.statusFleetId)
    let state = cmd.statusState.toLowerAscii()
    let cmdType = case state
      of "reserve": FleetCommandType.Reserve
      of "mothball": FleetCommandType.Mothball
      of "active", "hold": FleetCommandType.Hold
      else: return (false, "Unknown status: " & state)
    
    var existing = if model.ui.stagedFleetCommands.hasKey(fId.get()):
      model.ui.stagedFleetCommands[fId.get()]
    else:
      FleetCommand(fleetId: FleetId(fId.get()), priority: 1)
    
    existing.commandType = cmdType
    model.stageFleetCommand(existing)
    model.ui.modifiedSinceSubmit = true
    return (true, "Set fleet status to " & state)

  of ExpertCommandKind.ColonyBuild:
    let cId = findColonyId(model, cmd.buildColony)
    if cId.isNone: return (false, "Colony not found: " & cmd.buildColony)
    
    let shipOpt = parseShipClass(cmd.buildItem)
    if shipOpt.isSome:
      model.ui.stagedBuildCommands.add(BuildCommand(
        colonyId: ColonyId(cId.get()),
        buildType: BuildType.Ship,
        quantity: int32(cmd.buildQty),
        shipClass: shipOpt,
        facilityClass: none(FacilityClass),
        groundClass: none(GroundClass),
        industrialUnits: 0
      ))
      model.ui.modifiedSinceSubmit = true
      return (true, "Staged build for " & $cmd.buildQty & " " & cmd.buildItem)
      
    let facOpt = parseFacilityType(cmd.buildItem)
    if facOpt.isSome:
      model.ui.stagedBuildCommands.add(BuildCommand(
        colonyId: ColonyId(cId.get()),
        buildType: BuildType.Facility,
        quantity: int32(cmd.buildQty),
        shipClass: none(ShipClass),
        facilityClass: facOpt,
        groundClass: none(GroundClass),
        industrialUnits: 0
      ))
      model.ui.modifiedSinceSubmit = true
      return (true, "Staged build for " & $cmd.buildQty & " " & cmd.buildItem)
      
    return (false, "Unknown build item: " & cmd.buildItem)

  of ExpertCommandKind.ColonyQrm:
    let cId = findColonyId(model, cmd.qrmColony)
    if cId.isNone: return (false, "Colony not found: " & cmd.qrmColony)
    model.ui.stagedScrapCommands.add(ScrapCommand(
      colonyId: ColonyId(cId.get()),
      targetType: ScrapTargetType.Neoria, # Placeholder, qrm implies queue item in parser
      targetId: uint32(cmd.qrmIndex),
      acknowledgeQueueLoss: true
    ))
    model.ui.modifiedSinceSubmit = true
    return (true, "Staged queue removal")

  of ExpertCommandKind.ColonyQup:
    return (false, "qup command not supported by engine yet")

  of ExpertCommandKind.ColonyAuto:
    let cId = findColonyId(model, cmd.autoColony)
    if cId.isNone: return (false, "Colony not found: " & cmd.autoColony)
    let sys = cmd.autoSystem.toLowerAscii()
    let state = cmd.autoState.toLowerAscii() == "on"
    
    let idx = model.getColonyMgmtIdx(cId.get())
    if idx == -1:
      model.ui.stagedColonyManagement.add(ColonyManagementCommand(
        colonyId: ColonyId(cId.get()),
        autoRepair: false, autoLoadFighters: false, autoLoadMarines: false
      ))
    
    let finalIdx = if idx == -1: model.ui.stagedColonyManagement.len - 1 else: idx
    case sys
    of "rep", "repair": model.ui.stagedColonyManagement[finalIdx].autoRepair = state
    of "fig", "fighter": model.ui.stagedColonyManagement[finalIdx].autoLoadFighters = state
    of "mar", "marine":
      model.ui.stagedColonyManagement[finalIdx].autoLoadMarines = state
    else: return (false, "Unknown auto system: " & sys)

    model.ui.modifiedSinceSubmit = true
    return (true, "Set " & sys & " auto to " & (if state: "on" else: "off"))

  of ExpertCommandKind.TechAlloc:
    let field = cmd.allocField.toLowerAscii()
    case field
    of "eco": model.ui.researchAllocation.economic = int32(cmd.allocAmount)
    of "sci": model.ui.researchAllocation.science = int32(cmd.allocAmount)
    else:
      var matched = false
      for f in TechField:
        if ($f).toLowerAscii().contains(field):
          model.ui.researchAllocation.technology[f] = int32(cmd.allocAmount)
          matched = true
          break
      if not matched: return (false, "Unknown tech field: " & field)
      
    model.ui.modifiedSinceSubmit = true
    return (true, "Allocated " & $cmd.allocAmount & " PP to " & field)

  of ExpertCommandKind.TechClear:
    model.ui.researchAllocation.economic = 0
    model.ui.researchAllocation.science = 0
    model.ui.researchAllocation.technology.clear()
    model.ui.modifiedSinceSubmit = true
    return (true, "Cleared research allocations")

  of ExpertCommandKind.SpyBudget:
    let bType = cmd.budgetType.toLowerAscii()
    if bType == "ebp":
      model.ui.stagedEbpInvestment = int32(cmd.budgetAmount)
    elif bType == "cip":
      model.ui.stagedCipInvestment = int32(cmd.budgetAmount)
    else:
      return (false, "Usage: :s <ebp|cip> budget <amount>")
      
    model.ui.modifiedSinceSubmit = true
    return (true, "Set " & bType & " budget to " & $cmd.budgetAmount)

  of ExpertCommandKind.SpyOp:
    let hId = findHouseId(model, cmd.opHouse)
    if hId.isNone: return (false, "House not found: " & cmd.opHouse)
    
    var opType: EspionageAction
    var foundOp = false
    for op in EspionageAction:
      if ($op).toLowerAscii().contains(cmd.opType.toLowerAscii()):
        opType = op
        foundOp = true
        break
    if not foundOp: return (false, "Unknown operation: " & cmd.opType)
    
    model.ui.stagedEspionageActions.add(EspionageAttempt(
      attacker: HouseId(model.view.viewingHouse),
      target: HouseId(hId.get()),
      action: opType
    ))
    model.ui.modifiedSinceSubmit = true
    return (true, "Staged " & $opType & " against house " & $hId.get())

  of ExpertCommandKind.SpyClear:
    model.ui.stagedEbpInvestment = 0
    model.ui.stagedCipInvestment = 0
    model.ui.stagedEspionageActions.setLen(0)
    model.ui.modifiedSinceSubmit = true
    return (true, "Cleared espionage budget and operations")

  of ExpertCommandKind.GovTax:
    if cmd.taxRate < 0 or cmd.taxRate > 100: return (false, "Tax rate must be 0-100")
    model.ui.stagedTaxRate = some(cmd.taxRate)
    for i in 0 ..< model.ui.stagedColonyManagement.len:
      model.ui.stagedColonyManagement[i].taxRate = some(int32(cmd.taxRate))
    
    model.ui.modifiedSinceSubmit = true
    return (true, "Set empire tax rate to " & $cmd.taxRate & "%")

  of ExpertCommandKind.GovDip:
    let hId = findHouseId(model, cmd.dipHouse)
    if hId.isNone: return (false, "House not found: " & cmd.dipHouse)
    let stance = cmd.dipStance.toLowerAscii()
    
    let actionType = case stance
      of "neutral": DiplomaticActionType.SetNeutral
      of "hostile": DiplomaticActionType.DeclareHostile
      of "enemy": DiplomaticActionType.DeclareEnemy
      else: return (false, "Unknown stance: " & stance)
    
    model.ui.stagedDiplomaticCommands.add(DiplomaticCommand(
      houseId: HouseId(model.view.viewingHouse),
      targetHouse: HouseId(hId.get()),
      actionType: actionType
    ))
    model.ui.modifiedSinceSubmit = true
    return (true, "Staged diplomatic stance change to " & stance)

  of ExpertCommandKind.MapExport:
    model.ui.exportMapRequested = true
    return (true, "Exporting starmap...")

  of ExpertCommandKind.MapNote:
    let sId = findSystemId(model, cmd.noteSystem)
    if sId.isNone: return (false, "System not found: " & cmd.noteSystem)
    model.ui.intelNoteSaveRequested = true
    model.ui.intelNoteSaveSystemId = sId.get()
    model.ui.intelNoteSaveText = cmd.noteText
    return (true, "Saving note for " & cmd.noteSystem)

  of ExpertCommandKind.MetaClear, ExpertCommandKind.MetaList, ExpertCommandKind.MetaSubmit, ExpertCommandKind.MetaHelp, ExpertCommandKind.MetaDrop, ExpertCommandKind.ParseError:
    return (false, "Meta commands and errors should be handled in the acceptor")
