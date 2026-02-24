## Expert Mode Autocomplete Engine
##
## Provides context-aware fuzzy matching for expert mode commands.

import std/[strutils, options, algorithm, tables]
import ../sam/expert_parser
import ../sam/tui_model
import ../../engine/types/core

type
  ExpertSuggestionType* {.pure.} = enum
    Category
    Action
    Target
    Argument

  ExpertSuggestion* = object
    text*: string
    hint*: string
    score*: int
    matchIndices*: seq[int]
    suggestionType*: ExpertSuggestionType

# --- Fuzzy Matching ---

proc fuzzyMatchIndices*(query: string, target: string): Option[tuple[score: int, indices: seq[int]]] =
  ## Fuzzy subsequence match (case-insensitive) with simple scoring
  let normalizedQuery = query.toLowerAscii()
  if normalizedQuery.len == 0:
    return some((score: 0, indices: newSeq[int]()))
    
  let normalizedTarget = target.toLowerAscii()
  var indices: seq[int] = @[]
  var lastIdx = -1
  var totalGap = 0
  
  for ch in normalizedQuery:
    var found = false
    for i in (lastIdx + 1) ..< normalizedTarget.len:
      if normalizedTarget[i] == ch:
        indices.add(i)
        if lastIdx >= 0:
          totalGap += i - lastIdx - 1
        lastIdx = i
        found = true
        break
    if not found:
      return none(tuple[score: int, indices: seq[int]])
      
  let firstIdx = indices[0]
  let score = 1000 - (totalGap * 5) - firstIdx
  some((score: score, indices: indices))

# --- Suggestions ---

proc suggest(query: string, items: seq[tuple[text: string, hint: string]], sType: ExpertSuggestionType): seq[ExpertSuggestion] =
  result = @[]
  for item in items:
    if query.len == 0:
      result.add(ExpertSuggestion(text: item.text, hint: item.hint, score: 0, matchIndices: @[], suggestionType: sType))
      continue
      
    let matchOpt = fuzzyMatchIndices(query, item.text)
    if matchOpt.isSome:
      let match = matchOpt.get()
      result.add(ExpertSuggestion(
        text: item.text,
        hint: item.hint,
        score: match.score,
        matchIndices: match.indices,
        suggestionType: sType
      ))
      
  result.sort(proc(a, b: ExpertSuggestion): int =
    if a.score == b.score:
      cmp(a.text, b.text)
    else:
      cmp(b.score, a.score)
  )

proc suggestCategories(query: string): seq[ExpertSuggestion] =
  let categories = @[
    (text: "fleet", hint: "Fleet operations"),
    (text: "colony", hint: "Colony management"),
    (text: "tech", hint: "Research & Development"),
    (text: "spy", hint: "Espionage"),
    (text: "gov", hint: "Government & Diplomacy"),
    (text: "map", hint: "Starmap utilities"),
    (text: "clear", hint: "Clear staged commands"),
    (text: "list", hint: "List staged commands"),
    (text: "drop", hint: "Drop staged command"),
    (text: "submit", hint: "Submit turn")
  ]
  suggest(query, categories, ExpertSuggestionType.Category)

proc suggestFleetTargets(model: TuiModel, query: string): seq[ExpertSuggestion] =
  var targets: seq[tuple[text: string, hint: string]] = @[]
  for fleet in model.view.fleets:
    if fleet.owner == model.view.viewingHouse:
      let name = if fleet.name.contains(" "): """ & fleet.name & """ else: fleet.name
      targets.add((text: name, hint: fleet.locationName))
  suggest(query, targets, ExpertSuggestionType.Target)

proc suggestColonyTargets(model: TuiModel, query: string): seq[ExpertSuggestion] =
  var targets: seq[tuple[text: string, hint: string]] = @[]
  for colony in model.view.colonies:
    if colony.owner == model.view.viewingHouse:
      let name = if colony.systemName.contains(" "): """ & colony.systemName & """ else: colony.systemName
      targets.add((text: name, hint: "Pop: " & $colony.populationUnits))
  suggest(query, targets, ExpertSuggestionType.Target)

proc suggestFleetActions(query: string): seq[ExpertSuggestion] =
  let actions = @[
    (text: "move", hint: "Move to system"),
    (text: "hold", hint: "Hold position"),
    (text: "roe", hint: "Set Rules of Engagement"),
    (text: "split", hint: "Detach ships"),
    (text: "merge", hint: "Merge into fleet"),
    (text: "load", hint: "Load cargo/troops"),
    (text: "status", hint: "Set reserve/mothball")
  ]
  suggest(query, actions, ExpertSuggestionType.Action)

proc suggestColonyActions(query: string): seq[ExpertSuggestion] =
  let actions = @[
    (text: "build", hint: "Build ship/facility"),
    (text: "qrm", hint: "Remove from queue"),
    (text: "qup", hint: "Move up in queue"),
    (text: "auto", hint: "Set automation")
  ]
  suggest(query, actions, ExpertSuggestionType.Action)

proc suggestTechTargets(query: string): seq[ExpertSuggestion] =
  let targets = @[
    (text: "wep", hint: "Weapons Tech"),
    (text: "cst", hint: "Construction Tech"),
    (text: "fc", hint: "Fleet Command"),
    (text: "sc", hint: "Strategic Cmd"),
    (text: "fd", hint: "Fighter Doctrine"),
    (text: "aco", hint: "Carrier Ops"),
    (text: "sld", hint: "Shields"),
    (text: "clk", hint: "Cloaking"),
    (text: "eli", hint: "Electronic Int"),
    (text: "ter", hint: "Terraforming"),
    (text: "stl", hint: "Strategic Lift"),
    (text: "cic", hint: "Counter Intel"),
    (text: "eco", hint: "Economic Level"),
    (text: "sci", hint: "Science Level"),
    (text: "clear", hint: "Clear allocations")
  ]
  suggest(query, targets, ExpertSuggestionType.Target)

proc suggestTechActions(query: string): seq[ExpertSuggestion] =
  let actions = @[
    (text: "alloc", hint: "Allocate PP")
  ]
  suggest(query, actions, ExpertSuggestionType.Action)

proc suggestSpyTargets(model: TuiModel, query: string): seq[ExpertSuggestion] =
  var targets: seq[tuple[text: string, hint: string]] = @[
    (text: "ebp", hint: "Espionage Budget"),
    (text: "cip", hint: "Counter-Intel Budget"),
    (text: "clear", hint: "Clear spy commands")
  ]
  for id, name in model.view.houseNames.pairs:
    if id > 0 and id != model.view.viewingHouse:
      let houseName = if name.contains(" "): """ & name & """ else: name
      targets.add((text: houseName, hint: "House Target"))
  suggest(query, targets, ExpertSuggestionType.Target)

proc suggestSpyActions(query: string): seq[ExpertSuggestion] =
  let actions = @[
    (text: "budget", hint: "Set budget"),
    (text: "op", hint: "Launch operation")
  ]
  suggest(query, actions, ExpertSuggestionType.Action)

proc suggestGovTargets(model: TuiModel, query: string): seq[ExpertSuggestion] =
  var targets: seq[tuple[text: string, hint: string]] = @[
    (text: "empire", hint: "Empire policies")
  ]
  for id, name in model.view.houseNames.pairs:
    if id > 0 and id != model.view.viewingHouse:
      let houseName = if name.contains(" "): """ & name & """ else: name
      targets.add((text: houseName, hint: "House Target"))
  suggest(query, targets, ExpertSuggestionType.Target)

proc suggestGovActions(target: string, query: string): seq[ExpertSuggestion] =
  var actions: seq[tuple[text: string, hint: string]] = @[]
  if target == "empire":
    actions.add((text: "tax", hint: "Set tax rate"))
  else:
    actions.add((text: "dip", hint: "Set diplomatic stance"))
  suggest(query, actions, ExpertSuggestionType.Action)

proc suggestMapTargets(model: TuiModel, query: string): seq[ExpertSuggestion] =
  var targets: seq[tuple[text: string, hint: string]] = @[
    (text: "export", hint: "Export starmap")
  ]
  for coord, sys in model.view.systems.pairs:
    let name = if sys.name.contains(" "): """ & sys.name & """ else: sys.name
    targets.add((text: name, hint: "System"))
  suggest(query, targets, ExpertSuggestionType.Target)

proc suggestMapActions(query: string): seq[ExpertSuggestion] =
  let actions = @[
    (text: "note", hint: "Add intel note")
  ]
  suggest(query, actions, ExpertSuggestionType.Action)

proc suggestSystemArguments(model: TuiModel, query: string): seq[ExpertSuggestion] =
  var systems: seq[tuple[text: string, hint: string]] = @[]
  for coord, sys in model.view.systems.pairs:
    let name = if sys.name.contains(" "): """ & sys.name & """ else: sys.name
    systems.add((text: name, hint: "System"))
  suggest(query, systems, ExpertSuggestionType.Argument)

proc getAutocompleteSuggestions*(model: TuiModel, input: string): seq[ExpertSuggestion] =
  ## Main entry point for expert mode autocomplete
  let tokens = tokenize(input)
  let rawStr = input.strip(leading = false)
  let hasTrailingSpace = rawStr.len > 0 and rawStr[^1] == ' '
  
  if tokens.len == 0 or (tokens.len == 1 and not hasTrailingSpace):
    let query = if tokens.len == 1: tokens[0] else: ""
    return suggestCategories(query)
    
  let catStr = tokens[0]
  let isCategoryComplete = tokens.len > 1 or hasTrailingSpace
  
  if isCategoryComplete:
    let category = case catStr.toLowerAscii()
      of "fleet", "f": ExpertCategory.Fleet
      of "colony", "c": ExpertCategory.Colony
      of "tech", "t": ExpertCategory.Tech
      of "spy", "s": ExpertCategory.Spy
      of "gov", "g": ExpertCategory.Gov
      of "map", "m": ExpertCategory.Map
      else: ExpertCategory.Unknown
      
    if category == ExpertCategory.Unknown:
      return @[]
      
    let targetIdx = 1
    let actionIdx = 2
    let argIdx = 3
    
    # Typing Target
    if tokens.len == targetIdx + 1 and not hasTrailingSpace:
      let query = tokens[targetIdx]
      case category
      of ExpertCategory.Fleet: return suggestFleetTargets(model, query)
      of ExpertCategory.Colony: return suggestColonyTargets(model, query)
      of ExpertCategory.Tech: return suggestTechTargets(query)
      of ExpertCategory.Spy: return suggestSpyTargets(model, query)
      of ExpertCategory.Gov: return suggestGovTargets(model, query)
      of ExpertCategory.Map: return suggestMapTargets(model, query)
      else: return @[]
      
    # Empty Target
    if tokens.len == targetIdx and hasTrailingSpace:
      case category
      of ExpertCategory.Fleet: return suggestFleetTargets(model, "")
      of ExpertCategory.Colony: return suggestColonyTargets(model, "")
      of ExpertCategory.Tech: return suggestTechTargets("")
      of ExpertCategory.Spy: return suggestSpyTargets(model, "")
      of ExpertCategory.Gov: return suggestGovTargets(model, "")
      of ExpertCategory.Map: return suggestMapTargets(model, "")
      else: return @[]
      
    # Typing Action
    if tokens.len == actionIdx + 1 and not hasTrailingSpace:
      let target = tokens[targetIdx].toLowerAscii()
      if target == "clear" or target == "export": return @[] # Terminal targets
      let query = tokens[actionIdx]
      case category
      of ExpertCategory.Fleet: return suggestFleetActions(query)
      of ExpertCategory.Colony: return suggestColonyActions(query)
      of ExpertCategory.Tech: return suggestTechActions(query)
      of ExpertCategory.Spy: return suggestSpyActions(query)
      of ExpertCategory.Gov: return suggestGovActions(tokens[targetIdx].toLowerAscii(), query)
      of ExpertCategory.Map: return suggestMapActions(query)
      else: return @[]
      
    # Empty Action
    if tokens.len == actionIdx and hasTrailingSpace:
      let target = tokens[targetIdx].toLowerAscii()
      if target == "clear" or target == "export": return @[]
      case category
      of ExpertCategory.Fleet: return suggestFleetActions("")
      of ExpertCategory.Colony: return suggestColonyActions("")
      of ExpertCategory.Tech: return suggestTechActions("")
      of ExpertCategory.Spy: return suggestSpyActions("")
      of ExpertCategory.Gov: return suggestGovActions(tokens[targetIdx].toLowerAscii(), "")
      of ExpertCategory.Map: return suggestMapActions("")
      else: return @[]
      
    # Typing Arguments (Depth 3+)
    if tokens.len >= argIdx:
      let action = tokens[actionIdx].toLowerAscii()
      let query = if hasTrailingSpace: "" else: tokens[^1]
      
      case category
      of ExpertCategory.Fleet:
        if action == "move":
          # :f <fleet> move <system>
          if tokens.len == argIdx + 1 and not hasTrailingSpace or (tokens.len == argIdx and hasTrailingSpace):
            return suggestSystemArguments(model, query)
      else:
        discard
        
  return @[]
