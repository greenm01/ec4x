## Expert Mode Parser
##
## Parses a text command into a strongly-typed AST for the SAM acceptor.
##
## Syntax: :[category] [target] [action] [arguments...]

import std/[strutils, parseutils]

# --- AST Definitions ---

type
  ExpertCategory* {.pure.} = enum
    Fleet
    Colony
    Tech
    Spy
    Gov
    Map
    Meta
    Unknown

  ExpertCommandKind* {.pure.} = enum
    # Fleet
    FleetMove
    FleetHold
    FleetRoe
    FleetSplit
    FleetMerge
    FleetLoad
    FleetStatus
    # Colony
    ColonyBuild
    ColonyQrm
    ColonyQup
    ColonyAuto
    # Tech
    TechAlloc
    TechClear
    # Spy
    SpyBudget
    SpyOp
    SpyClear
    # Gov
    GovTax
    GovDip
    # Map
    MapNote
    MapExport
    # Meta
    MetaClear
    MetaList
    MetaDrop
    MetaSubmit
    MetaHelp
    # Error
    ParseError

  ExpertCommand* = object
    case kind*: ExpertCommandKind
    of FleetMove:
      fleetId*: string
      targetSystem*: string
    of FleetHold:
      holdFleetId*: string
    of FleetRoe:
      roeFleetId*: string
      roeLevel*: int
    of FleetSplit:
      splitFleetId*: string
      splitQty*: int
      splitClass*: string
    of FleetMerge:
      mergeSource*: string
      mergeTarget*: string
    of FleetLoad:
      loadFleetId*: string
      loadQty*: int
      loadCargo*: string
    of FleetStatus:
      statusFleetId*: string
      statusState*: string
    of ColonyBuild:
      buildColony*: string
      buildQty*: int
      buildItem*: string
    of ColonyQrm:
      qrmColony*: string
      qrmIndex*: int
    of ColonyQup:
      qupColony*: string
      qupIndex*: int
    of ColonyAuto:
      autoColony*: string
      autoSystem*: string
      autoState*: string
    of TechAlloc:
      allocField*: string
      allocAmount*: int
    of TechClear:
      discard
    of SpyBudget:
      budgetType*: string
      budgetAmount*: int
    of SpyOp:
      opHouse*: string
      opType*: string
    of SpyClear:
      discard
    of GovTax:
      taxRate*: int
    of GovDip:
      dipHouse*: string
      dipStance*: string
    of MapNote:
      noteSystem*: string
      noteText*: string
    of MapExport:
      discard
    of MetaClear, MetaList, MetaSubmit, MetaHelp:
      discard
    of MetaDrop:
      dropIndex*: int
    of ParseError:
      errorMessage*: string

# --- Tokenizer ---

proc tokenize*(input: string): seq[string] =
  ## Split input by spaces, respecting double-quoted strings
  result = @[]
  var current = ""
  var inQuotes = false
  var i = 0
  let s = input.strip()
  
  if s.len == 0: return result
  # skip leading colon if present
  let startIdx = if s[0] == ':': 1 else: 0

  while i < s.len:
    if i == 0 and startIdx == 1:
      i += 1
      continue

    let c = s[i]
    if c == '"':
      inQuotes = not inQuotes
      # don't add the quote char to the token
    elif c == ' ' and not inQuotes:
      if current.len > 0:
        result.add(current)
        current = ""
    else:
      current.add(c)
    i += 1
    
  if current.len > 0:
    result.add(current)

# --- Parser ---

proc parseCategory(tok: string): ExpertCategory =
  case tok.toLowerAscii()
  of "fleet", "f": ExpertCategory.Fleet
  of "colony", "c": ExpertCategory.Colony
  of "tech", "t": ExpertCategory.Tech
  of "spy", "s": ExpertCategory.Spy
  of "gov", "g": ExpertCategory.Gov
  of "map", "m": ExpertCategory.Map
  of "clear", "list", "ls", "drop", "rm", "submit", "help", "?": ExpertCategory.Meta
  else: ExpertCategory.Unknown

proc parseFleetCommand(tokens: seq[string]): ExpertCommand =
  if tokens.len < 2:
    return ExpertCommand(kind: ParseError, errorMessage: "Fleet commands require a target fleet")
  
  let fleetId = tokens[0]
  let action = tokens[1].toLowerAscii()
  
  case action
  of "hold":
    return ExpertCommand(kind: FleetHold, holdFleetId: fleetId)
  of "move":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Move requires a target system")
    return ExpertCommand(kind: FleetMove, fleetId: fleetId, targetSystem: tokens[2])
  of "roe":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "ROE requires a level (1-10)")
    var level: int
    if parseInt(tokens[2], level) == 0 and tokens[2] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid ROE level")
    return ExpertCommand(kind: FleetRoe, roeFleetId: fleetId, roeLevel: level)
  of "split":
    if tokens.len < 4: return ExpertCommand(kind: ParseError, errorMessage: "Split requires qty and class")
    var qty: int
    if parseInt(tokens[2], qty) == 0 and tokens[2] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid split quantity")
    return ExpertCommand(kind: FleetSplit, splitFleetId: fleetId, splitQty: qty, splitClass: tokens[3])
  of "merge":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Merge requires a target fleet")
    return ExpertCommand(kind: FleetMerge, mergeSource: fleetId, mergeTarget: tokens[2])
  of "load":
    if tokens.len < 4: return ExpertCommand(kind: ParseError, errorMessage: "Load requires qty and cargo type")
    var qty: int
    if parseInt(tokens[2], qty) == 0 and tokens[2] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid load quantity")
    return ExpertCommand(kind: FleetLoad, loadFleetId: fleetId, loadQty: qty, loadCargo: tokens[3])
  of "status":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Status requires a state (e.g. reserve, mothball)")
    return ExpertCommand(kind: FleetStatus, statusFleetId: fleetId, statusState: tokens[2])
  else:
    return ExpertCommand(kind: ParseError, errorMessage: "Unknown fleet action: " & action)

proc parseColonyCommand(tokens: seq[string]): ExpertCommand =
  if tokens.len < 2:
    return ExpertCommand(kind: ParseError, errorMessage: "Colony commands require a target colony")
  
  let colonyId = tokens[0]
  let action = tokens[1].toLowerAscii()
  
  case action
  of "build":
    if tokens.len < 4: return ExpertCommand(kind: ParseError, errorMessage: "Build requires qty and item")
    var qty: int
    if parseInt(tokens[2], qty) == 0 and tokens[2] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid build quantity")
    return ExpertCommand(kind: ColonyBuild, buildColony: colonyId, buildQty: qty, buildItem: tokens[3])
  of "qrm":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Qrm requires a queue index")
    var idx: int
    if parseInt(tokens[2], idx) == 0 and tokens[2] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid queue index")
    return ExpertCommand(kind: ColonyQrm, qrmColony: colonyId, qrmIndex: idx)
  of "qup":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Qup requires a queue index")
    var idx: int
    if parseInt(tokens[2], idx) == 0 and tokens[2] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid queue index")
    return ExpertCommand(kind: ColonyQup, qupColony: colonyId, qupIndex: idx)
  of "auto":
    if tokens.len < 4: return ExpertCommand(kind: ParseError, errorMessage: "Auto requires system (rep/mar/fig) and state (on/off)")
    return ExpertCommand(kind: ColonyAuto, autoColony: colonyId, autoSystem: tokens[2], autoState: tokens[3])
  else:
    return ExpertCommand(kind: ParseError, errorMessage: "Unknown colony action: " & action)

proc parseTechCommand(tokens: seq[string]): ExpertCommand =
  if tokens.len == 0:
    return ExpertCommand(kind: ParseError, errorMessage: "Tech command missing target/action")
  
  if tokens[0].toLowerAscii() == "clear":
    return ExpertCommand(kind: TechClear)
  
  if tokens.len < 2:
    return ExpertCommand(kind: ParseError, errorMessage: "Tech command requires an action")
    
  let target = tokens[0]
  let action = tokens[1].toLowerAscii()
  
  case action
  of "alloc":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Alloc requires an amount")
    var amount: int
    if parseInt(tokens[2], amount) == 0 and tokens[2] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid allocation amount")
    return ExpertCommand(kind: TechAlloc, allocField: target, allocAmount: amount)
  else:
    return ExpertCommand(kind: ParseError, errorMessage: "Unknown tech action: " & action)

proc parseSpyCommand(tokens: seq[string]): ExpertCommand =
  if tokens.len == 0:
    return ExpertCommand(kind: ParseError, errorMessage: "Spy command missing target/action")

  if tokens[0].toLowerAscii() == "clear":
    return ExpertCommand(kind: SpyClear)
    
  if tokens.len < 2:
    return ExpertCommand(kind: ParseError, errorMessage: "Spy command requires an action")
    
  let target = tokens[0]
  let action = tokens[1].toLowerAscii()
  
  case action
  of "budget":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Budget requires an amount")
    var amount: int
    if parseInt(tokens[2], amount) == 0 and tokens[2] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid budget amount")
    return ExpertCommand(kind: SpyBudget, budgetType: target, budgetAmount: amount)
  of "op":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Op requires an operation type")
    return ExpertCommand(kind: SpyOp, opHouse: target, opType: tokens[2])
  else:
    return ExpertCommand(kind: ParseError, errorMessage: "Unknown spy action: " & action)

proc parseGovCommand(tokens: seq[string]): ExpertCommand =
  if tokens.len < 2:
    return ExpertCommand(kind: ParseError, errorMessage: "Gov command missing target/action")
    
  let target = tokens[0].toLowerAscii()
  let action = tokens[1].toLowerAscii()
  
  if target == "empire" and action == "tax":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Tax requires a rate (0-100)")
    var rate: int
    if parseInt(tokens[2], rate) == 0 and tokens[2] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid tax rate")
    return ExpertCommand(kind: GovTax, taxRate: rate)
  
  if action == "dip":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Dip requires a stance")
    return ExpertCommand(kind: GovDip, dipHouse: target, dipStance: tokens[2])
    
  return ExpertCommand(kind: ParseError, errorMessage: "Unknown gov action: " & action)

proc parseMapCommand(tokens: seq[string]): ExpertCommand =
  if tokens.len == 0:
    return ExpertCommand(kind: ParseError, errorMessage: "Map command missing target/action")
    
  if tokens[0].toLowerAscii() == "export":
    return ExpertCommand(kind: MapExport)
    
  if tokens.len < 2:
    return ExpertCommand(kind: ParseError, errorMessage: "Map command requires an action")
    
  let target = tokens[0]
  let action = tokens[1].toLowerAscii()
  
  case action
  of "note":
    if tokens.len < 3: return ExpertCommand(kind: ParseError, errorMessage: "Note requires text")
    return ExpertCommand(kind: MapNote, noteSystem: target, noteText: tokens[2])
  else:
    return ExpertCommand(kind: ParseError, errorMessage: "Unknown map action: " & action)

proc parseMetaCommand(tokens: seq[string]): ExpertCommand =
  let action = tokens[0].toLowerAscii()
  case action
  of "help", "?": return ExpertCommand(kind: MetaHelp)
  of "clear": return ExpertCommand(kind: MetaClear)
  of "list", "ls": return ExpertCommand(kind: MetaList)
  of "submit": return ExpertCommand(kind: MetaSubmit)
  of "drop", "rm":
    if tokens.len < 2: return ExpertCommand(kind: ParseError, errorMessage: "Drop requires an index")
    var idx: int
    if parseInt(tokens[1], idx) == 0 and tokens[1] != "0": return ExpertCommand(kind: ParseError, errorMessage: "Invalid index")
    return ExpertCommand(kind: MetaDrop, dropIndex: idx)
  else: return ExpertCommand(kind: ParseError, errorMessage: "Unknown meta action")

proc parseExpertCommand*(input: string): ExpertCommand =
  ## Parses a raw input string into an AST
  let tokens = tokenize(input)
  if tokens.len == 0:
    return ExpertCommand(kind: ParseError, errorMessage: "Empty command")
    
  let cat = parseCategory(tokens[0])
  if cat == ExpertCategory.Unknown:
    return ExpertCommand(kind: ParseError, errorMessage: "Unknown category: " & tokens[0])
    
  if cat == ExpertCategory.Meta:
    return parseMetaCommand(tokens)
    
  let args = tokens[1..^1]
  
  case cat
  of ExpertCategory.Fleet: return parseFleetCommand(args)
  of ExpertCategory.Colony: return parseColonyCommand(args)
  of ExpertCategory.Tech: return parseTechCommand(args)
  of ExpertCategory.Spy: return parseSpyCommand(args)
  of ExpertCategory.Gov: return parseGovCommand(args)
  of ExpertCategory.Map: return parseMapCommand(args)
  of ExpertCategory.Meta, ExpertCategory.Unknown: discard # Unreachable
