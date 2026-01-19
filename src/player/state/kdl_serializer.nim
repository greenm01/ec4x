import std/[options, strformat, strutils, tables]
import ../../engine/types/[command, core, fleet, production]

proc fleetCommandName(cmdType: FleetCommandType): string =
  case cmdType
  of FleetCommandType.Hold: "hold"
  of FleetCommandType.Move: "move"
  of FleetCommandType.SeekHome: "seek-home"
  of FleetCommandType.Patrol: "patrol"
  of FleetCommandType.GuardStarbase: "guard-starbase"
  of FleetCommandType.GuardColony: "guard-colony"
  of FleetCommandType.Blockade: "blockade"
  of FleetCommandType.Bombard: "bombard"
  of FleetCommandType.Invade: "invade"
  of FleetCommandType.Blitz: "blitz"
  of FleetCommandType.Colonize: "colonize"
  of FleetCommandType.ScoutColony: "scout-colony"
  of FleetCommandType.ScoutSystem: "scout-system"
  of FleetCommandType.HackStarbase: "hack-starbase"
  of FleetCommandType.JoinFleet: "join-fleet"
  of FleetCommandType.Rendezvous: "rendezvous"
  of FleetCommandType.Salvage: "salvage"
  of FleetCommandType.Reserve: "reserve"
  of FleetCommandType.Mothball: "mothball"
  of FleetCommandType.View: "view"

proc hasFleetParams(cmd: FleetCommand): bool =
  cmd.targetSystem.isSome or cmd.targetFleet.isSome or cmd.roe.isSome or
    cmd.priority != 0

proc fleetCommandLine(cmd: FleetCommand): string =
  var parts = @[fleetCommandName(cmd.commandType)]
  if cmd.targetSystem.isSome:
    parts.add(fmt"to=(SystemId){cmd.targetSystem.get()}")
  if cmd.targetFleet.isSome:
    parts.add(fmt"target=(FleetId){cmd.targetFleet.get()}")
  if cmd.roe.isSome:
    parts.add(fmt"roe={cmd.roe.get()}")
  if cmd.priority != 0:
    parts.add(fmt"priority={cmd.priority}")
  parts.join(" ")

proc buildCommandLine(cmd: BuildCommand): Option[string] =
  var parts: seq[string] = @[]
  case cmd.buildType
  of BuildType.Ship:
    if cmd.shipClass.isNone:
      return none(string)
    parts.add("ship")
    parts.add($cmd.shipClass.get())
  of BuildType.Facility:
    if cmd.facilityClass.isNone:
      return none(string)
    parts.add("facility")
    parts.add($cmd.facilityClass.get())
  of BuildType.Ground:
    if cmd.groundClass.isNone:
      return none(string)
    parts.add("ground")
    parts.add($cmd.groundClass.get())
  of BuildType.Industrial:
    parts.add("industrial")
    parts.add(fmt"units={cmd.industrialUnits}")
  of BuildType.Infrastructure:
    return none(string)

  if cmd.quantity != 1:
    parts.add(fmt"quantity={cmd.quantity}")

  some(parts.join(" "))

proc groupBuildCommandsByColony(
    commands: seq[BuildCommand]): Table[ColonyId, seq[BuildCommand]] =
  result = initTable[ColonyId, seq[BuildCommand]]()
  for cmd in commands:
    if not result.hasKey(cmd.colonyId):
      result[cmd.colonyId] = @[]
    result[cmd.colonyId].add(cmd)

proc commandPacketToKdl*(packet: CommandPacket): string =
  var lines: seq[string] = @[]
  lines.add(
    fmt"orders turn={packet.turn} house=(HouseId){packet.houseId} {{")

  for cmd in packet.fleetCommands:
    if hasFleetParams(cmd):
      lines.add(fmt"  fleet (FleetId){cmd.fleetId} {{")
      lines.add("    " & fleetCommandLine(cmd))
      lines.add("  }")
    else:
      lines.add(
        fmt"  fleet (FleetId){cmd.fleetId} {fleetCommandName(cmd.commandType)}")

  let buildGroups = groupBuildCommandsByColony(packet.buildCommands)
  for colonyId, commands in buildGroups.pairs:
    if commands.len == 0:
      continue
    lines.add(fmt"  build (ColonyId){colonyId} {{")
    for cmd in commands:
      let lineOpt = buildCommandLine(cmd)
      if lineOpt.isSome:
        lines.add("    " & lineOpt.get())
    lines.add("  }")

  lines.add("}")
  lines.join("\n")
