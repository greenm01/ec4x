## Expert Mode Command Parser
##
## Parses expert mode commands into staged commands.
## Commands follow the format:
##   :move fleet 1 to 5 roe 8
##   :01 fleet 1 to 5 roe 8
##   :hold fleet 2
##   :00 fleet 2
##   :patrol fleet 3
##   :03 fleet 3
##   :build colony 1 ship Destroyer quantity 2
##   :clear - Clear all staged commands
##   :list - Show staged command summary
##   :drop 2 - Remove staged command by index
##   :submit - Submit turn immediately (bypass confirmation)
##
## Reference: AGENTS.md and KDL serializer for command structure

import std/[strutils, options, parseutils]
import ../../engine/types/[core, fleet, production, ship, facilities, ground_unit]

# =============================================================================
# Parser Result Types
# =============================================================================

type
  MetaCommandType* {.pure.} = enum
    None
    Clear          ## Clear all staged commands
    List           ## List all staged commands
    Submit         ## Submit turn (same as Ctrl+E)
    Help           ## Show available commands
    Drop           ## Drop staged command by index

  ParseResult* = object
    ## Result of parsing a command
    success*: bool
    error*: string
    fleetCommand*: Option[FleetCommand]
    buildCommand*: Option[BuildCommand]
    metaCommand*: MetaCommandType = MetaCommandType.None
    metaIndex*: Option[int] = none(int)

# =============================================================================
# Helper Procs
# =============================================================================

proc normalizeCommandToken(token: string): string =
  ## Normalize command token to a canonical name
  let lower = token.toLowerAscii()
  case lower
  of "00": "hold"
  of "01": "move"
  of "02": "seek"
  of "03": "patrol"
  of "04": "guard-starbase"
  of "05": "guard"
  of "06": "blockade"
  of "07": "bombard"
  of "08": "invade"
  of "09": "blitz"
  of "10": "colonize"
  of "11": "scout-colony"
  of "12": "scout-system"
  of "13": "hack"
  of "14": "join"
  of "15": "rendezvous"
  of "16": "salvage"
  of "17": "reserve"
  of "18": "mothball"
  of "19": "view"
  of "m": "move"
  of "h": "hold"
  of "p": "patrol"
  of "b": "build"
  of "ls": "list"
  of "rm": "drop"
  else: lower

proc parseShipClass(s: string): Option[ShipClass] =
  ## Parse ship class name (case-insensitive)
  let lower = s.toLowerAscii()
  case lower
  of "corvette": some(ShipClass.Corvette)
  of "frigate": some(ShipClass.Frigate)
  of "destroyer": some(ShipClass.Destroyer)
  of "lightcruiser", "light-cruiser", "light_cruiser": 
    some(ShipClass.LightCruiser)
  of "cruiser": some(ShipClass.Cruiser)
  of "battlecruiser", "battle-cruiser", "battle_cruiser": 
    some(ShipClass.Battlecruiser)
  of "battleship": some(ShipClass.Battleship)
  of "dreadnought": some(ShipClass.Dreadnought)
  of "superdreadnought", "super-dreadnought", "super_dreadnought": 
    some(ShipClass.SuperDreadnought)
  of "carrier": some(ShipClass.Carrier)
  of "supercarrier", "super-carrier", "super_carrier": 
    some(ShipClass.SuperCarrier)
  of "raider": some(ShipClass.Raider)
  of "scout": some(ShipClass.Scout)
  of "etac": some(ShipClass.ETAC)
  of "trooptransport", "troop-transport", "troop_transport": 
    some(ShipClass.TroopTransport)
  of "fighter": some(ShipClass.Fighter)
  of "planetbreaker", "planet-breaker", "planet_breaker": 
    some(ShipClass.PlanetBreaker)
  else: none(ShipClass)

proc parseFacilityType(s: string): Option[NeoriaClass] =
  ## Parse facility type name (case-insensitive)
  let lower = s.toLowerAscii()
  case lower
  of "shipyard": some(NeoriaClass.Shipyard)
  of "spaceport": some(NeoriaClass.Spaceport)
  of "drydock": some(NeoriaClass.Drydock)
  else: none(NeoriaClass)

# =============================================================================
# Fleet Command Parsers
# =============================================================================

proc parseFleetMove(tokens: seq[string]): ParseResult =
  ## Parse: move fleet <id> to <systemId> [roe <value>] [priority <value>]
  if tokens.len < 5:
    return ParseResult(
      success: false,
      error: "Usage: :move fleet <id> to <system> [roe <value>]"
    )
  
  if tokens[0] != "move" or tokens[1] != "fleet" or tokens[3] != "to":
    return ParseResult(
      success: false,
      error: "Usage: :move fleet <id> to <system> [roe <value>]"
    )
  
  # Parse fleet ID
  var fleetId: int
  if parseInt(tokens[2], fleetId) == 0:
    return ParseResult(success: false, error: "Invalid fleet ID")
  
  # Parse system ID
  var systemId: int
  if parseInt(tokens[4], systemId) == 0:
    return ParseResult(success: false, error: "Invalid system ID")
  
  # Parse optional ROE
  var roe = none(int32)
  var priority = 1'i32
  
  var i = 5
  while i < tokens.len:
    if tokens[i] == "roe" and i + 1 < tokens.len:
      var roeVal: int
      if parseInt(tokens[i + 1], roeVal) > 0:
        if roeVal >= 0 and roeVal <= 10:
          roe = some(int32(roeVal))
        else:
          return ParseResult(success: false, error: "ROE must be 0-10")
      i += 2
    elif tokens[i] == "priority" and i + 1 < tokens.len:
      var priVal: int
      if parseInt(tokens[i + 1], priVal) > 0:
        priority = int32(priVal)
      i += 2
    else:
      i += 1
  
  let cmd = FleetCommand(
    fleetId: FleetId(fleetId),
    commandType: FleetCommandType.Move,
    targetSystem: some(SystemId(systemId)),
    targetFleet: none(FleetId),
    priority: priority,
    roe: roe
  )
  
  ParseResult(
    success: true,
    error: "",
    fleetCommand: some(cmd)
  )

proc parseFleetHold(tokens: seq[string]): ParseResult =
  ## Parse: hold fleet <id> [roe <value>]
  if tokens.len < 3:
    return ParseResult(
      success: false,
      error: "Usage: :hold fleet <id> [roe <value>]"
    )
  
  if tokens[0] != "hold" or tokens[1] != "fleet":
    return ParseResult(
      success: false,
      error: "Usage: :hold fleet <id> [roe <value>]"
    )
  
  # Parse fleet ID
  var fleetId: int
  if parseInt(tokens[2], fleetId) == 0:
    return ParseResult(success: false, error: "Invalid fleet ID")
  
  # Parse optional ROE
  var roe = none(int32)
  if tokens.len >= 5 and tokens[3] == "roe":
    var roeVal: int
    if parseInt(tokens[4], roeVal) > 0:
      if roeVal >= 0 and roeVal <= 10:
        roe = some(int32(roeVal))
      else:
        return ParseResult(success: false, error: "ROE must be 0-10")
  
  let cmd = FleetCommand(
    fleetId: FleetId(fleetId),
    commandType: FleetCommandType.Hold,
    targetSystem: none(SystemId),
    targetFleet: none(FleetId),
    priority: 1,
    roe: roe
  )
  
  ParseResult(
    success: true,
    error: "",
    fleetCommand: some(cmd)
  )

proc parseFleetSimple(tokens: seq[string], cmdType: FleetCommandType,
                      name: string): ParseResult =
  ## Parse simple fleet commands without targets
  if tokens.len < 3:
    return ParseResult(
      success: false,
      error: "Usage: :" & name & " fleet <id>"
    )

  if tokens[0] != name or tokens[1] != "fleet":
    return ParseResult(
      success: false,
      error: "Usage: :" & name & " fleet <id>"
    )

  var fleetId: int
  if parseInt(tokens[2], fleetId) == 0:
    return ParseResult(success: false, error: "Invalid fleet ID")

  let cmd = FleetCommand(
    fleetId: FleetId(fleetId),
    commandType: cmdType,
    targetSystem: none(SystemId),
    targetFleet: none(FleetId),
    priority: 1,
    roe: none(int32)
  )

  ParseResult(
    success: true,
    error: "",
    fleetCommand: some(cmd)
  )

proc parseFleetTargetSystem(tokens: seq[string], cmdType: FleetCommandType,
                            name: string): ParseResult =
  ## Parse fleet commands with system targets
  if tokens.len < 5:
    return ParseResult(
      success: false,
      error: "Usage: :" & name & " fleet <id> to <system> [roe <value>]"
    )

  if tokens[0] != name or tokens[1] != "fleet" or tokens[3] != "to":
    return ParseResult(
      success: false,
      error: "Usage: :" & name & " fleet <id> to <system> [roe <value>]"
    )

  var fleetId: int
  if parseInt(tokens[2], fleetId) == 0:
    return ParseResult(success: false, error: "Invalid fleet ID")

  var systemId: int
  if parseInt(tokens[4], systemId) == 0:
    return ParseResult(success: false, error: "Invalid system ID")

  var roe = none(int32)
  if tokens.len >= 7 and tokens[5] == "roe":
    var roeVal: int
    if parseInt(tokens[6], roeVal) > 0:
      if roeVal >= 0 and roeVal <= 10:
        roe = some(int32(roeVal))
      else:
        return ParseResult(success: false, error: "ROE must be 0-10")

  let cmd = FleetCommand(
    fleetId: FleetId(fleetId),
    commandType: cmdType,
    targetSystem: some(SystemId(systemId)),
    targetFleet: none(FleetId),
    priority: 1,
    roe: roe
  )

  ParseResult(
    success: true,
    error: "",
    fleetCommand: some(cmd)
  )

proc parseFleetPatrol(tokens: seq[string]): ParseResult =
  ## Parse: patrol fleet <id> [roe <value>]
  if tokens.len < 3:
    return ParseResult(
      success: false,
      error: "Usage: :patrol fleet <id> [roe <value>]"
    )
  
  if tokens[0] != "patrol" or tokens[1] != "fleet":
    return ParseResult(
      success: false,
      error: "Usage: :patrol fleet <id> [roe <value>]"
    )
  
  # Parse fleet ID
  var fleetId: int
  if parseInt(tokens[2], fleetId) == 0:
    return ParseResult(success: false, error: "Invalid fleet ID")
  
  # Parse optional ROE
  var roe = none(int32)
  if tokens.len >= 5 and tokens[3] == "roe":
    var roeVal: int
    if parseInt(tokens[4], roeVal) > 0:
      if roeVal >= 0 and roeVal <= 10:
        roe = some(int32(roeVal))
      else:
        return ParseResult(success: false, error: "ROE must be 0-10")
  
  let cmd = FleetCommand(
    fleetId: FleetId(fleetId),
    commandType: FleetCommandType.Patrol,
    targetSystem: none(SystemId),
    targetFleet: none(FleetId),
    priority: 1,
    roe: roe
  )
  
  ParseResult(
    success: true,
    error: "",
    fleetCommand: some(cmd)
  )

proc parseFleetJoinFleet(tokens: seq[string]): ParseResult =
  ## Parse: join fleet <id> to <fleet>
  if tokens.len < 5:
    return ParseResult(
      success: false,
      error: "Usage: :join fleet <id> to <fleet>"
    )

  if tokens[0] != "join" or tokens[1] != "fleet" or tokens[3] != "to":
    return ParseResult(
      success: false,
      error: "Usage: :join fleet <id> to <fleet>"
    )

  var fleetId: int
  if parseInt(tokens[2], fleetId) == 0:
    return ParseResult(success: false, error: "Invalid fleet ID")

  var targetId: int
  if parseInt(tokens[4], targetId) == 0:
    return ParseResult(success: false, error: "Invalid target fleet ID")

  let cmd = FleetCommand(
    fleetId: FleetId(fleetId),
    commandType: FleetCommandType.JoinFleet,
    targetSystem: none(SystemId),
    targetFleet: some(FleetId(targetId)),
    priority: 1,
    roe: none(int32)
  )

  ParseResult(
    success: true,
    error: "",
    fleetCommand: some(cmd)
  )

# =============================================================================
# Build Command Parsers
# =============================================================================

proc parseBuildShip(tokens: seq[string]): ParseResult =
  ## Parse: build colony <id> ship <class> [quantity <n>]
  if tokens.len < 5:
    return ParseResult(
      success: false,
      error: "Usage: :build colony <id> ship <class> [quantity <n>]"
    )
  
  if tokens[0] != "build" or tokens[1] != "colony" or tokens[3] != "ship":
    return ParseResult(
      success: false,
      error: "Usage: :build colony <id> ship <class> [quantity <n>]"
    )
  
  # Parse colony ID
  var colonyId: int
  if parseInt(tokens[2], colonyId) == 0:
    return ParseResult(success: false, error: "Invalid colony ID")
  
  # Parse ship class
  let shipClassOpt = parseShipClass(tokens[4])
  if shipClassOpt.isNone:
    return ParseResult(
      success: false,
      error: "Unknown ship class: " & tokens[4]
    )
  
  # Parse optional quantity
  var quantity = 1'i32
  if tokens.len >= 7 and tokens[5] == "quantity":
    var qtyVal: int
    if parseInt(tokens[6], qtyVal) > 0:
      quantity = int32(qtyVal)
  
  let cmd = BuildCommand(
    colonyId: ColonyId(colonyId),
    buildType: BuildType.Ship,
    quantity: quantity,
    shipClass: shipClassOpt,
    facilityClass: none(FacilityClass),
    groundClass: none(GroundClass),
    industrialUnits: 0
  )
  
  ParseResult(
    success: true,
    error: "",
    buildCommand: some(cmd)
  )

proc parseBuildFacility(tokens: seq[string]): ParseResult =
  ## Parse: build colony <id> facility <type>
  if tokens.len < 5:
    return ParseResult(
      success: false,
      error: "Usage: :build colony <id> facility <type>"
    )
  
  if tokens[0] != "build" or tokens[1] != "colony" or tokens[3] != "facility":
    return ParseResult(
      success: false,
      error: "Usage: :build colony <id> facility <type>"
    )
  
  # Parse colony ID
  var colonyId: int
  if parseInt(tokens[2], colonyId) == 0:
    return ParseResult(success: false, error: "Invalid colony ID")
  
  # Parse facility type - need to map NeoriaClass to FacilityClass
  let neoriaOpt = parseFacilityType(tokens[4])
  if neoriaOpt.isNone:
    return ParseResult(
      success: false,
      error: "Unknown facility type: " & tokens[4]
    )
  
  # Convert NeoriaClass to FacilityClass
  let facilityClass = case neoriaOpt.get()
    of NeoriaClass.Shipyard: FacilityClass.Shipyard
    of NeoriaClass.Spaceport: FacilityClass.Spaceport
    of NeoriaClass.Drydock: FacilityClass.Drydock
  
  let cmd = BuildCommand(
    colonyId: ColonyId(colonyId),
    buildType: BuildType.Facility,
    quantity: 1,
    shipClass: none(ShipClass),
    facilityClass: some(facilityClass),
    groundClass: none(GroundClass),
    industrialUnits: 0
  )
  
  ParseResult(
    success: true,
    error: "",
    buildCommand: some(cmd)
  )

# =============================================================================
# Main Parser
# =============================================================================

proc parseExpertCommand*(input: string): ParseResult =
  ## Parse expert mode command string
  ## Commands must start with : prefix
  
  # Remove leading/trailing whitespace
  let trimmed = input.strip()
  
  # Must start with :
  if not trimmed.startsWith(":"):
    return ParseResult(
      success: false,
      error: "Commands must start with :"
    )
  
  # Remove : prefix and tokenize
  let cmdStr = trimmed[1..^1].strip()
  if cmdStr.len == 0:
    return ParseResult(
      success: false,
      error: "Empty command"
    )
  
  var tokens = cmdStr.splitWhitespace()
  if tokens.len == 0:
    return ParseResult(
      success: false,
      error: "Empty command"
    )

  tokens[0] = normalizeCommandToken(tokens[0])
  
  # Route to appropriate parser based on first token
  case tokens[0].toLowerAscii()
  # Meta commands (no game state needed)
  of "help", "?":
    return ParseResult(
      success: true,
      error: "",
      metaCommand: MetaCommandType.Help
    )
  of "clear":
    return ParseResult(
      success: true,
      error: "",
      metaCommand: MetaCommandType.Clear
    )
  of "list", "show":
    return ParseResult(
      success: true,
      error: "",
      metaCommand: MetaCommandType.List
    )
  of "submit":
    return ParseResult(
      success: true,
      error: "",
      metaCommand: MetaCommandType.Submit
    )
  of "drop":
    if tokens.len < 2:
      return ParseResult(
        success: false,
        error: "Usage: :drop <index>"
      )
    var idx: int
    if parseInt(tokens[1], idx) == 0:
      return ParseResult(success: false, error: "Invalid index")
    return ParseResult(
      success: true,
      error: "",
      metaCommand: MetaCommandType.Drop,
      metaIndex: some(idx)
    )
  # Fleet commands
  of "move":
    parseFleetMove(tokens)
  of "hold":
    parseFleetHold(tokens)
  of "patrol":
    parseFleetPatrol(tokens)
  of "seek":
    parseFleetSimple(tokens, FleetCommandType.SeekHome, "seek")
  of "guard":
    parseFleetSimple(tokens, FleetCommandType.GuardColony, "guard")
  of "guard-starbase":
    parseFleetSimple(tokens, FleetCommandType.GuardStarbase, "guard-starbase")
  of "blockade":
    parseFleetTargetSystem(tokens, FleetCommandType.Blockade, "blockade")
  of "bombard":
    parseFleetTargetSystem(tokens, FleetCommandType.Bombard, "bombard")
  of "invade":
    parseFleetTargetSystem(tokens, FleetCommandType.Invade, "invade")
  of "blitz":
    parseFleetTargetSystem(tokens, FleetCommandType.Blitz, "blitz")
  of "colonize":
    parseFleetTargetSystem(tokens, FleetCommandType.Colonize, "colonize")
  of "scout-colony":
    parseFleetTargetSystem(tokens, FleetCommandType.ScoutColony, "scout-colony")
  of "scout-system":
    parseFleetTargetSystem(tokens, FleetCommandType.ScoutSystem, "scout-system")
  of "hack":
    parseFleetTargetSystem(tokens, FleetCommandType.HackStarbase, "hack")
  of "join":
    parseFleetJoinFleet(tokens)
  of "rendezvous":
    parseFleetTargetSystem(tokens, FleetCommandType.Rendezvous, "rendezvous")
  of "salvage":
    parseFleetSimple(tokens, FleetCommandType.Salvage, "salvage")
  of "reserve":
    parseFleetSimple(tokens, FleetCommandType.Reserve, "reserve")
  of "mothball":
    parseFleetSimple(tokens, FleetCommandType.Mothball, "mothball")
  of "view":
    parseFleetTargetSystem(tokens, FleetCommandType.View, "view")
  # Build commands
  of "build":
    if tokens.len >= 4 and tokens[3] == "ship":
      parseBuildShip(tokens)
    elif tokens.len >= 4 and tokens[3] == "facility":
      parseBuildFacility(tokens)
    else:
      ParseResult(
        success: false,
        error: "Usage: :build colony <id> ship/facility <type>",
        metaCommand: MetaCommandType.None
      )
  else:
    ParseResult(
      success: false,
      error: "Unknown command: " & tokens[0],
      metaCommand: MetaCommandType.None
    )
