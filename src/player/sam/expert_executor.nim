## Executes ExpertCommand AST by modifying TUI model state

import std/[strutils, options, parseutils, tables]
import ./tui_model
import ./expert_parser
import ../../engine/types/[core, fleet, production, ship, facilities, ground_unit]

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
    
  else:
    return (false, "Command execution not fully implemented yet: " & $cmd.kind)
